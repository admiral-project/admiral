#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Verify idle worker removal preserves terminal customer and operation history.
set -euo pipefail
[[ $# -eq 9 ]] || { echo "usage: $0 SSH_KEY HUB_KNOWN WORKER_KNOWN HUB_IP WORKER_IP NODE_ID DIST_TAG EPOCH OUTPUT_DIR" >&2; exit 2; }
ssh_key=$1 hub_known=$2 worker_known=$3 hub_ip=$4 worker_ip=$5 node_id=$6 dist_tag=$7 epoch=$8 output_dir=$9
[[ $node_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ && $dist_tag =~ ^(el10|fc46)$ && $epoch =~ ^[0-9]{1,4}$ && $output_dir == /* ]] || { echo 'expected a disposable worker ID, el10/fc46 dist tag, RPM Epoch, and absolute output directory' >&2; exit 2; }
release=${RC6_PACKAGE_RELEASE:-7}
[[ $release =~ ^[0-9]+$ ]] || { echo 'RC6_PACKAGE_RELEASE must be a numeric RPM Release' >&2; exit 2; }
candidate="0.0.1rc6-$release.$dist_tag"
for p in "$ssh_key" "$hub_known" "$worker_known"; do [[ -r $p ]] || { echo "unreadable input: $p" >&2; exit 1; }; done
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../../../.." && pwd)
fixture="$repo_root/examples/apps/e2e-whoami.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
install -d -m 0700 "$output_dir"
umask 077
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes)
hub_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$hub_known")
worker_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$worker_known")
hub="validator@$hub_ip" worker="validator@$worker_ip"
instance_id= node_removed=0 deprovisioned=0
snapshot_customer_app() {
  local destination=$1
  ssh "${hub_args[@]}" "$hub" sudo -u postgres psql -X -q -t -A -v ON_ERROR_STOP=1 -d admiral -v "instance_id=$instance_id" >"$destination" <<'SQL'
SELECT COALESCE(json_agg(row_to_json(s)), '[]'::json)
FROM (
  SELECT id, customer_id, app_definition_name, tier_name, node_id, commercial_status, technical_status
  FROM customer_apps
  WHERE id = :'instance_id'
) AS s;
SQL
}
snapshot_operations() {
  local destination=$1
  ssh "${hub_args[@]}" "$hub" sudo -u postgres psql -X -q -t -A -v ON_ERROR_STOP=1 -d admiral -v "instance_id=$instance_id" >"$destination" <<'SQL'
SELECT COALESCE(json_agg(row_to_json(s)), '[]'::json)
FROM (
  SELECT id, instance_id, node_id, action, status, task_id
  FROM operations
  WHERE instance_id = :'instance_id'
  ORDER BY id
) AS s;
SQL
}
finish() {
  local rc=$?
  trap - EXIT
  if [[ -n $instance_id && $node_removed -eq 0 && $deprovisioned -eq 0 ]]; then
    ssh "${hub_args[@]}" "$hub" "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" >"$output_dir/final-deprovision-on-exit.json" 2>&1 || true
  fi
  printf 'exit_code=%s\n' "$rc" >"$output_dir/exit-status.txt"
  find "$output_dir" -maxdepth 1 -type f ! -name SHA256SUMS -exec chmod 0600 {} +
  (cd "$output_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
  chmod 0600 "$output_dir/SHA256SUMS"
  exit "$rc"
}
trap finish EXIT

ssh "${hub_args[@]}" "$hub" 'rpm -q --qf "%{EPOCHNUM}:%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor | sort' >"$output_dir/candidate-hub.txt"
ssh "${worker_args[@]}" "$worker" 'rpm -q --qf "%{EPOCHNUM}:%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" admiral-common admiral-fleet | sort' >"$output_dir/candidate-worker.txt"
for expected in \
  "$epoch:admiral-common-$candidate.noarch" \
  "$epoch:admirald-$candidate.x86_64" \
  "$epoch:admiral-fleet-$candidate.x86_64" \
  "$epoch:admiralctl-$candidate.x86_64" \
  "$epoch:admiral-flagship-$candidate.noarch" \
  "$epoch:admiral-harbor-$candidate.noarch"; do
  grep -Fx "$expected" "$output_dir/candidate-hub.txt" >/dev/null
done
for expected in "$epoch:admiral-common-$candidate.noarch" "$epoch:admiral-fleet-$candidate.x86_64"; do
  grep -Fx "$expected" "$output_dir/candidate-worker.txt" >/dev/null
done
suffix=$(date -u +%Y%m%d%H%M%S)
customer="rc6-node-removal-$suffix" key="rc6-node-removal-$suffix"
printf 'test_id=RC6-MN-NODE-REMOVE-HISTORY-01\ncandidate=%s\nepoch=%s\nnode_id=%s\nstarted_utc=%s\n' "$candidate" "$epoch" "$node_id" "$(date -u +%FT%TZ)" >"$output_dir/metadata.txt"
scp "${hub_args[@]}" "$fixture" "$hub:/tmp/rc6-e2e-whoami-node-removal.yaml"
ssh "${hub_args[@]}" "$hub" 'sudo -u validator env HOME=/home/validator admiralctl apps apply --file /tmp/rc6-e2e-whoami-node-removal.yaml' >"$output_dir/app-apply.log" 2>&1
ssh "${hub_args[@]}" "$hub" "sudo -u validator env HOME=/home/validator admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$key' --node '$node_id' --wait --wait-timeout 10m --quiet --output json" >"$output_dir/provision.json"
instance_id=$(python3 - "$output_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'): raise SystemExit('provision did not succeed')
print(x['instance_id'])
PY
)
printf 'instance_id=%s\n' "$instance_id" >>"$output_dir/metadata.txt"
ssh "${hub_args[@]}" "$hub" "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$output_dir/instance-before-removal.json"
endpoint=$(ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" <<'REMOTE'
set -euo pipefail
cd /tmp
uid=$(id -u admiral-apps); app_home=$(getent passwd admiral-apps | cut -d: -f6)
runuser -u admiral-apps -- env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman port "admiral-$1-app" 80/tcp | head -n1
REMOTE
)
[[ $endpoint =~ ^10\.99\.0\.[0-9]+:[0-9]+$ ]]
http=$(ssh "${hub_args[@]}" "$hub" "curl --retry 30 --retry-delay 2 --retry-all-errors --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
[[ $http == 200 ]]
printf 'endpoint=%s\nhttp_before_remove=%s\n' "$endpoint" "$http" >>"$output_dir/metadata.txt"

ssh "${hub_args[@]}" "$hub" sudo bash -s -- "$node_id" >"$output_dir/remove-active-instance.log" 2>&1 <<'REMOTE'
set -u
node_id=$1
set +e
printf 'y\n' | sudo -u validator env HOME=/home/validator admiralctl nodes remove "$node_id"
rc=$?
set -e
printf 'command_exit=%s\n' "$rc"
REMOTE
grep -E 'has active instances \(1 active instance\)' "$output_dir/remove-active-instance.log" >/dev/null
grep -Fx 'command_exit=1' "$output_dir/remove-active-instance.log" >/dev/null
ssh "${hub_args[@]}" "$hub" "sudo -u validator env HOME=/home/validator admiralctl nodes show '$node_id'" >"$output_dir/node-after-rejected-removal.json"
ssh "${hub_args[@]}" "$hub" "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$output_dir/instance-after-rejected-removal.json"
python3 - "$output_dir/instance-after-rejected-removal.json" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if (x.get('node_id'),x.get('technical_status'),x.get('health_status'),x.get('effective_availability')) != (sys.argv[2],'running','healthy','available'):
 raise SystemExit('workload state changed after the rejected node removal')
PY
http=$(ssh "${hub_args[@]}" "$hub" "curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
[[ $http == 200 ]]
printf 'http_after_rejected_remove=%s\n' "$http" >>"$output_dir/metadata.txt"

ssh "${hub_args[@]}" "$hub" "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" >"$output_dir/deprovision.json"
python3 - "$output_dir/deprovision.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1],encoding='utf-8')).get('status')!='succeeded': raise SystemExit('deprovision failed')
PY
deprovisioned=1
ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" >"$output_dir/worker-clean-before-node-removal.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
uid=$(id -u admiral-apps); app_home=$(getent passwd admiral-apps | cut -d: -f6)
run_as_apps() { runuser -u admiral-apps -- env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
instance_id=$1
containers=$(run_as_apps ps -a --filter "name=$instance_id" --format '{{.Names}}')
pods=$(run_as_apps pod ps --format '{{.Name}}' | grep -F "$instance_id" || true)
volumes=$(run_as_apps volume ls --format '{{.Name}}' | grep -F "$instance_id" || true)
files=$(find /etc/containers/systemd /var/lib/admiral "$app_home/.config/containers/systemd" -xdev -iname "*$instance_id*" -print 2>/dev/null || true)
printf 'containers=%s\npods=%s\nvolumes=%s\nfiles=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}" "${files:-none}"
[[ -z $containers && -z $pods && -z $volumes && -z $files ]]
REMOTE
snapshot_customer_app "$output_dir/customer-app-before-node-removal.json"
snapshot_operations "$output_dir/operations-before-node-removal.json"
python3 - "$output_dir/customer-app-before-node-removal.json" "$output_dir/operations-before-node-removal.json" "$instance_id" "$node_id" <<'PY'
import json,sys
app_rows=json.load(open(sys.argv[1],encoding='utf-8'))
operations=json.load(open(sys.argv[2],encoding='utf-8'))
if len(app_rows)!=1:
    raise SystemExit(f'expected the terminal customer instance before removal, found {len(app_rows)} rows')
app=app_rows[0]
if app.get('id')!=sys.argv[3] or app.get('node_id')!=sys.argv[4]:
    raise SystemExit(f'instance is not associated with the removed worker: {app}')
if (app.get('commercial_status'),app.get('technical_status'))!=('cancelled','deprovisioned'):
    raise SystemExit(f'instance is not terminal before node removal: {app}')
if len(operations)<2 or any(row.get('instance_id')!=sys.argv[3] for row in operations):
    raise SystemExit(f'expected provision/deprovision operation history, got {operations}')
if not any(row.get('action')=='provision_app' and row.get('status')=='succeeded' for row in operations):
    raise SystemExit('successful provision operation is missing before node removal')
if not any(row.get('action')=='deprovision_app' and row.get('status')=='succeeded' for row in operations):
    raise SystemExit('successful deprovision operation is missing before node removal')
print(f'customer_instance_before_removal={app["id"]} commercial={app["commercial_status"]} technical={app["technical_status"]} node={app["node_id"]}')
print(f'operation_history_before_removal={len(operations)}')
PY
ssh "${hub_args[@]}" "$hub" sudo bash -s -- "$node_id" >"$output_dir/remove-idle-node.log" 2>&1 <<'REMOTE'
set -euo pipefail
node_id=$1
printf 'y\n' | sudo -u validator env HOME=/home/validator admiralctl nodes remove "$node_id"
REMOTE
grep -F "Node \"$node_id\" removed." "$output_dir/remove-idle-node.log" >/dev/null
node_removed=1
snapshot_customer_app "$output_dir/customer-app-after-node-removal.json"
snapshot_operations "$output_dir/operations-after-node-removal.json"
python3 - "$output_dir/customer-app-before-node-removal.json" "$output_dir/operations-before-node-removal.json" "$output_dir/customer-app-after-node-removal.json" "$output_dir/operations-after-node-removal.json" "$instance_id" "$node_id" <<'PY'
import json,sys
before_apps=json.load(open(sys.argv[1],encoding='utf-8'))
before_ops=json.load(open(sys.argv[2],encoding='utf-8'))
after_apps=json.load(open(sys.argv[3],encoding='utf-8'))
after_ops=json.load(open(sys.argv[4],encoding='utf-8'))
instance_id,node_id=sys.argv[5:7]
if len(before_apps)!=1 or len(after_apps)!=1:
    raise SystemExit(f'customer instance row was deleted or duplicated: before={len(before_apps)} after={len(after_apps)}')
before,after=before_apps[0],after_apps[0]
for field in ('id','customer_id','app_definition_name','tier_name','commercial_status','technical_status'):
    if before.get(field)!=after.get(field):
        raise SystemExit(f'customer instance field {field} changed: {before.get(field)!r} -> {after.get(field)!r}')
if before.get('id')!=instance_id or before.get('node_id')!=node_id:
    raise SystemExit('before snapshot does not identify the removed worker instance')
if after.get('node_id') not in (None,node_id):
    raise SystemExit(f'instance node association has an unexpected value: {after.get("node_id")!r}')
if before_ops!=after_ops:
    raise SystemExit(f'operation history changed during node removal: before={before_ops} after={after_ops}')
if sorted((row.get('id'),row.get('action'),row.get('status')) for row in after_ops) != sorted((row.get('id'),row.get('action'),row.get('status')) for row in before_ops):
    raise SystemExit('operation IDs, actions, or terminal states did not survive node removal')
print(f'customer_instance_preserved=True id={instance_id} node_after={after.get("node_id")} commercial={after.get("commercial_status")} technical={after.get("technical_status")}')
print(f'operation_history_preserved=True rows={len(after_ops)}')
PY
ssh "${hub_args[@]}" "$hub" 'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$output_dir/nodes-after-removal.json"
python3 - "$output_dir/nodes-after-removal.json" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); nodes=x if isinstance(x,list) else x.get('nodes',[])
if any(n.get('id')==sys.argv[2] for n in nodes): raise SystemExit('removed node remains in nodes list')
print(f'node_count={len(nodes)} removed_node_absent=yes')
PY
ssh "${hub_args[@]}" "$hub" sudo bash -s -- "$node_id" >"$output_dir/node-show-after-removal.log" 2>&1 <<'REMOTE'
set -u
set +e
sudo -u validator env HOME=/home/validator admiralctl nodes show "$1"
rc=$?
set -e
printf 'command_exit=%s\n' "$rc"
REMOTE
grep -F 'not found' "$output_dir/node-show-after-removal.log" >/dev/null
grep -Fx 'command_exit=1' "$output_dir/node-show-after-removal.log" >/dev/null
ssh "${worker_args[@]}" "$worker" sudo bash -s >"$output_dir/worker-after-control-plane-removal.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
systemctl is-active admiral-fleet
uid=$(id -u admiral-apps); app_home=$(getent passwd admiral-apps | cut -d: -f6)
env_args=(env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
printf 'containers='; runuser -u admiral-apps -- "${env_args[@]}" podman ps -a --format '{{.Names}}' | paste -sd, -
printf 'pods='; runuser -u admiral-apps -- "${env_args[@]}" podman pod ps --format '{{.Name}}' | paste -sd, -
printf 'volumes='; runuser -u admiral-apps -- "${env_args[@]}" podman volume ls --format '{{.Name}}' | paste -sd, -
REMOTE
printf 'finished_utc=%s\nresult=PASS\n' "$(date -u +%FT%TZ)" >>"$output_dir/metadata.txt"
echo "result=PASS evidence=$output_dir"
