# Release 74 Single-Node fresh-VM rerun — 2026-10-24

## Result

**All three active Single-Node cells PASS in one coordinated run:** Rocky Linux 10.2, CentOS Stream 10 and Fedora Rawhide 46, x86_64. Each lane completed all six functional stages on a fresh VM. Matrix status remains **3/6** because Rocky, CentOS Stream and Fedora Multi-Node have not passed. This is functional Release 74 evidence, not a full production-readiness certification.

The rerun followed a launcher-only failure: the first coordinated launch was blocked before entering any test because `run-single-pass.sh` tried to execute `run-single-lane.sh`, whose Git mode was `100644`. The failure is retained under `packaging/build/validation/rc5-r74/runtime/single-recheck-20261024T1935Z/single/{rocky,centos,fedora}/launcher.log`. The executable bit was fixed in root commit [`888e097`](https://github.com/admiral-project/admiral/commit/888e09733911feaaaf6ba7d711729ad39f989769); its root CI passed in [run 40126619383](https://github.com/admiral-project/admiral/actions/runs/40126619383). The three test lanes then ran concurrently against new seed clones. The initial launch is classified as a harness failure before test execution, not as a product result.

An early SSH preflight probe also ran before cloud-init/network startup had completed and received `No route to host`/`Connection refused`. Those first-attempt logs are preserved under `preflight/initial-connect-attempt/` and `preflight/*-connect-retries.log`; retrying after guest startup succeeded, and all three recorded preflights passed.

## Candidate and environment identity

- Admiral RPM candidate: Release 74, exact package-preparation source commit `d6e5cacb7c35807417f19b7f970c1d1f6a2d387c`; the five component pins, component CI and coordinated RPM manifests are recorded in [`release74-single-node.md`](release74-single-node.md).
- No Admiral source, spec or RPM bytes changed between the prior pass and this rerun. Root commit `888e097` changes only the executable mode of the R74 audit lane script.
- The R74 candidate root CI remains [40120683532](https://github.com/admiral-project/admiral/actions/runs/40120683532); component CI and RPM checksums are in the candidate report and manifests.
- Host: Rocky Linux 10.2 x86_64, 4 vCPU, 8 GiB RAM, 4 GiB swap, KVM/libvirt. The test used three concurrent 2-vCPU/2-GiB guests. A final host check found 53 GiB free disk; this is a final snapshot, not peak-time disk monitoring.
- Seed image hashes are unchanged from [`ansible-seed-preflight-20261024.md`](ansible-seed-preflight-20261024.md). Earlier same-day preflight clones from those exact images reported zero pending OS package updates. This rerun used those images without repeating a full OS update.
- The candidate repository was set up in each guest, not baked into the seeds. EL10 guests used EPEL and CRB plus Admiral COPR; Fedora used Fedora-native repositories and Admiral COPR. The exact six per-OS Release 74 RPMs were installed through signed native DNF resolution, without `--nodeps`, force, vendor override or cross-distribution binaries.
- Before install, all guests had no Admiral RPMs, `admiral-apps` user, Admiral services or local candidate repository file. SELinux was Enforcing. The installer logs verify the eight seeded Python helper RPMs remained at their original NEVRAs on all three guests.

| OS | Seed SHA-256 | VM / IP / MAC | Kernel | Host key fingerprint | Boot ID before → after reboot |
|---|---|---|---|---|---|
| Rocky Linux 10.2 | `fd2456f930929c1ba9ae05b5a86548a0e9e436957fbcaf08d4583795915dc930` | `adm-r74-rocky-single` / `192.168.122.150` / `52:54:00:74:20:01` | `6.12.0-211.68.1.el10_2.x86_64` | `SHA256:4yVZJjSsBB0dClTHcq6B5cxEo1ohIPxxSJu4kRotl+o` | `3fe566a3-78d1-43d7-9252-6bedf31b632d` → `889b9279-9830-4ee8-892c-7f2b0d5400d0` |
| CentOS Stream 10 | `2b046acf36e4b775bac179ad2dd5c93cadc051ea7b6991842d0d0274a466b195` | `adm-r74-centos-single` / `192.168.122.151` / `52:54:00:74:20:02` | `6.12.0-278.el10.x86_64` | `SHA256:qrMP9UoORLvf/24ILzJE0laIxct/dKrVLDQC1zUngrk` | `033f390c-149b-4129-ab0b-fcb4cc8342b7` → `072ba0b0-03a5-4a29-aafa-32c08887b96c` |
| Fedora Rawhide 46 | `3199f6fd067a97e11bd29fb466c31edbf3727c95cb6e2c16ac1ed2434c4bb7ef` | `adm-r74-fedora-single` / `192.168.122.152` / `52:54:00:74:20:03` | `7.4.0-0.rc0.261023g734bef548a96.6.fc46.x86_64` | `SHA256:wEz6vh/9osF8PClGSNAI1Rv/FbHgVrEWSX958PaiguQ` | `68e447cf-21cb-4385-ade0-a59e6ff7b3d1` → `4ecd3950-5c6f-4246-92d4-192e88fcda78` |

## Installation and checks

| OS | Secure install elapsed | Ansible recap (`ok/changed/unreachable/failed/skipped`) |
|---|---:|---|
| Rocky Linux 10.2 | 380 s | `231 / 94 / 0 / 0 / 148` |
| CentOS Stream 10 | 422 s | `230 / 97 / 0 / 0 / 149` |
| Fedora Rawhide 46 | 424 s | `237 / 99 / 0 / 0 / 142` |

All three installer processes exited 0 and reported Admiral API/Harbor authentication reachable. The three lanes started together at `2026-10-24T19:44:04Z` and completed by `19:52:52Z`.

Each lane passed these stages:

1. Create a real workload, replay the same idempotency key, confirm same operation/instance, HTTP 200 and SQL marker, then deprovision and check resources.
2. Resize small → medium → small and confirm SQL marker continuity and HTTP 200 at each tier.
3. Create and checksum a local backup, reject restore while the workload is active, mutate then restore the marker, verify HTTP 200, delete the backup artifact and clean up. **This exercises the local backup backend; external S3/R2 was not tested here.**
4. Exercise pause/resume/stop/start/restart and stop/restart `admirald`; verify API/workload recovery and expected CLI failure while the service is stopped.
5. Reboot the actual guest, confirm changed boot ID, restore the workload, SQL marker and HTTP 200, then deprovision.
6. Verify no failed systemd units, exact six Release 74 NEVRAs, and empty rootless Podman container/pod/volume inventories.

The reboot probes preserved transitional observations rather than treating requests as completed operations. On all three OSes, API/runtime samples briefly reported unavailable or stopped while the host, database and containers were starting. The next sample converged to `running/healthy/available`, all three containers, HTTP 200 and the SQL marker. Rocky converged in three polls (~24 seconds); CentOS in three (~20 seconds); Fedora in three (~22 seconds). The temporary startup observations match the readiness behavior already tracked by [#236](https://github.com/admiral-project/admiral/issues/236); they were not a new reproducible failure in this run.

All six stages passed with zero failed stages on every OS. No new product defect was found. This result does not cover external S3/R2, stress/percentile performance, isolation negatives, disk/memory exhaustion, physical host failure or any Multi-Node scenario.

After the functional lanes, each guest's database audit found five Release 74 test instances, all `technical_status=deprovisioned` and `commercial_status=cancelled`, and 23/23 Release 74 operations in terminal `succeeded` state. Runtime resource cleanup was checked per instance during the functional lanes; the audit confirms the remaining database rows are terminal history, not active workloads or orphaned instances. All three terminal-state audits passed.

## Protected raw evidence

Raw logs are retained on the lab host with mode `0600` under:

`packaging/build/validation/rc5-r74/runtime/single-recheck-20261024T1935Z/`

Logs contain machine-specific operational data and are not committed. SHA-256 values:

| Artifact | SHA-256 |
|---|---|
| Rocky preflight | `7fe147b6c31771be1e660f1006398c478ad8e4e61129aaca760f12ec9b12a661` |
| CentOS preflight | `f11bf2da5740e4fcfb901cdc88b68f361a23bde69f050acb583a058d6429c6f7` |
| Fedora preflight | `075044279ee7c40beca10397cab6fdc38df4efc8ee1912cd77116e91a9a38737` |
| Rocky install | `eb3470c61a7fff1daec0e55ff7dc1de3f0fd214a967d144cc57d7130a9655192` |
| CentOS install | `f921b0a2f2d3cc567cf27ddcc017b7adae69a8baf69abb8d1c610b4303915d43` |
| Fedora install | `72960ab42439b2b875842e998fad587853b588b971400ebebddabb5f8d1f7720` |
| Parallel result | `f12da71678cd67736d3eccf0d94e0c5103c68f4fabb6127489c602f49723314e` |
| Rocky functional lane | `5b9009fc907442236a534474d3eb90dfa77946ae705cae0904083c71c90f8592` |
| CentOS functional lane | `e2e262d101caf48d3e150dbf77e1e2a517ac2a6225acd4ce66945092ca18a962` |
| Fedora functional lane | `700226027a310f5f0018a96e7680b96953471afb2759be37cfa9dd41aa181fdf` |
| Rocky terminal-state database audit | `c3e236e5ffb86d6fa27fd83ee737fb42bf7d309aac2c8ae10d7bec5a9d84ff1d` |
| CentOS terminal-state database audit | `c9c92ff95aabb10e51b0dbddcc729d6370d2bae91b016cfdfec9a544d955f6da` |
| Fedora terminal-state database audit | `13592e35a3c5752078c08fcff5133b65e4983b7d59d19632eff872045fbf8983` |
| Rocky initial launcher failure (before test execution) | `1261070075a88ac4b5cbddaa2279a6d891ee57a8dc3feedccba68763945f1a38` |
| CentOS initial launcher failure (before test execution) | `0ae2d4db449fbfe5d8fbec24cb51bc85a66257c5cb2fb396e006865701cc5fd8` |
| Fedora initial launcher failure (before test execution) | `373c3627692c3e39e9ca5c99160939516c256bc82b5d9f8f4c677a286da6522f` |
| Initial SSH preflight probe — Rocky | `d61286ed6faebc51eb25c38448db4180ec98710cd94dda7866690b62b8764b33` |
| Initial SSH preflight probe — CentOS | `406d59e046c1266f7ce0e0a7fa13d71a6d091fde2537346e5399e175d594826e` |
| Initial SSH preflight probe — Fedora | `bb3b4ba22b5a69ff1bf1d1d0cdf36825c58e04aa257eff64845283bac7d1bc0c` |

The failed preflight and launcher attempts remain separately retained and are not part of the PASS lane hashes. The prior Release 74 pass evidence remains in [`release74-single-node.md`](release74-single-node.md); this rerun supplements it with fresh guests after the launcher fix.
