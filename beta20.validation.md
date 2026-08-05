# Admiral beta20 validation

## Final host session (2026-08-04)

The release sources were checked out at the latest published `origin/main`
heads, all five component CI workflows were green for those exact SHAs, and
`python3 scripts/validate-release-refs.py` passed. COPR was queried with
`dnf`; its six current EL10 NEVRAs exactly matched the six release specs:

| Package | NEVRA |
| --- | --- |
| admiral-common | `admiral-common-0.0.1beta20-112.el10.noarch` |
| admirald | `admirald-0.0.1beta20-45.el10.x86_64` |
| admiral-fleet | `admiral-fleet-0.0.1beta20-50.el10.x86_64` |
| admiralctl | `admiralctl-0.0.1beta20-43.el10.x86_64` |
| admiral-flagship | `admiral-flagship-0.0.1beta20-76.el10.noarch` |
| admiral-harbor | `admiral-harbor-0.0.1beta20-44.el10.noarch` |

The host received a persistent `/var/swap/admiral-test.swap` 4 GiB swap file.
Three KVM guests were created with 1843 MiB each, leaving more than 2 GiB of
host memory available while all three were running. They used an isolated
libvirt NAT network and the official Rocky Linux 10.2 GenericCloud image;
the image SHA-256 matched the official `CHECKSUM` file.

### Current-session Rocky Linux 10.2 single-node

The admin guest (`192.168.220.175`) installed the exact six COPR packages and
completed `admiral-install --single-node --yes` with:

```text
ok=220 changed=98 unreachable=0 failed=0 skipped=125 rescued=0 ignored=0
```

