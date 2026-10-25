# Issue #259 — rootless user systemd manager restart

**Disposition: targeted diagnostic acceptance passed.** On the `Epoch 3 / 0.0.1rc6 / Release 5` package set, the check passed four consecutive repetitions on Rocky Linux 10.2 x86_64 and four on Fedora Rawhide x86_64. The issue remains open pending rerun on the final no-Epoch release candidate and the remaining release environments. These runs do not count as matrix cells.

Each repetition restarted `user@<uid>.service` while a DB-backed workload was active, checked that health was not advertised before its manager/pod/database recovered, verified API readiness and persistence of `r68-user-systemd-persisted`, deprovisioned the workload, and confirmed successful cleanup. All eight logs report `false_healthy_available_polls=0` and `user_systemd_manager_restart_and_recovery=PASS`.

| OS | Successful repetitions | Evidence directory |
|---|---:|---|
| Rocky Linux 10.2 x86_64 | 4/4 | `rocky-final/` |
| Fedora Rawhide x86_64 | 4/4 | `fedora-final/` |

The per-run SHA-256 values are recorded in each directory's `SHA256SUMS`. The candidate identity and package hashes are recorded alongside issue #260 in `../rc6-epoch3-issue-260/`.

This is issue-specific diagnostic evidence only. The active release matrix remains **0/6** until one exact no-Epoch candidate passes Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide in Single-Node and Multi-Node (Admin + Worker + independent Portal).
