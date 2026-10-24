# Release 74 CentOS Stream Multi-Node run — 2026-10-24

## Decision

**CentOS Stream 10 x86_64 Multi-Node: FAIL for Release 74.** The functional service scenarios ran against the exact `0.0.1rc5-74.el10` RPM set, but the final data-retention audit found that normal idle-node removal permanently deleted four terminal customer-instance records and their operation history. This is tracked as [#278](https://github.com/admiral-project/admiral/issues/278), under the active functional release gate [#277](https://github.com/admiral-project/admiral/issues/277).

The earlier workload, retry, concurrency, worker-reboot, partition/rejoin, hub-reboot, active-node-refusal, and peer-revocation observations remain reproducible scenario evidence for exact R74. They do **not** make this Multi-Node cell PASS. Per #277's candidate rule, finding this actionable defect invalidates the preceding R74 matrix run as a whole: all six active cells currently receive **no PASS credit** for the release decision. The prior three Single-Node outcomes are retained as historical R74 evidence only. A rebuilt candidate needs a new coordinated run of all six cells.

The local raw-evidence directory is named `pass-20261024T2115Z` because that name was allocated before the post-run audit. It contains both successful scenario outputs and the failure evidence documented below; the directory name is not the cell result.

## Candidate and lab

- Candidate preparation source: root commit `d6e5cacb7c35807417f19b7f970c1d1f6a2d387c`.
- Installed Admiral packages: six native EL10 RPMs, all `0.0.1rc5-74.el10`; exact SHA-256 values are in [`release74-el10-RPM-MANIFEST.tsv`](release74-el10-RPM-MANIFEST.tsv) and [`release74-el10-SHA256SUMS`](release74-el10-SHA256SUMS).
- OS: CentOS Stream 10 x86_64, kernel `6.12.0-278.el10.x86_64`, SELinux Enforcing.
- Seed SHA-256: `2b046acf36e4b775bac179ad2dd5c93cadc051ea7b6991842d0d0274a466b195`.
- Three isolated guests, each 2 vCPU / 2 GiB RAM: hub `adm-r74-centos-mn-hub` (`192.168.122.166`, WireGuard `10.99.0.1`), W1 `adm-r74-centos-mn-w1` (`192.168.122.167`, `10.99.0.2`), W2 `adm-r74-centos-mn-w2` (`192.168.122.168`, `10.99.0.3`). These addresses were read from the lab and guest configuration.
- Hub installed all six packages; each worker installed `admiral-common` and `admiral-fleet`. Installation recaps: hub `ok=239 changed=106 unreachable=0 failed=0 skipped=140`; W1 `ok=152 changed=52 unreachable=0 failed=0 skipped=224`; W2 `ok=152 changed=52 unreachable=0 failed=0 skipped=224`.
- Hub, PostgreSQL, Harbor and portal services were active; Fleet was intentionally inactive on the portal-only hub. Both workers had active Fleet and rootless workload users. All guests reported zero failed systemd units after the run. The three VMs are now shut off; disks and raw logs are retained.
- The candidate RPM bytes and specs were unchanged during this run. EL10 packages were installed via the signed native DNF repository with normal dependency resolution; no Fedora binaries, `--nodeps`, force, or vendor override was used.

## Scenarios executed

| Test | Observed result | Scenario result |
|---|---|---|
| `R74-CENTOS-MN-PLACEMENT-01` | Explicit placement succeeded on W1 and W2. Both workloads returned HTTP 200 and preserved SQL markers; root-owned tier configuration had mode 0600 and a 1 GiB limit. W2's first storage observation was `unknown`/0, then converged to 1 GiB/`ok` by the fourth sample. Deprovision left no matching runtime resources. | PASS scoped |
| `R74-CENTOS-MN-CONCURRENT-IDEMPOTENCY-01` | Three synchronized clients using the same idempotency key received the same operation/task/instance on W1; workload HTTP 200 and cleanup succeeded. | PASS scoped |
| `R74-CENTOS-MN-UPDATE-DELETE-01` | Concurrent resize and forced deprovision returned succeeded; final instance was deprovisioned and worker resources were absent. | PASS scoped |
| `R74-CENTOS-MN-WORKER-REBOOT-01` | W1 boot ID changed from `551b59ac-5a0a-4f92-8ba2-d9941b588a8f` to `7eb376a4-1e9a-435b-9077-326a8d0aa036`; workload, HTTP 200 and SQL marker recovered; cleanup succeeded. | PASS scoped |
| `R74-CENTOS-MN-PARTITION-01` | W2 lost hub connectivity (`curl` exit 28), was reported offline/degraded and the instance unavailable after heartbeat timeout; route restoration rejoined W2 and restored workload HTTP 200 and SQL marker. Cleanup succeeded. | PASS scoped |
| `R74-CENTOS-MN-HUB-REBOOT-01` | Hub boot ID changed from `2f7e5015-87f2-444c-82a0-ab431060e40d` to `5b56d983-f76b-419f-a953-6e1f3736c948`; W1's workload recovered with HTTP 200 and its SQL marker. Cleanup succeeded. | PASS scoped |
| `R74-CENTOS-MN-NODE-REMOVE-01` | Removing active W2 without force was refused; its instance stayed available and HTTP 200. After deprovision, idle removal succeeded. W2 disappeared from node inventory, its WireGuard peer was absent from live and persistent hub state, and its rootless runtime inventory was empty. A post-removal PostgreSQL audit then found that all four W2 instance rows and their operation rows had been deleted. | **FAIL** |

The full guest post-check found CentOS Stream 10 x86_64, SELinux Enforcing, no failed units, and empty workload inventories on the remaining workers. This confirms cleanup but cannot compensate for loss of customer history.

## Finding #278: node removal deletes customer history

After removal of W2, a read-only PostgreSQL query at `2026-10-24T21:25:27Z` found the following test instances absent: `inst_2f4e601fde11def4`, `inst_688ff725b61dfb3d`, `inst_aede61cb83c40e8c`, and `inst_f01a138673866a33`. All four had first reached terminal deprovisioned state and had no worker runtime resources. Their associated operation rows were also absent. For comparison, the four W1 test instances remained terminal and retained nine successful operation rows. The removed node row was absent as intended.

The saved read-only query output is `packaging/build/validation/rc5-r74/runtime/multi/centos/pass-20261024T2115Z/postrun/instance-retention-after-node-removal.txt`, mode 0600, SHA-256 `6e76c73e2d3a3e9c44f995f8c16c0236e1abf5b271ac469bfaffb28eeeeb48ff`. It lists all eight test IDs, instance statuses, per-instance operation counts, and removed-node count.

Root cause is confirmed in `admirald/internal/database/nodes.go`, `RemoveNodeWithHook`: it deleted every `customer_apps` row for the removed node. The `operations.instance_id` foreign key uses `ON DELETE CASCADE`, which deleted the operation history. Instance-owned backup/secret metadata can also cascade from deletion. The schema permits `customer_apps.node_id` to be null, so historical records can survive after the node association is detached.

A minimal fix is now in `admirald` commit `65afd58947c56edaef041737d7f775e7b4038182` on `origin/main`: idle-node removal detaches customer instances and legacy backup rows from the node inside the same transaction, retaining instance, operation, and backup history. Regression `TestRemoveNodePreservesTerminalInstanceAndOperationHistory` passed against an isolated PostgreSQL test database. Full `go test -p 1 ./...` and `go vet ./...` passed locally. GitHub CI is green in [run 40134043032](https://github.com/admiral-project/admirald/actions/runs/40134043032). No RPM built from this fix has been runtime tested.

## Reproduction and raw evidence

The reproduction scripts, without keys or host pins, are committed in [`scripts/`](scripts/):

- `r74-centos-multinode-placement.sh`
- `r74-centos-multinode-concurrent-idempotency.py`
- `r74-centos-multinode-concurrent-update-delete.sh`
- `r74-centos-multinode-worker-reboot.sh`
- `r74-centos-multinode-partition.sh`
- `r74-centos-multinode-hub-reboot.sh`
- `r74-centos-multinode-node-removal.sh`

Shell syntax checks (`bash -n`) and Python AST parsing passed. The per-scenario raw captures and SHA-256 manifests are retained under `packaging/build/validation/rc5-r74/runtime/multi/centos/pass-20261024T2115Z/scenarios/`, with file mode 0600. The local evidence includes preflight/install attempts, all scenario outputs, and post-run state; it is not committed because it contains lab-specific operational data. The data-retention SQL capture above is an explicit sanitized query artifact.

Initial harness-only errors are preserved: one preflight attempt occurred before all guests finished starting; a duplicate W2 install-helper invocation was rejected while the actual process was running; an early host post-run capture had no output directory. All were retried and are not product failures. A first `admiralctl instances show` post-removal query used an unsupported output flag; retry without that flag returned “Instance not found,” and the direct database audit then confirmed deletion. These failed attempts are kept separately from the product finding.

## Limits

This is three-node real integration and resilience evidence on CentOS Stream 10, not a broad production certification. It does not cover stress/latency percentiles, memory or disk exhaustion, isolation-negative tests, external S3/R2, PostgreSQL outage recovery, or physical host failure. The new fix has not yet been built into an RPM or revalidated end to end.
