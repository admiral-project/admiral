#!/usr/bin/env bash
# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- helpers ---
die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
require_option_value() {
    local opt="$1"
    local val="${2-}"
    [[ -n "$val" && "$val" != --* ]] || die "$opt requires a value."
}
read_public_key_file() {
    local key_file="$1"
    python3 - "$key_file" <<'PY'
import re
import subprocess
import sys

key_types = re.compile(
    r"^(?:ssh-(?:ed25519|rsa)|ecdsa-sha2-nistp(?:256|384|521)|"
    r"sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)$"
)
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        lines = stream.readlines()
except OSError:
    raise SystemExit(1)

for raw in lines:
    fields = raw.strip().split()
    for index, field in enumerate(fields[:-1]):
        if not key_types.fullmatch(field):
            continue
        candidate = " ".join(fields[index:])
        result = subprocess.run(
            ["ssh-keygen", "-lf", "-"],
            input=candidate + "\n",
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            print(candidate)
            raise SystemExit(0)
raise SystemExit(1)
PY
}
read_invoking_user_public_key() {
    local invoking_user="${SUDO_USER-}"
    local invoking_uid="${SUDO_UID-}"
    local actual_uid=""
    local invoking_home=""

    [[ -n "$invoking_user" && "$invoking_user" != "root" ]] || return 1
    [[ "$invoking_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$invoking_uid" =~ ^[0-9]+$ ]] || return 1
    actual_uid=$(id -u "$invoking_user" 2>/dev/null) || return 1
    [[ "$actual_uid" == "$invoking_uid" ]] || return 1
    invoking_home=$(getent passwd "$invoking_user" | cut -d: -f6)
    [[ -n "$invoking_home" ]] || return 1
    read_public_key_file "$invoking_home/.ssh/authorized_keys"
}
is_loopback_host() {
    case "$1" in
        ""|localhost|::1)
            return 0
            ;;
    esac
    if [[ "$1" =~ ^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}
# Read a single key from the secrets file safely (no shell evaluation).
# Usage: value=$(read_admiral_secret "KEY_NAME")
read_admiral_secret() {
    local key="$1"
    local file="/etc/admiral/secrets"
    [[ -f "$file" ]] || { echo ""; return 1; }
    grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}
read_install_state_value() {
    local key="$1"
    local file="/etc/admiral/install.env"
    [[ -f "$file" ]] || return 1
    python3 - "$file" "$key" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        state = json.load(stream)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
value = state.get(sys.argv[2])
if not isinstance(value, str) or not value:
    raise SystemExit(1)
print(value)
PY
}
expected_node_role() {
    case "$1" in
        single-node) printf '%s\n' 'single' ;;
        admin-node) printf '%s\n' 'admin' ;;
        admin-portal-node) printf '%s\n' 'admin-portal' ;;
        worker-node) printf '%s\n' 'worker' ;;
        portal-node) printf '%s\n' 'portal' ;;
        *) return 1 ;;
    esac
}
validate_node_role() {
    local persisted_role="$1"
    local requested_role="$2"
    local target="$3"

    case "$persisted_role" in
        "$requested_role") return 0 ;;
        dev)
            [[ "$requested_role" == "single" ]] && return 0
            ;;
        admin|admin-portal|worker|portal|single) ;;
        *) die "$target has an invalid Admiral role '$persisted_role'. Refusing to modify the host." ;;
    esac
    die "$target is provisioned as '$persisted_role' and cannot be provisioned as '$requested_role'. Refusing to modify the host."
}
preflight_local_node_role() {
    local requested_role="$1"
    local persisted_role=""
    local legacy_path=""

    if [[ -f /etc/admiral/role ]]; then
        IFS= read -r persisted_role < /etc/admiral/role || true
        validate_node_role "$persisted_role" "$requested_role" "This host"
        return
    fi
    # The RPM installs baseline configuration files before the first run.
    # Treat that package-only state as new; secrets mark a real installation.
    if command -v rpm >/dev/null 2>&1 && rpm -q admiral-common >/dev/null 2>&1 &&
        [[ ! -e /etc/admiral/secrets ]]; then
        return
    fi
    for legacy_path in /etc/admiral/secrets /etc/admiral/harbor.env /etc/admiral/fleet.env /etc/admirald.ini; do
        [[ ! -e "$legacy_path" ]] || die "This host has an unprofiled Admiral installation. Refusing to modify packages or repositories."
    done
}
preflight_remote_node_role() {
    local requested_role="$1"
    local probe_command=""
    local quoted_probe=""
    local persisted_role=""

    probe_command='if [ -f /etc/admiral/role ]; then tr -d "\r\n" < /etc/admiral/role; elif rpm -q admiral-common >/dev/null 2>&1 && [ ! -e /etc/admiral/secrets ]; then printf %s __ADMIRAL_NEW__; elif [ -e /etc/admiral/secrets ] || [ -e /etc/admiral/harbor.env ] || [ -e /etc/admiral/fleet.env ] || [ -e /etc/admirald.ini ]; then printf %s __ADMIRAL_LEGACY__; else printf %s __ADMIRAL_NEW__; fi'
    printf -v quoted_probe '%q' "$probe_command"
    if [[ "$INSTALL_TARGET_SSH_USER" == "root" ]]; then
        persisted_role=$(ssh "${SSH_OPTIONS[@]}" "root@${INSTALL_PUBLIC_IP}" "bash -lc $quoted_probe") ||
            die "Could not inspect the existing Admiral role on $INSTALL_PUBLIC_IP. Refusing remote changes."
    else
        persisted_role=$(ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo -n bash -lc $quoted_probe") ||
            die "Could not inspect the existing Admiral role on $INSTALL_PUBLIC_IP. Refusing remote changes."
    fi
    case "$persisted_role" in
        __ADMIRAL_NEW__) return ;;
        __ADMIRAL_LEGACY__)
            die "Remote host $INSTALL_PUBLIC_IP has an unprofiled Admiral installation. Refusing to modify packages or repositories."
            ;;
    esac
    validate_node_role "$persisted_role" "$requested_role" "Remote host $INSTALL_PUBLIC_IP"
}
require_firewall_services() {
    local actual="$1"
    shift
    local service
    for service in "$@"; do
        [[ " $actual " == *" $service "* ]] || {
            warn "Missing firewall service: $service"
            return 1
        }
    done
}
expected_public_listeners() {
    local listeners=""
    case "$1" in
        single-node) listeners=$'tcp/22\ntcp/80\ntcp/443\nudp/443' ;;
        admin-node|admin-portal-node) listeners=$'tcp/22\ntcp/80\ntcp/443\nudp/443\nudp/51820' ;;
        worker-node|portal-node) listeners=$'tcp/22\nudp/51820' ;;
    esac
    printf '%s\n' "$listeners" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}
require_exact_public_listeners() {
    local actual="$1" expected="$2"
    [[ "$actual" == "$expected" ]] || {
        warn "Unexpected public listeners: expected '$expected', found '$actual'"
        return 1
    }
}
expected_firewall_ports() {
    case "$1" in
        admin-node|admin-portal-node|worker-node|portal-node) printf '%s\n' '51820/udp' ;;
        single-node) printf '%s\n' ;;
    esac
}
usage() {
    cat <<'EOF'
Usage:
  admiral-install --single-node [--public-ip <public-ip>]
  admiral-install --dev-node [--public-ip <public-ip>]
  admiral-install --admin-node [--public-ip <public-ip>]
  admiral-install --admin-portal-node [--public-ip <public-ip>]
  admiral-install --worker-node --public-ip <public-ip> [--wireguard-ip <wireguard-ip>]
  admiral-install --portal-node --public-ip <public-ip> [--wireguard-ip <wireguard-ip>]

Options:
  --single-node       Install all single-node components on one host.
  --dev-node          Evaluation mode: single-node with relaxed firewall/bindings.
  --admin-node        Install control plane components only.
  --admin-portal-node Install control plane and Harbor on one host.
  --worker-node       Install worker components only.
  --portal-node       Install portal components only.
  --node-id           Set a custom node ID (default: hostname).
  --public-ip         Set the public IP address of the node being configured.
  --wireguard-ip      Set the WireGuard IP address for a spoke node.
  --admin-endpoint    Override the admin endpoint for spoke installs.
  --ssh-user          SSH user for remote spoke configuration (default: root for bootstrap).
  --ssh-key           SSH private key for remote spoke configuration.
  --ssh-public-key    Public key to authorize for the generated administrator.
  --ssh-fingerprint   Expected SSH host key fingerprint (SHA256:...) for verification.
  --s3-credentials-file  File containing ADMIRAL_S3_ACCESS_KEY_ID and ADMIRAL_S3_SECRET_ACCESS_KEY.
  --yes               Confirm non-interactive dangerous operations such as --dev-node.
  --no-revoke-ssh-key Do not revoke the bootstrap SSH key after spoke onboarding.
  -h, --help          Show this help message.

Note: --worker-node and --portal-node are mutually exclusive by design.
      A single host cannot run both roles. Deploy separate nodes if both
      worker and portal capabilities are required.
EOF
}

INSTALL_MODE=""
INSTALL_DEV_MODE="false"
INSTALL_NODE_ID=""
INSTALL_PUBLIC_IP=""
INSTALL_WIREGUARD_IP=""
INSTALL_ADMIN_ENDPOINT=""
INSTALL_TARGET_SSH_USER="root"
INSTALL_TARGET_SSH_USER_EXPLICIT="false"
INSTALL_TARGET_SSH_KEY=""
INSTALL_SSH_PUBLIC_KEY_FILE=""
INSTALL_SSH_FINGERPRINT=""
BOOTSTRAP_SSH_PUB_KEY=""
BOOTSTRAP_SSH_USER=""
INSTALL_RECONVERGE_SSH_KEY="false"
ADMIN_SSH_DELIVERY_KEY=""
INSTALL_S3_CREDENTIALS_FILE=""
INSTALL_NO_REVOKE_SSH_KEY="false"
INSTALL_YES="false"
INSTALLER_TEMP_BASE=""
EXTRA_VARS_FILE=""
TMP_INVENTORY=""
TMP_KNOWN_HOSTS=""
SSH_OPTIONS=()

