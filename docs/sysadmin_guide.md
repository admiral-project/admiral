# Admiral Sysadmin Guide

This guide matches the current repository state and the EL10 packaging.

## Supported Platform

- Enterprise Linux 10 only
- Supported installer entry point: `admiral_install`
- Source-tree installer: `scripts/install.sh`
- HTTPS helper: `admiral_https_setup`

Harbor is part of the current product and is in active development.

## Deployment Modes

`admiral_install` supports four modes:

- `--single-node`
- `--admin-node`
- `--worker-node`
- `--portal-node`

Single-node combines the admin, worker, and portal roles on one host.

**Important**: `--worker-node` and `--portal-node` are mutually exclusive by design
and cannot be installed on the same host. A worker node runs `admiral-fleet`
for workload execution; a portal node runs `admiral-harbor` for customer
self-service and its own PostgreSQL database. Each role requires its own
WireGuard IP and dedicated system resources. If your deployment needs both
worker and portal capabilities, deploy separate physical or virtual nodes.

### Service Map

| Mode | Services started by the installer |
|------|-----------------------------------|
| single-node | `postgresql`, `caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, `cockpit.socket` |
| admin-node | `postgresql`, `caddy`, `admirald`, `cockpit.socket` |
| worker-node | `admiral-fleet` |
| portal-node | `postgresql`, `admiral-harbor` |

The Harbor package also ships `admiral-harbor-worker.service`, `admiral-harbor-worker.timer`, `admiral-harbor-catalog-sync.service`, and `admiral-harbor-catalog-sync.timer`.

## Public Exposure Policy

The default installation is designed so that only the following ingress is public:

- `22/tcp` for SSH on every node
- `80/tcp` and `443/tcp` on admin and single-node hosts, terminated by Caddy
- `51820/udp` for WireGuard on every node

Everything else is internal-only. Do not publish the following ports directly to the Internet:

- `8080/tcp` `admirald`
- `9099/tcp` `admiral-fleet`
- `5000/tcp` `admiral-flagship`
- `5001/tcp` `admiral-harbor` direct listener
- `5432/tcp` PostgreSQL
- `2019/tcp` Caddy Admin API

`admiral-harbor` is the only customer-facing HTTP service, and it is meant to be published through Caddy, not by exposing its Gunicorn port directly.

`admirald` and `admiral-flagship` have authentication and transport protection, but they are still control-plane services. Their direct ports are not a supported public edge.

## Node Authentication and VPN Security

In multinode deployments (`--worker-node`), the use of a WireGuard VPN is **mandatory** for secure node authentication.

- **WireGuard IP Verification**: `admirald` strictly validates that any incoming worker requests (such as heartbeats, task callbacks, health reports, and storage reports) originate from the registered WireGuard IP of the claiming node.
- **Node Scoping & Isolation**: Even though a shared token is used for protocol authentication, `admirald` enforces node scoping. A node cannot query, update, or report status for instances or resources belonging to another node. Attempts to do so, or requests coming from mismatching VPN IPs, will be rejected with a `403 Forbidden` error.
- **Single-Node Mode Exception**: In single-node deployments (`--single-node`), since all components run locally on `127.0.0.1` and no WireGuard IP is registered, this IP matching verification is bypassed automatically.

## TLS Material

`/etc/admiral/tls/ca.pem` is the public CA certificate used to validate Admiral-issued TLS material and may be distributed where trust is needed.

`/etc/admiral/tls/ca-key.pem` is the private CA signing key. It must remain on the admin node only and must not be copied to workers or portal nodes.

## Systemd and Config

| Component | Unit | Config file |
|-----------|------|-------------|
| `admirald` | `admirald.service` | `/etc/admirald.ini` |
| `admiral-fleet` | `admiral-fleet.service` | `/etc/admiral/fleet.env` |
| `admiral-flagship` | `admiral-flagship.service` | `/etc/admiral/flagship.env` |
| `admiral-harbor` | `admiral-harbor.service` | `/etc/admiral/harbor.env` and optional `/etc/admiral/harbor.smtp.env` |
| `admiralctl` | `admiralctl` | `~/.config/admiralctl/config.yaml` |

Package defaults are installed under `/etc/admiralctl/config.yaml`, but the CLI reads the user config in `~/.config/admiralctl/config.yaml` first.

`admiral-fleet` requires `ADMIRAL_FLEET_ROOTLESS_USER` and runs Podman through the rootless user manager.

## What the Installer Does

The installer and Ansible bootstrap:

- install the RPMs
- configure the services
- generate the platform secrets
- install the local CA bundle
- start the selected systemd units

## What the Installer Does Not Do

These are operator tasks and must be completed after installation:

- Public HTTPS setup via `admiral_https_setup`
- S3 or other backup-storage configuration
- DNS records for public endpoints
- Any external email provider setup for Harbor

For HTTPS, run:

```bash
sudo admiral_https_setup --domain cloud.example.com
```

For backup storage, use `admiralctl` after the platform is up. The installer does not create or configure the backup-storage backend.

## Backup Storage Configuration

Backups are a critical data-protection feature. Admiral stores backups in
external S3-compatible storage (MinIO, Backblaze B2, AWS S3, etc.) to
ensure data survives node failure.

### Configure S3 backup storage

Use `admiralctl` to configure the active backup storage backend:

```bash
admiralctl backups storage set \
  --backend s3 \
  --endpoint http://10.99.0.1:9000 \
  --region us-east-1 \
  --bucket admiral-backups \
  --prefix admiral/multi-node-beta
