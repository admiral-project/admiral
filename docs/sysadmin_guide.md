# Admiral Sysadmin Guide

This guide matches the current repository state and the EL10 packaging.

## Supported Platform

- Enterprise Linux 10 only
- Supported installer entry point: `admiral_install`
- Source-tree installer: `scripts/install.sh`
- HTTPS helper: `admiral_https_setup`

Admiral is a functional beta under testing and validation. It is not yet
recommended for production use; Harbor's real PayPal payment flow remains a
1.0 validation item.

## Deployment Modes

`admiral_install` supports six modes:

- `--single-node`
- `--admin-node`
- `--admin-portal-node`
- `--worker-node`
- `--portal-node`
- `--dev-node`

Single-node combines the admin, worker, and portal roles on one host.

The supported shared beta topology uses `--admin-portal-node` from the
first installation. It installs the Admin services and Harbor on one host;
Workers remain dedicated nodes. Installing `--admin-node` and then running
`--portal-node` on the same host is not supported.

The other supported beta topology uses `--admin-node` with a dedicated
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
uses the bootstrap key only for the Ansible connection, creates the fixed
`admiral-ssh` account and a unique Ed25519 identity on the Admin controller,
then retries the Fleet/Harbor handshake and service checks. The bootstrap
credential remains usable during this entire flow. Only after the new SSH
identity, onboarding, WireGuard, service, and security checks succeed does the
installer revoke the bootstrap key and disable root SSH login.

### 5. Verify the New Host from Admin

After the command succeeds, remain on the admin node and verify:

```bash
sudo admiralctl nodes list
sudo wg show wg-admiral
sudo systemctl is-active admirald caddy
```

Use the `admiral-ssh` username and the per-node private key artifact printed by
the installer for an optional direct administrative check:

```bash
ssh -i /var/lib/admiral/ssh-delivery/worker-01.ed25519 \
  admiral-ssh@198.51.100.20 'sudo -n systemctl is-active admiral-fleet'
```

The private key is a temporary delivery artifact on the Admin node. Extract it
to secure administrator storage, verify its fingerprint and delete the local
copy. Admiral does not use this key for normal Fleet, WireGuard, API, or TLS
operations, and each Worker or Portal receives a different key pair.

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
adding remote cluster hosts. `--single-node` is the secure beta profile
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

The installer creates the `admiral-ssh` non-root SSH admin user on every node. This user:

- Has an identity generated exclusively for that node by Ansible on the Admin controller
- Belongs to the `wheel` group with NOPASSWD sudo access. This is full root
  access and is required for unattended provisioning; protect the SSH private
  key as a root-equivalent credential.
- Authenticates via SSH key only (password authentication is disabled)
- Is the recommended access method for ongoing administration

The username is printed at the end of a successful installation:

```
SSH access (recommended, non-root):
  ssh opsa_a1b2c3d4e5@203.0.113.10
```

### SSH Key Requirements

Before running the installer, you must have SSH key-based access to the
target node. The installer uses SSH keys to:

1. Connect to remote spoke nodes during installation
2. Select or extract the public key for the new admin user
3. Deploy the public key to the admin user's `authorized_keys`

#### Key selection

For local installation modes, the installer selects the operator public key in
the following order:

| Mode | Detection order |
|------|----------------|
| `--single-node`, `--admin-node`, `--admin-portal-node` | 1. `--ssh-public-key <path>` if provided |
| | 2. Public key extracted from `--ssh-key <path>` if provided |
| | 3. Root's `id_ed25519.pub`, `id_rsa.pub`, or `authorized_keys` |
| | 4. The invoking sudo user's `authorized_keys` |
| `--worker-node`, `--portal-node` | The bootstrap `--ssh-key <path>` is used only for temporary transport. |

**Important**: Spoke provisioning still needs a private key accessible by root
to establish the remote SSH connection. Local installation does not need the
private key on the server; prefer `--ssh-public-key`:

```bash
# Example: run from the admin node with a key in a custom location
sudo admiral_install --worker-node \
  --public-ip 198.51.100.20 \
  --ssh-key /opt/keys/admin_id_ed25519 \
  --ssh-fingerprint SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
  --admin-endpoint 203.0.113.10

# Local setup authorizes a public key and never needs its private half
sudo admiral_install --single-node \
  --ssh-public-key /home/admin/.ssh/authorized_keys
```

