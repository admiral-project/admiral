#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run as root on Worker' >&2; exit 2; }
cd /

instance=inst_9fbe80d771bcb0ce
container="admiral-${instance}-db"
marker=R26-FEDORA-MULTI-HARBOR-20261028
uid=$(id -u admiral-apps)

result=$(runuser -u admiral-apps -- env \
    HOME=/var/lib/admiral-apps \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    podman exec "$container" sh -ec \
    'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT marker FROM release_validation_marker WHERE marker = '\''R26-FEDORA-MULTI-HARBOR-20261028'\''"')
[[ $result == "$marker" ]]
printf 'persisted_marker=%s\n' "$result"
