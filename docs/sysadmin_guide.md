# Admiral Sysadmin Guide

This guide matches the current repository state and the EL10 packaging.

## Supported Platform

- Enterprise Linux 10 only
- Supported installer entry point: `admiral_install`
- Source-tree installer: `scripts/install.sh`
- HTTPS helper: `admiral_https_setup`

Harbor is part of the current product and is in active development.

## Deployment Modes

`admiral_install` supports six modes:

- `--single-node`
- `--admin-node`
- `--admin-portal-node`
- `--worker-node`
- `--portal-node`
- `--dev-node`

Single-node combines the admin, worker, and portal roles on one host.

The supported shared production topology uses `--admin-portal-node` from the
first installation. It installs the Admin services and Harbor on one host;
Workers remain dedicated nodes. Installing `--admin-node` and then running
`--portal-node` on the same host is not supported.

The other supported production topology uses `--admin-node` with a dedicated
`--portal-node` and dedicated Workers. A dedicated portal receives a separate
local PostgreSQL role and password and reaches Admirald only through its
WireGuard address.

The installer persists the selected role in `/etc/admiral/role`. Re-running
the same mode reconciles that host idempotently. Selecting a different role
fails before the installer changes the host. The only automatic role transition
is `--dev-node` to `--single-node`, which restores the secure single-node
profile.

**Important**: `--worker-node` and `--portal-node` are mutually exclusive by design
and cannot be installed on the same host. A worker node runs `admiral-fleet`
for workload execution; a portal node runs `admiral-harbor` for customer
self-service and its own PostgreSQL database. Each role requires its own
WireGuard IP and dedicated system resources. If your deployment needs both
worker and portal capabilities, deploy separate physical or virtual nodes.

## Provisioning New Cluster Hosts from the Admin Node

All worker and dedicated portal provisioning is initiated on the Admiral admin
node. Do not copy `/etc/admiral/secrets`, the Admiral CA private key, or the
installer to a spoke and run it there. The admin node is the Ansible controller,
holds the cluster bootstrap inventory, and performs the remote installation over
SSH.

The examples below use documentation addresses:

| Host | Public address | WireGuard address | Node ID |
|------|----------------|-------------------|---------|
| Admin | `203.0.113.10` | `10.99.0.1` | admin host name |
| Portal | `198.51.100.30` | `10.99.0.100` | `portal-01` |
| Worker | `198.51.100.20` | `10.99.0.2` | `worker-01` |

Replace every address, node ID, SSH key path, and fingerprint with values from
the real deployment.

### 1. Install the Admin Profile

For a dedicated admin with a separate portal, run on the future admin host:

```bash
sudo admiral_install --admin-node --public-ip 203.0.113.10
```

For the supported shared admin and portal topology, use this mode from the
first installation:

```bash
sudo admiral_install --admin-portal-node --public-ip 203.0.113.10
```

Do not install `--admin-node` and later run `--portal-node` on that same host.
`--portal-node` always describes a dedicated remote portal spoke.

Before adding a spoke, verify on the admin node:

```bash
sudo test -f /etc/admiral/secrets
sudo test -f /etc/admiral/tls/ca.pem
sudo test -f /var/lib/admiral/know_host.yaml
sudo admiralctl nodes list
```

The private SSH key used for first contact must be present on the admin node and
must authenticate to the new host. Initial bootstrap may use `root` with a key.
Password-based bootstrap is not supported.

### 2. Obtain the Spoke Fingerprint Independently

Before running the installer, open the VPS provider's serial console or another
trusted out-of-band console on the new host. Read the fingerprint directly from
that host, for example:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

ECDSA or RSA host keys are also supported:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub -E sha256
sudo ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub -E sha256
```

Copy the complete `SHA256:...` value to the admin node. Do not establish trust
from `ssh-keyscan` output alone; the installer uses `ssh-keyscan` only to obtain
candidate public keys and accepts a candidate only when it matches this
independently obtained fingerprint.

### 3. Add a Dedicated Portal

Run the following command on the admin node:

```bash
sudo admiral_install --portal-node \
  --node-id portal-01 \
  --public-ip 198.51.100.30 \
  --wireguard-ip 10.99.0.100 \
  --admin-endpoint 203.0.113.10 \
  --ssh-key /root/.ssh/id_ed25519 \
  --ssh-fingerprint SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
