#!/usr/bin/env bash
set -euo pipefail
instance_id=inst_172ee815ef007f2a
admiralctl operations list --output json > /var/tmp/issue300-before.json
python3 - /var/tmp/issue300-before.json "$instance_id" <<'PY2'
import json,sys
xs=json.load(open(sys.argv[1])); a=[x for x in xs if x.get("instance_id")==sys.argv[2] and x.get("action")=="deprovision_app"]
assert len(a)==1 and a[0].get("status")=="succeeded",a
print("before_deprovision_operations=1 task_id="+str(a[0].get("task_id")))
PY2
set +e
admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 2m --output json > /var/tmp/issue300-repeat.out 2>&1
rc=$?
set -e
cat /var/tmp/issue300-repeat.out
printf "repeat_exit=%s\n" "$rc"
admiralctl operations list --output json > /var/tmp/issue300-after.json
python3 - /var/tmp/issue300-before.json /var/tmp/issue300-after.json "$instance_id" <<'PY2'
import json,sys
get=lambda p:json.load(open(p))
sel=lambda p:[x for x in get(p) if x.get("instance_id")==sys.argv[3] and x.get("action")=="deprovision_app"]
a,b=sel(sys.argv[1]),sel(sys.argv[2])
assert len(a)==1 and len(b)==1 and a[0].get("id")==b[0].get("id") and a[0].get("task_id")==b[0].get("task_id"),(a,b)
print("after_deprovision_operations=1 task_id="+str(b[0].get("task_id")))
PY2
printf "issue_300_repeat_deprovision=PASS\n"
