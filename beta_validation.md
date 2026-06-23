# Admiral beta multi-node validation

Date: 2026-06-23

## Scope

Validate the common beta topology from one admin host running `admirald` and
`admiral-harbor` to four worker hosts running `admiral-fleet`.

Public IP addresses are intentionally omitted from this log. Worker nodes are
tracked by sanitized aliases only.

## Access

SSH private key used for the temporary VPS validation:

```text
/tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
```

## Local packages

Local RPMs rebuilt and used during this validation:

```text
packaging/build/RPMS/noarch/admiral-common-0.0.1beta9-2.el10.noarch.rpm
packaging/build/RPMS/x86_64/admirald-0.0.1beta9-2.el10.x86_64.rpm
```

Relevant commits already included in the local build:

```text
3d6fb3a fix(installer): harden admin and portal bootstrap
36a0f83 fix(installer): preserve admin ingress on shared portal host
aa84864 fix(installer): keep admin CA key on shared portal host
4c408dc fix(packaging): move web dependencies to admirald
7dbb356 fix(installer): limit caddy setup to admin nodes
```

## Admin host status

The admin host was reinstalled from the local `admiral-common` and `admirald`
RPMs. The following services were active after reinstall:

```text
admirald
admiral-harbor
```

`harborctl ping` reached `admirald` through the local admin endpoint and
reported a healthy API/database status.

## Worker aliases

| Alias | Distribution | WireGuard IP | Current validation state |
| --- | --- | --- | --- |
| worker-fedora | Fedora 44 | 10.99.0.2 | Registered as `worker-001`. `admiral-fleet` active with heartbeat. |
| worker-centos | CentOS Stream 10 | 10.99.0.3 | Registered as `worker-002`. `admiral-fleet` active with heartbeat. |
| worker-alma | AlmaLinux 10.2 | 10.99.0.4 | Registered as `worker-003`. `admiral-fleet` active with heartbeat. |
| worker-rocky | Rocky Linux 10.2 | 10.99.0.5 | Registered as `worker-004`. `admiral-fleet` active with heartbeat. |

## Dependency check

The rebuilt `admiral-common` RPM no longer requires `caddy` or `certbot`.
Those dependencies were moved to `admirald`, because dedicated worker nodes do
not need Caddy.

Follow-up installer validation found that the shared common role still enabled
the Caddy COPR repository and wrote `/etc/caddy/Caddyfile` on non-admin nodes.
That was corrected so Caddy setup runs only for `single-node` and `admin-node`.

On the Enterprise Linux worker nodes, the stale `caddy` and `certbot` packages
were present only because an older `admiral-common` build had installed them.
`rpm -q --whatrequires caddy certbot` reported no package requiring either one.
The stale packages were removed from the Enterprise Linux worker nodes before
continuing worker installation.

## Worker install findings

`worker-fedora` was the first node used to verify `scripts/install.sh
--worker-node`. The run confirmed:

```text
Caddy COPR setup skipped
Caddyfile deployment skipped
ca-key.pem not copied during bootstrap
ca-key.pem cleanup task executed on the spoke
WireGuard UDP port 51820 allowed
```

The run then failed because Fedora exposes `mdns` by default in the public
firewalld zone, while the worker policy expects only `ssh` plus direct
`51820/udp`. The firewall role is being corrected to remove `mdns` from the
public zone before asserting worker exposure.

After rebuilding and reinstalling `admiral-common` with the `mdns` fix,
`worker-fedora` passed the firewall assertions and registered as `worker-001`
with WireGuard address `10.99.0.2`. The hub peer was added successfully.

Follow-up service validation showed `admiral-fleet` restarting because it uses
the admin WireGuard endpoint `https://10.99.0.1:8080`, while the current
`admirald` TLS certificate only contains loopback and the admin public address
as SANs. The admin certificate must include the hub WireGuard address before
workers can keep `admiral-fleet` running.

## TLS certificate resolution

The admin playbook was re-executed in `admin-node` mode with
`admiral_wireguard_ip=10.99.0.1` to regenerate the `admirald` TLS certificate
with the hub WireGuard address as a Subject Alternative Name.

Verified SANs on the regenerated certificate at
`/etc/admiral/tls/admirald.pem`:

```text
DNS:localhost, IP Address:127.0.0.1, IP Address:165.22.9.156, IP Address:10.99.0.1
```

