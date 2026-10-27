#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(git rev-parse --show-toplevel)
key=/var/lib/libvirt/images/admiral-validation/keys/rc6-e5-r15-validator
admin_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r15-rocky-admin/known_hosts
worker_known=/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r15-rocky-worker/known_hosts
admin_ip=10.77.0.130
worker_ip=10.77.0.132
run_tag=rocky-mn-$(date -u +%Y%m%dt%H%M%Sz | tr '[:upper:]' '[:lower:]')-$$
run_dir="$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r17/runtime/issue-271-r17-$run_tag"
work_dir=/var/tmp/rc6-271-$run_tag
app_name=r17-issue-271-$run_tag
customer=$app_name-customer
remote_image=docker.io/library/admiral-r17-redirect:$run_tag
mkdir -m 0700 -p "$run_dir"
ssh_common=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5)
admin_args=("${ssh_common[@]}" -o "UserKnownHostsFile=$admin_known")
worker_args=("${ssh_common[@]}" -o "UserKnownHostsFile=$worker_known")
admin() { ssh "${admin_args[@]}" "validator@$admin_ip" "cd / && $*"; }
worker_cmd() { ssh "${worker_args[@]}" "validator@$worker_ip" "cd / && $*"; }
instance_id=''
listener_pid=''
tmp=$(mktemp -d)
cleanup() {
  rc=$?
  trap - EXIT
  if [[ -n $instance_id ]]; then
    admin "sudo -n -u validator env HOME=/home/validator admiralctl instances deprovision '$instance_id' --force --wait --wait-timeout 5m --output json" >"$run_dir/trap-deprovision.json" 2>&1 || true
  fi
  if [[ -n $listener_pid ]]; then worker_cmd "kill '$listener_pid'" >/dev/null 2>&1 || true; fi
  worker_cmd "cd / && sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) podman rmi '$remote_image'" >>"$run_dir/cleanup.log" 2>&1 || true
  admin "sudo -n -u validator env HOME=/home/validator admiralctl apps deactivate --name '$app_name' --force" >>"$run_dir/cleanup.log" 2>&1 || true
  worker_cmd "python3 - '$work_dir' <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
for child in p.iterdir() if p.is_dir() else ():
    if child.is_file() or child.is_symlink(): child.unlink()
if p.is_dir(): p.rmdir()
PY" >>"$run_dir/cleanup.log" 2>&1 || true
  worker_cmd "python3 - '/tmp/rc6-271-$run_tag-rootfs.tar' '/tmp/rc6-271-$run_tag-listener.py' <<'PY'
from pathlib import Path
import sys
for name in sys.argv[1:]:
    p=Path(name)
    if p.is_file() or p.is_symlink(): p.unlink()
PY" >>"$run_dir/cleanup.log" 2>&1 || true
  admin "python3 - '/tmp/$app_name.yaml' <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
if p.is_file() or p.is_symlink(): p.unlink()
PY" >>"$run_dir/cleanup.log" 2>&1 || true
  python3 - "$tmp" <<'PY'
from pathlib import Path
import shutil,sys
shutil.rmtree(Path(sys.argv[1]))
PY
  exit "$rc"
}
trap cleanup EXIT

