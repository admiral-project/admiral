#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

root=$(git rev-parse --show-toplevel)
key=/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519
admin_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-admin/known_hosts
source_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-worker/known_hosts
target_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-r255-worker2/known_hosts
admin_ip=10.77.0.10
source_ip=10.77.0.11
target_ip=10.77.0.13
source_node=rc6e5r18-ipv6-worker
target_node=rc6e5r18-r255-worker2
candidate_root=ba7c4396743e84baae0b4de9f89f91ff5503a33b
run_tag="r20-issue255-rocky-mn-$(date -u +%Y%m%dt%H%M%Sz | tr '[:upper:]' '[:lower:]')-$$"
app_name=$run_tag
customer=$run_tag-customer
run_dir="$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r20/runtime/issue-255-$run_tag"
remote_sampler=/tmp/$run_tag-sampler.py
remote_timeline=/var/tmp/$run_tag-timeline.jsonl
tmp=$(mktemp -d)
mkdir -m 0700 -p "$run_dir"
ssh_common=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5)
admin_args=("${ssh_common[@]}" -o "UserKnownHostsFile=$admin_known")
source_args=("${ssh_common[@]}" -o "UserKnownHostsFile=$source_known")
target_args=("${ssh_common[@]}" -o "UserKnownHostsFile=$target_known")

admin() { ssh "${admin_args[@]}" "validator@$admin_ip" "cd / && $*"; }
admin_detached() { ssh "${admin_args[@]}" "validator@$admin_ip" "$*"; }
source_worker() { ssh "${source_args[@]}" "validator@$source_ip" "cd / && $*"; }
target_worker() { ssh "${target_args[@]}" "validator@$target_ip" "cd / && $*"; }
worker_podman() {
  local ip=$1 known=$2 command=$3
  ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=5 -o "UserKnownHostsFile=$known" "validator@$ip" \
    "cd /; uid=\$(id -u admiral-apps); sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$uid podman $command"
}

instance_id=
logical_id=
sampler_pid=
resource_pid=
cleanup_complete=false
app_applied=false
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n $resource_pid ]]; then
    kill "$resource_pid" >/dev/null 2>&1 || true
    wait "$resource_pid" >/dev/null 2>&1 || true
  fi
  if [[ $cleanup_complete != true && -n $sampler_pid ]]; then
    admin "if [ -r '/proc/$sampler_pid/cmdline' ] && tr '\000' ' ' <'/proc/$sampler_pid/cmdline' | grep -F -- '$remote_sampler' >/dev/null; then kill '$sampler_pid'; fi" >/dev/null 2>&1 || true
  fi
  if [[ $cleanup_complete != true && -n $instance_id ]]; then
    printf 'cleanup=preserved_fixture_and_source_instance_after_incomplete_run\n' >"$run_dir/cleanup-note.txt"
  elif [[ $cleanup_complete != true && $app_applied == true ]]; then
    admin "sudo -n -u validator env HOME=/home/validator admiralctl apps deactivate --name '$app_name' --force" >"$run_dir/cleanup-app.log" 2>&1 || true
    admin "rm -f -- '/tmp/$run_tag-app.yaml'" >/dev/null 2>&1 || true
  fi
  if [[ $cleanup_complete == true ]]; then
    admin "rm -f -- '/tmp/$run_tag-app.yaml' '$remote_sampler' '$remote_timeline'" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$tmp"
  exit "$rc"
}
trap cleanup EXIT

printf 'issue=255\ncandidate=RC6-E5-R20\nroot_candidate=%s\nos=Rocky Linux 10.2 x86_64\ntopology=Multi-Node\nsource_node=%s\ntarget_node=%s\nrun_tag=%s\nstart_utc=%s\n' \
  "$candidate_root" "$source_node" "$target_node" "$run_tag" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$run_dir/metadata.txt"
