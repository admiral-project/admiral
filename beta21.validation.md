# Admiral beta21 validation

Fecha de corte: 2026-08-05 (UTC-04:00). Este informe conserva la regla de
validación objetiva: una ejecución beta20 no se convierte automáticamente en
una ejecución beta21.

## Candidato

El candidato actual incluye `dc710bb` en el superproyecto y el parche de Fleet
`f9a386fc654ffb66f925da69f7639cfec43323c2`. Además de las correcciones TLS y
de instalación ya descritas, Fleet interpreta `need_restarting` como una
actualización de imágenes: valida las referencias, descarga cada imagen a
través de `admiral-fleet-lifecycle` como `admiral-apps`, detiene las unidades,
recarga Quadlet, arranca los contenedores y verifica la referencia e ID reales.
El pull tiene un límite operativo de diez minutos. Los commits tienen trailer
Signed-off-by.

Los submódulos estaban limpios y alineados con `origin/main`:

| Componente | Commit |
|---|---|
| admirald | `df2c87425aa1614e869495a52bad4c2ff09b2ec9` |
| admiral-fleet | `f9a386fc654ffb66f925da69f7639cfec43323c2` |
| admiralctl | `3c50732484b766e167383756659b57249f70470b` |
| admiral-flagship | `34fd70c380649cd85c76cd1bd905650222b2d0d9` |
| admiral-harbor | `c9e4f73407db81849067585159d375804f53c519` |

`python3 scripts/validate-release-refs.py` terminó PASS.

## RPM beta21 local

| NEVRA | SHA-256 |
|---|---|
| `admiral-common-0.0.1beta21-116.el10.noarch` | `5253df3e99db98a1a3ef59a6e04c477b0a9808388b7c530e353f7fe80b81720f` |
| `admirald-0.0.1beta21-49.el10.x86_64` | `2fd53ae1b29d6d0e5c837bf9f0c0e40ba31e31bbedaa7dad7841a51ff2da0270` |
| `admiral-fleet-0.0.1beta21-54.el10.x86_64` | `8e03dc155c17a7a78d906bbfddc580db15682f85784a230e1e3fc402c60ec77a` |
| `admiralctl-0.0.1beta21-47.el10.x86_64` | `5eb1563da6f8fb536069c2f649e6851d16dbf0966b39c06d569892e54ea815aa` |
| `admiral-flagship-0.0.1beta21-80.el10.noarch` | `f250dacbcce6e2fd3230b3f36895037a85efdfc9ebf27eab1f5fadd66f8d9042` |
| `admiral-harbor-0.0.1beta21-48.el10.noarch` | `0fc5df9325320392050ee407acdc6735f552448cb897136c8631a318144fbe86` |

Build evidence: the supported `make rpm-admiral` sequence generated the four
RPMs whose build dependencies were available, followed by equivalent
`rpmbuild -ba --nodeps` invocations for the two Python RPMs. All six packages
were generated. Go package
tests passed for `admirald`, `admiral-fleet`, and `admiralctl`; Flagship passed
241 pytest tests; Harbor passed 295 pytest tests with 9 warnings. The two
Python RPMs were invoked with `--nodeps` because the EL10 repositories do not
provide the project-specific `python3-pytest`, Flask-Alembic, Flask-Login and
Flask-SQLAlchemy RPM names; their test suites still executed successfully.

Additional regression checks: `python3 -m pytest -q
scripts/test_admiral_https_setup.py scripts/test_installer_modes.py` passed
with 60 tests and 10 subtests; `bash -n` passed for the deploy hook.

## COPR publication handoff

The operator reported that the six beta21 SRPMs were imported into COPR. COPR
build completion has not yet been independently verified. Validation is paused
until the operator confirms that all six builds completed; no COPR build result
is treated as a release PASS before that confirmation.

For interim retrieval, the last local SRPM build remains available at
`http://142.93.2.122:8888/`, served by the transient systemd unit
`admiral-beta21-srpm-http.service`. It contains exactly six files: the
`0.0.1beta21` SRPMs for common, admirald, fleet, admiralctl, flagship and
harbor. The server is not evidence of COPR publication.

## Firewall defect #71

The fresh multinode lab reproduced issue #71 on AlmaLinux Portal. The managed
`inet admiral_egress` policy allowed TCP `443`, `587` and `9000` for spoke
nodes, but EL10 repository metadata selected HTTP mirror URLs on TCP `80`.
Portal could resolve DNS and reach HTTPS, while Ansible failed at
`admiral_fail2ban` downloading `perl-File-stat-1.14-512.2.el10_0.noarch`:
`Cannot download, all mirrors were already tried without success`. The fresh
Portal recap was `ok=118 changed=58 unreachable=0 failed=1`.

