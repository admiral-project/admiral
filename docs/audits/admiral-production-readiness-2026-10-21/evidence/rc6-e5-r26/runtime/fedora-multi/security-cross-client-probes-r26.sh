#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run as root on Worker' >&2; exit 2; }

instance_a=${INSTANCE_A:-inst_f2af615d40c7ed70}
instance_b=${INSTANCE_B:-inst_8ee0351ddf00e745}
worker_wg_ip=10.99.0.2
uid=$(id -u admiral-apps)
apps_env=(
    HOME=/var/lib/admiral-apps
    XDG_RUNTIME_DIR="/run/user/$uid"
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
)
as_apps() { runuser -u admiral-apps -- env "${apps_env[@]}" "$@"; }

a_app="admiral-${instance_a}-app"
a_db="admiral-${instance_a}-db"
a_infra="admiral-${instance_a}-infra"
b_app="admiral-${instance_b}-app"
b_db="admiral-${instance_b}-db"
b_infra="admiral-${instance_b}-infra"
probe_file=.admiral-r26-cross-client-probe
write_probe_file=.admiral-r26-cross-client-write-probe

for container in "$a_app" "$a_db" "$a_infra" "$b_app" "$b_db" "$b_infra"; do
    as_apps podman container exists "$container"
done

get_pid() { as_apps podman inspect --format '{{.State.Pid}}' "$1"; }
a_app_pid=$(get_pid "$a_app")
b_app_pid=$(get_pid "$b_app")
a_infra_pid=$(get_pid "$a_infra")
b_infra_pid=$(get_pid "$b_infra")

read -r _ a_uid_start a_uid_count <"/proc/$a_app_pid/uid_map"
read -r _ b_uid_start b_uid_count <"/proc/$b_app_pid/uid_map"
(( a_uid_start + a_uid_count <= b_uid_start || b_uid_start + b_uid_count <= a_uid_start ))
printf 'userns_ranges_non_overlapping=yes A=%s+%s B=%s+%s\n' \
    "$a_uid_start" "$a_uid_count" "$b_uid_start" "$b_uid_count"

a_net=$(readlink "/proc/$a_infra_pid/ns/net")
b_net=$(readlink "/proc/$b_infra_pid/ns/net")
a_pidns=$(readlink "/proc/$a_app_pid/ns/pid")
b_pidns=$(readlink "/proc/$b_app_pid/ns/pid")
[[ $a_net != "$b_net" && $a_pidns != "$b_pidns" ]]
printf 'network_namespaces_distinct=yes\n'
printf 'pid_namespaces_distinct=yes\n'

a_label=$(as_apps podman inspect --format '{{.ProcessLabel}}' "$a_app")
b_label=$(as_apps podman inspect --format '{{.ProcessLabel}}' "$b_app")
[[ -n $a_label && -n $b_label && $a_label != "$b_label" ]]
printf 'selinux_mcs_labels_distinct=yes\n'

a_volume=$(as_apps podman inspect --format \
    '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}' "$a_db")
b_volume=$(as_apps podman inspect --format \
    '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}' "$b_db")
[[ -n $a_volume && -n $b_volume && $a_volume != "$b_volume" ]]
printf 'postgres_volume_paths_distinct=yes\n'
a_host_owner=$(stat -c '%u:%g' "$a_volume/PG_VERSION")
b_host_owner=$(stat -c '%u:%g' "$b_volume/PG_VERSION")
a_container_owner=$(as_apps podman exec "$a_db" stat -c '%u:%g' /var/lib/postgresql/data/PG_VERSION)
b_container_owner=$(as_apps podman exec "$b_db" stat -c '%u:%g' /var/lib/postgresql/data/PG_VERSION)
printf 'volume_owner_translation_A=container:%s host:%s\n' "$a_container_owner" "$a_host_owner"
printf 'volume_owner_translation_B=container:%s host:%s\n' "$b_container_owner" "$b_host_owner"
[[ $a_host_owner != "$b_host_owner" ]]
printf 'host_volume_owners_distinct=yes\n'