host_mem_available_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
host_disk_available_bytes=$(df -B1 --output=avail /var/lib/libvirt/images | tail -n 1 | tr -d ' ')
(( host_mem_available_kib >= 2500000 && host_disk_available_bytes >= 30000000000 )) || {
  echo 'host resource guard refused the migration run' >&2
  exit 1
}
printf 'host_mem_available_kib=%s\nhost_disk_available_bytes=%s\nfixture_tier_memory=128M\n' "$host_mem_available_kib" "$host_disk_available_bytes" >>"$run_dir/metadata.txt"
git -C "$root" rev-parse HEAD >"$run_dir/evidence-collection-root-head.txt"
admin "sudo -n -u validator env HOME=/home/validator admiralctl operations list --output json" >"$tmp/preexisting-operations.json"
python3 - "$tmp/preexisting-operations.json" "$run_dir/preexisting-operations.json" <<'PY'
import json,sys
ops=json.load(open(sys.argv[1],encoding="utf-8")); keep=[]
for op in ops:
    meta=op.get("metadata") or {}
    if op.get("instance_id")=="inst_9a7a819dcf3c4689" or op.get("action")=="test_backup_storage":
        keep.append({k:op.get(k) for k in ("id","instance_id","node_id","action","status","updated_at","error_message")} | {"migration_step":meta.get("migration_step")})
json.dump(keep,open(sys.argv[2],"w",encoding="utf-8"),indent=2,sort_keys=True)
PY
sha256sum \
  "$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r20/CANDIDATE.md" \
  "$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r20/source-pins.txt" \
  "$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r20/el10/RPM-MANIFEST.tsv" \
  >"$run_dir/candidate-inputs.sha256"

admin "rpm -q admiral-common admirald admiralctl; sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json | python3 -c 'import json,sys; ns=json.load(sys.stdin); fields=(\"id\",\"status\",\"health_status\",\"available_for_provisioning\",\"wireguard_ip\"); print(json.dumps([{k:n.get(k) for k in fields} for n in ns],sort_keys=True))'" \
  >"$run_dir/admin-baseline.txt"
source_worker 'rpm -q admiral-common admiral-fleet; free -m; df -h /' >"$run_dir/source-baseline.txt"
target_worker 'rpm -q admiral-common admiral-fleet; free -m; df -h /; systemctl is-active admiral-fleet' >"$run_dir/target-baseline.txt"
admin_mem_available=$(admin "awk '/^MemAvailable:/ {print \$2}' /proc/meminfo")
source_mem_available=$(source_worker "awk '/^MemAvailable:/ {print \$2}' /proc/meminfo")
target_mem_available=$(target_worker "awk '/^MemAvailable:/ {print \$2}' /proc/meminfo")
(( admin_mem_available >= 200000 && source_mem_available >= 350000 && target_mem_available >= 350000 )) || {
  echo 'guest memory guard refused the migration run' >&2
  exit 1
}
printf 'admin_mem_available_kib=%s\nsource_mem_available_kib=%s\ntarget_mem_available_kib=%s\n' \
  "$admin_mem_available" "$source_mem_available" "$target_mem_available" >>"$run_dir/metadata.txt"
grep -q 'admirald-0.0.1rc6-20.el10.x86_64' "$run_dir/admin-baseline.txt"
grep -q 'admiral-fleet-0.0.1rc6-20.el10.x86_64' "$run_dir/source-baseline.txt"
grep -q 'admiral-fleet-0.0.1rc6-20.el10.x86_64' "$run_dir/target-baseline.txt"
python3 - "$run_dir/admin-baseline.txt" "$source_node" "$target_node" <<'PY'
import json,sys
text=open(sys.argv[1],encoding="utf-8").read()
nodes=json.loads(text[text.index("["):])
for node_id in sys.argv[2:]:
    node=next((n for n in nodes if n.get("id")==node_id),None)
    if not node or (node.get("status"),node.get("health_status"),node.get("available_for_provisioning")) != ("active","healthy",True):
        raise SystemExit(f"worker precondition failed: {node_id}")
PY

source_worker "sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) podman image ls --format '{{.Repository}}:{{.Tag}}' | sort" >"$run_dir/source-images.txt"
target_worker "sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) podman image ls --format '{{.Repository}}:{{.Tag}}' | sort" >"$run_dir/target-images.txt"
grep -q '^docker.io/library/postgres:16$' "$run_dir/source-images.txt"
grep -q '^docker.io/library/postgres:16$' "$run_dir/target-images.txt"
worker_podman "$source_ip" "$source_known" "ps -a --format '{{.Names}}'" >"$run_dir/source-containers-before.txt"
worker_podman "$target_ip" "$target_known" "ps -a --format '{{.Names}}'" >"$run_dir/target-containers-before.txt"