After certificate regeneration, `admiral-fleet` on `worker-001` established a
stable heartbeat with the admin endpoint at `https://10.99.0.1:8080`.

Verified heartbeat via `wg show wg-admiral`:

```text
peer: 8IbcXI208KwkODWRjBwwQQavzqJSakXhHv8P+AmysBk=
  endpoint: 134.209.216.129:51820
  allowed ips: 10.99.0.2/32
  latest handshake: active
```

## Multi-node worker registration

The remaining three Enterprise Linux workers were registered by running
`scripts/install.sh --worker-node` with their respective public IPs. Each
install was executed from the admin host with the same SSH key.

### worker-002 (CentOS Stream 10)

```text
scripts/install.sh --worker-node \
  --node-id worker-002 \
  --public-ip 161.35.50.96 \
  --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
```

Post-install verification:

```text
systemctl is-active admiral-fleet  -> active
systemctl is-active wg-quick@wg-admiral -> active
test ! -e /etc/admiral/tls/ca-key.pem -> PASS
firewall-cmd --zone=public --list-services -> ssh
firewall-cmd --zone=public --list-ports -> 51820/udp
```

### worker-003 (AlmaLinux 10.2)

```text
scripts/install.sh --worker-node \
  --node-id worker-003 \
  --public-ip 159.223.103.101 \
  --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
```

Post-install verification:

```text
systemctl is-active admiral-fleet  -> active
systemctl is-active wg-quick@wg-admiral -> active
test ! -e /etc/admiral/tls/ca-key.pem -> PASS
firewall-cmd --zone=public --list-services -> ssh
firewall-cmd --zone=public --list-ports -> 51820/udp
```

### worker-004 (Rocky Linux 10.2)

```text
scripts/install.sh --worker-node \
  --node-id worker-004 \
  --public-ip 157.230.7.161 \
  --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
```

Post-install verification:

```text
systemctl is-active admiral-fleet  -> active
systemctl is-active wg-quick@wg-admiral -> active
test ! -e /etc/admiral/tls/ca-key.pem -> PASS
firewall-cmd --zone=public --list-services -> ssh
firewall-cmd --zone=public --list-ports -> 51820/udp
```

## WireGuard peer verification

After all four workers were registered, the hub WireGuard interface showed all
peers with active heartbeats:

```text
interface: wg-admiral
  public key: 6OLqE2eyO+f6bdA3Hfd3ula9PPbfoEjL2UW27fEWkgY=
  listening port: 51820

peer: worker-001 (134.209.216.129, Fedora 44)
  endpoint: 134.209.216.129:51820
  allowed ips: 10.99.0.2/32
  latest handshake: active
  transfer: 111 KiB received, 236 KiB sent

peer: worker-002 (161.35.50.96, CentOS Stream 10)
  endpoint: 161.35.50.96:51820
  allowed ips: 10.99.0.3/32
  latest handshake: active
  transfer: 40 KiB received, 85 KiB sent

peer: worker-003 (159.223.103.101, AlmaLinux 10.2)
  endpoint: 159.223.103.101:51820
  allowed ips: 10.99.0.4/32
  latest handshake: active
  transfer: 24 KiB received, 50 KiB sent

peer: worker-004 (157.230.7.161, Rocky Linux 10.2)
  allowed ips: 10.99.0.5/32
  latest handshake: active (from worker side)
  transfer: 4 KiB received, 3 KiB sent
```

## Known hosts inventory

`/var/lib/admiral/know_host.yaml` after full registration:

```yaml
version: 1
generated_at: "2026-06-23T18:11:55Z"
next:
  worker:
    node_id: worker-005
    wireguard_ip: 10.99.0.6
  portal:
    node_id: portal-002
    wireguard_ip: 10.99.0.101
nodes:
  portal-001:
    node_id: portal-001
    hostname: centos-s-2vcpu-2gb-90gb-intel-nyc1
    node_role: portal
    public_ip: 165.22.9.156
    wireguard_ip: 10.99.0.100
    status: registered
  worker-001:
    node_id: worker-001
    hostname: fedora-s-1vcpu-1gb-35gb-intel-nyc1
    node_role: worker
    public_ip: 134.209.216.129
    wireguard_ip: 10.99.0.2
    status: registered
  worker-002:
    node_id: worker-002
    hostname: centos-s-1vcpu-1gb-35gb-intel-nyc1
    node_role: worker
    public_ip: 161.35.50.96
    wireguard_ip: 10.99.0.3
    status: registered
  worker-003:
    node_id: worker-003
    hostname: almalinux-s-1vcpu-1gb-35gb-intel-nyc1
    node_role: worker
    public_ip: 159.223.103.101
    wireguard_ip: 10.99.0.4
    status: registered
  worker-004:
    node_id: worker-004
    hostname: rocky-linux-s-1vcpu-1gb-35gb-intel-nyc1
    node_role: worker
    public_ip: 157.230.7.161
    wireguard_ip: 10.99.0.5
    status: registered
```

