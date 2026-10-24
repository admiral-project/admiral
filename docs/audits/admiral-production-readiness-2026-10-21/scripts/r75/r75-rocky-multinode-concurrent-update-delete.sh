#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Race resize against deprovision on one disposable R75 Rocky Linux worker.
set -euo pipefail

[[ $# -eq 7 ]] || {
  echo "usage: $0 SSH_KEY HUB_KNOWN_HOSTS WORKER_KNOWN_HOSTS HUB_IP WORKER_IP NODE_ID OUTPUT_DIR" >&2
  exit 2
}
ssh_key=$1 hub_known_hosts=$2 worker_known_hosts=$3
hub_ip=$4 worker_ip=$5 node_id=$6 output_dir=$7
[[ $node_id =~ ^adm-r75-rocky-mn-w[12]$ ]] || { echo 'invalid worker node ID' >&2; exit 2; }
[[ $output_dir == /* && ! -e $output_dir && ! -L $output_dir ]] || {
  echo 'output directory must be an unused absolute path' >&2
  exit 2
}
for path in "$ssh_key" "$hub_known_hosts" "$worker_known_hosts"; do
  [[ -r $path ]] || { echo "unreadable SSH input: $path" >&2; exit 1; }
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../../../.." && pwd)
fixture="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-resize.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
install -d -m 0700 "$output_dir"
umask 077
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes)
hub_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$hub_known_hosts")
worker_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$worker_known_hosts")
hub="validator@$hub_ip"
worker="validator@$worker_ip"
suffix=$(date -u +%Y%m%d%H%M%S)
customer="r75-rocky-race-$suffix"
idempotency_key="r75-rocky-race-$suffix"
remote_fixture="/tmp/r74-e2e-resize-${suffix}.yaml"
instance_id=

ssh_hub() { ssh "${hub_args[@]}" "$hub" "$@"; }
ssh_worker() { ssh "${worker_args[@]}" "$worker" "$@"; }

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n $instance_id ]]; then
    ssh_hub \
      "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
      >"$output_dir/final-deprovision-on-exit.json" 2>&1 || true
  fi
  ssh_hub "rm -f -- '$remote_fixture'" >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT

for pkg in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
  ssh_hub "rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\\n' '$pkg'"
done >"$output_dir/hub-nevra.txt"
ssh_worker "rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\\n' admiral-common admiral-fleet" >"$output_dir/worker-nevra.txt"
if grep -v '0\.0\.1rc5-75\.el10' "$output_dir/hub-nevra.txt" || \
   ! grep -Fxq 'admiral-common-0.0.1rc5-75.el10.noarch' "$output_dir/worker-nevra.txt" || \
   ! grep -Fxq 'admiral-fleet-0.0.1rc5-75.el10.x86_64' "$output_dir/worker-nevra.txt"; then
  echo 'hub or worker is not running the expected exact Release 74 package set' >&2
  exit 1
fi

scp "${hub_args[@]}" "$fixture" "$hub:$remote_fixture"
ssh_hub "sudo -u validator env HOME=/home/validator admiralctl apps apply --file '$remote_fixture'" \
  >"$output_dir/app-apply.log" 2>&1
ssh_hub \
  "sudo -u validator env HOME=/home/validator admiralctl instances provision --app e2e-resize-audit --tier small --customer '$customer' --idempotency-key '$idempotency_key' --node '$node_id' --wait --wait-timeout 10m --quiet --output json" \
  >"$output_dir/provision.json"
instance_id=$(python3 - "$output_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'):
    raise SystemExit('initial provision did not succeed')
print(x['instance_id'])
PY
)
printf 'candidate=0.0.1rc5-75.el10\nnode_id=%s\ninstance_id=%s\nstart_utc=%s\n' \
  "$node_id" "$instance_id" "$(date -u +%FT%TZ)" >"$output_dir/metadata.txt"

ssh_worker sudo bash -s -- "$instance_id" >"$output_dir/runtime-before-race.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1
uid=$(id -u admiral-apps)
run_as_apps() { runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman "$@"; }
db="admiral-${instance_id}-db"
ready=0
for attempt in $(seq 1 60); do
  if run_as_apps exec "$db" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then ready=1; break; fi
  sleep 5
done
[[ $ready -eq 1 ]] || { echo 'workload DB did not become ready'; exit 1; }
containers=$(run_as_apps ps --filter "name=$instance_id" --format '{{.Names}}')
printf 'containers=%s\n' "$containers"
[[ $(printf '%s\n' "$containers" | wc -l) -eq 3 ]]
REMOTE

set +e
(
  set +e
  printf 'y\n' | ssh_hub \
    "sudo -u validator env HOME=/home/validator admiralctl instances resize --tier medium '$instance_id' --wait --wait-timeout 10m --output json" \
    >"$output_dir/resize.json" 2>"$output_dir/resize.stderr"
  printf '%s\n' "$?" >"$output_dir/resize.exit"
) &
resize_pid=$!
sleep 0.25
(
  set +e
  ssh_hub \
    "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
    >"$output_dir/deprovision.json" 2>"$output_dir/deprovision.stderr"
  printf '%s\n' "$?" >"$output_dir/deprovision.exit"
) &
deprovision_pid=$!
wait "$resize_pid"
wait "$deprovision_pid"
set -e
[[ -s $output_dir/resize.exit && -s $output_dir/deprovision.exit ]] || {
  echo 'a concurrent CLI process did not record its exit status' >&2
  exit 1
}

python3 - "$output_dir/resize.json" "$output_dir/deprovision.json" "$output_dir/operation-summary.txt" <<'PY'
import json,sys
def load(path):
    text=open(path,encoding='utf-8').read()
    start=text.find('{')
    if start < 0:
        raise SystemExit(f'CLI output has no JSON object: {path}')
    return json.loads(text[start:])
resize,delete=map(load,sys.argv[1:3])
summary=(f"resize_operation={resize.get('id')} status={resize.get('status')}\n"
         f"deprovision_operation={delete.get('id')} status={delete.get('status')}\n")
open(sys.argv[3],'w',encoding='utf-8').write(summary)
if resize.get('action')!='resize_app' or resize.get('status') not in ('succeeded','failed','cancelled'):
    raise SystemExit('resize did not reach an explicit terminal state')
if delete.get('action')!='deprovision_app' or delete.get('status')!='succeeded':
    raise SystemExit('deprovision did not succeed')
PY
printf 'resize_exit=%s\ndeprovision_exit=%s\n' "$(cat "$output_dir/resize.exit")" "$(cat "$output_dir/deprovision.exit")" >>"$output_dir/operation-summary.txt"

ssh_hub "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" \
  >"$output_dir/instance-after-race.json"
sleep 30
ssh_hub "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" \
  >"$output_dir/instance-after-settle.json"
python3 - "$output_dir/instance-after-race.json" "$output_dir/instance-after-settle.json" <<'PY'
import json,sys
for path in sys.argv[1:]:
    x=json.load(open(path,encoding='utf-8'))
    print(f"instance={x.get('id')} technical={x.get('technical_status')} availability={x.get('effective_availability')}")
    if x.get('technical_status')!='deprovisioned':
        raise SystemExit(f'instance not deprovisioned in {path}')
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
units=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user list-units --all --no-legend "admiral-${instance_id}*" 2>/dev/null || true)
files=$(find /etc/containers/systemd /var/lib/admiral -xdev -iname "*$instance_id*" -print 2>/dev/null || true)
printf 'containers=%s\npods=%s\nvolumes=%s\nunits=%s\nfiles=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}" "${units:-none}" "${files:-none}"
[[ -z $containers && -z $pods && -z $volumes && -z $units && -z $files ]]
REMOTE
instance_id=
find "$output_dir" -maxdepth 1 -type f -exec chmod 0600 {} +
(cd "$output_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
chmod 0600 "$output_dir/SHA256SUMS"
echo "concurrent_update_delete=PASS evidence=$output_dir"
