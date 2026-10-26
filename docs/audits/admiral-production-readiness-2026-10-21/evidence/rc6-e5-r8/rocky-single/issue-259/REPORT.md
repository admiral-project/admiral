# Issue #259 — Rocky Linux 10 Single-Node on RC6 R8

**Result: PASS for this OS/topology probe.** Candidate `rc6-e5-r8` installed
all six Epoch 5 / Release 8 RPMs recorded in `../../el10/RPM-MANIFEST.tsv`.

The installed `user@991.service` manager was restarted four times while a
database-backed workload was active. In all four runs, the rootless workload
and SQL marker recovered, the instance returned to healthy/available, no
healthy/available sample was observed while the manager/workload was stopped
or recovering, and deprovision completed cleanly. Each run log is listed in
`SHA256SUMS`.

This is issue-specific evidence for Rocky Single-Node. Fedora Rawhide and
CentOS Stream Single-Node also pass on R8; Multi-Node coverage remains pending.
