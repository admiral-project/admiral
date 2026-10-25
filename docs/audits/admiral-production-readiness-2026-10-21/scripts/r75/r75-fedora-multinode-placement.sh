#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Exercise explicit Release 75 placement on both Fedora Rawhide workers.
set -euo pipefail

[[ $# -eq 8 ]] || {
  echo "usage: $0 SSH_KEY HUB_KNOWN_HOSTS W1_KNOWN_HOSTS W2_KNOWN_HOSTS HUB_IP W1_IP W2_IP RUN_SUFFIX" >&2
  exit 2
}
ssh_key=$1 hub_known_hosts=$2 w1_known_hosts=$3 w2_known_hosts=$4
hub_ip=$5 w1_ip=$6 w2_ip=$7 suffix=$8
[[ $suffix =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,40}$ ]] || { echo 'invalid run suffix' >&2; exit 2; }
for path in "$ssh_key" "$hub_known_hosts" "$w1_known_hosts" "$w2_known_hosts"; do
  [[ -r $path ]] || { echo "unreadable SSH input: $path" >&2; exit 1; }
done

repo_root="${ADMIRAL_REPO_ROOT:-/root/admiral}"
fixture="$repo_root/examples/apps/e2e-whoami.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
umask 077
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes)
hub_ssh_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$hub_known_hosts")
w1_ssh_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$w1_known_hosts")
w2_ssh_args=("${ssh_args[@]}" -o "UserKnownHostsFile=$w2_known_hosts")
hub="validator@$hub_ip"
run_dir="${EVIDENCE_DIR:?set EVIDENCE_DIR to a fresh private path}/placement"
mkdir -m 0700 -- "$run_dir"
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -f $run_dir/created-instances.txt ]]; then
    while IFS= read -r instance_id; do
      [[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]] || continue
      if ! ssh "${hub_ssh_args[@]}" "$hub" \
        "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
        >/dev/null; then
        echo "cleanup failed for instance $instance_id" >&2
        rc=1
      fi
    done <"$run_dir/created-instances.txt"
  fi
  if ! ssh "${hub_ssh_args[@]}" "$hub" 'rm -f -- /tmp/r75-e2e-whoami.yaml' >/dev/null; then
    echo 'cleanup failed for uploaded workload definition' >&2
    rc=1
  fi
  find "$run_dir" -type f -exec chmod 0600 {} +
  exit "$rc"
}
trap cleanup EXIT

ssh "${hub_ssh_args[@]}" "$hub" \
  'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' \
  >"$run_dir/nodes.json"
python3 - "$run_dir/nodes.json" <<'PY'
import json,sys
nodes=json.load(open(sys.argv[1],encoding='utf-8'))
expected={'adm-r75-fedora-mn-w1','adm-r75-fedora-mn-w2'}
found={node['id'] for node in nodes if node.get('status')=='active' and node.get('health_status')=='healthy' and node.get('available_for_provisioning')}
missing=expected-found
print(f'active_healthy_available_workers={len(found & expected)}')
if missing:
    raise SystemExit(f'test precondition failed; active healthy workers missing: {sorted(missing)}')
PY

scp "${hub_ssh_args[@]}" "$fixture" "$hub:/tmp/r75-e2e-whoami.yaml"
ssh "${hub_ssh_args[@]}" "$hub" \
  'sudo -u validator env HOME=/home/validator admiralctl apps apply --file /tmp/r75-e2e-whoami.yaml'

