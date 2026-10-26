# Issue #259 — Fedora Rawhide Single-Node, RC6 R8

**Result: PASS for Fedora Rawhide Single-Node.** On 2026-10-26, four fresh
workload instances on `rc6r8-fedora-single` ran on candidate `rc6-e5-r8`
(Epoch 5, Release 8, native Fedora `.fc46` RPMs). Each probe restarted the
rootless user systemd manager. No healthy/available sample occurred during the
restart/recovery window; the SQL marker persisted, HTTP returned 200 after
recovery, and each instance deprovisioned successfully with no residual
resources. All four runs reported PASS; logs and SHA-256 values are in
`SHA256SUMS`.

This is Fedora Single-Node evidence only. It does not claim issue-wide
acceptance or a 6/6 release matrix result; the remaining requested OS/topology
coverage is still pending.
