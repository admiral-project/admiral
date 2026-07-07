#!/usr/bin/env bash
# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# --- helpers ---
die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
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
detect_non_loopback_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')
    fi
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i !~ /^127\./) { print $i; exit }}')
    fi
    [[ -n "$ip" ]] && printf '%s\n' "$ip"
}
usage() {
    cat <<'EOF'
Usage:
  admiral_install --single-node [--public-ip <public-ip>]
  admiral_install --dev-node [--public-ip <public-ip>]
  admiral_install --admin-node [--public-ip <public-ip>]
  admiral_install --worker-node --public-ip <public-ip> [--wireguard-ip <wireguard-ip>]
  admiral_install --portal-node --public-ip <public-ip> [--wireguard-ip <wireguard-ip>]

Options:
  --single-node       Install all single-node components on one host.
  --dev-node          Evaluation mode: single-node with relaxed firewall/bindings.
  --admin-node        Install control plane components only.
  --worker-node       Install worker components only.
  --portal-node       Install portal components only.
  --node-id           Set a custom node ID (default: hostname).
  --public-ip         Set the public IP address of the node being configured.
  --wireguard-ip      Set the WireGuard IP address for a spoke node.
  --admin-endpoint    Override the admin endpoint for spoke installs.
  --ssh-user          SSH user for remote spoke configuration (default: root).
  --ssh-key           SSH private key for remote spoke configuration.
  --ssh-fingerprint   Expected SSH host key fingerprint (SHA256:...) for verification.
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
INSTALL_TARGET_SSH_KEY=""
INSTALL_SSH_FINGERPRINT=""

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
            INSTALL_NODE_ID="$1"
            ;;
        --public-ip)
            shift
            INSTALL_PUBLIC_IP="$1"
            ;;
        --wireguard-ip)
            shift
            INSTALL_WIREGUARD_IP="$1"
            ;;
        --admin-endpoint)
            shift
            INSTALL_ADMIN_ENDPOINT="$1"
            ;;
        --ssh-user|--admin-ssh-user)
            shift
            INSTALL_TARGET_SSH_USER="$1"
            ;;
        --ssh-key|--admin-ssh-key)
            shift
            INSTALL_TARGET_SSH_KEY="$1"
            ;;
        --ssh-fingerprint)
            shift
            INSTALL_SSH_FINGERPRINT="$1"
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

[[ -n "$INSTALL_MODE" ]] || die "An installation mode is required. Use --single-node, --dev-node, --admin-node, --worker-node or --portal-node."
if [[ "$INSTALL_MODE" == "single-node" && -z "$INSTALL_PUBLIC_IP" ]]; then
    INSTALL_PUBLIC_IP="127.0.0.1"
fi
if [[ "$INSTALL_MODE" == "admin-node" && -z "$INSTALL_PUBLIC_IP" ]]; then
    INSTALL_PUBLIC_IP="$(detect_non_loopback_ip || true)"
    if [[ -z "$INSTALL_PUBLIC_IP" ]]; then
        die "Could not detect a non-loopback admin public IP. Use --public-ip."
    fi
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
        # shellcheck disable=SC1091
        source /etc/admiral/install.env
        if ! is_loopback_host "${ADMIRAL_PUBLIC_IP:-}"; then
            INSTALL_ADMIN_ENDPOINT="${ADMIRAL_PUBLIC_IP:-}"
        fi
    fi
    [[ -n "$INSTALL_ADMIN_ENDPOINT" ]] || die "Worker and portal nodes require an admin endpoint from /etc/admiral/install.env or --admin-endpoint."
    [[ -f /etc/admiral/secrets ]] || die "Spoke installs must run from an admin host with /etc/admiral/secrets available."
    [[ -f /etc/admiral/tls/ca.pem ]] || die "Spoke installs must run from an admin host with /etc/admiral/tls/ca.pem available."
    [[ -f /var/lib/admiral/know_host.yaml ]] || die "Spoke installs must run from an admin host with /var/lib/admiral/know_host.yaml available."
    [[ -n "$INSTALL_TARGET_SSH_KEY" ]] || die "Spoke installs require an SSH key. Use --ssh-key or install a default root key."
fi