```

If `portal.node_id` and `portal.wireguard_ip` are already assigned under
`next` in `/var/lib/admiral/know_host.yaml`, `--node-id` and
`--wireguard-ip` may be omitted. The installer resolves and validates those
two values on the admin node.

### 4. Add a Worker

Run the following command on the admin node for each new worker:

```bash
sudo admiral_install --worker-node \
  --node-id worker-01 \
  --public-ip 198.51.100.20 \
  --wireguard-ip 10.99.0.2 \
  --admin-endpoint 203.0.113.10 \
  --ssh-key /root/.ssh/id_ed25519 \
  --ssh-fingerprint SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
```

As with a portal, the worker node ID and WireGuard address may be omitted when
the correct `next.worker` assignment exists in `know_host.yaml`.

The installer performs the complete remote flow: verifies the SSH host key,
runs Ansible, installs the shared `opsa_*` operator account, verifies
passwordless sudo, disables root SSH login, exchanges WireGuard peers, and
checks the expected services and security profile.

### 5. Verify the New Host from Admin

After the command succeeds, remain on the admin node and verify:

```bash
sudo admiralctl nodes list
sudo wg show wg-admiral
sudo systemctl is-active admirald caddy
```

Use the `opsa_*` username printed by the installer for an optional direct
administrative check:

```bash
ssh -i /root/.ssh/id_ed25519 \
  opsa_REPLACE@198.51.100.20 'sudo -n systemctl is-active admiral-fleet'
```

For a portal, replace the final service with `admiral-harbor`.

### 6. Reconcile or Reinstall a Spoke

Re-run the same `admiral_install --worker-node` or
`admiral_install --portal-node` command from the admin node. The installer
detects the persisted `opsa_*` account, connects with that non-root account,
uses `sudo -n` for privileged operations, and preserves existing secrets and
registrations. Supply the currently verified SSH host fingerprint on every
run. If the host key changed, stop and verify the new key through the provider
console before retrying.

`--single-node` and `--dev-node` are local co-located setups, not commands for
adding remote cluster hosts. `--single-node` is the secure production profile
that combines admin, portal, and worker on one host. `--dev-node` is an
explicitly insecure evaluation profile; the supported automatic transition is
from `--dev-node` to `--single-node` on that same host.

For safety, `--dev-node` requires the operator to type `yes-insecure` when run
interactively. Automation must pass `--yes` explicitly; without that flag the
installer aborts when standard input is not a terminal.

### Manual migration from Admin+Portal to dedicated Portal

An `admin-portal` host may become an `admin` host only after the operator has
manually moved Harbor to a dedicated `--portal-node` and stopped Harbor on the
original host. This is a manual operational change; the installer does not
migrate or validate Harbor data.

After completing and validating that manual migration, stop and disable
`admiral-harbor`, `admiral-harbor-worker.timer`, and
`admiral-harbor-catalog-sync.timer` on the original host. The operator may then
change the content of `/etc/admiral/role` from `admin-portal` to `admin`.
Do not change this file before Harbor has been moved and stopped.

### SSH Admin User

The installer creates a non-root SSH admin user on every node. This user:

- Has a generated username (prefixed `opsa_`) stored in `/etc/admiral/secrets`
- Belongs to the `wheel` group with NOPASSWD sudo access
- Authenticates via SSH key only (password authentication is disabled)
- Is the recommended access method for ongoing administration

The username is printed at the end of a successful installation:

```
SSH access (recommended, non-root):
  ssh opsa_a1b2c3d4e5@203.0.113.10
