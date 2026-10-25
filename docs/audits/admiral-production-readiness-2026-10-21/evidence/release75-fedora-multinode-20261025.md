# Release 75 Fedora Rawhide Multi-Node validation

**Result: PASS for the Release 75 Fedora Rawhide x86_64 Multi-Node functional cell.**

The coordinated Release 75 functional matrix is now **6/6 cells PASS**: Fedora Rawhide, Rocky Linux 10 and CentOS Stream 10, each Single-Node and Multi-Node. This is release-candidate functional evidence, not a full production-readiness certification.

## Candidate and package identity

This run used the unchanged Release 75 candidate prepared at root commit [`b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953`](https://github.com/admiral-project/admiral/commit/b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953). The later root changes were limited to validation helpers and documentation. Packaged component SHAs, component CI, and candidate RPM hashes are recorded in the [R75 Single-Node report](release75-single-node-20261024.md). The Fedora guests reported and retained the native `0.0.1rc5-75.fc46` packages; no EL10 RPMs, `--nodeps`, forced install, or vendor override was used.

| Guest role | Installed candidate packages |
|---|---|
| Hub | All six `0.0.1rc5-75.fc46` Admiral RPMs |
| Workers W1 and W2 | `admiral-common` and `admiral-fleet`, both `0.0.1rc5-75.fc46` |

The Fedora `.fc46` package hashes in the linked candidate report identify the exact RPM payloads. The VM postrun records confirmed OS `fedora` version `46`, architecture `x86_64`, exact expected installed package names/releases, and no failed system or user units.

## Lab and seed

The run directory is `packaging/build/validation/rc5-r75/runtime/multi/fedora-run-20261025T000323Z/`. It ran on the isolated KVM/libvirt audit host as three real 2 GiB Fedora Rawhide 46 x86_64 VMs. Each reported kernel `7.4.0-0.rc0.261023g734bef548a96.6.fc46.x86_64` and SELinux Enforcing. The refreshed Fedora seed is `Fedora-Rawhide-seed-20261025-r75-updated.x86_64.qcow2`, SHA-256 `0498dd865b5bea8dfab77af043ef2bf80eb88081c5a0801f0ce2d16c9b86e2ea`. It had current OS updates and the spec-derived runtime requirements, Admiral COPR enabled, no Admiral RPMs or enabled Admiral services, and no local validation repository baked into the image.

| Role | VM | Test underlay | WireGuard |
|---|---|---:|---:|
| Hub (Admirald + Harbor) | `adm-r75-fedora-mn-hub` | `10.77.0.10` | `10.99.0.1` |
| Worker 1 | `adm-r75-fedora-mn-w1` | `10.77.0.11` | `10.99.0.2` |
| Worker 2 | `adm-r75-fedora-mn-w2` | `10.77.0.12` | `10.99.0.3` |

Hub installation completed with `ok=246 changed=108 failed=0 unreachable=0 skipped=133`. Both workers installed and enrolled successfully. PostgreSQL, Admirald, Caddy and Harbor were active on the hub; Fleet was active on both workers. The validation key was pinned and accepted; the temporary bootstrap key was rejected.

## Executed checks

| Test ID | Expected behavior | Observed result |
|---|---|---|
| `R75-FEDORA-MN-ENROLL-01` | Install native candidate on three real VMs; securely enroll both workers and verify services, heartbeats, WireGuard, SELinux and initial state | **PASS.** Hub installation recap had zero failures/unreachable hosts; both workers enrolled and converged active/healthy/available with fresh heartbeats. |
| `R75-FEDORA-MN-AUTH-ISOLATION-01` | Verified TLS succeeds; anonymous worker API and lateral worker TCP access are denied | **PASS, scoped.** Both workers received HTTP 401 without credentials; worker-to-worker TCP 9099 was denied (`connect_ex=113`). SELinux was Enforcing. This is a focused negative check, not exhaustive workload isolation validation. |
| `R75-FEDORA-MN-PLACEMENT-01` | Place on each worker, replay same idempotency key, verify assignment, storage, SQL, HTTP and cleanup | **PASS.** W1 and W2 placements/replays returned their original operation and instance; each retained a PostgreSQL marker, returned HTTP 200 over WireGuard, reported the 1 GiB tier, and deprovisioned with no matching runtime resources. |
| `R75-FEDORA-MN-CONCURRENT-IDEMPOTENCY-01` | Three synchronized identical same-key requests result in one operation/task/instance | **PASS, scoped.** All three returned operation `op_e52e8abe6def21e8`, task `task_65340e4bcbbd30c6`, and instance `inst_3dffada2dcebb026` on W2; cleanup succeeded. |
| `R75-FEDORA-MN-UPDATE-DELETE-01` | Concurrent resize and deprovision converge to a consistent terminal state without orphaned runtime | **PASS.** Both operations completed; after the settle interval the instance was deprovisioned/unavailable and the runtime inventory was empty. |
| `R75-FEDORA-MN-WORKER-REBOOT-01` | Reboot W1 with live workload; verify changed boot ID, recovery, SQL and HTTP | **PASS.** Boot ID changed; by poll 2 the node and workload were active/healthy/available, HTTP returned 200 and the SQL marker persisted; cleanup succeeded. |
| `R75-FEDORA-MN-PARTITION-01` | Partition W2 from hub, observe stale/unavailable state, restore route and confirm recovery | **PASS.** The workload became unavailable; W2 became offline/degraded at poll 12 (~147 s after partition start). Route restoration recovered the worker and workload by rejoin poll 3 (~36 s), with HTTP 200 and SQL data intact; cleanup succeeded. |
| `R75-FEDORA-MN-HUB-REBOOT-01` | Reboot hub with workload; verify services, worker reconnection, HTTP and SQL | **PASS.** Hub boot ID changed, hub services and worker routes/handshakes returned, and the active W1 workload recovered with HTTP 200 and its SQL marker; cleanup succeeded. |
| `R75-FEDORA-MN-NODE-REMOVE-01` | Refuse removal of active worker, then remove idle worker and verify inventory/route cleanup | **PASS.** Active W2 removal was refused. After deprovision, idle removal succeeded; W2 was absent from cluster inventory and hub peer routes. |
| `R75-FEDORA-MN-POSTRUN-01` | Check exact OS/candidate, failed units, final node/peer state and empty worker runtime | **PASS.** Fedora 46 x86_64 and expected native Release 75 packages were confirmed, no failed units or workload resources remained, and hub inventory contained itself and W1 after W2 removal. |

## Evidence and reproduction

Private raw output is retained locally under the run directory above. Its 202-file `RAW-EVIDENCE.SHA256` manifest has SHA-256 `18eb11d50f7882f0afb7fa3da819da15eb90041dc3583adeeb1d47c374fac6ac`; directories are mode `0700` and files mode `0600`. The manifest includes preliminary harness/environment failures and corrected passing runs; no raw logs, keys or credentials are published here. These preliminary attempts were not classified as Admiral product failures. The initial unprivileged TLS probe could not traverse a root-only CA directory; the corrected root probe passed certificate verification. A worker-reboot preflight expected Fedora's old `NAME` value, was corrected to check `ID=fedora` and `VERSION_ID=46`, and the actual reboot/recovery rerun passed. The postrun checker was likewise corrected to test the stable OS ID/version and then passed.

Reproduction scripts are under [`scripts/r75/`](../scripts/r75/): `r75-fedora-multinode-placement.sh`, `r75-fedora-multinode-concurrent-idempotency.py`, `r75-fedora-multinode-concurrent-update-delete.sh`, `r75-fedora-multinode-worker-reboot.sh`, `r75-fedora-multinode-partition.sh`, `r75-fedora-multinode-hub-reboot.sh`, `r75-fedora-multinode-node-removal.sh`, and `r75-fedora-multinode-postrun.sh`. All test VMs are disposable overlays; the refreshed shared Fedora seed is preserved.

## Decision and limits

This completes the Release 75 functional Multi-Node cell for Fedora Rawhide x86_64. All six active functional cells now pass on the exact unchanged Release 75 source/RPM candidate. The broader audit remains **NOT VALIDATED**: comprehensive security and cross-workload isolation, PostgreSQL outage, task interruption/replay, resource exhaustion, wider fault permutations, and stress/performance percentiles were not established by this matrix. A passing functional matrix is not a guarantee of production readiness.
