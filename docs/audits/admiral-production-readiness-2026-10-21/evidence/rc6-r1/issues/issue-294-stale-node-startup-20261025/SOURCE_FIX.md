# Issue #294 — source fix and regression evidence

## Fix

- Component: `admirald`
- Commit: `0fd76b6c902cfae179cfe6fb3e685c935a350cf7` (`fix(api): reconcile stale workers before serving`)
- Change: before binding the API listener, run the existing two-minute stale-worker reconciliation synchronously. The periodic health monitor calls the same helper. Workers with fresh heartbeats remain active; workers with expired heartbeats become offline/degraded/unavailable until a new heartbeat recomputes their state.
- Regression: `internal/api/startup_health_test.go::TestStartupReconcileMarksStaleWorkersUnavailable` seeds one worker with a five-minute-old heartbeat and one fresh worker; it asserts stale→offline/degraded/unavailable and fresh→active/healthy/available.

## Verification

- Disposable PostgreSQL-backed targeted regression: PASS.
- Full component suite: `DATABASE_URL=postgres://... go test ./... -count=1 -p 1 -timeout 300s` — PASS across all packages.
- `go vet ./...` — PASS.
- `go build ./...` — PASS.
- GitHub component CI: [admirald run 40209830489](https://github.com/admiral-project/admirald/actions/runs/40209830489) — SUCCESS, including gofmt, vet, build, gosec/govulncheck steps and PostgreSQL-backed full tests.

## Still required

This source fix is not present in the installed RC6 Release 1 packages. Rebuild the six coordinated Admiral RPMs with the exact new component pin, validate the fix in local-Epoch Rocky and Fedora packages, then revalidate the no-Epoch candidate on fresh VMs. #294 remains open and `fix-proposed`; no package or matrix PASS is claimed here.
