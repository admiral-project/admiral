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
  admiral_install --single-node --public-ip <public-ip>
  admiral_install --admin-node --public-ip <public-ip>
  admiral_install --worker-node --public-ip <public-ip> --admin-endpoint <admin-endpoint>
  admiral_install --portal-node --public-ip <public-ip> --admin-endpoint <admin-endpoint>

Options:
  --single-node       Install all single-node components on one host.
  --admin-node        Install control plane components only.
  --worker-node       Install worker components only.
  --portal-node       Install portal components only.
  --node-id           Set a custom node ID (default: hostname).
  --public-ip         Set the public IP address for remote connectivity.
  --admin-endpoint    Admin node WireGuard endpoint (required for worker/portal).
  --admin-ssh-user      SSH user for fetching admin bootstrap files (default: root).
  --admin-ssh-key       SSH private key for fetching admin bootstrap files.
  --admin-secrets-file  Path to the admin /etc/admiral/secrets inventory.
  --admin-ca-file       Path to the admin CA certificate PEM.
  --admin-known-hosts-file  Path to the admin /etc/admiral/know_host.yaml inventory.
  -h, --help          Show this help message.
EOF
}

INSTALL_MODE=""
INSTALL_NODE_ID=""
INSTALL_PUBLIC_IP=""
INSTALL_ADMIN_ENDPOINT=""
INSTALL_ADMIN_SSH_USER="root"
INSTALL_ADMIN_SSH_KEY=""
INSTALL_ADMIN_SECRETS_FILE=""
INSTALL_ADMIN_CA_FILE=""
INSTALL_ADMIN_KNOWN_HOSTS_FILE=""

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
        --admin-ssh-user)
            shift
            INSTALL_ADMIN_SSH_USER="$1"
            ;;
        --admin-ssh-key)
            shift
            INSTALL_ADMIN_SSH_KEY="$1"
            ;;
        --admin-secrets-file)
            shift
            INSTALL_ADMIN_SECRETS_FILE="$1"
            ;;
        --admin-ca-file)
            shift
            INSTALL_ADMIN_CA_FILE="$1"
            ;;
        --admin-known-hosts-file)
            shift
            INSTALL_ADMIN_KNOWN_HOSTS_FILE="$1"
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
[[ -n "$INSTALL_PUBLIC_IP" ]] || die "All installation modes require --public-ip."

if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    if [[ -z "$INSTALL_ADMIN_KNOWN_HOSTS_FILE" && -n "$INSTALL_ADMIN_SECRETS_FILE" ]]; then
        INSTALL_ADMIN_KNOWN_HOSTS_FILE="$(dirname "$INSTALL_ADMIN_SECRETS_FILE")/know_host.yaml"
    fi
    if [[ -z "$INSTALL_ADMIN_ENDPOINT" ]]; then
        die "Worker and portal nodes require --admin-endpoint (public IP or hostname of the admin node)."
    fi
    if [[ -z "$INSTALL_ADMIN_SSH_KEY" ]]; then
        if [[ -f /root/.ssh/id_ed25519 ]]; then
            INSTALL_ADMIN_SSH_KEY="/root/.ssh/id_ed25519"
        elif [[ -f /root/.ssh/id_rsa ]]; then
            INSTALL_ADMIN_SSH_KEY="/root/.ssh/id_rsa"
        fi
    fi
    if [[ -z "$INSTALL_ADMIN_SECRETS_FILE" || -z "$INSTALL_ADMIN_CA_FILE" || -z "$INSTALL_ADMIN_KNOWN_HOSTS_FILE" ]]; then
        [[ -n "$INSTALL_ADMIN_SSH_KEY" ]] || die "Worker and portal nodes require --admin-ssh-key or pre-copied admin bootstrap files."
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

# --- 8. import admin bootstrap materials for spoke installs ---
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    if [[ -z "$INSTALL_ADMIN_SECRETS_FILE" || -z "$INSTALL_ADMIN_CA_FILE" || -z "$INSTALL_ADMIN_KNOWN_HOSTS_FILE" ]]; then
        TMP_BOOTSTRAP_DIR="$(mktemp -d)"
        SSH_OPTS=(-i "$INSTALL_ADMIN_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
        info "Fetching Admirald-managed bootstrap files from ${INSTALL_ADMIN_SSH_USER}@${INSTALL_ADMIN_ENDPOINT} using SSH key..."
        scp "${SSH_OPTS[@]}" "${INSTALL_ADMIN_SSH_USER}@${INSTALL_ADMIN_ENDPOINT}:/etc/admiral/secrets" "$TMP_BOOTSTRAP_DIR/secrets"
        scp "${SSH_OPTS[@]}" "${INSTALL_ADMIN_SSH_USER}@${INSTALL_ADMIN_ENDPOINT}:/etc/admiral/tls/ca.pem" "$TMP_BOOTSTRAP_DIR/ca.pem"
        scp "${SSH_OPTS[@]}" "${INSTALL_ADMIN_SSH_USER}@${INSTALL_ADMIN_ENDPOINT}:/etc/admiral/know_host.yaml" "$TMP_BOOTSTRAP_DIR/know_host.yaml"
        INSTALL_ADMIN_SECRETS_FILE="$TMP_BOOTSTRAP_DIR/secrets"
        INSTALL_ADMIN_CA_FILE="$TMP_BOOTSTRAP_DIR/ca.pem"
        INSTALL_ADMIN_KNOWN_HOSTS_FILE="$TMP_BOOTSTRAP_DIR/know_host.yaml"
    fi

    [[ -f "$INSTALL_ADMIN_SECRETS_FILE" ]] || die "Admin secrets file not found: $INSTALL_ADMIN_SECRETS_FILE"
    [[ -f "$INSTALL_ADMIN_CA_FILE" ]] || die "Admin CA file not found: $INSTALL_ADMIN_CA_FILE"
    [[ -f "$INSTALL_ADMIN_KNOWN_HOSTS_FILE" ]] || die "Admin known hosts file not found: $INSTALL_ADMIN_KNOWN_HOSTS_FILE"

    install -d -m 0750 /etc/admiral /etc/admiral/tls
    install -m 0600 "$INSTALL_ADMIN_SECRETS_FILE" /etc/admiral/secrets
    install -m 0644 "$INSTALL_ADMIN_CA_FILE" /etc/admiral/tls/ca.pem
    install -m 0644 "$INSTALL_ADMIN_KNOWN_HOSTS_FILE" /etc/admiral/know_host.yaml
fi

# --- 9. build extra-vars ---
EXTRA_VARS="admiral_install_mode=$INSTALL_MODE"
if [[ -n "$INSTALL_NODE_ID" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_node_id=$INSTALL_NODE_ID"
fi
if [[ -n "$INSTALL_PUBLIC_IP" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_public_ip=$INSTALL_PUBLIC_IP"
fi
if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]; then
    EXTRA_VARS="$EXTRA_VARS fleet_node_role=$( [[ "$INSTALL_MODE" == "portal-node" ]] && echo 'portal' || echo 'worker' )"
    EXTRA_VARS="$EXTRA_VARS admiral_admin_endpoint=$INSTALL_ADMIN_ENDPOINT"
    EXTRA_VARS="$EXTRA_VARS admiral_wireguard_hub_endpoint=$INSTALL_ADMIN_ENDPOINT"
fi

# --- 10. run official playbook ---
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

# --- 11. verify core runtime ---
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
    systemctl is-active --quiet "$service" || die "Service $service is not active after setup."
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
