# Admiral beta12 multinode check

Date: 2026-06-26
Workspace: `/root/admiral`
Admin VPS: `161.35.112.132`

## Beta13 release update

Date: 2026-06-27

- Bumped all Admiral components to `0.0.1beta13`.
- Committed component release bumps in the submodules:
  - `admirald`: `6dee59c` then `36452ce` for the logging test correction.
  - `admiral-fleet`: `8013eed`.
  - `admiralctl`: `cad24d5`.
  - `admiral-flagship`: `bbfec70`.
  - `admiral-harbor`: `8c678d6`.
- Pushed all submodule `main` branches to origin before packaging.
- Added multinode portal routing fixes:
  - Ansible now binds Harbor to `127.0.0.1:5001` only for `--single-node` or a supported same-host admin+portal installation.
  - Dedicated `--portal-node` binds Harbor to its WireGuard IP on port `5001`.
  - Portal-node installation updates the admin `admirald` override with the effective portal target and runs `admiralctl routes sync`.
  - `admirald` now allows replacing a default portal route target of `https://127.0.0.1:5001` with the Ansible-provided target while preserving custom targets.
- Corrected the existing `admirald/internal/logging` test to match the current secure behavior: sensitive values are fully masked as `****`.
- Updated release packaging:
  - `Makefile` version is `0.0.1beta13`.
  - All six Admiral specs use `Version: 0.0.1beta13`.
  - All six Admiral specs reset to `Release: 1%{?dist}`.
  - Monorepo-backed specs currently pin `%global commit` to the repo-mother commit that includes the `admirald` test fix.
  - `admiral-flagship` and `admiral-harbor` specs pin their submodule release commits directly.
- RPM rebuild started from a clean `packaging/build` after the logging test fix. The clean rebuild is expected to produce:
  - `admiral-common-0.0.1beta13-1.el10.noarch.rpm`
  - `admirald-0.0.1beta13-1.el10.x86_64.rpm`
  - `admiral-fleet-0.0.1beta13-1.el10.x86_64.rpm`
  - `admiralctl-0.0.1beta13-1.el10.x86_64.rpm`
  - `admiral-flagship-0.0.1beta13-1.el10.noarch.rpm`
  - `admiral-harbor-0.0.1beta13-1.el10.noarch.rpm`
- Clean RPM rebuild completed successfully and produced all six beta13 RPMs.
- Published the six beta13 SRPMs for COPR import over temporary HTTP on port 8000, then closed the port after import.
- Confirmed component CI with `gh`:
  - `admirald` `36452ce`: green.
  - `admiral-fleet` `8013eed`: green.
  - `admiralctl` `cad24d5`: green.
  - `admiral-flagship` `bbfec70`: green.
  - `admiral-harbor` `8c678d6`: green.
  - Repo mother `admiral` had no Actions run recorded for the beta13 packaging commit at the time checked.

## Beta13 common package follow-up

Date: 2026-06-27

- First COPR build of `admiral-common-0.0.1beta13-1` failed on upgrade because `%sysusers_create_package` was left literal in the generated RPM scriptlet:
  - Runtime error: `/var/tmp/rpm-tmp.*: line 1: fg: no job control`.
  - Root cause: COPR build environment did not have the sysusers macro available during spec parsing.
- Kept the sysusers macro approach and fixed packaging by adding `BuildRequires: systemd-rpm-macros`.
- Released `admiral-common-0.0.1beta13-2` and imported the SRPM into COPR.
- Re-ran `dnf --refresh update 'admiral*'`:
  - Admin node updated to `admiral-common-0.0.1beta13-2.el10`, `admirald-0.0.1beta13-1.el10`, `admiral-flagship-0.0.1beta13-1.el10`, and `admiralctl-0.0.1beta13-1.el10`.
  - Portal node updated to `admiral-common-0.0.1beta13-2.el10`, `admiral-harbor-0.0.1beta13-1.el10`, and `admiralctl-0.0.1beta13-1.el10`.
  - EL10 workers updated to `admiral-common-0.0.1beta13-2.el10`, `admiral-fleet-0.0.1beta13-1.el10`, and `admiralctl-0.0.1beta13-1.el10`.
  - Fedora worker still needs the Fedora `admiral-common` rebuild equivalent because COPR exposed `0.0.1beta13-1.fc44` during that update attempt.