python3 - "$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r19/issue-255-r19-issue255-rocky-mn-20261027t225640z/app.yaml" "$tmp/app.yaml" "$app_name" <<'PY'
from pathlib import Path
import sys
source=Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
source[0]=f"name: {sys.argv[3]}"
source[1]=f"display_name: R20 issue 255 {sys.argv[3]}"
source[2]="description: Disposable R20 migration and S3 backup validation."
text="\n".join(source)+"\n"
text=text.replace("    memory: 512M\n", "    memory: 128M\n", 1)
if "    memory: 128M\n" not in text or "backup_volumes: false" not in text or "backup_database: true" not in text:
    raise SystemExit("R20 migration fixture must fit the existing node and use database-only S3 backup")
Path(sys.argv[2]).write_text(text,encoding="utf-8")
PY
cp "$tmp/app.yaml" "$run_dir/app.yaml"
scp "${admin_args[@]}" "$tmp/app.yaml" "validator@$admin_ip:/tmp/$run_tag-app.yaml"
admin "sudo -n -u validator env HOME=/home/validator admiralctl apps apply --file '/tmp/$run_tag-app.yaml'" >"$run_dir/apply.log" 2>&1
app_applied=true
admin "sudo -n -u validator env HOME=/home/validator admiralctl apps activate --name '$app_name'" >"$run_dir/activate.log" 2>&1
admin "sudo -n -u validator env HOME=/home/validator admiralctl instances provision --app '$app_name' --tier small --customer '$customer' --node '$source_node' --idempotency-key '$run_tag-provision' --wait --wait-timeout 10m --quiet --output json" \
  >"$run_dir/provision.json" 2>"$run_dir/provision.stderr"
instance_id=$(python3 - "$run_dir/provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
if x.get("status")!="succeeded" or not x.get("instance_id"):
    raise SystemExit(f"provision failed: status={x.get('status')!r}")
print(x["instance_id"])
PY
)
[[ $instance_id =~ ^inst_[0-9a-f]{16}$ ]]
printf 'instance_id=%s\n' "$instance_id" >>"$run_dir/metadata.txt"

for attempt in $(seq 1 60); do
  admin "sudo -n -u validator env HOME=/home/validator admiralctl instances list --output json | python3 -c 'import json,sys; xs=json.load(sys.stdin); fields=(\"id\",\"app_definition_name\",\"node_id\",\"logical_instance_id\",\"technical_status\",\"health_status\",\"effective_availability\",\"last_health_checked_at\"); print(json.dumps([{k:x.get(k) for k in fields} for x in xs if x.get(\"id\")==\"$instance_id\"],sort_keys=True))'" \
    >"$run_dir/instance-before-migration.json"
  if python3 - "$run_dir/instance-before-migration.json" "$app_name" "$source_node" <<'PY'
import json,sys
xs=json.load(open(sys.argv[1],encoding="utf-8"))
if len(xs)!=1: raise SystemExit(1)
x=xs[0]
if x.get("app_definition_name")!=sys.argv[2] or x.get("node_id")!=sys.argv[3]: raise SystemExit(1)
if (x.get("technical_status"),x.get("health_status"),x.get("effective_availability")) != ("running","healthy","available"): raise SystemExit(1)
if not x.get("logical_instance_id"): raise SystemExit(1)
print(x["logical_instance_id"])
PY
  then
    break
  fi
  [[ $attempt -lt 60 ]] || { echo 'instance did not become healthy/available before migration' >&2; exit 1; }
  sleep 2
done
logical_id=$(python3 - "$run_dir/instance-before-migration.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8"))[0]["logical_instance_id"])
PY
)
printf 'logical_instance_id=%s\n' "$logical_id" >>"$run_dir/metadata.txt"

worker_podman "$source_ip" "$source_known" "ps -a --format '{{.Names}}'" >"$tmp/source-containers.txt"
db_container=$(rg "admiral-${instance_id}-database" "$tmp/source-containers.txt" | head -n 1 || true)
[[ -n $db_container ]]
insert_marker_sql='psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE TABLE IF NOT EXISTS audit_marker (id integer PRIMARY KEY)" -c "INSERT INTO audit_marker VALUES (2552071) ON CONFLICT DO NOTHING"'
verify_marker_sql='psql -v ON_ERROR_STOP=1 -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id FROM audit_marker WHERE id = 2552071"'
worker_podman "$source_ip" "$source_known" "exec '$db_container' sh -ec '$insert_marker_sql'" \
  >"$run_dir/source-marker-insert.log" 2>&1
worker_podman "$source_ip" "$source_known" "exec '$db_container' sh -ec '$verify_marker_sql'" \
  >"$run_dir/source-marker-verify.txt" 2>&1