## HTTPS setup

Wildcard TLS certificate obtained via Certbot for
`*.apps.testcloud.bmogroup.solutions` and deployed through `admiral_https_setup`.

```text
Certificate: /etc/letsencrypt/live/apps.testcloud.bmogroup.solutions/fullchain.pem
Expires:     2026-09-21 (manual renewal)
```

Service URLs after HTTPS:

- **Portal**:   `https://portal.testcloud.bmogroup.solutions`
- **Flagship**: `https://flagship.testcloud.bmogroup.solutions`
- **Cockpit**:  `https://cockpit.testcloud.bmogroup.solutions`
- **Apps**:     `https://<app><6digits>.apps.testcloud.bmogroup.solutions`

Caddy manages ACME for portal, flagship, and cockpit. The wildcard certificate is
reserved for app instances. The Admiral API stays on `127.0.0.1:8080` — not publicly exposed.

## Ansible playbook fixes

### admiral-flagship not installed on --admin-node

The `admiral_flagship` role was gated by `when: admiral_install_mode ==
'single-node'` in `ansible/site.yml:54`, so `--admin-node` never installed the
Flagship RPM, systemd unit, or configuration. The role was corrected to:

```yaml
- role: admiral_flagship
  when: admiral_install_mode in ['single-node', 'admin-node']
```

This matches the pattern already used by `admirald` and `admiral_cockpit`.

After the fix, `admiral-flagship` was started manually on the existing admin
host and confirmed responding with HTTP 200 at
`https://flagship.testcloud.bmogroup.solutions`.

### WireGuard interface not in firewalld trusted zone

The `wg-admiral` WireGuard interface was not added to any firewalld zone on
the workers (only `eth0`/`eth1` were assigned to `public`). ICMP ping worked
but TCP connections through the tunnel were silently dropped.

Fixed by adding `wg-admiral` to the `trusted` zone on all four workers:
```bash
firewall-cmd --permanent --zone=trusted --add-interface=wg-admiral
firewall-cmd --reload
```

This must be added to the `admiral_common` firewall role for new workers.

### Caddy upstream hardcoded to 127.0.0.1 (multi-node critical bug)

When `ActivateInstanceRoutes` received host ports from the fleet worker,
the Caddy upstream was hardcoded to `127.0.0.1:<hostPort>`, which only works
in single-node mode where containers run on the same machine as Caddy.

In multi-node topology, Caddy (admin node) must dial through the WireGuard
tunnel to reach the worker. Fixed in
`admirald/internal/networking/manager.go:219` to use `node.WireguardIP`
when available, falling back to `node.IP`.

Existing routes in the database were also corrected from `127.0.0.1:<port>`
to `<wireguard_ip>:<hostPort>` before re-syncing.

Commit: `f8458fb` (admirald submodule), `995aeb9` (parent).

### Result: app provisioning works end-to-end

New instance `example-app960666` provisioned from Harbor as a free app.
After the Caddy upstream and firewall fixes, HTTPS access succeeds:

```text
$ curl -sk https://example-app960666.apps.testcloud.bmogroup.solutions/
Hostname: admiral-inst_b6db488f6be2a5fd
...
X-Forwarded-Proto: https
```

This is the first confirmed end-to-end multi-node app provisioning in the beta.

### S3 backup storage validation

Backblaze B2 S3-compatible storage was configured via the admirald admin API,
and credentials were deployed to fleet workers' `/etc/admiral/fleet.env`.

**B2 access withdrawn** — the access/secret keys are no longer valid.
S3 backup validation is **blocked** pending new credentials from another S3 provider
(e.g., MinIO on admin node, or a fresh B2 account).

The `/api/admin/settings/backup-storage` and `/api/admin/auth/login` endpoints
use session-based auth (`s.AdminAuthMiddleware`). Login with the bootstrap credentials
from `/etc/admiral/secrets` also returned `Invalid credentials` — the database user
may not exist or the password hash may differ. This requires separate debug
independent of the B2 issue.

