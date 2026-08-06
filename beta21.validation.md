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
a non-blocking Tier 2 limitation. The required three-node, network
segmentation and WireGuard evidence is blocked by repository availability and
an invalid worker overlay containing beta20 state. Negative checks and final
cleanup evidence remain open.

## Security and negative validation

The portable TLS correction was tested in isolation, including expected
lineage rejection and restart-failure rollback. Existing hardening regressions
for issues #63–#67 are covered by commits `944a3c5`, `168463b`, `01985fe`,
`a8acf56`, and `e134645`; those issues remain open for review and were not
closed.

The complete VM-level checks requested by #68/#69 (SELinux AVC delta, external
port scan, three-node segmentation, WireGuard break/restore, SSH password
rejection, secret scans, permissions, reboot recovery, and hostile-node tests)
remain incomplete because the multi-node installation did not produce clean
Portal and Worker recaps. The
single-node SELinux, firewall, listener, permissions and SSH smoke checks
passed on Rocky, Alma and CentOS; they do not substitute for the blocked
multi-node checks.

## GitHub issue evidence

Comments were posted on issues #63–#69. Issue #70 records the reproducible
image-update defect, the two proposed Fleet fixes, RPM `-54` verification and
runtime evidence. Issue #70 remains OPEN intentionally for independent review;
no issue was closed.

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
passed`. The fix requires a new immutable RPM release `120`; Worker runtime
verification remains pending that build.
