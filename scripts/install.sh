#!/usr/bin/env bash
# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# --- helpers ---
die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
require_option_value() {
    local opt="$1"
    local val="${2-}"
    [[ -n "$val" && "$val" != --* ]] || die "$opt requires a value."
}
is_loopback_host() {
    case "$1" in
        ""|127.0.0.1|localhost|::1)
            return 0
            ;;
    esac
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
        single-node) listeners=$'tcp/22\ntcp/80\ntcp/443' ;;
        admin-node|admin-portal-node) listeners=$'tcp/22\ntcp/80\ntcp/443\nudp/51820' ;;
        worker-node|portal-node) listeners=$'tcp/22\nudp/51820' ;;
    esac
    printf '%s\n' "$listeners" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}
public_listeners() {
    ss -H -lntu 2>/dev/null | awk '
        {
            address = $5
            port = address
            sub(/^.*:/, "", port)
            host = address
            sub(/:[^:]*$/, "", host)
            gsub(/^\[/, "", host)
            gsub(/\]$/, "", host)
            if (host !~ /^(127\.|::1$)/) print $1 "/" port
        }
    ' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
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
  admiral_install --single-node [--public-ip <public-ip>]
  admiral_install --dev-node [--public-ip <public-ip>]
  admiral_install --admin-node [--public-ip <public-ip>]
  admiral_install --admin-portal-node [--public-ip <public-ip>]
  admiral_install --worker-node --public-ip <public-ip> [--wireguard-ip <wireguard-ip>]
  admiral_install --portal-node --public-ip <public-ip> [--wireguard-ip <wireguard-ip>]

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
  --ssh-fingerprint   Expected SSH host key fingerprint (SHA256:...) for verification.
  --yes               Confirm non-interactive dangerous operations such as --dev-node.
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
INSTALL_SSH_FINGERPRINT=""
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
        --ssh-fingerprint)
            shift
            require_option_value "--ssh-fingerprint" "${1-}"
            INSTALL_SSH_FINGERPRINT="$1"
            ;;
        --yes)
            INSTALL_YES="true"
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

# --- 0b1. detect SSH public key for admin user creation ---
# The public key is needed to set up the non-root SSH admin user on every node.
# For admin/single-node: detect from --ssh-key, id_ed25519.pub, id_rsa.pub, or authorized_keys.
# For worker/portal: extract from the private key used to connect to the spoke.
INSTALL_SSH_PUB_KEY=""
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" || "$INSTALL_MODE" == "admin-portal-node" ]]; then
    if [[ -n "$INSTALL_TARGET_SSH_KEY" && -f "$INSTALL_TARGET_SSH_KEY" ]]; then
        INSTALL_SSH_PUB_KEY=$(ssh-keygen -y -f "$INSTALL_TARGET_SSH_KEY" 2>/dev/null || true)
    fi
    if [[ -z "$INSTALL_SSH_PUB_KEY" ]]; then
        if [[ -f /root/.ssh/id_ed25519.pub ]]; then
            INSTALL_SSH_PUB_KEY=$(cat /root/.ssh/id_ed25519.pub)
        elif [[ -f /root/.ssh/id_rsa.pub ]]; then
            INSTALL_SSH_PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
        fi
    fi
    if [[ -z "$INSTALL_SSH_PUB_KEY" ]]; then
        INSTALL_SSH_PUB_KEY=$(head -1 /root/.ssh/authorized_keys 2>/dev/null || true)
    fi
    [[ -n "$INSTALL_SSH_PUB_KEY" ]] || die "No SSH public key found for admin user setup. Use --ssh-key or install a key at ~/.ssh/id_ed25519.pub."
