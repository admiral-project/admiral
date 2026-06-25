# Session: Gitea provisioning — healthcheck, container user, and setup_command

## Problem

Gitea provisioning via `admiralctl instances provision --app gitea` failed at the setup_command stage. Three root causes were identified and fixed sequentially.

## Root Causes & Fixes

### 1. Healthcheck detection: JSON status format mismatch

`serviceReadyCheck` in `admiral-fleet/internal/executor/executor_provision.go` searched for `"status":"running"` (no space, no capital S) in `podman container inspect` output. Real podman output is `"Status": "running"` (capital S, space after colon).

**Fix:** Switched to `json.Unmarshal` via `extractContainerStatus()` with raw-string fallback.

### 2. D-Bus Connection reset by peer from systemd-run --machine

`runAsUserWithStdinTrusted` unconditionally used `systemd-run --machine` for all podman commands. From within the fleet service (`PrivateTmp`, `ProtectControlGroups`, etc.), `systemd-run --machine` fails with `Connection reset by peer` / `Transport endpoint is not connected`.

**Fix:** Applied the same pattern as the non-trusted path:
- `podman run` → `runuser` with `XDG_RUNTIME_DIR` (works)
- `podman exec` → `systemd-run --machine` (needed for Quadlet cgroup access)

### 3. Gitea refuses to run as root

The Gitea binary (inside the container) refuses to run as root with: `Gitea is not supposed to be run as root. Sorry.`

Gitea's Docker entrypoint normally drops privileges to the `git` user (UID 1000) via s6. The one-shot transient containers used by `setup_command` bypass the entrypoint, so they ran as root.

**Fix:** Added an optional `user` field to the app definition YAML, threaded through `ServiceInfo` → `podman run --user <value>`. Gitea needs `user: "1000"`.

### 4. Gitea CLI needs installed config file

`gitea admin user create` (and even `gitea migrate`) fail with `Unable to load config file for a installed Gitea instance` because Gitea requires `/data/gitea/conf/app.ini` to exist with `INSTALL_LOCK = true`.

**Fix:** Updated `setup_command` in `gitea.yaml` to generate `app.ini` from environment variables before running `gitea migrate` and the admin user creation.

### 5. Gitea web Quadlet container also ran as root

The Quadlet `[Container]` section had no `User=` key, so the Gitea `web` service started as root and failed. Reverted — Gitea's entrypoint handles user switching internally, so the Quadlet container should run as root and let the entrypoint drop privileges via s6.

## Changes Made

### admiral-fleet

- `internal/podman/inspector.go`: Added `containerUser` parameter to `RunTrustedInPod`, `RunTrustedInPodNoEntrypoint`, `RunTrustedShellInPod` for `--user` support.
- `internal/executor/executor_helpers.go`: Threaded `svc.User` through `runServiceCommand*` helpers.
- `internal/executor/executor_provision.go`:
  - Added `extractContainerStatus` for robust JSON-based status detection.
  - Added per-attempt error logging in `waitForServiceReady` loop.
  - `RunTrustedInPod` calls in trusted path now use `runuser` instead of `systemd-run --machine`.

### admirald

- `pkg/admiral/api.go`: Added `User` field to `YAMLService`.
- `pkg/admiral/tasks.go`: Added `User` field to `ServiceInfo`.
- `internal/api/tier_env.go`: Mapped `User` from YAML to task struct.

### App definitions

- `examples/apps/gitea.yaml`: Added `user: "1000"`, `requires: [db]`, `healthcheck_wait_timeout: 180`, updated `setup_command` with `app.ini` creation.
- `examples/apps/erpnext.yaml`: Added `requires` to backend, setup, scheduler, worker-default; `depends_on` + `requires` from frontend to backend; `healthcheck_wait_timeout: 180` for db.
- `examples/apps/wordpress.yaml`: Added `healthcheck_wait_timeout: 120` for web service.

### Documentation

- `docs/app-definition-v1.md`: Documented `user` field and added setup_command example with non-root user.

## Key Decisions

1. Use `json.Unmarshal` instead of raw string search for container status detection.
2. Avoid `systemd-run --machine` for `podman run` commands from fleet; use `runuser` with `XDG_RUNTIME_DIR`. Only `podman exec` needs `systemd-run --machine` (Quadlet cgroup access).
3. Add an optional `user` field to `ServiceInfo` for per-service container UID. Only applies to one-shot transient containers (setup_command, healthchecks), not to Quadlet services (entrypoints handle user switching).

## Environment

- Podman 5.8.3
- CentOS Stream 10 (EL10 Tier 1)
- SELinux Enforcing
- systemd 257
