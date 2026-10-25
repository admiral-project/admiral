# Release 75 CentOS Stream Multi-Node validation

> **Topology correction (2026-10-25):** This run used an admin/portal hub plus workers. Its observed results remain historical, but the run does not validate the required independent `--portal-node` and receives no Multi-Node release-gate credit.

**Corrected gate result: NOT TESTED for the required independent-portal Multi-Node cell.** The observed checks below passed only for the historical `--admin-portal-node` + workers topology; they are not a cell PASS.

This report preserves scoped historical observations for the old topology. It does not validate Harbor installed independently, its WireGuard API connection to Admirald, public routing to the portal guest, or customer workflows through that guest. No R75 Multi-Node gate credit is assigned.

## Candidate and source identity

The cell ran the exact `0.0.1rc5-75.el10` candidate prepared at root commit [`b88370d`](https://github.com/admiral-project/admiral/commit/b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953). Later root commits changed only validation harnesses and documentation; packaged component sources remained unchanged. Root package-preparation CI [40134458726](https://github.com/admiral-project/admiral/actions/runs/40134458726), harness CI [40137247001](https://github.com/admiral-project/admiral/actions/runs/40137247001), and evidence commit CI will be linked from the master tracker. The packaged source SHAs and component CI are:

| Component | Packaged source commit | CI run |
|---|---|---|
| `admiral-common` | `3faa349a5ba96b051104f1af5d043cb14bc8259d` | Root package CI above |
| `admirald` | `65afd58947c56edaef041737d7f775e7b4038182` | [40134043032](https://github.com/admiral-project/admirald/actions/runs/40134043032) |
| `admiral-fleet` | `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` | [40069777965](https://github.com/admiral-project/admiral-fleet/actions/runs/40069777965) |
| `admiralctl` | `fa2a65e866310bd82bea78859804b6c3aea7989a` | [40030034925](https://github.com/admiral-project/admiralctl/actions/runs/40030034925) |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | [39795263415](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415) |
| `admiral-harbor` | `dd39e9a74bf658ecf6fd6e9f8bd30b2ddf82d7db` | [39795262318](https://github.com/admiral-project/admiral-harbor/actions/runs/39795262318) |

The guest package set and hashes are the same candidate values recorded in the [R75 Single-Node report](release75-single-node-20261024.md):

| Package | NEVRA | SHA-256 |
|---|---|---|
| `admiral-common` | `admiral-common-0.0.1rc5-75.el10.noarch` | `c992fa847d6004226396914535de01e94b4afcebd0c9173d0a180ed832988153` |
| `admirald` | `admirald-0.0.1rc5-75.el10.x86_64` | `aac135efbf4509c07bb9220ea846931964e6aae26a2b0094ed7c33370dd03f2c` |
| `admiral-fleet` | `admiral-fleet-0.0.1rc5-75.el10.x86_64` | `ee1822feededecfbe783abe712070124dd115a8822a0db3f9356bfdd130f857d` |
| `admiralctl` | `admiralctl-0.0.1rc5-75.el10.x86_64` | `16b9c4ad72b1fdb5857c35e47e8057909031b0c88d76fc2b366a79bcf70ce21b` |
| `admiral-flagship` | `admiral-flagship-0.0.1rc5-75.el10.noarch` | `6723cede0125f7e98f9198a20e9ff2b64e5bb33cbc626652900658dc63f589e8` |
| `admiral-harbor` | `admiral-harbor-0.0.1rc5-75.el10.noarch` | `a26baf08d290040162440ae6f818fbc923da189bbb4ebc95f27938cc0575a178` |

Only signed native EL10 RPMs were installed with normal DNF dependency resolution. No cross-distribution packages, `--nodeps`, `--force`, or vendor overrides were used.

## Lab and preflight

The run started at **2026-10-24 23:11 UTC** and completed at **23:45 UTC**. Three fresh disposable libvirt guests ran together on the Rocky Linux 10.2 x86_64 audit host, configured with 8 GiB RAM and 4 GiB swap; each guest had 2 vCPU and 2 GiB RAM. All three overlays were cloned from the refreshed CentOS Stream 10 seed with SHA-256 `2b046acf36e4b775bac179ad2dd5c93cadc051ea7b6991842d0d0274a466b195`. The seed was not modified during this run. The guests reported kernel `6.12.0-278.el10.x86_64` and SELinux Enforcing.

| Role | Guest | NAT address | Test underlay NIC | WireGuard address |
|---|---|---:|---:|---:|
| Admin/control plane + Harbor | `adm-r75-centos-mn-hub` | `192.168.122.153` | `10.77.0.10` | `10.99.0.1` |
| Worker 1 | `adm-r75-centos-mn-w1` | `192.168.122.154` | `10.77.0.11` | `10.99.0.2` |
| Worker 2 | `adm-r75-centos-mn-w2` | `192.168.122.155` | `10.77.0.12` | `10.99.0.3` |

Each guest passed preflight: expected OS/architecture/network, SELinux Enforcing, no preinstalled Admiral RPMs or runtime users, and no candidate repository configured in the seed. The configured CentOS BaseOS, AppStream, CRB and Extras repositories had no available OS updates (`dnf check-update`); no full OS update was repeated during this run. EPEL and Admiral COPR supplied the expected Python helper RPMs. The candidate repo and signed RPMs were configured only in the lab after the preflight.

The hub installer completed with `ok=239 changed=106 failed=0 unreachable=0`; W1 with `ok=153 changed=49 failed=0 unreachable=0`; W2 with `ok=152 changed=52 failed=0 unreachable=0`. All six hub and two worker RPM NEVRAs matched Release 75 exactly. Both workers enrolled active, healthy and available with fresh heartbeats and WireGuard handshakes. Each worker reached the hub API over verified TLS and received HTTP 401 without credentials; lateral worker access to TCP 9099 was denied. Fleet, firewalld, WireGuard and SELinux checks passed. Initial rootless workload inventories were empty.

## Executed checks

| Test ID | Expected behavior | Observed result |
|---|---|---|
| `R75-CENTOS-MN-ENROLL-01` | Three real guests install the signed exact candidate, securely enroll both workers, and converge healthy/available with empty initial runtime | **PASS.** Installer recaps had zero failures/unreachable hosts; exact package set, heartbeats, services, SELinux, firewall and WireGuard passed. |
| `R75-CENTOS-MN-AUTH-ISOLATION-01` | Trusted TLS path reaches hub; anonymous API access and lateral worker access are denied | **PASS.** Both workers received HTTP 401 from the hub API without credentials; worker-to-worker TCP 9099 was denied. This is a scoped network/auth check, not exhaustive isolation validation. |
| `R75-CENTOS-MN-PLACEMENT-01` | Place a workload on W1 and W2 in turn; replay the idempotency key; verify assignment, tier, SQL, HTTP and cleanup | **PASS.** Both placements landed on the requested worker, reported the 1 GiB tier, retained a PostgreSQL marker, returned HTTP 200 over WireGuard, and same-key replay returned the original operation/instance. Deprovision left no matching containers, pods, volumes, units or files. |
| `R75-CENTOS-MN-CONCURRENT-IDEMPOTENCY-01` | Three synchronized clients with the same request key yield one instance and one operation | **PASS, scoped.** All three clients returned operation `op_985d5ba8a3f4a38c`, instance `inst_41034af8938e918f`, and task `task_f65681ca9e18ea4d` on W1; cleanup passed. |
| `R75-CENTOS-MN-UPDATE-DELETE-01` | Concurrent resize and deprovision settle to a consistent terminal state and clean runtime resources | **PASS.** Both operations reported succeeded; after the settle interval the instance was deprovisioned and runtime inventory was empty. |
| `R75-CENTOS-MN-WORKER-REBOOT-01` | Reboot W1 with a live workload; verify new boot ID, service/health recovery, HTTP and SQL persistence | **PASS.** Boot ID changed; workload became healthy/available by poll 3, HTTP returned 200, SQL marker persisted, and cleanup succeeded. |
| `R75-CENTOS-MN-PARTITION-01` | Interrupt W2 WireGuard connectivity; observe unavailable/offline state; restore route and verify convergence | **PASS.** The workload became unavailable/stale; W2 transitioned offline/degraded at poll 12. After the armed route restoration, W2 and its workload returned active/healthy/available by rejoin poll 2; cleanup succeeded. |
| `R75-CENTOS-MN-HUB-REBOOT-01` | Reboot hub with a live W1 workload; verify services, routes, handshakes, worker heartbeats, SQL and HTTP recover | **PASS.** Hub boot ID changed, PostgreSQL/Admirald/WireGuard were active, both worker routes and fresh handshakes returned, and the workload recovered with HTTP 200 and its SQL marker by recovery poll 2. The first API sample still showed pre-reboot heartbeats and temporary unavailable state; convergence completed inside the script's four-minute deadline. Cleanup succeeded. |
| `R75-CENTOS-MN-NODE-REMOVE-01` | Refuse removal of an active worker, then remove it only after deprovision; verify record/route/resource cleanup | **PASS.** Active W2 removal was rejected without interrupting HTTP 200. After deprovision, idle W2 removal succeeded; W2 disappeared from Admiral inventory and the hub peer set, with no rootless containers, pods or volumes. |
| `R75-CENTOS-MN-POSTRUN-01` | Verify no failed system/user units or workload resources, exact candidate remains, and final node/peer inventory matches | **PASS.** All three guests had no failed system units; W1/W2 had no failed user units or rootless workloads. The hub retained only itself and W1, with W2's WireGuard route absent. All three guests were shut down and destroyed after capture; the seed remains. |

## Evidence and reproduction

Private raw evidence is retained locally under `packaging/build/validation/rc5-r75/runtime/multi/centos-run-20261024T231123Z/`; directories are mode `0700`, files mode `0600`. The 207-entry manifest `RAW-EVIDENCE.SHA256` has SHA-256 `96436bd2c532d831a3298386df7066f4ea72122d3e7f9f754e1914fc37b29129`. It includes failed preliminary harness attempts and the corrected passing reruns; no raw logs or secrets are published in this report.

Reproduction scripts are in [`scripts/r75/`](../scripts/r75/): CentOS-specific placement, concurrent same-key idempotency, update/delete race, worker reboot, WireGuard partition/rejoin, hub reboot, node removal, and final postrun audit. Each script records its output and hashes in the private run directory.

Two retained preliminary failures were test-environment/harness issues, not product failures: the first SSH attempt occurred while the new guest was still booting; and the first final-postrun run used a checker regex that omitted two package names, so its candidate-count assertion failed. The corrected checker was rerun against all guests and passed; both attempts remain in the raw evidence manifest. During hub recovery the first health sample also exposed the expected transient stale state, which converged on the second sample. No new product defect was confirmed in this cell.

## Decision and limits

These checks do not complete the required Release 75 Multi-Node cell for **CentOS Stream 10 x86_64** because Harbor was co-hosted on the admin node. Independent portal installation, registration, private API connectivity, public routing and customer workflows remain **NOT TESTED**. This report has no Multi-Node release-gate credit. PostgreSQL outage and in-flight task interruption, exhaustive security/isolation, memory/disk exhaustion, broad stress/performance percentiles, external S3/volume backup and restore, consensus, and automatic workload migration also remain outside the executed checks; production readiness remains **NOT VALIDATED**.
