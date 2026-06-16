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

### Service Map

| Mode | Services started by the installer |
|------|-----------------------------------|
| single-node | `postgresql`, `caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, `cockpit.socket` |
| admin-node | `postgresql`, `caddy`, `admirald`, `cockpit.socket` |
| worker-node | `admiral-fleet` |
| portal-node | `postgresql`, `admiral-harbor` |

The Harbor package also ships `admiral-harbor-worker.service`, `admiral-harbor-worker.timer`, `admiral-harbor-catalog-sync.service`, and `admiral-harbor-catalog-sync.timer`.

## Node Authentication and VPN Security

In multinode deployments (`--worker-node`), the use of a WireGuard VPN is **mandatory** for secure node authentication.

- **WireGuard IP Verification**: `admirald` strictly validates that any incoming worker requests (such as heartbeats, task callbacks, health reports, and storage reports) originate from the registered WireGuard IP of the claiming node.
- **Node Scoping & Isolation**: Even though a shared token is used for protocol authentication, `admirald` enforces node scoping. A node cannot query, update, or report status for instances or resources belonging to another node. Attempts to do so, or requests coming from mismatching VPN IPs, will be rejected with a `403 Forbidden` error.
- **Single-Node Mode Exception**: In single-node deployments (`--single-node`), since all components run locally on `127.0.0.1` and no WireGuard IP is registered, this IP matching verification is bypassed automatically.

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
