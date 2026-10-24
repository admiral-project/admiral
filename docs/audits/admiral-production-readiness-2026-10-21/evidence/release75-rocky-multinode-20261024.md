# Release 75 Rocky Linux Multi-Node validation

**Result: PASS for the Release 75 Rocky Linux 10 x86_64 Multi-Node functional cell.**

**R75 functional matrix after this run: 4/6 PASS.** The three Single-Node cells and Rocky Multi-Node pass; CentOS Stream and Fedora Rawhide Multi-Node are NOT TESTED. This is functional release-gate evidence, not a complete production-readiness certification.

## Candidate and source identity

The cell ran `0.0.1rc5-75.el10` on the exact Release 75 RPM candidate prepared at root commit [`b88370d`](https://github.com/admiral-project/admiral/commit/b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953). Later root commits changed the validation harness and documentation, not the six packaged component sources. The root package-preparation CI run [40134458726](https://github.com/admiral-project/admiral/actions/runs/40134458726), harness CI [40137247001](https://github.com/admiral-project/admiral/actions/runs/40137247001), and evidence commit CI will be recorded on the master issue. Component source commits and their CI runs:

| Component | Packaged source commit | CI run |
|---|---|---|
| `admiral-common` | `3faa349a5ba96b051104f1af5d043cb14bc8259d` | Root package CI above |
| `admirald` | `65afd58947c56edaef041737d7f775e7b4038182` | [40134043032](https://github.com/admiral-project/admirald/actions/runs/40134043032) |
| `admiral-fleet` | `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` | [40069777965](https://github.com/admiral-project/admiral-fleet/actions/runs/40069777965) |
| `admiralctl` | `fa2a65e866310bd82bea78859804b6c3aea7989a` | [40030034925](https://github.com/admiral-project/admiralctl/actions/runs/40030034925) |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | [39795263415](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415) |
| `admiral-harbor` | `dd39e9a74bf658ecf6fd6e9f8bd30b2ddf82d7db` | [39795262318](https://github.com/admiral-project/admiral-harbor/actions/runs/39795262318) |

The guest DNF transactions installed only the native signed EL10 Release 75 RPMs, with ordinary dependency resolution. No cross-distribution packages, `--nodeps`, `--force`, or vendor overrides were used. The six package hashes are the same values recorded in the [R75 Single-Node report](release75-single-node-20261024.md):

| Package | NEVRA | SHA-256 |
|---|---|---|
| `admiral-common` | `admiral-common-0.0.1rc5-75.el10.noarch` | `c992fa847d6004226396914535de01e94b4afcebd0c9173d0a180ed832988153` |
| `admirald` | `admirald-0.0.1rc5-75.el10.x86_64` | `aac135efbf4509c07bb9220ea846931964e6aae26a2b0094ed7c33370dd03f2c` |
| `admiral-fleet` | `admiral-fleet-0.0.1rc5-75.el10.x86_64` | `ee1822feededecfbe783abe712070124dd115a8822a0db3f9356bfdd130f857d` |
| `admiralctl` | `admiralctl-0.0.1rc5-75.el10.x86_64` | `16b9c4ad72b1fdb5857c35e47e8057909031b0c88d76fc2b366a79bcf70ce21b` |
| `admiral-flagship` | `admiral-flagship-0.0.1rc5-75.el10.noarch` | `6723cede0125f7e98f9198a20e9ff2b64e5bb33cbc626652900658dc63f589e8` |
| `admiral-harbor` | `admiral-harbor-0.0.1rc5-75.el10.noarch` | `a26baf08d290040162440ae6f818fbc923da189bbb4ebc95f27938cc0575a178` |

## Lab and preflight

Run window: **2026-10-24 22:38:10–23:06:47 UTC**. The host is Rocky Linux 10 x86_64 with 8 GiB RAM and 4 GiB swap. Three disposable KVM VMs ran together, each configured for 2 vCPU and 2 GiB RAM. All guest overlays came from the refreshed Rocky seed with SHA-256 `fd2456f930929c1ba9ae05b5a86548a0e9e436957fbcaf08d4583795915dc930`; they reported Rocky Linux 10.2 x86_64 and kernel `6.12.0-211.68.1.el10_2.x86_64`. The seed was not updated during this run.

| Role | Guest | Libvirt NAT address | Test underlay NIC | WireGuard address |
|---|---|---:|---:|---:|
| Admin/control plane + Harbor | `adm-r75-rocky-mn-hub` | `192.168.122.153` | `10.77.0.10` | `10.99.0.1` |
| Worker 1 | `adm-r75-rocky-mn-w1` | `192.168.122.154` | `10.77.0.11` | `10.99.0.2` |
| Worker 2 | `adm-r75-rocky-mn-w2` | `192.168.122.155` | `10.77.0.12` | `10.99.0.3` |

The per-VM preflight checked the OS/kernel/architecture, SELinux Enforcing, the assigned private NIC address, expected Python helper RPMs, and absence of Admiral RPMs, Admiral users, and a candidate-repository file before install. All three passed. The candidate repository was configured in the lab after preflight. The hub secure installer completed with `ok=240 changed=103 failed=0 unreachable=0`; each worker installer completed with `ok=153 changed=49 failed=0 unreachable=0`. All six exact hub NEVRAs and both worker NEVRAs were checked after installation.

Both workers registered as active, healthy, and available; their Fleet heartbeat and metrics converged. WireGuard handshakes succeeded. The bootstrap helper verified that its temporary worker SSH key was rejected after enrollment while the pinned validator key still worked. SELinux was Enforcing; `admiral-fleet`, firewalld, and WireGuard were active on each worker. Initial workload inventories were empty.

## Executed checks

| Test ID | Method and expected result | Observed result |
|---|---|---|
| `R75-ROCKY-MN-ENROLL-01` | Three real VMs; signed candidate install; secure worker registration; active/healthy/available state, fresh heartbeats, WireGuard and service checks | **PASS.** Hub and both workers reported active/healthy/available before workload tests. |
| `R75-ROCKY-MN-AUTH-ISOLATION-01` | Verify TLS trust and reachability to hub from each worker, reject anonymous API access, and deny lateral worker TCP access | **PASS.** Hub API returned HTTP 401 without credentials over its trusted TLS certificate on both workers. TCP to the other worker on port 9099 was denied. A preliminary ICMP ping to the hub timed out under the host firewall; ICMP is not an acceptance criterion, and the attempt is retained. |
| `R75-ROCKY-MN-PLACEMENT-01` | Apply a real app, place it on W1 and W2 in turn, replay each idempotency key, verify quota/SQL/HTTP and cleanup | **PASS.** Both instances landed on the requested worker, were healthy/available, retained the 1 GiB tier and a PostgreSQL marker, and returned HTTP 200 over WireGuard. Each replay returned the original operation and instance. Deprovision left no matching containers, pods, volumes, units, or files. |
| `R75-ROCKY-MN-CONCURRENT-IDEMPOTENCY-01` | Three synchronized clients issue the same provision operation and key | **PASS.** All clients converged on one operation and instance, assigned to W2; the harness returned `PASS_SCOPED`. |
| `R75-ROCKY-MN-UPDATE-DELETE-01` | Race a resize against forced deprovision; check terminal state and runtime cleanup | **PASS.** Both operations reported succeeded. The instance remained deprovisioned after a 30-second settle check; runtime inventory was empty. |
| `R75-ROCKY-MN-WORKER-REBOOT-01` | Reboot W1 with a live workload; verify new boot ID, health recovery, HTTP and SQL persistence | **PASS.** W1 and the instance recovered; the instance returned to running/healthy/available by poll 2. HTTP remained 200 and the SQL marker survived. Cleanup succeeded. |
| `R75-ROCKY-MN-PARTITION-01` | Temporarily remove W2's WireGuard route, observe outage, restore, and verify recovery | **PASS.** The workload became unavailable/stale, W2 transitioned to offline/degraded after about 147 seconds, and W2 returned active/healthy/available by rejoin poll 2. HTTP 200 and the PostgreSQL marker survived. A timed automatic route restoration was armed before the fault. Cleanup succeeded. |
| `R75-ROCKY-MN-HUB-REBOOT-01` | Reboot the actual hub with a live W1 workload; verify services, routes, handshakes and data recovery | **PASS.** Hub boot ID changed; PostgreSQL, Admirald and WireGuard became active; both worker routes and fresh handshakes returned. The workload became healthy/available by recovery poll 1, returned HTTP 200 and retained its SQL marker. Cleanup succeeded. |
| `R75-ROCKY-MN-NODE-REMOVE-01` | Refuse active-worker removal; then deprovision, remove idle W2 and verify inventory/route cleanup | **PASS.** Removal with an active instance was refused and HTTP remained 200. After deprovision, W2 removal succeeded; it disappeared from Admiral inventory and its hub route was removed. The worker had no rootless containers, pods, or volumes. |
| `R75-ROCKY-MN-POSTRUN-01` | Check systemd failures, remaining workload resources and final cluster inventory | **PASS.** All three VMs had zero failed units; W1/W2 rootless container, pod, and volume inventories were empty. Final inventory contained only the hub and W1; W2's route was absent. |

The raw test evidence, including unsuccessful preliminary harness attempts, remains in the ignored local directory `packaging/build/validation/rc5-r75/runtime/multi/rocky-run-20261024T224000Z/`, with directories mode `0700` and files mode `0600`. Its 200-file checksum manifest is `RAW-EVIDENCE.SHA256`, whose SHA-256 is `7bfcf54f859e2caa1df5eca8fa0758087ee1e24d206cff7c551a4b158f15b93d`. The initial postrun helper attempts failed before state inspection because `runuser` inherited the restricted `/home/validator` working directory and an empty command result was counted as one line; the corrected inspection changed to `/tmp` and passed. Those attempts remain in the manifest but are not counted as product failures or PASS checks.

Reproduction scripts, adapted to the R75 candidate and node IDs, are in [`scripts/r75/`](../scripts/r75/): placement, concurrent idempotency, concurrent update/delete, worker reboot, WireGuard partition/rejoin, hub reboot, and node removal. The scripts invoke the supported CLI and real VM/runtime paths; R74 run results were not reused as R75 evidence.

## Decision and limits

This satisfies the Release 75 functional Multi-Node checklist for **Rocky Linux 10 x86_64**. No new product defect was confirmed in this cell. All three Rocky guests were shut down after evidence collection; the host then had about 6.1 GiB memory available, 2.9 GiB swap free, and 42 GiB disk free.

This result does not validate CentOS Stream or Fedora Multi-Node. It also does not establish distributed consensus, automatic workload migration, full authorization/isolation guarantees, resource exhaustion behavior, broad stress/performance percentiles, or external S3 backup/restore behavior in Multi-Node mode. Those remain NOT TESTED; do not interpret this functional cell as a full production-readiness certification.