printf 'issue=271 candidate=rc6-e5-r17 topology=rocky-multinode run_tag=%s start_utc=%s\n' "$run_tag" "$(date -u +%FT%TZ)" | tee "$run_dir/run.log"
printf 'root_head=%s\n' "$(git -C "$root" rev-parse HEAD)" | tee -a "$run_dir/run.log"
sha256sum "$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r17/el10/RPM-MANIFEST.tsv" "$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r17/source-pins.txt" >"$run_dir/candidate-inputs.sha256"
admin 'hostname; rpm -q admiral-common admiralctl admirald; sudo -n systemctl is-active admirald; sudo -n -u validator env HOME=/home/validator admiralctl nodes list --output json' >"$run_dir/admin-baseline.txt"
worker_cmd 'hostname; rpm -q admiral-common admiral-fleet; sudo -n systemctl is-active admiral-fleet; free -m; df -h /; sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/$(id -u admiral-apps) podman ps -a --format "{{.Names}}|{{.Status}}"' >"$run_dir/worker-baseline.log"
grep -q 'admiral-common-0.0.1rc6-17.el10.noarch' "$run_dir/admin-baseline.txt"
grep -q 'admirald-0.0.1rc6-17.el10.x86_64' "$run_dir/admin-baseline.txt"
grep -q 'admiralctl-0.0.1rc6-17.el10.x86_64' "$run_dir/admin-baseline.txt"
grep -q 'admiral-fleet-0.0.1rc6-17.el10.x86_64' "$run_dir/worker-baseline.log"
python3 - "$run_dir/admin-baseline.txt" <<'PY'
import json,sys
t=open(sys.argv[1],encoding="utf-8").read()
nodes=json.loads(t[t.index("["):])
w=next((n for n in nodes if n.get("id")=="rc6e5r15-rocky-worker"),None)
if not w or (w.get("status"),w.get("health_status"),w.get("available_for_provisioning")) != ("active","healthy",True): raise SystemExit("Worker precondition failed")
PY
if worker_cmd 'sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/$(id -u admiral-apps) podman ps -q | grep -q .'; then echo 'Worker already has a running rootless container' >&2; exit 1; fi
if worker_cmd 'sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/$(id -u admiral-apps) podman ps -aq | grep -q .'; then echo 'Worker has a residual rootless container' >&2; exit 1; fi
if worker_cmd 'ss -ltn "sport = :18081" | grep -q LISTEN'; then echo 'tcp/18081 already has a listener' >&2; exit 1; fi

server_source="$root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/redirect-health-server.go"
GOMAXPROCS=1 GOFLAGS=-p=1 CGO_ENABLED=0 GO111MODULE=off timeout 120s go build -trimpath -o "$tmp/redirect-health-server" "$server_source"
tar --owner=0 --group=0 --numeric-owner -C "$tmp" -cf "$tmp/rootfs.tar" redirect-health-server
cp "$server_source" "$run_dir/redirect-health-server.go"
cp "$tmp/rootfs.tar" "$run_dir/redirect-rootfs.tar"
sha256sum "$server_source" "$tmp/redirect-health-server" "$tmp/rootfs.tar" >"$run_dir/fixture-sha256.txt"
scp "${worker_args[@]}" "$tmp/rootfs.tar" "validator@$worker_ip:/tmp/rc6-271-$run_tag-rootfs.tar"
cat >"$tmp/listener.py" <<'PY'
from http.server import BaseHTTPRequestHandler,HTTPServer
import sys,time
path,port=sys.argv[1],int(sys.argv[2])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(path,"a",encoding="utf-8") as out: out.write(f"{time.time_ns()} {self.client_address[0]} {self.path}\n")
        self.send_response(204); self.end_headers()
    def log_message(self,*_args): pass