provision_one() {
  local label=$1 node_id=$2 worker expected_ip
  case "$label" in
    w1) worker="validator@$w1_ip"; worker_args=("${w1_ssh_args[@]}"); expected_ip=10.99.0.2 ;;
    w2) worker="validator@$w2_ip"; worker_args=("${w2_ssh_args[@]}"); expected_ip=10.99.0.3 ;;
    *) echo "invalid worker label: $label" >&2; return 2 ;;
  esac
  customer="r75-fedora-${suffix}-${label}"
  key="r75-fedora-${suffix}-${label}"

  echo "test=R75-FEDORA-MN-PLACEMENT-$label start_utc=$(date -u +%FT%TZ) target=$node_id"
  local provision_rc=0
  ssh "${hub_ssh_args[@]}" "$hub" \
    "sudo -u validator env HOME=/home/validator admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$key' --node '$node_id' --wait --wait-timeout 10m --quiet --output json" \
    >"$run_dir/$label-provision.json" || provision_rc=$?
  local instance_id
  instance_id=$(python3 - "$run_dir/$label-provision.json" <<'PY' || true
import json,sys
try:
    value=json.load(open(sys.argv[1],encoding='utf-8')).get('instance_id','')
except (OSError,ValueError):
    value=''
print(value)
PY
)
  if [[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]]; then
    printf '%s\n' "$instance_id" >>"$run_dir/created-instances.txt"
  fi
  if [[ $provision_rc -ne 0 ]]; then
    echo "provision command failed with exit code $provision_rc for $node_id" >&2
    return "$provision_rc"
  fi
  [[ $instance_id =~ ^inst_[A-Za-z0-9]+$ ]] || { echo "invalid instance ID from provision: $instance_id" >&2; return 1; }
  python3 - "$run_dir/$label-provision.json" "$node_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
for k in ('id','instance_id','node_id','status','created_at','updated_at'):
    print(f'{k}={x.get(k)}')
if x.get('status')!='succeeded' or x.get('node_id')!=sys.argv[2]:
    raise SystemExit('provision did not succeed on the requested worker')
PY

  # Capture the first API view and the worker's durable tier metadata. An
  # unknown measurement may be pending, but a declared 1G tier must never be
  # reported as "no storage limit configured".
  ssh "${hub_ssh_args[@]}" "$hub" \
    "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" \
    >"$run_dir/$label-storage-first.json"
  python3 - "$run_dir/$label-storage-first.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
tier=x.get('tier_snapshot_json') or '{}'
if isinstance(tier,str): tier=json.loads(tier)
print('storage_first_api limit_bytes={} state={} message={!r} checked_at={} declared_storage={}'.format(
    x.get('storage_limit_bytes'),x.get('storage_state'),x.get('storage_message'),
    x.get('storage_checked_at'),tier.get('storage')))
if tier.get('storage')!='1G': raise SystemExit('instance snapshot does not declare the requested 1G storage tier')
if x.get('storage_message')=='no storage limit configured':
    raise SystemExit('API reported that no storage limit is configured for the declared 1G tier')
PY
  case "$label" in
    w1) worker="validator@$w1_ip"; worker_args=("${w1_ssh_args[@]}") ;;
    w2) worker="validator@$w2_ip"; worker_args=("${w2_ssh_args[@]}") ;;
  esac
  ssh "${worker_args[@]}" "$worker" sudo python3 - "$instance_id" <<'REMOTE' >"$run_dir/$label-tier-file.txt"
import json,os,stat,sys
path=f'/var/lib/admiral/instances/{sys.argv[1]}/tier.json'
st=os.stat(path,follow_symlinks=False)
data=json.load(open(path,encoding='utf-8'))
print(f'tier_file={path} owner_uid={st.st_uid} mode={stat.S_IMODE(st.st_mode):04o} storage={data.get("storage")}')
if st.st_uid!=0 or stat.S_IMODE(st.st_mode)!=0o600 or data.get('storage')!='1G':
    raise SystemExit('tier metadata is not securely persisted with the declared 1G storage limit')
REMOTE
  cat "$run_dir/$label-tier-file.txt"

  ssh "${hub_ssh_args[@]}" "$hub" \
    "sudo -u validator env HOME=/home/validator admiralctl instances provision --app e2e-whoami --tier small --customer '$customer' --idempotency-key '$key' --node '$node_id' --wait --wait-timeout 2m --quiet --output json" \
    >"$run_dir/$label-replay.json"
  python3 - "$run_dir/$label-provision.json" "$run_dir/$label-replay.json" <<'PY'
