#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo 'usage: issue-182-worker-marker-check.sh INSTANCE_ID MARKER' >&2; exit 2; }
instance_id=$1
marker=$2
[[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]] || { echo 'invalid instance ID' >&2; exit 2; }
[[ $marker =~ ^[A-Za-z0-9._-]{1,80}$ ]] || { echo 'invalid marker' >&2; exit 2; }

uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
container="admiral-${instance_id}-db"
result=$(runuser -u admiral-apps -- env "HOME=$home" "XDG_RUNTIME_DIR=/run/user/$uid" \
  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" \
  podman exec "$container" sh -c "psql -At -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -v ON_ERROR_STOP=1 -c \"SELECT marker FROM audit_restore_marker WHERE marker = '$marker'\"")
[[ $result == "$marker" ]] || { echo 'restored database marker mismatch' >&2; exit 1; }
printf 'restored_postgresql_marker=%s\n' "$result"
