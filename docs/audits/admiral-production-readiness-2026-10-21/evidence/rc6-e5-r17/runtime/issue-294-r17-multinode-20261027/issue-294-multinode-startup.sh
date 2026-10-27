#!/usr/bin/env bash
set -euo pipefail
umask 077

root=$(git rev-parse --show-toplevel)
key=/var/lib/libvirt/images/admiral-validation/keys/rc6-e5-r15-validator
admin_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r15-rocky-admin/known_hosts
worker_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r15-rocky-worker/known_hosts
admin=10.77.0.130
worker=10.77.0.132
run_dir="$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r17/runtime/issue-294-r17-multinode-20261027"
mkdir -m 0700 -p "$run_dir"

ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5)
ssh_admin() { ssh "${ssh_args[@]}" -o "UserKnownHostsFile=$admin_known" "validator@$admin" "$@"; }
ssh_worker() { ssh "${ssh_args[@]}" -o "UserKnownHostsFile=$worker_known" "validator@$worker" "$@"; }

admin_stopped=0
worker_stopped=0
restore_services() {
  rc=$?
  trap - EXIT
  if (( admin_stopped )); then ssh_admin 'sudo -n systemctl start admirald' >>"$run_dir/recovery.log" 2>&1 || true; fi
  if (( worker_stopped )); then ssh_worker 'sudo -n systemctl start admiral-fleet' >>"$run_dir/recovery.log" 2>&1 || true; fi
  exit "$rc"
}
trap restore_services EXIT

printf 'issue=294 candidate=rc6-e5-r17 topology=rocky-multinode start_utc=%s\n' "$(date -u +%FT%TZ)" | tee "$run_dir/run.log"
ssh_admin 'hostname; rpm -q admiral-common admiralctl admirald; sudo -n systemctl is-active admirald' | tee "$run_dir/admin-before.log"
ssh_worker 'hostname; rpm -q admiral-common admiral-fleet; sudo -n systemctl is-active admiral-fleet; free -m; df -h /' | tee "$run_dir/worker-before.log"
ssh_admin 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-before.json"
python3 - "$run_dir/nodes-before.json" <<'PY' | tee -a "$run_dir/run.log"
import json, sys
nodes = json.load(open(sys.argv[1], encoding="utf-8"))
worker = next((n for n in nodes if n.get("id") == "rc6e5r15-rocky-worker"), None)
if not worker or (worker.get("status"), worker.get("health_status"), worker.get("available_for_provisioning")) != ("active", "healthy", True):
    raise SystemExit("precondition failed: Worker is not active/healthy/available")
print("baseline_worker", worker["status"], worker["health_status"], worker["available_for_provisioning"], worker.get("last_metrics_at"), sep="\t")
PY

ssh_worker 'sudo -n systemctl stop admiral-fleet && test "$(sudo -n systemctl is-active admiral-fleet || true)" = inactive'
worker_stopped=1
printf 'fleet_stopped_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
ssh_admin 'sudo -n systemctl stop admirald && test "$(sudo -n systemctl is-active admirald || true)" = inactive'
admin_stopped=1
printf 'admirald_stopped_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
sleep 125
printf 'restart_window_seconds=125 end_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"

ssh_admin 'sudo -n systemctl start admirald'
for _ in $(seq 1 30); do
  if ssh_admin 'sudo -n systemctl is-active --quiet admirald && sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json >/dev/null'; then break; fi
  sleep 2
done
ssh_admin 'sudo -n systemctl is-active admirald' >"$run_dir/admin-after-start.log"
ssh_admin 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-after-admin-start.json"
admin_stopped=0
python3 - "$run_dir/nodes-after-admin-start.json" <<'PY' | tee "$run_dir/stale-worker-assertion.log"
import json, sys
nodes = json.load(open(sys.argv[1], encoding="utf-8"))
worker = next((n for n in nodes if n.get("id") == "rc6e5r15-rocky-worker"), None)
if not worker:
    raise SystemExit("Worker missing after Admin startup")
got = (worker.get("status"), worker.get("health_status"), worker.get("available_for_provisioning"))
if got != ("offline", "degraded", False):
    raise SystemExit(f"stale Worker was not reconciled before a fresh heartbeat: {got!r}; metrics={worker.get('last_metrics_at')!r}")
print("stale_worker=PASS", "status=" + str(got[0]), "health=" + str(got[1]), "available=" + str(got[2]), "metrics=" + str(worker.get("last_metrics_at")), "heartbeat=" + str(worker.get("last_heartbeat")), sep="\t")
PY
if ssh_worker 'sudo -n systemctl is-active --quiet admiral-fleet'; then
  echo 'FAIL: Fleet became active before the stale-state assertion' | tee -a "$run_dir/stale-worker-assertion.log"
  exit 1
fi

ssh_worker 'sudo -n systemctl start admiral-fleet'
worker_stopped=0
recovered=0
for _ in $(seq 1 60); do
  if ssh_admin 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-recovery-poll.json" 2>/dev/null; then
    if python3 - "$run_dir/nodes-recovery-poll.json" <<'PY'
import json, sys
nodes = json.load(open(sys.argv[1], encoding="utf-8"))
w = next((n for n in nodes if n.get("id") == "rc6e5r15-rocky-worker"), None)
raise SystemExit(0 if w and (w.get("status"), w.get("health_status"), w.get("available_for_provisioning")) == ("active", "healthy", True) else 1)
PY
    then recovered=1; break; fi
  fi
  sleep 2
done
(( recovered == 1 )) || { echo 'FAIL: Worker did not recover after fresh Fleet heartbeat' | tee "$run_dir/recovery-assertion.log"; exit 1; }
ssh_admin 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-after-fleet-recovery.json"
ssh_admin 'sudo -n systemctl is-active admirald' >"$run_dir/admin-after.log"
ssh_worker 'sudo -n systemctl is-active admiral-fleet; free -m; df -h /' >"$run_dir/worker-after.log"
python3 - "$run_dir/nodes-after-fleet-recovery.json" <<'PY' | tee "$run_dir/recovery-assertion.log"
import json, sys
nodes = json.load(open(sys.argv[1], encoding="utf-8"))
w = next((n for n in nodes if n.get("id") == "rc6e5r15-rocky-worker"), None)
if not w or (w.get("status"), w.get("health_status"), w.get("available_for_provisioning")) != ("active", "healthy", True):
    raise SystemExit("Worker did not recover to active/healthy/available")
print("recovered_worker=PASS", "status=" + str(w["status"]), "health=" + str(w["health_status"]), "available=" + str(w["available_for_provisioning"]), "metrics=" + str(w.get("last_metrics_at")), "heartbeat=" + str(w.get("last_heartbeat")), sep="\t")
PY

printf 'issue_294_r17_multinode=PASS end_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
trap - EXIT
(cd "$run_dir" && sha256sum *.json *.log > SHA256SUMS)
