# Admiral Sysadmin Guide

## Multi-node deployment

The full networking architecture is defined in `multi_node_networking_v1.md`.

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

From the admin node, run the installed bootstrap command and pass only the worker public IP:

```bash
admiral_install --worker-node --public-ip <worker-public-ip>
```

`admiral_install` connects to the target over SSH using the local root key, copies `/etc/admiral/secrets`, `/etc/admiral/tls/ca.pem`, and `/etc/admiral/know_host.yaml`, then runs the installed Ansible playbook against that public IP.

The playbook will:

1. Install and configure WireGuard VPN
2. Install admiral-fleet
3. Register the node with admirald via `admiralctl nodes register`

After installation, run the peer exchange playbook from the admin node to register the new worker's WireGuard public key on the hub:

```bash
ansible-playbook /usr/share/admiral/ansible/wireguard-peers.yml -i /path/to/inventory.yml
```

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
- Admin/hub IP: 10.99.0.1
- Worker IP pool: 10.99.0.2–10.99.0.99
- Portal IP pool: 10.99.0.100–10.99.0.199
- All nodes generate a key pair during installation. The public key is stored at `/etc/wireguard/admiral.pub`.

After all nodes are installed, run the peer exchange playbook from the admin node to register each spoke's public key on the hub and deploy the full WireGuard configuration:

```bash
ansible-playbook /usr/share/admiral/ansible/wireguard-peers.yml -i /path/to/inventory.yml
```

The playbook must be run whenever a new node is added. It collects public keys from all nodes, writes peer configs on the hub, and restarts the WireGuard service on every node.

### Node health states

Each node has two status fields:

| Field | Values | Description |
|-------|--------|-------------|
| `status` | `active`, `offline`, `disabled` | Node reachability. `active` means the node is sending heartbeats; `offline` means no heartbeat was received within the timeout window (2 minutes); `disabled` means an operator manually disabled the node. |
| `health_status` | `healthy`, `degraded`, `unhealthy` | Node health. `degraded` is set automatically when the node misses its heartbeat deadline; `healthy` is restored on the next successful heartbeat. |

When a node is marked `offline` with `health_status=degraded`:

- The admirald health monitor logs a warning with the affected node IDs.
- admiral-flagship shows a warning alert on the dashboard and a callout on the node detail page.
- The node is marked unavailable for provisioning.
- Instances running on the node continue to operate until the node is restored or recovered.

A node recovers automatically when its fleet agent sends the next successful heartbeat — `status` returns to `active`, `health_status` returns to `healthy`, and it becomes available for provisioning again.

### Backup storage (S3)

All workers share a single S3-compatible bucket for backup storage. Configure it after installation:

1. Store the S3 endpoint, region, and bucket in admirald's `backup_storage_configs` table.
2. Write `ADMIRAL_AWS_ACCESS_KEY_ID` and `ADMIRAL_AWS_SECRET_ACCESS_KEY` to `/etc/admiral/fleet.env` on each worker node (or single-node host).

Using the CLI:

```bash
admiralctl backups storage set \
  --backend s3 \
  --endpoint https://s3.us-east-1.amazonaws.com \
  --bucket admiral-backups \
  --region us-east-1
```

Then, on each worker node, write the credentials to `/etc/admiral/fleet.env` and restart the agent:

```bash
echo 'ADMIRAL_AWS_ACCESS_KEY_ID=AKIDEXAMPLE' >> /etc/admiral/fleet.env
echo 'ADMIRAL_AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' >> /etc/admiral/fleet.env
systemctl restart admiral-fleet
```

Supported backends: `s3` and `local` (default). S3-compatible services include MinIO, Wasabi, Backblaze B2, and Cloudflare R2.

Test the storage configuration:

```bash
admiralctl backups storage test
```

View the current configuration:

```bash
admiralctl backups storage get
```

Delete a backup (with confirmation):

```bash
admiralctl backups delete <backup-id>
```

Prune old succeeded backups (with confirmation):

```bash
admiralctl backups prune
```

---

### Provisioning instances

```bash
admiralctl instances provision \
  --app my-app \
  --tier starter \
  --customer customer1 \
  --node worker1
```

To preserve a logical instance identity across reprovisioning (e.g. during disaster recovery):

```bash
admiralctl instances provision \
  --app my-app \
  --tier starter \
  --customer customer1 \
  --node worker2 \
  --logical-instance-id <uuid>
```

The `logical_instance_id` is a permanent identifier used for billing, backup ownership, and audit records. It never changes, even if the runtime instance (`instance_id`) changes due to migration or recovery.

---

### Instance migration (offline)

Migrate an instance from one worker node to another. The source node and target node do not need to be online simultaneously — data is transferred via S3 backup.

```bash
admiralctl instances migrate <instance-id> --target-node <new-node-id> --wait
```

The CLI triggers a background operation in admirald that:

1. Backs up database and volumes on the source node to S3.
2. Saves the existing public route for the instance (hostname is preserved).
3. Updates the instance node assignment to the target.
4. Deprovisions the instance on the source node (removes containers, releases capacity).
5. Re-provisions the instance on the target node, preserving `logical_instance_id`.
6. Restores database and volumes from S3 on the target node.
7. Starts the instance.
8. Recreates the public route on the target node with the original hostname.
9. Syncs the route to Caddy so the public URL remains unchanged.

Monitor progress:

```bash
admiralctl operation show <operation-id>
```

The migration is idempotent — if it fails mid-way, the instance state is predictable. A failed migration leaves the instance in its last known state (deprovisioned on source if deprovision completed, or provisioned on target if provision completed). If the migration succeeds, the public URL (`https://<app>.apps.<domain>`) continues to work without any DNS changes.

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
