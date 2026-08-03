# Admiral beta20 validation

## New-host validation run (2026-08-03)

This section records the validation started on the new Rocky Linux 10.2
x86_64 host. Results from earlier hosts below are historical and are not
counted as evidence for this run.

Initial state: the five submodule working trees were empty. They were
initialized at the exact commits pinned by the superproject, and
`python3 scripts/validate-release-refs.py` then passed. The host had KVM
available at `/dev/kvm`, but no libvirt tooling; KVM/libvirt, `virt-install`,
and guest tooling were installed for this validation. A persistent 4 GiB
`/swapfile` was added because the host has 8 GiB RAM. VM product validation
is still in progress and is not a release-wide PASS.

Current new-host status: PREPARATION COMPLETE; RPM BUILD PASS; CENTOS
STREAM 10, ROCKY LINUX 10, AND ALMALINUX 10 SINGLE-NODE PASS; MULTINODE
PENDING.

### New-host local RPM build

`make rpm-admiral-no-test` completed successfully after building the local
Python dependency RPMs required by Harbor. `python3 scripts/validate-release-refs.py`
passed before the build. The final build includes the Harbor/Fleet registration
authentication fixes and incremented all six package releases.

| Package | NEVRA | SHA-256 |
| --- | --- | --- |
| admiral-common | `admiral-common-0.0.1beta20-65.el10.noarch` | `ea53634c80a133cb7538c410137fd0f553efcc523508e3ed79cbfcb87735afac` |
| admirald | `admirald-0.0.1beta20-33.el10.x86_64` | `cdffa5827b8ec801eca18817aaf8582bba023c9f46e2e830e3e59d1c8f4f2fb2` |
| admiral-fleet | `admiral-fleet-0.0.1beta20-38.el10.x86_64` | `2f634efe01b2c0ed3e3eb4358d41c2221639d450823b6bd7d2c8c0faa14c5b1d` |
| admiralctl | `admiralctl-0.0.1beta20-31.el10.x86_64` | `0f9cab58a6a62f239c680a9ece54dd59e836ec68d8454ff1e7e618b0304f4045` |
| admiral-flagship | `admiral-flagship-0.0.1beta20-30.el10.noarch` | `bc64abf67fe2c2c83a10b2ba1b599653b01ac33e38077f9d7b73579377c62b90` |
| admiral-harbor | `admiral-harbor-0.0.1beta20-32.el10.noarch` | `695c0fbe3f16c9c72341e33dc36b5579e76567c4f1853ff221ab5d70417f7424` |

The local repository at `/var/lib/admiral/rpm-local` contains these six
candidate RPMs plus five locally built Python dependency RPMs.

### New-host VM harness status

Official CentOS Stream 10, Rocky Linux 10, and AlmaLinux 10 GenericCloud
images were downloaded and cloned into three 20 GiB qcow2 guests with 2 GiB
RAM each. BIOS boot was not usable in this nested KVM host; UEFI was enabled.
All three guests now boot, obtain DHCP leases, accept the lab SSH key, and see
the candidate repository. The repository is copied into the guests as a local
file repository because the libvirt bridge does not reliably permit guest to
host TCP/8080 access.

CentOS Stream 10 single-node was installed from the candidate RPMs. Direct
evidence after convergence: `postgresql`, `caddy`, `admirald`,
`admiral-fleet`, `admiral-flagship`, and `admiral-harbor` were all `active` and
`enabled`; expected listeners were present on Caddy and the loopback service
ports; and `admiralctl --help` succeeded. This is a single-node PASS for
CentOS only.