HTTPServer(("0.0.0.0",port),Handler).serve_forever()
PY
scp "${worker_args[@]}" "$tmp/listener.py" "validator@$worker_ip:/tmp/rc6-271-$run_tag-listener.py"
worker_cmd "cd / && sudo -n install -d -o validator -g admiral-apps -m 0750 '$work_dir' && sudo -n install -o admiral-apps -g admiral-apps -m 0640 '/tmp/rc6-271-$run_tag-rootfs.tar' '$work_dir/rootfs.tar' && sudo -n install -o validator -g validator -m 0644 '/tmp/rc6-271-$run_tag-listener.py' '$work_dir/listener.py' && sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) podman import --change 'CMD [\"/redirect-health-server\"]' '$work_dir/rootfs.tar' '$remote_image'" >"$run_dir/worker-image-import.log" 2>&1
worker_cmd "cd '$work_dir' || exit 1; nohup python3 -u '$work_dir/listener.py' '$work_dir/redirect-target.log' 18081 >'$work_dir/listener.stdout' 2>&1 </dev/null & echo \$!" >"$run_dir/listener-pid.txt"
listener_pid=$(tr -d '[:space:]' <"$run_dir/listener-pid.txt")
[[ $listener_pid =~ ^[0-9]+$ ]]
for _ in $(seq 1 30); do worker_cmd 'timeout 1 bash -c ":</dev/tcp/127.0.0.1/18081"' >/dev/null 2>&1 && break; sleep 0.2; done
worker_cmd 'ss -ltn "sport = :18081" | grep LISTEN' >"$run_dir/listener-ready.log"
worker_cmd "python3 - '$worker_ip' <<'PY'
import http.client,sys
for host in ('127.0.0.1',sys.argv[1]):
    c=http.client.HTTPConnection(host,18081,timeout=3)
    c.request('GET','/reachability-control')
    status=c.getresponse().status
    c.close()
    print(host,status)
    if status != 204: raise SystemExit('listener target is not reachable')
PY
test -f '$work_dir/redirect-target.log' && : >'$work_dir/redirect-target.log'" >"$run_dir/listener-reachability.log"

run_variant() {
  local variant=$1 target=$2 yaml="$tmp/$1.yaml" response="$tmp/$1-provision.json" last='' checked='' health='' availability='' node_id='' changes=0 deadline hits completed_id
  cat >"$yaml" <<EOF
name: $app_name
display_name: R17 issue 271 redirect probe
description: Disposable Multi-Node health redirect validation.
services:
  web:
    image: $remote_image
    port: 8080
    public: false
    env:
      REDIRECT_TARGET: "$target"
    healthcheck:
      type: http
      port: 8080
      path: /
      expected_status: 302
      timeout_seconds: 2
    healthcheck_wait_timeout: 30
    backup:
      type: none
tiers:
  small:
    cpu: 1
    memory: 128M
    storage: 256M
    price_monthly: 0
    free: true
EOF
  cp "$yaml" "$run_dir/$variant-app.yaml"
  scp "${admin_args[@]}" "$yaml" "validator@$admin_ip:/tmp/$app_name.yaml"
  admin "sudo -n -u validator env HOME=/home/validator admiralctl apps apply --file '/tmp/$app_name.yaml'" >"$run_dir/$variant-apply.log" 2>&1
  admin "sudo -n -u validator env HOME=/home/validator admiralctl instances provision --app '$app_name' --tier small --customer '$customer' --idempotency-key '$customer-$variant' --wait --wait-timeout 5m --quiet --output json" >"$response" 2>"$run_dir/$variant-provision.stderr"
  instance_id=$(python3 - "$response" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
if x.get("status")!="succeeded" or not x.get("instance_id"): raise SystemExit("provision did not succeed")
print(x["instance_id"])
PY
)
  completed_id=$instance_id
  cp "$response" "$run_dir/$variant-provision.json"
  echo "variant=$variant instance=$instance_id redirect=$target" | tee -a "$run_dir/redirect-health.log"
  deadline=$(( $(date +%s) + 60 ))
  while (( $(date +%s) < deadline )); do
    admin "sudo -n -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$tmp/$variant-state.json"
    read -r health availability checked node_id < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("health_status",""),x.get("effective_availability",""),x.get("last_health_checked_at",""),x.get("node_id",""))' <"$tmp/$variant-state.json")
    if [[ $health == healthy && $availability == available && -n $checked ]]; then last=$checked; break; fi
    sleep 1
  done
  [[ $health == healthy && $availability == available && -n $last && $node_id == rc6e5r15-rocky-worker ]]
  deadline=$(( $(date +%s) + 45 ))
  while (( changes < 2 )) && (( $(date +%s) < deadline )); do
    sleep 1
    admin "sudo -n -u validator env HOME=/home/validator admiralctl instances show '$instance_id'" >"$tmp/$variant-state.json"
    read -r health availability checked node_id < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("health_status",""),x.get("effective_availability",""),x.get("last_health_checked_at",""),x.get("node_id",""))' <"$tmp/$variant-state.json")
    hits=$(worker_cmd "test -f '$work_dir/redirect-target.log' && wc -l < '$work_dir/redirect-target.log' || echo 0")
    printf 'variant=%s at=%s health=%s availability=%s checked_at=%s target_hits=%s\n' "$variant" "$(date -u +%FT%TZ)" "$health" "$availability" "$checked" "$hits" | tee -a "$run_dir/redirect-health.log"
    [[ $health == healthy && $availability == available && $hits -eq 0 && $node_id == rc6e5r15-rocky-worker ]]
    if [[ $checked != "$last" ]]; then ((changes+=1)); last=$checked; fi
  done
  (( changes >= 2 ))
  echo "variant=$variant target_requests=0 periodic_reports=$changes result=PASS" | tee -a "$run_dir/redirect-health.log"
  admin "sudo -n -u validator env HOME=/home/validator admiralctl instances deprovision '$completed_id' --force --wait --wait-timeout 5m --output json" >"$run_dir/$variant-deprovision.json"
  python3 - "$run_dir/$variant-deprovision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
