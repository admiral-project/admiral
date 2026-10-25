# RC6 Release 1 Rocky Linux 10 Single-Node repeated functional lane

**Result: both complete six-stage functional runs PASS on the same guest and exact installed candidate.** This resolves the stale idempotency-key harness behavior for this runner, but does not by itself certify production readiness or clear unrelated issue-specific gates.

## Identity and method

- Guest: `rc6r1rocky-single`, Rocky Linux 10.2 x86_64, `192.168.122.208`.
- Installed set: six exact RPMs, each `0:0.0.1rc6-1.el10` (Go packages x86_64; Python/common packages noarch). The lane log prints each NEVRA at final check.
- RPM candidate root source: `267da7ebd739a0703c276ec8d4770ffa31a45f25`; component pins match the previously recorded candidate manifest.
- Validation harness source: `f70e45fee85043cde3eadf725df173488bbdac2a`.
- The first invocation used generated run ID `2610251542030402`; the second explicitly used `R1rockyRetry2`. Each invocation had a separate protected evidence directory.
- Commands used the same native Rocky guest and candidate:
  `RC6_EXPECTED_EPOCH=0 RC6_PACKAGE_RELEASE=1 bash scripts/rc6/run-single-lane.sh rocky 192.168.122.208 rc6r1rocky-single`
  and the second invocation added `RC6_RUN_ID=R1rockyRetry2` plus a separate `RC6_RUNTIME_ROOT`.

## Results

Both complete invocations passed all six stages:

1. Provision, same-key idempotent replay, HTTP 200, SQL marker, deprovision and empty matching resource inventory.
2. Resize small→medium→small with HTTP 200 and SQL marker preserved.
3. Database backup/checksum, expected HTTP 409 when restoring a running app, pause/restore, original SQL marker recovery, artifact deletion and cleanup.
4. Pause/resume/stop/start/restart and Admirald stop/start lifecycle with API availability checks.
5. Real guest reboot with a changed boot ID, workload/SQL recovery, HTTP 200 and deprovision.
6. Exact RPM NEVRAs, no failed systemd units, and empty rootless container/pod/volume inventories.

Each raw lane log ends `single_node_lane=os:rocky result:PASS failed_stages:0`. The test starts and ends are timestamped in the logs. No secrets are present.

## Scope limit

This verifies repeatable functional Single-Node behavior on Rocky for this exact candidate. It does not complete the Multi-Node matrix, other OS cells, broader stress/security/fault audit, or every issue-specific gate. Keep overall release status NOT VALIDATED until those gates pass. The earlier static-key attempt is preserved separately as an incomplete harness reproduction and is not counted as a product failure.
