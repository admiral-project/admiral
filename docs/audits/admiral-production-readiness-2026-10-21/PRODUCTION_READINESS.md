# Production readiness decision

Audit ID: `ADM-AUDIT-2026-10-21`<br>
Audit began: 2026-10-21 UTC<br>
> **Active scope — 2026-10-24:** Four x86_64 operating systems (Fedora Rawhide, Rocky Linux 10, AlmaLinux 10 and CentOS Stream 10), each Single-Node and Multi-Node. The prior R73 dependency set had **4/8 PASS, 3/8 PARTIAL, 1/8 NOT TESTED**; all those results are historical after the Python helper RPM refresh. The active refreshed set is **0/8** pending COPR rebuilds and a fresh coordinated release run. Local native EL10 and Fedora Rawhide SQLAlchemy `%check` builds passed, but they do not prove COPR success or any runtime cell. The audit also has a broader scope than the functional release gate and does not establish comprehensive security, isolation, resilience, scalability or performance.

Production readiness is **NOT VALIDATED**. The functional release gate is narrower than the full production audit and cannot establish production security, fault-tolerance, scalability or performance.

## Current decision by topology

| Topology | Decision | Basis |
| --- | --- | --- |
| Single-Node | **NOT VALIDATED** | The four prior R73 cells passed their functional checklist, but this refreshed Python dependency set has no runtime cell evidence yet. Broader isolation/security negatives, resource-exhaustion behavior, stress and performance also remain incomplete. |
| Multi-Node | **NOT VALIDATED** | This refreshed dependency set has no runtime cell evidence yet. Prior R73 scoped runs are historical; none completed a full Multi-Node cell. Fedora was untested, and database outage, in-flight tasks, comprehensive isolation, resource exhaustion and performance remain incomplete. |

Neither topology is READY or CONDITIONALLY READY on current evidence. Exact-commit CI and scoped scenarios do not substitute for a complete matrix cell. No production system was touched.

## Historical Release 42 decision (superseded)

| Topology | Decision | Basis |
| --- | --- | --- |
| Single-Node | **NOT READY** | Scoped install/lifecycle evidence exists on all four OS targets, but full coverage is incomplete. Two open HIGH findings affect this mode: production config accepts shipped `__REQUIRED__` values for the secrets encryption and Fleet callback keys (`ADM-F-007` / #212), and a failed declared workload service can still produce `succeeded` provisioning and `healthy` instance state (`ADM-F-006` / #227). Repeated provisioning created distinct instances on all four distributions (`ADM-F-001`). Harbor rendered an unsafe percent-encoded script URL on Rocky and Fedora (`ADM-F-004`, MEDIUM). Concurrent update/delete, isolation negatives, stress/fault coverage, controlled performance and full matrix remain outstanding. HTTP/2 network exposure in this mode was not established. |
| Multi-Node | **NOT READY** | AlmaLinux now has a scoped three-node install, placement, worker outage/rejoin, hub peer-loss on power-cycle (`ADM-F-005`), local PostgreSQL backup/restore, failed-service false health (`ADM-F-006`), and false-success deprovision with remaining Podman resources (`ADM-F-008`). Rocky and Fedora placed workloads on both workers and preserved SQL markers across worker reboots; their hubs also lost peers on startup. CentOS Stream has a scoped three-guest install, placement, local PostgreSQL backup/restore and cleanup; it reproduced hub restart peer loss, false healthy state with a failed DB (`ADM-F-006`), duplicate same-customer provisions across workers (`ADM-F-001`), and stale healthy instance state after worker loss (`ADM-F-002` / #208). Five open HIGH findings block readiness: reachable Go HTTP/2 advisories (`ADM-F-003`), hub peer-recovery defect (`ADM-F-005`), failed-service status (`ADM-F-006`), placeholder secret acceptance (`ADM-F-007` / #212), and false-success cleanup with residual resources (`ADM-F-008` / #228). Rocky, AlmaLinux and CentOS Stream outages left assigned instances reporting stale `running/healthy` after workers were marked offline. External S3 and volume backup/restore, database outage, latency injection, task replay/lease behavior, conflicting updates/deletes, full security negatives, performance and complete distribution coverage remain open. |

The NOT READY statuses in this historical table applied to Release 42 runtime evidence. They do not validate or determine the next candidate status. Release 45–47 observations are candidate-specific and do not carry forward.

## Historical Release 46 candidate identity and host

Release 46 is historical. Its source pins and six RPMs were built at package-preparation commit `7223561646b60d3c24e8bfb257d544a5eb6dea04`; its targeted guest observations are retained below and in `evidence/`, but do not count for the rebuilt candidate. Rocky Linux 10 is back in the active scope; its Release 46 dependency-resolution failure and workaround remain historical evidence only.

The Release 46 reference check, exact NEVRAs, hashes and targeted observations are recorded in `evidence/release46-candidate.md` and `evidence/release46-rpm-sha256.txt`. The lab host is Rocky Linux 10.2 x86_64, 4 vCPU, 8 GiB RAM, 4 GiB swap and KVM/QEMU 10.1/libvirt 11.10. Guest tests use isolated libvirt VMs. The active target is Fedora Rawhide, Rocky Linux 10, AlmaLinux 10 and CentOS Stream 10 x86_64 in Single-Node and Multi-Node (eight cells).

## What would change this decision

The remaining Release 73 functional cells in [issue #200](https://github.com/admiral-project/admiral/issues/200) must pass for all four supported x86_64 platforms in both topologies. A separate production-readiness assessment still needs reproducible security/isolation negatives, broader fault injection, resource-pressure tests, concurrency and performance measurements, with scope and operating assumptions documented. Any new source/RPM fix requires a new candidate and invalidates its runtime evidence.

## Current answer to the audit question

The broader production-readiness question remains **NOT VALIDATED**. The active refreshed package set has **0/8** runtime cells executed; the prior R73 dependency set's 4/8 result is historical and carries no credit. Even a complete functional matrix does not establish all security, isolation, fault-tolerance, resource-exhaustion or performance properties required for a production decision. No production-readiness claim is made.