fi
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    INSTALL_SSH_PUB_KEY=$(ssh-keygen -y -f "$INSTALL_TARGET_SSH_KEY" 2>/dev/null || true)
    [[ -n "$INSTALL_SSH_PUB_KEY" ]] || die "Could not extract public key from $INSTALL_TARGET_SSH_KEY."
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
        [[ -n "$HOST_KEY" ]] || continue
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
        -o StrictHostKeyChecking=yes
        -o "UserKnownHostsFile=$TMP_KNOWN_HOSTS"
    )

    if [[ "$INSTALL_TARGET_SSH_USER_EXPLICIT" != "true" ]]; then
        PERSISTED_SSH_USER="$(read_admiral_secret ADMIRAL_SSH_USER || true)"
        if [[ -n "$PERSISTED_SSH_USER" ]] &&
            ssh "${SSH_OPTIONS[@]}" \
                "${PERSISTED_SSH_USER}@${INSTALL_PUBLIC_IP}" true >/dev/null 2>&1; then
            INSTALL_TARGET_SSH_USER="$PERSISTED_SSH_USER"
            info "Using persisted non-root SSH user: $INSTALL_TARGET_SSH_USER"
        fi
    fi
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

# --- 3. verify Python 3 ---
command -v python3 >/dev/null 2>&1 || die "Python 3 is required but not installed."

# --- 4. enable EPEL (Enterprise Linux only) ---
if [[ "$ID" != "fedora" && "$ID" != "amzn" ]]; then
    if ! rpm -q epel-release >/dev/null 2>&1; then
        info "Installing EPEL repository..."
        dnf install -y epel-release
    else
        info "EPEL already installed."
    fi
fi

# --- 5. install dnf-plugins-core (for copr) ---
if ! rpm -q dnf-plugins-core >/dev/null 2>&1; then
    dnf install -y dnf-plugins-core
fi

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

# --- 7. install ansible-core and admiral-common ---
if ! rpm -q ansible-core >/dev/null 2>&1; then
    info "Installing ansible-core..."
    dnf install -y ansible-core
fi

# Install or update admiral-common first so reconciliation always uses the
# playbooks from the currently enabled Admiral repository.
info "Installing the current admiral-common package..."
dnf install -y admiral-common

# --- 7b. resolve spoke node defaults from know_host.yaml (without copying topology) ---
# Extract only the wireguard_ip and node_id needed for this specific spoke.
# know_host.yaml NEVER leaves the admin node — it contains full cluster topology.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    ROLE_KEY="worker"
    [[ "$INSTALL_MODE" == "portal-node" ]] && ROLE_KEY="portal"
    if [[ -z "$INSTALL_NODE_ID" || -z "$INSTALL_WIREGUARD_IP" ]]; then
        if [[ -f /var/lib/admiral/know_host.yaml ]]; then
            # grep -A2 after "  worker:" or "  portal:" under the "next:" section
            if [[ -z "$INSTALL_NODE_ID" ]]; then
                INSTALL_NODE_ID=$(grep -A2 "^  ${ROLE_KEY}:" /var/lib/admiral/know_host.yaml | grep "node_id:" | awk '{print $2}')
                [[ -n "$INSTALL_NODE_ID" ]] && info "Resolved node ID from know_host.yaml: $INSTALL_NODE_ID"
            fi
            if [[ -z "$INSTALL_WIREGUARD_IP" ]]; then
                INSTALL_WIREGUARD_IP=$(grep -A2 "^  ${ROLE_KEY}:" /var/lib/admiral/know_host.yaml | grep "wireguard_ip:" | awk '{print $2}')
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
SECRETS_TASK_ENCRYPTION_KEY=""
SECRETS_HARBOR_SECRET_KEY=""
SECRETS_HARBOR_ENCRYPTION_KEY=""
SECRETS_HARBOR_POSTGRES_PASSWORD=""
SECRETS_HARBOR_BOOTSTRAP_USER=""
SECRETS_HARBOR_BOOTSTRAP_PASSWORD=""
SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD=""
SECRETS_HARBOR_API_TOKEN=""
SECRETS_HARBOR_POSTGRES_USER="admiral"
SECRETS_SSH_USER=""
if [[ "$INSTALL_MODE" == "worker-node" ]]; then
    SECRETS_TASK_ENCRYPTION_KEY=$(read_admiral_secret "ADMIRAL_TASK_ENCRYPTION_KEY") || true
