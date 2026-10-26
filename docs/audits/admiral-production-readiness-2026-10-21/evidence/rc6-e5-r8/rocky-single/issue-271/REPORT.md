# Issue #271 — Rocky Linux 10 Single-Node on RC6 R8

**Result: PASS for this OS/topology probe.** Candidate `rc6-e5-r8` installed
all six Epoch 5 / Release 8 RPMs recorded in `../../el10/RPM-MANIFEST.tsv`.

Both tested HTTP 302 targets (loopback and the guest NAT address) received zero
requests at the redirect listener. The workload stayed healthy/available
through at least two periodic health reports for each variant, and both test
instances deprovisioned cleanly. Full host and guest evidence, with hashes, is
in `SHA256SUMS`.

This is issue-specific evidence for Rocky Single-Node. Fedora Rawhide and
CentOS Stream Single-Node also pass on R8; Multi-Node coverage remains pending.
