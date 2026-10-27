#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 4 ]] || { echo 'usage: issue-271-postcheck.sh RUN_DIR INSTANCE_A INSTANCE_B APP_NAME' >&2; exit 2; }
run_dir=$1 instance_a=$2 instance_b=$3 app_name=$4
key=/var/lib/libvirt/images/admiral-validation/keys/rc6-e5-r15-validator
admin_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r15-rocky-admin/known_hosts
worker_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r15-rocky-worker/known_hosts
admin_ip=10.77.0.130 worker_ip=10.77.0.132
common=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5)
admin() { ssh "${common[@]}" -o "UserKnownHostsFile=$admin_known" "validator@$admin_ip" "cd / && $*"; }
worker() { ssh "${common[@]}" -o "UserKnownHostsFile=$worker_known" "validator@$worker_ip" "cd / && $*"; }

printf 'issue=271 final_resource_postcheck candidate=rc6-e5-r17 utc=%s\n' "$(date -u +%FT%TZ)" | tee "$run_dir/postcheck.log"
worker 'hostname; rpm -q admiral-common admiral-fleet; sudo -n systemctl is-active admiral-fleet; sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/$(id -u admiral-apps) sh -c '\''set -e; podman ps -a; podman pod ps; podman volume ls; podman images'\''; ss -ltn "sport = :18081"; free -h; df -h /' >"$run_dir/podman-inventory-postcheck.log"
for id in "$instance_a" "$instance_b"; do
  admin "sudo -n -u validator env HOME=/home/validator admiralctl instances show '$id'" >"$run_dir/$id-final-state.json"
done
admin "sudo -n -u validator env HOME=/home/validator admiralctl apps list" >"$run_dir/apps-postcheck.log"
python3 - "$run_dir" "$instance_a" "$instance_b" "$app_name" <<'PY' | tee "$run_dir/postcheck-assertions.log"
from pathlib import Path
import json,sys
run=Path(sys.argv[1]); ids=sys.argv[2:4]; app=sys.argv[4]
for instance_id in ids:
    item=json.loads((run/f"{instance_id}-final-state.json").read_text())
    if item.get("id") != instance_id or item.get("technical_status") != "deprovisioned":
        raise SystemExit(f"instance did not finish deprovisioned: {instance_id}")
text=(run/"podman-inventory-postcheck.log").read_text()
for marker in ids:
    if marker in text: raise SystemExit(f"managed Podman resource remains: {marker}")
if "admiral-r17-redirect:" in text: raise SystemExit("temporary redirect image remains")
if ":18081" in text: raise SystemExit("temporary listener remains")
apps=(run/"apps-postcheck.log").read_text()
if app not in apps or "inactive" not in apps.split(app,1)[1].splitlines()[0]:
    raise SystemExit("temporary app definition is not recorded inactive")
print("instances=2 deprovisioned; managed containers/pods/volumes=0; test image absent; listener absent; app=inactive")
PY
printf 'issue_271_resource_cleanup=PASS end_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/postcheck.log"
(cd "$run_dir" && sha256sum postcheck.log podman-inventory-postcheck.log apps-postcheck.log postcheck-assertions.log inst_79a3f8e9e6ae916e-final-state.json inst_0809ec0e491bdb71-final-state.json > POSTCHECK-SHA256SUMS)
