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

| Alias | Distribution | Current validation state |
| --- | --- | --- |
| worker-fedora | Fedora 44 | `admiral-common` local RPM installed; 8 GiB swap active at `/swap/swapfile`; `caddy` and `certbot` absent |
| worker-centos | CentOS Stream 10 | `admiral-common` local RPM reinstalled; 8 GiB swap active at `/swapfile`; stale `caddy` and `certbot` found from previous common dependency |
| worker-alma | AlmaLinux 10.2 | `admiral-common` local RPM reinstalled; 8 GiB swap active at `/swapfile`; stale `caddy` and `certbot` found from previous common dependency |
| worker-rocky | Rocky Linux 10.2 | `admiral-common` local RPM reinstalled; 8 GiB swap active at `/swapfile`; stale `caddy` and `certbot` found from previous common dependency |

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

## Pending validation

Continue with:

```text
scripts/install.sh --worker-node --node-id worker-001 --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
scripts/install.sh --worker-node --node-id worker-002 --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
scripts/install.sh --worker-node --node-id worker-003 --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
scripts/install.sh --worker-node --node-id worker-004 --ssh-key /tmp/upload_form_files/ssh-key-2025-05-24-776ad9788e26.key
```

For each worker, verify:

```text
systemctl is-active admiral-fleet
systemctl is-active wg-quick@wg-admiral
test ! -e /etc/admiral/tls/ca-key.pem
firewall-cmd --zone=public --list-services
firewall-cmd --zone=public --list-ports
```

Expected worker firewall exposure:

```text
services: ssh
ports: 51820/udp
```

Expected final state:

```text
admin: admirald active, admiral-harbor active
workers: admiral-fleet active on all four worker aliases
workers: registered in admirald with unique WireGuard addresses
workers: no ca-key.pem copied to worker hosts
workers: no caddy/certbot dependency from admiral-common
```
