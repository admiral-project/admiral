# Performance report

Audit ID: `ADM-AUDIT-2026-10-21`<br>
> **Release 75 status:** no controlled benchmark or scalability campaign has run. The parallel functional run is not a controlled performance sample. There are no R75 p50/p95/p99 measurements; performance remains **NOT TESTED**.

R75 provisioning and installer durations are observations within the functional run only; they are not controlled benchmark samples. No R75 load sweep, resource-profile sampling, repeated latency distribution, or p50/p95/p99 measurement was performed. See [`release75-single-node-20261024.md`](evidence/release75-single-node-20261024.md).

> **Historical R67 status:** Scoped Single-Node install, lifecycle and reboot runs are recorded for all four OSes, plus Fedora Multi-Node functional runs. Individual installer and operation timings are observations only. No controlled R67 performance or scalability campaign has been run. Matrix remains 0/8.

Historical R68 performance status (no R69 evidence): **NOT VALIDATED — no controlled performance campaign; matrix 0/8.** No R68 run has measured progressive workload/concurrency load, repeated latency samples, p50/p95/p99, or controlled CPU/memory/I/O/file-descriptor consumption. R67 installer timings below are historical single functional observations and do not count as R68 performance evidence.

This audit defines no product SLO. It will record the measured baseline and the limiting resource for each workload. Results must identify the exact candidate, guest OS, VM sizing, app definition, concurrency, database mode, image-cache state, and host load. Cold image pulls must be reported separately from warm container creation.

## Required measurements

For provision, update, pause/resume, backup, restore and deprovision, record operation request-to-terminal latency and separate API request latency where applicable. For repeated samples, report count, p50, p95 and p99, plus failures/timeouts. Record host and guest CPU, RSS, swap, memory pressure, disk free/IO, PostgreSQL activity, process count, file descriptors and Podman/systemd unit state. Multi-Node measurements must include hub and each worker, placement, WireGuard traffic, and one-worker versus two-worker behavior.

## Historical R67 observations (not R68 performance evidence)

R67 Single-Node runs provide one functional lifecycle and one host-reboot sample per OS, not a benchmark distribution. The secure installer ran for 441 seconds on Fedora, 920 on Rocky, 379 on AlmaLinux and 369 on CentOS Stream, all on seeded 2-vCPU/2-GiB guests. The Rocky sample includes a recorded host-side wrapper error after the installer itself exited 0. Database readiness was observed on poll 2 (Fedora) and poll 1 (Rocky, AlmaLinux and CentOS Stream) during the basic lifecycle. Post-reboot availability followed DB readiness on the sampled recovery paths. These observations are useful for reproduction only; no SLO or percentile is inferred. See [`release67-single-node-targeted.md`](evidence/release67-single-node-targeted.md).

Release 60 targeted runs record install and fault-detection elapsed times in protected raw logs. No R60 numbers are reported here as benchmark samples because cache state, host load and repetitions were not controlled. Prior Release 58, Release 47 and Release 46 timings remain historical diagnostics only; no p50/p95/p99 values are available and none are inferred.

Release 46 functional probes provide historical provision-to-terminal timings of 138.1s on AlmaLinux 10.2, 94.9s on CentOS Stream 10, 11.3s on Fedora Rawhide 46, and 37.6s on Rocky Linux 10.2 (8.7s deprovision). Rocky remains in the active Release 49 matrix; none of these Release 46 figures validate any R49 cell. None are controlled performance samples: image-cache state was not held constant, the AlmaLinux and CentOS runs showed database startup delays during cold image/service startup, and only one sample exists per tested OS. Release 46 deprovision samples were 11.9s, 9.9s, 9.6s and 8.7s respectively. They provide historical functional timing observations only. No repeatable sample distribution, latency percentiles or concurrent load profile was captured for this audit. Therefore no p50/p95/p99 values are available and none are inferred.

One operational timing is captured but is not a workload benchmark: the secure worker2 installer on an AlmaLinux 10.2 2-vCPU/2-GiB VM ran from `13:10:07Z` to `13:17:40Z` (7m33s), including security updates and secure setup. The installer output shows the DNF security-update task was a distinct part of this duration. This single onboarding sample cannot be generalized to release performance or used as a percentile.

| OS / topology | Candidate / guest resources | Samples | p50 / p95 / p99 | Bottleneck assessment | Status |
| --- | --- | ---: | --- | --- | --- |
| Fedora Rawhide x86_64 Single-Node | Release 46 functional probe; one provision sample 11.3s and one deprovision sample 9.6s; warm/cold image state not controlled | 1 functional run | — | — | NOT TESTED (performance) |
| AlmaLinux 10 x86_64 Single-Node | Release 46 functional probe; one provision sample 138.1s and one deprovision sample 11.9s; DB startup delayed during image/service startup | 1 functional run | — | — | NOT TESTED (performance) |
| Rocky Linux 10 x86_64 Single-Node | Release 46 historical probe; one provision sample 37.6s and one deprovision sample 8.7s; seed exception now documented for Release 47 | 1 functional run | — | — | NOT TESTED (performance) |
| CentOS Stream 10 x86_64 Single-Node | Release 46 functional probe; one provision sample 94.9s and one deprovision sample 9.9s; DB startup delayed during image/service startup | 1 functional run | — | — | NOT TESTED (performance) |
| Fedora Rawhide x86_64 Multi-Node | Three-node functional checks; no controlled sample set | — | — | — | NOT TESTED (performance) |
| Rocky Linux 10 x86_64 Multi-Node | No Release 47 run; prior exploratory setup is not a performance sample | — | — | — | NOT TESTED (performance) |
| AlmaLinux 10 x86_64 Multi-Node | Three-node functional checks; no controlled sample set | — | — | — | NOT TESTED (performance) |
| CentOS Stream 10 x86_64 Multi-Node | Historical runtime install, placement on both workers and cleanup subset; no controlled performance sample set | — | — | — | NOT TESTED (performance); runtime evidence is partial |

## Measurement procedure

The reproducible harness will timestamp operation submissions and terminal states, retain raw samples as CSV, and sample `/proc`, `systemd`, Podman, disk and PostgreSQL metrics at a fixed interval. It will use disposable app instances and clean up only those audit instances. Stress levels will rise gradually and stop before host pressure threatens other work. Host limits (4 vCPU, 8 GiB RAM plus 4 GiB swap) will be reported separately from product behavior. Three simultaneous 2-GiB VMs used approximately 6 GiB of assigned guest memory; at peak the host had around 1 GiB available and 1.3 GiB swap used, so no additional VMs or high-load runs were started during this topology test.

No scalability or production-throughput conclusion is available yet.