Issue [#71](https://github.com/admiral-project/admiral/issues/71) was created
after duplicate search. Commit `5a47e85` adds TCP `80` to spoke egress only;
it does not expose TCP `80` inbound. The focused firewall regression tests
passed (`2 passed, 46 deselected`).

The project policy requires all six Release fields to be incremented on a
rebuild; all six SRPMs were therefore generated. For this firewall correction,
only `admiral-common` is needed for COPR upload and runtime verification:

| SRPM | SHA-256 |
|---|---|
| `admiral-common-0.0.1beta21-117.el10.src.rpm` | `c819deb46c0859a035792a966ab61312a85e9667d20f78eeed39bc7e374ec61d` |
| `admirald-0.0.1beta21-50.el10.src.rpm` | `d8d8cbaa036f543017ce0269a9bf3207264448dec22e18f3880426484856f3f1` |
| `admiral-fleet-0.0.1beta21-55.el10.src.rpm` | `4a07c640fbe6f6c7670ed90989c7c49fe207a12427ed7c9e617807782979a380` |
| `admiralctl-0.0.1beta21-48.el10.src.rpm` | `b3ddeb836e9c66e742d3f4b29217d79e9d2c5e4e511971c5bedad36a2f3e1968` |
| `admiral-flagship-0.0.1beta21-81.el10.src.rpm` | `0a34ffb4c9bcdae9692359e1f92d5205dac943f56992263a6bc9a5c65e406cc0` |
| `admiral-harbor-0.0.1beta21-49.el10.src.rpm` | `e5777c7f7f0971fb578575d6ae1bd18f1da2a374d0b7ea79f1eb8f9ed9154197` |

Only `admiral-common-0.0.1beta21-117.el10.src.rpm` is currently served at
`http://142.93.2.122:8888/` for COPR upload. Runtime verification of the fix
remains pending COPR build/import and a fresh rerun; issue #71 remains open.

Before pausing for COPR, the root cause was independently isolated on the
fresh Portal: with the original egress chain, `dnf makecache --refresh` failed;
after inserting only `tcp dport 80 accept` before the default reject,
BaseOS/AppStream/CRB/EPEL metadata completed successfully (`rc=0`). The
automatic Ansible rerun was then stopped at operator request pending the COPR
RPM; this manual result is diagnostic evidence, not final runtime acceptance.

## Release matrix

| Escenario | Resultado beta21 | Evidence / classification |
|---|---|---|
| Rocky Linux 10 single-node, clean GenericCloud | PASS for installation, security smoke, Golden Test and cleanup | Official image SHA256 `9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48`; guest `beta21-rocky-single`. Installer playbook: `ok=222 changed=100 unreachable=0 failed=0`. WordPress lifecycle completed through apply, provision, setup, healthy/HTTP, DB and volume backup/restore, pause/resume, image update, deprovision and cleanup. Fix verification operation `op_38cc937ae41fab9d` succeeded; actual rootless container image was `docker.io/library/wordpress:6.8.1`, `need_restarting=false`, HTTP 301. |
| AlmaLinux 10 single-node, clean GenericCloud | PASS for installation, security smoke, complete Golden Test and cleanup | Official image SHA256 `47f2218668dd4776be140dd92fa3bea700be1766e2c7d88bdfd6a4b50f477b4d`; guest `beta21-alma-single` at `192.168.122.175`. Installer playbook: `ok=222 changed=100 unreachable=0 failed=0`; all required Admiral services active, SELinux Enforcing, firewall services `http https ssh`, SSH password authentication disabled. Via `admiralctl`: apply/provision/setup/healthy, HTTP validation, DB backup `op_f8aceb3d5d1d1629`, volume backup `op_30748a2240256227`, DB restore `op_1b8652b6479de09e`, volume restore `op_0ae3785f926f3479`, pause/resume, image update/restart `op_ca110125182c6fa1`, actual rootless `wordpress:6.8.1` image ID `36e2490fa1a957f3cee615693157139c64b69951dcc7bfd48ee4fd6d03750a31`, `need_restarting=false`, healthy, then deprovision `op_b5fd3d973ff9313e`; no containers remained. |
| CentOS Stream 10 single-node, clean GenericCloud | PASS for installation/security smoke and complete Golden Test; environmental kdump blocker recorded | Official image SHA256 `9116da2c148c2a3da55579238a543ee9bd238265eba89234201d680e19ae1fbc`; guest `beta21-centos-single` at `192.168.122.249`. Installer playbook: `ok=221 changed=100 unreachable=0 failed=0`; Admiral services active, SELinux Enforcing, firewall services `http https ssh`, SSH password authentication disabled. `kdump.service` failed with `No memory reserved for crash kernel`; classified ENVIRONMENTAL BLOCKER for this VM. Via `admiralctl`: provision `op_9c15044bd37fa44a`, healthy/setup complete, HTTP 308, DB backup `op_7ef753bbe9fd6648`, volume backup `op_8c77a64b0b36c5b5`, DB restore `op_fc204fecdb0a0fa7`, volume restore `op_d7db0ff4aac828ce`, pause/resume, image update/restart `op_f6376d466f6da770`, actual rootless `wordpress:6.8.1` image ID `36e2490fa1a957f3cee615693157139c64b69951dcc7bfd48ee4fd6d03750a31`, `need_restarting=false`, healthy, then deprovision `op_3ae38ca9143977f2`; no containers remained. |
| Fedora smoke and WordPress attempt | FAIL, non-blocking Tier 2 expected limitation; no fix applied | Official Fedora 44 Generic Cloud image `Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2`, SHA256 `28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f`; guest `beta21-fedora-smoke` at `192.168.122.47`. RPM installation and `--dev-node` installer completed; SELinux Enforcing. `admiral-harbor-worker` and `admiral-harbor-catalog-sync` fail with `ADMIRAL_INSECURE_SKIP_VERIFY must be false in production`; this matches the documented Fedora/Python 3.14/OpenSSL limitation and was not changed. WordPress `admiralctl instances provision` was attempted four times and failed safely with HTTP 503; persisted operations report `node_provisioning_rejected_no_capacity` with `metrics_stale`, `node_unhealthy`, and Fleet evidence of `wireguard_ip_mismatch`/HTTP 403. Classified EXPECTED LIMITATION for the documented Tier 2 dev-node path, not a Tier 1 release blocker. |
| Admin/Portal/Worker multi-node | BLOCKED; partial execution with environmental blockers | q35 clean-boot rerun reached SSH: Admin `192.168.122.32`, Portal `192.168.122.247`, Worker `192.168.122.182`. Admin playbook completed `ok=193 changed=99 unreachable=0 failed=0`; final installer check initially failed only because the harness staged RPMs with `rpm --nodeps` and omitted declared `python3-gunicorn`; installing the declared dependency made Flagship active and `admiralctl status --output json` returned `{"status":"healthy"}`. Portal failed three times on repository access: first `ok=118 changed=58 unreachable=0 failed=1` downloading `perl-Getopt-Std`, retry one failed AppStream `repomd.xml`, and retry two failed CRB `repomd.xml` (`all mirrors tried`). Worker first failed `ok=133 changed=51 unreachable=0 failed=1` and retry failed `ok=127 changed=13 unreachable=0 failed=1` in the `no_log` Fleet configuration task; the VM also contained pre-existing beta20 packages, so this execution is not valid clean-image evidence. Classified HARNESS DEFECT for RPM staging/contaminated overlay and ENVIRONMENTAL BLOCKER for repository outage; no PASS is inferred. |
| WordPress Golden Test | PASS Rocky, AlmaLinux and CentOS Stream; Fedora non-blocking failure documented | Rocky, AlmaLinux and CentOS each completed the full lifecycle with CLI and runtime evidence. Fedora provisioning was attempted and failed with documented Tier 2 node-health/certificate limitations; no Fedora fix was applied. |
| VM destruction/cleanup | PASS | All beta21 domains are undefined and no VMs are running. Multi-node overlays and the temporary SSH key were removed; official base images remain under `/var/lib/libvirt/beta21` for a future clean rerun. The only libvirt network is the persistent default NAT network. |

The host has `/dev/kvm`, 4 vCPU, 8 GiB RAM and more than 150 GiB free disk.
Libvirt, QEMU/KVM, the default NAT network and cloud-init are operational.
The Rocky base image and the AlmaLinux and CentOS Stream GenericCloud images
were downloaded from their official image locations and checksum-verified.
The three Tier 1 single-node installations and their independent WordPress
Golden Tests are now evidenced. Fedora smoke/Golden validation is recorded as
a non-blocking Tier 2 limitation. The required three-node validation was
subsequently executed on fresh Rocky 10, AlmaLinux 10, and CentOS Stream 10
overlays. Current evidence is recorded in the update sections below; the
earlier blocked-row text is historical and is superseded by that evidence.

## Security and negative validation

The portable TLS correction was tested in isolation, including expected
lineage rejection and restart-failure rollback. Existing hardening regressions
for issues #63–#67 are covered by commits `944a3c5`, `168463b`, `01985fe`,
`a8acf56`, and `e134645`; those issues remain open for review and were not
closed.

The current three-node checks provide SELinux AVC deltas, external Nmap
results, segmentation failures, WireGuard invalid-peer recovery, SSH password
rejection, secret scans, permissions, rootless isolation, DNS,
resource-pressure, and reboot evidence. A libvirt-specific reboot limitation
remains classified as an ENVIRONMENTAL BLOCKER: `systemctl reboot` powered off
each disposable guest instead of returning it automatically, so the harness
had to start the same VM again before service recovery could be checked.

## GitHub issue evidence

Comments were posted on the active validation issues #68 and #69, on the
historical duplicate #8, and on the now-closed image-update issue #70. The
accepted fixes were not closed by this validation agent. The only currently
open tracking issues are #68 and #69.

## Verdict

**BLOCKED** for publication acceptance: source fixes and local RPM/test gates
pass, but the required beta21 clean-VM release and security matrix lacks
execution evidence. This report intentionally does not claim that beta20
results prove beta21.

## Validation update: package reconciliation and spoke SSH lockdown

The installer reconciliation defect was reproduced on the fresh AlmaLinux
Portal. A rerun completed the Ansible playbook with `ok=181 changed=30
unreachable=0 failed=0`, but the Portal remained on
`admiral-common-0.0.1beta21-117` when that was the newest package available at
the start of the run. After COPR published `118`, the controller saw both
`117` and `118`; the next reconvergence was started with the updated
controller playbook. The package update behavior is covered by issue
[#72](https://github.com/admiral-project/admiral/issues/72) and commit
`e5a6c7a`, which changes the Ansible package task from `state: present` to
`state: latest`.

The same Portal reconvergence exposed a separate idempotency defect: the
already-onboarded spoke had the intended final lockdown
`/etc/ssh/sshd_config.d/49-admiral-root-lockdown.conf` with
`PermitRootLogin no`; `sshd -T` confirmed `permitrootlogin no`,
`passwordauthentication no`, `kbdinteractiveauthentication no`, and
`permitemptypasswords no`. The installer nevertheless hard-failed because
the pre-lockdown checklist required `prohibit-password`. This is recorded in
issue [#73](https://github.com/admiral-project/admiral/issues/73).

Proposed fix commit `e9f1822` accepts `permitrootlogin no` only for
`worker-node` and `portal-node` reconvergence, while retaining the existing
baseline check for other modes. Verification: `bash -n scripts/install.sh`
PASS and `python3 -m pytest -q scripts/test_installer_modes.py -k
'root_lockdown or reconciled or egress or firewall'` => `4 passed`.

The fix is released as a new immutable RPM build:

| Artifact | Value |
|---|---|
| Commit | `e9f1822113f112108f070dfd08bbaf9cf5b3deb4` |
| SRPM | `admiral-common-0.0.1beta21-119.el10.src.rpm` |
| SRPM SHA-256 | `94e42e7674c096822dd81beda3206ea9ba7337cd7ff5597568587a61b6afb279` |
| Release | `119` |

Release `118` is not replaced; it remains the package-reconciliation build.
Release `119` must be built by COPR before runtime verification. Issues #72
and #73 remain open for review; no issue was closed.

### Runtime verification update

The local `admiral-common-119` RPM was installed on the Admin controller and
the Portal reconvergence was rerun. Final evidence:

```text
PLAY RECAP
target : ok=181 changed=30 unreachable=0 failed=0 skipped=161 rescued=0 ignored=0
Admiral installation completed.
```

Portal reported `admiral-common-0.0.1beta21-118.el10.noarch`,
`admiral-harbor active`, `postgresql active`, public ports `51820/udp`, and
`sshd -T` reported `permitrootlogin no`, `passwordauthentication no`,
`kbdinteractiveauthentication no`, and `permitemptypasswords no`. The former
`PermitRootLogin` hard failure did not recur. This is local proposed-fix
verification; COPR publication of `119` is still required for package-level
acceptance.

Worker negative SSH validation was executed. The stale fingerprint
`SHA256:3jtFaOdCjDbFx4nivM+BSUSvEdkjwiLUw5H4czJTxZU` was rejected with:

```text
[FATAL] SSH host key fingerprint mismatch for 192.168.122.49. Aborting.
```

The current verified Worker fingerprint is
`SHA256:edk3sGH3SQVFKFB67rfML/fCBf9+Pn5am8FaKLoBSyk`; the positive Worker
installation was started with that value and remains pending its final recap.

### Worker Fleet configuration defect

With the verified Worker fingerprint, the installation reached Fleet and
reproduced a separate product defect:

```text
TASK [admiral_fleet : Deploy admiral-fleet configuration]
fatal: [target]: FAILED! => {"censored": "the output has been hidden due to the fact that 'no_log: true' was specified for this result"}
PLAY RECAP
target : ok=127 changed=13 unreachable=0 failed=1 skipped=200 rescued=0 ignored=0
```

Inspection of the task and installer contract showed that
`ansible/roles/admiral_fleet/tasks/main.yml` renders
`ADMIRAL_FLEET_CALLBACK_KEY`, but `scripts/install.sh` extracted and passed
only `ADMIRAL_TASK_PUBLIC_KEY` to dedicated spokes. The callback variable was
therefore undefined on Worker. Secret-bearing tasks remain protected by
`no_log: true`; the proposed fix extracts
`ADMIRAL_FLEET_CALLBACK_KEY` only for `worker-node` and passes it through the
existing protected JSON extra-vars path.

This is classified PRODUCT DEFECT and is recorded in issue
[#74](https://github.com/admiral-project/admiral/issues/74). The focused
regression set passed: `bash -n scripts/install.sh` and
`python3 -m pytest -q scripts/test_installer_modes.py -k
'worker_receives or spoke_extra or root_lockdown or reconciled'` => `4
passed`. The fix is committed as `cdc9162` and released as a new immutable
RPM build:

| Artifact | Value |
|---|---|
| Commit | `cdc91622cf95ce7332916324f85c005850fec816` |
| SRPM | `admiral-common-0.0.1beta21-120.el10.src.rpm` |
| SRPM SHA-256 | `f057ed8adc40a9f8029937882c92bf29f07b65b9b8b5e7681d25b20401536868` |
| Binary RPM SHA-256 | `b925cfdcbed4f5b18cd603b6eca279d9bc41556fe2ac26a47caf6b391a6dc1ec` |
| Release | `120` |

The SRPM is served at `http://142.93.2.122:8888/`; Worker runtime
verification remains pending COPR publication and a new run.

### Worker proposed-fix runtime verification

Before COPR exposed `120`, the Admin controller was upgraded locally to
`admiral-common-120` and the Worker was re-run. The Fleet configuration task
that previously failed now completed successfully:

```text
TASK [admiral_fleet : Deploy admiral-fleet configuration]
changed: [target]
PLAY RECAP
target : ok=137 changed=19 unreachable=0 failed=0 skipped=206 rescued=0 ignored=0
```

Runtime checks then confirmed:

| Check | Result |
|---|---|
| Worker common package | `admiral-common-0.0.1beta21-119.el10.noarch` (latest COPR package available during the run) |
| Fleet package | `admiral-fleet-0.0.1beta21-54.el10.x86_64` |
| `admiral-fleet` service | `active` |
| Fleet listener | `10.99.0.2:9099` |
| WireGuard | handshake with Admin peer active; allowed IP `10.99.0.1/32` |
| `admiralctl nodes list` | `worker-fresh`: `active`, `healthy`, `available_for_provisioning=true` |

This verifies the proposed callback-key fix functionally, but package-level
acceptance of `120` remains pending its COPR build and a final rerun with the
Worker itself updated to NEVRA `120`. `kdump.service` remains failed on this
1.5 GiB Worker with no reserved crash kernel; it is classified as an
ENVIRONMENTAL BLOCKER and does not explain the Fleet configuration defect.

### WordPress image-update validation and Fleet-56

The local three-node cluster was operated through `admiralctl`: Rocky Linux 10
Admin, AlmaLinux 10 Portal, and CentOS Stream 10 Worker. The WordPress
definition validated and applied, provisioning completed with
`technical_status=running`, `health_status=healthy`, and
`setup_completed=true`, and actual rootless Podman containers were observed
under `admiral-apps`. HTTP returned the expected WordPress redirect.

Database and volume backups succeeded with SHA-256 checksums. Restore requests
while running were rejected with HTTP 409, matching the pause precondition;
sequential database and volume restores while paused succeeded, followed by a
successful resume.

Changing the web image from `wordpress:6` to `wordpress:6.8.1` set
`need_restarting=true` and `update_type=improvement`. Restart through
`admiralctl` then failed twice with the pre-fix Fleet package:

```text
inspect started container "admiral-inst_6115bc8017a1b128-web" for image verification:
... Error: no such container "admiral-inst_6115bc8017a1b128-web"
```

Operation IDs were `op_99f4bff10c158fe8` and `op_ffa5a0a44b2fd2da`. The
instance remained `running` with `need_restarting=true`; the new image was
not verified. This is PRODUCT DEFECT #70, now closed after acceptance of its
fix; package-level verification remains pending.

The root project now pins Fleet commit
`b2d42e0ebca5f546f431294221b174fc945a0d3c`, which pulls requested images via
the rootless helper and recreates affected units. The proposed RPM was built
and tested:

| Artifact | Value |
|---|---|
| RPM | `admiral-fleet-0.0.1beta21-56.el10.x86_64.rpm` |
| RPM SHA-256 | `e9a3af34686a799366cd2e5b3ddf3a285dcb898f2cdfd594a43b2b510cab84a6` |
| SRPM | `admiral-fleet-0.0.1beta21-56.el10.src.rpm` |
| SRPM SHA-256 | `08ebebe999ed9d69675038c18c1d68f3b954d1bb7d834a15409f875249e612a0` |
| Root commit | `d15ce1f` |

`go test ./...` and the RPM `%check` passed. COPR currently exposes only
Fleet `0.0.1beta21-54`; Fleet-56 has been staged in the local SRPM HTTP
directory and awaits COPR publication before rerunning the lifecycle.

### Fleet-56 local runtime verification

The locally built Fleet-56 RPM was installed on the Worker and the service
restarted successfully:

```text
admiral-fleet-0.0.1beta21-56.el10.x86_64
active
```

The lifecycle was repeated through `admiralctl` and succeeded:

```text
stop_operation: op_2cc615d5e26f62f0
start_operation: op_4803ee61a42f3773
```

The instance then reported `technical_status=running`,
`health_status=healthy`, `need_restarting=false`, and
`setup_completed=true`. Direct inspection as `admiral-apps` showed the web
container running `docker.io/library/wordpress:6.8.1`, with the database,
infra, and setup containers also running. HTTP from Admin to the actual
Worker runtime returned WordPress `301 Moved Permanently`. This verifies the
image update fix at runtime with the proposed RPM; COPR publication remains a
distribution-channel check.

The remaining lifecycle steps also completed through `admiralctl`: pause
`op_343d5361a3929c64`, resume `op_db190f6f19f89b8a`, and deprovision
`op_92050a49d2042531`. After deprovision, direct Worker inspection as
`admiral-apps` reported `containers=0`, `volumes=0`, and `units=0` for the
instance ID. The control-plane state was `technical_status=deprovisioned`.

### Security validation update (#69)

The fresh three-node lab produced the following direct evidence:

| Control | Evidence | Result |
|---|---|---|
| SELinux | `getenforce=Enforcing` on Admin, Portal, Worker; AVC count over the validation window was `0` on all three | PASS |
| External TCP exposure | Nmap found Admin `22,80,443`; Portal `22`; Worker `22`; no unexpected TCP ports among `5001,5432,9099,40000,51820` | PASS for documented lab exposure |
| WireGuard UDP exposure | Nmap reported `51820/udp open|filtered` on each node; internal listeners matched `51820/udp` | PASS |
| SSH hardening | All nodes: `pubkeyauthentication yes`, `passwordauthentication no`, `kbdinteractiveauthentication no`; Portal/Worker `permitrootlogin no`; password-only SSH was rejected | PASS |
| Secrets | Redacted scans of journal, `/tmp`, and `/var/log` found no secret material. One Admin match was non-secret `GENERATE_SSH_KEY` metadata | PASS; false positive recorded |
| Permissions | WireGuard private keys `0400/0600`, configuration directories `0700/0750`, TLS private material restricted to root/admiral; no world-writable Admiral files | PASS |
| Rootless isolation | `podman info` as `admiral-apps` reported `rootless=true`; Golden Test containers used `no-new-privileges` | PASS |
| DNS | All nodes resolved `example.com` through the configured NetworkManager resolver; no unexpected DNS listener exposed | PASS |
| Resource pressure | Worker `/tmp` filled to 92%, Fleet remained active, cleanup returned free space to 40% | PASS |

Segmentation returned the expected failures: Worker could not reach
Admin/Portal PostgreSQL, Portal could not reach Worker Fleet or PostgreSQL,
and Admin could not reach Portal PostgreSQL. Worker could reach the documented
Admin API on `10.99.0.1:8080`; other tested undocumented paths rejected or
timed out.

WireGuard negative validation temporarily added an invalid peer with
`AllowedIPs=10.99.0.250/32`; its latest handshake remained `0`. Removing it
restored both legitimate peers and active handshakes. No invalid peer or
temporary key remained.

The first reboot cycle exposed a libvirt harness limitation: `systemctl
reboot` powered off each disposable guest rather than automatically returning
it. Starting the same guests again restored services. Before the WireGuard
fix, Admin booted with zero peers despite durable `peers.d` files; this
reproduced historical issue [#8](https://github.com/admiral-project/admiral/issues/8).
Fix `a138797` preserves peer fragments by default. After rendering the
corrected configuration, Admin reboot retained two peer blocks, both
handshakes became active, and `admiralctl nodes list` reported Portal and
Worker `active/healthy` with fresh heartbeats. The shutdown behavior remains
an ENVIRONMENTAL BLOCKER for fully automated reboot validation.

TLS chain/SAN/expiration validation passed, but the pre-fix internal
`admirald.pem` lacked `keyUsage` and `extendedKeyUsage`. This reproducible
PRODUCT DEFECT is tracked in [#75](https://github.com/admiral-project/admiral/issues/75).
Fix `2bad3e3` adds CA constraints, TLS server key usage, and
`serverAuth,clientAuth` EKU. `admiral-common-0.0.1beta21-121` was compiled,
installed locally on Admin, and its generation commands verified with
`openssl verify`, SAN, critical constraints, key usage, EKU, and expiration.

| Artifact | SHA-256 |
|---|---|
| `admiral-common-0.0.1beta21-121.el10.src.rpm` | `1544967de7d801e3b16266e0268eaff601b8749fdac81d1dc8f36a18abe40713` |
| `admiral-common-0.0.1beta21-121.el10.noarch.rpm` | `f77d4446bff8e141eb5c43d4e247e6cd57c3ec64be8232103593c72c6d2b2d85` |

The SRPM is staged at `http://142.93.2.122:8888/` for COPR import. Existing
lab certificates were not replaced destructively; replacement material was
verified in an isolated temporary directory and removed.

### Current release-gate status

The local runtime gate is complete for the three-node WordPress lifecycle and
the security checks above. GitHub currently has only #68 and #69 open among
the tracked beta21 fixes; #63–#67 and #70–#74 are closed after accepted
changes. Newly discovered TLS defect #75 remains intentionally open for peer
review. Fleet-56 and common-121 are compiled and staged on the local SRPM
server, but COPR metadata must expose those exact NEVRAs before distribution
channel acceptance can be marked PASS.

The current release verdict therefore remains **BLOCKED** pending COPR
publication/verification of the proposed packages, review of #75, and the
libvirt reboot-harness limitation. No validation issue was closed by this
agent.

### COPR Fleet-56 revalidation and second proposed fix

COPR now exposes Fleet `0.0.1beta21-56`. The exact COPR RPM was downloaded
from its published URL and installed on Worker. A new WordPress instance was
provisioned successfully (`op_43c2ef69ea717f64`), then the image definition
was changed to `wordpress:6.8.1`, setting `need_restarting=true`. The restart
still failed with `no such container` (`op_baedb9e6473b85c2`), proving that
the first accepted fix was incomplete in the production artifact.

The failure is a bounded systemd/Podman materialization race: Fleet inspects
the named rootless container immediately after `systemd start`, before conmon
has created it. Issue #70 was reopened and the evidence was posted there.

The second proposed fix is Fleet commit
`4d2897048dc17e91151c5e46ad4fe919f5c83ff3`. It retries only transient
`no such container` inspection errors for a bounded 30-second window and
includes a regression test. Full Fleet tests and the RPM `%check` passed.

| Artifact | SHA-256 |
|---|---|
| `admiral-fleet-0.0.1beta21-57.el10.src.rpm` | `2b246739b17c1424da78f9b818e3d0ae1497a23af6cb37822b77318e06caf32c` |
| `admiral-fleet-0.0.1beta21-57.el10.x86_64.rpm` | `4d79f42c069ef0ef6ef425181d0a9a669ae0eb105020bc2660e6f6abc9d1e927` |
| Root commit | `ddc116f` |

Fleet-57 SRPM is staged at `http://142.93.2.122:8888/` pending COPR import;
no success is inferred until the COPR artifact itself passes the same runtime
scenario.

### Fleet-57 local runtime verification

The proposed Fleet-57 RPM was installed on the Worker from the locally built
artifact. The previously provisioned COPR-56 reproduction instance was
restarted through `admiralctl` using the normal control-plane workflow:

| Check | Evidence | Result |
|---|---|---|
| Restart operation | `op_d74092c35958e1e4`, status `succeeded`; stop operation `op_1bc4ba7f117d5fdf` | PASS |
| Runtime state | `technical_status=running`, `health_status=healthy`, `setup_completed=true` | PASS |
| Image update flag | `need_restarting=false` after restart | PASS |
| Application lifecycle | Instance remained provisioned and healthy after materialization retry | PASS |

This verifies the proposed retry fix locally, but does not substitute for
verification of the exact Fleet-57 binary produced by COPR. Issue #70 remains
open pending that channel-level verification.

### Release-gate correction

The earlier summary stating that only #68 and #69 were open is superseded.
Current relevant open issues are #68, #69, #70, and #75. Issue #70 was
reopened after the exact COPR-56 artifact reproduced the image-update race;
#75 is the newly discovered internal TLS key-usage defect and remains open for
peer review. No issue was closed by this validation run.

### COPR publication audit — 2026-08-06

The current COPR project page does not expose the proposed artifacts. Direct
requests for `admiral-fleet-0.0.1beta21-57.el10.x86_64.rpm` and
`admiral-common-0.0.1beta21-121.el10.noarch.rpm` returned HTTP 404. The latest
published Fleet build visible in the project history remains beta21-56.
Therefore no COPR-57 runtime result is claimed, and the distribution gate
remains **BLOCKED** pending publication and exact-artifact verification.

### Repeated external-state audit — 2026-08-06

A subsequent audit found no external-state change: both exact COPR URLs still
return HTTP 404 and the open issue set remains #68, #69, #70, and #75. The
three-node lab remains available, but the required distribution-channel test
cannot be truthfully executed until the exact packages are published.

### COPR artifacts published — 2026-08-06

The exact proposed artifacts are now available from COPR. Direct downloads
returned HTTP 200 and RPM metadata matched the requested NEVRAs:

| Artifact | NEVRA | SHA-256 |
|---|---|---|
| Fleet | `admiral-fleet-0.0.1beta21-57.el10.x86_64` | `b95e63d0681bd438c839d8a79fefc276d10dd60ecdc1a00d6f0d21c13ec0a33f` |
| Common | `admiral-common-0.0.1beta21-121.el10.noarch` | `626c51ebd9692680812acc331321eb42df399b23d7760290eda664eaff6a78b2` |

The exact Fleet-57 RPM was staged on the Admin for delivery, but after the
Worker reboot its SSH delivery key was no longer accepted on either the LAN
or WireGuard address. The Worker still reports healthy through Fleet, while
`admiralctl nodes show worker-fresh` reports the installed Fleet version as
`0.0.1beta20`; therefore the exact COPR runtime test has not yet been claimed
as passed. This is currently a lab access/harness condition, not a product
failure classification.

### COPR-57 version identity defect and proposed correction — 2026-08-06

After restoring the Worker SSH delivery account (`admiral-ssh`), the exact
COPR Fleet-57 RPM was installed and its downloaded RPM SHA-256 was verified as
`b95e63d0681bd438c839d8a79fefc276d10dd60ecdc1a00d6f0d21c13ec0a33f`. The
package NEVRA was correct, but the Worker heartbeat still reported
`fleet_version=0.0.1beta20`. Source inspection identified
`internal/agent/heartbeat.go:const FleetVersion` as the cause. This is a
PRODUCT DEFECT in the published beta21 artifact and is covered by beta21
validation issue #68.

The correction changes the heartbeat identity to `0.0.1beta21` and adds an
exact-version regression test. Fleet commit
`c2ac4f46f78aa301f3e26757d2a5dfd465605369` was pushed with a signed semantic
commit. The root pin was updated in commit `f6fd13e`; the RPM release was
incremented from 57 to 58.

| Proposed artifact | SHA-256 |
|---|---|
| `admiral-fleet-0.0.1beta21-58.el10.src.rpm` | `89fb945d90e5be7868baa66f8b0ccf5444e314da5c32eb70f276bd700a501fc1` |
| `admiral-fleet-0.0.1beta21-58.el10.x86_64.rpm` | `995a0232b2b1a2e6c60deca215c0bdbb16e8aef763002cb962daf30640e25d52` |

`go test ./...` and the RPM `%check` pass. The beta21-58 SRPM is staged on
the local source server for COPR import. Fleet-58 must be published and
retested before #68 can be closed.

### Fleet-58 local revalidation — 2026-08-06

The locally built Fleet-58 RPM was installed on the Worker. Its SHA-256 was
verified as `995a0232b2b1a2e6c60deca215c0bdbb16e8aef763002cb962daf30640e25d52`,
the service was active, and the control plane subsequently reported
`fleet_version=0.0.1beta21` with `health_status=healthy`.

The WordPress update scenario was exercised through `admiralctl`. A test
attempt to change the web image to `wordpress:6.8.0` failed while the helper
was pulling the image with `signal: killed` (`op_584322f276954de1`); this is
classified as an ENVIRONMENTAL BLOCKER on the 1.5 GiB Worker, not as the
previous `no such container` race. The definition was restored to
`wordpress:6.8.1`, and restart succeeded:

| Check | Evidence | Result |
|---|---|---|
| Stop | `op_b6ea46e35c0909a2` | PASS |
| Start | `op_1ee5458d37394448` | PASS |
| State | `technical_status=running`, `need_restarting=false`, `health_status=healthy` | PASS |
| Runtime | rootless web container `docker.io/library/wordpress:6.8.1` | PASS |
| HTTP | WordPress `301 Moved Permanently` on allocated port `40001` | PASS |

The exact Fleet-58 COPR URL still returns HTTP 404; only the local Fleet-58
artifact has been runtime-tested. The release gate and issue #68 therefore
remain open pending COPR publication and exact-artifact repetition.

### Repository publication audit — 2026-08-06

All Admiral component repositories are synchronized with `origin/main`:

| Repository | Commit on `origin/main` |
|---|---|
| `admirald` | `df2c87425aa1614e869495a52bad4c2ff09b2ec9` |
| `admiral-fleet` | `c2ac4f46f78aa301f3e26757d2a5dfd465605369` |
| `admiralctl` | `3c50732484b766e167383756659b57249f70470b` |
| `admiral-flagship` | `34fd70c380649cd85c76cd1bd905650222b2d0d9` |
| `admiral-harbor` | `c9e4f73407db81849067585159d375804f53c519` |

### Current issue gate — 2026-08-06

The security evidence was posted to issue #69 and the issue was closed after
validation. The only remaining open issue is #68. Fleet-58 is compiled,
locally installed, and locally verified, but its exact COPR URL still returns
HTTP 404; therefore #68 remains open pending publication and exact-artifact
verification.

### DNF COPR channel audit — 2026-08-06

The Admin's enabled repositories include
`copr:copr.fedorainfracloud.org:admiral-project:admiral`. After
`dnf clean all` and `dnf makecache --refresh`, `dnf --showduplicates list`
exposed Common-121 and Fleet through Fleet-57. COPR build `10827876` for
Fleet-58 is submitted but still `running`, so DNF cannot yet expose Fleet-58.
The exact RPM installation test remains pending build completion.

The same build already produced an Alma/EPEL x86_64_v2 package. Its direct
artifact returned HTTP 200 and SHA-256
`7efe6e53ba52c1c915a7f747e4d67be7f9f529dfa5c129f21baeb82ac9d309bc`. Attempting
to install it on the CentOS Worker with `dnf install` was rejected as an
incompatible architecture (`x86_64_v2`). It was not forced with RPM, because
that would not be a valid target-architecture validation. The Worker remains
on the locally built Fleet-58 x86_64 package while the EPEL x86_64 chroot
finishes.