```

### SSH Key Requirements

Before running the installer, you must have SSH key-based access to the
target node. The installer uses this key to:

1. Connect to the node during installation
2. Extract the public key for the new admin user
3. Deploy the public key to the admin user's `authorized_keys`

#### Private key location

The installer auto-detects the SSH private key in the following order:

| Mode | Detection order |
|------|----------------|
| `--single-node`, `--admin-node`, `--admin-portal-node` | 1. `--ssh-key <path>` flag if provided |
| | 2. `~/.ssh/id_ed25519` |
| | 3. `~/.ssh/id_rsa` |
| `--worker-node`, `--portal-node` | 1. `--ssh-key <path>` flag if provided |
| | 2. `/root/.ssh/id_ed25519` |
| | 3. `/root/.ssh/id_rsa` |

**Important**: The installer runs as root. For spoke nodes, the key path
must be accessible by root. If your key is in a non-standard location,
use `--ssh-key` explicitly:

```bash
# Example: run from the admin node with a key in a custom location
sudo admiral_install --worker-node \
  --public-ip 198.51.100.20 \
  --ssh-key /opt/keys/admin_id_ed25519 \
  --ssh-fingerprint SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
  --admin-endpoint 203.0.113.10

# Example: same key for local setup
admiral_install --single-node \
  --ssh-key /home/admin/.ssh/id_ed25519
```

#### Public key extraction

The public key is automatically extracted from the private key using
`ssh-keygen -y -f <private_key>`. This means:

- The private key file must exist on disk
- The private key must not be passphrase-protected (the installer
  uses `BatchMode=yes` for non-interactive SSH)
- The corresponding `.pub` file is not required

#### Spoke node flow

For `--worker-node` and `--portal-node`:

1. The installer is run on the admin node and verifies the spoke host key.
2. Initial bootstrap may connect as **root** using the SSH key.
3. Ansible creates the cluster `opsa_<random>` user on the spoke.
4. The public key is extracted from the private key and deployed to
   the new user's `authorized_keys`
5. The installer verifies `sudo -n` through that account and then sets
   effective `PermitRootLogin no`.
6. After installation, you can SSH as the admin user:
   ```bash
   ssh opsa_a1b2c3d4e5@198.51.100.20
   ```

If the non-root login or passwordless sudo check fails, installation stops
before disabling key-based root recovery.

Worker and portal modes accept the following additional flags for secure
remote provisioning:

| Flag | Description |
|------|-------------|
| `--public-ip <ip>` | Public IP of the target node (required) |
| `--wireguard-ip <ip>` | WireGuard VPN IP for the target node |
| `--admin-endpoint <ip>` | Admin node IP for API access from spoke |
| `--ssh-user <user>` | SSH user for remote connection (default: root) |
| `--ssh-key <path>` | SSH private key for remote authentication |
| `--ssh-fingerprint <fingerprint>` | Expected SSH host key fingerprint for MITM verification |

### Service Map

| Mode | Services started by the installer |
|------|-----------------------------------|
| single-node | `postgresql`, `caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, `cockpit.socket` |
| admin-node | `postgresql`, `caddy`, `admirald`, `admiral-flagship`, `cockpit.socket` |
| admin-portal-node | `postgresql`, `caddy`, `admirald`, `admiral-flagship`, `admiral-harbor`, `cockpit.socket` |
| worker-node | `admiral-fleet` |
| portal-node | `postgresql`, `admiral-harbor` |

The Harbor package also ships `admiral-harbor-worker.service`, `admiral-harbor-worker.timer`, `admiral-harbor-catalog-sync.service`, and `admiral-harbor-catalog-sync.timer`.

## Public Exposure Policy

The default installation is designed so that only the following ingress is public:

