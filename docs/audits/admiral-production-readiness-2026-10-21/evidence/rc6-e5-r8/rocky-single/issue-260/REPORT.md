# Issue #260 — Rocky Linux 10 Single-Node on RC6 R8

**Result: PASS for this OS/topology probe.** Candidate `rc6-e5-r8` installed
all six Epoch 5 / Release 8 RPMs recorded in `../../el10/RPM-MANIFEST.tsv`.

The test stopped the declared PostgreSQL unit for 60.070 seconds and captured
61 health samples at approximately one-second intervals. Admiral changed
from healthy/available to failed/unhealthy/unavailable by 4.034 seconds; zero
samples remained healthy/available at or after five seconds. PostgreSQL then
recovered, the SQL marker persisted, and cleanup succeeded. The complete
transcript and its hash are in `SHA256SUMS`.

This is issue-specific evidence for Rocky Single-Node. Fedora Rawhide and
CentOS Stream Single-Node also pass on R8; Multi-Node coverage remains pending.
