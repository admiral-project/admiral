#!/usr/bin/env bash
# Reproduce issue #202 against an installed RC6 candidate on a disposable guest.
set -euo pipefail

[[ $# -eq 4 ]] || { echo 'usage: issue-202-volume-backup.sh SSH_KEY KNOWN_HOSTS GUEST_IP RUN_ID' >&2; exit 2; }
key=$1 known_hosts=$2 guest_ip=$3 run_id=$4
[[ $run_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,30}$ ]] || { echo 'invalid run id' >&2; exit 2; }
repo_root=$(git rev-parse --show-toplevel)
fixture="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-backup-policy.yaml"
evidence="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-epoch5-release4/issue-acceptance/rocky-single/issue-202"
mkdir -p "$evidence"
chmod 0700 "$evidence"
log="$evidence/volume-backup-$run_id.log"
[[ ! -e $log ]] || { echo "refusing to overwrite $log" >&2; exit 1; }
umask 077
exec > >(tee "$log") 2>&1

ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts")
guest="validator@$guest_ip"
remote() { ssh "${ssh_args[@]}" "$guest" "$@"; }
printf 'test=ISSUE-202 candidate=5:0.0.1rc6-4.el10 guest=%s run_id=%s start_utc=%s\n' "$guest_ip" "$run_id" "$(date -u +%FT%TZ)"
scp "${ssh_args[@]}" "$fixture" "$guest:/tmp/rc6-issue-202-fixture.yaml"

remote 'sudo bash -s' "$run_id" <<'REMOTE'
set -euo pipefail
cd /
run_id=$1
run_dir="/var/tmp/admiral-issue-202-$run_id"
install -d -m 0700 "$run_dir"
fixture=/tmp/rc6-issue-202-fixture.yaml
install -o root -g root -m 0600 "$fixture" "$run_dir/app.yaml"
sed -i 's/restore_allowed: false/restore_allowed: true/' "$run_dir/app.yaml"
admiralctl apps apply --file "$run_dir/app.yaml" >"$run_dir/apply.json"
cat "$run_dir/apply.json"
customer="rc6-202-$run_id"
admiralctl instances provision --app e2e-backup-policy --tier free --customer "$customer" --idempotency-key "$customer" --wait --wait-timeout 10m --quiet --output json >"$run_dir/provision.json"
cat "$run_dir/provision.json"
instance_id=$(python3 - "$run_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x.get('status')=='succeeded',x
print(x['instance_id'])
PY
)
completed=0
fleet_stopped=0
symlink_path=
cleanup() {
  rc=$?
  trap - EXIT
  if (( fleet_stopped )); then systemctl start admiral-fleet.service || rc=1; fi
  if [[ -n ${symlink_path:-} && -L $symlink_path ]]; then rm -f -- "$symlink_path"; fi
  if [[ -n ${instance_id:-} ]]; then
    admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 10m --output json >"$run_dir/deprovision.json" 2>&1 || rc=1
    cat "$run_dir/deprovision.json"
  fi
  rm -f -- "$fixture"
  printf 'cleanup_exit=%s\n' "$rc"
  exit "$rc"
}
trap cleanup EXIT

uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
app_env=(env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
app_container="admiral-${instance_id}-app"
for attempt in $(seq 1 36); do
  if runuser -u admiral-apps -- "${app_env[@]}" podman inspect "$app_container" >/dev/null 2>&1; then break; fi
  (( attempt < 36 )) || { echo 'volume workload container did not appear'; exit 1; }
  sleep 5
done
volume=$(runuser -u admiral-apps -- "${app_env[@]}" podman inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$app_container")
[[ -n $volume ]] || { echo 'app container has no /data volume mount'; exit 1; }
marker='original-issue-202-marker'
mountpoint=$(runuser -u admiral-apps -- "${app_env[@]}" podman volume inspect --format '{{.Mountpoint}}' "$volume")
marker_file="$mountpoint/admiral-audit-marker.txt"
runuser -u admiral-apps -- bash -c 'printf "%s\\n" "$1" > "$2"' _ "$marker" "$marker_file"
marker_before=$(cat "$marker_file")
printf 'instance_id=%s app_container=%s volume=%s mountpoint=%s marker_before=%s\n' "$instance_id" "$app_container" "$volume" "$mountpoint" "$marker_before"
[[ $marker_before == "$marker" ]]

admiralctl instances backup "$instance_id" --service app --wait --wait-timeout 10m --output json >"$run_dir/backup-operation.json"
cat "$run_dir/backup-operation.json"
backup_id=$(python3 - "$run_dir/backup-operation.json" "$instance_id" <<'PY'
import json,subprocess,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
op=x.get('id') or x.get('operation_id')
assert op, x
items=json.loads(subprocess.check_output(['admiralctl','backups','list','--output','json'],text=True))
found=[b for b in items if b.get('instance_id')==sys.argv[2] and b.get('service')=='app' and b.get('backup_type')=='volume' and b.get('status')=='succeeded']
assert found,items
print(sorted(found,key=lambda b:b.get('created_at',''))[-1]['id'])
PY
)
admiralctl backups show "$backup_id" >"$run_dir/backup-record.json"
cat "$run_dir/backup-record.json"
read -r storage_key expected_sha size_bytes < <(python3 - "$run_dir/backup-record.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x.get('backup_type')=='volume' and x.get('status')=='succeeded',x
print(x['storage_key'],x['checksum_sha256'],x['size_bytes'])
PY
)
[[ $storage_key == "$instance_id"/volumes-op_*.tar.gz ]] || { echo "unexpected storage key: $storage_key"; exit 1; }
artifact="/var/lib/admiral/backups/$storage_key"
stat -c 'volume_artifact=%n mode=%a owner=%U:%G size=%s' "$artifact"
stat -c 'volume_backup_directory=%n mode=%a owner=%U:%G' "$(dirname "$artifact")"
actual_sha=$(sha256sum "$artifact" | awk '{print $1}')
actual_size=$(stat -c %s "$artifact")
printf 'volume_backup_id=%s storage_key=%s expected_sha256=%s actual_sha256=%s expected_size=%s actual_size=%s\n' "$backup_id" "$storage_key" "$expected_sha" "$actual_sha" "$size_bytes" "$actual_size"
[[ $(stat -c %a "$artifact") == 600 && $(stat -c %a "$(dirname "$artifact")") == 700 ]]
[[ $actual_sha == "$expected_sha" && $actual_size == "$size_bytes" ]]

runuser -u admiral-apps -- bash -c 'printf "%s\\n" "$1" > "$2"' _ 'mutated-after-backup' "$marker_file"
admiralctl instances pause "$instance_id" --wait --wait-timeout 5m --output json >"$run_dir/pause.json"
restore_out=$(admiralctl backups restore --backup-id "$backup_id" --instance-id "$instance_id" --service app --verify-checksum 2>&1)
printf '%s\n' "$restore_out" | tee "$run_dir/restore-request.txt"
restore_op=$(sed -n 's/^Operation ID: //p' "$run_dir/restore-request.txt" | tail -n1)
[[ -n $restore_op ]] || { echo 'restore operation ID missing'; exit 1; }
for attempt in $(seq 1 120); do
  admiralctl operations show "$restore_op" >"$run_dir/restore-operation.json"
  state=$(python3 - "$run_dir/restore-operation.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8')).get('status',''))
PY
)
  printf 'restore_poll=%s status=%s\n' "$attempt" "$state"
  [[ $state == succeeded ]] && break
  [[ $state != failed && $state != cancelled ]] || { cat "$run_dir/restore-operation.json"; exit 1; }
  (( attempt < 120 )) || { echo 'restore operation timed out'; exit 1; }
  sleep 2
done
admiralctl instances resume "$instance_id" --wait --wait-timeout 5m --output json >"$run_dir/resume.json"
marker_after=$(cat "$marker_file")
printf 'marker_after_restore=%s\n' "$marker_after"
[[ $marker_after == "$marker" ]]

# Stop the worker so the queued operation ID is known before creating the symlink.
systemctl stop admiral-fleet.service
fleet_stopped=1
symlink_request="$run_dir/symlink-backup-request.json"
admiralctl instances backup "$instance_id" --service app --output json >"$symlink_request"
cat "$symlink_request"
symlink_op=$(python3 - "$symlink_request" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('id') or x.get('operation_id') or '')
PY
)
[[ $symlink_op =~ ^op_[A-Za-z0-9]+$ ]] || { echo 'queued backup operation ID missing'; exit 1; }
symlink_path="/var/lib/admiral/backups/$instance_id/volumes-$symlink_op.tar.gz"
target="/var/tmp/admiral-issue-202-symlink-target-$run_id"
printf 'untouched-target-%s\n' "$run_id" >"$target"
chmod 0600 "$target"
ln -s "$target" "$symlink_path"
printf 'symlink_attack_path=%s target=%s target_sha_before=%s\n' "$symlink_path" "$target" "$(sha256sum "$target" | awk '{print $1}')"
systemctl start admiral-fleet.service
fleet_stopped=0
for attempt in $(seq 1 120); do
  admiralctl operations show "$symlink_op" >"$run_dir/symlink-operation.json"
  state=$(python3 - "$run_dir/symlink-operation.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8')).get('status',''))
PY
)
  printf 'symlink_backup_poll=%s status=%s\n' "$attempt" "$state"
  [[ $state == failed ]] && break
  [[ $state != succeeded && $state != cancelled ]] || { echo "symlink backup unexpectedly reached $state"; exit 1; }
  (( attempt < 120 )) || { echo 'symlink backup operation timed out'; exit 1; }
  sleep 2
done
cat "$run_dir/symlink-operation.json"
[[ -L $symlink_path ]]
grep -Eiq 'too many levels|symbolic link|symlink|ELOOP' "$run_dir/symlink-operation.json" || grep -Eiq 'too many levels|symbolic link|symlink|ELOOP' "$run_dir/symlink-operation.json" "$run_dir/symlink-backup-request.json"
[[ $(cat "$target") == "untouched-target-$run_id" ]]
printf 'symlink_write_through=PREVENTED target_contents=UNCHANGED\n'
rm -f -- "$symlink_path" "$target"
symlink_path=
printf 'issue_202_volume_backup_restore_permissions_checksum_symlink=PASS end_utc=%s\n' "$(date -u +%FT%TZ)"
REMOTE

printf 'test=ISSUE-202 result=PASS end_utc=%s\n' "$(date -u +%FT%TZ)"
chmod 0600 "$log"
sha256sum "$log"
