# RC6 Release 1 — stale node availability after a cold Single-Node restart

**Observed FAIL: node-list availability was inconsistent with the admission decision.** The provision was safely rejected, so no unapproved workload was created. This is separate from the earlier test-helper idempotency issue and is tracked by GitHub #294.

## Candidate and environment

- Fedora Rawhide 46 x86_64 guest `rc6r1fedora-single`, `192.168.122.209`.
- Exact native Fedora packages installed: all six `0:0.0.1rc6-1.fc46`; no EL10 RPMs were installed.
- RPM candidate root source: `267da7ebd739a0703c276ec8d4770ffa31a45f25`; components match the RC6 Release 1 manifest.
- Runner source: root `e11b88878333b7a4bd7eadfa3f5c477bfca0b179`, run ID `2610251553374719`.

## Reproduction and result

The VM had been shut down while its stored node record still contained the previous active/healthy/available state. On cold boot, the helper queried `admiralctl nodes list --output json` before a fresh Fleet metrics report. The worker record still showed `status=active`, `health_status=healthy`, `available_for_provisioning=true`, while `last_metrics_at` was `2026-10-25T13:25:11Z` (over two hours old). The immediate provision request was rejected with code `no_node_available_for_requested_tier` and reason `metrics_stale`. About three seconds later, a fresh heartbeat/metrics report allowed the next scenario to provision.

The first lifecycle stage is recorded as FAIL in the lane; it is not counted as PASS. The subsequent resize, backup/restore, control-plane lifecycle, real reboot/recovery and final clean-inventory stages passed. The whole lane therefore remains FAIL, not a Fedora cell pass. The guest ended with no containers, pods, volumes or failed systemd units.

## Cause assessment

Confirmed behavior: `provision` evaluates freshness at request time and fails closed; the node-list endpoint exposed persisted availability from before shutdown. Source inspection shows the health monitor calls `MarkNodesOffline(2m)` on a 30-second ticker, without a synchronous stale-worker reconciliation before the server accepts requests. This explains the brief mismatch. No lost data or unauthorized workload was observed.

## Reproduction artifacts

- `nodes-list-before-failed-provision.json`
- `provision-rejection.json`
- `admirald-startup-window.log` (credentials redacted)
- `fedora-lane-failed-precondition.log` (full lane output including all passing later stages and final cleanup)

The source-level fix and regression are pending; this report does not claim #294 resolved.
