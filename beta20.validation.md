# Admiral beta20 validation

Date: 2026-08-02  
Host: Rocky Linux 10 (EL10), x86_64  
Scope: local RC1 candidate packages and single-node WordPress golden test

## Source and package candidate

The five component submodules were initialized at the commits pinned by the
superproject. The local repository was built from those commits and the
superproject source tree.

The six Admiral RPMs were built with `make rpm-admiral-no-test` after raising
the package releases for the final local RC1 candidate build:

| Package | Candidate |
| --- | --- |
| admiral-common | `0.0.1beta20-45.el10.noarch` |
| admirald | `0.0.1beta20-13.el10.x86_64` |
| admiral-fleet | `0.0.1beta20-18.el10.x86_64` |
| admiralctl | `0.0.1beta20-11.el10.x86_64` |
| admiral-flagship | `0.0.1beta20-10.el10.noarch` |
| admiral-harbor | `0.0.1beta20-12.el10.noarch` |

`python3-flask-login`, `python3-flask-sqlalchemy`, and
`python3-flask-alembic` were built only as local build dependencies; they are
not Admiral release candidates.

The repository is available at `/var/lib/admiral/rpm-local` and is exposed as
the enabled `admiral-local` DNF repository in `/etc/yum.repos.d/admiral-local.repo`.
`dnf install 'admiral*' --assumeno` selected all six candidates from
`admiral-local`, not COPR. The real transaction installed all six candidates
successfully.

## Installer validation

Command:

```text
dnf install 'admiral*'
admiral-install --single-node --yes
```

Result: PASS. Ansible completed with `ok=182 changed=23 failed=0`, and the
installer completed its Harbor API verification. `admirald`, `admiral-fleet`,
`admiral-harbor`, Caddy, and PostgreSQL were active after installation. No
systemd units were failed.

The installer update phase upgraded the EL10 host packages and regenerated
kernel initramfs images before Ansible ran.

## Golden WordPress lifecycle

Application: `examples/apps/wordpress.yaml`  
Customer: `beta20-rc1-final`  
Instance: `inst_946e67049d529abd`  
Node: `rocky-linux-s-2vcpu-4gb-nyc1`  
Tier: `small`

| Stage | Evidence | Result |
| --- | --- | --- |
| Apply definition | `admiralctl apps apply` | PASS |
| Provision and setup | `op_28a736749304d9ad`, `setup_completed=true` | PASS |
| Rootless runtime | Containers owned by `admiral-apps`; cgroup under `user-991.slice` | PASS |
| HTTP | WordPress returned HTTP 200 with `Host: localhost` on mapped port 40002 | PASS |
| Backup | `op_9fe9b45775ab9d1d`, backup `bk_766ea7261b002639`, status `succeeded` | PASS |
| Backup checksum | `655584962c1d054adc1e3e8ace9fb1ed9aad505d1a4c08945d3b0f91e1182f80` matched the file | PASS |
| Backup ownership | `admiral-apps:admiral-apps`, mode `0600` | PASS |
| Pause | `op_6e6fed951b900d2c`, endpoint unavailable while paused | PASS |
| Resume | `op_02a9c14cb4586f21`, HTTP 200 restored | PASS |
| Deprovision | `op_172d8104ec6b82ff`, `technical_status=deprovisioned` | PASS |
| Runtime cleanup | No instance containers or user units remained | PASS |

The backup artifact is gzip-compressed MariaDB SQL despite its historical
`.tar.gz` storage suffix; its recorded and recalculated SHA-256 values match.

## Test observations

The first golden provision reproduced admiralctl#24: the installed binary
prefixed `--output json` with a human-readable operation line. The fix was
committed in `admiralctl` as `4718c3c`, rebuilt as
`admiralctl-0.0.1beta20-7`, and installed from `admiral-local`. A second
provision (`op_7ea3b6b6a095b378`) was parsed as one JSON document with no
prefix, then deprovisioned successfully (`op_27cfa2dafb2b4bf0`).

Flagship's full test suite passed with 240 tests after the BFF fixes in
`737b921`: node maintenance uses the node action API, resize validates the
tier whitelist, and restore sends the required service field.

The final local installation also contains the node CLI, signing-key, fleet
inspect redaction, and billing/restore hardening commits `b65cd11`, `1481c61`,
`5d8bf2e`, `96bc83c`, `bb2084f`, `b216870`, and `000343d`, packaged as the
latest releases above. The installer changes were validated with
`ansible-playbook --syntax-check ansible/site.yml` and the 46 installer tests.

The unprivileged `scripts/install.sh --help` contract and installer test suite
passed: 52 tests, with `--help` returning exit code 0 for `nobody`.

Release reference validation passed after checking the Makefile pins, RPM
spec pins, and submodule HEADs.
