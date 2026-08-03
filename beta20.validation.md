# Admiral beta20 validation

Date: 2026-08-03
Host: Rocky Linux 10 (EL10), x86_64  
Scope: local RC1 candidate packages and single-node WordPress golden test

RC1 validation target is EL10 x86_64. aarch64 is a secondary platform and is
deferred from this RC1 validation gate; this document does not infer aarch64
coverage from the x86_64 run.

## Source and package candidate

The five component submodules were initialized at the commits pinned by the
superproject. The local repository was built from those commits and the
superproject source tree.

The six Admiral RPMs were built with `make rpm-admiral-no-test` after raising
the package releases for the final local RC1 candidate build:

| Package | Candidate |
| --- | --- |
| admiral-common | `0.0.1beta20-53.el10.noarch` |
| admirald | `0.0.1beta20-21.el10.x86_64` |
| admiral-fleet | `0.0.1beta20-26.el10.x86_64` |
| admiralctl | `0.0.1beta20-19.el10.x86_64` |
| admiral-flagship | `0.0.1beta20-18.el10.noarch` |
| admiral-harbor | `0.0.1beta20-20.el10.noarch` |

SHA-256 of the six RPMs in `/var/lib/admiral/rpm-local`:

| Package | SHA-256 |
| --- | --- |
| admiral-common | `0ee0c4bd2f32d99e680debeb3bf71714a249f3523faeca19eeeea4d20f0a9925` |
| admirald | `f8187603cc648c3e38378f3c4de1493a22c395d2b4be87146ae8b656eb8da6f6` |
| admiral-fleet | `d3725a31aec9b578b6caa4106622d3dbaced67074d14fd70329139168d73e03c` |
| admiralctl | `35324ea230f6143fccfcc1ca84c673d5cdc69c43318fe0845f66bb435b977ee8` |
| admiral-flagship | `62642e5d05312055294855838ae5b40420a82b1ae6291045108ba6dacd595d27` |
| admiral-harbor | `cf15aa249bb0da2f53e271fd802bedd1dfb37adcc3dd555b2317f84d7b29580a` |

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

The image-update marker was exercised on instance
`inst_51d8fdd5e77ad618`: applying a changed MariaDB image set
`need_restarting=true`; successful stop/start operations
`op_4046cce2adf7d4a1` and `op_bd5286dc333ae75e` cleared it back to `false`,
then deprovision `op_4bea5440f3ba11ff` succeeded.

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

The RC1 security disposition is recorded in `notas.md`: node registration
tokens are passed through the task environment with `no_log`, bootstrap SSH is
accepted as a temporary per-node design with explicit mitigation, and S3
production TLS remains a pre-1.0 gate rather than a claim of local validation.

The unprivileged `scripts/install.sh --help` contract and installer test suite
passed: 48 tests, with `--help` returning exit code 0 for `nobody`.

Release reference validation passed after checking the Makefile pins, RPM
spec pins, and submodule HEADs.