Rocky Linux 10.2 completed the detached installer run with
`ok=186 changed=24 failed=0 unreachable=0 skipped=148`, including the
single-node worker/portal registration assertions and Harbor API verification.
`postgresql`, `caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, and
`admiral-harbor` were all active and enabled; `admiralctl --help` succeeded.

AlmaLinux 10 completed the same single-node checks: all six services were
active and enabled, expected loopback listeners were present, and
`admiralctl --help` succeeded. Multinode role tests have not yet run.

The multinode harness was then prepared with three same-distribution CentOS
Stream 10 clones (admin, portal, worker). The fresh UEFI clones stopped at the
firmware boot manager instead of selecting the guest disk and therefore never
obtained DHCP. This is a harness failure, not Admiral product evidence; no
multinode PASS is claimed until the VM boot path is corrected.

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
| admiral-common | `0.0.1beta20-58.el10.noarch` |
| admirald | `0.0.1beta20-26.el10.x86_64` |
| admiral-fleet | `0.0.1beta20-31.el10.x86_64` |
| admiralctl | `0.0.1beta20-24.el10.x86_64` |
| admiral-flagship | `0.0.1beta20-23.el10.noarch` |
| admiral-harbor | `0.0.1beta20-25.el10.noarch` |

SHA-256 of the six RPMs in `/var/lib/admiral/rpm-local`:

| Package | SHA-256 |
| --- | --- |
| admiral-common | `cac417ee9dfa4d781aaad50176ff7c1ef914f3578084ea07bcfe806ec2ee4fbd` |
| admirald | `71e157b34644c930a966998420dd171d20a1ce81ca862933c07445e8cbddf040` |
| admiral-fleet | `0c4961ab18b178b8f27b377e25356f6a4d0783944a4190e66b5244cfa3288d83` |
| admiralctl | `48be8717aa8e5a4e2623f42d797e9cacb3509e6ea0658a7348a7552433ff2d19` |
| admiral-flagship | `830ca46e1f3a9e49e58fbc6c85b78446d1b07da0c9ad7e7125085ec32c7403ea` |
| admiral-harbor | `6a7292ee252f06ec7f36f294958eba77ab1b2077dd27e27ca1a5878602595901` |

`python3-flask-login`, `python3-flask-sqlalchemy`, and
`python3-flask-alembic` were built only as local build dependencies; they are
not Admiral release candidates.

The repository is available at `/var/lib/admiral/rpm-local` and is exposed as
the enabled `admiral-local` DNF repository in `/etc/yum.repos.d/admiral-local.repo`.
`dnf install 'admiral*' --assumeno` selected all six candidates from
`admiral-local`, not COPR. The real transaction upgraded and installed all six
latest candidates successfully (`58/26/31/24/23/25`).

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

## Security image restart verification

The complete security-update flow was verified on the local EL10 host with a
temporary definition `wp-restart-test` and instance
`inst_1eabc8f2defe26cf`. The definition was first applied with
`docker.io/library/mariadb:10.11`; provision operation
`op_70675a92624e815e` succeeded. The running DB container reported image ID
`37b9f8bf6fe12f7d493c8aa55e97dd0205367e7b29445166e661a2739fdbae02` and the
old image reference.

The definition was then updated only to `docker.io/library/mariadb:11.4`.
Admiral reported `need_restarting=true` before the restart. A real stop
(`op_5e611e474227f7e9`) followed by start (`op_0c27e15d172227ae`) succeeded.
Fleet's authenticated callback verified the image reference and immutable
image ID for each running service; the DB container then reported image ID
`5eb84d23187c27447ef6ddfec3f0332bbbc12c09fd5818b7d6b5bbef1da35772` with
`docker.io/library/mariadb:11.4`. The old and new IDs differ, proving the
instance restarted with the new image. Admiral subsequently reported
`need_restarting=false` and `technical_status=running`.

The first implementation attempt was rejected because it tried to inspect the
transient `setup` helper after provisioning. The corrected implementation skips
only that non-running helper and normalizes Podman's 64-character image ID to
the `sha256:` OCI form. A normal pause/resume flow does not request image
verification; verification is enabled only when Admiral dispatches a
start/resume/reactivate task while `need_restarting=true`.

The temporary instance was then deprovisioned successfully with
`op_ff6ff2eaad5bf74b`, and the temporary app definition was deactivated.

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
