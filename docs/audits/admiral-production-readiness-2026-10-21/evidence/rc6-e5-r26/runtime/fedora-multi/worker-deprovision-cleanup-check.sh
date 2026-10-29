#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exit 2
cd /
instance=inst_9fbe80d771bcb0ce
uid=$(id -u admiral-apps)
run_as_apps() { runuser -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"; }
containers=$(run_as_apps podman ps -a --format '{{.Names}}' | grep -F "$instance" || true)
pods=$(run_as_apps podman pod ps --format '{{.Name}}' | grep -F "$instance" || true)
volumes=$(run_as_apps podman volume ls --format '{{.Name}}' | grep -F "$instance" || true)
secrets=$(run_as_apps podman secret ls --format '{{.Name}}' | grep -F "$instance" || true)
units=$(runuser -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user list-units --all --no-legend 2>/dev/null | grep -F "$instance" || true)
quadlets=$(find /var/lib/admiral-apps/.config/containers/systemd -maxdepth 1 -iname "*$instance*" -print 2>/dev/null || true)
data_paths=$(find /var/lib/admiral-apps -maxdepth 4 -iname "*$instance*" -print 2>/dev/null || true)
printf 'worker_containers=%s
worker_pods=%s
worker_volumes=%s
worker_secrets=%s
test_user_units=%s
worker_quadlet_files=%s
worker_instance_data_paths=%s
' "${containers:-none}" "${pods:-none}" "${volumes:-none}" "${secrets:-none}" "${units:-none}" "${quadlets:-none}" "${data_paths:-none}"
[[ -z $containers && -z $pods && -z $volumes && -z $secrets && -z $units && -z $quadlets && -z $data_paths ]]
awk '/MemAvailable:/ {printf "worker_mem_available_mib=%d\n", $2/1024}' /proc/meminfo
df -B1 --output=avail / | tail -n 1 | awk '{printf "worker_disk_available_gib=%.1f\n", $1/1073741824}'
