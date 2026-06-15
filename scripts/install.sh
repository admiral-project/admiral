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
  install.sh --single-node
  install.sh --admin-node
  install.sh --worker-node
  install.sh --portal-node

Options:
  --single-node       Install all single-node components on one host.
  --admin-node        Install control plane components only.
  --worker-node       Install worker components only.
  --portal-node       Install portal components only.
  --node-id           Set a custom node ID (default: hostname).
  --public-ip         Set the public IP address for remote connectivity.
  -h, --help          Show this help message.
EOF
}

INSTALL_MODE=""
INSTALL_NODE_ID=""
INSTALL_PUBLIC_IP=""

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

# --- 1. root check ---
[[ $EUID -eq 0 ]] || die "This script must be run as root."

# --- 2. detect OS ---
if ! source /etc/os-release 2>/dev/null; then
    die "Cannot detect OS. /etc/os-release not found."
fi

case "$ID" in
    rhel|centos|rocky|almalinux)
        MAJOR="${VERSION_ID%%.*}"
        [[ "$MAJOR" -ge 9 ]] || die "Enterprise Linux >= 9 required (got $ID $VERSION_ID)"
        ;;
    fedora)
        ;;
    *)
        die "Unsupported OS: $ID. Supported: RHEL, CentOS Stream, Rocky Linux, AlmaLinux >= 9, Fedora."
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
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_node_role=$( [[ "$INSTALL_MODE" == "portal-node" ]] && echo 'portal' || echo 'worker' )"
fi

# --- 9. run official playbook ---
# The playbook handles the rest: packages, configuration, services
info "Running Admiral configuration playbook for mode: $INSTALL_MODE"
ANSIBLE_DIR="/usr/share/admiral/ansible"
if [[ -d "$ANSIBLE_DIR" ]]; then
    ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
    ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
    ANSIBLE_GALAXY_CACHE_DIR=/tmp/ansible-galaxy-cache \
    ansible-playbook \
        "$ANSIBLE_DIR/site.yml" \
        -i "$ANSIBLE_DIR/inventory/localhost.yml" \
        --extra-vars "$EXTRA_VARS"
else
    die "Ansible playbook directory not found at $ANSIBLE_DIR"
fi

# --- 10. verify core runtime ---
command -v podman >/dev/null 2>&1 || die "Podman was not installed by RPM dependencies."
PODMAN_VER=$(podman version --format '{{.Version}}' 2>/dev/null || echo "0")
info "Podman version: $PODMAN_VER"
if [[ "$(printf '%s\n' "5.0" "$PODMAN_VER" | sort -V | head -1)" != "5.0" ]]; then
    die "Podman >= 5.0 required. Found: $PODMAN_VER"
fi

case "$INSTALL_MODE" in
    single-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-fleet admiral-flagship admiral-harbor cockpit.socket)
        ;;
    admin-node)
        REQUIRED_SERVICES=(postgresql caddy admirald admiral-flagship admiral-harbor cockpit.socket)
        ;;
    worker-node)
        REQUIRED_SERVICES=(admiral-fleet)
        ;;
    portal-node)
        REQUIRED_SERVICES=(admiral-fleet)
        ;;
esac

for service in "${REQUIRED_SERVICES[@]}"; do
    systemctl is-active --quiet "$service" || die "Service $service is not active after setup."
done

# --- 11. final message ---
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
