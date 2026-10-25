#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Reboot the isolated R75 Fedora hub with an active W1 workload.
set -euo pipefail

[[ $# -eq 9 ]] || {
  echo "usage: $0 SSH_KEY HUB_KNOWN_HOSTS W1_KNOWN_HOSTS HUB_IP W1_IP HUB_GUEST W1_NODE_ID W1_GUEST OUTPUT_DIR" >&2
  exit 2
}
ssh_key=$1 hub_known_hosts=$2 w1_known_hosts=$3 hub_ip=$4 w1_ip=$5
hub_guest=$6 w1_node=$7 w1_guest=$8 output_dir=$9
[[ $hub_guest == adm-r75-fedora-mn-hub && $w1_guest == adm-r75-fedora-mn-w1 ]] || {
  echo 'guest names do not match the isolated Fedora R75 lab' >&2; exit 2;
}
[[ $w1_node == adm-r75-fedora-mn-w1 ]] || { echo 'unexpected worker node id' >&2; exit 2; }
[[ $output_dir = /* && ! -e $output_dir ]] || { echo 'output directory must be an unused absolute path' >&2; exit 2; }
for path in "$ssh_key" "$hub_known_hosts" "$w1_known_hosts"; do
  [[ -r $path ]] || { echo "unreadable SSH input: $path" >&2; exit 1; }
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../../../.." && pwd)
fixture="$repo_root/examples/apps/e2e-whoami.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
umask 077
mkdir -m 0700 -- "$output_dir"
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5)
hub_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$hub_known_hosts")
w1_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$w1_known_hosts")
hub="validator@$hub_ip" w1="validator@$w1_ip"
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

echo "test=R75-FEDORA-MN-HUB-REBOOT start_utc=$(date -u +%FT%TZ)"
scp "${hub_args[@]}" "$fixture" "$hub:/tmp/r75-fedora-hub-reboot-whoami.yaml"
ssh "${hub_args[@]}" "$hub" \
  'sudo -u validator env HOME=/home/validator admiralctl apps apply --file /tmp/r75-fedora-hub-reboot-whoami.yaml' \
  >"$output_dir/app-apply.log" 2>&1
suffix=$(date -u +%Y%m%d%H%M%S)
customer="r75-fedora-hubreboot-$suffix"
idempotency_key="r75-fedora-hubreboot-$suffix"
ssh "${hub_args[@]}" "$hub" \
  "sudo -u validator env HOME=/home/validator admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$idempotency_key' --node '$w1_node' --wait --wait-timeout 10m --quiet --output json" \
  >"$output_dir/provision.json"
instance_id=$(python3 - "$output_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or x.get('node_id')!='adm-r75-fedora-mn-w1' or not x.get('instance_id'):
    raise SystemExit('W1 provision did not succeed on the requested node')
print(x['instance_id'])
PY
)

ssh "${w1_args[@]}" "$w1" sudo bash -s -- "$instance_id" >"$output_dir/workload-before-reboot.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1
uid=$(id -u admiral-apps)
podman_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
db="admiral-${instance_id}-db" app="admiral-${instance_id}-app"
for attempt in $(seq 1 60); do
  if podman_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
    printf 'database_ready_attempt=%s utc=%s\n' "$attempt" "$(date -u +%FT%TZ)"
    break
  fi
  [[ $attempt -lt 60 ]] || { echo 'workload database did not become ready'; exit 1; }
  sleep 5
done
endpoint=$(podman_as_apps port "$app" 80/tcp | head -n1)
[[ $endpoint =~ ^10\.99\.0\.2:[0-9]+$ ]] || { echo "unexpected endpoint: $endpoint"; exit 1; }
marker="r75-fedora-hub-reboot-${instance_id}"
sql="CREATE TABLE IF NOT EXISTS admiral_audit_marker (value TEXT PRIMARY KEY); INSERT INTO admiral_audit_marker(value) VALUES ('$marker') ON CONFLICT DO NOTHING; SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
podman_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"' sh "$sql"
printf 'app_endpoint=%s\nsql_marker=%s\n' "$endpoint" "$marker"
REMOTE
endpoint=$(sed -n 's/^app_endpoint=//p' "$output_dir/workload-before-reboot.txt" | tail -n1)
marker=$(sed -n 's/^sql_marker=//p' "$output_dir/workload-before-reboot.txt" | tail -n1)
[[ -n $endpoint && -n $marker ]] || { echo 'missing pre-reboot endpoint or SQL marker'; exit 1; }
http_before=$(ssh "${hub_args[@]}" "$hub" "curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
[[ $http_before == 200 ]] || { echo 'W1 workload did not return HTTP 200 before hub reboot'; exit 1; }
ssh "${hub_args[@]}" "$hub" cat /proc/sys/kernel/random/boot_id >"$output_dir/hub-boot-id-before.txt"
ssh "${hub_args[@]}" "$hub" sudo wg show wg-admiral allowed-ips | awk '$2 ~ /^10[.]99[.]0[.][23]\/32$/ {n++} END {print n+0}' >"$output_dir/hub-configured-worker-routes-before.txt"
ssh "${hub_args[@]}" "$hub" sudo wg show wg-admiral latest-handshakes | awk '$2>0 && systime()-$2<300 {n++} END {print n+0}' >"$output_dir/hub-fresh-handshakes-before.txt"
[[ $(cat "$output_dir/hub-configured-worker-routes-before.txt") == 2 ]] || { echo 'hub did not have two W2/W1 routes before reboot'; exit 1; }
[[ $(cat "$output_dir/hub-fresh-handshakes-before.txt") == 2 ]] || { echo 'hub did not have two fresh worker handshakes before reboot'; exit 1; }
printf 'candidate=0.0.1rc5-75.fc46\ninstance_id=%s\nhttp_before=%s\n' "$instance_id" "$http_before" >"$output_dir/metadata.txt"

reboot_epoch=$(date -u +%s)
virsh reboot "$hub_guest" >"$output_dir/virsh-reboot.log" 2>&1
reboot_requested=$(date -u +%FT%TZ)
printf 'hub_reboot_requested=%s\nhub_reboot_epoch=%s\n' "$reboot_requested" "$reboot_epoch" >>"$output_dir/metadata.txt"
ssh_ready=false
for attempt in $(seq 1 60); do
  if ssh "${hub_args[@]}" "$hub" true >/dev/null 2>&1; then
    ssh_ready=true
    break
  fi
  sleep 5
done
[[ $ssh_ready == true ]] || { echo 'hub SSH did not return within five minutes'; exit 1; }
ssh "${hub_args[@]}" "$hub" cat /proc/sys/kernel/random/boot_id >"$output_dir/hub-boot-id-after.txt"
[[ $(cat "$output_dir/hub-boot-id-before.txt") != "$(cat "$output_dir/hub-boot-id-after.txt")" ]] || {
  echo 'hub boot ID did not change'; exit 1;
}

recovered=false
for poll in $(seq 1 24); do
  ssh "${hub_args[@]}" "$hub" sudo systemctl is-active admirald postgresql wg-quick@wg-admiral >"$output_dir/services-$poll.txt" 2>&1 || true
  ssh "${hub_args[@]}" "$hub" sudo wg show wg-admiral allowed-ips | awk '$2 ~ /^10[.]99[.]0[.][23]\/32$/ {n++} END {print n+0}' >"$output_dir/routes-$poll.txt" 2>/dev/null || echo 0 >"$output_dir/routes-$poll.txt"
  ssh "${hub_args[@]}" "$hub" sudo wg show wg-admiral latest-handshakes | awk '$2>0 && systime()-$2<300 {n++} END {print n+0}' >"$output_dir/handshakes-$poll.txt" 2>/dev/null || echo 0 >"$output_dir/handshakes-$poll.txt"
  if ssh "${hub_args[@]}" "$hub" \
      'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' \
      >"$output_dir/nodes-$poll.json" 2>/dev/null && \
     ssh "${hub_args[@]}" "$hub" \
      "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" \
      >"$output_dir/instance-$poll.json" 2>/dev/null; then
    if python3 - "$output_dir/nodes-$poll.json" "$output_dir/instance-$poll.json" "$w1_node" "$reboot_epoch" <<'PY'
import datetime,json,sys,time
data=json.load(open(sys.argv[1],encoding='utf-8'))
nodes=data if isinstance(data,list) else data.get('nodes',[])
workers=[n for n in nodes if n.get('id') in ('adm-r75-fedora-mn-w1','adm-r75-fedora-mn-w2')]
inst=json.load(open(sys.argv[2],encoding='utf-8'))
if len(workers)!=2 or any(n.get('status')!='active' or n.get('health_status')!='healthy' or n.get('available_for_provisioning') is not True for n in workers):
    raise SystemExit(1)
reboot_epoch=float(sys.argv[4])
for node in workers:
    observed=node.get('last_heartbeat')
    if not observed:
        raise SystemExit(1)
    stamp=datetime.datetime.fromisoformat(observed.replace('Z','+00:00')).timestamp()
    if stamp < reboot_epoch or stamp > time.time()+5:
        raise SystemExit(1)
if inst.get('node_id')!=sys.argv[3] or inst.get('technical_status')!='running' or inst.get('health_status')!='healthy' or inst.get('effective_availability')!='available':
    raise SystemExit(1)
PY
    then
      [[ $(cat "$output_dir/routes-$poll.txt") == 2 && $(cat "$output_dir/handshakes-$poll.txt") == 2 ]] || {
        sleep 10
        continue
      }
      recovered=true
      printf 'recovery_poll=%s utc=%s\n' "$poll" "$(date -u +%FT%TZ)" >>"$output_dir/metadata.txt"
      break
    fi
  fi
  sleep 10
done
[[ $recovered == true ]] || { echo 'hub, both workers, or assigned instance did not converge within four minutes'; exit 1; }

ssh "${w1_args[@]}" "$w1" sudo bash -s -- "$instance_id" "$marker" >"$output_dir/workload-after-reboot.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1 marker=$2
uid=$(id -u admiral-apps)
podman_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
db="admiral-${instance_id}-db" app="admiral-${instance_id}-app"
for attempt in $(seq 1 30); do
  if podman_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then break; fi
  [[ $attempt -lt 30 ]] || { echo 'W1 DB did not recover'; exit 1; }
  sleep 2
done
query="SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
podman_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"' sh "$query"
endpoint=$(podman_as_apps port "$app" 80/tcp | head -n1)
printf 'app_endpoint=%s\n' "$endpoint"
REMOTE
grep -Fx "$marker" "$output_dir/workload-after-reboot.txt" >/dev/null || { echo 'SQL marker was not preserved'; exit 1; }
http_after=$(ssh "${hub_args[@]}" "$hub" "curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
printf 'http_after=%s\n' "$http_after" >>"$output_dir/metadata.txt"
[[ $http_after == 200 ]] || { echo 'W1 workload did not return HTTP 200 after hub reboot'; exit 1; }

ssh "${hub_args[@]}" "$hub" \
  "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
  >"$output_dir/deprovision.json"
python3 - "$output_dir/deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded': raise SystemExit('deprovision failed')
print(f"deprovision_operation={x.get('id')} status={x.get('status')}")
PY
ssh "${w1_args[@]}" "$w1" sudo bash -s -- "$instance_id" >"$output_dir/final-inventory.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1
uid=$(id -u admiral-apps)
podman_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
containers=$(podman_as_apps ps -a --filter "name=$instance_id" --format '{{.Names}}')
pods=$(podman_as_apps pod ps --format '{{.Name}}' | grep -F "$instance_id" || true)
volumes=$(podman_as_apps volume ls --format '{{.Name}}' | grep -F "$instance_id" || true)
files=$(find /etc/containers/systemd /var/lib/admiral -xdev -iname "*$instance_id*" -print 2>/dev/null || true)
printf 'containers=%s\npods=%s\nvolumes=%s\nfiles=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}" "${files:-none}"
[[ -z $containers && -z $pods && -z $volumes && -z $files ]]
REMOTE
instance_id=
(cd "$output_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
chmod 0600 "$output_dir"/*
echo "hub_reboot_recovery=PASS evidence=$output_dir"
