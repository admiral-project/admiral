#!/usr/bin/env bash
# Stop a disposable workload's PostgreSQL user unit, observe API health, restart,
# verify persisted data, and always attempt to deprovision the test instance.
set -euo pipefail
cd /
[[ $# -eq 3 ]] || { echo "usage: $0 {fedora|rocky|alma|centos} CUSTOMER IDEMPOTENCY_KEY" >&2; exit 2; }
os=$1 customer=$2 key=$3
run_dir="/var/tmp/adm-r69-${os}-db-outage"
install -d -m 0700 "$run_dir"
cp /tmp/audit-e2e-backup.yaml "$run_dir/fixture.yaml"
chmod 0600 "$run_dir/fixture.yaml"
printf 'os=%s start_utc=%s\n' "$os" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
admiralctl apps apply --file "$run_dir/fixture.yaml" > "$run_dir/apply.log" 2>&1
admiralctl instances provision --app e2e-backup --tier small --customer "$customer" --idempotency-key "$key" --wait --wait-timeout 10m --quiet --output json > "$run_dir/provision.json"
instance_id=$(python3 - "$run_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'):
    raise SystemExit('initial provision did not succeed')
print(x['instance_id'])
PY
)
uid=$(id -u admiral-apps)
db_container="admiral-${instance_id}-db"
db_unit="admiral-${instance_id}-db.service"
cleanup_enabled=1
cleanup() {
  rc=$?
  trap - EXIT
  if [[ ${cleanup_enabled:-0} -eq 1 ]]; then
    runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user start "$db_unit" >/dev/null 2>&1 || true
    admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 10m --output json > "$run_dir/trap-deprovision.json" 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT
printf 'instance_id=%s db_unit=%s\n' "$instance_id" "$db_unit"
runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active "$db_unit" | tee "$run_dir/db-unit-before.txt"
runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" podman exec "$db_container" pg_isready -h 127.0.0.1 -p 5432 | tee "$run_dir/db-ready-before.txt"
printf "CREATE TABLE IF NOT EXISTS admiral_outage_marker (value TEXT PRIMARY KEY); TRUNCATE admiral_outage_marker; INSERT INTO admiral_outage_marker(value) VALUES ('r69-db-outage-persisted');\n" | runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" podman exec -i "$db_container" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' > "$run_dir/marker-before.txt"
cat "$run_dir/marker-before.txt"
baseline_deadline=$(( $(date +%s) + 30 ))
baseline_checked_at=''
while (( $(date +%s) < baseline_deadline )); do
  baseline_health=$(admiralctl instances show "$instance_id")
  read -r baseline_status baseline_availability baseline_checked_at < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("health_status", ""), x.get("effective_availability", ""), x.get("last_health_checked_at", ""))' <<<"$baseline_health")
  if [[ $baseline_status == healthy && $baseline_availability == available && -n $baseline_checked_at ]]; then
    break
  fi
  sleep 0.25
done
[[ $baseline_status == healthy && $baseline_availability == available && -n $baseline_checked_at ]] || {
  echo 'database workload did not reach a current healthy baseline within 30 seconds' >&2
  exit 1
}
fresh_report_deadline=$(( $(date +%s) + 20 ))
fresh_report_checked_at=''
while (( $(date +%s) < fresh_report_deadline )); do
  current_health=$(admiralctl instances show "$instance_id")
  read -r current_status current_availability current_checked_at < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("health_status", ""), x.get("effective_availability", ""), x.get("last_health_checked_at", ""))' <<<"$current_health")
  if [[ $current_status == healthy && $current_availability == available && $current_checked_at != "$baseline_checked_at" ]]; then
    fresh_report_checked_at=$current_checked_at
    break
  fi
  sleep 0.1
done
[[ -n $fresh_report_checked_at ]] || { echo 'Fleet did not produce a fresh healthy report before outage' >&2; exit 1; }
printf 'fresh_healthy_report_before_outage=%s observed_utc=%s\n' "$fresh_report_checked_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user stop "$db_unit"
stopped=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active "$db_unit" 2>/dev/null || true)
printf 'db_unit_after_stop=%s utc=%s\n' "$stopped" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ $stopped != active ]] || { echo 'database systemd unit remained active after stop'; exit 1; }
outage_start_epoch_ns=$(date +%s%N)

api_pids=()
api_samples=0
for attempt in $(seq 0 60); do
  sample_started_ns=$(date +%s%N)
  elapsed_ms=$(( (sample_started_ns - outage_start_epoch_ns) / 1000000 ))
  unit_state=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active "$db_unit" 2>/dev/null || true)
  runtime=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" podman inspect --format '{{.State.Status}}' "$db_container" 2>/dev/null || printf absent)
  [[ $runtime != running ]] || { echo 'database container restarted unexpectedly while its user unit was stopped'; exit 1; }
  printf '%s %s %s\n' "$elapsed_ms" "$unit_state" "$runtime" > "$run_dir/outage-local-$attempt.txt"
  (
    admiralctl instances show "$instance_id" > "$run_dir/instance-outage-$attempt.json" 2>"$run_dir/instance-outage-$attempt.stderr"
    rc=$?
    printf '%s %s\n' "$sample_started_ns" "$(date +%s%N)" > "$run_dir/instance-outage-$attempt.timing"
    exit "$rc"
  ) &
  api_pids+=("$!")
  ((api_samples+=1))
  if [[ $attempt -lt 60 ]]; then
    target_ns=$((outage_start_epoch_ns + (attempt + 1) * 1000000000))
    now_ns=$(date +%s%N)
    remaining_ns=$((target_ns - now_ns))
    if (( remaining_ns > 0 )); then
      sleep "$(awk -v ns="$remaining_ns" 'BEGIN { printf "%.3f", ns / 1000000000 }')"
    fi
  fi
