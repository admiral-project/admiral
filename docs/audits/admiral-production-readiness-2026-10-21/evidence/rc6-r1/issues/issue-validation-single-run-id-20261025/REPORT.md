# RC6 Single-Node harness — fixed idempotency key replay

**Status: INCOMPLETE; no runtime test pass/fail is assigned. This is a harness defect, not an Admiral product failure.**

- Candidate installed: Admiral `0.0.1rc6-1`, no explicit RPM Epoch, Rocky Linux 10.2 x86_64.
- Package source identity: root `267da7ebd739a0703c276ec8d4770ffa31a45f25`; Harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107` (all six identities are in the lane log).
- Reproduction: invoke `scripts/rc6/run-single-lane.sh rocky <guest-ip> <guest-name>` twice against the same guest. The lifecycle helper used the constant idempotency key `rc6-single-rc6-rocky-lifecycle`.
- Observation: Admiral returned the original successful operation and instance from the earlier run. The instance was already `deprovisioned`; runtime inspection therefore had no matching DB container. This is the expected idempotency behavior for replaying the same key, but the harness incorrectly treated the old operation as a new test run.
- Classification: harness defect; no Admiral product defect inferred. The lane was interrupted before a result and is not counted as PASS or FAIL.
- Cleanup check: a later read-only guest inventory found no containers, pods, volumes, or failed systemd units. The replayed instance was already in terminal `deprovisioned` state.
- Fix under evaluation: generate a safe per-invocation run ID and include it in all customer/idempotency/resource suffixes. Evidence from the corrected complete lane is required before this helper issue is marked fixed.

Artifacts: `lane-incomplete.log`, `provision-replayed-operation.json`, `idempotency-replay.json`, and `runtime-inspection-empty.txt`. No credentials are included.
