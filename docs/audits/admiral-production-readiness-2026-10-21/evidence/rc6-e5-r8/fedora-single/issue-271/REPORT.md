# Issue #271 — Fedora Rawhide Single-Node, RC6 R8

**Result: PASS for Fedora Rawhide Single-Node.** On 2026-10-26, the R8 guest
`rc6r8-fedora-single` tested HTTP 302 health-check targets at loopback and the
guest's NAT address. Both workloads stayed healthy and available through two
fresh periodic reports, the redirect listener received zero requests, and
both workloads were deprovisioned. The final runner reported
`issue_271_redirect_health_checks=PASS`; `redirect-health.log` and the captured
guest evidence tarball have SHA-256 values in `SHA256SUMS`.

This is Fedora Single-Node evidence only. Remaining requested OS/topology
coverage is still pending; this is not an issue-wide or release-matrix pass.