grep -qx '2552071' "$run_dir/source-marker-verify.txt"

cat >"$tmp/sampler.py" <<'PY'
import datetime,json,subprocess,sys,time
instance_id=sys.argv[1]
path=sys.argv[2]
period=0.75
started=time.monotonic()
next_sample=started
parent_id=None
terminal_seen=None
deadline=started+900
with open(path,"w",encoding="utf-8",buffering=1) as out:
    while time.monotonic()<deadline:
        now=time.monotonic()
        row={"sampled_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"elapsed_seconds":round(now-started,3),"period_seconds":period}
        try:
            result=subprocess.run(["admiralctl","operations","list","--output","json"],capture_output=True,text=True,timeout=10,check=False)
            if result.returncode:
                row["sample_error_code"]=result.returncode
                row["operations"]=[]
            else:
                ops=json.loads(result.stdout)
                selected=[]
                for op in ops:
                    if op.get("instance_id")!=instance_id: continue
                    meta=op.get("metadata") or {}
                    selected.append({k:op.get(k) for k in ("id","instance_id","node_id","task_id","action","status","error_message","created_at","updated_at")})
                    selected[-1]["metadata"]={k:meta.get(k) for k in ("source_node_id","target_node_id","logical_instance_id","migration_step") if meta.get(k) is not None}
                    if op.get("action")=="migrate" and meta.get("target_node_id"):
                        parent_id=op.get("id")
                row["operations"]=selected
                parent=next((o for o in selected if o.get("id")==parent_id),None)
                if parent and parent.get("status") in ("succeeded","failed","cancelled"):
                    terminal_seen=terminal_seen or time.monotonic()
                if terminal_seen and time.monotonic()-terminal_seen>=2.0:
                    row["sampler_stop_reason"]="migration_terminal_plus_2s"
                    out.write(json.dumps(row,sort_keys=True)+"\n")
                    break
        except Exception as exc:
            row["sample_exception_type"]=type(exc).__name__
            row["operations"]=[]
        out.write(json.dumps(row,sort_keys=True)+"\n")
        next_sample+=period
        delay=next_sample-time.monotonic()
        if delay>0: time.sleep(delay)
PY
scp "${admin_args[@]}" "$tmp/sampler.py" "validator@$admin_ip:$remote_sampler"
admin_detached "nohup python3 '$remote_sampler' '$instance_id' '$remote_timeline' >/dev/null 2>&1 </dev/null & echo \$!" >"$run_dir/sampler-pid.txt"
sampler_pid=$(tr -d '[:space:]' <"$run_dir/sampler-pid.txt")
[[ $sampler_pid =~ ^[0-9]+$ ]]
cat >"$tmp/resource-monitor.py" <<'PY'
import concurrent.futures,datetime,json,pathlib,shutil,subprocess,sys,time
path,key=sys.argv[1:3]
hosts={"admin":(sys.argv[3],sys.argv[4]),"source":(sys.argv[5],sys.argv[6]),"target":(sys.argv[7],sys.argv[8])}
def guest_sample(endpoint):
    ip,known=endpoint
    cmd=["ssh","-i",key,"-o","IdentitiesOnly=yes","-o","BatchMode=yes","-o","StrictHostKeyChecking=yes","-o","ConnectTimeout=5",f"-oUserKnownHostsFile={known}",f"validator@{ip}","awk '/^MemAvailable:/ {print $2}' /proc/meminfo; df -B1 --output=avail / | tail -n 1"]
    try:
        p=subprocess.run(cmd,capture_output=True,text=True,timeout=12,check=True)
        vals=[int(x.strip()) for x in p.stdout.splitlines() if x.strip()]
        if len(vals)!=2: raise ValueError("unexpected guest resource output")
        return {"mem_available_kib":vals[0],"root_disk_available_bytes":vals[1]}
    except Exception as exc:
        return {"error":type(exc).__name__}
with open(path,"a",encoding="utf-8",buffering=1) as out:
    while True:
        mem=int(next(x.split()[1] for x in pathlib.Path("/proc/meminfo").read_text().splitlines() if x.startswith("MemAvailable:")))
        row={"sampled_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"host_mem_available_kib":mem,"host_disk_available_bytes":shutil.disk_usage("/var/lib/libvirt/images").free,"guests":{}}
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            futures={pool.submit(guest_sample,endpoint):label for label,endpoint in hosts.items()}
            for future,label in futures.items(): row["guests"][label]=future.result()
        warnings=[]
        if row["host_mem_available_kib"]<1572864: warnings.append("host_ram_below_1536MiB")
        if row["host_disk_available_bytes"]<30000000000: warnings.append("host_disk_below_30GB")
        for label,guest in row["guests"].items():
            if guest.get("mem_available_kib",10**12)<131072: warnings.append(label+"_ram_below_128MiB")
            if guest.get("root_disk_available_bytes",10**15)<2000000000: warnings.append(label+"_disk_below_2GB")
        row["warnings"]=warnings
        out.write(json.dumps(row,sort_keys=True)+"\n")
        time.sleep(15)
PY
python3 "$tmp/resource-monitor.py" "$run_dir/resource-monitor.jsonl" "$key" "$admin_ip" "$admin_known" "$source_ip" "$source_known" "$target_ip" "$target_known" >"$run_dir/resource-monitor.stderr" 2>&1 &
resource_pid=$!
sleep 1
printf 'y\n' | admin "sudo -n -u validator env HOME=/home/validator admiralctl instances migrate '$instance_id' --target-node '$target_node' --output json" \
  >"$run_dir/migration-start.raw.log" 2>"$run_dir/migration-start.stderr"
python3 - "$run_dir/migration-start.raw.log" "$run_dir/migration-start.json" <<'PY'
from pathlib import Path
import json,sys
raw=Path(sys.argv[1]).read_text(encoding="utf-8")
start=raw.find("{")
if start<0: raise SystemExit("migration CLI did not return its JSON response")
response=json.loads(raw[start:])
Path(sys.argv[2]).write_text(json.dumps(response,sort_keys=True)+"\n",encoding="utf-8")
PY
python3 - "$run_dir/migration-start.json" "$instance_id" "$logical_id" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
if x.get("instance_id")!=sys.argv[2] or x.get("logical_instance_id")!=sys.argv[3] or x.get("status")!="running" or not x.get("operation_id"):
    raise SystemExit("migration start response did not match the provisioned logical instance")
print(x["operation_id"])
PY
migration_id=$(python3 - "$run_dir/migration-start.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8"))["operation_id"])
PY
)
printf 'migration_operation_id=%s\n' "$migration_id" >>"$run_dir/metadata.txt"

