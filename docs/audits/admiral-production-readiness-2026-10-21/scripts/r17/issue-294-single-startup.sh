#!/usr/bin/env bash
set -euo pipefail
umask 077

root=$(git rev-parse --show-toplevel)
key=/var/lib/libvirt/images/admiral-validation/keys/rc6-e5-r15-validator
known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r17-rocky-single/known_hosts
host=192.168.122.175
node_id=rc6e5r17-rocky-single
run_dir="$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r17/runtime/issue-294-r17-rocky-single-20261027"
mkdir -m 0700 -p "$run_dir"

ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known" -o ConnectTimeout=5)
guest() { ssh "${ssh_args[@]}" "validator@$host" "cd / && $*"; }

admin_stopped=0
fleet_stopped=0
restore_services() {
  rc=$?
  trap - EXIT
  if (( admin_stopped )); then guest 'sudo -n systemctl start admirald' >>"$run_dir/recovery.log" 2>&1 || true; fi
  if (( fleet_stopped )); then guest 'sudo -n systemctl start admiral-fleet' >>"$run_dir/recovery.log" 2>&1 || true; fi
  exit "$rc"
}
trap restore_services EXIT

printf 'issue=294 candidate=rc6-e5-r17 topology=rocky-single-node start_utc=%s\n' "$(date -u +%FT%TZ)" | tee "$run_dir/run.log"
guest 'hostname; rpm -q admiral-common admiralctl admirald admiral-fleet admiral-flagship admiral-harbor; sudo -n systemctl is-active admirald admiral-fleet; free -m; df -h /' | tee "$run_dir/guest-before.log"
guest 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-before.json"
python3 - "$run_dir/nodes-before.json" "$node_id" <<'PY' | tee -a "$run_dir/run.log"
import json, sys
nodes=json.load(open(sys.argv[1],encoding="utf-8"))
n=next((x for x in nodes if x.get("id")==sys.argv[2]),None)
if not n or (n.get("status"),n.get("health_status"),n.get("available_for_provisioning")) != ("active","healthy",True):
    raise SystemExit("precondition failed: worker is not active/healthy/available")
print("baseline_worker=PASS",n["status"],n["health_status"],n["available_for_provisioning"],n.get("last_metrics_at"),sep="\t")
PY

guest 'sudo -n systemctl stop admiral-fleet && test "$(sudo -n systemctl is-active admiral-fleet || true)" = inactive'
fleet_stopped=1
printf 'fleet_stopped_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
guest 'sudo -n systemctl stop admirald && test "$(sudo -n systemctl is-active admirald || true)" = inactive'
admin_stopped=1
printf 'admirald_stopped_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
sleep 125
printf 'stale_window_seconds=125 end_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"

guest 'sudo -n systemctl start admirald'
for _ in $(seq 1 30); do
  if guest 'sudo -n systemctl is-active --quiet admirald && sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json >/dev/null'; then break; fi
  sleep 2
done
guest 'sudo -n systemctl is-active admirald' >"$run_dir/admirald-after-start.log"
guest 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-after-admin-start.json"
admin_stopped=0
python3 - "$run_dir/nodes-after-admin-start.json" "$node_id" <<'PY' | tee "$run_dir/stale-worker-assertion.log"
import json, sys
nodes=json.load(open(sys.argv[1],encoding="utf-8"))
n=next((x for x in nodes if x.get("id")==sys.argv[2]),None)
if not n: raise SystemExit("single-node worker missing after Admirald startup")
got=(n.get("status"),n.get("health_status"),n.get("available_for_provisioning"))
if got != ("offline","degraded",False):
    raise SystemExit(f"stale worker was not reconciled before Fleet heartbeat: {got!r}; metrics={n.get('last_metrics_at')!r}")
print("stale_worker=PASS", "status="+str(got[0]), "health="+str(got[1]), "available="+str(got[2]), "metrics="+str(n.get("last_metrics_at")), "heartbeat="+str(n.get("last_heartbeat")), sep="\t")
PY
if guest 'sudo -n systemctl is-active --quiet admiral-fleet'; then
  echo 'FAIL: Fleet became active before stale-state assertion' | tee -a "$run_dir/stale-worker-assertion.log"
  exit 1
fi

guest 'sudo -n systemctl start admiral-fleet'
fleet_stopped=0
recovered=0
for _ in $(seq 1 60); do
  if guest 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-recovery-poll.json" 2>/dev/null; then
    if python3 - "$run_dir/nodes-recovery-poll.json" "$node_id" <<'PY'
import json,sys
nodes=json.load(open(sys.argv[1],encoding="utf-8"))
n=next((x for x in nodes if x.get("id")==sys.argv[2]),None)
raise SystemExit(0 if n and (n.get("status"),n.get("health_status"),n.get("available_for_provisioning")) == ("active","healthy",True) else 1)
PY
    then recovered=1; break; fi
  fi
  sleep 2
done
(( recovered == 1 )) || { echo 'FAIL: Worker did not recover after fresh Fleet heartbeat' | tee "$run_dir/recovery-assertion.log"; exit 1; }
guest 'sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/nodes-after-fleet-recovery.json"
guest 'sudo -n systemctl is-active admirald admiral-fleet; free -m; df -h /' >"$run_dir/guest-after.log"
python3 - "$run_dir/nodes-after-fleet-recovery.json" "$node_id" <<'PY' | tee "$run_dir/recovery-assertion.log"
import json,sys
nodes=json.load(open(sys.argv[1],encoding="utf-8"))
n=next((x for x in nodes if x.get("id")==sys.argv[2]),None)
if not n or (n.get("status"),n.get("health_status"),n.get("available_for_provisioning")) != ("active","healthy",True):
    raise SystemExit("worker did not recover to active/healthy/available")
print("recovered_worker=PASS", "status="+str(n["status"]), "health="+str(n["health_status"]), "available="+str(n["available_for_provisioning"]), "metrics="+str(n.get("last_metrics_at")), "heartbeat="+str(n.get("last_heartbeat")), sep="\t")
PY

printf 'issue_294_r17_rocky_single=PASS end_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
trap - EXIT
(cd "$run_dir" && sha256sum *.json *.log > SHA256SUMS)