fi
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
    SECRETS_SSH_USER=$(read_admiral_secret "ADMIRAL_SSH_USER") || true
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
    SECRETS_TASK_ENCRYPTION_KEY="$SECRETS_TASK_ENCRYPTION_KEY" \
    SECRETS_HARBOR_SECRET_KEY="$SECRETS_HARBOR_SECRET_KEY" \
    SECRETS_HARBOR_ENCRYPTION_KEY="$SECRETS_HARBOR_ENCRYPTION_KEY" \
    SECRETS_HARBOR_POSTGRES_PASSWORD="$SECRETS_HARBOR_POSTGRES_PASSWORD" \
    SECRETS_HARBOR_POSTGRES_USER="$SECRETS_HARBOR_POSTGRES_USER" \
    SECRETS_HARBOR_BOOTSTRAP_USER="$SECRETS_HARBOR_BOOTSTRAP_USER" \
    SECRETS_HARBOR_BOOTSTRAP_PASSWORD="$SECRETS_HARBOR_BOOTSTRAP_PASSWORD" \
    SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD="$SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD" \
    SECRETS_HARBOR_API_TOKEN="$SECRETS_HARBOR_API_TOKEN" \
    SECRETS_SSH_USER="$SECRETS_SSH_USER" \
    INSTALL_SSH_PUB_KEY="$INSTALL_SSH_PUB_KEY" \
    python3 -c '
import json, os

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

if os.environ.get("INSTALL_WIREGUARD_IP"):
    d["admiral_wireguard_ip"] = os.environ["INSTALL_WIREGUARD_IP"]

task_key = os.environ.get("SECRETS_TASK_ENCRYPTION_KEY", "")
if task_key:
    d["admiral_task_encryption_key_value"] = task_key

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

ssh_user = os.environ.get("SECRETS_SSH_USER", "")
if ssh_user:
    d["admiral_ssh_admin_user"] = ssh_user