#### Public key extraction

For remote authentication, the public key is automatically extracted from the
private key using `ssh-keygen -y -f <private_key>`. This means:

- The private key file must exist on disk
- The private key must not be passphrase-protected (the installer
  uses `BatchMode=yes` for non-interactive SSH)
- The corresponding `.pub` file is not required

An explicitly supplied public-key file and discovered `authorized_keys` entries
are parsed to remove authorization options and validated with `ssh-keygen`
before Ansible writes the selected local key. For a spoke, Ansible generates a
new Ed25519 pair on the Admin controller and writes only its public half to the
remote node. The bootstrap private key is never copied into `admiral-ssh`.

#### Spoke node flow

For `--worker-node` and `--portal-node`:

1. The installer is run on the admin node and verifies the spoke host key.
2. Initial bootstrap may connect as **root** using the SSH key.
3. Ansible installs `admiral-common`, including the bootstrap-revocation helper,
   and creates `admiral-ssh`.
4. Ansible generates a unique per-node key pair on the Admin controller and
   deploys only its public key to the spoke.
5. The installer retries registration, WireGuard, Fleet/Harbor readiness and
   service checks; it may restart the workload service once after initial
   handshake attempts.
6. After all checks pass, the helper removes the exact bootstrap public key,
   and the installer applies `PermitRootLogin no`.
7. After installation, you can SSH as the admin user:
   ```bash
   ssh -i /var/lib/admiral/ssh-delivery/worker-01.ed25519 \
     admiral-ssh@198.51.100.20
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
| `--ssh-public-key <path>` | Public key authorized for the generated administrator |
| `--ssh-fingerprint <fingerprint>` | Expected SSH host key fingerprint for MITM verification |

### Service Map

| Mode | Services started by the installer |
|------|-----------------------------------|
| single-node | `postgresql`, `caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor` |
| admin-node | `postgresql`, `caddy`, `admirald`, `admiral-flagship` |
| admin-portal-node | `postgresql`, `caddy`, `admirald`, `admiral-flagship`, `admiral-harbor` |
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

The mandatory Tier 1 platform family is Enterprise Linux 10: RHEL 10,
CentOS Stream 10, Rocky Linux 10, and AlmaLinux 10. The same production
installer modes and security controls apply to all four. Installation applies
currently available vendor security errata and enables
`dnf-automatic.timer` for subsequent security updates. Kernel updates can
still require an operator-controlled reboot. Fail2ban uses its native nftables
action and the playbook exercises a temporary documentation-range ban to prove
that an effective kernel rule is installed.

Fedora Rawhide is Tier 2 and is supported only through `--dev-node`. That
profile is insecure by design and does not receive the conditional EL10
production update policy or the complete production hardening baseline.

### Configuring secure spoke egress

Worker and dedicated portal nodes use a default-deny outbound nftables policy.
TCP 587 is explicitly allowed for SMTP submission so Harbor and Flagship can
send quota, account, and operational notifications.
It permits only loopback, established traffic, the Admiral VPN, SSH, DNS
(UDP/TCP 53), NTP (UDP 123), HTTPS (TCP 443), and WireGuard (UDP 51820). All
other outbound traffic is rejected for both IPv4 and IPv6. DNS and HTTPS are
intentionally allowed by port rather than by fixed IP: Docker Hub and PayPal
use rotating CDN addresses, and resolver addresses may be supplied dynamically
by DHCP.

This is a node-level baseline, not an application egress allowlist. The
installer verifies that `chronyd` has actually synchronized the host clock;
correct time is required for TLS, token expiry, and trustworthy audit
timestamps. The policy keeps the node operational without brittle endpoint
lists; image policy, digests, and workload-specific restrictions remain
separate controls. This mirrors Kubernetes, where node networking is distinct
from optional per-Pod `NetworkPolicy` egress isolation.

The WireGuard topology is deliberately hub-and-spoke. Spokes install only a
`10.99.0.1/32` route to the admin hub, IP forwarding is disabled, and
`wg-admiral` belongs to a dedicated firewalld zone with a `DROP` target. Worker
and portal nodes therefore cannot use the admin node to route traffic directly
to one another.

References: [Kubernetes network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
and [Kubernetes cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/).

`--dev-node` is explicitly an evaluation mode and does **not** apply all production hardening controls. In dev-node mode:

- Fail2ban protections are not applied.
- Strict egress control is not enforced.
- Post-install security checklist warnings are skipped.

Use `--dev-node` only for temporary testing workflows where direct port access is required.

The installer enables the signed Caddy and Admiral COPR repositories. It
refuses repository definitions that do not enable RPM GPG metadata checking;
operators should still review the repository trust policy and pin package
versions through their normal RPM/COPR change-control process before production
rollouts.

## SELinux Recommended Configuration

Admiral expects SELinux to stay enabled. The recommended operational state is:

- SELinux in `Enforcing` mode
- `httpd_can_network_connect` boolean set to `on`
- `container_manage_cgroup` boolean set to `on` on `single-node` and
  `worker-node` hosts

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

## Current Beta 18 Validation Status

The July 29, 2026 validation confirmed the following runtime path:

```text
admirald ⇄ authenticated API over WireGuard ⇄ admiral-fleet
                                      ↓
                         rootless Podman as admiral-apps