set +e
admin "while kill -0 '$sampler_pid' 2>/dev/null; do sleep 1; done" >/dev/null 2>&1
sampler_wait_rc=$?
set -e
[[ $sampler_wait_rc -eq 0 ]]
kill "$resource_pid" >/dev/null 2>&1 || true
wait "$resource_pid" >/dev/null 2>&1 || true
resource_pid=
scp "${admin_args[@]}" "validator@$admin_ip:$remote_timeline" "$run_dir/operation-timeline.jsonl"
admin "sudo -n -u validator env HOME=/home/validator admiralctl operations show '$migration_id'" \
  | python3 -c 'import json,sys; x=json.load(sys.stdin); m=x.get("metadata") or {}; fields=("id","instance_id","node_id","action","status","created_at","updated_at"); y={k:x.get(k) for k in fields}; y["metadata"]={k:m.get(k) for k in ("source_node_id","target_node_id","logical_instance_id","migration_step","backup_record_ids") if m.get(k) is not None}; print(json.dumps(y,sort_keys=True))' \
  >"$run_dir/migration-final.json"
backup_ids=$(python3 - "$run_dir/migration-final.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8")); ids=(x.get("metadata") or {}).get("backup_record_ids") or []
if not ids: raise SystemExit("migration operation contains no fresh backup record IDs")
print(" ".join(ids))
PY
)
for backup_id in $backup_ids; do
  admin "sudo -n -u validator env HOME=/home/validator admiralctl backups show '$backup_id'" >"$run_dir/backup-$backup_id.json"
done
python3 - "$run_dir" "$instance_id" <<'PY'
import glob,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); instance_id=sys.argv[2]
files=glob.glob(str(root/"backup-bk_*.json"))
if not files: raise SystemExit("no fresh backup records were captured")
records=[]
for filename in files:
    x=json.load(open(filename,encoding="utf-8"))
    if x.get("instance_id")!=instance_id or x.get("status")!="succeeded": raise SystemExit("fresh migration backup did not succeed for the disposable instance")
    if x.get("storage_backend")!="s3" or not x.get("storage_key") or not x.get("checksum_sha256"): raise SystemExit("fresh migration backup lacks S3 key or checksum evidence")
    if x.get("backup_type")!="database": raise SystemExit("unexpected non-database backup in database-only migration fixture")
    records.append({k:x.get(k) for k in ("id","instance_id","backup_type","status","storage_backend","storage_key","checksum_sha256","size_bytes","created_at","completed_at")})