ssh_pub_key = os.environ.get("INSTALL_SSH_PUB_KEY", "")
if ssh_pub_key:
    d["admiral_ssh_pub_key"] = ssh_pub_key

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
unset SECRETS_TASK_ENCRYPTION_KEY SECRETS_HARBOR_SECRET_KEY
unset SECRETS_HARBOR_ENCRYPTION_KEY SECRETS_HARBOR_POSTGRES_PASSWORD
unset SECRETS_HARBOR_POSTGRES_USER SECRETS_HARBOR_BOOTSTRAP_USER
unset SECRETS_HARBOR_BOOTSTRAP_PASSWORD SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD
unset SECRETS_HARBOR_API_TOKEN SECRETS_SSH_USER INSTALL_SSH_PUB_KEY

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
    REMOTE_SSH_USER="$(read_admiral_secret ADMIRAL_SSH_USER || true)"
    [[ "$REMOTE_SSH_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Remote installation did not produce a valid non-root SSH user. Root login remains available for recovery."
    if ! ssh "${SSH_OPTIONS[@]}" \
        "${REMOTE_SSH_USER}@${INSTALL_PUBLIC_IP}" true >/dev/null 2>&1; then
        die "Non-root SSH login verification failed for ${REMOTE_SSH_USER}; root login was not disabled."
    fi
    if ! ssh "${SSH_OPTIONS[@]}" \
        "${REMOTE_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo -n true" >/dev/null 2>&1; then
        die "Non-root sudo verification failed for ${REMOTE_SSH_USER}; root login was not disabled."
    fi
    ssh "${SSH_OPTIONS[@]}" \
        "${REMOTE_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "sudo sh -c 'tmp=/etc/ssh/sshd_config.d/.60-admiral-root-lockdown.conf.tmp; install -m 0644 /dev/stdin \"\$tmp\" && mv \"\$tmp\" /etc/ssh/sshd_config.d/60-admiral-root-lockdown.conf && { sshd -t && systemctl reload sshd || { rm -f /etc/ssh/sshd_config.d/60-admiral-root-lockdown.conf; exit 1; }; }'" \
        <<<"PermitRootLogin no" \
        || die "Could not validate and apply PermitRootLogin no; root login remains available for recovery."
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
    SPOKE_KEY=$(ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo sh -c 'wg pubkey < /etc/wireguard/admiral.key'" 2>/dev/null || true)
    SPOKE_NODE_ID="${INSTALL_NODE_ID:-$(ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo sh -c \"grep -hE '^(ADMIRAL_FLEET_NODE_ID|HARBOR_NODE_ID)=' /etc/admiral/*.env 2>/dev/null | tail -n1 | cut -d= -f2-\"" 2>/dev/null || true)}"
    if [[ -z "$SPOKE_KEY" ]]; then
        die "Could not read the spoke WireGuard public key after installation."
    fi
    if [[ -z "$SPOKE_NODE_ID" ]]; then
        die "Could not resolve the spoke node ID from --node-id or /etc/admiral/*.env after installation."
    fi
    SPOKE_WG_IP=$(SPOKE_NODE_ID="$SPOKE_NODE_ID" admiralctl nodes list --output json 2>/dev/null | python3 -c "
import os, sys, json
target = os.environ['SPOKE_NODE_ID']
data = json.load(sys.stdin)
for n in data if isinstance(data, list) else data.get('nodes', []):
    if n.get('node_id') == target or n.get('id') == target:
        sys.stdout.write(n.get('wireguard_ip', n.get('wg_ip', '')))
        break
" 2>/dev/null || true)
    if [[ -z "$SPOKE_WG_IP" ]]; then
        die "Could not resolve wireguard_ip for spoke node '$SPOKE_NODE_ID' from admirald."
    fi
    wg set wg-admiral peer "$SPOKE_KEY" allowed-ips "${SPOKE_WG_IP}/32" persistent-keepalive 25
        wg-quick save wg-admiral
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
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-fleet admiral-flagship admiral-harbor cockpit.socket firewalld auditd fail2ban)
        ;;
    admin-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-flagship cockpit.socket firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
    admin-portal-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-flagship admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer cockpit.socket firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
    worker-node)
        REQUIRED_SERVICES=(admiral-fleet firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
    portal-node)
        REQUIRED_SERVICES=(postgresql admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer firewalld auditd fail2ban wg-quick@wg-admiral)
        ;;
esac

for service in "${REQUIRED_SERVICES[@]}"; do
    if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
        ssh "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "systemctl is-active --quiet '$service'" || die "Service $service is not active after remote setup."
    else
        systemctl is-active --quiet "$service" || die "Service $service is not active after setup."
    fi
done

if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-portal-node" ]]; then
    info "Verifying Harbor authentication with the Admiral API..."
    harborctl ping || die "Harbor cannot authenticate with the Admiral API. Check ADMIRAL_HARBOR_API_TOKEN in /etc/admiral/harbor.env and harbor_api_token in /etc/admirald.ini."
fi

