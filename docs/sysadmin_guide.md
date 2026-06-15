# Admiral System Administrator Guide

This guide provides a comprehensive overview of the operation, configuration, and maintenance of an Admiral platform in single-node and multi-node deployments.

## 1. Admiral Components

Admiral consists of five main services that work together to provide a billing-aware PaaS platform:

- **admirald**: The control plane (the "brain" of the system). It manages global state, the provisioning API, administrative users, and coordinates tasks for the workers.
- **admiralctl**: Command-line interface (CLI) for administrators. It allows managing nodes, users, applications, and instances from the terminal.
- **admiral-fleet**: The worker runtime agent. It executes instructions from `admirald` on the local host, managing the lifecycle of containers and monitoring resources.
- **admiral-flagship**: Administrative web console. A graphical interface for the platform operator to manage infrastructure, catalogs, and monitoring.
- **admiral-harbor**: Customer and billing portal. This is where end-users register, select plans, manage their subscriptions, and their own instances.

## 2. System Dependencies

Admiral leverages standard Linux technologies to ensure stability and security:

- **Podman (>= 5.0)**: Native Linux container engine, used for rootless execution of workloads.
- **Quadlet**: A Podman/Systemd extension that allows defining containers as native systemd units.
- **Systemd**: Service manager that orchestrates the startup, persistence, and logs of all components and applications.
- **PostgreSQL (>= 16)**: Relational database where platform state, the task queue, and customer data are stored.
- **Caddy Server**: Web server and reverse proxy that automatically manages TLS termination (HTTPS) and dynamic routing to applications.
- **SELinux**: Required in `enforcing` mode to guarantee security isolation between containers and the host.

## 3. Rootless Model

Admiral implements a **rootless execution model by design**. This means:

- Customer applications **never** run as root.
- The `admiral-fleet` agent uses a dedicated user (typically `admiral-apps`) to launch containers.
- `loginctl enable-linger` is used to ensure that rootless user services persist after system reboot without an active session.
- Isolation is reinforced through User Namespaces and SELinux policies.

## 4. Setup with scripts/install.sh

The recommended command for a quick single-node installation is:

```bash
sudo bash scripts/install.sh --single-node
```

### Created Files
The installation organizes configuration in standard paths:

- `/etc/admiral/secrets`: Master file containing all keys and passwords.
- `/etc/admirald.ini`: Main configuration for the control plane.
- `/etc/admiral/fleet.env`: Environment variables for the worker agent.
- `/etc/admiral/flagship.env`: Configuration for the admin console.
- `/etc/admiral/harbor.env`: Configuration for the customer portal.
- `/etc/admiral/tls/`: Internal certificates generated during setup.
- `/var/lib/admiral/`: Data directory for instances and persistent files.

### Secrets Management
The `/etc/admiral/secrets` file is **critical**. It contains:
- `ADMIRAL_POSTGRES_PASSWORD`: Database access.
- `ADMIRAL_SHARED_TOKEN`: Communication token between components.
- `ADMIRAL_SECRETS_KEY`: Key for encrypting secrets at rest.
- Bootstrap credentials for Flagship and Harbor.

**IMPORTANT:** Back up this file to a secure external location immediately after installation.

### S3 Backup Configuration
To allow instances to perform external backups, configure the S3 variables in `/etc/admiral/fleet.env`:

```bash
ADMIRAL_STORAGE_ENDPOINT=https://s3.region.amazonaws.com
ADMIRAL_STORAGE_REGION=us-east-1
ADMIRAL_STORAGE_BUCKET=my-backup-bucket
ADMIRAL_STORAGE_ACCESS_KEY=YOUR_ACCESS_KEY
ADMIRAL_STORAGE_SECRET_KEY=YOUR_SECRET_KEY
```

### SMTP Configuration (Harbor)
For Harbor to send confirmation emails and notifications, edit `/etc/admiral/harbor.smtp.env` (or add to `harbor.env`):

```bash
HARBOR_SMTP_HOST=smtp.example.com
HARBOR_SMTP_PORT=587
HARBOR_SMTP_USERNAME=user@example.com
HARBOR_SMTP_PASSWORD=secure_password
HARBOR_SMTP_USE_TLS=true
```
Restart the service after the change: `systemctl restart admiral-harbor`.

## 5. HTTPS and DNS Configuration

The `scripts/admiral_https_setup.py` script automates obtaining SSL certificates.

