#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Exercise active-instance protection and idle worker removal on R75 Fedora.
set -euo pipefail
[[ $# -eq 7 ]] || { echo "usage: $0 SSH_KEY HUB_KNOWN WORKER_KNOWN HUB_IP WORKER_IP NODE_ID OUTPUT_DIR" >&2; exit 2; }
ssh_key=$1 hub_known=$2 worker_known=$3 hub_ip=$4 worker_ip=$5 node_id=$6 output_dir=$7
[[ $node_id == adm-r75-fedora-mn-w2 && $output_dir == /* ]] || { echo 'expected absolute output and disposable Fedora W2 ID' >&2; exit 2; }
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

ssh "${hub_args[@]}" "$hub" 'rpm -q --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor | sort' >"$output_dir/candidate-hub.txt"
ssh "${worker_args[@]}" "$worker" 'rpm -q --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" admiral-common admiral-fleet | sort' >"$output_dir/candidate-worker.txt"
[[ $(grep -c -- '-0.0.1rc5-75\.fc46\.' "$output_dir/candidate-hub.txt") -eq 6 ]]
[[ $(grep -c -- '-0.0.1rc5-75\.fc46\.' "$output_dir/candidate-worker.txt") -eq 2 ]]
suffix=$(date -u +%Y%m%d%H%M%S)
customer="r75-fedora-node-removal-$suffix" key="r75-fedora-node-removal-$suffix"
printf 'test_id=R75-FEDORA-MN-NODE-REMOVE-01\ncandidate=0.0.1rc5-75.fc46\nnode_id=%s\nstarted_utc=%s\n' "$node_id" "$(date -u +%FT%TZ)" >"$output_dir/metadata.txt"
scp "${hub_args[@]}" "$fixture" "$hub:/tmp/r75-e2e-whoami-node-removal.yaml"
ssh "${hub_args[@]}" "$hub" 'sudo -u validator env HOME=/home/validator admiralctl apps apply --file /tmp/r75-e2e-whoami-node-removal.yaml' >"$output_dir/app-apply.log" 2>&1
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
[[ $endpoint =~ ^10\.99\.0\.3:[0-9]+$ ]]
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
python3 - "$output_dir/instance-after-rejected-removal.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if (x.get('node_id'),x.get('technical_status'),x.get('health_status'),x.get('effective_availability')) != ('adm-r75-fedora-mn-w2','running','healthy','available'):
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
instance_id=

ssh "${hub_args[@]}" "$hub" sudo bash -s -- "$node_id" >"$output_dir/remove-idle-node.log" 2>&1 <<'REMOTE'
set -euo pipefail
node_id=$1
printf 'y\n' | sudo -u validator env HOME=/home/validator admiralctl nodes remove "$node_id"
REMOTE
grep -F "Node \"$node_id\" removed." "$output_dir/remove-idle-node.log" >/dev/null
node_removed=1
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
printf 'finished_utc=%s\nresult=PASS-scoped\n' "$(date -u +%FT%TZ)" >>"$output_dir/metadata.txt"
echo "result=PASS scoped evidence=$output_dir"