json.dump(records,open(root/"backup-records-validated.json","w",encoding="utf-8"),indent=2,sort_keys=True)
PY
python3 - "$run_dir/resource-monitor.jsonl" "$run_dir/resource-analysis.json" <<'PY'
import json,pathlib,sys
samples=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines() if x.strip()]
if not samples: raise SystemExit("resource monitor produced no samples")
if any("error" in guest for row in samples for guest in row.get("guests",{}).values()): raise SystemExit("resource monitor could not read one or more guest snapshots")
warnings=[w for row in samples for w in row.get("warnings",[])]
report={"samples":len(samples),"first_sample":samples[0]["sampled_at_utc"],"last_sample":samples[-1]["sampled_at_utc"],"minimum_host_mem_available_kib":min(r["host_mem_available_kib"] for r in samples),"minimum_host_disk_available_bytes":min(r["host_disk_available_bytes"] for r in samples),"minimum_guest_mem_available_kib":{name:min(r["guests"][name]["mem_available_kib"] for r in samples) for name in ("admin","source","target")},"minimum_guest_root_disk_available_bytes":{name:min(r["guests"][name]["root_disk_available_bytes"] for r in samples) for name in ("admin","source","target")},"warnings":sorted(set(warnings)),"result":"PASS" if not warnings else "WARN"}
json.dump(report,open(sys.argv[2],"w",encoding="utf-8"),indent=2,sort_keys=True)
if warnings: raise SystemExit("resource telemetry crossed a caution threshold; inspect resource-analysis.json")
PY
admin "sudo -n -u validator env HOME=/home/validator admiralctl instances list --output json | python3 -c 'import json,sys; xs=json.load(sys.stdin); fields=(\"id\",\"app_definition_name\",\"node_id\",\"logical_instance_id\",\"technical_status\",\"health_status\",\"effective_availability\",\"last_health_checked_at\"); print(json.dumps([{k:x.get(k) for k in fields} for x in xs if x.get(\"id\")==\"$instance_id\"],sort_keys=True))'" \
  >"$run_dir/instance-after-migration.json"
worker_podman "$source_ip" "$source_known" "ps -a --format '{{.Names}}'" >"$run_dir/source-containers-after.txt"
worker_podman "$target_ip" "$target_known" "ps -a --format '{{.Names}}'" >"$run_dir/target-containers-after.txt"
worker_podman "$source_ip" "$source_known" "ps --format '{{.Names}}'" >"$run_dir/source-running-after.txt"
if rg -q "admiral-${instance_id}" "$run_dir/source-running-after.txt"; then
  echo 'source workload remained running after successful target cutover' >&2
  exit 1
fi
target_db=$(rg "admiral-${instance_id}-database" "$run_dir/target-containers-after.txt" | head -n 1 || true)
[[ -n $target_db ]]
worker_podman "$target_ip" "$target_known" "exec '$target_db' sh -ec '$verify_marker_sql'" \
  >"$run_dir/target-marker-verify.txt" 2>&1
grep -qx '2552071' "$run_dir/target-marker-verify.txt"