import json,sys
a,b=(json.load(open(p,encoding='utf-8')) for p in sys.argv[1:])
print(f"idempotency_replay_same_operation={a.get('id')==b.get('id')}")
print(f"idempotency_replay_same_instance={a.get('instance_id')==b.get('instance_id')}")
if a.get('id')!=b.get('id') or a.get('instance_id')!=b.get('instance_id'):
    raise SystemExit('same-key replay did not return the original operation and instance')
PY

  local converged=0
  for attempt in $(seq 1 60); do
    if ! ssh "${hub_ssh_args[@]}" "$hub" \
      "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" \
      >"$run_dir/$label-instance.json"; then
      echo "instance inspection failed on health-convergence poll $attempt" >&2
      sleep 5
      continue
    fi
    if python3 - "$run_dir/$label-instance.json" "$node_id" "$attempt" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
for k in ('id','node_id','technical_status','health_status','effective_availability','availability_reason','health_message','last_health_checked_at'):
    print(f'{k}={x.get(k)}')
if x.get('node_id')!=sys.argv[2]:
    raise SystemExit('instance was assigned to a different worker')
if x.get('technical_status')=='deprovisioned' or x.get('availability_reason')=='instance_deprovisioned':
    raise SystemExit('instance was deprovisioned before becoming healthy')
if x.get('health_status')=='healthy' and x.get('effective_availability')=='available':
    print(f'health_converged_poll={sys.argv[3]}')
    raise SystemExit(0)
raise SystemExit(1)
PY
    then
      converged=1
      break
    fi
    [[ $attempt -lt 60 ]] || break
    sleep 5
  done
  [[ $converged -eq 1 ]] || { echo 'instance did not converge to healthy/available within 5 minutes' >&2; return 1; }

  # Wait for at least one real Fleet storage measurement and require the
  # configured limit to survive reporting. The checker is periodic, so the
  # API can initially expose an empty pending measurement.
  local storage_converged=0 stable_storage_samples=0 storage_rc
  for attempt in $(seq 1 36); do
    ssh "${hub_ssh_args[@]}" "$hub" \
      "sudo -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" \
      >"$run_dir/$label-storage-$attempt.json"
    set +e
    python3 - "$run_dir/$label-storage-$attempt.json" "$attempt" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
tier=x.get('tier_snapshot_json') or '{}'
if isinstance(tier,str): tier=json.loads(tier)
limit=x.get('storage_limit_bytes') or 0
state=x.get('storage_state') or ''
message=x.get('storage_message') or ''
checked=x.get('storage_checked_at')
print('storage_sample={} limit_bytes={} state={} message={!r} checked_at={} tier={}'.format(
    sys.argv[2],limit,state,message,checked,tier.get('storage')))
if tier.get('storage')!='1G': raise SystemExit(2)
if message=='no storage limit configured': raise SystemExit(2)
if limit==0 and state=='unknown' and not checked: raise SystemExit(1)
if limit!=1073741824: raise SystemExit(2)
if state=='unknown': raise SystemExit(1)
if state not in {'ok','warning','critical','over_quota','grace_period','suspended'}: raise SystemExit(2)
PY
    storage_rc=$?
    set -e
    if [[ $storage_rc -eq 0 ]]; then
      stable_storage_samples=$((stable_storage_samples + 1))
      if [[ $stable_storage_samples -ge 2 ]]; then storage_converged=1; break; fi
    elif [[ $storage_rc -eq 1 ]]; then
      stable_storage_samples=0
    else
      echo 'Fleet storage report contradicted the declared 1G tier' >&2
      return 1
    fi
    [[ $attempt -lt 36 ]] || break
    sleep 5
  done
  [[ $storage_converged -eq 1 ]] || { echo 'Fleet storage report did not converge to the declared 1G limit within 3 minutes' >&2; return 1; }
  echo "configured_storage_limit_converged_${label}=PASS samples=$stable_storage_samples"

  ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" "$expected_ip" \
    >"$run_dir/$label-runtime.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1 expected_ip=$2
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
  [[ $attempt -lt 60 ]] || { echo 'database did not become ready within 5 minutes'; exit 1; }
  sleep 5