cleanup_probe() {
    as_apps podman exec "$b_db" rm -f "/var/lib/postgresql/data/$probe_file" >/dev/null 2>&1 || true
    as_apps podman exec "$b_db" rm -f "/var/lib/postgresql/data/$write_probe_file" >/dev/null 2>&1 || true
}
trap cleanup_probe EXIT
as_apps podman exec "$b_db" sh -ec \
    "printf '%s' 'customer-b-volume-probe' > '/var/lib/postgresql/data/$probe_file'"
if as_apps podman exec "$a_db" test -e "/var/lib/postgresql/data/$probe_file"; then
    echo 'customer_a_saw_customer_b_volume_marker=yes' >&2
    exit 1
fi
printf 'customer_a_cannot_see_customer_b_volume_marker=yes\n'

if as_apps podman exec "$a_db" sh -ec 'test -r "$1/PG_VERSION"' sh "$b_volume"; then
    echo 'customer_a_read_customer_b_host_volume=yes' >&2
    exit 1
fi
printf 'customer_a_cannot_read_customer_b_host_volume=yes\n'
if as_apps podman exec "$a_db" sh -ec 'touch "$1"' sh "$b_volume/$write_probe_file"; then
    echo 'customer_a_wrote_customer_b_host_volume=yes' >&2
    exit 1
fi
printf 'customer_a_cannot_modify_customer_b_host_volume=yes\n'

a_secret_hash=$(as_apps podman exec "$a_db" sh -ec \
    'test -n "$POSTGRES_PASSWORD"; printf %s "$POSTGRES_PASSWORD" | sha256sum | cut -d" " -f1')
b_secret_hash=$(as_apps podman exec "$b_db" sh -ec \
    'test -n "$POSTGRES_PASSWORD"; printf %s "$POSTGRES_PASSWORD" | sha256sum | cut -d" " -f1')
[[ -n $a_secret_hash && -n $b_secret_hash && $a_secret_hash != "$b_secret_hash" ]]
printf 'postgres_passwords_distinct_without_disclosure=yes\n'
for pair in \
    "$a_db|admiral-${instance_b}-db-POSTGRES_PASSWORD" \
    "$b_db|admiral-${instance_a}-db-POSTGRES_PASSWORD"; do
    db=${pair%%|*}
    peer_secret=${pair#*|}
    if ! as_apps podman exec "$db" sh -ec \
        'test ! -r "/run/secrets/$1" && ! printenv "$1" >/dev/null 2>&1' \
        sh "$peer_secret"; then
        echo 'cross_customer_secret_was_visible=yes' >&2
        exit 1
    fi
done
printf 'cross_customer_secret_paths_and_names_unavailable=yes\n'

for db in "$a_db" "$b_db"; do
    check=$(as_apps podman exec --env CHECK_UID="$uid" "$db" sh -ec '
for socket in "/run/user/$CHECK_UID/podman/podman.sock" "/run/podman/podman.sock" "/run/user/$CHECK_UID/bus"; do
    if [ -S "$socket" ]; then echo visible; exit 1; fi
done
if command -v podman >/dev/null 2>&1; then echo podman_cli_present; exit 1; fi
echo absent
')
    [[ $check == absent ]]
done
printf 'runtime_podman_and_systemd_control_interfaces_absent_in_db_containers=yes\n'

for db in "$a_db" "$b_db"; do
    ports=$(as_apps podman port "$db" 5432/tcp 2>&1 || true)
    [[ $ports == *'failed to find published port "5432/tcp"'* ]]
done
if as_apps podman exec "$a_db" pg_isready -h "$worker_wg_ip" -p 5432 -t 3 >/dev/null 2>&1; then
    echo 'customer_a_reached_worker_database_port=yes' >&2
    exit 1
fi
printf 'postgres_5432_not_published_or_reachable_from_customer_a=yes\n'

printf 'SELinux_mode=%s\n' "$(getenforce)"