- Re-ran `scripts/install.sh --portal-node` for `157.245.81.44` from the admin node with:
  - `--admin-endpoint 161.35.112.132`
  - `--node-id portal-001`
  - `--wireguard-ip 10.99.0.100`
- The portal-node playbook completed with `failed=0` and registered/synchronized the portal route to `https://10.99.0.100:5001`.
- Found one remaining idempotency bug: changing the Harbor systemd bind override did not restart an already running `admiral-harbor` service because the task used `state: started`.
- Manually restarted `admiral-harbor` on the portal node, after which Harbor listened on `10.99.0.100:5001` and responded `HTTP/1.1 200 OK`.
- Confirmed public portal recovery:
  - `https://portal.pinky.bmogroup.solutions` returned `HTTP/2 200`.
  - `admiralctl routes list --output json` showed the portal route as `healthy` and targeting `https://10.99.0.100:5001`.
- Fixed the playbook so Harbor restarts automatically when `/etc/systemd/system/admiral-harbor.service.d/override.conf` changes.
- Released `admiral-common-0.0.1beta13-3` with the Harbor restart fix and served `admiral-common-0.0.1beta13-3.el10.src.rpm` for COPR import over temporary HTTP on port 8000.

## Session summary

- Reviewed `scripts/install.sh`, Ansible playbooks, and `packaging/`.
- Confirmed multinode spoke installs are intended to run serially from the admin node.
- Confirmed `/etc/admiral/secrets` and `/etc/admiral/tls/ca.pem` are created during the first admin install.
- Confirmed `/var/lib/admiral/know_host.yaml` is regenerated by `admirald` after node registration and heartbeat syncs.
- Agreed that the preferred multinode flow is to pass explicit spoke parameters and keep `know_host.yaml` as operator sugar and fallback.
- Decided to update `admiral-common` before the real multinode run so `install.sh` and the packaged playbooks match the preferred operator workflow.
- Moved system account creation into `admiral-common` packaging via RPM `sysusers`, removing the temporary Ansible bootstrap workaround.
- Admin-node validation completed successfully on `161.35.112.132`.
- Portal-node validation completed successfully on `157.245.81.44`.
- Worker-001, worker-002, worker-003, and worker-004 all completed via `install.sh` after preinstalling `admiral-common-0.0.1beta12-8.el10` on each worker host.
- `worker-001` required an `admiral-fleet` restart after the bootstrap to clear a transient HTTP 401 heartbeat failure; it is now healthy.

## Findings from review

- `install.sh` needed explicit `--wireguard-ip` support for `--worker-node` and `--portal-node`.
- `install.sh` needed a better `--admin-node` default than persisting loopback for later spoke bootstraps.
- `admiral_wireguard` only rendered `wg-admiral.conf` on first install, which made retries and config changes brittle.
- `admiral_harbor` generated `harbor.env` with two misindented lines:
  - `ADMIRAL_CA_FILE`
  - `ADMIRAL_INSECURE_SKIP_VERIFY`
- `portal-node` registration happened before Harbor was installed and started.
- `install.sh` final portal verification missed Harbor timers.
- `admiral-common` should own `admiral` and `admiral-apps` system account creation through the RPM, not Ansible.
- `--single-node` must keep its current behavior.

## Runtime status

- Admin node: installed and active.
- Portal node: installed and active.
- Worker-001: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Worker-002: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Worker-003: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Worker-004: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Control plane snapshot shows worker-001 through worker-004 as `active` and `healthy` in `admirald`.

## Commands used during analysis

