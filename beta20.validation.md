# Admiral beta20 validation

Date: 2026-08-03
Host: Rocky Linux 10 (EL10), x86_64  
Scope: local RC1 candidate packages and single-node WordPress golden test

RC1 validation target is EL10 x86_64. aarch64 is a secondary platform and is
deferred from this RC1 validation gate; this document does not infer aarch64
coverage from the x86_64 run.

The package pins are the latest `origin/main` commits of every component. The
Fleet and Harbor pins were advanced after their GitHub CI runs passed.

## Source and package candidate

The five component submodules were initialized at the commits pinned by the
superproject. The local repository was built from those commits and the
superproject source tree.

The six Admiral RPMs were built with `make rpm-admiral-no-test` after raising
the package releases for the final local RC1 candidate build:

| Package | Candidate |
| --- | --- |
| admiral-common | `0.0.1beta20-54.el10.noarch` |
| admirald | `0.0.1beta20-22.el10.x86_64` |
| admiral-fleet | `0.0.1beta20-27.el10.x86_64` |
| admiralctl | `0.0.1beta20-20.el10.x86_64` |
| admiral-flagship | `0.0.1beta20-19.el10.noarch` |
| admiral-harbor | `0.0.1beta20-21.el10.noarch` |

SHA-256 of the six RPMs in `/var/lib/admiral/rpm-local`:

| Package | SHA-256 |
| --- | --- |
| admiral-common | `5dca69503a074673635bcb9b6cce99768ccd6527d129b441924d278ab322fa7b` |
| admirald | `18959fe0f334efcaab027b9a2993f6ba5517ea9613cc5c78c27261cd79592479` |
| admiral-fleet | `21c826c618e8c27f27ceed3d83be7ac35ed5ba6f26504553831405096ac712e7` |
| admiralctl | `26432427c0667d26e6180ec2a100bf682ca5ea933fe4a7ad80bf32abedc602fd` |
| admiral-flagship | `40b2151b76427f36497006f29e09d16b044b93f73988fcae2092c3ffda026f61` |
| admiral-harbor | `8dcb5254c4c8677b1be0320abd5c919105037fe0d68e8e9bd2734409731d73b7` |

`python3-flask-login`, `python3-flask-sqlalchemy`, and
`python3-flask-alembic` were built only as local build dependencies; they are
not Admiral release candidates.

The repository is available at `/var/lib/admiral/rpm-local` and is exposed as
the enabled `admiral-local` DNF repository in `/etc/yum.repos.d/admiral-local.repo`.
`dnf install 'admiral*' --assumeno` selected all six candidates from
`admiral-local`, not COPR. The real transaction upgraded and installed all six
latest candidates successfully (`54/22/27/20/19/21`).

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

A second `admiral-install --single-node --yes` run against the already
installed candidate also completed successfully. Its Ansible recap was
`ok=183 changed=19 failed=0 unreachable=0 skipped=148 rescued=0 ignored=0`;
this provides local idempotency/reconvergence evidence for the single-node
installation.

The installer update phase upgraded the EL10 host packages and regenerated
kernel initramfs images before Ansible ran.

## Golden WordPress lifecycle

Application: `examples/apps/wordpress.yaml`
Customer: `beta20-stream-20260803`
Instance: `inst_2729889e87aa5ccc`
Node: `rocky-linux-s-2vcpu-4gb-nyc1`  
Tier: `small`

| Stage | Evidence | Result |
| --- | --- | --- |
| Apply definition | `admiralctl apps apply` | PASS |
| Provision and setup | `op_6cd826e1840d7e7c`, `setup_completed=true` | PASS |
| Rootless runtime | Containers owned by `admiral-apps`; cgroup under `user-991.slice` | PASS |
| HTTP | WordPress returned HTTP 200 with `Host: localhost` on mapped port 40010 | PASS |
| Backup | `op_55efdd0e2ff797e4`, backup `bk_889bc8c1f54d327f`, status `succeeded` | PASS |
| Backup checksum | `de3c7a1b53b17ded485b57a5a3e7c9c61e2b716cf45ec5e72e020e6596605532` matched the file | PASS |
| Backup ownership | `admiral-apps:admiral-apps`, mode `0600` | PASS |
| Pause | `op_076cd00f2c0f3afd`, endpoint unavailable while paused | PASS |
| Resume | `op_5d61b8468af4e042`, HTTP 200 restored | PASS |
| Deprovision | `op_5af1284648dee015`, `technical_status=deprovisioned` | PASS |
| Runtime cleanup | No instance containers or user units remained | PASS |

The backup artifact is gzip-compressed MariaDB SQL despite its historical
`.tar.gz` storage suffix; its recorded and recalculated SHA-256 values match.

Fleet's authenticated OCI image pre-pull endpoint was included in this
candidate: `GET /api/v1/fleet/oci_images` is served by `admirald`, and the
worker accepts only the `pull` operation through its rootless lifecycle helper.

The control-plane image-update marker was exercised on instance
`inst_51d8fdd5e77ad618`: applying a changed MariaDB image set
`need_restarting=true`; successful stop/start operations
`op_4046cce2adf7d4a1` and `op_bd5286dc333ae75e` cleared it back to `false`,
then deprovision `op_4bea5440f3ba11ff` succeeded. This is only a state and
callback test: no before/after image ID or digest was captured, so it is not
accepted as proof that the workload restarted with the new image.

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
contract were covered by `scripts/test_admiral_https_setup.py` (7 passed).

The full Harbor test suite passed with 287 tests (16 warnings).

## Real restore run

Source instance `inst_ed864bf0cd2c31fa` was provisioned, then produced a
database backup `bk_b988264b924a68a3` (checksum
`7d8783bd03eec344fff766e3a079fd3b605469e41b640437c4e5417eaea30195`) and a
volume backup `bk_ee103382b94c6f62` (checksum
`b6c495bb271ce9cddb24ecfb2c70fbcecea984dd6d5fc1f9b99bffbe0452aa8d`).

The destination `inst_da5444304144b614` was provisioned and paused. Database
restore succeeded with operation `op_a1eadf15a3d7fcd9` and checksum
verification enabled. Volume restore was attempted with operation
`op_65d779bfb9a34e27` but failed while creating `.htaccess` because the
rootless Podman volume data was owned by an unmapped container UID and was not
writable by `admiral-apps`. Both lab instances were subsequently deprovisioned
successfully (`op_36b0bf9e8e34f8f4`, `op_a0801ca241a367e0`). This is recorded as
a restore-volume defect, not as a passing full restore.

The RC1 security disposition is recorded in `notas.md`: node registration
tokens are passed through the task environment with `no_log`, bootstrap SSH is
accepted as a temporary per-node design with explicit mitigation, and S3
production TLS remains a pre-1.0 gate rather than a claim of local validation.

The unprivileged `scripts/install.sh --help` contract and installer test suite
passed: 48 tests, with `--help` returning exit code 0 for `nobody`.

Release reference validation passed after checking the Makefile pins, RPM
spec pins, and submodule HEADs.
