#!/usr/bin/env bash
# Verify a successful Single-Node tier resize and data/workload continuity.
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 CUSTOMER IDEMPOTENCY_KEY" >&2; exit 2; }
customer=$1 key=$2
[[ $customer =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo 'invalid customer ID' >&2; exit 2; }
[[ $key =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$ ]] || { echo 'invalid idempotency key' >&2; exit 2; }

cd /
run_dir="/var/tmp/adm-r74-resize-${customer}"
install -d -m 0700 "$run_dir"
cp /tmp/audit-e2e-resize.yaml "$run_dir/fixture.yaml"
chmod 0600 "$run_dir/fixture.yaml"
instance_id=
cleanup() {
  rc=$?
  trap - EXIT
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
  exit "$rc"
}
trap cleanup EXIT

admiralctl apps apply --file "$run_dir/fixture.yaml" >"$run_dir/apply.log" 2>&1
printf 'test=R74-SN-RESIZE\nstart_utc=%s\n' "$(date -u +%FT%TZ)"
admiralctl instances provision --app e2e-resize-audit --tier small --customer "$customer" \
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
uid=$(id -u admiral-apps)

wait_tier() {
  local target=$1 attempt fields
  for attempt in $(seq 1 60); do
    admiralctl instances show "$instance_id" >"$run_dir/state.json"
    fields=$(python3 - "$run_dir/state.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('tier_name',''),x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)
    if [[ $fields == "$target running healthy available" ]]; then
      printf 'tier=%s state=%s\n' "$target" "$fields"
      return 0
    fi
    sleep 3
  done
  echo "instance did not converge to tier $target: $fields" >&2
  return 1
}

probe_workload() {
  local label=$1 endpoint code marker_value
  endpoint=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    podman port "admiral-${instance_id}-app" 80/tcp | head -n1)
  [[ $endpoint =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo "unexpected endpoint: $endpoint" >&2; return 1; }
  code=$(curl --connect-timeout 3 --max-time 10 -sS -o /dev/null -w '%{http_code}' "http://$endpoint/")
  printf '%s_http=%s endpoint=%s\n' "$label" "$code" "$endpoint"
  [[ $code == 200 ]] || return 1
  marker_value=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    podman exec "admiral-${instance_id}-db" sh -c \
    'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT value FROM admiral_audit_marker WHERE value = '\''r74-resize-marker'\''"')
  printf '%s_sql_marker=%s\n' "$label" "$marker_value"
  [[ $marker_value == r74-resize-marker ]]
}

wait_tier small
runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" \
  podman exec "admiral-${instance_id}-db" sh -c \
  'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS admiral_audit_marker(value TEXT PRIMARY KEY); INSERT INTO admiral_audit_marker(value) VALUES ('\''r74-resize-marker'\'') ON CONFLICT DO NOTHING"' \
  >"$run_dir/marker-before.txt"
probe_workload before_resize

for target in medium small; do
  printf 'resize_target=%s requested_utc=%s\n' "$target" "$(date -u +%FT%TZ)"
  printf 'y\n' | admiralctl instances resize "$instance_id" --tier "$target" --wait \
    --wait-timeout 10m --output json >"$run_dir/resize-${target}.json"
  python3 - "$run_dir/resize-${target}.json" "$target" <<'PY'
import json,sys
text=open(sys.argv[1],encoding='utf-8').read()
start=text.find('{')
if start < 0:
    raise SystemExit('resize command returned no JSON object')
x=json.loads(text[start:])
print('resize_operation=',x.get('id'),'status=',x.get('status'),'tier=',x.get('tier_name'))
if x.get('action')!='resize_app' or x.get('status')!='succeeded':
    raise SystemExit('resize operation did not succeed')
PY
  wait_tier "$target"
  probe_workload "after_${target}"
done

printf 'resize_data_and_health=PASS\nend_utc=%s\n' "$(date -u +%FT%TZ)"
