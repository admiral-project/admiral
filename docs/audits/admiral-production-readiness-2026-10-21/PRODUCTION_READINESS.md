# Production readiness decision

Audit ID: `ADM-AUDIT-2026-10-21`<br>
Audit began: 2026-10-21 UTC<br>
Release 75 functional closeout: [RELEASE75_VALIDATION_CLOSURE.md](RELEASE75_VALIDATION_CLOSURE.md).
> **Topology and scope correction — 2026-10-25:** The required Multi-Node shape is `--admin-node` + `--worker-node` + independent `--portal-node`. R75 used `--admin-portal-node` plus workers, so its three Multi-Node cells are invalid for this gate; independent Harbor is not validated. The active release matrix is Fedora Rawhide, Rocky Linux 10, AlmaLinux 10 and CentOS Stream 10, each Single-Node and Multi-Node. RC6 currently has **0/8 complete cells**. Production readiness remains NOT VALIDATED.

Production readiness is **NOT VALIDATED**. The functional release gate is narrower than the full production audit and cannot establish production security, fault-tolerance, scalability or performance.

## Current decision by topology

| Topology | Decision | Basis |
| --- | --- | --- |
| Single-Node | **NOT VALIDATED** | RC6 has not yet been run. R75's three functional cells are historical and candidate-specific; broader isolation/security negatives, resource-exhaustion behavior, stress and controlled performance also remain incomplete. |
| Multi-Node | **NOT VALIDATED** | RC6 has not yet been run. R75's `admin-portal + workers` topology did not validate the required independent Harbor portal node. |

Neither topology is READY or CONDITIONALLY READY on current evidence. Exact-commit CI and scoped scenarios do not substitute for a complete matrix cell. No production system was touched.

## Historical Release 42 decision (superseded)

| Topology | Decision | Basis |
| --- | --- | --- |
| Single-Node | **NOT READY** | Scoped install/lifecycle evidence exists on all four OS targets, but full coverage is incomplete. Two open HIGH findings affect this mode: production config accepts shipped `__REQUIRED__` values for the secrets encryption and Fleet callback keys (`ADM-F-007` / #212), and a failed declared workload service can still produce `succeeded` provisioning and `healthy` instance state (`ADM-F-006` / #227). Repeated provisioning created distinct instances on all four distributions (`ADM-F-001`). Harbor rendered an unsafe percent-encoded script URL on Rocky and Fedora (`ADM-F-004`, MEDIUM). Concurrent update/delete, isolation negatives, stress/fault coverage, controlled performance and full matrix remain outstanding. HTTP/2 network exposure in this mode was not established. |
| Multi-Node | **NOT READY** | AlmaLinux now has a scoped three-node install, placement, worker outage/rejoin, hub peer-loss on power-cycle (`ADM-F-005`), local PostgreSQL backup/restore, failed-service false health (`ADM-F-006`), and false-success deprovision with remaining Podman resources (`ADM-F-008`). Rocky and Fedora placed workloads on both workers and preserved SQL markers across worker reboots; their hubs also lost peers on startup. CentOS Stream has a scoped three-guest install, placement, local PostgreSQL backup/restore and cleanup; it reproduced hub restart peer loss, false healthy state with a failed DB (`ADM-F-006`), duplicate same-customer provisions across workers (`ADM-F-001`), and stale healthy instance state after worker loss (`ADM-F-002` / #208). Five open HIGH findings block readiness: reachable Go HTTP/2 advisories (`ADM-F-003`), hub peer-recovery defect (`ADM-F-005`), failed-service status (`ADM-F-006`), placeholder secret acceptance (`ADM-F-007` / #212), and false-success cleanup with residual resources (`ADM-F-008` / #228). Rocky, AlmaLinux and CentOS Stream outages left assigned instances reporting stale `running/healthy` after workers were marked offline. External S3 and volume backup/restore, database outage, latency injection, task replay/lease behavior, conflicting updates/deletes, full security negatives, performance and complete distribution coverage remain open. |

The NOT READY statuses in this historical table applied to Release 42 runtime evidence. They do not validate or determine the next candidate status. Release 45–47 observations are candidate-specific and do not carry forward.

## Historical Release 46 candidate identity and host

Release 46 is historical. Its source pins and six RPMs were built at package-preparation commit `7223561646b60d3c24e8bfb257d544a5eb6dea04`; its targeted guest observations are retained below and in `evidence/`, but do not count for the rebuilt candidate. Rocky Linux 10 is back in the active scope; its Release 46 dependency-resolution failure and workaround remain historical evidence only.

The Release 46 reference check, exact NEVRAs, hashes and targeted observations are recorded in `evidence/release46-candidate.md` and `evidence/release46-rpm-sha256.txt`. The lab host is Rocky Linux 10.2 x86_64, 4 vCPU, 8 GiB RAM, 4 GiB swap and KVM/QEMU 10.1/libvirt 11.10. Guest tests use isolated libvirt VMs. At that time the target was four distributions in both topologies; this historical scope does not describe the Release 74 gate.

## What would change this decision

R75's historical reports recorded six functional PASS results, but the three Multi-Node runs co-hosted Harbor with the admin service. They therefore do not validate the required independent portal topology and receive no Multi-Node gate credit. RC6 must rerun all cells on one exact candidate, including Harbor on a separate `--portal-node`. A separate production-readiness assessment still needs reproducible security/isolation negatives, broader fault injection, resource-pressure tests, concurrency and performance measurements, with scope and operating assumptions documented. Any new source/RPM fix requires a new candidate and invalidates its runtime evidence.

## Current answer to the audit question

The broader production-readiness question remains **NOT VALIDATED**. R75 has three historical Single-Node passes; its three Multi-Node results used the wrong topology and receive no gate credit. RC6 has **0/8 complete cells**. Even a complete functional matrix would not establish all security, isolation, fault-tolerance, resource-exhaustion or performance properties required for a production decision. No production-readiness claim is made.