# --- 11b. security checklist (blocking in secure modes) ---
if [[ "$INSTALL_DEV_MODE" != "true" ]]; then
    SECURITY_WARNINGS=()

    run_target_cmd() {
        local cmd="$1"
        if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
            local quoted_cmd
            printf -v quoted_cmd '%q' "$cmd"
            ssh "${SSH_OPTIONS[@]}" \
                "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo bash -lc $quoted_cmd" 2>/dev/null || true
        else
            bash -lc "$cmd" 2>/dev/null || true
        fi
    }

    SELINUX_STATE="$(run_target_cmd "getenforce")"
    if [[ "$SELINUX_STATE" != "Enforcing" ]]; then
        SECURITY_WARNINGS+=("SELinux is '$SELINUX_STATE' (expected: Enforcing).")
    fi

    SELINUX_BOOLS="$(run_target_cmd "getsebool httpd_can_network_connect container_manage_cgroup")"
    if [[ "$SELINUX_BOOLS" != *"httpd_can_network_connect --> on"* ]]; then
        SECURITY_WARNINGS+=("SELinux boolean httpd_can_network_connect is not set to on.")
    fi
    if [[ "$SELINUX_BOOLS" != *"container_manage_cgroup --> on"* ]]; then
        SECURITY_WARNINGS+=("SELinux boolean container_manage_cgroup is not set to on.")
    fi

    SSHD_EFFECTIVE="$(run_target_cmd "sshd -T")"
    EXPECTED_ROOT_LOGIN="prohibit-password"
    if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
        EXPECTED_ROOT_LOGIN="no"
    fi
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
    if [[ "$SSHD_EFFECTIVE" != *"maxauthtries 3"* ]]; then
        SECURITY_WARNINGS+=("sshd MaxAuthTries differs from recommended value 3.")
    fi

    PUBLIC_LISTENERS="$(run_target_cmd "ss -H -lntu 2>/dev/null | awk '{ address=\$5; port=address; sub(/^.*:/, \"\", port); host=address; sub(/:[^:]*$/, \"\", host); gsub(/^\\[/, \"\", host); gsub(/\\]$/, \"\", host); if (host !~ /^(127\\.|::1\$)/) print \$1 \"/\" port }' | sort -u | tr '\\n' ' ' | sed 's/[[:space:]]*\$//'" || true)"
    EXPECTED_LISTENERS="$(expected_public_listeners "$INSTALL_MODE")"
    if ! require_exact_public_listeners "$PUBLIC_LISTENERS" "$EXPECTED_LISTENERS"; then
        SECURITY_WARNINGS+=("Public listening sockets do not match the declared host profile.")
    fi

    AUDIT_RULES="$(run_target_cmd "auditctl -l" || true)"
    for audit_key in admiral_config admiral_secrets admiral_tls admiral_data admiral_wireguard; do
        if [[ "$AUDIT_RULES" != *"$audit_key"* ]]; then
            SECURITY_WARNINGS+=("Loaded audit rules are missing key $audit_key.")
        fi
    done

    FAIL2BAN_STATUS="$(run_target_cmd "fail2ban-client ping && fail2ban-client status sshd" || true)"
    if [[ "$FAIL2BAN_STATUS" != *"Server replied: pong"* || "$FAIL2BAN_STATUS" != *"Jail list"* ]]; then
        SECURITY_WARNINGS+=("fail2ban is not responding with the expected sshd jail.")
    fi

    NFT_EGRESS="$(run_target_cmd "nft list chain inet admiral_egress output" || true)"
    if [[ "$NFT_EGRESS" != *"reject"* ]]; then
        SECURITY_WARNINGS+=("The managed nftables egress reject policy is not active.")
    fi

    FW_SERVICES="$(run_target_cmd "firewall-cmd --zone=public --list-services")"
    FW_PORTS="$(run_target_cmd "firewall-cmd --permanent --zone=public --list-ports")"
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
  sudo admiral_https_setup

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

if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    cat <<EOF

***** REMINDER *****
Harbor PayPal mode is 'sandbox'. To accept real payments:
  1. Set HARBOR_PAYPAL_MODE=live in /etc/admiral/harbor.env
  2. Set HARBOR_PAYPAL_BASE_URL=https://api-m.paypal.com
  3. Configure HARBOR_PAYPAL_CLIENT_ID and HARBOR_PAYPAL_CLIENT_SECRET
See https://admiral-project.github.io for PayPal setup guide.
***** REMINDER *****
EOF
fi
