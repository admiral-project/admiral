# RC6 Epoch 5 / Release 6 — Fedora Rawhide Single-Node

**Result: PASS — 2026-10-26.** This is one release-gate cell only; the candidate is not Gold.

## Candidate identity

- Candidate: `0.0.1rc6`, Epoch `5`, Release `6`
- Architecture: `x86_64`
- Source revision in the RPM set: root `bfa00c07f462bafc32627922d884248f9523c603`
- Component pins: admirald `6e4a725d30c0fff877fe2252e843fae687810ae6`; fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Fedora-native package suffix: `.fc46`. The guest installed packages from the signed local Fedora repository, not EL10 RPMs.

| Package | NEVRA | RPM SHA-256 |
|---|---|---|
| admiral-common | `5:admiral-common-0.0.1rc6-6.fc46.noarch` | `4a58fc5e83370ee1f7aa2fe130ae96bd55d4f036855b804e677afe49447df51e` |
| admirald | `5:admirald-0.0.1rc6-6.fc46.x86_64` | `0d83781bd48f219686870c7cdaa0db52a490c7b70e0d6bf9a38cd43b1e5698f7` |
| admiral-fleet | `5:admiral-fleet-0.0.1rc6-6.fc46.x86_64` | `25010c906586532403edcf2427bf420e4f399df4f190d0114362de8eb960e324` |
| admiralctl | `5:admiralctl-0.0.1rc6-6.fc46.x86_64` | `e4c1d7c75362b9baa3ffd28c3687231ffbf968a5099969bd9809afccad1d9340` |
| admiral-harbor | `5:admiral-harbor-0.0.1rc6-6.fc46.noarch` | `cb80eac589c838839d3402c83044a20453516468223aa9c0c460ac8e8e26728c` |
| admiral-flagship | `5:admiral-flagship-0.0.1rc6-6.fc46.noarch` | `6e3da2ef50ab008f71b69c266b954eae85ffc472638472f38df4d8926eb0e3ae` |

The complete candidate manifest, signatures, and native build logs are in this directory. The installed NEVRAs were checked before and after the functional sequence.

## Guest and installation

- Fedora Linux 46 Cloud Edition Prerelease, kernel `7.4.0-0.rc0.261023g734bef548a96.6.fc46.x86_64`, `x86_64`
- `admiral-install --single-node --validation-seed` completed successfully. Ansible recap: `ok=238 changed=98 unreachable=0 failed=0`.
- SELinux: Enforcing. PostgreSQL, admirald, admiral-fleet, Caddy, admiral-harbor, and admiral-flagship were active at final check. No failed systemd units remained.

## Functional acceptance

The complete lane is recorded in `functional/fedora-single/lane.log`.

- Provisioned a real rootless workload; duplicate idempotency key returned the same operation and instance.
- Verified running/healthy/available state, HTTP 200, and a persistent PostgreSQL marker.
- Resized small → medium → small while preserving HTTP 200 and the SQL marker.
- Created a database backup with checksum; restore while running was rejected with HTTP 409; paused restore recovered the original marker and HTTP 200.
- Pause/resume, stop/start, workload restart, and admirald restart recovered successfully.
- Performed a real guest reboot: boot ID changed from `fc590cee-4fef-4f3c-afef-b7fbc11f6c66` to `02c847fd-a4a3-4087-803d-4536919fb4db`; workload and SQL marker recovered, HTTP returned 200, and deprovision succeeded.
- Final rootless container, pod, volume, and matching unit inventories were empty; all six RPM NEVRAs remained exact.

Evidence hashes:

- Functional lane: `2b6719a5f17c6a5f5c17451e9e0dd548b958c82b8f48be5c2f70801cc1971e27`
- Installer log: `03b9884c1edb507226f759e762af54d151f2a4b7884ff92c11a14c04d7d7d032`

## Release matrix

| Operating system | Single-Node | Multi-Node |
|---|---:|---:|
| Rocky Linux 10 x86_64 | Pending | Pending |
| CentOS Stream 10 x86_64 | Pending | Pending |
| Fedora Rawhide x86_64 | **PASS** | Pending |

Current matrix result: **1/6**.
