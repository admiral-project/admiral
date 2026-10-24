#!/usr/bin/env bash
# Run the full Release 75 single-node E2E pass for one disposable guest.
set -u
[[ $# -eq 2 ]] || { echo "usage: $0 OS GUEST_IP" >&2; exit 2; }
os=$1
guest_ip=$2
case "$os" in rocky|centos|fedora) ;; *) echo "unsupported OS: $os" >&2; exit 2 ;; esac
repo_root=${R75_REPO_ROOT:-$(git rev-parse --show-toplevel)}
runtime=${R75_RUNTIME_ROOT:-"$repo_root/packaging/build/validation/rc5-r75/runtime"}
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
evidence="$runtime/single/$os"
: "${R75_SSH_KEY:?Set R75_SSH_KEY to the protected lab SSH private-key path}"
key=$R75_SSH_KEY
known_hosts_dir=${R75_KNOWN_HOSTS_DIR:-/var/lib/libvirt/images/admiral-validation/cloud-init}
known_hosts="$known_hosts_dir/adm-r75-$os-single/known_hosts"
guest="validator@$guest_ip"
node_id="adm-r75-$os-single"
[[ -r $key && -r $known_hosts ]] || { echo "missing SSH material for $os" >&2; exit 2; }
umask 077
exec > >(tee -a "$evidence/functional.log") 2>&1
chmod 0600 "$evidence/functional.log"
ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5)
remote() { ssh "${ssh_args[@]}" "$guest" "$@"; }
upload_fixture() {
  local source=$1 destination=$2
  remote "sudo install -o root -g root -m 0600 /dev/stdin '$destination'" < "$source"
}
run_guest_script() {
  local script=$1
  shift
  remote "sudo bash -s -- $*" < "$script"
}
failures=0
run_stage() {
  local label=$1 rc
  shift
  printf '\n=== %s start_utc=%s ===\n' "$label" "$(date -u +%FT%TZ)"
  if "$@"; then
    printf 'stage=%s result=PASS end_utc=%s\n' "$label" "$(date -u +%FT%TZ)"
  else
    rc=$?
    printf 'stage=%s result=FAIL exit=%s end_utc=%s\n' "$label" "$rc" "$(date -u +%FT%TZ)"
    failures=$((failures + 1))
  fi
}
do_lifecycle() {
  bash "$scripts/single-node-lifecycle.sh" "$key" "$known_hosts" "$guest_ip" "$node_id" "r75-$os"
}
do_resize() {
  upload_fixture "$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-resize.yaml" /tmp/audit-e2e-resize.yaml &&
    run_guest_script "$scripts/single-resize-functional.sh" "r75-resize-$os" "r75-resize-$os"
}
do_backup() {
  upload_fixture "$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-backup.yaml" /tmp/audit-e2e-backup.yaml &&
    run_guest_script "$scripts/single-backup-restore.sh" "$os" "r75-backup-$os" "r75-backup-$os"
}
do_control_plane() {
  upload_fixture "$repo_root/examples/apps/e2e-whoami.yaml" /tmp/audit-e2e-whoami.yaml &&
    run_guest_script "$scripts/single-control-plane-lifecycle.sh" "$os" "r75-control-$os" "r75-control-$os"
}
do_host_reboot() {
  ADMIRAL_RC_RELEASE=75 bash "$scripts/host-reboot.sh" "$os" "adm-r75-$os-single" "$guest" "$key" "$known_hosts" "r75-reboot-$os"
}
do_final_cleanup_check() {
  remote 'sudo bash -s --' <<'REMOTE'
set -euo pipefail
cd /tmp
failed=$(systemctl --failed --no-legend --no-pager)
printf 'failed_units=%s\n' "${failed:-none}"
[[ -z $failed ]]
for service in postgresql admirald admiral-fleet caddy admiral-harbor admiral-flagship; do
  systemctl is-active --quiet "$service"
done
uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
app_env=(env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
containers=$(runuser -u admiral-apps -- "${app_env[@]}" podman ps --all --format '{{.Names}}')
pods=$(runuser -u admiral-apps -- "${app_env[@]}" podman pod ps --format '{{.Name}}')
volumes=$(runuser -u admiral-apps -- "${app_env[@]}" podman volume ls --format '{{.Name}}')
printf 'final_rootless_containers=%s pods=%s volumes=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}"
[[ -z $containers && -z $pods && -z $volumes ]]
printf 'final_boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id)"
printf 'final_candidate_rpms=\n'
rpm -q admiral-common admirald admiral-fleet admiralctl admiral-harbor admiral-flagship
printf 'final_cleanup=PASS\n'
REMOTE
}

printf 'candidate=Release75 os=%s guest=%s node=%s start_utc=%s\n' "$os" "$guest_ip" "$node_id" "$(date -u +%FT%TZ)"
run_stage workload_create_idempotency_deprovision do_lifecycle
run_stage resize_data_continuity do_resize
run_stage backup_restore_checksum_negative_state do_backup
run_stage instance_and_admirald_lifecycle do_control_plane
run_stage host_reboot_persistence do_host_reboot
run_stage final_services_resources_rpms do_final_cleanup_check
printf 'single_node_lane=os:%s result:%s failed_stages:%s end_utc:%s\n' "$os" "$([[ $failures -eq 0 ]] && echo PASS || echo FAIL)" "$failures" "$(date -u +%FT%TZ)"
[[ $failures -eq 0 ]]
