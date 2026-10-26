# RC6 Epoch 5 / Release 6 — Rocky Linux 10 Single-Node

**Result: PASS — 2026-10-26.** This is one release-gate cell only; the candidate is not Gold.

## Candidate identity

- Candidate: `0.0.1rc6`, Epoch `5`, Release `6`
- Architecture: `x86_64`
- Source revision in the RPM set: root `bfa00c07f462bafc32627922d884248f9523c603`
- Component pins: admirald `6e4a725d30c0fff877fe2252e843fae687810ae6`; fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Native EL10 RPMs were installed from the signed local repository. The exact six-package NEVRA and SHA-256 manifest is `el10/x86_64/RPM-MANIFEST.tsv`.

## Guest and installation

- Rocky Linux 10.2, kernel `6.12.0-211.68.1.el10_2.x86_64`, `x86_64`
- `admiral-install --single-node --validation-seed` completed successfully. Ansible recap: `ok=232 changed=96 unreachable=0 failed=0`.
- SELinux was `Enforcing` before and after the real reboot; `/etc/selinux/config` contained `SELINUX=enforcing` after reboot.
- PostgreSQL, admirald, admiral-fleet, Caddy, admiral-harbor, and admiral-flagship were active at final check. No failed systemd units remained.

## Functional acceptance

The complete lane is recorded in `functional/rocky-single/lane.log`.

- Provisioned a real rootless workload; duplicate idempotency key returned the same operation and instance.
- Verified running/healthy/available state, HTTP 200, and a persistent PostgreSQL marker.
- Resized small → medium → small while preserving HTTP 200 and the SQL marker.
- Created a database backup with checksum; restore while running was rejected with HTTP 409; paused restore recovered the original marker and HTTP 200.
- Pause/resume, stop/start, workload restart, and admirald restart recovered successfully.
- Performed a real guest reboot: boot ID changed from `550b2f5d-9e13-4358-8e64-5144c7d6a513` to `6687d3bd-8bf5-456c-8c76-61c6fa34323b`; workload and SQL marker recovered, HTTP returned 200, and deprovision succeeded.
- Final rootless container, pod, volume, and matching unit inventories were empty; all six RPM NEVRAs remained exact.

Evidence hashes:

- Functional lane: `b22784cd7a0acd915eea20bea70d8ae7ee4ddb97ed9b33d4d06f691bd8d51f85`
- Installer log: `ca6f4c357ac34954ec30ce496cc0473fc5b1a57c422dbd51d2aaa63012712f6d`
- Final state, including SELinux runtime and boot configuration: `0787cad8826d1bf18343571c0db2b8e0208c12efdca35f12903ac0ff1674c9ae`

## Release matrix

| Operating system | Single-Node | Multi-Node |
|---|---:|---:|
| Rocky Linux 10 x86_64 | **PASS** | Pending |
| CentOS Stream 10 x86_64 | Pending | Pending |
| Fedora Rawhide x86_64 | **PASS** | Pending |

Current matrix result: **2/6**.
