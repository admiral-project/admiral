#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Exercise one Release 69 workload lifecycle on a fresh single-node guest.
set -euo pipefail

[[ $# -eq 5 ]] || {
  echo "usage: $0 SSH_KEY KNOWN_HOSTS GUEST_IP NODE_ID RUN_SUFFIX" >&2
  exit 2
}
ssh_key=$1 known_hosts=$2 guest_ip=$3 node_id=$4 suffix=$5
[[ $suffix =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,40}$ ]] || { echo 'invalid run suffix' >&2; exit 2; }
[[ $guest_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'invalid guest IPv4' >&2; exit 2; }
[[ $node_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo 'invalid node ID' >&2; exit 2; }
for path in "$ssh_key" "$known_hosts"; do
  [[ -r $path ]] || { echo "unreadable SSH input: $path" >&2; exit 1; }
done

repo_root=${R75_REPO_ROOT:-$(git rev-parse --show-toplevel)}
fixture="$repo_root/examples/apps/e2e-whoami.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
umask 077
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts")
guest="validator@$guest_ip"
run_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/r75-single-lifecycle.XXXXXXXX")
chmod 0700 "$run_dir"
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -f $run_dir/created-instances.txt ]]; then
    while IFS= read -r instance_id; do
      [[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]] || continue
      if ! ssh "${ssh_args[@]}" "$guest" \
        "sudo admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
        >/dev/null; then
        echo "cleanup failed for instance $instance_id" >&2
        rc=1
      fi
    done <"$run_dir/created-instances.txt"
  fi
  if ! ssh "${ssh_args[@]}" "$guest" 'rm -f -- /tmp/r75-single-e2e-whoami.yaml' >/dev/null; then
    echo 'cleanup failed for uploaded workload definition' >&2
    rc=1
  fi
  chmod -R go-rwx "$run_dir"
  echo "private-run-evidence=$run_dir"
  exit "$rc"
}
trap cleanup EXIT

ssh "${ssh_args[@]}" "$guest" \
  "sudo admiralctl nodes list --output json" \
  >"$run_dir/nodes.json"
python3 - "$run_dir/nodes.json" "$node_id" <<'PY'
import json,sys
nodes=json.load(open(sys.argv[1],encoding='utf-8'))
matches=[n for n in nodes if n.get('id')==sys.argv[2] and n.get('node_role')=='worker']
if len(matches)!=1:
    raise SystemExit(f'expected exactly one worker node {sys.argv[2]!r}; found {len(matches)}')
n=matches[0]
for key in ('id','os','status','health_status','available_for_provisioning','wireguard_ip','fleet_version'):
    print(f'{key}={n.get(key)}')
if n.get('status')!='active' or n.get('health_status')!='healthy' or not n.get('available_for_provisioning'):
    raise SystemExit('single-node worker is not active, healthy and available')
PY

scp "${ssh_args[@]}" "$fixture" "$guest:/tmp/r75-single-e2e-whoami.yaml"
ssh "${ssh_args[@]}" "$guest" \
  'sudo admiralctl apps apply --file /tmp/r75-single-e2e-whoami.yaml'

customer="r75-single-${suffix}"
key="r75-single-${suffix}"
echo "test=R75-SINGLE-NODE-LIFECYCLE start_utc=$(date -u +%FT%TZ) node=$node_id"
provision_rc=0
ssh "${ssh_args[@]}" "$guest" \
  "sudo admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$key' --node '$node_id' --wait --wait-timeout 10m --quiet --output json" \
  >"$run_dir/provision.json" || provision_rc=$?
instance_id=$(python3 - "$run_dir/provision.json" <<'PY' || true
import json,sys
try:
    print(json.load(open(sys.argv[1],encoding='utf-8')).get('instance_id',''))
except (OSError,ValueError):
    print('')
PY
)
if [[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]]; then
  printf '%s\n' "$instance_id" >>"$run_dir/created-instances.txt"
fi
[[ $provision_rc -eq 0 ]] || { echo "provision command failed with exit code $provision_rc" >&2; exit "$provision_rc"; }
[[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]] || { echo 'invalid instance ID from provision' >&2; exit 1; }
python3 - "$run_dir/provision.json" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
for k in ('id','instance_id','node_id','status','created_at','updated_at'):
    print(f'{k}={x.get(k)}')
if x.get('status')!='succeeded' or x.get('node_id')!=sys.argv[2]:
    raise SystemExit('provision did not succeed on the selected local worker')
PY

ssh "${ssh_args[@]}" "$guest" \
  "sudo admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$key' --node '$node_id' --wait --wait-timeout 2m --quiet --output json" \
  >"$run_dir/replay.json"
python3 - "$run_dir/provision.json" "$run_dir/replay.json" <<'PY'
import json,sys
a,b=(json.load(open(p,encoding='utf-8')) for p in sys.argv[1:])
same_op=a.get('id')==b.get('id')
same_instance=a.get('instance_id')==b.get('instance_id')
print(f'idempotency_replay_same_operation={same_op}')
print(f'idempotency_replay_same_instance={same_instance}')
if not same_op or not same_instance:
    raise SystemExit('same-key replay did not return the original operation and instance')
