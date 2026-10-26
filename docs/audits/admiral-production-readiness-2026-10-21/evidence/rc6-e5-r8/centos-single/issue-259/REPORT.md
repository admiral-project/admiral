# Issue #259 — CentOS Stream 10 Single-Node, RC6 R8

**Result: PASS for CentOS Stream 10 Single-Node.** On 2026-10-26, four fresh
workload instances on `rc6r8-centos-single` ran on candidate `rc6-e5-r8`
(Epoch 5, Release 8, EL10 RPMs). Each probe restarted the rootless user
systemd manager. No healthy/available sample occurred during restart/recovery;
the SQL marker persisted, HTTP returned 200 after recovery, and each instance
deprovisioned successfully with no residual resources. All four runs reported
PASS; logs and SHA-256 values are in `SHA256SUMS`.

This is CentOS Single-Node evidence only. It does not claim issue-wide
acceptance or a 6/6 release matrix result; Multi-Node coverage is pending.