- `22/tcp` for SSH on every node
- `80/tcp` and `443/tcp` on admin and single-node hosts, terminated by Caddy
- `51820/udp` on admin, worker, and portal hosts in multinode deployments;
  standalone secure single-node keeps WireGuard disabled

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
- **Single-Node Mode and Authentication**: In single-node deployments
  (`--single-node`), all components run on the same host and communicate
  over loopback. However, because the Ansible bootstrap assigns a
  WireGuard IP to every node, `admirald` would normally require the
  fleet origin IP to match the registered WireGuard IP, which fails
  for loopback connections.

  The **Laguna M1** security audit (July 2026) hardened node
  authentication: localhost bypass is no longer allowed in production
  mode. To restore single-node functionality, the installer sets
  `ADMIRAL_SINGLE_NODE=true` in the `admirald` systemd environment
  when running `--single-node` without `--dev-node`.

  This variable tells `admirald` that fleet is connecting from the
  same host via loopback. This is an intentional design choice, not
  a security flaw: single-node collocates all services on one machine
  and does not use the VPN for internal worker-to-control-plane traffic.

  Operators should **not** set `ADMIRAL_SINGLE_NODE=true` on multi-node
  deployments (workers or portal nodes), since those nodes are expected
  to communicate over WireGuard.

## Spoke Bootstrapping and SSH Host Key Verification

When provisioning a remote worker or portal node (`--worker-node` or
`--portal-node`), the installer (`admiral_install` or `scripts/install.sh`)
transmits only the role-scoped bootstrap values, public CA certificate, and
WireGuard public material required by that target. The central
`/etc/admiral/secrets` inventory and CA private key never leave the admin host.

The installer performs SSH host key verification before any secrets leave the
admin node. A fingerprint is mandatory for remote bootstrap:

1. **`ssh-keyscan` pre-flight**: Before the first SSH connection, the
   installer obtains candidate public keys from `ssh-keyscan <public-ip>`.
   This scan does not establish trust.

2. **`StrictHostKeyChecking=yes`**: Every subsequent SSH connection uses
   a root-only temporary `known_hosts` file containing only the candidate key
   that matched the operator-supplied fingerprint. A stale or unrelated entry
   in the operator's persistent `known_hosts` cannot override that decision.

3. **Fingerprint verification**: `--ssh-fingerprint` is required and must
   match one of the candidate keys. Obtain the trusted value from the VPS
   provider console or another out-of-band channel, for example by running
   this command directly on the new spoke:

   ```bash
   sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
   ```

An unknown host without an independently verified fingerprint fails before
authentication or secret transfer. The persistent `known_hosts` file is never
modified by spoke bootstrap.

### Example with fingerprint verification

```bash
admiral_install --worker-node \
  --public-ip 198.51.100.20 \
  --ssh-fingerprint SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
  --admin-endpoint 203.0.113.10
```

If the fingerprint does not match, the installer exits with:

```
[FATAL] SSH host key fingerprint mismatch for 198.51.100.20. Aborting.
```

For automation, store the verified fingerprint in the deployment secret
store and pass it explicitly. If the spoke's SSH host key changes, stop and
re-verify the replacement key before retrying.

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
- create a non-root SSH admin user with sudo access
- apply SSH hardening (key-only root login, password auth disabled)
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

## Security Baseline and Dev-Node Exceptions

The official installer assumes a **fresh VPS** with no unrelated public services already running.

### Alcance de las garantías

Esta guía describe transiciones soportadas y comprobaciones bloqueantes; no
considera suficiente que una unidad esté habilitada o que un archivo exista en
disco. Después de cada reconciliación se deben comprobar las unidades efectivas,
los listeners, SELinux, WireGuard en spokes y el conjunto de servicios requerido.

La identidad de bootstrap y la identidad operativa son distintas:

- el acceso SSH inicial usa el `--ssh-user` y la clave suministrados;
- el bootstrap remoto exige `--ssh-fingerprint` y `StrictHostKeyChecking=yes`
  antes de transferir secretos;
- las operaciones rutinarias usan la cuenta no root generada `opsa_*` y su
  política `sudo` restringida;
- la recuperación break-glass depende de la ruta SSH externa del operador y no
  se infiere del inventario generado.

Las topologías también son explícitas: `--single-node` combina admin, worker y
portal localmente; `--admin-node` instala el plano de control; `--worker-node`
instala un spoke rootless dedicado; y `--portal-node` instala un portal dedicado.
Un portal compartido con el admin debe declararse como topología compartida y
preserva el inventario de secretos del admin. Un portal dedicado no recibe ese
inventario ni la clave privada de la CA. Tras una transición de topología deben
repetirse las comprobaciones bloqueantes de servicios, listeners, firewall y
registros antes de declarar la instalación terminada.