PY

if ! ssh "${ssh_args[@]}" "$guest" sudo bash -s -- "$instance_id" "$node_id" <<'REMOTE' >"$run_dir/runtime.txt"
set -euo pipefail
cd /tmp
instance_id=$1 node_id=$2
uid=$(id -u admiral-apps)
podman_as_apps() {
  runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"
}
app="admiral-${instance_id}-app"
db="admiral-${instance_id}-db"
for attempt in $(seq 1 60); do
  if podman_as_apps exec "$db" sh -c \
    'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    >/dev/null 2>&1; then
    printf 'database_ready_attempt=%s utc=%s\n' "$attempt" "$(date -u +%FT%TZ)"
    break
  fi
  [[ $attempt -lt 60 ]] || { echo 'database did not become ready within five minutes'; exit 1; }
  sleep 5
done
podman_as_apps ps --all --filter "name=$instance_id" --format '{{.Names}}|{{.Status}}|{{.Ports}}'
endpoint=$(podman_as_apps port "$app" 80/tcp | head -n1)
[[ $endpoint =~ ^([0-9.]+):([0-9]+)$ ]] || { echo "unexpected mapped endpoint: $endpoint"; exit 1; }
[[ ${BASH_REMATCH[1]} == 127.0.0.1 ]] || { echo "single-node app is not restricted to loopback: $endpoint"; exit 1; }
printf 'app_endpoint=%s\n' "$endpoint"
marker="r75-single-${instance_id}"
sql="CREATE TABLE IF NOT EXISTS admiral_audit_marker (value TEXT PRIMARY KEY); INSERT INTO admiral_audit_marker(value) VALUES ('$marker') ON CONFLICT DO NOTHING; SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
podman_as_apps exec "$db" sh -c \
  'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"' \
  sh "$sql"
REMOTE
then
  cat "$run_dir/runtime.txt"
  echo 'runtime inspection failed; preserved private run evidence' >&2
  exit 1
fi
cat "$run_dir/runtime.txt"
endpoint=$(sed -n 's/^app_endpoint=//p' "$run_dir/runtime.txt" | tail -n1)
[[ $endpoint =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo "single-node app endpoint is not restricted to loopback: $endpoint" >&2; exit 1; }
http_code=$(ssh "${ssh_args[@]}" "$guest" \
  "curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
printf 'local_workload_http_status=%s endpoint=%s\n' "$http_code" "$endpoint"
[[ $http_code == 200 ]] || { echo 'local workload HTTP probe did not return 200' >&2; exit 1; }

ssh "${ssh_args[@]}" "$guest" \
  "sudo admiralctl instances show '$instance_id'" \
  >"$run_dir/instance.json"
python3 - "$run_dir/instance.json" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
for k in ('id','node_id','technical_status','health_status','effective_availability','availability_reason'):
    print(f'{k}={x.get(k)}')
if x.get('node_id')!=sys.argv[2] or x.get('effective_availability')!='available':
    raise SystemExit('API workload state does not match the active local node')
PY

ssh "${ssh_args[@]}" "$guest" \
  "sudo admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
  >"$run_dir/deprovision.json"
python3 - "$run_dir/deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(f"deprovision_operation={x.get('id')} status={x.get('status')}")
if x.get('status')!='succeeded':
    raise SystemExit('explicit test deprovision did not succeed')
PY
ssh "${ssh_args[@]}" "$guest" sudo bash -s -- "$instance_id" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1
uid=$(id -u admiral-apps)
run_as_apps() {
  runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}
containers=$(run_as_apps podman ps -a --filter "name=$instance_id" --format '{{.Names}}')
pods=$(run_as_apps podman pod ps --format '{{.Name}}' | grep -F "$instance_id" || true)
volumes=$(run_as_apps podman volume ls --format '{{.Name}}' | grep -F "$instance_id" || true)
units=$(run_as_apps systemctl --user list-unit-files --no-legend | grep -F "$instance_id" || true)
files=$(find /etc/containers/systemd /var/lib/admiral -iname "*$instance_id*" -print 2>/dev/null || true)
printf 'remaining_matching_containers=%s\nremaining_matching_pods=%s\nremaining_matching_volumes=%s\nremaining_matching_units=%s\nremaining_matching_files=%s\n' \
  "${containers:-none}" "${pods:-none}" "${volumes:-none}" "${units:-none}" "${files:-none}"
[[ -z $containers && -z $pods && -z $volumes && -z $units && -z $files ]]
REMOTE
ssh "${ssh_args[@]}" "$guest" 'rm -f -- /tmp/r75-single-e2e-whoami.yaml'
rm -f -- "$run_dir/created-instances.txt"
echo "single_node_lifecycle=PASS node=$node_id instance=$instance_id end_utc=$(date -u +%FT%TZ)"
