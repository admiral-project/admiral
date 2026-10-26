# Issue #260 — Fedora Rawhide Single-Node, RC6 R8

**Result: PASS for Fedora Rawhide Single-Node.** On 2026-10-26, the R8 guest
`rc6r8-fedora-single` stopped the declared PostgreSQL unit and recorded 61
samples across 60.015 seconds. The first unavailable report arrived at about
3.0 seconds; there were zero healthy/available samples after the five-second
cutoff. PostgreSQL recovery restored the workload to healthy/available,
preserved the SQL marker, and deprovision completed cleanly. The final runner
reported `database_service_outage_and_recovery=PASS`; exact transcript SHA-256
is recorded in `SHA256SUMS`.

This is Fedora Single-Node evidence only. Remaining requested OS/topology
coverage is still pending; this is not an issue-wide or release-matrix pass.
