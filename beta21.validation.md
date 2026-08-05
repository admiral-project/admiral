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

## Release matrix

| Escenario | Resultado beta21 | Evidence / classification |
|---|---|---|
| Rocky Linux 10 single-node, clean GenericCloud | PASS for installation, security smoke, Golden Test and cleanup | Official image SHA256 `9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48`; guest `beta21-rocky-single`. Installer playbook: `ok=222 changed=100 unreachable=0 failed=0`. WordPress lifecycle completed through apply, provision, setup, healthy/HTTP, DB and volume backup/restore, pause/resume, image update, deprovision and cleanup. Fix verification operation `op_38cc937ae41fab9d` succeeded; actual rootless container image was `docker.io/library/wordpress:6.8.1`, `need_restarting=false`, HTTP 301. |
| AlmaLinux 10 single-node, clean GenericCloud | PASS for installation, security smoke, complete Golden Test and cleanup | Official image SHA256 `47f2218668dd4776be140dd92fa3bea700be1766e2c7d88bdfd6a4b50f477b4d`; guest `beta21-alma-single` at `192.168.122.175`. Installer playbook: `ok=222 changed=100 unreachable=0 failed=0`; all required Admiral services active, SELinux Enforcing, firewall services `http https ssh`, SSH password authentication disabled. Via `admiralctl`: apply/provision/setup/healthy, HTTP validation, DB backup `op_f8aceb3d5d1d1629`, volume backup `op_30748a2240256227`, DB restore `op_1b8652b6479de09e`, volume restore `op_0ae3785f926f3479`, pause/resume, image update/restart `op_ca110125182c6fa1`, actual rootless `wordpress:6.8.1` image ID `36e2490fa1a957f3cee615693157139c64b69951dcc7bfd48ee4fd6d03750a31`, `need_restarting=false`, healthy, then deprovision `op_b5fd3d973ff9313e`; no containers remained. |
| CentOS Stream 10 single-node, clean GenericCloud | PASS for installation/security smoke and complete Golden Test; environmental kdump blocker recorded | Official image SHA256 `9116da2c148c2a3da55579238a543ee9bd238265eba89234201d680e19ae1fbc`; guest `beta21-centos-single` at `192.168.122.249`. Installer playbook: `ok=221 changed=100 unreachable=0 failed=0`; Admiral services active, SELinux Enforcing, firewall services `http https ssh`, SSH password authentication disabled. `kdump.service` failed with `No memory reserved for crash kernel`; classified ENVIRONMENTAL BLOCKER for this VM. Via `admiralctl`: provision `op_9c15044bd37fa44a`, healthy/setup complete, HTTP 308, DB backup `op_7ef753bbe9fd6648`, volume backup `op_8c77a64b0b36c5b5`, DB restore `op_fc204fecdb0a0fa7`, volume restore `op_d7db0ff4aac828ce`, pause/resume, image update/restart `op_f6376d466f6da770`, actual rootless `wordpress:6.8.1` image ID `36e2490fa1a957f3cee615693157139c64b69951dcc7bfd48ee4fd6d03750a31`, `need_restarting=false`, healthy, then deprovision `op_3ae38ca9143977f2`; no containers remained. |
| Fedora smoke and WordPress attempt | FAIL, non-blocking Tier 2 expected limitation; no fix applied | Official Fedora 44 Generic Cloud image `Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2`, SHA256 `28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f`; guest `beta21-fedora-smoke` at `192.168.122.47`. RPM installation and `--dev-node` installer completed; SELinux Enforcing. `admiral-harbor-worker` and `admiral-harbor-catalog-sync` fail with `ADMIRAL_INSECURE_SKIP_VERIFY must be false in production`; this matches the documented Fedora/Python 3.14/OpenSSL limitation and was not changed. WordPress `admiralctl instances provision` was attempted four times and failed safely with HTTP 503; persisted operations report `node_provisioning_rejected_no_capacity` with `metrics_stale`, `node_unhealthy`, and Fleet evidence of `wireguard_ip_mismatch`/HTTP 403. Classified EXPECTED LIMITATION for the documented Tier 2 dev-node path, not a Tier 1 release blocker. |
| Admin/Portal/Worker multi-node | BLOCKED; partial execution with environmental blockers | q35 clean-boot rerun reached SSH: Admin `192.168.122.32`, Portal `192.168.122.247`, Worker `192.168.122.182`. Admin playbook completed `ok=193 changed=99 unreachable=0 failed=0`; final installer check initially failed only because the harness staged RPMs with `rpm --nodeps` and omitted declared `python3-gunicorn`; installing the declared dependency made Flagship active and `admiralctl status --output json` returned `{"status":"healthy"}`. Portal failed three times on repository access: first `ok=118 changed=58 unreachable=0 failed=1` downloading `perl-Getopt-Std`, retry one failed AppStream `repomd.xml`, and retry two failed CRB `repomd.xml` (`all mirrors tried`). Worker first failed `ok=133 changed=51 unreachable=0 failed=1` and retry failed `ok=127 changed=13 unreachable=0 failed=1` in the `no_log` Fleet configuration task; the VM also contained pre-existing beta20 packages, so this execution is not valid clean-image evidence. Classified HARNESS DEFECT for RPM staging/contaminated overlay and ENVIRONMENTAL BLOCKER for repository outage; no PASS is inferred. |
| WordPress Golden Test | PASS Rocky, AlmaLinux and CentOS Stream; Fedora non-blocking failure documented | Rocky, AlmaLinux and CentOS each completed the full lifecycle with CLI and runtime evidence. Fedora provisioning was attempted and failed with documented Tier 2 node-health/certificate limitations; no Fedora fix was applied. |
| VM destruction/cleanup | OPEN | Multi-node VMs remain active for evidence collection and revalidation. Final cleanup (domains, overlays, bootstrap key and temporary files) is pending and must not be marked PASS yet. |

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
