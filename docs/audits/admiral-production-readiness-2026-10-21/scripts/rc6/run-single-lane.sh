#!/usr/bin/env bash
# Run the RC6 secure Single-Node functional sequence on one disposable guest.
set -u
[[ $# -eq 3 ]] || { echo "usage: $0 {rocky|alma|centos|fedora} GUEST_IP GUEST_NAME" >&2; exit 2; }
os=$1 guest_ip=$2 guest_name=$3
case "$os" in rocky|alma|centos|fedora) ;; *) echo "unsupported OS: $os" >&2; exit 2 ;; esac
[[ $guest_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'invalid guest IPv4' >&2; exit 2; }
[[ $guest_name =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || { echo 'invalid guest name' >&2; exit 2; }
expected_epoch=${RC6_EXPECTED_EPOCH:-5}
[[ $expected_epoch =~ ^[0-9]{1,4}$ ]] || { echo 'RC6_EXPECTED_EPOCH must be an RPM Epoch integer' >&2; exit 2; }
package_release=${RC6_PACKAGE_RELEASE:-11}
[[ $package_release =~ ^[0-9]+$ ]] || { echo 'RC6_PACKAGE_RELEASE must be an RPM Release integer' >&2; exit 2; }
run_id=${RC6_RUN_ID:-$(date -u +%y%m%d%H%M%S)$(printf '%04d' "$((RANDOM % 10000))")}
[[ $run_id =~ ^[A-Za-z0-9_.-]{1,16}$ ]] || { echo 'RC6_RUN_ID must contain 1-16 safe characters' >&2; exit 2; }
repo_root=$(git rev-parse --show-toplevel)
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runtime=${RC6_RUNTIME_ROOT:-/var/lib/libvirt/images/admiral-validation/evidence/rc6-r1}
evidence="$runtime/functional/${os}-single"
key=${RC6_SSH_KEY:-/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519}
known_hosts="${RC6_KNOWN_HOSTS_DIR:-/var/lib/libvirt/images/admiral-validation/cloud-init}/$guest_name/known_hosts"
node_id="$guest_name"
guest="validator@$guest_ip"
[[ -r $key && -r $known_hosts ]] || { echo 'SSH key or pinned known_hosts is unavailable' >&2; exit 1; }
[[ ! -e $evidence ]] || { echo "refusing to overwrite existing evidence: $evidence" >&2; exit 1; }
umask 077
mkdir -p "$evidence"
chmod 0700 "$evidence"
: >"$evidence/lane.log"
chmod 0600 "$evidence/lane.log"
exec > >(tee -a "$evidence/lane.log") 2>&1
ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5)
remote() { ssh "${ssh_args[@]}" "$guest" "$@"; }
upload_fixture() { local source=$1 destination=$2; remote "sudo install -o root -g root -m 0600 /dev/stdin '$destination'" <"$source"; }
run_guest_script() { local script=$1; shift; remote "sudo bash -s -- $*" <"$script"; }
failures=0
run_stage() {
  local label=$1 rc
  shift
  printf '\n=== stage=%s start_utc=%s ===\n' "$label" "$(date -u +%FT%TZ)"
  if "$@"; then
    printf 'stage=%s result=PASS end_utc=%s\n' "$label" "$(date -u +%FT%TZ)"
  else
    rc=$?
    printf 'stage=%s result=FAIL exit=%s end_utc=%s\n' "$label" "$rc" "$(date -u +%FT%TZ)"
    failures=$((failures + 1))
  fi
}
do_lifecycle() {
  bash "$scripts/single-node-lifecycle.sh" "$key" "$known_hosts" "$guest_ip" "$node_id" "rc6-${os}-life-${run_id}"
}
do_resize() {
  upload_fixture "$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-resize.yaml" /tmp/rc6-e2e-resize.yaml &&
    remote 'sudo mv /tmp/rc6-e2e-resize.yaml /tmp/audit-e2e-resize.yaml' &&
    run_guest_script "$scripts/single-resize-functional.sh" "rc6-resize-${os}-${run_id}" "rc6-resize-${os}-${run_id}"
}
do_backup() {
  upload_fixture "$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-backup.yaml" /tmp/rc6-e2e-backup.yaml &&
    remote 'sudo mv /tmp/rc6-e2e-backup.yaml /tmp/audit-e2e-backup.yaml' &&
    run_guest_script "$scripts/single-backup-restore.sh" "$os" "rc6-backup-${os}-${run_id}" "rc6-backup-${os}-${run_id}"
}
do_control_plane() {
  upload_fixture "$repo_root/examples/apps/e2e-whoami.yaml" /tmp/rc6-e2e-whoami.yaml &&
    remote 'sudo mv /tmp/rc6-e2e-whoami.yaml /tmp/audit-e2e-whoami.yaml' &&
    run_guest_script "$scripts/single-control-plane-lifecycle.sh" "$os" "rc6-control-${os}-${run_id}" "rc6-control-${os}-${run_id}"
}
do_host_reboot() {
  ADMIRAL_RC_RELEASE=$package_release bash "$scripts/host-reboot.sh" "$os" "$guest_name" "$guest" "$key" "$known_hosts" "rc6-reboot-${os}-${run_id}"
}
do_final_check() {
  expected_dist=$(case "$os" in rocky|centos|alma) echo el10 ;; fedora) echo fc46 ;; esac)
remote sudo bash -s -- "$expected_epoch" "$package_release" "$expected_dist" <<'REMOTE'
set -euo pipefail
expected_epoch=$1 expected_release=$2 expected_dist=$3
cd /
failed=$(systemctl --failed --no-legend --no-pager)
printf 'failed_units=%s\n' "${failed:-none}"
[[ -z $failed ]]
for service in postgresql.service admirald.service admiral-fleet.service caddy.service admiral-harbor.service admiral-flagship.service; do
  systemctl is-active --quiet "$service"
done
for package in admiral-common admirald admiral-fleet admiralctl admiral-harbor admiral-flagship; do
  rpm -q --qf '%{EPOCHNUM}:%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$package"
  actual=$(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$package")
  [[ $actual == "$expected_epoch:0.0.1rc6-$expected_release.$expected_dist" ]]
done
uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
app_env=(env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
containers=$(runuser -u admiral-apps -- "${app_env[@]}" podman ps -a --format '{{.Names}}')
pods=$(runuser -u admiral-apps -- "${app_env[@]}" podman pod ps --format '{{.Name}}')
volumes=$(runuser -u admiral-apps -- "${app_env[@]}" podman volume ls --format '{{.Name}}')
printf 'final_rootless_containers=%s pods=%s volumes=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}"
[[ -z $containers && -z $pods && -z $volumes ]]
printf 'final_boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id)"
REMOTE
}

root_commit=$(git -C "$repo_root" rev-parse HEAD)
printf 'candidate=0.0.1rc6-%s epoch=%s os=%s guest=%s node=%s run_id=%s root_commit=%s start_utc=%s\n' \
  "$package_release" "$expected_epoch" "$os" "$guest_ip" "$node_id" "$run_id" "$root_commit" "$(date -u +%FT%TZ)"
for ref in ADMIRALD_COMMIT FLEET_COMMIT ADMIRALCTL_COMMIT FLAGSHIP_COMMIT HARBOR_COMMIT; do
  printf '%s=%s\n' "$ref" "$(sed -n "s/^$ref := //p" "$repo_root/Makefile")"
done
run_stage workload_create_idempotency_deprovision do_lifecycle
run_stage resize_data_continuity do_resize
run_stage backup_restore_checksum_negative_state do_backup
run_stage instance_and_admirald_lifecycle do_control_plane
run_stage host_reboot_persistence do_host_reboot
run_stage final_services_resources_rpms do_final_check
printf 'single_node_lane=os:%s result:%s failed_stages:%s end_utc:%s\n' \
  "$os" "$([[ $failures -eq 0 ]] && echo PASS || echo FAIL)" "$failures" "$(date -u +%FT%TZ)"
[[ $failures -eq 0 ]]
