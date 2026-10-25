#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo 'usage: issue-182-worker-marker.sh INSTANCE_ID MARKER' >&2; exit 2; }
instance_id=$1
marker=$2
[[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]] || { echo 'invalid instance ID' >&2; exit 2; }
[[ $marker =~ ^[A-Za-z0-9._-]{1,80}$ ]] || { echo 'invalid marker' >&2; exit 2; }

uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
runtime=(runuser -u admiral-apps -- env "HOME=$home" "XDG_RUNTIME_DIR=/run/user/$uid" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus")
container="admiral-${instance_id}-db"
sql="CREATE TABLE IF NOT EXISTS audit_restore_marker (marker text PRIMARY KEY); INSERT INTO audit_restore_marker(marker) VALUES ('$marker') ON CONFLICT (marker) DO NOTHING; SELECT marker FROM audit_restore_marker WHERE marker = '$marker';"
printf '%s\n' "$sql" | "${runtime[@]}" podman exec -i "$container" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1'