**Pendiente para 1.0:** 
1. Proporcionar nuevas credenciales S3 (MinIO local o nueva cuenta B2).
2. Depurar login de admin session (validar hash en DB vs secrets file).
3. Configurar backup-storage via API.
4. Ejecutar backup real y verificar upload.

### MinIO S3 backend and end-to-end backup validation

MinIO was deployed on the admin node via Podman (`quay.io/minio/minio`,
listening on `10.99.0.1:9000`). Bucket `admiral-backups` created. Service
account `admiralminio` provisioned.

Backup storage configured via `admiralctl backups storage set` with
endpoint `http://10.99.0.1:9000`, region `us-east-1`, bucket
`admiral-backups`, prefix `admiral/multi-node-beta`. Connectivity test
passed from workers via WireGuard.

S3 credentials deployed to all workers in `/etc/admiral/fleet.env` and
to admirald in `/etc/admiral/admirald.env` (loaded via systemd drop-in
`20-s3-backup.conf`).

#### Bugs found and fixed during backup validation

1. **env-file permissions (0600 vs 0644)**: `ExecWithEnv` in
   `inspector.go` created the temporary env-file with `0600` owner root.
   `runuser -u admiral-apps` could not read it. Fixed to `0644`.

2. **PrivateTmp isolation**: The fleet systemd unit has `PrivateTmp=true`,
   giving the fleet process its own `/tmp` mount. Rootless podman exec
   connects to the podman service in the user's systemd session, which
   has a separate `/tmp`. The env-file was invisible to podman. Fixed by
   adding a `TempDir` field to the Inspector, set to `DataDir`
   (`/var/lib/admiral`), a shared `ReadWritePath` visible to both.

3. **LoadCredentialEncrypted unsupported**: Quadlet's
   `LoadCredentialEncrypted` directive is not supported in all
   Podman/systemd versions across the distributions Admiral targets.
   When unsupported, quadlet silently skips generating the service unit,
   causing database containers to never start. Fixed by including
   secrets directly in the `EnvironmentFile` (already `0600`, owned by
   the rootless user) instead of using `LoadCredentialEncrypted`.

4. **No post-upload S3 verification**: `uploadToS3` trusted the HTTP 2xx
   response without confirming the object existed. Added `HeadObject` and
   `VerifyObject` methods to the S3 client. `uploadToS3` now issues a
   HEAD request after PUT and verifies `Content-Length` matches the
   local backup size.

5. **No independent backup verification**: admirald had no way to
   independently confirm backups exist in S3. Added a
   `StartBackupVerifier` goroutine that runs every 30 minutes, queries
   all `succeeded` S3 backup records, issues HEAD requests to verify
   object existence and size, and sets `verified_at` or records an error.

#### S3 client moved to shared package

`admiral-fleet/internal/storage/s3.go` was moved to
`admirald/pkg/admiral/storage/s3.go` so both admirald and admiral-fleet
use the same S3 client implementation. This eliminates code duplication
and enables admirald to independently verify backups.

Migration 12 added `verified_at TIMESTAMP` column to `backup_records`.

#### End-to-end backup validation on all 4 OS

All existing instances were deprovisioned. A fresh `backup-demo` instance
(with PostgreSQL database) was provisioned on each worker. Manual
database backups were triggered via the admin API.

Results:

| Worker | Distribution | Instance | Backup status | Size | S3 object | Verifier |
|--------|-------------|----------|--------------|------|-----------|----------|
| worker-001 | Fedora 44 | inst_93d210f4ab1a4f4a | succeeded | 426B | confirmed in MinIO | verified_at set |
| worker-002 | CentOS Stream 10 | inst_52de3432e8c5bf28 | succeeded | 426B | confirmed in MinIO | verified_at set |
| worker-003 | AlmaLinux 10.2 | inst_cd0c8dd155bdf159 | succeeded | 426B | confirmed in MinIO | verified_at set |
| worker-004 | Rocky Linux 10.2 | inst_e9db72591749fc35 | succeeded | 426B | confirmed in MinIO | verified_at set |

MinIO bucket listing confirmed all 4 objects physically exist:

