# RC6 Epoch 5 / Release 2 — Single-Node functional lanes

Date: 2026-10-26 UTC. Candidate: Admiral 0.0.1rc6 Release 2, RPM Epoch 5. Root source commit: e710237fd908feabf17b12fb61d08429deb21e52. All five selected component submodule commits are printed at the start of each raw lane log. Exact RPM NEVRA and SHA-256 values are in [RPM-MANIFEST.tsv](x86_64/RPM-MANIFEST.tsv); RPM files, native local repositories, and repository metadata are under x86_64/.

## Results

| Test ID / OS | VM and seed | Run ID / UTC | Installer result | Functional lane |
|---|---|---|---|---|
| RC6-SN-R2-ROCKY | Rocky Linux 10.2 x86_64, fresh 2-vCPU/2-GiB overlay rc6r2-rocky-sn, 192.168.122.199 | r2rocky2601, 00:41:04–00:46:41 | Exact six native .el10 RPMs, Epoch 5 / Release 2; secure install completed before lane. | PASS, 6/6 stages, zero failed stages. |
| RC6-SN-R2-FEDORA | Fedora Rawhide x86_64, fresh 2-vCPU/2-GiB overlay rc6r2-fedora-sn, 192.168.122.249 | r2fedora2601, 00:41:04–00:47:27 | Exact six native .fc46 RPMs, Epoch 5 / Release 2; secure install completed before lane. | PASS, 6/6 stages, zero failed stages. |
| RC6-SN-R2-CENTOS | CentOS Stream 10 x86_64, fresh 2-vCPU/2-GiB overlay rc6r2-centos-sn, 192.168.122.84 | r2cent2601, 00:55:22–01:00:13 | Exact six native .el10 RPMs, Epoch 5 / Release 2; secure install recap ok=231 changed=96 unreachable=0 failed=0. | PASS, 6/6 stages, zero failed stages. |

The six lane stages were workload create/idempotency/deprovision; resize and database marker continuity; local backup/restore, checksum and invalid-state rejection; instance and admirald service lifecycle; actual guest reboot with workload/HTTP/SQL persistence; and final service, package EVR, and rootless runtime cleanup checks. Stage outputs and test IDs are in each adjacent lane.log.

The test recorded transitional unavailable/stopped/failed states while services and workloads recovered after the actual guest reboot. Each run then reached running/healthy/available, returned HTTP 200, preserved its SQL marker, deprovisioned the test instance, and ended with no failed system units or target rootless containers, pods, volumes, Quadlet units, or files. These observed transitional samples are retained in raw logs rather than suppressed.

## Evidence and limits

Raw functional captures: [Rocky lane](functional/rocky-single/lane.log), [Fedora lane](functional/fedora-single/lane.log), [CentOS lane](functional/centos-single/lane.log). Local SHA-256 values at capture time:

- Rocky: ef0a8d09a6438f592120125a1aa0912c7ce51d5eccaaae8e0e2fba79e3e0828b
- Fedora: a48b8dad9910e022d2cf4097a9ccd0337be2802d3211cd4ef92f76d6ba5b6f5c
- CentOS: 55afe447d71f5de5405fe4924c6d47d0687135c841bb2069da1215a82c92e25d

Installer output logs remain access-restricted under /var/lib/libvirt/images/admiral-validation/evidence/rc6-r2-epoch5/{rocky-single,fedora-single,centos-single}/install.log because they contain generated bootstrap credentials. The redacted evidence record preserves each installer recap and lane logs contain no credential values.

These results are candidate-specific functional lanes, not formal matrix-cell sign-off. The linked-issue gate remains incomplete; Multi-Node, broader security/isolation negatives, controlled fault injection, resource exhaustion, systematic concurrency and performance have not all been run on this candidate. Formal matrix status remains 0/6 complete cells.
