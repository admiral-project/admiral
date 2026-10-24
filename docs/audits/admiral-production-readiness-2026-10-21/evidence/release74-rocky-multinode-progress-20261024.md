# Release 74 Rocky Linux Multi-Node progress — 2026-10-24

## Result and scope

**Release 74 Rocky Linux 10.2 x86_64 Multi-Node: scoped scenarios PASS; the full cell is INCOMPLETE.** This is one real admin hub and two real Rocky workers. It does not increase the accepted functional matrix count: Release 74 remains **3/6 complete cells**, all three Single-Node. CentOS Stream and Fedora Rawhide Multi-Node remain NOT TESTED. This report is not a production-readiness certification.

The tests ran against unchanged R74 RPMs (`0.0.1rc5-74.el10`) built from candidate preparation commit `d6e5cacb7c35807417f19b7f970c1d1f6a2d387c`. The hub had all six native EL10 RPMs; each worker had `admiral-common` and `admiral-fleet`. All guests reported Rocky Linux 10.2, kernel `6.12.0-211.68.1.el10_2.x86_64`. The lab used three 2-vCPU/2-GiB guests on the isolated libvirt host. The hub was `192.168.122.163` / WireGuard `10.99.0.1`; workers were `192.168.122.164` / `10.99.0.2` and `192.168.122.165` / `10.99.0.3`. These addresses were read from the running guest and hub configuration. The hub and both workers reported no failed systemd units after the run. Disk availability at the host check was 51 GiB.

The OS seed already contained updates and the pinned Python helper RPM set. The test installed native R74 EL10 RPMs through the signed EL10 repository; Fedora RPMs were not used. The guest clones and Python package baseline were unchanged during these runs.

## Executed scenarios

| Test ID | Procedure and observed result | Status |
|---|---|---|
| `R74-ROCKY-MN-PLACEMENT-01` | Explicitly provisioned to W1 and W2 in turn. Same-key replay returned the same operation and instance; both workloads reported 1 GiB configured storage, PostgreSQL marker roundtrip and HTTP 200 through WireGuard; deprovision left no matching containers, pods, volumes, units or files. W1 had one transient `running/unhealthy/unavailable` observation while its DB container was starting, then converged to healthy/available on the next sample. W2 was healthy/available on its first captured sample. | PASS, scoped |
| `R74-ROCKY-MN-CONCURRENT-IDEMPOTENCY-01` | Three synchronized clients issued the same provision request and idempotency key. All received operation `op_46028c0049ec7f2d`, task `task_312e7714ea3b0e02`, instance `inst_0c198bace00c1a4d`, assigned to W2. The workload returned HTTP 200 and cleanup succeeded with empty runtime inventories on both workers. | PASS, scoped |
| `R74-ROCKY-MN-UPDATE-DELETE-01` | Concurrent resize and forced deprovision both returned succeeded. The instance remained deprovisioned after the settle check; matching runtime resources were empty. | PASS, scoped |
| `R74-ROCKY-MN-WORKER-REBOOT-01` | Rebooted W1 with an active workload. Boot ID changed from `767cc3bc-8278-4d6c-b76e-4f95dea6902a` to `b0b759e7-637a-409f-baa1-b47c18c43b40`. Transitional unavailable/stopped samples were retained; by poll 3 the instance was running/healthy/available, HTTP was 200 and the SQL marker persisted. Deprovision cleanup was empty. | PASS, scoped |
| `R74-ROCKY-MN-PARTITION-01` | Changed only W2's in-memory WireGuard AllowedIPs. W2 could not reach the hub; the workload became unavailable with `runtime_observation_stale`, then W2 reached `offline/degraded` after heartbeat timeout (~94 seconds from partition start). Restoring the route recovered W2 and the workload on the first poll; HTTP 200 and SQL marker persisted; cleanup was empty. A 180-second systemd restore timer was armed as a safety fallback. | PASS, scoped |
| `R74-ROCKY-MN-HUB-REBOOT-01` | Rebooted the actual hub VM with a healthy W1 workload. Hub boot ID changed; `admirald`, PostgreSQL and WireGuard became active; both worker routes and fresh handshakes returned; the workers supplied fresh post-reboot heartbeats. The workload converged by recovery poll 3, returned HTTP 200 and retained its SQL marker. Deprovision cleanup was empty. | PASS, scoped |
| `R74-ROCKY-MN-NODE-REMOVE-01` | Attempted to remove W2 while it had one healthy active instance; the CLI refused with the active-instance error and exit 1, and the workload remained HTTP 200. After deprovision, idle removal succeeded; the node was absent from inventory and `nodes show` returned HTTP 404. A follow-up read found no live WireGuard route or persistent config entry for `10.99.0.3/32`. The removed worker's rootless runtime inventory was empty. | PASS, scoped |

