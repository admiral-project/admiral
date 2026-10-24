#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Exercise W2-only WireGuard partition detection and recovery on the R75 CentOS Stream lab.
set -euo pipefail

[[ $# -eq 6 ]] || {
  echo "usage: $0 SSH_KEY HUB_KNOWN_HOSTS WORKER_KNOWN_HOSTS HUB_IP WORKER_IP OUTPUT_DIR" >&2
  exit 2
}
ssh_key=$1 hub_known_hosts=$2 worker_known_hosts=$3
hub_ip=$4 worker_ip=$5 output_dir=$6
node_id=adm-r75-centos-mn-w2
peer_overlay=10.99.0.3/32
partition_overlay=10.99.0.254/32
worker_wg_ip=10.99.0.3
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
suffix=$(date -u +%Y%m%d%H%M%S)
customer="r75-centos-partition-$suffix"
idempotency_key="r75-centos-partition-$suffix"
instance_id=
peer_key=
restore_unit="admiral-r75-centos-partition-$suffix"
partition_active=false

ssh_hub() { ssh "${hub_args[@]}" "$hub" "$@"; }
ssh_worker() { ssh "${worker_args[@]}" "$worker" "$@"; }

restore_peer() {
  [[ -n $peer_key ]] || return 0
  ssh_hub sudo wg set wg-admiral peer "$peer_key" allowed-ips "$peer_overlay" || true
  ssh_hub sudo systemctl stop "$restore_unit.timer" >/dev/null 2>&1 || true
  partition_active=false
}
cleanup() {
  local rc=$?
  trap - EXIT
  [[ $partition_active != true ]] || restore_peer
  if [[ -n $instance_id ]]; then
    ssh_hub \
      "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
      >"$output_dir/final-deprovision-on-exit.json" 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

scp "${hub_args[@]}" "$fixture" "$hub:/tmp/r74-e2e-whoami-partition.yaml"
ssh_hub 'sudo -u validator env HOME=/home/validator admiralctl apps apply --file /tmp/r74-e2e-whoami-partition.yaml' \
  >"$output_dir/app-apply.log" 2>&1
ssh_hub \
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

ssh_worker sudo bash -s -- "$instance_id" "$worker_wg_ip" >"$output_dir/workload-before-partition.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1 expected_ip=$2
uid=$(id -u admiral-apps)
run_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
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
marker="r75-centos-partition-${instance_id}"
sql="CREATE TABLE IF NOT EXISTS admiral_audit_marker (value TEXT PRIMARY KEY); INSERT INTO admiral_audit_marker(value) VALUES ('$marker') ON CONFLICT DO NOTHING; SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"' sh "$sql"
printf 'app_endpoint=%s\nsql_marker=%s\n' "$endpoint" "$marker"
REMOTE
endpoint=$(sed -n 's/^app_endpoint=//p' "$output_dir/workload-before-partition.txt" | tail -n1)
marker=$(sed -n 's/^sql_marker=//p' "$output_dir/workload-before-partition.txt" | tail -n1)
[[ $endpoint == "$worker_wg_ip:"* && -n $marker ]] || { echo 'invalid pre-partition workload evidence'; exit 1; }
[[ $(ssh_hub "curl --connect-timeout 3 --max-time 10 -fsS -o /dev/null -w '%{http_code}' 'http://$endpoint/'") == 200 ]]

peer_key=$(ssh_hub sudo wg show wg-admiral allowed-ips | awk -v allowed="$peer_overlay" '$2 == allowed {print $1}')
[[ $peer_key =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo 'could not identify the W2 WireGuard peer'; exit 1; }
current_allowed=$(ssh_hub sudo wg show wg-admiral allowed-ips | awk -v peer="$peer_key" '$1 == peer {print $2}')
[[ $current_allowed == "$peer_overlay" ]] || { echo "unexpected W2 AllowedIPs: $current_allowed" >&2; exit 1; }
printf 'candidate=0.0.1rc5-75.el10\nnode_id=%s\ninstance_id=%s\npeer_allowed_before=%s\n' \
  "$node_id" "$instance_id" "$current_allowed" >"$output_dir/metadata.txt"

ssh_hub sudo systemd-run --unit="$restore_unit" --on-active=180s \
  /usr/bin/wg set wg-admiral peer "$peer_key" allowed-ips "$peer_overlay" \
  >"$output_dir/restore-timer.log" 2>&1
partition_active=true
ssh_hub sudo wg set wg-admiral peer "$peer_key" allowed-ips "$partition_overlay"
partition_started=$(date -u +%FT%TZ)
printf 'partition_started=%s\n' "$partition_started" >>"$output_dir/metadata.txt"

set +e
ssh_worker curl --connect-timeout 3 --max-time 5 -ksS -o /dev/null \
  -w 'worker_to_hub_http=%{http_code}\n' https://10.99.0.1:8080/health \
  >"$output_dir/worker-health-during-partition.txt" 2>&1
curl_rc=$?
set -e
printf 'worker_to_hub_curl_exit=%s\n' "$curl_rc" >>"$output_dir/metadata.txt"
[[ $curl_rc -ne 0 ]] || { echo 'worker still reached hub API through WireGuard'; exit 1; }

partition_seen=false
for poll in $(seq 1 15); do
  nodes="$output_dir/nodes-partition-$poll.json"
  instance="$output_dir/instance-partition-$poll.json"
  ssh_hub 'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$nodes"
  ssh_hub "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$instance"
  read -r node_status node_health heartbeat <<<"$(python3 - "$nodes" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
items=x if isinstance(x,list) else x.get('nodes',[])
n=next((n for n in items if n.get('id')==sys.argv[2]),{})
print(n.get('status',''),n.get('health_status',''),n.get('last_heartbeat',''))
PY
)"
  read -r technical health availability reason checked <<<"$(python3 - "$instance" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''),str(x.get('availability_reason') or '-'),x.get('last_health_checked_at','-'))
PY
)"
  printf 'partition_poll=%s utc=%s node=%s/%s heartbeat=%s instance=%s/%s/%s reason=%s checked=%s\n' \
    "$poll" "$(date -u +%FT%TZ)" "$node_status" "$node_health" "$heartbeat" \
    "$technical" "$health" "$availability" "$reason" "$checked" >>"$output_dir/recovery-timeline.txt"
  if [[ $node_status == offline && $node_health == degraded && $availability == unavailable ]]; then
    partition_seen=true
    break
  fi
  sleep 10
done
[[ $partition_seen == true ]] || { echo 'node/instance did not become offline/degraded/unavailable within 150 seconds'; exit 1; }

restore_peer
printf 'partition_restored=%s\n' "$(date -u +%FT%TZ)" >>"$output_dir/metadata.txt"
rejoined=false
for poll in $(seq 1 12); do
  nodes="$output_dir/nodes-rejoin-$poll.json"
  instance="$output_dir/instance-rejoin-$poll.json"
  ssh_hub 'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$nodes"
  ssh_hub "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$instance"
  read -r node_status node_health available <<<"$(python3 - "$nodes" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
items=x if isinstance(x,list) else x.get('nodes',[])
n=next((n for n in items if n.get('id')==sys.argv[2]),{})
print(n.get('status',''),n.get('health_status',''),str(n.get('available_for_provisioning','')).lower())
PY
)"
  read -r technical health availability <<<"$(python3 - "$instance" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)"
  printf 'rejoin_poll=%s utc=%s node=%s/%s/available=%s instance=%s/%s/%s\n' \
    "$poll" "$(date -u +%FT%TZ)" "$node_status" "$node_health" "$available" \
    "$technical" "$health" "$availability" >>"$output_dir/recovery-timeline.txt"
  if [[ $node_status == active && $node_health == healthy && $available == true && $availability == available ]]; then
    rejoined=true
    break
  fi
  sleep 10
done
[[ $rejoined == true ]] || { echo 'worker or instance did not recover within 120 seconds'; exit 1; }
http_after=$(ssh_hub "curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
printf 'post_rejoin_http=%s\n' "$http_after" >>"$output_dir/metadata.txt"
[[ $http_after == 200 ]] || { echo 'workload HTTP did not recover'; exit 1; }
ssh_worker sudo bash -s -- "$instance_id" "$marker" >"$output_dir/workload-after-rejoin.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1 marker=$2
uid=$(id -u admiral-apps)
run_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
db="admiral-${instance_id}-db"
query="SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"' sh "$query"
REMOTE
grep -Fx "$marker" "$output_dir/workload-after-rejoin.txt" >/dev/null || { echo 'SQL marker did not persist'; exit 1; }

ssh_hub \
  "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
  >"$output_dir/deprovision.json"
python3 - "$output_dir/deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded': raise SystemExit('deprovision failed')
print(f"deprovision_operation={x.get('id')} status={x.get('status')}")
PY
ssh_worker sudo bash -s -- "$instance_id" >"$output_dir/final-inventory.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1
uid=$(id -u admiral-apps)
run_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
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
echo "partition_detection_and_rejoin=PASS evidence=$output_dir"
