# Admiral beta20 validation

Date: 2026-08-03
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
| admiral-common | `0.0.1beta20-49.el10.noarch` |
| admirald | `0.0.1beta20-17.el10.x86_64` |
| admiral-fleet | `0.0.1beta20-22.el10.x86_64` |
| admiralctl | `0.0.1beta20-15.el10.x86_64` |
| admiral-flagship | `0.0.1beta20-14.el10.noarch` |
| admiral-harbor | `0.0.1beta20-16.el10.noarch` |

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

Result: PASS. Ansible completed with `ok=184 changed=23 failed=0`, and the
installer completed its Harbor API verification. `admirald`, `admiral-fleet`,
`admiral-harbor`, Caddy, and PostgreSQL were active after installation. No
systemd units were failed.

The installer update phase upgraded the EL10 host packages and regenerated
kernel initramfs images before Ansible ran.

## Golden WordPress lifecycle

Application: `examples/apps/wordpress.yaml`
Customer: `beta20-rc1-20260803d`
Instance: `inst_c6df276d4a7bd859`
Node: `rocky-linux-s-2vcpu-4gb-nyc1`  
Tier: `small`

| Stage | Evidence | Result |
| --- | --- | --- |
| Apply definition | `admiralctl apps apply` | PASS |
| Provision and setup | `op_d3bf6b6ea6d570f9`, `setup_completed=true` | PASS |
| Rootless runtime | Containers owned by `admiral-apps`; cgroup under `user-991.slice` | PASS |
| HTTP | WordPress returned HTTP 200 with `Host: localhost` on mapped port 40006 | PASS |
| Backup | `op_0c8ea49aa3446710`, backup `bk_6eb2221535a476f5`, status `succeeded` | PASS |
| Backup checksum | `697a6f60c855ede98d35df36196b071b64e145d13df3f7aa493821d06fa33fea` matched the file | PASS |
| Backup ownership | `admiral-apps:admiral-apps`, mode `0600` | PASS |
| Pause | `op_87f0362599d24fdc`, endpoint unavailable while paused | PASS |
| Resume | `op_0a1c8c9d15b25f60`, HTTP 200 restored | PASS |
| Deprovision | `op_bce3df28561b8a6c`, `technical_status=deprovisioned` | PASS |
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
`5d8bf2e`, `96bc83c`, `bb2084f`, `b216870`, `000343d`, `a6afeb4`, and
`cd36c62`, packaged as the
latest releases above. The installer changes were validated with
`ansible-playbook --syntax-check ansible/site.yml` and the 48 installer tests.

The wildcard renewal hook was syntax-checked and its atomic deployment,
certificate/key matching, permissions, service restart, and healthcheck
contract were covered by `scripts/test_admiral_https_setup.py` (6 passed).

The full Harbor test suite passed with 287 tests (16 warnings).

The RC1 security disposition is recorded in `notas.md`: node registration
tokens are passed through the task environment with `no_log`, bootstrap SSH is
accepted as a temporary per-node design with explicit mitigation, and S3
production TLS remains a pre-1.0 gate rather than a claim of local validation.

The unprivileged `scripts/install.sh --help` contract and installer test suite
passed: 52 tests, with `--help` returning exit code 0 for `nobody`.

Release reference validation passed after checking the Makefile pins, RPM
spec pins, and submodule HEADs.
