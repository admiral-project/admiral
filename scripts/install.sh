#!/usr/bin/env bash
# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# --- helpers ---
die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
usage() {
    cat <<'EOF'
Usage:
  admiral_install --single-node [--public-ip <public-ip>]
  admiral_install --admin-node --public-ip <public-ip>
  admiral_install --worker-node --public-ip <public-ip>
  admiral_install --portal-node --public-ip <public-ip>

Options:
  --single-node       Install all single-node components on one host.
  --admin-node        Install control plane components only.
  --worker-node       Install worker components only.
  --portal-node       Install portal components only.
  --node-id           Set a custom node ID (default: hostname).
  --public-ip         Set the public IP address of the node being configured.
  --admin-endpoint    Override the admin endpoint for spoke installs.
  --ssh-user          SSH user for remote spoke configuration (default: root).
  --ssh-key           SSH private key for remote spoke configuration.
  -h, --help          Show this help message.

Note: --worker-node and --portal-node are mutually exclusive by design.
      A single host cannot run both roles. Deploy separate nodes if both
      worker and portal capabilities are required.
EOF
}

INSTALL_MODE=""
INSTALL_NODE_ID=""
INSTALL_PUBLIC_IP=""
INSTALL_ADMIN_ENDPOINT=""
INSTALL_TARGET_SSH_USER="root"
INSTALL_TARGET_SSH_KEY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --single-node)
            [[ -z "$INSTALL_MODE" ]] || die "Only one installation mode may be selected."
            INSTALL_MODE="single-node"
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

[[ -n "$INSTALL_MODE" ]] || die "An installation mode is required. Use --single-node, --admin-node, --worker-node or --portal-node."
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" ]]; then
    if [[ -z "$INSTALL_PUBLIC_IP" ]]; then
        INSTALL_PUBLIC_IP="127.0.0.1"
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
        INSTALL_ADMIN_ENDPOINT="${ADMIRAL_PUBLIC_IP:-}"
    fi
    [[ -n "$INSTALL_ADMIN_ENDPOINT" ]] || die "Worker and portal nodes require an admin endpoint from /etc/admiral/install.env or --admin-endpoint."
    [[ -f /etc/admiral/secrets ]] || die "Spoke installs must run from an admin host with /etc/admiral/secrets available."
    [[ -f /etc/admiral/tls/ca.pem ]] || die "Spoke installs must run from an admin host with /etc/admiral/tls/ca.pem available."
    [[ -f /var/lib/admiral/know_host.yaml ]] || die "Spoke installs must run from an admin host with /var/lib/admiral/know_host.yaml available."
    [[ -n "$INSTALL_TARGET_SSH_KEY" ]] || die "Spoke installs require an SSH key. Use --ssh-key or install a default root key."
fi

# --- 0b. worker and portal roles are mutually exclusive per host ---
# A single host cannot run both admiral-fleet (worker) and admiral-harbor (portal).
# Each role requires its own WireGuard IP, dedicated system resources, and
# a distinct service footprint. Deploy separate nodes if both are needed.
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "admin-node" ]]; then
    if systemctl is-active --quiet admiral-harbor 2>/dev/null && [[ "$INSTALL_MODE" == "admin-node" ]]; then
        die "Host already has admiral-harbor (portal role) running. --admin-node and --portal-node are mutually exclusive per host."
    fi
    if systemctl is-active --quiet admiral-fleet 2>/dev/null && [[ "$INSTALL_MODE" == "admin-node" ]]; then
        die "Host already has admiral-fleet (worker role) running. --admin-node and --worker-node are mutually exclusive per host."
    fi
elif [[ "$INSTALL_MODE" == "worker-node" ]]; then
    ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "systemctl is-active --quiet admiral-harbor" 2>/dev/null && \
        die "Target host already runs admiral-harbor (portal role). --worker-node and --portal-node are mutually exclusive per host."
elif [[ "$INSTALL_MODE" == "portal-node" ]]; then
    ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" \
        "systemctl is-active --quiet admiral-fleet" 2>/dev/null && \
        die "Target host already runs admiral-fleet (worker role). --worker-node and --portal-node are mutually exclusive per host."
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
    *)
        die "Unsupported OS: $ID. Supported: RHEL, CentOS Stream, Rocky Linux, AlmaLinux 10."
        ;;
esac

# --- 3. verify Python 3 ---
command -v python3 >/dev/null 2>&1 || die "Python 3 is required but not installed."

# --- 4. enable EPEL (Enterprise Linux only) ---
if [[ "$ID" != "fedora" ]]; then
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