The installer Harbor API verification passed. Rocky Linux reported SELinux
`Enforcing`; `admiralctl --help` passed; all six services (`postgresql`,
`caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, and
`admiral-harbor`) were active; and `systemctl --failed` was empty.

The portal and worker guests booted Rocky Linux 10.2 with SELinux enforcing
and cloud-init complete. They remain infrastructure slots for the sequential
AlmaLinux and CentOS single-node runs; no product source or RPM spec was
changed during this session.

### Current-session AlmaLinux 10.2 single-node

The Rocky overlay was replaced with a fresh official AlmaLinux 10.2
GenericCloud overlay. The same six COPR NEVRAs were installed and
`admiral-install --single-node --yes` completed with:

```text
ok=221 changed=100 unreachable=0 failed=0 skipped=124 rescued=0 ignored=0
```

The Harbor API verification passed. AlmaLinux reported SELinux `Enforcing`,
and all six Admiral services were active with no failed systemd units.

### Current-session CentOS Stream 10 single-node and complete app lifecycle

The CentOS Stream 10 guest installed the same six COPR NEVRAs and completed
`admiral-install --single-node --yes` with:

```text
ok=220 changed=100 unreachable=0 failed=0 skipped=125 rescued=0 ignored=0
```

The installer Harbor API verification passed, SELinux was `Enforcing`, and
the six Admiral services were active. CentOS also reported a pre-existing
guest `kdump.service` failure; this is recorded as an environment observation,
not hidden as a clean `systemctl --failed` result.

The example app lifecycle was completed with the published packages. App
definition `wp` was applied from `examples/apps/wordpress.yaml`, and instance
`inst_42246a8d3c99b892` reached `healthy`, `setup_completed=true`, and
`technical_status=running`. HTTP returned 200 from the published local port.
The database backup succeeded as operation `op_c9a413fb5acc6bae`, producing
backup `bk_abbbceee22676b36` with SHA-256
`7cfec52a4134ecaef18efd35b14bd4065e0cb0a1c79cd5cb51d2e5831c0f7ac7`.
Pause (`op_65efcdb0e4f6d96b`) and resume (`op_532a68c7b8516c65`) both
succeeded, with HTTP restored after resume. Deprovision completed as
`op_372212ac3b6ffa74`; the instance ended in `technical_status=deprovisioned`.

This is the first current-session Tier 1 result meeting the full
`--single-node` lifecycle criterion; Rocky and Alma installation evidence is
recorded above, but their lifecycle gate remains to be rerun on their saved
installed overlays before declaring the three-tier matrix complete.

### Lifecycle gate disposition for the remaining Tier 1 overlays

The saved Rocky overlay was booted to avoid reinstalling the already verified
RPM set. Its services started, but its persisted control-plane state retained
the previous guest's node metrics. The worker remained `offline` with
`heartbeat_timeout`, and provision was rejected with HTTP 503 and
`metrics_stale`. This is not counted as a lifecycle pass. Alma's lifecycle was
not run after this finding. No source or RPM change was made; the complete
three-Tier-1 `--single-node` gate therefore remains open.

### Fresh-VM follow-up (2026-08-04)

A clean Rocky Linux 10.2 overlay was booted to rerun the lifecycle without
reusing persisted Admiral state. After enabling EPEL, CRB, and the published
Admiral/Caddy COPRs, `dnf` could not resolve the required beta20 NEVRAs: the
repo metadata exposed older Admiral builds and no
`admiral-common-0.0.1beta20-112` (nor the corresponding beta20 component
packages). Installation therefore stopped before `admiral-install` and no
Rocky lifecycle result was claimed. This is an external repository-state
blocker; no source, spec, or RPM was changed in response.

### Final clean Tier 1 lifecycle session (2026-08-05)

The COPR metadata was rechecked directly. It contains the six beta20 NEVRAs;
the earlier clean-VM failure was caused by stale guest DNF metadata. Fresh
Rocky and Alma overlays were then installed from the exact six COPR RPMs.

Rocky Linux 10.2 completed `admiral-install --single-node --yes` with:

```text
ok=221 changed=100 unreachable=0 failed=0 skipped=124 rescued=0 ignored=0
```

The Harbor API check passed, SELinux was `Enforcing`, all six required
services were active, and `systemctl --failed` was empty. Instance
`inst_2cbc50fbba5bb08c` reached `setup_completed=true` and `running`; HTTP
returned 200 before pause. Its database backup succeeded as
`bk_88450e189742fda7`, SHA-256
`3a8005118fca0722abc82e3f9cdb68cfc2c649fce98e847ded3c9a4248b53ede`.
Pause `op_dbd07ab4bc10da28` returned HTTP 000 while paused; resume
`op_f7dcfa893e1ce28e` returned HTTP 200 after the normal transient startup
period; deprovision completed successfully. A second Rocky instance also
repeated pause/resume with HTTP 000/200 (`op_8ad1147de112a6a3`,
`op_33bf8774cdc88a3b`) and deprovisioned successfully.

AlmaLinux 10.2 completed `admiral-install --single-node --yes` with the same
recap (`ok=221 changed=100 unreachable=0 failed=0 skipped=124 rescued=0
ignored=0`), Harbor API pass, SELinux `Enforcing`, all six services active,
and no failed systemd units. On single lifecycle instance
`inst_48e9aeff4ae79b7f`, HTTP returned 200 before pause, database backup
`bk_5580234813186d24` succeeded with SHA-256
`fb7cf602138a09a5e809c13f69ea1b083352cb8fc04c7035adc08f8ef1b91fa1`,
pause returned HTTP 000, resume returned a transient HTTP 500 followed by
HTTP 200 after polling, and deprovision succeeded. This completes the
full example-app lifecycle gate for all three Tier 1 distributions when
combined with the CentOS lifecycle recorded above.

## New-host validation run (2026-08-03)

This section records the validation started on the new Rocky Linux 10.2
x86_64 host. Results from earlier hosts below are historical and are not
counted as evidence for this run.

Initial state: the five submodule working trees were empty. They were
initialized at the exact commits pinned by the superproject, and
`python3 scripts/validate-release-refs.py` then passed. The host had KVM
available at `/dev/kvm`, but no libvirt tooling; KVM/libvirt, `virt-install`,
and guest tooling were installed for this validation. A persistent 4 GiB
`/swapfile` was added because the host has 8 GiB RAM. The requested Tier 1 VM
validation is complete; final repository, CI, push,
and VM-shutdown gates are recorded below.

Current new-host status: RPM BUILD PASS; CENTOS STREAM 10, ROCKY LINUX 10,
AND ALMALINUX 10 SINGLE-NODE PASS. The multinode role-installation and
registration evidence below is retained, but the complete multinode gate is
NOT YET PASS: a real WordPress lifecycle on the worker and a successful
dedicated-portal catalog synchronization must also be recorded. Handshake,
node registration, or `admiralctl nodes list` alone are insufficient.

### New-host local RPM build

`make rpm-admiral-no-test` completed successfully after building the local
Python dependency RPMs required by Harbor. `python3 scripts/validate-release-refs.py`
passed before the build. The final build includes the Harbor/Fleet registration
authentication fixes and incremented all six package releases.

| Package | NEVRA | SHA-256 |
| --- | --- | --- |
| admiral-common | `admiral-common-0.0.1beta20-77.el10.noarch` | `f8ccb97dabc0defcf50945422923b6788c8083cd35283314cdfbfaef24ac2705` |
| admirald | `admirald-0.0.1beta20-45.el10.x86_64` | `57535d131ae52c60a50304d5a5e6c15ea93030df2498181a591af57c2808b2ad` |
| admiral-fleet | `admiral-fleet-0.0.1beta20-50.el10.x86_64` | `bb8d53d64df51598aca3830d6f84078ce450d8e50a8b631627a546c7c8a6299b` |
| admiralctl | `admiralctl-0.0.1beta20-43.el10.x86_64` | `ea762fa7675931bad36826c5e67be95fa082587559e725434932e2e6b8361912` |
| admiral-flagship | `admiral-flagship-0.0.1beta20-42.el10.noarch` | `5d22e84a85affdbe1883774ebeddfa1294cac8459c8ab9ad8fe364a87fdc4138` |
| admiral-harbor | `admiral-harbor-0.0.1beta20-44.el10.noarch` | `2a2b534cbee7e1c20e2282dc22d4bef04da79d0703cc21416a322c638f3e71c6` |

The local repository at `/var/lib/admiral/rpm-local` contains these six
candidate RPMs plus five locally built Python dependency RPMs. A 17 MiB
latest-package subset was copied into the guests as `file://` repositories
when the libvirt bridge rejected guest-to-host TCP/8080 connections.

Component CI is green for the exact pinned commits used in this build:
admirald `4e7d728b`, admiral-fleet `81d2383a`, admiralctl `492ddb02`,
admiral-flagship `7238cedc`, and admiral-harbor `3eec3aaa`.

### New-host backup/restore closure

On Rocky Linux 10.2 single-node, with the new Fleet RPM
`admiral-fleet-0.0.1beta20-50.el10`, a real WordPress volume backup was created
as `bk_083b210de160a03c`, checksum verification was enabled, the instance was
paused, and restore operation `op_6381ddfd15d3272c` completed with `succeeded`.
The instance returned to `technical=running` and `storage=ok`. A post-restore
container check successfully created and read a file in `/var/www/html`, and
verified that `.htaccess` was present.

With the same Fleet-50 binary, database backup `bk_f45e95b273a59646` completed
successfully and database restore operation `op_3320c8f44ba3f935` also completed
with `succeeded` and checksum verification enabled.

The preceding Fleet-49 attempt failed as expected during this investigation
because archive host IDs were passed unchanged to `podman unshare`. Fleet-50
translates the archive UID/GID through the effective rootless `uid_map` and
`gid_map`; the same real restore then passed. This closes the previously known
volume-restore defect for the validated rootless Podman path.

### New-host multinode evidence

#### Explicit installer-mode gate (installation/registration only)

This is a separate multinode gate from the single-node lifecycle above. Each
distribution used three dedicated VMs and these exact installer modes:

```text
admin VM  : admiral-install --admin-node  --public-ip <admin-ip>
portal VM : admiral-install --portal-node --public-ip <portal-ip> --wireguard-ip <portal-wg-ip>
worker VM : admiral-install --worker-node --public-ip <worker-ip> --wireguard-ip <worker-wg-ip>
```

The admin VM was the control plane, the portal VM was a dedicated portal
spoke, and the worker VM was a dedicated Fleet spoke. The portal and worker
commands were launched from the admin node using the bootstrap SSH delivery
path. `--portal-node` and `--worker-node` were never combined on one guest.

The final admin-side assertion for each distribution was:

```text
admiralctl nodes list --output json
portal-01: status=active health_status=healthy available_for_provisioning=true
worker-01: status=active health_status=healthy available_for_provisioning=true
```

The role-specific Ansible recaps below are the authoritative results for this
gate; every role has `unreachable=0` and `failed=0`. This evidence is dated
2026-08-03 and is intentionally kept distinct from the fresh single-node
session dated 2026-08-04/05.

This section does not claim the full multinode validation. Pending evidence is
explicitly:

1. apply the WordPress definition through the admin and provision it onto the
   registered worker;
2. verify the workload through the worker's published/WireGuard address, then
   exercise backup, pause, resume, and deprovision;
3. verify on the dedicated portal that
   `admiral-harbor-catalog-sync.service` succeeds and that the portal catalog
   contains the application snapshot supplied by `admirald`.

Each distribution used one admin VM, one dedicated portal VM, and one worker
VM, with 2 GiB RAM per guest. CentOS Stream 10 completed the final portal and
worker playbooks with `failed=0` (`ok=178 changed=33 skipped=160` and
`ok=134 changed=16 skipped=204` respectively); both peer exchanges and the admin node list
reported healthy spokes.

Rocky Linux 10.2 completed the admin, portal, and worker playbooks with:

| Role | Ansible recap | Peer exchange |
| --- | --- | --- |
| admin | `ok=190 changed=97 unreachable=0 failed=0 skipped=151` | controller installed |
| portal | `ok=187 changed=84 unreachable=0 failed=0 skipped=152` | verified on attempt 1 |
| worker | `ok=142 changed=55 unreachable=0 failed=0 skipped=197` | verified on attempt 1 |

The final Rocky `admiralctl nodes list` showed both `portal-01` and `worker-01`
as `active healthy true`.

AlmaLinux 10 completed the admin, portal, and worker playbooks with:

| Role | Ansible recap | Peer exchange |
| --- | --- | --- |
| admin | `ok=165 changed=46 unreachable=0 failed=0 skipped=175` | controller installed |
| portal | `ok=183 changed=52 unreachable=0 failed=0 skipped=156` | verified on attempt 1 |
| worker | `ok=136 changed=20 unreachable=0 failed=0 skipped=202` | verified on attempt 1 |

The final Alma `admiralctl nodes list` showed both `portal-01` and `worker-01`
as `active healthy true`. The intermediate Alma retries were caused by the
test host's restrictive egress policy blocking EL10 mirror HTTP traffic; the
successful final runs completed after the required packages were available
and retained the normal installer firewall configuration.

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
`admiralctl --help` succeeded. Its multinode role evidence is recorded below.

The multinode harness was then prepared with three same-distribution CentOS
Stream 10 clones (admin, portal, worker). The fresh UEFI clones stopped at the
firmware boot manager instead of selecting the guest disk and therefore never
obtained DHCP. This was an intermediate harness failure, not Admiral product
evidence. The UEFI clone path was corrected and the final CentOS multinode
evidence is recorded above.

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

## Fedora single-node smoke run — 2026-08-04

The real `admiral-install --single-node` command was **not executed** on a
Fedora VM in this session: the lab contained only EL10 Rocky guests, and no
Fedora guest was available. Therefore this is not Fedora runtime evidence and
must not be reported as a Fedora single-node pass.

The available automated installer smoke run completed with 48 tests passing
(`python3 -m unittest scripts.test_installer_modes`). It validates installer
argument and policy behavior, including Fedora's `--dev-node` restriction;
it does not validate the installed binaries or a Fedora single-node lifecycle.

## Current-RPM multinode WordPress lifecycle — 2026-08-05

The three-node EL10 lab used the current beta20 RPMs recorded above. The
admin and portal installers completed with `failed=0` and
`unreachable=0`. The portal registered as `portal-01`, became `active` and
`healthy`, and established a WireGuard handshake at `10.99.0.100`.

The first worker installer run reached `admiral-fleet` configuration but
failed with `failed=1`, `unreachable=0`, leaving the RPM-provided placeholder
configuration in `/etc/admiral/fleet.env`. The worker was then reconciled
with the admin's current signing/callback keys and WireGuard peer, registered
as `worker-01`, and became `active` and `healthy`. This is recorded as an
installer-gate defect; it is not evidence that the worker installer exited
successfully.

The functional workload lifecycle completed on the worker:

| Check | Evidence | Result |
|---|---|---|
| App definition | `wp` applied from `examples/apps/wordpress.yaml` | PASS |
| Provision | `op_c95f6b9688e46a07`, instance `inst_5d79d6116d40419f`, `node_id=worker-01` | PASS |
| Setup/health | `setup_completed=true`, `technical_status=running`, `health_status=healthy` | PASS |
| Worker HTTP | `http://10.99.0.2:40000` returned HTTP 301 from the admin path | PASS |
| MariaDB backup | `op_cb26e418fa481f4f`, backup `bk_f85a25ddca15942f`, SHA-256 `08a771336518f82a56ddaac28e27e03eba782ed182376f749137b2caef0f18c6` | PASS |
| WordPress volume backup | `op_5c6d4cfb7380d970`, backup `bk_819e115262f660ed`, SHA-256 `cd94fde3ee77744a9eabab4784f67dea966cb9a42191d7b5bb48481479cb117e` | PASS |
| Pause/resume | Pause `op_1ba2900602e06d50` made the worker endpoint unavailable; resume `op_e9f89d530765c988` restored `running` and HTTP 301 | PASS |
| Deprovision | `op_8fd4e94d9ce3572f` succeeded on `worker-01` | PASS |

The dedicated portal catalog timer was active. After clearing the stale
bootstrap `in_progress` audit record, the service completed successfully:
`sync_b7456bb4c8134930`, `success`, `1 new`, `0 updated`, `0 marked missing`.
The portal catalog contains `wp` with `sync_status=synced` and
`upstream_present=true`.

Conclusion: the current-RPM multinode WordPress workload and portal catalog
functional gates PASS. The overall multinode installer gate remains NOT PASS
until the worker `--worker-node` run completes without the configuration
failure; no source or RPM change was made in this lab session.