```

SSH is used only by `install.sh` as a temporary bootstrap transport for
remote spoke configuration. Fleet does not use SSH to execute workloads or
exchange tasks, heartbeats, or results.

Validated evidence:

- Rocky Linux 10 single-node with local
  `admiral-fleet-0.0.1beta18-2.fc44.x86_64.rpm`;
- Rocky Linux 10 private multinode with the same RPM on `rocky-worker`;
- WordPress/MariaDB provisioned successfully in both modes;
- `setup_completed=true`, `health_status=healthy`, and
  `technical_status=running`;
- Podman reported `rootless=true` with graph root
  `/var/lib/admiral-apps/.local/share/containers/storage`;
- the Fleet healthcheck fix is commit
  `7eec3c25b81a7babf7967a8039241c66546cdfd9`.
- WireGuard peer persistence is commit
  `613b2651497fd5032d4ce2f80a23928605d81147`; re-running the admin installer
  was verified to preserve the worker peer and handshake.

When testing a private multinode worker, use the worker WireGuard address for
the published workload port. The WordPress example uses `http://localhost` as
its initial `siteurl`; a direct request to an ephemeral published port can
therefore redirect to port 80. Treat `setup_completed` and the Fleet operation
result as the provisioning gate, and configure a real external hostname/URL
before using the example as an HTTP routing test.

Still required before calling the beta18 validation complete: backup/restore
against private S3 with TLS and a second private topology. WireGuard
re-convergence is now validated.

## Local KVM Validation Host

A clean KVM guest is preferable to repeatedly reconciling an existing Admiral
host when validating installer, RPM, SELinux, firewall, rootless Podman, or
first-boot behavior. See
[`local_kvm_cloud_setup.md`](local_kvm_cloud_setup.md) for the complete lab
topology and golden WordPress test.

On a disposable validation host with only about 4 GiB of RAM, a 4 GiB swap file
can prevent QEMU, package updates, or image pulls from triggering the OOM
killer. This is a laboratory safeguard, not a replacement for enough production
RAM and not a performance recommendation.

Create it once using an explicit path:

```bash
sudo install -d -m 0700 /var/swap
sudo fallocate -l 4G /var/swap/admiral-test.swap
sudo chmod 0600 /var/swap/admiral-test.swap
sudo mkswap /var/swap/admiral-test.swap
sudo swapon /var/swap/admiral-test.swap
grep -qxF '/var/swap/admiral-test.swap none swap defaults 0 0' /etc/fstab \
  || echo '/var/swap/admiral-test.swap none swap defaults 0 0' \
     | sudo tee -a /etc/fstab
sudo findmnt --verify
```

Monitor the host while testing:

```bash
free -h
swapon --show
ps -C qemu-kvm -o pid,rss,cmd
```

Multi-node validation should use 8–12 GiB of host RAM rather than relying on
swap for several simultaneous guests.

## References

- `docs/admiral-installation-guide.md` for the full install runbook
- `docs/networking_v1.md` for network behavior
- `admiralctl/docs/man.md` for the CLI reference
