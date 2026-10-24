#!/usr/bin/env bash
# Exercise instance lifecycle and explicit admirald stop/start/restart on a
# disposable Release 69 Single-Node validation guest.
set -euo pipefail
[[ $# -eq 3 ]] || {
  echo "usage: $0 {fedora|rocky|alma|centos} CUSTOMER IDEMPOTENCY_KEY" >&2
  exit 2
}
os=$1 customer=$2 key=$3
[[ $os =~ ^(fedora|rocky|alma|centos)$ ]] || { echo 'unsupported OS key' >&2; exit 2; }
[[ $customer =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo 'invalid customer ID' >&2; exit 2; }
[[ $key =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$ ]] || { echo 'invalid idempotency key' >&2; exit 2; }

cd /
run_dir="/var/tmp/adm-r75-${os}-control-plane-lifecycle"
install -d -m 0700 "$run_dir"
cp /tmp/audit-e2e-whoami.yaml "$run_dir/fixture.yaml"
chmod 0600 "$run_dir/fixture.yaml"
instance_id=
cleanup() {
  rc=$?
  trap - EXIT
  systemctl start admirald.service >/dev/null 2>&1 || rc=1
  if [[ -n ${instance_id:-} ]]; then
    admiralctl instances deprovision "$instance_id" --force --wait \
      --wait-timeout 10m --output json >"$run_dir/deprovision.json" 2>&1 || rc=1
    uid=$(id -u admiral-apps)
    if runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        podman ps --all --filter name="$instance_id" --format '{{.Names}}' \
        | grep -F "$instance_id"; then
      echo 'matching Podman container remains after cleanup' >&2
      rc=1
    fi
  fi
  printf 'cleanup_rc=%s\n' "$rc"
  exit "$rc"
}
trap cleanup EXIT

admiralctl apps apply --file "$run_dir/fixture.yaml" >"$run_dir/apply.log" 2>&1
printf 'test=R75-%s-SN-CONTROL-PLANE-LIFECYCLE\nstart_utc=%s\n' "$os" "$(date -u +%FT%TZ)"
admiralctl instances provision --app e2e-whoami --tier small --customer "$customer" \
  --idempotency-key "$key" --wait --wait-timeout 10m --quiet --output json \
  >"$run_dir/provision.json"
instance_id=$(python3 - "$run_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'):
    raise SystemExit('initial provision did not succeed')
print(x['instance_id'])
PY
)
printf 'instance_id=%s\n' "$instance_id"

wait_available() {
  local label=$1 attempt fields status health availability uid endpoint code
  uid=$(id -u admiral-apps)
  for attempt in $(seq 1 60); do
    if admiralctl instances show "$instance_id" >"$run_dir/state.json" 2>/dev/null; then
      fields=$(python3 - "$run_dir/state.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)
      read -r status health availability <<<"$fields"
      if [[ $status == running && $health == healthy && $availability == available ]]; then
        endpoint=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          podman port "admiral-${instance_id}-app" 80/tcp | head -n1)
        [[ $endpoint =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo "unexpected endpoint: $endpoint" >&2; return 1; }
        code=$(curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' "http://$endpoint/")
        printf '%s_available_poll=%s http=%s endpoint=%s\n' "$label" "$attempt" "$code" "$endpoint"
        [[ $code == 200 ]] && return 0
      else
        printf '%s_poll=%s state=%s\n' "$label" "$attempt" "$fields"
      fi
    fi
    sleep 3
  done
  echo "$label: instance did not return to running/healthy/available with HTTP 200" >&2
  return 1
}

run_instance_action() {
  local action=$1
  admiralctl instances "$action" "$instance_id" --force --wait --wait-timeout 10m \
    --output json >"$run_dir/${action}.json"
  python3 - "$run_dir/${action}.json" "$action" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print('operation=',x.get('id'),'action_status=',x.get('status'))
if x.get('status')!='succeeded': raise SystemExit('instance action did not succeed')
PY
}

wait_available initial
for action in pause resume stop start restart; do
  printf 'action=%s requested_utc=%s\n' "$action" "$(date -u +%FT%TZ)"
  run_instance_action "$action"
  if [[ $action != pause && $action != stop ]]; then wait_available "$action"; fi
done

systemctl restart admirald.service
systemctl is-active --quiet admirald.service
wait_available admirald_restart

systemctl stop admirald.service
if systemctl is-active --quiet admirald.service; then
  echo 'admirald remained active after systemctl stop' >&2
  exit 1
fi
set +e
admiralctl status >"$run_dir/status-while-stopped.json" 2>"$run_dir/status-while-stopped.stderr"
status_rc=$?
set -e
printf 'admiralctl_status_while_service_stopped_exit=%s\n' "$status_rc"
[[ $status_rc -ne 0 ]] || { echo 'CLI unexpectedly reached stopped admirald'; exit 1; }
systemctl start admirald.service
systemctl is-active --quiet admirald.service
wait_available admirald_start

printf 'instance_and_control_plane_lifecycle=PASS\nend_utc=%s\n' "$(date -u +%FT%TZ)"