# --- 0c. populate known_hosts before first SSH connection ---
# ssh-keyscan is read-only and transmits no credentials.
# This prevents MITM attacks during spoke bootstrap.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    info "Retrieving SSH host key for $INSTALL_PUBLIC_IP..."
    KEYSCAN_OUTPUT=$(ssh-keyscan "$INSTALL_PUBLIC_IP" 2>/dev/null) || \
        die "Failed to retrieve SSH host key for $INSTALL_PUBLIC_IP. Ensure SSH is running on the target host."
    echo "$KEYSCAN_OUTPUT" >> ~/.ssh/known_hosts
    if [[ -n "$INSTALL_SSH_FINGERPRINT" ]]; then
        FOUND_FINGERPRINT=$(echo "$KEYSCAN_OUTPUT" | ssh-keygen -lf - 2>/dev/null | head -1)
        info "Expected fingerprint: $INSTALL_SSH_FINGERPRINT"
        info "Received: $FOUND_FINGERPRINT"
        if ! echo "$FOUND_FINGERPRINT" | grep -qF "$INSTALL_SSH_FINGERPRINT"; then
            die "SSH host key fingerprint mismatch for $INSTALL_PUBLIC_IP. Aborting."
        fi
        info "SSH host key fingerprint verified."
    fi
fi

# --- 0b. worker and portal roles are mutually exclusive per host ---
# A remote spoke host cannot run both admiral-fleet (worker) and
# admiral-harbor (portal). Combined worker+portal support exists only
# in --single-node on the local host.
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" ]]; then
    if systemctl is-active --quiet admiral-harbor 2>/dev/null && [[ "$INSTALL_MODE" == "admin-node" ]]; then
        die "Host already has admiral-harbor (portal role) running. --admin-node and --portal-node are mutually exclusive per host."
    fi
    if systemctl is-active --quiet admiral-fleet 2>/dev/null && [[ "$INSTALL_MODE" == "admin-node" ]]; then
        die "Host already has admiral-fleet (worker role) running. --admin-node and --worker-node are mutually exclusive per host."
    fi
elif [[ "$INSTALL_MODE" == "worker-node" ]]; then
    ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes \
        "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "systemctl is-active --quiet admiral-harbor" 2>/dev/null && \
        die "Target host already runs admiral-harbor (portal role). Remote worker-node and portal-node installs are mutually exclusive; use --single-node only for combined local roles."
elif [[ "$INSTALL_MODE" == "portal-node" ]]; then
    ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes \
        "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "systemctl is-active --quiet admiral-fleet" 2>/dev/null && \
        die "Target host already runs admiral-fleet (worker role). Remote worker-node and portal-node installs are mutually exclusive; use --single-node only for combined local roles."
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

dnf clean all 2>/dev/null || true

# --- 7. install ansible-core and admiral-common ---
if ! rpm -q ansible-core >/dev/null 2>&1; then
    info "Installing ansible-core..."
    dnf install -y ansible-core
fi

# Install admiral-common first so its playbooks are on disk
if ! rpm -q admiral-common >/dev/null 2>&1; then
    info "Installing admiral-common..."
    dnf install -y admiral-common
fi

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

# --- 7c. read secrets from admin (never copied to spokes) ---
# Extract only the secrets each spoke type needs and pass them as extra-vars.
SECRETS_ADMIRAL_TOKEN=""
SECRETS_TASK_ENCRYPTION_KEY=""
SECRETS_HARBOR_SECRET_KEY=""
SECRETS_HARBOR_ENCRYPTION_KEY=""
SECRETS_HARBOR_POSTGRES_PASSWORD=""
SECRETS_HARBOR_BOOTSTRAP_USER=""
SECRETS_HARBOR_BOOTSTRAP_PASSWORD=""
SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD=""
SECRETS_HARBOR_API_TOKEN=""
if [[ "$INSTALL_MODE" == "worker-node" ]]; then
    SECRETS_ADMIRAL_TOKEN=$(read_admiral_secret "ADMIRAL_ADMIN_TOKEN") || true
    SECRETS_TASK_ENCRYPTION_KEY=$(read_admiral_secret "ADMIRAL_TASK_ENCRYPTION_KEY") || true
fi
if [[ "$INSTALL_MODE" == "portal-node" ]]; then
    SECRETS_ADMIRAL_TOKEN=$(read_admiral_secret "ADMIRAL_ADMIN_TOKEN") || true
    SECRETS_HARBOR_SECRET_KEY=$(read_admiral_secret "HARBOR_SECRET_KEY") || true
    SECRETS_HARBOR_ENCRYPTION_KEY=$(read_admiral_secret "HARBOR_ENCRYPTION_KEY") || true
    SECRETS_HARBOR_POSTGRES_PASSWORD=$(read_admiral_secret "ADMIRAL_POSTGRES_PASSWORD") || true
    SECRETS_HARBOR_BOOTSTRAP_USER=$(read_admiral_secret "HARBOR_BOOTSTRAP_USER") || true
    SECRETS_HARBOR_BOOTSTRAP_PASSWORD=$(read_admiral_secret "HARBOR_BOOTSTRAP_PASSWORD") || true
    SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD=$(read_admiral_secret "HARBOR_LEGACY_ADMIN_PASSWORD") || true
    SECRETS_HARBOR_API_TOKEN=$(read_admiral_secret "ADMIRAL_HARBOR_API_TOKEN") || true
