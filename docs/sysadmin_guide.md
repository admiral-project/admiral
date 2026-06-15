# Admiral Sysadmin Guide

## Multi-node deployment

The full networking architecture is defined in `multi_node_setup_v1.md`.

Admiral supports three node roles:

- **admin** — control plane (admirald, flagship, harbor, caddy, PostgreSQL)
- **worker** — runs workloads (admiral-fleet, podman)
- **portal** — customer portal node (admiral-fleet, future portal services)

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
