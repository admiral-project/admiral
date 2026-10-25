# Release 75 functional validation — closeout

Audit ID: `ADM-AUDIT-2026-10-21`<br>
Scope: Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide x86_64; Single-Node and Multi-Node.<br>
Result: **6/6 functional cells PASS.**

This closes the Release 75 functional E2E gate. It does not close the broader production-readiness audit: see [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) for the remaining security, resilience, and performance work. No production systems were used.

## Candidate identity

All six cells used the unchanged `0.0.1rc5-75` RPM candidate prepared at root commit [`b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953`](https://github.com/admiral-project/admiral/commit/b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953). The six packaged component source SHAs and the complete native `.el10` and `.fc46` RPM NEVRA/SHA-256 inventory are in the [R75 Single-Node candidate report](evidence/release75-single-node-20261024.md). EL10 packages were installed only on Rocky/CentOS; Fedora used its native `.fc46` set. No cross-distribution RPMs, `--nodeps`, forced installs, or vendor overrides were used.

| Component | Packaged source SHA | CI |
|---|---|---|
| `admiral-common` | `3faa349a5ba96b051104f1af5d043cb14bc8259d` | Root package CI [40134458726](https://github.com/admiral-project/admiral/actions/runs/40134458726) |
| `admirald` | `65afd58947c56edaef041737d7f775e7b4038182` | [40134043032](https://github.com/admiral-project/admirald/actions/runs/40134043032) |
| `admiral-fleet` | `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` | [40069777965](https://github.com/admiral-project/admiral-fleet/actions/runs/40069777965) |
| `admiralctl` | `fa2a65e866310bd82bea78859804b6c3aea7989a` | [40030034925](https://github.com/admiral-project/admiralctl/actions/runs/40030034925) |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | [39795263415](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415) |
| `admiral-harbor` | `dd39e9a74bf658ecf6fd6e9f8bd30b2ddf82d7db` | [39795262318](https://github.com/admiral-project/admiral-harbor/actions/runs/39795262318) |

## Cell results and evidence

| OS / topology | Result | Run evidence | Private raw manifest SHA-256 |
|---|---:|---|---|
| Rocky Linux 10 x86_64 / Single-Node | **PASS** | [Three-OS coordinated Single-Node report](evidence/release75-single-node-20261024.md) | `fc7b8b88b4a74e103907bc9ddb5ab87a9ac9d7baf25d795a268bf463c69b5f66` |
| Rocky Linux 10 x86_64 / Multi-Node | **PASS** | [Rocky Multi-Node report](evidence/release75-rocky-multinode-20261024.md) | `7bfcf54f859e2caa1df5eca8fa0758087ee1e24d206cff7c551a4b158f15b93d` |
| CentOS Stream 10 x86_64 / Single-Node | **PASS** | [Three-OS coordinated Single-Node report](evidence/release75-single-node-20261024.md) | `fc7b8b88b4a74e103907bc9ddb5ab87a9ac9d7baf25d795a268bf463c69b5f66` |
| CentOS Stream 10 x86_64 / Multi-Node | **PASS** | [CentOS Stream Multi-Node report](evidence/release75-centos-multinode-20261024.md) | `96436bd2c532d831a3298386df7066f4ea72122d3e7f9f754e1914fc37b29129` |
| Fedora Rawhide 46 x86_64 / Single-Node | **PASS** | [Three-OS coordinated Single-Node report](evidence/release75-single-node-20261024.md) | `fc7b8b88b4a74e103907bc9ddb5ab87a9ac9d7baf25d795a268bf463c69b5f66` |
| Fedora Rawhide 46 x86_64 / Multi-Node | **PASS** | [Fedora Multi-Node report](evidence/release75-fedora-multinode-20261025.md) | `18eb11d50f7882f0afb7fa3da819da15eb90041dc3583adeeb1d47c374fac6ac` |

All functional cells used fresh disposable VMs and the exact unchanged R75 packages. The Single-Node run executed all three OS lanes together. Each Multi-Node cell used three real VMs: one hub/admin node and two workers. The reports contain the OS/kernel/architecture, seed hashes, VM roles, exact RPM identities, procedures, expected and observed results, run timings, retained harness attempts, limits, and reproduction instructions.

The tracked reports and scripts are committed. Raw run logs are intentionally kept in the ignored, access-restricted local validation tree because they can contain operational data. The manifest fingerprints above identify those retained files; each active run manifest and the corrected Fedora seed manifest were verified. The earlier invalidated Single-Node preliminary attempt remains preserved and is not included in any PASS claim.

## Checks exercised

Single-Node passed secure installation and service checks, workload provision/idempotency, resize and data continuity, local backup/restore and invalid-state rejection, service lifecycle, actual guest reboot with PostgreSQL marker persistence, and final operation/resource cleanup.

Each Multi-Node cell passed secure enrollment and worker health, explicit placement on both workers, same-key replay, a three-client duplicate-provision race, concurrent resize/deprovision, worker reboot, WireGuard partition/rejoin, hub reboot with a live workload, active-node removal refusal, idle-node removal, and postrun cleanup. Scoped anonymous API rejection and lateral worker TCP denial were recorded. These checks do not establish exhaustive security/isolation or high-availability guarantees.

## Reproduction scripts

### Single-Node

- [run-single-release-pass.sh](scripts/r75/run-single-release-pass.sh) — coordinated three-OS runner.
- [run-single-pass.sh](scripts/r75/run-single-pass.sh) and [run-single-lane.sh](scripts/r75/run-single-lane.sh) — orchestration and per-OS lane.
- [single-node-lifecycle.sh](scripts/r75/single-node-lifecycle.sh), [single-resize-functional.sh](scripts/r75/single-resize-functional.sh), [single-backup-restore.sh](scripts/r75/single-backup-restore.sh), [single-control-plane-lifecycle.sh](scripts/r75/single-control-plane-lifecycle.sh), and [single-node-postcheck.sh](scripts/r75/single-node-postcheck.sh) — functional stages and cleanup.

### Multi-Node

The following per-OS runners reproduce placement/replay, concurrent idempotency, update/delete races, worker reboot, partition/rejoin, hub reboot, node removal, and (where present) postrun checks:

- Rocky Linux 10: [placement](scripts/r75/r75-rocky-multinode-placement.sh), [concurrent idempotency](scripts/r75/r75-rocky-multinode-concurrent-idempotency.py), [update/delete](scripts/r75/r75-rocky-multinode-concurrent-update-delete.sh), [worker reboot](scripts/r75/r75-rocky-multinode-worker-reboot.sh), [partition/rejoin](scripts/r75/r75-rocky-multinode-partition.sh), [hub reboot](scripts/r75/r75-rocky-multinode-hub-reboot.sh), [node removal](scripts/r75/r75-rocky-multinode-node-removal.sh).
- CentOS Stream 10: [placement](scripts/r75/r75-centos-multinode-placement.sh), [concurrent idempotency](scripts/r75/r75-centos-multinode-concurrent-idempotency.py), [update/delete](scripts/r75/r75-centos-multinode-concurrent-update-delete.sh), [worker reboot](scripts/r75/r75-centos-multinode-worker-reboot.sh), [partition/rejoin](scripts/r75/r75-centos-multinode-partition.sh), [hub reboot](scripts/r75/r75-centos-multinode-hub-reboot.sh), [node removal](scripts/r75/r75-centos-multinode-node-removal.sh), [postrun](scripts/r75/r75-centos-multinode-postrun.sh).
- Fedora Rawhide: [placement](scripts/r75/r75-fedora-multinode-placement.sh), [concurrent idempotency](scripts/r75/r75-fedora-multinode-concurrent-idempotency.py), [update/delete](scripts/r75/r75-fedora-multinode-concurrent-update-delete.sh), [worker reboot](scripts/r75/r75-fedora-multinode-worker-reboot.sh), [partition/rejoin](scripts/r75/r75-fedora-multinode-partition.sh), [hub reboot](scripts/r75/r75-fedora-multinode-hub-reboot.sh), [node removal](scripts/r75/r75-fedora-multinode-node-removal.sh), [postrun](scripts/r75/r75-fedora-multinode-postrun.sh).

### Lab preparation and installation support

- [create_seed_os.sh](scripts/create_seed_os.sh), [create-audit-vm.sh](scripts/create-audit-vm.sh), [prepare-audit-cloud-init.py](scripts/prepare-audit-cloud-init.py), [prepare-audit-seed-guest.sh](scripts/prepare-audit-seed-guest.sh), and [cleanup-audit-vm.sh](scripts/cleanup-audit-vm.sh) — updated seeds, disposable guests, pinned host keys, and safe VM cleanup.
- [publish-candidate-repo.sh](scripts/publish-candidate-repo.sh), [sign-local-validation-repo.sh](scripts/sign-local-validation-repo.sh), [install-single-node-audit.sh](scripts/install-single-node-audit.sh), [bootstrap-candidate-node.sh](scripts/bootstrap-candidate-node.sh), [install-admin-portal-audit.sh](scripts/install-admin-portal-audit.sh), and [install-worker-audit.sh](scripts/install-worker-audit.sh) — isolated native candidate repositories and secure setup.
- Focused auth/lateral-network probes and some Rocky postrun commands were issued directly; their output is retained in the private raw run logs rather than a standalone wrapper script.

## CI, tracker, and closeout boundaries

Root CI passed for the R75 runtime evidence commit [3c4d6db / run 40147625018](https://github.com/admiral-project/admiral/actions/runs/40147625018), the seed-manifest tooling fix [1d87058 / run 40147974868](https://github.com/admiral-project/admiral/actions/runs/40147974868), and the latest audit-documentation commit [9ce9ecc / run 40149559666](https://github.com/admiral-project/admiral/actions/runs/40149559666). The packaged component CI runs are listed above and in the candidate report.

The master functional tracker [#277](https://github.com/admiral-project/admiral/issues/277) records 6/6 PASS and remains open for the broader audit. The seed-manifest tooling item [#282](https://github.com/admiral-project/admiral/issues/282) remains open with `fix-proposed`; its fix changes validation tooling only and does not require an RPM rebuild or invalidate the R75 product candidate.

Production readiness remains **NOT VALIDATED**. Comprehensive isolation/security negatives, PostgreSQL/task interruption and replay, broader fault injection, resource exhaustion, external S3/R2 and volume backup/restore, and controlled performance/scalability percentiles remain outside this functional closeout. See [SECURITY_REVIEW.md](SECURITY_REVIEW.md), [RESILIENCE_REPORT.md](RESILIENCE_REPORT.md), and [PERFORMANCE_REPORT.md](PERFORMANCE_REPORT.md).