cleanup_installer_temps() {
    [[ -z "$TMP_INVENTORY" ]] || rm -f -- "$TMP_INVENTORY"
    [[ -z "$TMP_KNOWN_HOSTS" ]] || rm -f -- "$TMP_KNOWN_HOSTS"
    [[ -z "$EXTRA_VARS_FILE" ]] || rm -f -- "$EXTRA_VARS_FILE"
    [[ -z "$INSTALLER_TEMP_BASE" ]] || rm -rf -- "$INSTALLER_TEMP_BASE"
}
trap cleanup_installer_temps EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

while [[ $# -gt 0 ]]; do
    case "$1" in
        --single-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="single-node"
            ;;
        --dev-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="single-node"
            INSTALL_DEV_MODE="true"
            warn "----------------------------------------------------------------"
            warn "WARNING: --dev-node is INSECURE."
            warn "It exposes WSGI servers (Harbor and Flagship) directly to the internet."
            warn "ONLY use for development/evaluation."
            warn "----------------------------------------------------------------"
            ;;
        --admin-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="admin-node"
            ;;
        --admin-portal-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="admin-portal-node"
            ;;
        --worker-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="worker-node"
            ;;
        --portal-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="portal-node"
            ;;
        --node-id)
            shift
            require_option_value "--node-id" "${1-}"
            INSTALL_NODE_ID="$1"
            ;;
        --public-ip)
            shift
            require_option_value "--public-ip" "${1-}"
            INSTALL_PUBLIC_IP="$1"
            ;;
        --wireguard-ip)
            shift
            require_option_value "--wireguard-ip" "${1-}"
            INSTALL_WIREGUARD_IP="$1"
            ;;
        --admin-endpoint)
            shift
            require_option_value "--admin-endpoint" "${1-}"
            INSTALL_ADMIN_ENDPOINT="$1"
            ;;
        --ssh-user|--admin-ssh-user)
            shift
            require_option_value "--ssh-user" "${1-}"
            INSTALL_TARGET_SSH_USER="$1"
            INSTALL_TARGET_SSH_USER_EXPLICIT="true"
            ;;
        --ssh-key|--admin-ssh-key)
            shift
            require_option_value "--ssh-key" "${1-}"
            INSTALL_TARGET_SSH_KEY="$1"
            ;;
        --ssh-public-key)
            shift
            require_option_value "--ssh-public-key" "${1-}"
            INSTALL_SSH_PUBLIC_KEY_FILE="$1"
            ;;
        --ssh-fingerprint)
            shift
            require_option_value "--ssh-fingerprint" "${1-}"
            INSTALL_SSH_FINGERPRINT="$1"
            ;;
        --s3-credentials-file)
            shift
            require_option_value "--s3-credentials-file" "${1-}"
            INSTALL_S3_CREDENTIALS_FILE="$1"
            ;;
        --yes)
            INSTALL_YES="true"
            ;;
        --no-revoke-ssh-key)
            INSTALL_NO_REVOKE_SSH_KEY="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
    shift
done