fi

# --- 8. build extra-vars as JSON (prevents injection via --node-id) ---
EXTRA_VARS_JSON=$(
    INSTALL_MODE="$INSTALL_MODE" \
    INSTALL_DEV_MODE="$INSTALL_DEV_MODE" \
    INSTALL_NODE_ID="$INSTALL_NODE_ID" \
    INSTALL_PUBLIC_IP="$INSTALL_PUBLIC_IP" \
    INSTALL_WIREGUARD_IP="$INSTALL_WIREGUARD_IP" \
    INSTALL_ADMIN_ENDPOINT="$INSTALL_ADMIN_ENDPOINT" \
    SECRETS_ADMIRAL_TOKEN="$SECRETS_ADMIRAL_TOKEN" \
    SECRETS_TASK_ENCRYPTION_KEY="$SECRETS_TASK_ENCRYPTION_KEY" \
    SECRETS_HARBOR_SECRET_KEY="$SECRETS_HARBOR_SECRET_KEY" \
    SECRETS_HARBOR_ENCRYPTION_KEY="$SECRETS_HARBOR_ENCRYPTION_KEY" \
    SECRETS_HARBOR_POSTGRES_PASSWORD="$SECRETS_HARBOR_POSTGRES_PASSWORD" \
    SECRETS_HARBOR_BOOTSTRAP_USER="$SECRETS_HARBOR_BOOTSTRAP_USER" \
    SECRETS_HARBOR_BOOTSTRAP_PASSWORD="$SECRETS_HARBOR_BOOTSTRAP_PASSWORD" \
    SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD="$SECRETS_HARBOR_LEGACY_ADMIN_PASSWORD" \
    SECRETS_HARBOR_API_TOKEN="$SECRETS_HARBOR_API_TOKEN" \
    python3 -c '
import json, os

d = {"admiral_install_mode": os.environ["INSTALL_MODE"]}

if os.environ.get("INSTALL_DEV_MODE") == "true":
    d["admiral_dev_mode"] = True

if os.environ.get("INSTALL_NODE_ID"):
    d["fleet_node_id"] = os.environ["INSTALL_NODE_ID"]

if os.environ.get("INSTALL_PUBLIC_IP"):
    d["fleet_public_ip"] = os.environ["INSTALL_PUBLIC_IP"]

if os.environ.get("INSTALL_WIREGUARD_IP"):
    d["admiral_wireguard_ip"] = os.environ["INSTALL_WIREGUARD_IP"]

token = os.environ.get("SECRETS_ADMIRAL_TOKEN", "")
if token:
    d["admiral_admin_token_value"] = token

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

mode = os.environ["INSTALL_MODE"]
if mode in ("worker-node", "portal-node"):
    d["fleet_node_role"] = "portal" if mode == "portal-node" else "worker"
    d["admiral_admin_endpoint"] = os.environ["INSTALL_ADMIN_ENDPOINT"]
    d["admiral_admin_wireguard_ip"] = "10.99.0.1"
    d["admiral_wireguard_hub_endpoint"] = os.environ["INSTALL_ADMIN_ENDPOINT"]
    d["admiral_bootstrap_from_controller"] = True

if mode in ("admin-node", "single-node"):
    d["admiral_wireguard_ip"] = "10.99.0.1"

print(json.dumps(d))
'
)

# --- 9. run official playbook ---
# The playbook handles the rest: packages, configuration, services
info "Running Admiral configuration playbook for mode: $INSTALL_MODE"
ANSIBLE_DIR="/usr/share/admiral/ansible"
if [[ -d "$ANSIBLE_DIR" ]]; then
    ANSIBLE_LOCAL_TEMP=/tmp/ansible-local
    ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote
    ANSIBLE_GALAXY_CACHE_DIR=/tmp/ansible-galaxy-cache
    if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
        TMP_INVENTORY="$(mktemp).yml"
        cat > "$TMP_INVENTORY" <<EOF
all:
  hosts:
    target:
      ansible_host: ${INSTALL_PUBLIC_IP}
      ansible_user: ${INSTALL_TARGET_SSH_USER}
      ansible_ssh_private_key_file: ${INSTALL_TARGET_SSH_KEY}
      ansible_python_interpreter: /usr/bin/python3
      ansible_ssh_common_args: -o StrictHostKeyChecking=yes
EOF
        ANSIBLE_LOCAL_TEMP="$ANSIBLE_LOCAL_TEMP" \
        ANSIBLE_REMOTE_TEMP="$ANSIBLE_REMOTE_TEMP" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        ansible-playbook \
            "$ANSIBLE_DIR/site.yml" \
            -i "$TMP_INVENTORY" \
            --limit target \
            --extra-vars "$EXTRA_VARS_JSON"
    else
        ANSIBLE_LOCAL_TEMP="$ANSIBLE_LOCAL_TEMP" \
        ANSIBLE_REMOTE_TEMP="$ANSIBLE_REMOTE_TEMP" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        ansible-playbook \
            "$ANSIBLE_DIR/site.yml" \
            -i "$ANSIBLE_DIR/inventory/localhost.yml" \
            --extra-vars "$EXTRA_VARS_JSON"
    fi
