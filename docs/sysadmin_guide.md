# Admiral Sysadmin Guide

## Multi-node deployment

The full networking architecture is defined in `multi_node_setup_v1.md`.

### Role and dependency table

| Component | Function | Installed on | Depends on |
|-----------|----------|-------------|------------|
| `admiral-common` | Creates `admiral` user, directories, permissions, SELinux contexts | all nodes | `systemd`, `shadow-utils`, `wireguard-tools`, `openssh-clients`, `ansible-core`, `caddy` (files) |
| `postgresql-server` | Platform database (admirald state, queue, harbor) | admin, portal, single | — |
| `caddy` | Public reverse proxy, TLS termination, routing to workloads | admin, single | `admiral-common` (config) |
| `admirald` | Control plane API, operations, task dispatch, scheduling | admin, single | `admiral-common`, `postgresql-server`, `caddy`, `podman` |
| `admiral-fleet` | Worker agent, task execution, Podman rootless containers | worker, single | `admiral-common`, `podman`, `cockpit-bridge` |
| `admiral-flagship` | Admin web console (app/node management) | single | `admiral-common`, `admirald` |
| `admiral-harbor` | Customer portal (signup, app management) | portal, single | `admiral-common`, `postgresql-server`, `cockpit-bridge`, `wireguard-tools` |
| `admiralctl` | CLI for operators | admin (control host) | `admiral-common` |
| `cockpit.socket` | Web-based node monitoring via Cockpit | admin, single | `cockpit-bridge` on worker/portal |
| `wg-quick@wg-admiral` | WireGuard VPN (hub on admin/single, spoke on worker/portal) | all nodes | `wireguard-tools`, `admiral-common` |
| `firewalld` | Per-mode firewall rules (admin: 22/80/443/51820; worker/portal: 22/51820) | all nodes | — |

### Node roles

Admiral supports three node roles:

- **admin** — control plane. Runs admirald, caddy, PostgreSQL, cockpit, WireGuard VPN hub. Does NOT run workloads, flagship, or harbor.
- **worker** — workload execution. Runs admiral-fleet, Podman, cockpit-bridge, WireGuard VPN spoke. No PostgreSQL, no admirald.
- **portal** — customer-facing services. Runs admiral-harbor, PostgreSQL, cockpit-bridge, WireGuard VPN spoke. Does NOT run admirald or admiral-fleet.

Single-node mode combines admin + worker + portal on one host for development and small deployments.

### Monitoring workers via Cockpit

Since Cockpit on the admin node connects to remote hosts over **SSH**, and WireGuard provides a private network between nodes, you can monitor workers and portal by adding them in the Cockpit web UI using their **WireGuard private IP** (e.g. `10.99.0.2`). The SSH connection travels encrypted over the VPN — no need to expose port 9090 on workers. The `cockpit-bridge` package on worker/portal enables full system monitoring (processes, services, logs, storage) via that SSH tunnel.

### Secrets distribution

`/etc/admiral/secrets` on the admin node is the single source of truth for bootstrap secrets. It must be backed up securely.

Secrets from this file are propagated to service-specific env files on each node as needed:

| Secret | Stored in admin | Exposed to worker | Exposed to portal |
|--------|:--------------:|:-----------------:|:-----------------:|
| `ADMIRAL_POSTGRES_PASSWORD` | `/etc/admiral/secrets` | via queue DB URL in `fleet.env` | — |
| `ADMIRAL_SHARED_TOKEN` | `/etc/admiral/secrets` | `fleet.env` | `harbor.env` |
| `ADMIRAL_SECRETS_KEY` | `/etc/admiral/secrets` | — | — |
| `FLAGSHIP_SECRET_KEY` | `/etc/admiral/secrets` | — | — |
| `FLAGSHIP_BOOTSTRAP_USER` / `FLAGSHIP_BOOTSTRAP_PASSWORD` | `/etc/admiral/secrets` | — | — |
| `HARBOR_SECRET_KEY` | `/etc/admiral/secrets` | — | `harbor.env` |
| `HARBOR_ENCRYPTION_KEY` | `/etc/admiral/secrets` | — | `harbor.env` |
| `HARBOR_BOOTSTRAP_USER` / `HARBOR_BOOTSTRAP_PASSWORD` | `/etc/admiral/secrets` | — | — |
| `COCKPIT_ADMIN_USER` / `COCKPIT_ADMIN_PASSWORD` | `/etc/admiral/secrets` | — | — |

Workers receive only the shared token and the queue database URL (which contains the PG password embedded). Portal receives only the shared token and harbor encryption secrets.

**What is NOT propagated**: `ADMIRAL_SECRETS_KEY`, `FLAGSHIP_*`, bootstrap admin credentials, cockpit admin credentials. These remain exclusively on the admin node.

### Adding a worker node

From the admin node, use Ansible to bootstrap a remote worker:

```bash
ansible-playbook /usr/share/admiral/ansible/site.yml \
  -i /path/to/inventory.yml \
  --extra-vars "admiral_install_mode=worker-node fleet_node_id=worker1 fleet_api_url=https://10.99.0.1:8080 fleet_queue_database_url=postgres://admiral:PASSWORD@10.99.0.1:5432/admiral_queue?sslmode=disable"
```

The playbook will:

1. Install and configure WireGuard VPN
2. Install admiral-fleet
3. Register the node with admirald via `admiralctl nodes register`

### Node registration

```bash
admiralctl nodes register \
  --id "node1" \
  --hostname "node1.example.com" \
  --ip "10.0.0.10" \
  --role "worker" \
  --wireguard-ip "10.99.0.2" \
  --public-ip "203.0.113.10"
```

### Node roles

Each node has a `node_role` field (admin, worker, or portal). The scheduler only provisions workloads on nodes with role `worker`. Nodes with role `admin` or `portal` are excluded from workload scheduling.

### WireGuard VPN

- WireGuard is configured automatically by the `admiral_wireguard` Ansible role.
- Default port: 51820/udp
- Private network: 10.99.0.0/24
- Worker IP pool: 10.99.0.2–10.99.0.99
- Portal IP pool: 10.99.0.100–10.99.0.199

### Backup storage (S3)

All workers share a single S3-compatible bucket for backup storage. Configure it during installation:

```bash
install.sh --admin-node \
  --s3-endpoint https://s3.us-east-1.amazonaws.com \
  --s3-region us-east-1 \
  --s3-bucket admiral-backups \
  --s3-prefix production \
  --s3-access-key AKIDEXAMPLE \
  --s3-secret-key wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

The installer will:

1. Store the S3 endpoint, region, and bucket in admirald's `backup_storage_configs` table.
2. Write `ADMIRAL_AWS_ACCESS_KEY_ID` and `ADMIRAL_AWS_SECRET_ACCESS_KEY` to `/etc/admiral/fleet.env` on worker and single-node hosts.
3. All backup and restore operations will use this shared bucket.

You can also configure or update storage settings post-install via the API:

```bash
curl -X PUT https://admin.example.com/api/admin/settings/backup-storage \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"backend":"s3","endpoint":"https://s3.example.com","bucket":"admiral-backups","region":"us-east-1","access_key_env":"ADMIRAL_AWS_ACCESS_KEY_ID","secret_key_env":"ADMIRAL_AWS_SECRET_ACCESS_KEY","enabled":true}'
```

Supported backends: `s3` and `local` (default). S3-compatible services include MinIO, Wasabi, Backblaze B2, and Cloudflare R2.

Test the storage configuration:

```bash
curl -X POST https://admin.example.com/api/admin/settings/backup-storage/test \
  -H "Authorization: Bearer $TOKEN"
```

---

## Harbor

This section describes the operational behavior of Harbor after installation on a single-node Admiral setup.

### Key files

- `/etc/admiral/harbor.env`
- `/etc/admiral/harbor.smtp.env`
- `/etc/admiral/secrets`
- `/etc/admiral/tls/`

### Customer signup

- Public signup is exposed in the UI at `/auth/register`.
- New signups are created in `pending` state.
- Pending accounts cannot log in or deploy applications.
- A customer becomes active by either of these paths:
- email confirmation through the signup link, or
- manual approval by a Harbor administrator.

## SMTP configuration

- Harbor does not send email unless SMTP is configured.
- The Harbor service reads SMTP settings from `/etc/admiral/harbor.smtp.env`.
- After changing that file, restart the service:

```bash
systemctl restart admiral-harbor
```

- Required settings:
  - `HARBOR_SMTP_HOST`
  - `HARBOR_SMTP_PORT`
  - `HARBOR_SMTP_USERNAME`
  - `HARBOR_SMTP_PASSWORD`
  - `HARBOR_SMTP_USE_TLS`
  - `HARBOR_SMTP_USE_SSL`
  - `HARBOR_EMAIL_CONFIRMATION_TTL_HOURS`

- If SMTP is not available or mail delivery fails, the customer remains pending and an admin can approve the account manually.

## Admin review

- Pending customer accounts are reviewed in the admin UI at `/admin/review-user`.
- The review queue exists so Harbor can approve users even when the confirmation email does not arrive.
- Admin actions:
  - approve customer
  - reject customer

## Admin instances

- Harbor admins can create internal admin instances without PayPal billing.
- This flow is separate from customer signup and does not change customer billing rules.

## Catalog editing

- Catalog app logos are uploaded locally.
- Supported formats are PNG and JPG/JPEG.
- Customer-facing catalog views do not show CPU, RAM, or storage.
- Technical sizing may remain visible in admin-only views.

## Operational notes

- Do not create Harbor admins from the UI.
- Bootstrap admin accounts are created by the installation workflow and the `harborctl` operational path.
- If you update SMTP, review queue behavior, or signup state handling, restart Harbor and verify the login and approval flows.