done
podman_as_apps ps --all --filter "name=$instance_id" --format '{{.Names}}|{{.Status}}|{{.Ports}}'
endpoint=$(podman_as_apps port "$app" 80/tcp | head -n1)
[[ $endpoint =~ ^([0-9.]+):([0-9]+)$ ]] || { echo "unexpected mapped endpoint: $endpoint"; exit 1; }
[[ ${BASH_REMATCH[1]} == "$expected_ip" ]] || { echo "app bound to unexpected interface: $endpoint"; exit 1; }
printf 'app_endpoint=%s\n' "$endpoint"
marker="r75-fedora-${instance_id}"
sql="CREATE TABLE IF NOT EXISTS admiral_audit_marker (value TEXT PRIMARY KEY); INSERT INTO admiral_audit_marker(value) VALUES ('$marker') ON CONFLICT DO NOTHING; SELECT value FROM admiral_audit_marker WHERE value = '$marker';"
podman_as_apps exec "$db" sh -c \
  'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"' \
  sh "$sql"
REMOTE
  cat "$run_dir/$label-runtime.txt"
  local endpoint http_code
  endpoint=$(sed -n 's/^app_endpoint=//p' "$run_dir/$label-runtime.txt" | tail -n1)
  [[ $endpoint =~ ^10\.99\.0\.[23]:[0-9]+$ ]] || { echo "invalid workload endpoint: $endpoint"; return 1; }
  http_code=$(ssh "${hub_ssh_args[@]}" "$hub" \
    "curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' 'http://$endpoint/'")
  printf 'hub_to_workload_http_status=%s endpoint=%s\n' "$http_code" "$endpoint"
  [[ $http_code == 200 ]] || { echo 'hub could not reach the workload HTTP endpoint'; return 1; }

  ssh "${hub_ssh_args[@]}" "$hub" \
    "sudo -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 10m --output json" \
    >"$run_dir/$label-deprovision.json"
  python3 - "$run_dir/$label-deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(f"deprovision_operation={x.get('id')} status={x.get('status')}")
if x.get('status')!='succeeded':
    raise SystemExit('deprovision did not succeed')
PY
  ssh "${worker_args[@]}" "$worker" sudo bash -s -- "$instance_id" <<'REMOTE'
set -euo pipefail
cd /tmp
instance_id=$1
uid=$(id -u admiral-apps)
remaining=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman ps -a \
  --filter "name=$instance_id" --format '{{.Names}}')
printf 'remaining_matching_containers=%s\n' "${remaining:-none}"
[[ -z $remaining ]] || exit 1
pods=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman pod ps \
  --format '{{.Name}}' | grep -F "$instance_id" || true)
volumes=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" podman volume ls \
  --format '{{.Name}}' | grep -F "$instance_id" || true)
units=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
  systemctl --user list-unit-files --no-legend | grep -F "$instance_id" || true)
files=$(find /etc/containers/systemd /var/lib/admiral -iname "*$instance_id*" -print 2>/dev/null || true)
printf 'remaining_matching_pods=%s\nremaining_matching_volumes=%s\nremaining_matching_units=%s\nremaining_matching_files=%s\n' \
  "${pods:-none}" "${volumes:-none}" "${units:-none}" "${files:-none}"
[[ -z $pods && -z $volumes && -z $units && -z $files ]] || exit 1
REMOTE
  echo "placement_lifecycle_${label}=PASS instance=$instance_id end_utc=$(date -u +%FT%TZ)"
}

provision_one w1 adm-r75-fedora-mn-w1
provision_one w2 adm-r75-fedora-mn-w2