For normal modes (`--single-node`, `--admin-node`, `--admin-portal-node`, `--worker-node`, `--portal-node`), the installer applies a secure-by-default baseline including firewall policy, SELinux settings, login hardening, auditd, and fail2ban. Blocking security checks cause installation to fail; they are not advisory warnings.

### Configuring secure spoke egress

Worker and dedicated portal nodes use a default-deny outbound nftables policy.
It permits only loopback, established traffic, the Admiral VPN, SSH, DNS
(UDP/TCP 53), HTTPS (TCP 443), and WireGuard (UDP 51820). All other outbound
traffic is rejected for both IPv4 and IPv6. DNS and HTTPS are intentionally
allowed by port rather than by fixed IP: Docker Hub and PayPal use rotating
CDN addresses, and resolver addresses may be supplied dynamically by DHCP.

This is a node-level baseline, not an application egress allowlist. It keeps
the node operational without brittle endpoint lists; image policy, digests,
and workload-specific restrictions remain separate controls. This mirrors
Kubernetes, where node networking is distinct from optional per-Pod
`NetworkPolicy` egress isolation.

References: [Kubernetes network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
and [Kubernetes cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/).

`--dev-node` is explicitly an evaluation mode and does **not** apply all production hardening controls. In dev-node mode:

- Fail2ban protections are not applied.
- Strict egress control is not enforced.
- Post-install security checklist warnings are skipped.

Use `--dev-node` only for temporary testing workflows where direct port access is required.

## SELinux Recommended Configuration

Admiral expects SELinux to stay enabled. The recommended operational state is:

- SELinux in `Enforcing` mode
- `httpd_can_network_connect` boolean set to `on`
- `container_manage_cgroup` boolean set to `on`

The official setup path (`admiral_install`) leaves the system configured with these recommended SELinux parameters.

You can verify the effective state with:

```bash
getenforce
getsebool httpd_can_network_connect container_manage_cgroup
ausearch -m AVC -ts recent
```

If you apply additional host hardening after installation, re-check AVC denials and adjust your SELinux policy accordingly.

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
- It contains `ADMIRAL_SSH_USER`, the non-root SSH admin username for all nodes.

### Rotar `ADMIRAL_SECRETS_KEY`

Admiral soporta una ventana de rotación para no perder los secretos cifrados.
La clave nueva siempre se usa para cifrar valores nuevos; la clave anterior
solo se conserva temporalmente para descifrar los valores existentes.

1. Haz una copia segura de `/etc/admiral/secrets` y confirma que puedes
   restaurarla.
2. Genera una clave nueva en el nodo que ejecuta `admirald`:

   ```bash
   NEW_KEY=$(openssl rand -hex 32)
   printf '%s\n' "$NEW_KEY"
   ```

3. Conserva la clave anterior en `/etc/admiral/secrets` como respaldo y
   configura `/etc/admirald.ini` con la clave nueva y la anterior:

   ```ini
   secrets_key=<new-key>
   secrets_key_previous=<old-key>
   ```

   También puedes configurar `secrets_key_previous` en
   `/etc/admirald.ini`. Se pueden indicar varias claves anteriores separadas
   por comas.
4. Reinicia `admirald` y ejecuta la migración idempotente desde el nodo
   administrativo:

   ```bash
   sudo systemctl restart admirald
   sudo admiralctl secrets rotate
   sudo journalctl -u admirald -n 100 --no-pager
   ```

El comando devuelve `migrated`, `already_current` y `total`; repetirlo no
vuelve a cifrar los registros que ya usan la clave nueva. Durante la ventana
de rotación, cualquier secreto nuevo usa la clave nueva y los existentes
siguen siendo legibles con `secrets_key_previous`. Cuando `migrated` sea cero
y hayas verificado la aplicación, elimina la clave anterior de
`/etc/admirald.ini` y reinicia el servicio. Nunca compartas estas claves con
`admiral-fleet`, Flagship ni Harbor.

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