python3 - "$run_dir" "$instance_id" "$migration_id" "$logical_id" "$source_node" "$target_node" <<'PY'
import json,pathlib,sys,datetime
root=pathlib.Path(sys.argv[1]); instance_id,migration_id,logical_id,source,target=sys.argv[2:]
samples=[json.loads(line) for line in (root/"operation-timeline.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
if len(samples)<4: raise SystemExit("operation timeline has too few samples")
if any("sample_error_code" in s or "sample_exception_type" in s for s in samples): raise SystemExit("operation sampler recorded errors")
times=[datetime.datetime.fromisoformat(s["sampled_at_utc"]) for s in samples]
if max((b-a).total_seconds() for a,b in zip(times,times[1:]))>1.2: raise SystemExit("timeline sampling gap exceeded 1.2 seconds")
ops_by_id={}
for sample in samples:
    for op in sample.get("operations",[]):
        if op.get("id"): ops_by_id.setdefault(op["id"],[]).append(op)
if migration_id not in ops_by_id: raise SystemExit("migration operation was absent from the timeline")
for op_id,events in ops_by_id.items():
    statuses=[e.get("status") for e in events]
    seen_running=False; seen_terminal=False
    for status in statuses:
        if status=="running": seen_running=True
        if status in {"succeeded","failed","cancelled"}: seen_terminal=True
        if status=="queued" and (seen_running or seen_terminal): raise SystemExit(f"operation {op_id} regressed to queued")
parent=ops_by_id[migration_id][-1]
meta=parent.get("metadata") or {}
if parent.get("status")!="succeeded": raise SystemExit(f"migration finished {parent.get('status')!r}")
if meta.get("source_node_id")!=source or meta.get("target_node_id")!=target: raise SystemExit("migration source/target metadata mismatch")
if meta.get("logical_instance_id")!=logical_id: raise SystemExit("migration operation logical ID changed")
if meta.get("migration_step")!="completed": raise SystemExit(f"migration step did not complete: {meta.get('migration_step')!r}")
children=[events[-1] for op_id,events in ops_by_id.items() if op_id!=migration_id]
backup=[op for op in children if op.get("action")=="backup_database"]
restore=[op for op in children if op.get("action")=="restore_backup"]
resume=[op for op in children if op.get("action")=="resume_app"]
if not backup or not any(op.get("status")=="succeeded" for op in backup): raise SystemExit("fresh database backup operation did not succeed")
if not restore or not any(op.get("status")=="succeeded" for op in restore): raise SystemExit("S3 restore child operation did not succeed")
if not resume or not any(op.get("status")=="succeeded" for op in resume): raise SystemExit("target resume_app child operation did not succeed")
instances=json.load(open(root/"instance-after-migration.json",encoding="utf-8"))
if len(instances)!=1: raise SystemExit("migrated instance missing from control-plane inventory")
instance=instances[0]
if (instance.get("node_id"),instance.get("logical_instance_id"),instance.get("technical_status"),instance.get("health_status"),instance.get("effective_availability")) != (target,logical_id,"running","healthy","available"):
    raise SystemExit("post-cutover instance identity, node, or health mismatch")
if (root/"source-marker-verify.txt").read_text().strip()!="2552071" or (root/"target-marker-verify.txt").read_text().strip()!="2552071":
    raise SystemExit("database marker was not preserved across migration restore")
print(json.dumps({"samples":len(samples),"sample_period_seconds":0.75,"max_sample_gap_seconds":max((b-a).total_seconds() for a,b in zip(times,times[1:])),"migration_operation":migration_id,"migration_status":parent.get("status"),"backup_operations":[{"id":o.get("id"),"status":o.get("status")} for o in backup],"restore_operations":[{"id":o.get("id"),"status":o.get("status")} for o in restore],"resume_operations":[{"id":o.get("id"),"status":o.get("status")} for o in resume],"logical_instance_id":logical_id,"source_node":source,"target_node":target,"database_marker":"2552071","result":"PASS"},indent=2,sort_keys=True))
PY

admin "sudo -n -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 8m --output json" \
  >"$run_dir/deprovision.json"
python3 - "$run_dir/deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
if x.get("status")!="succeeded": raise SystemExit(f"deprovision status is {x.get('status')!r}")
PY
worker_podman "$source_ip" "$source_known" "ps -a --format '{{.Names}}'" >"$run_dir/source-containers-final.txt"
worker_podman "$target_ip" "$target_known" "ps -a --format '{{.Names}}'" >"$run_dir/target-containers-final.txt"
if rg -q "admiral-${instance_id}" "$run_dir/source-containers-final.txt" "$run_dir/target-containers-final.txt"; then
  echo 'migration workload remained on a worker after deprovision' >&2
  exit 1
fi
admin "sudo -n -u validator env HOME=/home/validator admiralctl apps deactivate --name '$app_name' --force" \
  >"$run_dir/deactivate.log" 2>&1
app_applied=false
admin "rm -f -- '/tmp/$run_tag-app.yaml'" >/dev/null 2>&1
admin "rm -f -- '$remote_sampler' '$remote_timeline'" >/dev/null 2>&1
sampler_pid=
instance_id=
printf 'end_utc=%s\nresult=PASS\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$run_dir/metadata.txt"
(
  cd "$run_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
)
cleanup_complete=true
echo "evidence_dir=$run_dir"