The concurrent same-key probe initially had a harness-only rootless Podman inventory failure because `runuser` inherited `/home/validator`; the corrected runner explicitly changed to `/tmp`, checked the inventory command, and passed. An earlier update/delete attempt stopped at a stale R66 candidate check; its next preflight stopped before the concurrent mutation because of the same working-directory issue. The final corrected R74 run passed. An initial hub-reboot invocation was rejected before touching the VM because its output directory already existed; the rerun used a fresh path and passed. These attempts are preserved in the restricted local validation directory and are not counted as product failures or passes.

## Evidence and reproduction

Reproduction scripts are committed under [`scripts/`](scripts/):

- `r74-rocky-multinode-placement.sh`
- `r74-rocky-multinode-concurrent-idempotency.py`
- `r74-rocky-multinode-concurrent-update-delete.sh`
- `r74-rocky-multinode-worker-reboot.sh`
- `r74-rocky-multinode-partition.sh`
- `r74-rocky-multinode-hub-reboot.sh`
- `r74-rocky-multinode-node-removal.sh`

The raw per-run captures are kept on the isolated host under `packaging/build/validation/rc5-r74/runtime/multi/rocky/`, mode `0600`; they are not committed. Each listed manifest verifies with `sha256sum -c SHA256SUMS`.

| Run | Test | SHA-256 of local `SHA256SUMS` |
|---|---|---|
| `placement-run-20261024T2020Z` | placement on W1 and W2 | `bbd20afdd9baecb29e61bfd01bb94fe938e35a3e12cb2fbc06c7778324cb0d22` |
| `concurrent-idempotency-rerun-20261024T2021Z` | three-client same-key replay | `9a7cd4549d256b62256b87378b56b67d4b50d28b39a60cb31f4f9d0670dc84e5` |
| `concurrent-update-delete-final-20261024T2023Z` | concurrent resize/deprovision | `c962d172f9111a52de5a09e7dae5a6fefd9e4b8269f44a6d2a3081b5722d444d` |
| `worker-reboot-run-20261024T2025Z` | active workload across W1 reboot | `c123af83cb7248ab5b4dec098886f87daf77ecb763c8d0c4a9fe95e6e85f6662` |
| `partition-run-20261024T2024Z` | W2 partition, timeout and rejoin | `b060b621cda1647518c32002aa8749ba79e04976432144fe0dd99d3b8f6e7964` |
| `hub-reboot-run-20261024T2027Z` | hub reboot and W1 workload recovery | `8a7849d81084cf6b14c8d7512878892ef8c19ec140e8913a7ff9b2bf6465fb95` |
| `node-removal-run-20261024T2028Z` | active removal refusal and idle removal | `2f31af724c9bff9f876a7f82dcf0b79f1ec8d3b77ec8d3e930f40b3fbaef63f7` |
| `postrun-state-20261024T2031Z` | final node inventory, both worker runtime inventories, failed-unit checks, and live/persistent route absence after removal | `edbe7125c59132d0926427470a259d063cca6ec33ba8aee71a0abe0b7a330be1` |

## Coverage still missing for a complete cell

This run did not test central PostgreSQL outage, in-flight task interruption/replay, node re-enrollment after removal, old Fleet-token rejection, failed node-removal helper rollback, broad authorization and isolation negatives, resource exhaustion, progressive load/latency percentiles, or external S3 backup/restore. It did not establish behavior across all Multi-Node platforms. These scenarios remain NOT TESTED for the active Release 74 matrix. A passing scoped scenario is not a full cell PASS.
