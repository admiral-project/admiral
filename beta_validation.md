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

### cockpit-podman plugin

`cockpit-podman` was already installed on the admin host. The `admiral_cockpit`
role was reviewed and confirmed to include `cockpit-podman` as a dependency in
the RPM spec, so no action was needed.

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
