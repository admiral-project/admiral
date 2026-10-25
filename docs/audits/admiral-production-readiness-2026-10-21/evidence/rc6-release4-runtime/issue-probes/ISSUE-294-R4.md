# Issue #294 — synchronous stale-worker reconciliation at control-plane startup

Date: 2026-10-25 UTC
Candidate: RC6 Release 4, Epoch 0 (`0.0.1rc6-4`)
Platforms: Rocky Linux 10.2 x86_64 and Fedora Rawhide 46 x86_64
Topology: real installed Single-Node guest per OS; the local worker record is persisted in PostgreSQL. This targeted test is not a full matrix cell.

## Procedure and expected result

The issue's failure mode is a stale worker left `active/healthy/available_for_provisioning=true` after a long control-plane outage, while admission separately rejects it as `metrics_stale`. On each guest, Fleet and `admirald` were stopped for 125 seconds (greater than the two-minute heartbeat threshold). `admirald` was then started while Fleet remained stopped. Before Fleet resumed, the persisted worker had to report `offline/degraded`, `available_for_provisioning=false`, and `heartbeat_timeout`. Fleet was then started, and the worker had to recover to `active/healthy/available_for_provisioning=true` with a fresh heartbeat and metrics timestamp.

## Results

**PASS on both exact RC6 Release 4 guests.** The worker was offline and unavailable as soon as the API returned after `admirald` startup, before Fleet was restarted. After Fleet resumed, both workers returned to active, healthy, and provisionable state.

| OS | Before interruption | After `admirald` start, Fleet still stopped | After Fleet recovery | Capture SHA-256 |
|---|---|---|---|---|
| Rocky 10.2 | `active/healthy/available=true` | `offline/degraded/available=false`, reason `heartbeat_timeout`; heartbeat remained `2026-10-25T21:04:46.835784Z` | `active/healthy/available=true`, fresh timestamp `2026-10-25T21:07:17.220965Z` | `e1bc09d1e792ce54411ea7b205fc1297b0fbeaacc3e442d7c173db50414eeb30` |
| Fedora Rawhide 46 | `active/healthy/available=true` | `offline/degraded/available=false`, reason `heartbeat_timeout`; heartbeat remained `2026-10-25T21:01:51.824479Z` | `active/healthy/available=true`, fresh timestamp `2026-10-25T21:04:35.088243Z` | `de4c2ae25fd235d4f31a2136715c1e5155e1c6f5633b3f46d09af2c0bcf043e1` |

Primary captures are `issue-294-rocky/startup-reconcile.log` and `issue-294-fedora/startup-reconcile.log`; each log includes the exact-candidate label and observed state transitions. `scripts/validate-release-refs.py` confirms the Release 4 component pins, including `admirald` `0fd76b6c902cfae179cfe6fb3e685c935a350cf7`.

## Harness attempt retained

The first Fedora attempt successfully restarted `admirald`, but its ad hoc parser indexed `unavailable_reason_codes` instead of treating that JSON field as optional. It exited with `KeyError` before printing the record; that attempt is **not counted**. Fleet was manually restored immediately, and a subsequent query confirmed normal recovery. The corrected rerun uses `.get()` for optional fields and passed the full stop/start sequence. The first-attempt error and disposition are retained in [`harness-attempt-1-NOT-COUNTED.txt`](issue-294-fedora/harness-attempt-1-NOT-COUNTED.txt) (SHA-256 `66dd8f4c8d2679fbbcd33a5bd49c981eebcc257dfcaf4b344be3f6335f1176e7`). It is not evidence of an Admiral failure or a passing test.

## Scope and disposition

This closes the exact-candidate Single-Node check for #294 on Rocky and Fedora. The issue remains open pending its Multi-Node control-plane restart coverage and remaining release matrix gates. No matrix cell credit is awarded by this targeted probe.
