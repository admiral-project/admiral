#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Exercise Release 75 workload recovery after rebooting one disposable worker VM.
set -euo pipefail

[[ $# -eq 8 ]] || {
  echo "usage: $0 SSH_KEY HUB_KNOWN_HOSTS WORKER_KNOWN_HOSTS HUB_IP WORKER_IP NODE_ID LIBVIRT_GUEST OUTPUT_DIR" >&2
  exit 2
}
ssh_key=$1 hub_known_hosts=$2 worker_known_hosts=$3
hub_ip=$4 worker_ip=$5 node_id=$6 guest=$7 output_dir=$8
[[ $node_id =~ ^adm-r75-fedora-mn-w[12]$ ]] || { echo 'invalid node id' >&2; exit 2; }
[[ $guest == adm-r75-fedora-mn-w${node_id##*w} ]] || { echo 'node ID and libvirt guest do not match' >&2; exit 2; }
[[ $output_dir == /* ]] || { echo 'output directory must be absolute' >&2; exit 2; }
for path in "$ssh_key" "$hub_known_hosts" "$worker_known_hosts"; do
  [[ -r $path ]] || { echo "unreadable SSH input: $path" >&2; exit 1; }
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../../../.." && pwd)
fixture="$repo_root/examples/apps/e2e-whoami.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
install -d -m 0700 "$output_dir"
umask 077
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes)
hub_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$hub_known_hosts")
worker_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$worker_known_hosts")
hub="validator@$hub_ip"
worker="validator@$worker_ip"
expected_os='fedora'
expected_release='0.0.1rc5-75.fc46'
for role in hub worker; do
  if [[ $role == hub ]]; then
    remote=$hub
    remote_args=("${hub_args[@]}")
    package_args=(admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor)
  else
    remote=$worker
    remote_args=("${worker_args[@]}")
    package_args=(admiral-common admiral-fleet)
  fi
  ssh "${remote_args[@]}" "$remote" bash -s -- "${package_args[@]}" >"$output_dir/candidate-$role.txt" <<'REMOTE'
set -euo pipefail
printf 'os='
. /etc/os-release
printf '%s %s\n' "$ID" "$VERSION_ID"
printf 'arch='
uname -m
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$@" | sort
REMOTE
  grep -E "^os=$expected_os 46([.]|$)" "$output_dir/candidate-$role.txt" >/dev/null || { echo "$role is not Fedora Rawhide (ID=fedora VERSION_ID=46)" >&2; exit 1; }
  grep -Fx 'arch=x86_64' "$output_dir/candidate-$role.txt" >/dev/null || { echo "$role is not x86_64" >&2; exit 1; }
  expected_count=${#package_args[@]}
  [[ $(grep -c -- "-$expected_release\\." "$output_dir/candidate-$role.txt") -eq $expected_count ]] || { echo "$role does not have all expected exact R75 RPMs" >&2; exit 1; }
done
wg_ip=10.99.0.2
[[ $node_id == adm-r75-fedora-mn-w2 ]] && wg_ip=10.99.0.3
suffix=$(date -u +%Y%m%d%H%M%S)
customer="r75-fedora-worker-reboot-$suffix"
idempotency_key="r75-fedora-worker-reboot-$suffix"
instance_id=

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n $instance_id ]]; then
    ssh "${hub_args[@]}" "$hub" \
      "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
      >"$output_dir/final-deprovision-on-exit.json" 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

scp "${hub_args[@]}" "$fixture" "$hub:/tmp/r75-e2e-whoami-worker-reboot.yaml"
ssh "${hub_args[@]}" "$hub" \
  'sudo -u validator env HOME=/home/validator admiralctl apps apply --file /tmp/r75-e2e-whoami-worker-reboot.yaml' \
  >"$output_dir/app-apply.log" 2>&1
ssh "${hub_args[@]}" "$hub" \
  "sudo -u validator env HOME=/home/validator admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$idempotency_key' --node '$node_id' --wait --wait-timeout 10m --quiet --output json" \
  >"$output_dir/provision.json"
instance_id=$(python3 - "$output_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'):
    raise SystemExit('provision did not succeed')
print(x['instance_id'])
PY
)

ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" "$wg_ip" >"$output_dir/workload-before-reboot.txt" <<'REMOTE'
set -euo pipefail
instance_id=$1 expected_ip=$2
cd /tmp
uid=$(id -u admiral-apps)
app_home=$(getent passwd admiral-apps | cut -d: -f6)
run_as_apps() { runuser -u admiral-apps -- env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
db="admiral-${instance_id}-db"
app="admiral-${instance_id}-app"
ready=0
for attempt in $(seq 1 60); do
  if run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 5
done
[[ $ready -eq 1 ]] || { echo 'workload DB did not become ready'; exit 1; }
endpoint=$(run_as_apps port "$app" 80/tcp | head -n1)
[[ $endpoint =~ ^([0-9.]+):([0-9]+)$ && ${BASH_REMATCH[1]} == "$expected_ip" ]] || { echo "unexpected app endpoint: $endpoint"; exit 1; }
marker="r75-fedora-worker-reboot-${instance_id}"
sql="CREATE TABLE IF NOT EXISTS admiral_audit_marker (value TEXT PRIMARY KEY); INSERT INTO admiral_audit_marker(value) VALUES ('$marker') ON CONFLICT DO NOTHING; SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"' sh "$sql"
printf 'app_endpoint=%s\nsql_marker=%s\nboot_id=%s\n' "$endpoint" "$marker" "$(cat /proc/sys/kernel/random/boot_id)"
REMOTE

endpoint=$(sed -n 's/^app_endpoint=//p' "$output_dir/workload-before-reboot.txt" | tail -n1)
marker=$(sed -n 's/^sql_marker=//p' "$output_dir/workload-before-reboot.txt" | tail -n1)
before_boot_id=$(sed -n 's/^boot_id=//p' "$output_dir/workload-before-reboot.txt" | tail -n1)
[[ $endpoint == "$wg_ip:"* && -n $marker && -n $before_boot_id ]] || { echo 'invalid pre-reboot workload evidence'; exit 1; }
[[ $(ssh "${hub_args[@]}" "$hub" "curl --connect-timeout 3 --max-time 10 -fsS -o /dev/null -w '%{http_code}' 'http://$endpoint/'") == 200 ]]
printf 'candidate=0.0.1rc5-75.fc46\nnode_id=%s\nguest=%s\ninstance_id=%s\nbefore_boot_id=%s\n' \
  "$node_id" "$guest" "$instance_id" "$before_boot_id" >"$output_dir/metadata.txt"

[[ $(virsh domstate "$guest" | tr '[:upper:]' '[:lower:]') == running ]] || { echo "libvirt guest is not running: $guest"; exit 1; }
reboot_utc=$(date -u +%FT%TZ)
virsh reboot "$guest" >"$output_dir/virsh-reboot.log" 2>&1
changed_boot_id=
for attempt in $(seq 1 60); do
  current=$(ssh "${worker_args[@]}" -o ConnectTimeout=3 "$worker" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
  if [[ -n $current && $current != "$before_boot_id" ]]; then
    changed_boot_id=$current
    break
  fi
  sleep 3
done
[[ -n $changed_boot_id ]] || { echo 'worker boot ID did not change within 180 seconds'; exit 1; }
printf 'reboot_utc=%s\nafter_boot_id=%s\n' "$reboot_utc" "$changed_boot_id" >>"$output_dir/metadata.txt"

stable=0
for attempt in $(seq 1 60); do
  node_json="$output_dir/nodes-poll-$attempt.json"
  instance_json="$output_dir/instance-poll-$attempt.json"
  ssh "${hub_args[@]}" "$hub" \
    'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$node_json"
  ssh "${hub_args[@]}" "$hub" \
    "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$instance_json"
  node_state=$(python3 - "$node_json" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
nodes=x if isinstance(x,list) else x.get('nodes',[])
n=next((n for n in nodes if n.get('id')==sys.argv[2]),{})
print('/'.join(str(n.get(k,'')) for k in ('status','health_status','available_for_provisioning')))
PY
)
  instance_state=$(python3 - "$instance_json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print('/'.join(str(x.get(k,'')) for k in ('technical_status','health_status','effective_availability')))
PY
)
  runtime=$(ssh "${worker_args[@]}" -o ConnectTimeout=3 "$worker" sudo bash -s -- "$instance_id" "$marker" <<'REMOTE' 2>/dev/null || true
set -u
instance_id=$1 marker=$2
cd /tmp
uid=$(id -u admiral-apps)
app_home=$(getent passwd admiral-apps | cut -d: -f6)
run_as_apps() { runuser -u admiral-apps -- env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
count=$(run_as_apps ps --filter "name=$instance_id" --format '{{.Names}}' 2>/dev/null | wc -l || true)
db="admiral-${instance_id}-db"
app="admiral-${instance_id}-app"
pg=0; marker_present=0
if run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
  pg=1
  query="SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
  if run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"' sh "$query" 2>/dev/null | grep -Fxq "$marker"; then marker_present=1; fi
fi
endpoint=$(run_as_apps port "$app" 80/tcp 2>/dev/null | head -n1 || true)
printf '%s,%s,%s,%s\n' "$count" "$pg" "$marker_present" "$endpoint"
REMOTE
  )
  http=$(ssh "${hub_args[@]}" "$hub" \
    "curl --connect-timeout 2 --max-time 5 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/' || true")
  [[ $http =~ ^[0-9]{3}$ ]] || http=000
  printf 'poll=%s utc=%s node=%s instance=%s runtime=%s http=%s\n' \
    "$attempt" "$(date -u +%FT%TZ)" "$node_state" "$instance_state" "${runtime:-unreachable}" "$http" >>"$output_dir/recovery-timeline.txt"
  if [[ $node_state == 'active/healthy/True' && $instance_state == 'running/healthy/available' && $runtime == "3,1,1,$endpoint" && $http == 200 ]]; then
    ((stable+=1))
  else
    stable=0
  fi
  [[ $stable -lt 2 ]] || break
  sleep 3
done
[[ $stable -ge 2 ]] || { echo 'worker/workload did not reach two consecutive healthy recovery samples'; exit 1; }
ssh "${hub_args[@]}" "$hub" \
  "sudo -u validator env HOME=/home/validator admiralctl nodes list --output json" >"$output_dir/nodes-after-recovery.json"
ssh "${hub_args[@]}" "$hub" \
  "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$output_dir/instance-after-recovery.json"
[[ $(ssh "${hub_args[@]}" "$hub" "curl --connect-timeout 3 --max-time 10 -fsS -o /dev/null -w '%{http_code}' 'http://$endpoint/'") == 200 ]]
ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" "$marker" >"$output_dir/workload-after-recovery.txt" <<'REMOTE'
set -euo pipefail
instance_id=$1 marker=$2
cd /tmp
uid=$(id -u admiral-apps)
app_home=$(getent passwd admiral-apps | cut -d: -f6)
run_as_apps() { runuser -u admiral-apps -- env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
db="admiral-${instance_id}-db"
query="SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"' sh "$query"
REMOTE
grep -Fx "$marker" "$output_dir/workload-after-recovery.txt" >/dev/null || { echo 'SQL marker did not persist across worker reboot'; exit 1; }
ssh "${hub_args[@]}" "$hub" \
  "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
  >"$output_dir/deprovision.json"
python3 - "$output_dir/deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded': raise SystemExit('deprovision failed')
print(f"deprovision_operation={x.get('id')} status={x.get('status')}")
PY
ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" >"$output_dir/final-inventory.txt" <<'REMOTE'
set -euo pipefail
instance_id=$1
cd /tmp
uid=$(id -u admiral-apps)
app_home=$(getent passwd admiral-apps | cut -d: -f6)
run_as_apps() { runuser -u admiral-apps -- env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
containers=$(run_as_apps ps -a --filter "name=$instance_id" --format '{{.Names}}')
pods=$(run_as_apps pod ps --format '{{.Name}}' | grep -F "$instance_id" || true)
volumes=$(run_as_apps volume ls --format '{{.Name}}' | grep -F "$instance_id" || true)
files=$(find /etc/containers/systemd /var/lib/admiral -xdev -iname "*$instance_id*" -print 2>/dev/null || true)
printf 'containers=%s\npods=%s\nvolumes=%s\nfiles=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}" "${files:-none}"
[[ -z $containers && -z $pods && -z $volumes && -z $files ]]
REMOTE
instance_id=
find "$output_dir" -maxdepth 1 -type f -exec chmod 0600 {} +
(cd "$output_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
chmod 0600 "$output_dir/SHA256SUMS"
echo "result=PASS evidence=$output_dir"