### Required DNS Records
Before running the script, ensure the following A records point to the server's public IP:

1. `admiral.<domain>`: Base host.
2. `*.admiral.<domain>`: For subdomains like `flagship`, `portal`, `cockpit`.
3. `*.apps.admiral.<domain>`: For all deployed application instances.

### Manual Wildcard Challenge
To support an unlimited number of application subdomains (`*.apps`), Admiral requires a Wildcard certificate obtained via **DNS-01 challenge**:

1. Run: `sudo admiral_https_setup --domain admiral.example.com`.
2. The script will invoke `certbot` in manual mode.
3. You will be asked to create a **TXT** record in your DNS named `_acme-challenge.apps.admiral.example.com`.
4. Wait for propagation and press Enter to continue.
5. The script will automatically configure Caddy and `admirald` to use this certificate.

## 6. Maintenance and Backups

### Full System Backup
For a complete backup, you must capture three elements:

1. **Secrets and Configuration:**
   ```bash
   tar -czf admiral-config-backup.tar.gz /etc/admiral/ /etc/admirald.ini
   ```
2. **Databases:**
   ```bash
   pg_dumpall -U postgres > admiral-db-backup.sql
   ```
3. **Instance Data:**
   ```bash
   tar -czf admiral-data-backup.tar.gz /var/lib/admiral/
   ```

### Wildcard DNS Maintenance (*.apps)
Certificates obtained via manual DNS-01 often require intervention for renewal unless a specific Certbot DNS plugin (like `certbot-dns-cloudflare`) is used.
If automatic renewal fails, re-run `admiral_https_setup` to update the certificate using the TXT challenge.

### System Updates
To keep Admiral up to date:

1. **Update RPM packages:**
   ```bash
   dnf clean all
   dnf update admiral-*
   ```
2. **Apply database migrations:**
   Services apply migrations automatically on startup. If there are major changes, check the logs:
   ```bash
   journalctl -u admirald -f
   ```
3. **Restart services:**
   ```bash
   systemctl restart admirald admiral-fleet admiral-flagship admiral-harbor
   ```

## 7. Multi-Node Deployment

The full networking architecture is defined in `multi_node_setup_v1.md`.

Admiral supports three node roles:

- **admin** — control plane (admirald, flagship, harbor, caddy, PostgreSQL)
- **worker** — runs workloads (admiral-fleet, podman)
- **portal** — customer portal node (admiral-fleet, future portal services)

### Node Registration

Nodes are registered with admirald using `admiralctl`. The registration command accepts role, WireGuard IP, and public IP:

```bash
admiralctl nodes register \
  --id "node1" \
  --hostname "node1.example.com" \
  --ip "10.0.0.10" \
  --role "worker" \
  --wireguard-ip "10.99.0.2" \
  --public-ip "203.0.113.10"
```

The scheduler only provisions workloads on nodes with role `worker`. Nodes with role `admin` or `portal` are excluded from workload scheduling.

### Adding a Worker Node via Ansible

From the admin node, use Ansible to bootstrap a remote worker:

```bash
ansible-playbook /usr/share/admiral/ansible/site.yml \
  -i workers.yml \
  --extra-vars "admiral_install_mode=worker-node fleet_node_id=worker1 fleet_api_url=https://10.99.0.1:8080 fleet_queue_database_url=postgres://admiral:PASSWORD@10.99.0.1:5432/admiral_queue?sslmode=disable"
```

The playbook will:

1. Install and configure WireGuard VPN
2. Install admiral-fleet
3. Register the node with admirald

### WireGuard VPN

- WireGuard is configured automatically by the `admiral_wireguard` Ansible role.
- Default port: 51820/udp
- Private network: 10.99.0.0/24
- Worker IP pool: 10.99.0.2–10.99.0.99
- Portal IP pool: 10.99.0.100–10.99.0.199

### Install Modes

The installer supports four deployment modes:

| Mode | Components | Use Case |
|---|---|---|
| `--single-node` | All components on one host | Development, small deployments |
| `--admin-node` | Control plane only (admirald, flagship, harbor, caddy, PostgreSQL) | Admin/control node |
| `--worker-node` | Worker agent only (admiral-fleet, podman) | Workload execution node |
| `--portal-node` | Portal agent only (admiral-fleet) | Customer portal node |

Additional flags:

- `--node-id` — custom node identifier (default: hostname)
- `--public-ip` — public IP for remote SSH connectivity
