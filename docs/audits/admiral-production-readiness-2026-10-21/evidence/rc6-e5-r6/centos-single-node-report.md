# RC6 Epoch 5 / Release 6 — CentOS Stream 10 Single-Node

**Result: PASS — 2026-10-26.** This is one release-gate cell only; the candidate is not Gold.

## Candidate identity

- Candidate: `0.0.1rc6`, Epoch `5`, Release `6`
- Architecture: `x86_64`
- Source revision in the RPM set: root `bfa00c07f462bafc32627922d884248f9523c603`
- Component pins: admirald `6e4a725d30c0fff877fe2252e843fae687810ae6`; fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Native EL10 RPMs were installed from the signed local repository. The exact six-package NEVRA and SHA-256 manifest is `el10/x86_64/RPM-MANIFEST.tsv`.

## Guest and installation

- CentOS Stream 10 (Coughlan), kernel `6.12.0-278.el10.x86_64`, `x86_64`
- `admiral-install --single-node --validation-seed` completed successfully. Ansible recap: `ok=231 changed=96 unreachable=0 failed=0`.
- SELinux was `Enforcing` after the real reboot and `/etc/selinux/config` contained `SELINUX=enforcing`.
- PostgreSQL, admirald, admiral-fleet, Caddy, admiral-harbor, and admiral-flagship were active at final check. No failed systemd units remained.

## Functional acceptance

The complete lane is recorded in `functional/centos-single/lane.log`.

- Provisioned a real rootless workload; duplicate idempotency key returned the same operation and instance.
- Verified running/healthy/available state, HTTP 200, and a persistent PostgreSQL marker.
- Resized small → medium → small while preserving HTTP 200 and the SQL marker.
- Created a database backup with checksum; restore while running was rejected with HTTP 409; paused restore recovered the original marker and HTTP 200.
- Pause/resume, stop/start, workload restart, and admirald restart recovered successfully.
- Performed a real guest reboot: boot ID changed from `0fcf2102-bc6b-419d-af7a-b6eb7151faeb` to `ba343c77-45ed-4169-9b27-6397dbedcb0b`; workload and SQL marker recovered, HTTP returned 200, and deprovision succeeded.
- Final rootless container, pod, volume, and matching unit inventories were empty; all six RPM NEVRAs remained exact.

## Issue #228 targeted acceptance

The separate controlled failure injection is recorded in `issue-228-centos-single.log`. With the six candidate RPMs installed, injected Podman removal failures caused the first deprovision operation to fail and preserve the instance as stopped/unavailable while residual resources remained. Restoring Podman byte-for-byte and retrying deprovision succeeded, marked the instance deprovisioned, and removed the residual containers, pod, and volume. The Single-Node half passes; Multi-Node validation remains required before closing #228.

## Evidence hashes

- Functional lane: `8d66b6f842673a434c0a80ae81746ea69bc8426813f420080a7e96ffed56a645`
- Installer log: `407047023a0d1a584c53c9476b9a74647d5f77a6a724b75f9607a7b453b2c1bb`
- Final state: `f549ba2ff1071deb57b038392c7693a50664e1597ab93bf16ab30311f31cafa0`
- Issue #228 targeted run: `75ba6cfe492fe5f7f083b5ddb5cb66fe6e55365104681f68fbb2f01cb959d21c`

## Release matrix

| Operating system | Single-Node | Multi-Node |
|---|---:|---:|
| Rocky Linux 10 x86_64 | **PASS** | Pending |
| CentOS Stream 10 x86_64 | **PASS** | Pending |
| Fedora Rawhide x86_64 | **PASS** | Pending |

Current matrix result: **3/6**.
