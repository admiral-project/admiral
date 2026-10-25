# Issue #190 — RC6 Release 1 Harbor worker unit regression

**Result: PASS for the three local unit regressions at the Harbor component pin in RC6 Release 1. This is not a packaged-worker runtime PASS and does not validate a matrix cell.**

- Candidate: root release `0.0.1rc6-1`, without explicit RPM Epoch.
- Harbor submodule SHA: recorded in `metadata.txt`.
- Tests: cancellation-preserving remote sync, no deprovision before prepaid expiry, and deprovision after expiry.
- Result: 3 passed. Raw pytest output and exact command are retained alongside this report.
- Limitation: the issue’s acceptance gate still requires running the installed RPM worker against a real Harbor subscription/workload before and after `next_billing_at`, then checking DB state and runtime. That E2E has not been run on RC6 Release 1.