# --- 8. build extra-vars ---
EXTRA_VARS="admiral_install_mode=$INSTALL_MODE"
if [[ -n "$INSTALL_NODE_ID" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_node_id=$INSTALL_NODE_ID"
fi
if [[ -n "$INSTALL_PUBLIC_IP" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_public_ip=$INSTALL_PUBLIC_IP"
fi
# fleet and harbor are mutually exclusive per host: fleet_node_role is either 'worker' or 'portal'.
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_node_role=$( [[ "$INSTALL_MODE" == "portal-node" ]] && echo 'portal' || echo 'worker' )"
    EXTRA_VARS="$EXTRA_VARS admiral_admin_endpoint=$INSTALL_ADMIN_ENDPOINT"
    EXTRA_VARS="$EXTRA_VARS admiral_admin_wireguard_ip=10.99.0.1"
    EXTRA_VARS="$EXTRA_VARS admiral_wireguard_hub_endpoint=$INSTALL_ADMIN_ENDPOINT"
    EXTRA_VARS="$EXTRA_VARS admiral_bootstrap_from_controller=true"
fi

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
      ansible_ssh_common_args: -o StrictHostKeyChecking=accept-new
EOF
        ANSIBLE_LOCAL_TEMP="$ANSIBLE_LOCAL_TEMP" \
        ANSIBLE_REMOTE_TEMP="$ANSIBLE_REMOTE_TEMP" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        ansible-playbook \
            "$ANSIBLE_DIR/site.yml" \
            -i "$TMP_INVENTORY" \
            --limit target \
            --extra-vars "$EXTRA_VARS"
    else
        ANSIBLE_LOCAL_TEMP="$ANSIBLE_LOCAL_TEMP" \
        ANSIBLE_REMOTE_TEMP="$ANSIBLE_REMOTE_TEMP" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        ansible-playbook \
            "$ANSIBLE_DIR/site.yml" \
            -i "$ANSIBLE_DIR/inventory/localhost.yml" \
            --extra-vars "$EXTRA_VARS"
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
    SPOKE_KEY=$(ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "wg pubkey < /etc/wireguard/admiral.key" 2>/dev/null || true)
    SPOKE_NODE_ID="${INSTALL_NODE_ID:-$(ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "cat /etc/admiral/fleet.env 2>/dev/null | grep ADMIRAL_FLEET_NODE_ID | cut -d= -f2" 2>/dev/null || true)}"
    if [[ -n "$SPOKE_KEY" && -n "$SPOKE_NODE_ID" ]]; then
        SPOKE_WG_IP=$(admiralctl nodes list --output json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for n in data if isinstance(data, list) else data.get('nodes', []):
    if n.get('node_id') == '$SPOKE_NODE_ID' or n.get('id') == '$SPOKE_NODE_ID':
        sys.stdout.write(n.get('wireguard_ip', n.get('wg_ip', '')))
        break
" 2>/dev/null || true)
        if [[ -z "$SPOKE_WG_IP" ]]; then
            SPOKE_WG_IP="10.99.0.2"
            warn "Could not resolve wireguard_ip from admirald; falling back to $SPOKE_WG_IP"
        fi
        wg set wg-admiral peer "$SPOKE_KEY" allowed-ips "${SPOKE_WG_IP}/32" persistent-keepalive 25
        wg-quick save wg-admiral
        info "WireGuard peer added for spoke node ($SPOKE_WG_IP) on hub."
    else
        warn "Could not read spoke WireGuard public key or node ID. Peer not added on hub."
    fi
fi

# --- 11. verify core runtime ---
if [[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "worker-node" ]]; then
    if [[ "$INSTALL_MODE" == "worker-node" ]]; then
        PODMAN_VER=$(ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "podman version --format '{{.Version}}'" 2>/dev/null || echo "0")
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
        REQUIRED_SERVICES=(postgresql caddy admirald cockpit.socket)
        ;;
    worker-node)
        REQUIRED_SERVICES=(admiral-fleet)
        ;;
    portal-node)
        REQUIRED_SERVICES=(postgresql admiral-harbor)
        ;;
esac

for service in "${REQUIRED_SERVICES[@]}"; do
    if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
        ssh -i "$INSTALL_TARGET_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "systemctl is-active --quiet '$service'" || die "Service $service is not active after remote setup."
    else
        systemctl is-active --quiet "$service" || die "Service $service is not active after setup."
    fi
done

# --- 12. final message ---
cat <<EOF

Admiral installation completed.

Installation mode:
  $INSTALL_MODE

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
