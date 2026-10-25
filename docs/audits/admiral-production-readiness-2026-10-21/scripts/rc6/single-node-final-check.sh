#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Final single-node state check; always run runtime-user commands from /.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: single-node-final-check.sh {el10|fc46}' >&2; exit 2; }
rpm_suffix=$1
cd /
printf 'final_check_start_utc=%s guest=%s boot_id=%s\n' \
  "$(date -u +%FT%TZ)" "$(hostname -s)" "$(cat /proc/sys/kernel/random/boot_id)"
failed=$(systemctl --failed --no-legend --no-pager)
printf 'failed_units=%s\n' "${failed:-none}"
[[ -z $failed ]]
for service in postgresql.service admirald.service admiral-fleet.service caddy.service admiral-harbor.service admiral-flagship.service; do
  state=$(systemctl is-active "$service")
  printf 'service=%s state=%s\n' "$service" "$state"
  [[ $state == active ]]
done
for package in admiral-common admirald admiral-fleet admiralctl admiral-harbor admiral-flagship; do
  actual=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$package")
  printf 'package=%s-%s\n' "$package" "$actual"
  [[ $actual == "0.0.1rc6-1.${rpm_suffix}" ]]
done
uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
app_env=(env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
run_app() { runuser -u admiral-apps -- "${app_env[@]}" "$@"; }
rootless=$(run_app podman info --format '{{.Host.Security.Rootless}}')
printf 'podman_rootless=%s\n' "$rootless"
[[ $rootless == true ]]
containers=$(run_app podman ps -a --format '{{.Names}}')
pods=$(run_app podman pod ps --format '{{.Name}}')
volumes=$(run_app podman volume ls --format '{{.Name}}')
printf 'final_rootless_containers=%s pods=%s volumes=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}"
[[ -z $containers && -z $pods && -z $volumes ]]
printf 'single_node_final_check=PASS end_utc=%s\n' "$(date -u +%FT%TZ)"