S3_ACCESS_KEY_VALUE=""
S3_SECRET_KEY_VALUE=""
if [[ -n "$INSTALL_S3_CREDENTIALS_FILE" ]]; then
    [[ -f "$INSTALL_S3_CREDENTIALS_FILE" ]] ||
        die "S3 credentials file not found: $INSTALL_S3_CREDENTIALS_FILE"
    S3_CREDENTIALS_MODE="$(stat -c '%a' "$INSTALL_S3_CREDENTIALS_FILE")" ||
        die "Cannot inspect S3 credentials file permissions: $INSTALL_S3_CREDENTIALS_FILE"
    if (( 10#$S3_CREDENTIALS_MODE % 100 != 0 )); then
        die "S3 credentials file must not be readable by group or other users: $INSTALL_S3_CREDENTIALS_FILE"
    fi
    S3_CREDENTIALS_JSON=$(python3 - "$INSTALL_S3_CREDENTIALS_FILE" <<'PY'
import json
import sys

required = {"ADMIRAL_S3_ACCESS_KEY_ID", "ADMIRAL_S3_SECRET_ACCESS_KEY"}
values = {}
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        for raw in stream:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            key, separator, value = line.partition("=")
            if separator and key in required and value:
                values[key] = value
except OSError as exc:
    raise SystemExit(f"cannot read credentials file: {exc}")

missing = sorted(required - values.keys())
if missing:
    raise SystemExit("missing required S3 credential keys: " + ", ".join(missing))
print(json.dumps(values))
PY
) || die "Invalid S3 credentials file: $INSTALL_S3_CREDENTIALS_FILE"
    S3_ACCESS_KEY_VALUE=$(printf '%s' "$S3_CREDENTIALS_JSON" | python3 -c 'import json, sys; print(json.load(sys.stdin)["ADMIRAL_S3_ACCESS_KEY_ID"])')
    S3_SECRET_KEY_VALUE=$(printf '%s' "$S3_CREDENTIALS_JSON" | python3 -c 'import json, sys; print(json.load(sys.stdin)["ADMIRAL_S3_SECRET_ACCESS_KEY"])')
    unset S3_CREDENTIALS_JSON
fi

[[ -n "$INSTALL_MODE" ]] || die "An installation mode is required. Use --single-node, --dev-node, --admin-node, --admin-portal-node, --worker-node or --portal-node."
if [[ "$INSTALL_DEV_MODE" == "true" && "$INSTALL_YES" != "true" ]]; then
    if [[ ! -t 0 ]]; then
        die "--dev-node requires --yes when stdin is not interactive."
    fi
    warn "Type 'yes-insecure' to confirm this insecure development installation:"
    read -r CONFIRMATION
    [[ "$CONFIRMATION" == "yes-insecure" ]] || die "Aborted: --dev-node was not confirmed."
fi
if [[ "$INSTALL_MODE" == "single-node" && -z "$INSTALL_PUBLIC_IP" ]]; then
    INSTALL_PUBLIC_IP="127.0.0.1"
fi
if [[ "$INSTALL_MODE" == "admin-node" || "$INSTALL_MODE" == "admin-portal-node" ]] && [[ -z "$INSTALL_PUBLIC_IP" ]]; then
    die "$INSTALL_MODE requires --public-ip; refusing to select an interface automatically."
fi
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    [[ -n "$INSTALL_PUBLIC_IP" ]] || die "Worker and portal modes require --public-ip."
fi

if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    if [[ -z "$INSTALL_TARGET_SSH_KEY" ]]; then
        if [[ -f /root/.ssh/id_ed25519 ]]; then
            INSTALL_TARGET_SSH_KEY="/root/.ssh/id_ed25519"
        elif [[ -f /root/.ssh/id_rsa ]]; then
            INSTALL_TARGET_SSH_KEY="/root/.ssh/id_rsa"
        fi
    fi
    if [[ -z "$INSTALL_ADMIN_ENDPOINT" && -f /etc/admiral/install.env ]]; then
        INSTALL_ADMIN_ENDPOINT="$(read_install_state_value ADMIRAL_PUBLIC_IP || true)"
        if is_loopback_host "$INSTALL_ADMIN_ENDPOINT"; then
            INSTALL_ADMIN_ENDPOINT=""
        fi
    fi
    [[ -n "$INSTALL_ADMIN_ENDPOINT" ]] || die "Worker and portal nodes require an admin endpoint from /etc/admiral/install.env or --admin-endpoint."
    [[ -f /etc/admiral/secrets ]] || die "Spoke installs must run from an admin host with /etc/admiral/secrets available."
    [[ -f /etc/admiral/tls/ca.pem ]] || die "Spoke installs must run from an admin host with /etc/admiral/tls/ca.pem available."
    [[ -f /var/lib/admiral/know_host.yaml ]] || die "Spoke installs must run from an admin host with /var/lib/admiral/know_host.yaml available."
    [[ -n "$INSTALL_TARGET_SSH_KEY" ]] || die "Spoke installs require an SSH key. Use --ssh-key or install a default root key."
fi

validate_ipv4_or_hostname() {
    local value="$1"
    [[ -n "$value" && "$value" != *[$'\n\r']* && "$value" != *[[:space:]]* ]] || return 1
    python3 - "$value" <<'PY'
import ipaddress, sys
value = sys.argv[1]
try:
    ipaddress.ip_address(value)
except ValueError:
    import re
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", value):
        raise SystemExit(1)
PY
}

validate_ipv4_or_hostname "$INSTALL_PUBLIC_IP" || die "Invalid public IP or hostname: $INSTALL_PUBLIC_IP"
if [[ -n "$INSTALL_ADMIN_ENDPOINT" ]]; then
    validate_ipv4_or_hostname "$INSTALL_ADMIN_ENDPOINT" || die "Invalid admin endpoint: $INSTALL_ADMIN_ENDPOINT"
fi
if [[ -n "$INSTALL_WIREGUARD_IP" ]]; then
    if ! python3 - "$INSTALL_WIREGUARD_IP" <<'PY'
import ipaddress, sys
ip = ipaddress.ip_address(sys.argv[1])
raise SystemExit(0 if ip.version == 4 and ip in ipaddress.ip_network("10.99.0.0/24") else 1)
PY
    then
        die "WireGuard IP must be inside 10.99.0.0/24"
    fi
fi
if [[ -n "$INSTALL_SSH_FINGERPRINT" && ! "$INSTALL_SSH_FINGERPRINT" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]; then
    die "Invalid SSH fingerprint; expected the complete OpenSSH SHA256 fingerprint"
fi
if [[ -n "$INSTALL_NODE_ID" && ! "$INSTALL_NODE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]]; then
    die "Invalid node ID; use 1-63 letters, numbers, dot, underscore, or hyphen"
fi
if [[ -n "$INSTALL_TARGET_SSH_USER" && ! "$INSTALL_TARGET_SSH_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    die "Invalid SSH username"
fi

REQUESTED_NODE_ROLE=$(expected_node_role "$INSTALL_MODE") || die "Unsupported installation mode: $INSTALL_MODE"

# Resolve the spoke identity before any local package or repository mutation.
# The delivery key is named after node_id when the admin controller has already
# onboarded the node; falling back to the public address here would make a
# reconvergence without --node-id look for the wrong key.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]] &&
    [[ -z "$INSTALL_NODE_ID" || -z "$INSTALL_WIREGUARD_IP" ]]; then
    ROLE_KEY="worker"
    [[ "$INSTALL_MODE" == "portal-node" ]] && ROLE_KEY="portal"
    resolve_known_host_value() {
        local role="$1" field="$2"
        if command -v admiral-known-host >/dev/null 2>&1; then
            admiral-known-host "$role" "$field"
        elif [[ -f "$SCRIPT_DIR/admiral_known_host.py" ]]; then
            python3 "$SCRIPT_DIR/admiral_known_host.py" "$role" "$field"
        else
            return 1
        fi
    }
    if [[ -z "$INSTALL_NODE_ID" ]]; then
        INSTALL_NODE_ID=$(resolve_known_host_value "$ROLE_KEY" node_id || true)
        [[ -n "$INSTALL_NODE_ID" ]] ||
            die "Could not resolve node ID for role '$ROLE_KEY' from know_host.yaml before spoke bootstrap. Pass --node-id explicitly."
        info "Resolved node ID from know_host.yaml: $INSTALL_NODE_ID"
    fi
    if [[ -z "$INSTALL_WIREGUARD_IP" ]]; then
        INSTALL_WIREGUARD_IP=$(resolve_known_host_value "$ROLE_KEY" wireguard_ip || true)
        [[ -n "$INSTALL_WIREGUARD_IP" ]] ||
            die "Could not resolve WireGuard IP for role '$ROLE_KEY' from know_host.yaml before spoke bootstrap. Pass --wireguard-ip explicitly."
        info "Resolved WireGuard IP from know_host.yaml: $INSTALL_WIREGUARD_IP"
    fi
fi

if [[ "$INSTALL_DEV_MODE" != "true" ]] &&
    [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" || "$INSTALL_MODE" == "admin-portal-node" ]]; then
    preflight_local_node_role "$REQUESTED_NODE_ROLE"
fi

# --- 0b1. detect SSH public key for admin user creation ---
# The public key is needed to set up the non-root SSH admin user on every node.
# An explicit public key is independent from the private bootstrap credential.
# Local modes can discover root's or the invoking sudo user's authorized key.
# Spokes still need a private key for transport when no separate public key is supplied.
INSTALL_SSH_PUB_KEY=""
if [[ -n "$INSTALL_SSH_PUBLIC_KEY_FILE" ]]; then
    [[ -f "$INSTALL_SSH_PUBLIC_KEY_FILE" ]] ||
        die "SSH public key file not found: $INSTALL_SSH_PUBLIC_KEY_FILE"
    INSTALL_SSH_PUB_KEY=$(read_public_key_file "$INSTALL_SSH_PUBLIC_KEY_FILE" || true)
    [[ -n "$INSTALL_SSH_PUB_KEY" ]] ||
        die "No valid OpenSSH public key found in $INSTALL_SSH_PUBLIC_KEY_FILE."
fi
if [[ -z "$INSTALL_SSH_PUB_KEY" ]] &&
    [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" || "$INSTALL_MODE" == "admin-portal-node" ]]; then
    if [[ -n "$INSTALL_TARGET_SSH_KEY" && -f "$INSTALL_TARGET_SSH_KEY" ]]; then
        INSTALL_SSH_PUB_KEY=$(ssh-keygen -y -f "$INSTALL_TARGET_SSH_KEY" 2>/dev/null || true)
    fi
    if [[ -z "$INSTALL_SSH_PUB_KEY" ]]; then
        if [[ -f /root/.ssh/id_ed25519.pub ]]; then
            INSTALL_SSH_PUB_KEY=$(read_public_key_file /root/.ssh/id_ed25519.pub || true)
        elif [[ -f /root/.ssh/id_rsa.pub ]]; then
            INSTALL_SSH_PUB_KEY=$(read_public_key_file /root/.ssh/id_rsa.pub || true)
        fi
    fi
    if [[ -z "$INSTALL_SSH_PUB_KEY" ]]; then
        INSTALL_SSH_PUB_KEY=$(read_public_key_file /root/.ssh/authorized_keys 2>/dev/null || true)
    fi
    if [[ -z "$INSTALL_SSH_PUB_KEY" ]]; then
        INSTALL_SSH_PUB_KEY=$(read_invoking_user_public_key 2>/dev/null || true)
    fi
    [[ -n "$INSTALL_SSH_PUB_KEY" ]] ||
        die "No SSH public key found for admin user setup. Use --ssh-public-key or provide a private key with --ssh-key."
fi
if [[ -z "$INSTALL_SSH_PUB_KEY" ]] &&
    [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    INSTALL_SSH_PUB_KEY=$(ssh-keygen -y -f "$INSTALL_TARGET_SSH_KEY" 2>/dev/null || true)
    [[ -n "$INSTALL_SSH_PUB_KEY" ]] || die "Could not extract public key from $INSTALL_TARGET_SSH_KEY."
fi
printf '%s\n' "$INSTALL_SSH_PUB_KEY" | ssh-keygen -lf - >/dev/null 2>&1 ||
    die "The selected administrator SSH public key is invalid."
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    BOOTSTRAP_SSH_PUB_KEY=$(ssh-keygen -y -f "$INSTALL_TARGET_SSH_KEY" 2>/dev/null || true)
    printf '%s\n' "$BOOTSTRAP_SSH_PUB_KEY" | ssh-keygen -lf - >/dev/null 2>&1 ||
        die "Could not derive the public key for the bootstrap credential."
fi

# --- 0c. populate known_hosts before first SSH connection ---
# ssh-keyscan is read-only and transmits no credentials.
# The scanned key is trusted only after it matches the operator-provided fingerprint.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    [[ -n "$INSTALL_SSH_FINGERPRINT" ]] || die "--ssh-fingerprint is required for remote spoke bootstrap."
    info "Retrieving SSH host key for $INSTALL_PUBLIC_IP..."
    KEYSCAN_OUTPUT=$(ssh-keyscan "$INSTALL_PUBLIC_IP" 2>/dev/null) || \
        die "Failed to retrieve SSH host key for $INSTALL_PUBLIC_IP. Ensure SSH is running on the target host."
    MATCHING_HOST_KEYS=""
    FOUND_FINGERPRINTS=""
    while IFS= read -r HOST_KEY; do
        [[ -n "$HOST_KEY" && "$HOST_KEY" != \#* ]] || continue
        HOST_FINGERPRINT=$(printf '%s\n' "$HOST_KEY" | ssh-keygen -lf - -E sha256 2>/dev/null | awk '{print $2}' || true)
        [[ -n "$HOST_FINGERPRINT" ]] || die "Could not parse SSH host keys returned by $INSTALL_PUBLIC_IP."
        FOUND_FINGERPRINTS+="${HOST_FINGERPRINT}"$'\n'
        if [[ "$HOST_FINGERPRINT" == "$INSTALL_SSH_FINGERPRINT" ]]; then
            MATCHING_HOST_KEYS+="${HOST_KEY}"$'\n'
        fi
    done <<< "$KEYSCAN_OUTPUT"
    info "Expected fingerprint: $INSTALL_SSH_FINGERPRINT"
    info "Received fingerprints: $FOUND_FINGERPRINTS"
    [[ -n "$MATCHING_HOST_KEYS" ]] || die "SSH host key fingerprint mismatch for $INSTALL_PUBLIC_IP. Aborting."
    info "SSH host key fingerprint verified."
    umask 077
    INSTALLER_TEMP_BASE="$(mktemp -d /tmp/admiral-install.XXXXXX)"
    chmod 700 "$INSTALLER_TEMP_BASE"
    TMP_KNOWN_HOSTS="$(mktemp "$INSTALLER_TEMP_BASE/known-hosts.XXXXXX")"
    printf '%s' "$MATCHING_HOST_KEYS" > "$TMP_KNOWN_HOSTS"
    SSH_OPTIONS=(
        -i "$INSTALL_TARGET_SSH_KEY"
        -o BatchMode=yes
        -o ControlMaster=no
        -o ControlPersist=no
        -o StrictHostKeyChecking=yes
        -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS"
    )

    BOOTSTRAP_SSH_USER="$INSTALL_TARGET_SSH_USER"
    if [[ "$INSTALL_TARGET_SSH_USER_EXPLICIT" != "true" ]]; then
        PERSISTED_SSH_USER="$(read_admiral_secret ADMIRAL_SSH_USER || true)"
        PERSISTED_SSH_USER="${PERSISTED_SSH_USER:-admiral-ssh}"
        if [[ -n "$PERSISTED_SSH_USER" ]] &&
            ssh "${SSH_OPTIONS[@]}" \
                "${PERSISTED_SSH_USER}@${INSTALL_PUBLIC_IP}" true >/dev/null 2>&1; then
            INSTALL_TARGET_SSH_USER="$PERSISTED_SSH_USER"
            info "Using persisted non-root SSH user: $INSTALL_TARGET_SSH_USER"
        else
            DELIVERY_ID="${INSTALL_NODE_ID:-$INSTALL_PUBLIC_IP}"
            DELIVERY_ID="${DELIVERY_ID//[^A-Za-z0-9_.-]/_}"
            DELIVERY_KEY_CANDIDATE="/var/lib/admiral/ssh-delivery/${DELIVERY_ID}.ed25519"
            if [[ -f "$DELIVERY_KEY_CANDIDATE" ]] &&
                ssh -i "$DELIVERY_KEY_CANDIDATE" \
                    -o BatchMode=yes -o ControlMaster=no -o ControlPersist=no \
                    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS" \
                    "${PERSISTED_SSH_USER}@${INSTALL_PUBLIC_IP}" true >/dev/null 2>&1; then
                INSTALL_TARGET_SSH_KEY="$DELIVERY_KEY_CANDIDATE"
                INSTALL_TARGET_SSH_USER="$PERSISTED_SSH_USER"
                INSTALL_RECONVERGE_SSH_KEY="true"
                SSH_OPTIONS=(
                    -i "$INSTALL_TARGET_SSH_KEY"
                    -o BatchMode=yes
                    -o ControlMaster=no
                    -o ControlPersist=no
                    -o StrictHostKeyChecking=yes
                    -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS"
                )
                info "Using per-node delivery key for spoke reconvergence as $INSTALL_TARGET_SSH_USER"
            fi
        fi
    fi
    preflight_remote_node_role "$REQUESTED_NODE_ROLE"
fi

# --- 1. root check ---
[[ $EUID -eq 0 ]] || die "This script must be run as root."

# --- 2. detect OS ---
if ! source /etc/os-release 2>/dev/null; then
    die "Cannot detect OS. /etc/os-release not found."
fi

case "$ID" in
    rhel|centos|rocky|almalinux)
        MAJOR="${VERSION_ID%%.*}"
        [[ "$MAJOR" -ge 10 ]] || die "Enterprise Linux 10 required (got $ID $VERSION_ID)"
        ;;
    fedora)
        info "Fedora detected (Tier 2 - development, not recommended for production)"
        [[ "$INSTALL_DEV_MODE" == "true" ]] ||
            die "Fedora is supported only with --dev-node; secure production modes require Enterprise Linux 10."
        ;;
    amzn)
        die "Amazon Linux does not ship Podman (required for rootless containers). Admiral is not installable on AL2023."
        ;;
    *)
        die "Unsupported OS: $ID. Supported: EL10, Fedora, Amazon Linux."
        ;;
esac

# Normalize the base operating system before adding repositories or installing
# Admiral packages. EL10 repositories can temporarily expose split package
# updates (for example vim-minimal/vim-data); allow DNF to replace the stale
# member so the rest of the setup starts from a consistent transaction state.
if [[ "$ID" != "amzn" && "$INSTALL_MODE" != "worker-node" && "$INSTALL_MODE" != "portal-node" ]]; then
    info "Applying available system updates before Admiral setup..."
    dnf -y update --refresh --allowerasing
fi

# --- 3. verify Python 3 ---
command -v python3 >/dev/null 2>&1 || die "Python 3 is required but not installed."

# --- 4. enable EPEL (Enterprise Linux only) ---
if [[ "$ID" != "fedora" && "$ID" != "amzn" && "$INSTALL_MODE" != "worker-node" && "$INSTALL_MODE" != "portal-node" ]]; then
    if ! rpm -q epel-release >/dev/null 2>&1; then
        info "Installing EPEL repository..."
        dnf install -y epel-release
    else
        info "EPEL already installed."
    fi
fi

# --- 5. install dnf-plugins-core (for copr) ---
if [[ "$INSTALL_MODE" != "worker-node" && "$INSTALL_MODE" != "portal-node" ]] &&
    ! rpm -q dnf-plugins-core >/dev/null 2>&1; then
    dnf install -y dnf-plugins-core
fi

# EL10 packages used by Admiral are split between EPEL and CRB. Enable CRB
# explicitly on every supported EL derivative so a fresh installation does not
# depend on an operator having prepared the host repositories beforehand.
if [[ "$INSTALL_MODE" != "worker-node" && "$INSTALL_MODE" != "portal-node" ]] &&
    [[ "$ID" == "rhel" || "$ID" == "centos" || "$ID" == "rocky" || "$ID" == "almalinux" ]]; then
    info "Enabling EL10 CRB repository..."
    dnf config-manager --set-enabled crb
fi

if [[ "$INSTALL_MODE" != "worker-node" && "$INSTALL_MODE" != "portal-node" ]]; then
    # --- 6. enable COPR repos ---
    info "Enabling Caddy COPR repository..."
    dnf copr enable -y "@caddy/caddy"

    info "Enabling Admiral COPR repository..."
    dnf copr enable -y "admiral-project/admiral"

    for copr_repo in \
        /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:group_caddy:caddy.repo \
        /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:admiral-project:admiral.repo; do
        [[ -f "$copr_repo" ]] || die "Expected COPR repository file is missing: $copr_repo"
        grep -Eq '^[[:space:]]*gpgcheck[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$copr_repo" ||
            die "Refusing repository without GPG metadata verification: $copr_repo"
    done

    dnf clean all 2>/dev/null || true
else
    info "Spoke mode: leaving local repositories and packages unchanged."
fi

# --- 7. install ansible-core and admiral-common ---
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    command -v ansible-playbook >/dev/null 2>&1 ||
        die "Spoke mode requires ansible-playbook on the admin controller; install admiral-common first."
    rpm -q admiral-common >/dev/null 2>&1 ||
        die "Spoke mode requires admiral-common on the admin controller; install the Admiral release first."
else
    if ! rpm -q ansible-core >/dev/null 2>&1; then
        info "Installing ansible-core..."
        dnf install -y ansible-core
    fi

    # Install or update the complete Admiral release set in one transaction so
    # the playbooks cannot be paired with older component binaries.
    info "Installing the current Admiral component packages..."
    dnf install -y admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship
fi

# --- 7b. resolve spoke node defaults from know_host.yaml (without copying topology) ---
# Extract only the wireguard_ip and node_id needed for this specific spoke.
# know_host.yaml NEVER leaves the admin node — it contains full cluster topology.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    ROLE_KEY="worker"
    [[ "$INSTALL_MODE" == "portal-node" ]] && ROLE_KEY="portal"
    if [[ -z "$INSTALL_NODE_ID" || -z "$INSTALL_WIREGUARD_IP" ]]; then
        if [[ -f /var/lib/admiral/know_host.yaml ]]; then
            if [[ -z "$INSTALL_NODE_ID" ]]; then
            if ! INSTALL_NODE_ID=$(admiral-known-host "$ROLE_KEY" node_id); then
                    warn "Could not resolve node ID for role '$ROLE_KEY' from know_host.yaml."
                    INSTALL_NODE_ID=""
                fi
                [[ -n "$INSTALL_NODE_ID" ]] && info "Resolved node ID from know_host.yaml: $INSTALL_NODE_ID"
            fi
            if [[ -z "$INSTALL_WIREGUARD_IP" ]]; then
                if ! INSTALL_WIREGUARD_IP=$(admiral-known-host "$ROLE_KEY" wireguard_ip); then
                    warn "Could not resolve WireGuard IP for role '$ROLE_KEY' from know_host.yaml."
                    INSTALL_WIREGUARD_IP=""
                fi
                [[ -n "$INSTALL_WIREGUARD_IP" ]] && info "Resolved WireGuard IP from know_host.yaml: $INSTALL_WIREGUARD_IP"
            fi
        fi
    fi
fi

if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    if [[ -n "$INSTALL_NODE_ID" && ! "$INSTALL_NODE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]]; then
        die "Invalid node ID resolved for spoke; use 1-63 letters, numbers, dot, underscore, or hyphen"
    fi
    if [[ -n "$INSTALL_WIREGUARD_IP" ]]; then
        if ! python3 - "$INSTALL_WIREGUARD_IP" <<'PY'
import ipaddress, sys
ip = ipaddress.ip_address(sys.argv[1])
raise SystemExit(0 if ip.version == 4 and ip in ipaddress.ip_network("10.99.0.0/24") else 1)
PY
        then
            die "WireGuard IP must be inside 10.99.0.0/24"
        fi
    fi
fi

# --- 7c. read secrets from admin (never copied to spokes) ---
# Extract only the secrets each spoke type needs and pass them as extra-vars.
SECRETS_HARBOR_SECRET_KEY=""
SECRETS_HARBOR_ENCRYPTION_KEY=""
SECRETS_HARBOR_POSTGRES_PASSWORD=""
SECRETS_HARBOR_BOOTSTRAP_USER=""
SECRETS_HARBOR_BOOTSTRAP_PASSWORD=""
SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD=""
SECRETS_HARBOR_API_TOKEN=""
SECRETS_HARBOR_POSTGRES_USER="admiral"
SECRETS_SSH_USER=""
SECRETS_TASK_PUBLIC_KEY=""
if [[ "$INSTALL_MODE" == "portal-node" ]]; then
    SECRETS_HARBOR_SECRET_KEY=$(read_admiral_secret "HARBOR_SECRET_KEY") || true
    SECRETS_HARBOR_ENCRYPTION_KEY=$(read_admiral_secret "HARBOR_ENCRYPTION_KEY") || true
    # --portal-node always targets a dedicated portal. Its local play creates
    # and preserves a separate PostgreSQL role and password; never transmit
    # the control-plane database credential from the controller.
    SECRETS_HARBOR_POSTGRES_USER="admiral_portal"
    SECRETS_HARBOR_POSTGRES_PASSWORD=""
    SECRETS_HARBOR_BOOTSTRAP_USER=$(read_admiral_secret "HARBOR_BOOTSTRAP_USER") || true
    SECRETS_HARBOR_BOOTSTRAP_PASSWORD=$(read_admiral_secret "HARBOR_BOOTSTRAP_PASSWORD") || true
    SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD=$(read_admiral_secret "HARBOR_LEGACY_ADMIN_PASSWORD") || true
    SECRETS_HARBOR_API_TOKEN=$(read_admiral_secret "ADMIRAL_HARBOR_API_TOKEN") || true
fi
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    SECRETS_TASK_PUBLIC_KEY=$(read_admiral_secret "ADMIRAL_TASK_PUBLIC_KEY") || true
fi

INSTALL_ADMIN_WIREGUARD_IP="${ADMIRAL_WIREGUARD_HUB_IP:-10.99.0.1}"

# --- 8. build extra-vars as JSON (prevents injection via --node-id) ---
EXTRA_VARS_JSON=$(
    INSTALL_MODE="$INSTALL_MODE" \
    INSTALL_DEV_MODE="$INSTALL_DEV_MODE" \
    INSTALL_NODE_ID="$INSTALL_NODE_ID" \
    INSTALL_PUBLIC_IP="$INSTALL_PUBLIC_IP" \
    INSTALL_WIREGUARD_IP="$INSTALL_WIREGUARD_IP" \
    INSTALL_ADMIN_ENDPOINT="$INSTALL_ADMIN_ENDPOINT" \
    INSTALL_ADMIN_WIREGUARD_IP="$INSTALL_ADMIN_WIREGUARD_IP" \
    SECRETS_HARBOR_SECRET_KEY="$SECRETS_HARBOR_SECRET_KEY" \
    SECRETS_HARBOR_ENCRYPTION_KEY="$SECRETS_HARBOR_ENCRYPTION_KEY" \
    SECRETS_HARBOR_POSTGRES_PASSWORD="$SECRETS_HARBOR_POSTGRES_PASSWORD" \
    SECRETS_HARBOR_POSTGRES_USER="$SECRETS_HARBOR_POSTGRES_USER" \
    SECRETS_HARBOR_BOOTSTRAP_USER="$SECRETS_HARBOR_BOOTSTRAP_USER" \
    SECRETS_HARBOR_BOOTSTRAP_PASSWORD="$SECRETS_HARBOR_BOOTSTRAP_PASSWORD" \
    SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD="$SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD" \
    SECRETS_HARBOR_API_TOKEN="$SECRETS_HARBOR_API_TOKEN" \
    SECRETS_SSH_USER="$SECRETS_SSH_USER" \
    SECRETS_TASK_PUBLIC_KEY="$SECRETS_TASK_PUBLIC_KEY" \
    S3_ACCESS_KEY_VALUE="$S3_ACCESS_KEY_VALUE" \
    S3_SECRET_KEY_VALUE="$S3_SECRET_KEY_VALUE" \
    INSTALL_SSH_PUB_KEY="$INSTALL_SSH_PUB_KEY" \
    python3 -c '
import ipaddress, json, os

d = {
    "admiral_install_mode": os.environ["INSTALL_MODE"],
    "admiral_wireguard_hub_ip": os.environ["INSTALL_ADMIN_WIREGUARD_IP"],
}

if os.environ.get("INSTALL_DEV_MODE") == "true":
    d["admiral_dev_mode"] = True

if os.environ.get("INSTALL_NODE_ID"):
    d["fleet_node_id"] = os.environ["INSTALL_NODE_ID"]

if os.environ.get("INSTALL_PUBLIC_IP"):
    d["fleet_public_ip"] = os.environ["INSTALL_PUBLIC_IP"]
    try:
        ipaddress.ip_address(os.environ["INSTALL_PUBLIC_IP"])
        d["fleet_public_ip_is_ip"] = True
    except ValueError:
        d["fleet_public_ip_is_ip"] = False

if os.environ.get("INSTALL_WIREGUARD_IP"):
    d["admiral_wireguard_ip"] = os.environ["INSTALL_WIREGUARD_IP"]

harbor_secret = os.environ.get("SECRETS_HARBOR_SECRET_KEY", "")
if harbor_secret:
    d["admiral_harbor_secret_key_value"] = harbor_secret

harbor_enc = os.environ.get("SECRETS_HARBOR_ENCRYPTION_KEY", "")
if harbor_enc:
    d["admiral_harbor_encryption_key_value"] = harbor_enc

pg_pass = os.environ.get("SECRETS_HARBOR_POSTGRES_PASSWORD", "")
if pg_pass:
    d["admiral_postgres_password"] = pg_pass

pg_user = os.environ.get("SECRETS_HARBOR_POSTGRES_USER", "admiral")
if pg_user:
    d["admiral_postgres_user"] = pg_user

hb_user = os.environ.get("SECRETS_HARBOR_BOOTSTRAP_USER", "")
if hb_user:
    d["admiral_harbor_bootstrap_user"] = hb_user

hb_pass = os.environ.get("SECRETS_HARBOR_BOOTSTRAP_PASSWORD", "")
if hb_pass:
    d["admiral_harbor_bootstrap_password"] = hb_pass

hb_legacy = os.environ.get("SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD", "")
if hb_legacy:
    d["admiral_harbor_legacy_admin_password"] = hb_legacy

hb_api_token = os.environ.get("SECRETS_HARBOR_API_TOKEN", "")
if hb_api_token:
    d["admiral_harbor_api_token_value"] = hb_api_token

task_public_key = os.environ.get("SECRETS_TASK_PUBLIC_KEY", "")
if task_public_key:
    d["admiral_task_public_key_value"] = task_public_key

s3_access_key = os.environ.get("S3_ACCESS_KEY_VALUE", "")
if s3_access_key:
    d["admiral_s3_access_key_value"] = s3_access_key

s3_secret_key = os.environ.get("S3_SECRET_KEY_VALUE", "")
if s3_secret_key:
    d["admiral_s3_secret_key_value"] = s3_secret_key

ssh_pub_key = os.environ.get("INSTALL_SSH_PUB_KEY", "")
if ssh_pub_key and os.environ["INSTALL_MODE"] not in ("worker-node", "portal-node"):
    d["admiral_ssh_pub_key"] = ssh_pub_key

delivery_id = os.environ.get("INSTALL_NODE_ID", "") or os.environ.get("INSTALL_PUBLIC_IP", "")
if delivery_id:
    d["admiral_ssh_delivery_id"] = delivery_id

mode = os.environ["INSTALL_MODE"]
if mode in ("worker-node", "portal-node"):
    d["fleet_node_role"] = "portal" if mode == "portal-node" else "worker"
    d["admiral_admin_endpoint"] = os.environ["INSTALL_ADMIN_ENDPOINT"]
    d["admiral_admin_wireguard_ip"] = os.environ["INSTALL_ADMIN_WIREGUARD_IP"]
    d["admiral_wireguard_hub_endpoint"] = os.environ["INSTALL_ADMIN_ENDPOINT"]
    d["admiral_bootstrap_from_controller"] = True

if mode in ("admin-node", "admin-portal-node", "single-node"):
    d["admiral_wireguard_ip"] = "10.99.0.1"

print(json.dumps(d))
'
)

umask 077
if [[ -z "$INSTALLER_TEMP_BASE" ]]; then
    INSTALLER_TEMP_BASE="$(mktemp -d /tmp/admiral-install.XXXXXX)"
    chmod 700 "$INSTALLER_TEMP_BASE"
fi
EXTRA_VARS_FILE="$(mktemp "$INSTALLER_TEMP_BASE/extra-vars.XXXXXX.json")"
printf '%s\n' "$EXTRA_VARS_JSON" > "$EXTRA_VARS_FILE"
unset EXTRA_VARS_JSON
unset SECRETS_HARBOR_SECRET_KEY
unset SECRETS_HARBOR_ENCRYPTION_KEY SECRETS_HARBOR_POSTGRES_PASSWORD
unset SECRETS_HARBOR_POSTGRES_USER SECRETS_HARBOR_BOOTSTRAP_USER
unset SECRETS_HARBOR_BOOTSTRAP_PASSWORD SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD
unset SECRETS_HARBOR_API_TOKEN SECRETS_SSH_USER INSTALL_SSH_PUB_KEY
unset S3_ACCESS_KEY_VALUE S3_SECRET_KEY_VALUE

# --- 9. run official playbook ---
# The playbook handles the rest: packages, configuration, services
info "Running Admiral configuration playbook for mode: $INSTALL_MODE"
ANSIBLE_DIR="/usr/share/admiral/ansible"
if [[ -d "$ANSIBLE_DIR" ]]; then
    ANSIBLE_LOCAL_TEMP="$INSTALLER_TEMP_BASE/ansible-local"
    ANSIBLE_REMOTE_TEMP="$INSTALLER_TEMP_BASE/ansible-remote"
    ANSIBLE_GALAXY_CACHE_DIR="$INSTALLER_TEMP_BASE/ansible-galaxy-cache"
    if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
        TMP_INVENTORY="$(mktemp "$INSTALLER_TEMP_BASE/inventory.XXXXXX.json")"
        INSTALL_PUBLIC_IP="$INSTALL_PUBLIC_IP" \
        INSTALL_TARGET_SSH_USER="$INSTALL_TARGET_SSH_USER" \
        INSTALL_TARGET_SSH_KEY="$INSTALL_TARGET_SSH_KEY" \
        TMP_KNOWN_HOSTS="$TMP_KNOWN_HOSTS" \
        python3 - "$TMP_INVENTORY" <<'PY'
import json, os, sys
inventory = {
    "all": {
        "hosts": {
            "target": {
                "ansible_host": os.environ["INSTALL_PUBLIC_IP"],
                "ansible_user": os.environ["INSTALL_TARGET_SSH_USER"],
                "ansible_ssh_private_key_file": os.environ["INSTALL_TARGET_SSH_KEY"],
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_ssh_common_args": (
                    "-o StrictHostKeyChecking=yes "
                    f"-o UserKnownHostsFile={os.environ['TMP_KNOWN_HOSTS']}"
                ),
            }
        }
    }
}
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump(inventory, stream)
    stream.write("\n")
PY
        ANSIBLE_LOCAL_TEMP="$ANSIBLE_LOCAL_TEMP" \
        ANSIBLE_REMOTE_TEMP="$ANSIBLE_REMOTE_TEMP" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        ansible-playbook \
            "$ANSIBLE_DIR/site.yml" \
            -i "$TMP_INVENTORY" \
            --limit target \
            --extra-vars "@$EXTRA_VARS_FILE"
    else
        ANSIBLE_LOCAL_TEMP="$ANSIBLE_LOCAL_TEMP" \
        ANSIBLE_REMOTE_TEMP="$ANSIBLE_REMOTE_TEMP" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        ansible-playbook \
            "$ANSIBLE_DIR/site.yml" \
            -i "$ANSIBLE_DIR/inventory/localhost.yml" \
            --extra-vars "@$EXTRA_VARS_FILE"
    fi
else
    die "Ansible playbook directory not found at $ANSIBLE_DIR"
fi

# --- 9b. verify non-root recovery before disabling root SSH ---
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    DELIVERY_ID="${INSTALL_NODE_ID:-$INSTALL_PUBLIC_IP}"
    DELIVERY_ID="${DELIVERY_ID//[^A-Za-z0-9_.-]/_}"
    ADMIN_SSH_DELIVERY_KEY="/var/lib/admiral/ssh-delivery/${DELIVERY_ID}.ed25519"
    [[ -f "$ADMIN_SSH_DELIVERY_KEY" ]] || die "Ansible did not create the per-node SSH delivery key: $ADMIN_SSH_DELIVERY_KEY"
    REMOTE_SSH_USER="admiral-ssh"
    if ! ssh -i "$ADMIN_SSH_DELIVERY_KEY" -o BatchMode=yes \
        -o ControlMaster=no -o ControlPersist=no \
        -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS" \
        "${REMOTE_SSH_USER}@${INSTALL_PUBLIC_IP}" true >/dev/null 2>&1; then
        die "Per-node SSH login verification failed for ${REMOTE_SSH_USER}; bootstrap access remains available for recovery."
    fi
    if ! ssh -i "$ADMIN_SSH_DELIVERY_KEY" -o BatchMode=yes \
        -o ControlMaster=no -o ControlPersist=no \
        -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS" \
        "${REMOTE_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo -n true" >/dev/null 2>&1; then
        die "Per-node sudo verification failed for ${REMOTE_SSH_USER}; bootstrap access remains available for recovery."
    fi
    SSH_OPTIONS=(
        -i "$ADMIN_SSH_DELIVERY_KEY"
        -o BatchMode=yes
        -o ControlMaster=no
        -o ControlPersist=no
        -o StrictHostKeyChecking=yes
        -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS"
    )
    INSTALL_TARGET_SSH_USER="$REMOTE_SSH_USER"
fi

# --- 10. persist local installer state for future spoke bootstraps ---
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" || "$INSTALL_MODE" == "admin-portal-node" ]]; then
    install -d -m 0750 /etc/admiral
    state_tmp="$(mktemp /etc/admiral/install.env.XXXXXX)"
    chmod 0640 "$state_tmp"
    INSTALL_STATE_PUBLIC_IP="$INSTALL_PUBLIC_IP" python3 - "$state_tmp" <<'PY'
import json, os, sys
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump({"version": 1, "ADMIRAL_PUBLIC_IP": os.environ["INSTALL_STATE_PUBLIC_IP"]}, stream)
    stream.write("\n")
PY
    chown root:root "$state_tmp"
    mv -f "$state_tmp" /etc/admiral/install.env
fi

# --- 10b. exchange WireGuard peers for spoke installs ---
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    info "Exchanging WireGuard peers between hub and spoke..."
    export ADMIRAL_ADMIN_TOKEN="$(read_admiral_secret ADMIRAL_ADMIN_TOKEN)"
    [[ -n "$ADMIRAL_ADMIN_TOKEN" ]] || die "Controller admin token is unavailable for WireGuard peer exchange."
    export ADMIRAL_SERVER_URL="https://${INSTALL_ADMIN_WIREGUARD_IP}:8080"
    export ADMIRAL_TLS_CA_FILE="/etc/admiral/tls/ca.pem"
    SPOKE_KEY=$(ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo sh -c 'wg pubkey < /etc/wireguard/admiral.key'" 2>/dev/null || true)
    SPOKE_NODE_ID="${INSTALL_NODE_ID:-$(ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo sh -c \"grep -hE '^(ADMIRAL_FLEET_NODE_ID|HARBOR_NODE_ID)=' /etc/admiral/*.env 2>/dev/null | tail -n1 | cut -d= -f2-\"" 2>/dev/null || true)}"
    if [[ -z "$SPOKE_KEY" ]]; then
        die "Could not read the spoke WireGuard public key after installation."
    fi
    if [[ -z "$SPOKE_NODE_ID" ]]; then
        die "Could not resolve the spoke node ID from --node-id or /etc/admiral/*.env after installation."
    fi
    SPOKE_WG_IP=""
    for attempt in $(seq 1 30); do
        WG_LOOKUP_ERROR_FILE="$(mktemp)"
        SPOKE_WG_IP=$(admiralctl nodes list --output json 2>"$WG_LOOKUP_ERROR_FILE" | SPOKE_NODE_ID="$SPOKE_NODE_ID" python3 -c "
import os, sys, json
target = os.environ['SPOKE_NODE_ID']
data = json.load(sys.stdin)
for n in data if isinstance(data, list) else data.get('nodes', []):
    if n.get('node_id') == target or n.get('id') == target:
        sys.stdout.write(n.get('wireguard_ip', n.get('wg_ip', '')))
        break
" 2>>"$WG_LOOKUP_ERROR_FILE" || true)
        if [[ -s "$WG_LOOKUP_ERROR_FILE" ]]; then
            warn "WireGuard IP lookup attempt $attempt reported: $(tr '\n' ' ' < "$WG_LOOKUP_ERROR_FILE")"
        fi
        rm -f "$WG_LOOKUP_ERROR_FILE"
        [[ -n "$SPOKE_WG_IP" ]] && break
        sleep 1
    done
    if [[ -z "$SPOKE_WG_IP" ]]; then
        die "Could not resolve wireguard_ip for spoke node '$SPOKE_NODE_ID' from admirald."
    fi
    wg set wg-admiral peer "$SPOKE_KEY" allowed-ips "${SPOKE_WG_IP}/32" persistent-keepalive 25
    install -d -m 0700 /etc/wireguard/peers.d
    PEER_FRAGMENT_NAME="${SPOKE_NODE_ID//[^A-Za-z0-9_.-]/_}"
    PEER_FRAGMENT_TMP="$(mktemp /etc/wireguard/peers.d/.${PEER_FRAGMENT_NAME}.XXXXXX)"
    chmod 0600 "$PEER_FRAGMENT_TMP"
    printf '[Peer]\nPublicKey = %s\nAllowedIPs = %s/32\n' \
        "$SPOKE_KEY" "$SPOKE_WG_IP" > "$PEER_FRAGMENT_TMP"
    mv -f "$PEER_FRAGMENT_TMP" "/etc/wireguard/peers.d/${PEER_FRAGMENT_NAME}.conf"
    info "WireGuard peer added for spoke node ($SPOKE_WG_IP) on hub."
    handshake_ok=false
    for _ in {1..12}; do
        if wg show wg-admiral latest-handshakes | awk -v now="$(date +%s)" -v key="$SPOKE_KEY" '$1 == key && $2 > now-120 { found=1 } END { exit(found ? 0 : 1) }'; then
            handshake_ok=true
            break
        fi
        sleep 2
    done
    if [[ "$handshake_ok" != true ]]; then
        die "WireGuard handshake with ${SPOKE_WG_IP} failed; check DNS/public UDP 51820, firewall, keys, and routes."
    fi
fi

# --- 11. verify core runtime ---
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "worker-node" ]]; then
    if [[ "$INSTALL_MODE" == "worker-node" ]]; then
        PODMAN_VER=$(ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo podman version --format '{{.Version}}'" 2>/dev/null || echo "0")
    else
        command -v podman >/dev/null 2>&1 || die "Podman was not installed by RPM dependencies."
        PODMAN_VER=$(podman version --format '{{.Version}}' 2>/dev/null || echo "0")
    fi
    info "Podman version: $PODMAN_VER"
    if [[ "$(printf '%s\n' "5.0" "$PODMAN_VER" | sort -V | head -1)" != "5.0" ]]; then
        die "Podman >= 5.0 required. Found: $PODMAN_VER"
    fi
fi

case "$INSTALL_MODE" in
    single-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-fleet admiral-flagship admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer firewalld auditd fail2ban)
        ;;
    admin-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-flagship firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
    admin-portal-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-flagship admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
    worker-node)
        REQUIRED_SERVICES=(admiral-fleet firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
    portal-node)
        REQUIRED_SERVICES=(postgresql admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
esac

for service in "${REQUIRED_SERVICES[@]}"; do
    service_ready=false
    for attempt in $(seq 1 12); do
        if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
            if ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "systemctl is-active --quiet '$service'"; then
                service_ready=true
                break
            fi
        elif systemctl is-active --quiet "$service"; then
            service_ready=true
            break
        fi
        if [[ "$attempt" == 6 && ( "$service" == "admiral-fleet" || "$service" == "admiral-harbor" ) &&
            ( "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ) ]]; then
            info "${service} is still starting; restarting it once before continuing readiness checks."
            ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
                "sudo -n systemctl restart '$service'" || true
        fi
        sleep 5
    done
    [[ "$service_ready" == true ]] || die "Service $service is not active after remote setup."
done

# Fleet and Harbor may need a few seconds to establish their first control
# plane handshake after WireGuard and their systemd units become available.
# Retry before failing, and restart the workload service once if the first
# attempts show a startup race.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    handshake_ok=false
    for attempt in $(seq 1 12); do
        ready_ok=false
        auth_ok=true
        if admiralctl nodes ready --node "$SPOKE_NODE_ID" >/dev/null 2>&1; then
            ready_ok=true
        fi
        if [[ "$INSTALL_MODE" == "portal-node" ]]; then
            if ! ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
                "sudo -n /usr/bin/harborctl ping" >/dev/null 2>&1; then
                auth_ok=false
            fi
        fi
        if [[ "$ready_ok" == true && "$auth_ok" == true ]]; then
            handshake_ok=true
            info "${INSTALL_MODE} control-plane handshake verified on attempt ${attempt}."
            break
        fi
        if [[ "$attempt" == 3 ]]; then
            if [[ "$INSTALL_MODE" == "worker-node" ]]; then
                info "Handshake is still pending; restarting admiral-fleet once before retrying."
                ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
                    "sudo -n systemctl restart admiral-fleet" || true
            else
                info "Handshake is still pending; restarting admiral-harbor once before retrying."
                ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
                    "sudo -n systemctl restart admiral-harbor" || true
            fi
        fi
        sleep 5
    done
    [[ "$handshake_ok" == true ]] || die "${INSTALL_MODE} did not complete the Admiral control-plane handshake after retries."
fi

case "$INSTALL_MODE" in
    single-node|admin-portal-node)
        info "Verifying Harbor authentication with the Admiral API..."
        harborctl ping || die "Harbor cannot authenticate with the Admiral API. Check ADMIRAL_HARBOR_API_TOKEN in /etc/admiral/harbor.env and harbor_api_token in /etc/admirald.ini."
        ;;
esac

# --- 11b. security checklist (blocking in secure modes) ---
if [[ "$INSTALL_DEV_MODE" != "true" ]]; then
    SECURITY_WARNINGS=()

    run_target_cmd() {
        local cmd="$1"
        if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
            ssh "${SSH_OPTIONS[@]}" \
                "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo bash -s --" \
                <<< "$cmd" 2>/dev/null || true
        else
            bash -c "$cmd" 2>/dev/null || true
        fi
    }

    SELINUX_STATE="$(run_target_cmd "getenforce")"
    if [[ "$SELINUX_STATE" != "Enforcing" ]]; then
        SECURITY_WARNINGS+=("SELinux is '$SELINUX_STATE' (expected: Enforcing).")
    fi

    SELINUX_BOOLS="$(run_target_cmd "getsebool httpd_can_network_connect")"
    if [[ "$SELINUX_BOOLS" != *"httpd_can_network_connect --> on"* ]]; then
        SECURITY_WARNINGS+=("SELinux boolean httpd_can_network_connect is not set to on.")
    fi
    if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "worker-node" ]]; then
        CONTAINER_SELINUX_BOOL="$(run_target_cmd "getsebool container_manage_cgroup")"
        if [[ "$CONTAINER_SELINUX_BOOL" != *"container_manage_cgroup --> on"* ]]; then
            SECURITY_WARNINGS+=("SELinux boolean container_manage_cgroup is not set to on.")
        fi
    fi

    SSHD_EFFECTIVE="$(run_target_cmd "sshd -T")"
    EXPECTED_ROOT_LOGIN="prohibit-password"
    # Spokes retain bootstrap root access until all onboarding, handshake, and
    # security checks have passed. The final root lockdown is applied below.
    ROOT_LOGIN_OK=false
    if [[ "$SSHD_EFFECTIVE" == *"permitrootlogin $EXPECTED_ROOT_LOGIN"* ]]; then
        ROOT_LOGIN_OK=true
    fi
    # OpenSSH >= 8.2 normalizes prohibit-password to without-password in sshd -T output.
    if [[ "$EXPECTED_ROOT_LOGIN" == "prohibit-password" && "$SSHD_EFFECTIVE" == *"permitrootlogin without-password"* ]]; then
        ROOT_LOGIN_OK=true
    fi
    if [[ "$ROOT_LOGIN_OK" == false ]]; then
        SECURITY_WARNINGS+=("sshd PermitRootLogin is not set to $EXPECTED_ROOT_LOGIN.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"passwordauthentication no"* ]]; then
        SECURITY_WARNINGS+=("sshd password authentication is not disabled.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"kbdinteractiveauthentication no"* ]]; then
        SECURITY_WARNINGS+=("sshd keyboard-interactive authentication is not disabled.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"permitemptypasswords no"* ]]; then
        SECURITY_WARNINGS+=("sshd empty passwords are not explicitly disabled.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"x11forwarding no"* ]]; then
        SECURITY_WARNINGS+=("sshd X11 forwarding is not disabled.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"allowagentforwarding no"* ]]; then
        SECURITY_WARNINGS+=("sshd agent forwarding is not disabled.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"maxauthtries 3"* ]]; then
        SECURITY_WARNINGS+=("sshd MaxAuthTries differs from recommended value 3.")
    fi

    PUBLIC_LISTENERS="$(run_target_cmd "ss -H -lntu 2>/dev/null | awk '{ address=\$5; port=address; sub(/^.*:/, \"\", port); host=address; sub(/:[^:]*$/, \"\", host); gsub(/^\\[/, \"\", host); gsub(/\\]$/, \"\", host); if (host !~ /^(127\\.|::1\$)/ && host !~ /^10\\.99\\.0\\./ && host !~ /^172\\.(1[6-9]|2[0-9]|3[0-1])\\./ && host !~ /^192\\.168\\./ && host !~ /^169\\.254\\./) print \$1 \"/\" port }' | sort -u | tr '\\n' ' ' | sed 's/[[:space:]]*\$//'" || true)"
    EXPECTED_LISTENERS="$(expected_public_listeners "$INSTALL_MODE")"
    if ! require_exact_public_listeners "$PUBLIC_LISTENERS" "$EXPECTED_LISTENERS"; then
        SECURITY_WARNINGS+=("Public listening sockets do not match the declared host profile.")
    fi

    AUDITCTL_PATH="$(run_target_cmd "command -v auditctl || true")"
    if [[ -n "$AUDITCTL_PATH" ]]; then
        AUDIT_RULES="$(run_target_cmd "auditctl -l" || true)"
        for audit_key in admiral_config admiral_secrets admiral_tls admiral_data admiral_wireguard; do
            if [[ "$AUDIT_RULES" != *"$audit_key"* ]]; then
                SECURITY_WARNINGS+=("Loaded audit rules are missing key $audit_key.")
            fi
        done
    else
        AUDIT_RULE_FILE_STATE="$(run_target_cmd "test -s /etc/audit/rules.d/admiral.rules && printf present || true")"
        if [[ "$AUDIT_RULE_FILE_STATE" != "present" ]]; then
            SECURITY_WARNINGS+=("The Admiral audit rules file is missing on a host without auditctl.")
        fi
    fi

    FAIL2BAN_STATUS="$(run_target_cmd "fail2ban-client ping && fail2ban-client status sshd" || true)"
    if ! [[ "$FAIL2BAN_STATUS" == *"Server replied: pong"* &&
        "$FAIL2BAN_STATUS" == *"Status for the jail"* ]]; then
        SECURITY_WARNINGS+=("fail2ban is not responding with the expected sshd jail.")
    fi
    FAIL2BAN_ACTIONS="$(run_target_cmd "fail2ban-client get sshd actions" || true)"
    if [[ "$FAIL2BAN_ACTIONS" != *"nftables"* ]]; then
        SECURITY_WARNINGS+=("fail2ban sshd jail is not using the required nftables action.")
    fi

    AUTOMATIC_UPDATES="$(run_target_cmd "systemctl is-enabled dnf-automatic.timer && systemctl is-active dnf-automatic.timer" || true)"
    if [[ "$AUTOMATIC_UPDATES" != *"enabled"* || "$AUTOMATIC_UPDATES" != *"active"* ]]; then
        SECURITY_WARNINGS+=("automatic security updates are not enabled and active.")
    fi

    TIME_SYNC="$(run_target_cmd "chronyc tracking" || true)"
    if [[ "$TIME_SYNC" != *"Leap status     : Normal"* ]]; then
        SECURITY_WARNINGS+=("chronyd has not synchronized the system clock.")
    fi

    NFT_EGRESS="$(run_target_cmd "nft list chain inet admiral_egress output" || true)"
    if [[ "$NFT_EGRESS" != *"reject"* ]]; then
        SECURITY_WARNINGS+=("The managed nftables egress reject policy is not active.")
    fi

    if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "worker-node" ]]; then
        ROOTLESS_STATE="$(run_target_cmd '
            uid=$(id -u admiral-apps) || exit 1
            /usr/bin/admiral-rootless-subids --user admiral-apps || exit 1
            test \"$(loginctl show-user admiral-apps -p Linger --value)\" = yes || exit 1
            systemctl is-active --quiet \"user@${uid}.service\" || exit 1
            systemctl is-active --quiet systemd-machined.service || exit 1
            test -S \"/run/user/${uid}/bus\" || exit 1
            graph_root=$(cd / && runuser -u admiral-apps -- env \
                HOME=/var/lib/admiral-apps \
                XDG_RUNTIME_DIR=\"/run/user/${uid}\" \
                DBUS_SESSION_BUS_ADDRESS=\"unix:path=/run/user/${uid}/bus\" \
                podman info --format \"{{.Store.GraphRoot}}\") || exit 1
            test \"$graph_root\" = /var/lib/admiral-apps/.local/share/containers/storage
        ' && printf '%s' secure || true)"
        if [[ "$ROOTLESS_STATE" != "secure" ]]; then
            SECURITY_WARNINGS+=("Rootless user IDs, user manager, D-Bus, or Podman storage are not securely initialized.")
        fi
    fi

    if [[ "$INSTALL_MODE" != "single-node" ]]; then
        IPV4_FORWARDING="$(run_target_cmd "sysctl -n net.ipv4.ip_forward | tr -d '[:space:]'" || true)"
        IPV6_FORWARDING="$(run_target_cmd "sysctl -n net.ipv6.conf.all.forwarding | tr -d '[:space:]'" || true)"
        if [[ "$IPV4_FORWARDING" != "0" || "$IPV6_FORWARDING" != "0" ]]; then
            SECURITY_WARNINGS+=("IP forwarding is not disabled on the VPN node.")
        fi

        # firewalld on EL10 exposes zone targets through the permanent
        # configuration API; without --permanent it exits with a usage error.
        WG_ZONE_TARGET="$(run_target_cmd "firewall-cmd --permanent --zone=admiral --get-target" || true)"
        WG_ZONE_INTERFACES="$(run_target_cmd "firewall-cmd --zone=admiral --list-interfaces" || true)"
        TRUSTED_INTERFACES="$(run_target_cmd "firewall-cmd --zone=trusted --list-interfaces" || true)"
        if [[ "$WG_ZONE_TARGET" != "DROP" ]]; then
            SECURITY_WARNINGS+=("The WireGuard firewalld zone does not use a DROP target.")
        fi
        if [[ " $WG_ZONE_INTERFACES " != *" wg-admiral "* ]]; then
            SECURITY_WARNINGS+=("wg-admiral is not assigned to the restricted firewalld zone.")
        fi
        if [[ " $TRUSTED_INTERFACES " == *" wg-admiral "* ]]; then
            SECURITY_WARNINGS+=("wg-admiral remains assigned to the trusted firewalld zone.")
        fi

        WG_ALLOWED_IPS="$(run_target_cmd "wg show wg-admiral allowed-ips" || true)"
        if [[ "$WG_ALLOWED_IPS" == *"10.99.0.0/24"* || "$WG_ALLOWED_IPS" == *"0.0.0.0/0"* ]]; then
            SECURITY_WARNINGS+=("WireGuard contains an unexpectedly broad peer route.")
        fi
        if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]] &&
            [[ "$WG_ALLOWED_IPS" != *"10.99.0.1/32"* ]]; then
            SECURITY_WARNINGS+=("The spoke WireGuard route is not restricted to the admin hub.")
        fi
    fi

    FW_SERVICES="$(run_target_cmd "firewall-cmd --zone=public --list-services")"
    FW_PORTS="$(run_target_cmd "firewall-cmd --zone=public --list-ports")"
    EXPECTED_FW_PORTS="$(expected_firewall_ports "$INSTALL_MODE")"
    if [[ "$FW_PORTS" != "$EXPECTED_FW_PORTS" ]]; then
        SECURITY_WARNINGS+=("Public firewall ports do not match the declared host profile: expected '$EXPECTED_FW_PORTS', found '$FW_PORTS'.")
    fi
    case "$INSTALL_MODE" in
        single-node|admin-node|admin-portal-node)
            require_firewall_services "$FW_SERVICES" ssh http https ||
                SECURITY_WARNINGS+=("Expected public services ssh/http/https for admin profile not fully present.")
            ;;
        worker-node|portal-node)
            require_firewall_services "$FW_SERVICES" ssh ||
                SECURITY_WARNINGS+=("Expected public service ssh is missing on spoke profile.")
            if [[ "$FW_SERVICES" == *"http"* || "$FW_SERVICES" == *"https"* ]]; then
                SECURITY_WARNINGS+=("Spoke profile exposes http/https in public zone.")
            fi
            ;;
    esac

    if [[ ${#SECURITY_WARNINGS[@]} -gt 0 ]]; then
        warn "----------------------------------------------------------------"
        die "Security checklist failed: ${SECURITY_WARNINGS[*]}"
    fi
fi

# --- 11c. revoke bootstrap SSH access only after complete onboarding ---
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]] &&
    [[ "$INSTALL_NO_REVOKE_SSH_KEY" != "true" ]]; then
    [[ -n "$BOOTSTRAP_SSH_PUB_KEY" ]] || die "Bootstrap public key is unavailable; refusing to claim onboarding completion."
    [[ -n "$BOOTSTRAP_SSH_USER" ]] || die "Bootstrap SSH user is unavailable; refusing to revoke bootstrap access."
    printf -v QUOTED_BOOTSTRAP_USER '%q' "$BOOTSTRAP_SSH_USER"
    printf -v QUOTED_BOOTSTRAP_KEY '%q' "$BOOTSTRAP_SSH_PUB_KEY"
    ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "sudo -n /usr/bin/admiral-revoke-bootstrap-key $QUOTED_BOOTSTRAP_USER $QUOTED_BOOTSTRAP_KEY" \
        || die "Could not revoke the bootstrap SSH credential from authorized_keys."
    if [[ "$INSTALL_RECONVERGE_SSH_KEY" != "true" ]] && ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes \
        -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS" \
        "${BOOTSTRAP_SSH_USER}@${INSTALL_PUBLIC_IP}" true >/dev/null 2>&1; then
        die "Bootstrap SSH credential is still accepted after revocation."
    fi
    ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "sudo sh -c 'tmp=/etc/ssh/sshd_config.d/.49-admiral-root-lockdown.conf.tmp; install -m 0644 /dev/stdin \"\$tmp\" && mv \"\$tmp\" /etc/ssh/sshd_config.d/49-admiral-root-lockdown.conf && { sshd -t && systemctl reload sshd || { rm -f /etc/ssh/sshd_config.d/49-admiral-root-lockdown.conf; exit 1; }; }'" \
        <<<"PermitRootLogin no" \
        || die "Could not validate and apply PermitRootLogin no after bootstrap revocation."
    ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo -n true" >/dev/null 2>&1 ||
        die "Per-node SSH identity stopped working after bootstrap revocation."
    info "Bootstrap SSH credential revoked; per-node admiral-ssh identity is now authoritative."
fi

# --- 12. final message ---
cat <<EOF

Admiral installation completed.

Installation mode:
  $INSTALL_MODE
EOF

if [[ "$INSTALL_DEV_MODE" == "true" ]]; then
    cat <<EOF

***** SECURITY WARNING *****
This node was installed in --dev-node mode.
WSGI servers (Harbor and Flagship) are exposed directly to the internet
on ports 5001 and 5000. Cockpit is exposed on port 9090.
Local self-signed certificates are used to protect the network.
This configuration is NOT recommended for production use.
***** SECURITY WARNING *****
EOF
fi

cat <<EOF

Bootstrap credentials and signing keys are stored at:
  /etc/admiral/secrets

***** WARNING *****
This file contains ALL your Admiral secrets, including database
passwords, shared tokens, and encryption keys. Without it you
cannot recover the platform.

BACK UP this file to a secure location OFF this node IMMEDIATELY.
If /etc/admiral/secrets is lost, the installation CANNOT be recovered.
***** WARNING *****

HTTPS has not been configured yet.
This is intentional.

Run:
  sudo admiral-https-setup

The Admiral API is not publicly exposed.
Internal services stay on loopback behind Caddy.
EOF

# --- 12b. SSH admin user access info ---
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" || "$INSTALL_MODE" == "admin-portal-node" ]]; then
    ADMIRAL_SSH_USER_VAL=$(read_admiral_secret "ADMIRAL_SSH_USER" 2>/dev/null || true)
    if [[ -n "$ADMIRAL_SSH_USER_VAL" ]]; then
        DISPLAY_HOST=$( [[ "$INSTALL_PUBLIC_IP" == "127.0.0.1" ]] && echo "localhost" || echo "$INSTALL_PUBLIC_IP" )
        cat <<EOF

SSH access (recommended, non-root):
  ssh ${ADMIRAL_SSH_USER_VAL}@${DISPLAY_HOST}

This user has sudo NOPASSWD access.
Root login is restricted to key-based authentication only.
EOF
    fi
fi

if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    DELIVERY_ID="${INSTALL_NODE_ID:-$INSTALL_PUBLIC_IP}"
    DELIVERY_ID="${DELIVERY_ID//[^A-Za-z0-9_.-]/_}"
    ADMIN_SSH_DELIVERY_KEY="/var/lib/admiral/ssh-delivery/${DELIVERY_ID}.ed25519"
    ADMIN_SSH_FINGERPRINT=$(ssh-keygen -lf "${ADMIN_SSH_DELIVERY_KEY}.pub" -E sha256 | awk '{$1=$1; print}' || true)
    cat <<EOF

Administrative SSH credential for this node:
  Node ID:       ${DELIVERY_ID}
  Host:          ${INSTALL_PUBLIC_IP}
  User:          admiral-ssh
  Private key:   ${ADMIN_SSH_DELIVERY_KEY}
  Public key:    ${ADMIN_SSH_DELIVERY_KEY}.pub
  Fingerprint:   ${ADMIN_SSH_FINGERPRINT}

Extract this private key to secure administrator storage and delete both
delivery artifacts from the Admin node after verification. Admiral will not
use this key for normal control-plane operations.
EOF
fi

if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    cat <<EOF

***** REMINDER *****
Harbor PayPal mode is 'sandbox'. To accept real payments:
  1. Set HARBOR_PAYPAL_MODE=live in /etc/admiral/harbor.env
  2. Configure HARBOR_PAYPAL_CLIENT_ID and HARBOR_PAYPAL_CLIENT_SECRET
See https://admiral-project.github.io for PayPal setup guide.
***** REMINDER *****
EOF
fi