done

for pid in "${api_pids[@]}"; do
  wait "$pid" || { echo 'an API health sample failed'; exit 1; }
done

healthy_available_polls=0
late_healthy_available_polls=0
first_unavailable_elapsed_ms=-1
last_sample_started_ns=0
for attempt in $(seq 0 60); do
  read -r elapsed_ms unit_state runtime < "$run_dir/outage-local-$attempt.txt"
  read -r sample_started_ns sample_finished_ns < "$run_dir/instance-outage-$attempt.timing"
  fields=$(python3 - "$run_dir/instance-outage-$attempt.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)
  read -r tech health avail <<< "$fields"
  response_ms=$(( (sample_finished_ns - sample_started_ns) / 1000000 ))
  printf 'outage_poll=%s elapsed_ms=%s utc=%s response_ms=%s unit=%s api=%s db_runtime=%s\n' \
    "$attempt" "$elapsed_ms" "$(date -u -d "@$((${sample_started_ns} / 1000000000))" +%Y-%m-%dT%H:%M:%SZ)" \
    "$response_ms" "$unit_state" "$fields" "$runtime"
  last_sample_started_ns=$sample_started_ns
  if [[ $health == healthy && $avail == available ]]; then
    ((healthy_available_polls+=1))
    if (( elapsed_ms >= 5000 )); then ((late_healthy_available_polls+=1)); fi
  elif (( first_unavailable_elapsed_ms < 0 )); then
    first_unavailable_elapsed_ms=$elapsed_ms
  fi
done
observation_ms=$(( (last_sample_started_ns - outage_start_epoch_ns) / 1000000 ))
printf 'outage_observation_ms=%s samples=%s healthy_available_polls=%s stale_after_5s_polls=%s first_unavailable_elapsed_ms=%s sample_interval_target_ms=1000\n' \
  "$observation_ms" "$api_samples" "$healthy_available_polls" "$late_healthy_available_polls" "$first_unavailable_elapsed_ms"
[[ $api_samples -eq 61 && $observation_ms -ge 59000 ]] || { echo 'did not collect 61 per-second samples across at least 59 seconds' >&2; exit 1; }
[[ $first_unavailable_elapsed_ms -ge 0 && $first_unavailable_elapsed_ms -lt 5000 ]] || { echo 'API did not leave healthy/available within one 5-second health tick' >&2; exit 1; }
[[ $late_healthy_available_polls -eq 0 ]] || { echo 'API returned healthy/available at or after the 5-second health tick while PostgreSQL remained stopped' >&2; exit 1; }

runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user start "$db_unit"
recovered=0
for attempt in $(seq 1 48); do
  state=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active "$db_unit" 2>/dev/null || true)
  ready=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" podman exec "$db_container" pg_isready -h 127.0.0.1 -p 5432 2>&1 || true)
  admiralctl instances show "$instance_id" > "$run_dir/instance-recovery-$attempt.json"
  fields=$(python3 - "$run_dir/instance-recovery-$attempt.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)
  printf 'recovery_poll=%s utc=%s unit=%s db=%s api=%s\n' "$attempt" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$state" "$ready" "$fields"
  read -r tech health avail <<< "$fields"
  if [[ $state == active && $ready == *'accepting connections'* && $health == healthy && $avail == available ]]; then recovered=1; break; fi
  [[ $attempt -lt 48 ]] || break
  sleep 5
done
if [[ $recovered -eq 1 ]]; then
  printf 'SELECT value FROM admiral_outage_marker;\n' | runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" podman exec -i "$db_container" sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' > "$run_dir/marker-after.txt"
  cat "$run_dir/marker-after.txt"
  [[ $(cat "$run_dir/marker-after.txt") == r69-db-outage-persisted ]] || recovered=0
fi

cleanup_rc=0
admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 10m --output json > "$run_dir/deprovision.json" 2> "$run_dir/deprovision.stderr" || cleanup_rc=$?
cat "$run_dir/deprovision.json" "$run_dir/deprovision.stderr"
printf 'deprovision_exit=%s\n' "$cleanup_rc"
resources=$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/$uid" podman ps --all --filter name="$instance_id" --format '{{.Names}}|{{.Status}}')
printf '%s\n' "$resources" > "$run_dir/resources-after-cleanup.txt"
[[ -z $resources ]] || { printf '%s\n' "$resources"; cleanup_rc=1; }
[[ $cleanup_rc -eq 0 ]] || { echo 'cleanup failed after database outage probe' >&2; exit 1; }
[[ $recovered -eq 1 ]] || { echo 'database service did not return healthy with persisted marker' >&2; exit 1; }
cleanup_enabled=0
echo 'database_service_outage_and_recovery=PASS'
printf 'end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