```bash
rg --files -g 'install.sh' -g 'ansible/**' -g 'packaging/**' -g 'Makefile' -g '*.md'
```

```bash
sed -n '1,240p' scripts/install.sh
sed -n '240,420p' scripts/install.sh
sed -n '1,220p' ansible/site.yml
sed -n '1,260p' ansible/roles/admiral_common/tasks/main.yml
sed -n '260,760p' ansible/roles/admiral_common/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_fleet/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_harbor/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_wireguard/tasks/main.yml
sed -n '1,220p' ansible/roles/admirald/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_flagship/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_firewall/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_selinux/tasks/main.yml
sed -n '1,220p' packaging/rpm/admiral-common.spec
sed -n '1,340p' Makefile
```

```bash
rg -n "know_host\\.yaml|next\\.worker|next\\.portal|wireguard_ip|nodes register|register node|known host" admirald admiralctl admiral-fleet ansible -S
sed -n '1,240p' /var/lib/admiral/know_host.yaml
sed -n '1,280p' admirald/internal/api/handlers_nodes.go
sed -n '140,220p' admirald/internal/api/api.go
```

```bash
bash -n scripts/install.sh
python3 - <<'PY'
import yaml
for path in ['ansible/site.yml', 'ansible/wireguard-peers.yml']:
    with open(path) as f:
        yaml.safe_load(f)
    print(path, 'YAML_OK')
PY
ansible-playbook ansible/site.yml -i ansible/inventory/localhost.yml --syntax-check -e admiral_install_mode=admin-node -e fleet_public_ip=161.35.112.132
```

## Preferred setup commands

Admin:

```bash
admiral_install --admin-node --public-ip 161.35.112.132
```

Portal:

```bash
admiral_install --portal-node \
  --public-ip 157.245.81.44 \
  --admin-endpoint 161.35.112.132 \
  --node-id portal-001 \
  --wireguard-ip 10.99.0.100 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

Workers:

```bash
admiral_install --worker-node \
  --public-ip 161.35.101.241 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-001 \
  --wireguard-ip 10.99.0.2 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

Worker-001 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@161.35.101.241:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@161.35.101.241 'dnf install -y /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

Worker-002 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@161.35.102.59:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@161.35.102.59 'rpm -Uvh --nodeps /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

Worker-003 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@159.223.163.220:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@159.223.163.220 'rpm -Uvh --nodeps /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

Worker-004 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@143.198.163.223:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@143.198.163.223 'rpm -Uvh --nodeps /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

```bash
admiralctl nodes list --output json
wg show wg-admiral
```

```bash
admiral_install --worker-node \
  --public-ip 161.35.102.59 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-002 \
  --wireguard-ip 10.99.0.3 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

```bash
admiral_install --worker-node \
  --public-ip 159.223.163.220 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-003 \
  --wireguard-ip 10.99.0.4 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

```bash
admiral_install --worker-node \
  --public-ip 143.198.163.223 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-004 \
  --wireguard-ip 10.99.0.5 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

## Verification commands

Admin:

```bash
systemctl is-active postgresql caddy admirald cockpit.socket
admiralctl nodes list --output json
wg show wg-admiral
cat /var/lib/admiral/know_host.yaml
```

Portal:

```bash
ssh -i /root/keys/ssh-key-2025-05-24.key root@157.245.81.44 \
  systemctl is-active postgresql admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer
```

Workers:

```bash
ssh -i /root/keys/ssh-key-2025-05-24.key root@161.35.101.241 systemctl is-active admiral-fleet
ssh -i /root/keys/ssh-key-2025-05-24.key root@161.35.102.59 systemctl is-active admiral-fleet
ssh -i /root/keys/ssh-key-2025-05-24.key root@159.223.163.220 systemctl is-active admiral-fleet
ssh -i /root/keys/ssh-key-2025-05-24.key root@143.198.163.223 systemctl is-active admiral-fleet
```