if x.get("status")!="succeeded": raise SystemExit("deprovision did not succeed")
PY
  instance_id=''
  worker_cmd "sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) sh -c 'podman ps -a --format {{.Names}}; podman pod ps -a --format {{.Name}}; podman volume ls --format {{.Name}}'" >"$run_dir/$variant-podman-final.txt"
  if grep -F "$completed_id" "$run_dir/$variant-podman-final.txt"; then echo "resources remain for $completed_id" >&2; return 1; fi
}

run_variant loopback http://127.0.0.1:18081/leak
run_variant worker-address "http://$worker_ip:18081/leak"
worker_cmd "cat '$work_dir/redirect-target.log'" >"$run_dir/redirect-target.log"
[[ ! -s $run_dir/redirect-target.log ]]
worker_cmd "kill '$listener_pid'"
listener_pid=''
worker_cmd "sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) podman rmi '$remote_image'" >"$run_dir/worker-image-remove.log" 2>&1
admin "sudo -n -u validator env HOME=/home/validator admiralctl apps deactivate --name '$app_name' --force" >"$run_dir/admin-app-deactivate.log" 2>&1
worker_cmd "sudo -n -u admiral-apps env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR=/run/user/\$(id -u admiral-apps) podman ps -a --format '{{.Names}}|{{.Status}}'; free -m; df -h /" >"$run_dir/worker-after.log"
printf 'issue_271_r17_rocky_multinode=PASS end_utc=%s\n' "$(date -u +%FT%TZ)" | tee -a "$run_dir/run.log"
python3 - "$tmp" <<'PY'
from pathlib import Path
import shutil,sys
shutil.rmtree(Path(sys.argv[1]))
PY
worker_cmd "python3 - '$work_dir' '/tmp/rc6-271-$run_tag-rootfs.tar' '/tmp/rc6-271-$run_tag-listener.py' <<'PY'
from pathlib import Path
import sys
for name in sys.argv[1:]:
    p=Path(name)
    if p.is_dir():
        for f in p.iterdir():
            if f.is_file() or f.is_symlink(): f.unlink()
        p.rmdir()
    elif p.is_file() or p.is_symlink(): p.unlink()
PY"
admin "python3 - '/tmp/$app_name.yaml' <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
if p.is_file() or p.is_symlink(): p.unlink()
PY"
trap - EXIT
cp "$root/docs/audits/admiral-production-readiness-2026-10-21/scripts/r17/issue-271-multinode.sh" "$run_dir/issue-271-multinode.sh"
(cd "$run_dir" && sha256sum *.log *.json *.yaml *.txt *.sha256 *.tar *.go *.sh > SHA256SUMS)