else
    die "Ansible playbook directory not found at $ANSIBLE_DIR"
fi

# --- 10. persist local installer state for future spoke bootstraps ---
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" ]]; then
    install -d -m 0750 /etc/admiral
    cat > /etc/admiral/install.env <<EOF
ADMIRAL_PUBLIC_IP=${INSTALL_PUBLIC_IP}
EOF
    chmod 0640 /etc/admiral/install.env
fi

# --- 10b. exchange WireGuard peers for spoke installs ---
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    info "Exchanging WireGuard peers between hub and spoke..."
    SPOKE_KEY=$(ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "wg pubkey < /etc/wireguard/admiral.key" 2>/dev/null || true)
    SPOKE_NODE_ID="${INSTALL_NODE_ID:-$(ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "grep -hE '^(ADMIRAL_FLEET_NODE_ID|HARBOR_NODE_ID)=' /etc/admiral/*.env 2>/dev/null | tail -n1 | cut -d= -f2-" 2>/dev/null || true)}"
    if [[ -z "$SPOKE_KEY" ]]; then
        die "Could not read the spoke WireGuard public key after installation."
    fi
    if [[ -z "$SPOKE_NODE_ID" ]]; then
        die "Could not resolve the spoke node ID from --node-id or /etc/admiral/*.env after installation."
    fi
    if [[ -n "$SPOKE_KEY" && -n "$SPOKE_NODE_ID" ]]; then
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
    fi
fi

# --- 11. verify core runtime ---
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "worker-node" ]]; then
    if [[ "$INSTALL_MODE" == "worker-node" ]]; then
        PODMAN_VER=$(ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "podman version --format '{{.Version}}'" 2>/dev/null || echo "0")
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
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-fleet admiral-flagship admiral-harbor cockpit.socket)
        ;;
    admin-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-flagship cockpit.socket)
        ;;
    worker-node)
        REQUIRED_SERVICES=(admiral-fleet)
        ;;
    portal-node)
        REQUIRED_SERVICES=(postgresql admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer)
        ;;
esac

for service in "${REQUIRED_SERVICES[@]}"; do
    if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
        ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "systemctl is-active --quiet '$service'" || die "Service $service is not active after remote setup."
    else
        systemctl is-active --quiet "$service" || die "Service $service is not active after setup."
    fi
done

# --- 11b. security checklist (warning-only, skipped in dev mode) ---
if [[ "$INSTALL_DEV_MODE" != "true" ]]; then
    SECURITY_WARNINGS=()

    run_target_cmd() {
        local cmd="$1"
        if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
            ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes \
                "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "$cmd" 2>/dev/null || true
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
    if [[ "$SSHD_EFFECTIVE" != *"passwordauthentication no"* ]]; then
        SECURITY_WARNINGS+=("sshd password authentication is not disabled.")
    fi
    if [[ "$SSHD_EFFECTIVE" != *"maxauthtries 3"* ]]; then
        SECURITY_WARNINGS+=("sshd MaxAuthTries differs from recommended value 3.")
    fi

    FW_SERVICES="$(run_target_cmd "firewall-cmd --zone=public --list-services")"
    case "$INSTALL_MODE" in
        single-node|admin-node)
            if [[ "$FW_SERVICES" != *"ssh"* || "$FW_SERVICES" != *"http"* || "$FW_SERVICES" != *"https"* ]]; then
                SECURITY_WARNINGS+=("Expected public services ssh/http/https for admin profile not fully present.")
            fi
            ;;
        worker-node|portal-node)
            if [[ "$FW_SERVICES" != *"ssh"* ]]; then
                SECURITY_WARNINGS+=("Expected public service ssh is missing on spoke profile.")
            fi
            if [[ "$FW_SERVICES" == *"http"* || "$FW_SERVICES" == *"https"* ]]; then
                SECURITY_WARNINGS+=("Spoke profile exposes http/https in public zone.")
            fi
            ;;
    esac

    if [[ ${#SECURITY_WARNINGS[@]} -gt 0 ]]; then
        warn "----------------------------------------------------------------"
        warn "SECURITY CHECKLIST WARNINGS (non-blocking)"
        warn "Installer assumes a fresh VPS with no unrelated services."
        for warning_item in "${SECURITY_WARNINGS[@]}"; do
            warn "- $warning_item"
        done
        warn "Address these warnings before production deployment."
        warn "----------------------------------------------------------------"
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
