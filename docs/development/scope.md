# Admiral Scope

This is the compact reference for what is currently relevant in Admiral development.

## Current Product Scope

- Enterprise Linux 10 only.
- `admirald` is the control plane.
- `admiral-fleet` is the rootless worker agent.
- `admiralctl` is the operator CLI.
- `admiral-flagship` is the administrative console.
- `admiral-harbor` is the customer portal and is still evolving.
- The official installer is `admiral_install`.
- Public HTTPS setup is handled manually with `admiral_https_setup`.

## Decisions That Are Still In Force

- Podman rootless, Quadlet, and systemd are the runtime model for workers.
- PostgreSQL is the durable queue and control-plane storage backend.
- There is no external broker as the official runtime transport.
- Communication between Admiral nodes uses WireGuard as a private VPN.
- Internal service ports are not exposed directly to the public Internet.
- `/etc/admiral/secrets` must be backed up off the server.
- That file contains the encryption keys used by Admiral and Harbor, including `ADMIRAL_SECRETS_KEY` and `HARBOR_ENCRYPTION_KEY`.

## Validated Scope

- single-node operation.
- provisioning and deprovisioning.
- pause and resume.
- backup and restore.
- routing for published services.
- rootless worker execution with Quadlet.
- the operator workflows exposed by `admiralctl`.

## Current Limits

- Multi-node validation is still incomplete.
- Universal application compatibility is not guaranteed.
- Harbor is active development, not a finished product.
- Backup is by service, not by whole app.

## What The Old Phase Docs Mean Now

- `fase1.md` to `fase5.md` are historical context, not source of truth.
- `rootless.md` and `message_broker_refactor.md` still describe active decisions.
- `alpha_known_limitations.md` remains useful, but this file is the shorter summary to consult first.

## Source Documents

- `docs/sysadmin_guide.md`
- `docs/admiral-installation-guide.md`
- `docs/networking_v1.md`
- `docs/development/rootless.md`
- `docs/development/message_broker_refactor.md`
- `docs/development/alpha_known_limitations.md`
