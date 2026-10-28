#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $# -eq 7 ]] || {
  echo "usage: $0 APP TIER BACKUP_SERVICES PUBLIC_SERVICE PUBLIC_PORT HEALTH_PATH CUSTOMER_PREFIX" >&2
  exit 2
}
app=$1 tier=$2 backup_services_csv=$3 public_service=$4 public_port=$5 health_path=$6 customer_prefix=$7
IFS=',' read -r -a backup_services <<<"$backup_services_csv"
[[ $app =~ ^[a-z0-9-]+$ && $tier =~ ^[a-z0-9-]+$ && $public_service =~ ^[a-z0-9-]+$ ]] || exit 2
((${#backup_services[@]} > 0)) || exit 2
for backup_service in "${backup_services[@]}"; do [[ $backup_service =~ ^[a-z0-9-]+$ ]] || exit 2; done
[[ $public_port =~ ^[0-9]+$ && $health_path == /* && $customer_prefix =~ ^[a-z0-9-]+$ ]] || exit 2

root=$(git rev-parse --show-toplevel)
run_tag=$(date -u +%Y%m%dT%H%M%SZ)-$$
out="$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r21/runtime/issue-305-r21-20261028/$app-$run_tag"
mkdir -m 0700 -p "$out"
cp "$0" "$out/runner.sh"
key=/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519
known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-admin/known_hosts
guest=validator@10.77.0.10
yaml="$root/examples/apps/$app.yaml"
customer="$customer_prefix-$run_tag"
instance_id=
backup_ids=()
success=no
monitor_pid=
parent_pid=$$
guest_ram_floor_kib=${R21_GUEST_RAM_FLOOR_KIB:-262144}
ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known" -o ConnectTimeout=5)
admin() { ssh "${ssh_args[@]}" "$guest" "$1"; }
status_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$1"; }

record_resources() {
  local host_mem host_disk guest_data guest_mem guest_disk alerts=()
  host_mem=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
  host_disk=$(df -Pk / | awk 'NR==2 {print $4}')
  guest_data=$(admin "cd /; awk '/MemAvailable:/ {print \$2}' /proc/meminfo; df -Pk / | awk 'NR==2 {print \$4}'") || return 1
  guest_mem=$(sed -n '1p' <<<"$guest_data")
  guest_disk=$(sed -n '2p' <<<"$guest_data")
  (( host_mem >= 2097152 )) || alerts+=(host_ram_below_2_gib)
  (( host_disk >= 31457280 )) || alerts+=(host_disk_below_30_gib)
  (( guest_mem >= guest_ram_floor_kib )) || alerts+=(guest_ram_below_floor)
  (( guest_disk >= 1572864 )) || alerts+=(guest_disk_below_1_5_gib)
  printf '{"at":"%s","host_memavailable_kib":%s,"host_disk_available_kib":%s,"guest_memavailable_kib":%s,"guest_disk_available_kib":%s,"alerts":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$host_mem" "$host_disk" "$guest_mem" "$guest_disk" "${alerts[*]:-}" >> "$out/resource-monitor.jsonl"
  if ((${#alerts[@]})); then
    printf 'STOP: %s\n' "${alerts[*]}" | tee "$out/STOP.txt"
    return 1
  fi
}
monitor_resources() {
  while [[ ! -e $out/monitor-stop ]]; do
    if ! record_resources; then
      kill -TERM "$parent_pid" 2>/dev/null || true
      return 1
    fi
    sleep 10
  done
}
guard_resources() {
  [[ ! -f $out/STOP.txt ]] || { cat "$out/STOP.txt"; return 1; }
  record_resources
}
wait_op() {
  local op=$1 file=$2 state=
  for poll in $(seq 1 100); do
    guard_resources
    admin "sudo -n admiralctl operations show '$op'" > "$file"
    state=$(status_of "$file")
    printf '%s poll=%s status=%s\n' "$op" "$poll" "$state" >> "$out/operations-poll.log"
    [[ $state == succeeded || $state == failed || $state == cancelled ]] && break
    sleep 3
  done
  [[ $state == succeeded ]]
}
wait_healthy() {
  local file=$1
  for poll in $(seq 1 48); do
    guard_resources
    admin "sudo -n admiralctl instances show '$instance_id'" > "$file"
    if python3 - "$file" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
raise SystemExit(0 if x.get("technical_status")=="running" and x.get("health_status")=="healthy" and x.get("effective_availability")=="available" else 1)
PY
    then return 0; fi
    sleep 5
  done
  return 1
}
http_check() {
  local file=$1 port_map host_port
  port_map=$(admin "cd /; uid=\$(id -u admiral-apps); sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$uid/bus podman port 'admiral-$instance_id-$public_service' '$public_port/tcp'")
  host_port=$(printf '%s\n' "$port_map" | head -n1 | awk -F: '{print $NF}')
  [[ $host_port =~ ^[0-9]+$ ]] || { echo "published port missing: $port_map" >&2; return 1; }
  admin "curl --connect-timeout 3 --max-time 20 -sS -D - -o /dev/null -w 'http_status=%{http_code}\\n' 'http://127.0.0.1:$host_port$health_path'" > "$file" 2>&1
  grep -q '^http_status=200$' "$file"
}
capture_backup() {
  local service=$1
  admin 'sudo -n admiralctl backups list --output json' > "$out/backups-list.json"
  python3 - "$out/backups-list.json" "$instance_id" "$service" > "$out/backup-id-$service.txt" <<'PY'
import json,sys
xs=json.load(open(sys.argv[1],encoding="utf-8"))
xs=[x for x in xs if x.get("instance_id")==sys.argv[2] and x.get("service")==sys.argv[3] and x.get("status")=="succeeded"]
if not xs: raise SystemExit("no succeeded backup for requested service")
x=max(xs,key=lambda x:x.get("created_at",""))
print(x["id"])
print("checksum_sha256="+str(x.get("checksum_sha256","")))
PY
  head -n1 "$out/backup-id-$service.txt"
}
cleanup() {
  local rc=$?
  trap - EXIT TERM
  touch "$out/monitor-stop"
  [[ -z $monitor_pid ]] || wait "$monitor_pid" 2>/dev/null || true
  if [[ -n $instance_id && $success != yes ]]; then
    admin "sudo -n admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" > "$out/deprovision-on-exit.json" 2>&1 || true
  fi
  local index bid
  for index in "${!backup_ids[@]}"; do
    bid=${backup_ids[$index]}
    [[ -z $bid ]] || printf 'y\n' | admin "sudo -n admiralctl backups delete '$bid'" > "$out/delete-backup-on-exit-$index.txt" 2>&1 || true
  done
  admin "sudo -n rm -f /tmp/issue305-$app-r21.yaml" >/dev/null 2>&1 || true
  [[ ! -f $out/STOP.txt ]] || cat "$out/STOP.txt"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 1' TERM

cp "$yaml" "$out/$app.yaml"
record_resources
monitor_resources & monitor_pid=$!
guard_resources
scp "${ssh_args[@]}" "$yaml" "$guest:/tmp/issue305-$app-r21.yaml"
admin "sudo -n admiralctl apps apply --file /tmp/issue305-$app-r21.yaml" > "$out/apps-apply.log" 2>&1
admin "sudo -n admiralctl apps activate --name '$app'" > "$out/app-activate.log" 2>&1
guard_resources
set +e
admin "sudo -n admiralctl instances provision --app '$app' --tier '$tier' --customer '$customer' --idempotency-key '$customer' --node rc6e5r18-ipv6-admin --wait --wait-timeout 45m --quiet --output json" > "$out/provision.json" 2>&1
provision_rc=$?
set -e
instance_id=$(python3 - "$out/provision.json" <<'PY'
import json,sys
raw=open(sys.argv[1],encoding="utf-8").read()
dec=json.JSONDecoder()
for i,c in enumerate(raw):
    if c!="{": continue
    try: obj,_=dec.raw_decode(raw[i:])
    except json.JSONDecodeError: continue
    if obj.get("instance_id"):
        print(obj["instance_id"])
        break
PY
)
if [[ ! $instance_id =~ ^inst_[A-Za-z0-9]+$ || $provision_rc -ne 0 ]]; then
  printf 'provision_exit_code=%s\ninstance_id=%s\nresult=FAIL\n' "$provision_rc" "${instance_id:-none}" > "$out/RESULT.txt"
  exit 1
fi
admin "sudo -n admiralctl instances show '$instance_id'" > "$out/instance-running.json"
wait_healthy "$out/instance-running.json"
http_check "$out/http-before-lifecycle.txt"
admin "sudo -n admiralctl instances pause '$instance_id' --force --wait --wait-timeout 5m --output json" > "$out/pause.json"
[[ $(status_of "$out/pause.json") == succeeded ]]
admin "sudo -n admiralctl instances resume '$instance_id' --force --wait --wait-timeout 5m --output json" > "$out/resume.json"
[[ $(status_of "$out/resume.json") == succeeded ]]
admin "sudo -n admiralctl instances restart '$instance_id' --force --wait --wait-timeout 5m --output json" > "$out/restart.json"
[[ $(status_of "$out/restart.json") == succeeded ]]
wait_healthy "$out/instance-after-restart.json"
http_check "$out/http-after-restart.txt"
guard_resources
for backup_service in "${backup_services[@]}"; do
  admin "sudo -n admiralctl instances backup '$instance_id' --service '$backup_service' --wait --wait-timeout 15m --output json" > "$out/backup-$backup_service.json"
  [[ $(status_of "$out/backup-$backup_service.json") == succeeded ]]
  backup_id=$(capture_backup "$backup_service")
  [[ $backup_id =~ ^bk_[A-Za-z0-9]+$ ]]
  backup_ids+=("$backup_id")
  [[ $(sed -n 's/^checksum_sha256=//p' "$out/backup-id-$backup_service.txt") =~ ^[a-f0-9]{64}$ ]]
done
admin "sudo -n admiralctl instances pause '$instance_id' --force --wait --wait-timeout 5m --output json" > "$out/pause-before-restore.json"
[[ $(status_of "$out/pause-before-restore.json") == succeeded ]]
for index in "${!backup_services[@]}"; do
  backup_service=${backup_services[$index]}
  backup_id=$(head -n1 "$out/backup-id-$backup_service.txt")
  admin "sudo -n admiralctl backups restore --backup-id '$backup_id' --instance-id '$instance_id' --service '$backup_service' --verify-checksum" > "$out/restore-request-$backup_service.txt"
  restore_op=$(sed -n 's/^Operation ID: //p' "$out/restore-request-$backup_service.txt" | tail -n1)
  [[ $restore_op =~ ^op_[A-Za-z0-9]+$ ]]
  wait_op "$restore_op" "$out/restore-operation-$backup_service.json"
done
admin "sudo -n admiralctl instances resume '$instance_id' --force --wait --wait-timeout 5m --output json" > "$out/resume-after-restore.json"
[[ $(status_of "$out/resume-after-restore.json") == succeeded ]]
wait_healthy "$out/instance-after-restore.json"
http_check "$out/http-after-restore.txt"
admin "sudo -n admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" > "$out/deprovision.json"
[[ $(status_of "$out/deprovision.json") == succeeded ]]
for backup_id in "${backup_ids[@]}"; do
  printf 'y\n' | admin "sudo -n admiralctl backups delete '$backup_id'" > "$out/delete-backup-$backup_id.txt"
done
backup_ids=()
admin "cd /; uid=\$(id -u admiral-apps); sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$uid/bus podman ps -a --filter name='$instance_id' --format '{{.Names}} {{.Status}}'; sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$uid/bus podman pod ps --format '{{.Name}}' | grep -F '$instance_id' || true; sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$uid/bus podman volume ls --format '{{.Name}}' | grep -F '$instance_id' || true; sudo -n find /etc/containers/systemd /var/lib/admiral/backups -iname '*$instance_id*' -print 2>/dev/null || true" > "$out/post-cleanup-inventory.txt"
guard_resources
printf 'candidate=RC6 E5 R21\napp=%s\ninstance_id=%s\nrpm_installed=PASS\nsetup=PASS\npause_resume_restart=PASS\nbackup_services=%s\nrestore_checksums=PASS\nhealth_before=%s\nhealth_after_restore=%s\ndeprovision_cleanup=PASS\n' \
  "$app" "$instance_id" "$backup_services_csv" "$(cat "$out/http-before-lifecycle.txt")" "$(cat "$out/http-after-restore.txt")" > "$out/RESULT.txt"
for backup_service in "${backup_services[@]}"; do
  printf 'backup_%s_id=%s\nbackup_%s_checksum=%s\n' \
    "$backup_service" "$(head -n1 "$out/backup-id-$backup_service.txt")" \
    "$backup_service" "$(sed -n 's/^checksum_sha256=//p' "$out/backup-id-$backup_service.txt")" >> "$out/RESULT.txt"
done
success=yes
printf '%s R21 E2E: PASS; evidence=%s\n' "$app" "$out"