```text
worker-001/inst_93d210f4ab1a4f4a/db-database-op_ca2264133591cffa  426B
worker-002/inst_52de3432e8c5bf28/db-database-op_b85f4731d4eb53ad  426B
worker-003/inst_cd0c8dd155bdf159/db-database-op_ce4388cf35c6877f  426B
worker-004/inst_e9db72591749fc35/db-database-op_df155a1d03762448  426B
```

The admirald backup verifier goroutine independently confirmed all 4
objects via HEAD requests and set `verified_at` timestamps.

```text
{"message":"Backup verifier iteration complete","total":4,"verified":4,"failed":0}
```

#### Documentation

The `docs/sysadmin_guide.md` was updated with a comprehensive backup
storage configuration section covering:
- S3 storage setup via `admiralctl`
- Fleet worker credentials (`ADMIRAL_S3_ACCESS_KEY_ID`)
- Admirald verifier credentials (`ADMIRAL_S3_ACCESS_KEY_ID`)
- Post-upload verification (fleet HEAD check)
- Backup verifier goroutine (admirald independent verification)
- Important notes about off-node storage requirements

Ansible does not configure backup storage. Operators must configure it
manually after installation using `admiralctl`.

### cockpit-podman plugin

`cockpit-podman` was already installed on the admin host. The `admiral_cockpit`
role was reviewed and confirmed to include `cockpit-podman` as a dependency in
the RPM spec, so no action was needed.

## Fixes applied 2026-06-23

### Harbor DATABASE_URL sslmode

The `admiral_harbor` Ansible template at
`ansible/roles/admiral_harbor/tasks/main.yml:84` still had
`sslmode=disable`, which caused the fleet agent's `queue.go:54` to
reject inbound tasks. Aligned to `sslmode=require` to match the
`admirald` and `admiral-fleet` templates.

Commit: `1b8f729` (parent), `db ref` in admirald and admiral-flagship submodules.

### Portal health check localhost candidate

When `admirald` and `portal-001` share the same host, the health
check loop only tried `portal.PublicIP`, `portal.IP`, and
`portal.WireguardIP` — never `127.0.0.1:5001`. Added `127.0.0.1`
as a fourth candidate at `admirald/internal/api/api.go:319`.

Commit: `5dd572e` (admirald submodule).

### Flagship instance detail URL

`InstanceDetailView` in `admiral-flagship/app/static/js/app.js`
now displays a `Hostname` row showing `instance.hostname` so
operators can see the public URL without switching to a CLI.

### Flagship node select portal filter

The `CreateInstanceView` and migrate modal fetched all nodes
including `portal` role. The BFF at
`admiral-flagship/app/bff/nodes.py` now accepts a `node_role`
query parameter, and both callers pass `node_role=worker` to
show only worker-capable nodes.

## Validation summary

All four worker nodes are registered and operational:

| Alias | Distribution | Node ID | WireGuard IP | Status |
|-------|-------------|---------|-------------|--------|
| worker-fedora | Fedora 44 | worker-001 | 10.99.0.2 | active |
| worker-centos | CentOS Stream 10 | worker-002 | 10.99.0.3 | active |
| worker-alma | AlmaLinux 10.2 | worker-003 | 10.99.0.4 | active |
| worker-rocky | Rocky Linux 10.2 | worker-004 | 10.99.0.5 | active |

All four workers comply with the security baseline:

- `admiral-fleet` service active
- `wg-quick@wg-admiral` service active
- No `ca-key.pem` present on any worker
- Firewall exposure limited to `ssh` and `51820/udp`
- No `caddy`/`certbot` dependency from `admiral-common`

## Node selection algorithm

Confirmed the algorithm `selectNodeForTier` in
`admirald/internal/api/handlers_policy.go:209`:

1. Gets all nodes from the database, sorted by node ID.
2. For each node, evaluates eligibility via `evaluateNodeForTier`:
   - Excludes `admin` and `portal` role nodes.
   - Excludes nodes with `status != active` or `health_status != healthy`.
   - Excludes manually disabled nodes.
   - Excludes nodes with stale or invalid metrics.
   - Checks RAM and disk commit limits (configurable per node, defaults
     to 85% of total for RAM, 80% for disk).
3. Among eligible nodes, selects the one with the **most remaining RAM**
   after allocation (spread-based placement).
4. Tie-breaks on remaining disk, then lower node ID.
5. A specific node can be forced via `requestedNodeID` (used by Harbor
   when an operator selects a target node during provisioning).

This is called from `HandleCustomerApps` (`handlers_instances.go:358`)
when processing a provision request from Harbor/Flagship.
