#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exit 2
cd /
uid=$(id -u admiral-apps)
container=admiral-inst_9fbe80d771bcb0ce-db
runuser -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman exec "$container" sh -ec 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "UPDATE release_validation_marker SET marker = '''R26-FEDORA-MULTI-HARBOR-DIRTY-BEFORE-RESTORE''' WHERE marker = '''R26-FEDORA-MULTI-HARBOR-20261028''';"'
runuser -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman exec "$container" sh -ec 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT marker FROM release_validation_marker WHERE marker = '''R26-FEDORA-MULTI-HARBOR-DIRTY-BEFORE-RESTORE'''"'