```

Verify connectivity from a worker node:

```bash
admiralctl backups storage test
```

### Fleet worker credentials

Each worker node running `admiral-fleet` needs S3 credentials in
`/etc/admiral/fleet.env`:

```text
ADMIRAL_S3_ACCESS_KEY_ID=<access-key>
ADMIRAL_S3_SECRET_ACCESS_KEY=<secret-key>
```

The fleet worker reads these environment variables when uploading
backups to S3. Without them, backups fall back to local-only storage
on the worker node and will be lost if the node fails.

### Admirald verifier credentials

The admin node running `admirald` also needs S3 credentials in
`/etc/admiral/admirald.env` to run the backup verifier:

```text
ADMIRAL_S3_ACCESS_KEY_ID=<access-key>
ADMIRAL_S3_SECRET_ACCESS_KEY=<secret-key>
```

The verifier is a background goroutine that independently confirms
backups exist in S3 (see below).

### Post-upload verification (fleet)

When `admiral-fleet` uploads a backup to S3, it does not trust the
HTTP 2xx response alone. After the PUT, the fleet worker issues an
HTTP HEAD request to the same object key and verifies that the
`Content-Length` reported by S3 matches the local backup size. If the
verification fails, the backup is reported as failed — even if the
PUT appeared to succeed.

This catches:
- Silent data loss during upload
- Partial writes
- Eventual-consistency lag
- Network errors that return 2xx but do not persist the object

### Backup verifier goroutine (admirald)

`admirald` runs a background goroutine (`StartBackupVerifier`) that
independently verifies succeeded S3 backups every 30 minutes.

For each backup record with `status='succeeded'` and
`storage_backend='s3'`, the verifier:

1. Issues an HTTP HEAD request to the object's `storage_key` in S3
2. Compares the reported `Content-Length` with the recorded `size_bytes`
3. On success: sets `verified_at` timestamp in the `backup_records` table
4. On failure: clears `verified_at` and records the error message

This is a paranoid second layer of verification — even if the fleet
worker reports a successful upload with post-upload verification,
admirald independently confirms the object is still reachable and has
the correct size at a later time.

To check verification status:

```bash
admiralctl backups list --instance <instance-id>
```

The `verified_at` field shows the last successful verification
timestamp. An empty `verified_at` with an `error_message` indicates
verification failed and the backup may not be recoverable.

### Important notes

- Backups must be stored off-node. Local-only backups on a worker
  node will be lost if the node fails.
- The S3 endpoint must be reachable from all worker nodes via the
  WireGuard network (e.g., `http://10.99.0.1:9000` for MinIO on the
  admin node).
- The verifier requires `ADMIRAL_S3_ACCESS_KEY_ID` and
  `ADMIRAL_S3_SECRET_ACCESS_KEY` in `admirald`'s environment. Without
  them, the verifier logs an error and skips verification.

## Secrets

`/etc/admiral/secrets` is the source of truth for generated platform secrets and the encryption material used by Admiral and Harbor.

- Back it up immediately after installation.
- Keep a copy off the server.
- If it is lost, encrypted data and bootstrap secrets cannot be recovered.
- The file must survive node loss and reinstall scenarios.
- It contains the keys used to encrypt stored secrets, including `ADMIRAL_SECRETS_KEY` and `HARBOR_ENCRYPTION_KEY`.

## Common Checks

```bash
systemctl status admirald admiral-fleet admiral-flagship admiral-harbor
admiralctl status
admiralctl nodes list
admiralctl instances list
admiralctl backups list
admiralctl routes list
admiralctl operations list
```

## References

- `docs/admiral-installation-guide.md` for the full install runbook
- `docs/networking_v1.md` for network behavior
- `admiralctl/docs/man.md` for the CLI reference
