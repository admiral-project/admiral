# Admiral beta21 validation

Fecha de corte: 2026-08-05 (UTC-04:00). Este informe conserva la regla de
validación objetiva: una ejecución beta20 no se convierte automáticamente en
una ejecución beta21.

## Candidato

El cambio correctivo de esta iteración es `831b5d8e24155621151a2343f1e4ae18f67f1527`
(`fix(tls): replace deprecated certificate hostname check`). El hook de
renovación ya validaba lineage y rollback, pero todavía usaba
`openssl x509 -checkhost`; beta21 lo reemplaza por lectura explícita de SAN
con `openssl x509 -ext subjectAltName`. El commit tiene trailer Signed-off-by.

Los submódulos estaban limpios y alineados con `origin/main`:

| Componente | Commit |
|---|---|
| admirald | `df2c87425aa1614e869495a52bad4c2ff09b2ec9` |
| admiral-fleet | `3cedeea041c99276938d70c827da183f4d429a47` |
| admiralctl | `3c50732484b766e167383756659b57249f70470b` |
| admiral-flagship | `34fd70c380649cd85c76cd1bd905650222b2d0d9` |
| admiral-harbor | `c9e4f73407db81849067585159d375804f53c519` |

`python3 scripts/validate-release-refs.py` terminó PASS.

## RPM beta21 local

| NEVRA | SHA-256 |
|---|---|
| `admiral-common-0.0.1beta21-113.el10.noarch` | `7ff7b79645286061221d001196c0c7290c9aa66104145a05b65a6eae9b11f788` |
| `admirald-0.0.1beta21-46.el10.x86_64` | `ac6eb0061ba5405ebfc7f52f20e393f85cefee174fb9e7eaf59db7d1f5569763` |
| `admiral-fleet-0.0.1beta21-51.el10.x86_64` | `dc277066403b5d9ff9e6736a8166f01b0fe072fd3e8ff049d07e3d6ef49189bf` |
| `admiralctl-0.0.1beta21-44.el10.x86_64` | `c18f8fe6dfdc84e25aad2d3462421b8e6dc9f5bc0bc9de381857a1b2c043c9bf` |
| `admiral-flagship-0.0.1beta21-77.el10.noarch` | `81b755c045c289516e17b92d142c412aad296b7c2e5ecd6276d7af3f86e4c6cd` |
| `admiral-harbor-0.0.1beta21-45.el10.noarch` | `8869caa848b6ec31a2f988594a65ea3d881ea6efd7aaa347995c3bb462eace04` |

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
| Rocky Linux 10 single-node, clean GenericCloud | NOT TESTED in this cut | Prior beta20 evidence exists in `beta20.validation.md`; it is not evidence for the new NEVRAs. ENVIRONMENTAL BLOCKER: no disposable image/VM was present. |
| AlmaLinux 10 single-node, clean GenericCloud | NOT TESTED in this cut | Same reason. |
| CentOS Stream 10 single-node, clean GenericCloud | NOT TESTED in this cut | Validation host is CentOS Stream 10, but it is not a clean VM. |
| Fedora smoke | NOT TESTED | No Fedora guest/image was available. Non-blocking by policy. |
| Admin/Portal/Worker multi-node | NOT TESTED in this cut | Prior beta20 report records the worker installer gate as not PASS; no beta21 three-VM run was performed. |
| WordPress Golden Test | NOT TESTED against beta21 packages | Prior beta20 lifecycle evidence remains historical only. |
| VM destruction/cleanup | NOT TESTED | No beta21 VMs were created. |

The host has `/dev/kvm`, 4 vCPU, 8 GiB RAM and 155 GiB free disk. QEMU/libvirt
packages were installed during preparation, but no libvirt daemon, guest
images, or disposable overlays existed in the workspace. Therefore the
required clean-VM matrix cannot be marked PASS from this host state.

## Security and negative validation

The portable TLS correction was tested in isolation, including expected
lineage rejection and restart-failure rollback. Existing hardening regressions
for issues #63–#67 are covered by commits `944a3c5`, `168463b`, `01985fe`,
`a8acf56`, and `e134645`; those issues remain open for review and were not
closed.

The complete VM-level checks requested by #68/#69 (SELinux AVC delta, external
port scan, three-node segmentation, WireGuard break/restore, SSH password
rejection, secret scans, permissions, reboot recovery, and hostile-node tests)
were not executed against beta21. They remain NOT TESTED rather than PASS.

## GitHub issue evidence

Comments were posted on issues #63–#69 with the candidate commit/build/test
evidence. No issue was closed. Any new defect discovered by the clean-VM run
must be opened separately, linked to this report, and left open for review.

## Verdict

**BLOCKED** for publication acceptance: source fixes and local RPM/test gates
pass, but the required beta21 clean-VM release and security matrix lacks
execution evidence. This report intentionally does not claim that beta20
results prove beta21.
