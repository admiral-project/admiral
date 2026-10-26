#!/usr/bin/env bash
set -euo pipefail
customer=rc6-300-fedora-$(date -u +%Y%m%d%H%M%S)
admiralctl instances provision --app e2e-backup-policy --tier free --customer "$customer" --idempotency-key "$customer" --wait --wait-timeout 10m --quiet --output json >/var/tmp/issue300-provision.json
cat /var/tmp/issue300-provision.json
instance_id=$(python3 -c 'import json;print(json.load(open("/var/tmp/issue300-provision.json"))["instance_id"])')
admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 10m --output json >/var/tmp/issue300-first.json
cat /var/tmp/issue300-first.json
admiralctl operations list --output json >/var/tmp/issue300-before.json
python3 - /var/tmp/issue300-before.json "$instance_id" <<'PY2'
import json,sys
a=[x for x in json.load(open(sys.argv[1])) if x.get("instance_id")==sys.argv[2] and x.get("action")=="deprovision_app"]
assert len(a)==1 and a[0].get("status")=="succeeded",a
print("before_deprovision_operations=1 task_id="+str(a[0].get("task_id")))
PY2
set +e
admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 2m --output json >/var/tmp/issue300-repeat.out 2>&1
rc=$?
set -e
cat /var/tmp/issue300-repeat.out
printf "repeat_exit=%s\n" "$rc"
admiralctl operations list --output json >/var/tmp/issue300-after.json
python3 - /var/tmp/issue300-before.json /var/tmp/issue300-after.json "$instance_id" <<'PY2'
import json,sys
sel=lambda p:[x for x in json.load(open(p)) if x.get("instance_id")==sys.argv[3] and x.get("action")=="deprovision_app"]
a,b=sel(sys.argv[1]),sel(sys.argv[2])
assert len(a)==1 and len(b)==1 and a[0].get("id")==b[0].get("id") and a[0].get("task_id")==b[0].get("task_id"),(a,b)
print("after_deprovision_operations=1 task_id="+str(b[0].get("task_id")))
PY2
grep -q 'HTTP 409 - Instance is already deprovisioned' /var/tmp/issue300-repeat.out
printf "issue_300_repeat_deprovision=PASS instance_id=%s\n" "$instance_id"
