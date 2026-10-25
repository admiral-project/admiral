# Issue #294 — RC6 Epoch 4 diagnostic startup regression

**Result: PASS for the #294 fix-specific runtime check. This is diagnostic evidence, not a release-matrix cell or release sign-off.**

## Candidate and build

- Root commit: `e4a43dd8b64b999186f2906ce153bce26f31e8f2`.
- `admirald` fix commit: `0fd76b6c902cfae179cfe6fb3e685c935a350cf7` (`origin/main`). The server reconciles stale workers before accepting API requests; the regression test is `internal/api/startup_health_test.go::TestStartupReconcileMarksStaleWorkersUnavailable`.
- Other component pins are recorded in `el10-source-pins.txt` and `fedora-source-pins.txt`; `scripts/validate-release-refs.py` passed before both builds.
- The same six-package set was built on native Rocky Linux 10.2 (`.el10`) and native Fedora 46 Rawhide (`.fc46`). No EL10 binaries were installed on Fedora.
- All packages are diagnostic `Epoch 4`, `Version 0.0.1rc6`, `Release 2`. Per-package NEVRA and SHA-256 are in `el10-rpm-manifest.tsv` and `fedora-rpm-manifest.tsv`. These Epoch-bearing RPMs are local-only and must not be published.
- All six `%check` stages passed on each builder: Admirald/Fleet/CLI Go tests and architecture checks, Flagship 266/266, Harbor 352/352. Root regression suite passed 159/159. Root CI for `e4a43dd` passed in run `40210372782`; the `admirald` fix commit's component CI passed in run `40209830489`.

## Fedora Rawhide cold-start reproduction

- Guest `rc6e4-fedora-single`, Fedora Rawhide 46 x86_64, built from seed `Fedora-Rawhide-seed-20261025-rc6-updated.x86_64.qcow2` (seed SHA-256: `01f5a6772943027a35b429e3a40d28de6ed22cb92f3d00e3858517269a992b1e`). The seed had already passed `qemu-img check` with no errors.
- The secure `admiral-install --single-node --validation-seed` setup completed in 381 seconds: Ansible recap 237 OK, 98 changed, zero failed/unreachable. Python helper RPM versions were unchanged by Admiral installation.
- Before the outage, the worker was `active/healthy/available`; its last heartbeat and metrics timestamp were `2026-10-25T16:33:31.178858Z`. Fleet was disabled while that persisted state was still fresh. The guest shut down at `16:34:04Z`, retaining that active state in PostgreSQL.
- The guest remained off for more than the two-minute stale-heartbeat threshold. At `16:36:19Z` it was started; at `16:36:54Z`, with `admirald` active and Fleet still inactive, the worker inventory reported `status=offline`, `health_status=degraded`, `available_for_provisioning=false`, reason `heartbeat_timeout`. Its stored metrics timestamp was unchanged. The stale worker was not exposed as available during startup.
- Fleet was re-enabled at `16:37:18Z`. By `16:37:31Z`, the same worker had a fresh heartbeat/metrics timestamp and returned to `active/healthy/available`.

This matches the expected result for #294: an old persisted worker state is invalidated before API service, then normal Fleet heartbeat restores availability. Raw install/build logs, before/after inventories, shutdown/recovery timing, source pins, package manifests, and their hashes are retained alongside this report.

## Scope and limits

- This validates the #294 behavior on Fedora Rawhide using the local diagnostic Epoch package. The formal release matrix remains **0/6**; no cell receives credit from an Epoch build.
- Rocky runtime and final no-Epoch candidate revalidation remain outstanding. The coordinated final candidate must use the next valid no-Epoch package EVR; RC6 Release 1 is invalidated by the original Fedora failure.
- No live or sandbox PayPal flow was run. PayPal issue #106 is excluded from this round. Any PayPal unit tests included by the package's generic `%check` are not provider or billing-flow validation.
