#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -eq 3 ]] || { echo 'usage: issue-271-guest.sh {rocky|fedora} NODE_IP RUN_TAG' >&2; exit 2; }
os=$1 node_ip=$2 run_tag=$3
[[ $os == rocky || $os == fedora ]] || { echo 'unsupported OS' >&2; exit 2; }
[[ $run_tag =~ ^[A-Za-z0-9_.-]{1,24}$ ]] || { echo 'invalid run tag' >&2; exit 2; }
work_dir="/var/tmp/rc6-271-${os}-${run_tag}"
install -d -m 0750 "$work_dir"
target_log="$work_dir/redirect-target.log"
listener_pid=''
instance_ids=()
cleanup() {
  rc=$?
  trap - EXIT
  for instance_id in "${instance_ids[@]}"; do
    admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 10m --output json >"$work_dir/${instance_id}-trap-deprovision.json" 2>&1 || true
  done
  sudo -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" \
    podman rmi docker.io/library/admiral-redirect-test:rc6 >/dev/null 2>&1 || true
  if [[ -n $listener_pid ]]; then kill "$listener_pid" 2>/dev/null || true; wait "$listener_pid" 2>/dev/null || true; fi
  exit "$rc"
}
trap cleanup EXIT

uid=$(id -u admiral-apps)
sudo -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" \
  podman import --change 'CMD ["/redirect-health-server"]' "$work_dir/rootfs.tar" docker.io/library/admiral-redirect-test:rc6 \
  >"$work_dir/image-import.log"

: > "$target_log"
python3 -u - "$target_log" 18081 >"$work_dir/listener.stdout" 2>&1 <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys, time
path, port = sys.argv[1], int(sys.argv[2])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(path, 'a', encoding='utf-8') as out:
            out.write(f'{time.time_ns()} {self.client_address[0]} {self.path}\n')
        self.send_response(204)
        self.end_headers()
    def log_message(self, *_args):
        pass
HTTPServer(('0.0.0.0', port), Handler).serve_forever()
PY
listener_pid=$!
for _ in $(seq 1 30); do
  if timeout 1 bash -c ':</dev/tcp/127.0.0.1/18081' 2>/dev/null; then break; fi
  sleep 0.1
done
kill -0 "$listener_pid"

write_app() {
  local target=$1
  cat > "$work_dir/app.yaml" <<EOF
name: e2e-health-redirect
display_name: E2E health redirect regression
description: Disposable local app definition for the Fleet HTTP redirect test.
services:
  web:
    image: docker.io/library/admiral-redirect-test:rc6
    port: 8080
    public: false
    env:
      REDIRECT_TARGET: "$target"
    healthcheck:
      type: http
      port: 8080
      path: /health
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
}

run_variant() {
  local variant=$1 target=$2 customer
  local instance_id baseline last_checked changes=0 deadline current health availability checked_at resources
  customer="rc6-271-${os}-${run_tag}-${variant}"
  write_app "$target"
  admiralctl apps apply --file "$work_dir/app.yaml" >"$work_dir/${variant}-apply.log" 2>&1
  admiralctl instances provision --app e2e-health-redirect --tier small --customer "$customer" \
    --idempotency-key "$customer" --wait --wait-timeout 5m --quiet --output json >"$work_dir/${variant}-provision.json"
  instance_id=$(python3 - "$work_dir/${variant}-provision.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'):
    raise SystemExit('provision did not succeed')
print(x['instance_id'])
PY
)
  instance_ids+=("$instance_id")
  deadline=$(( $(date +%s) + 30 ))
  last_checked=''
  while (( $(date +%s) < deadline )); do
    baseline=$(admiralctl instances show "$instance_id")
    read -r health availability checked_at < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("health_status", ""),x.get("effective_availability", ""),x.get("last_health_checked_at", ""))' <<<"$baseline")
    printf 'variant=%s baseline_poll=%s health=%s availability=%s checked_at=%s\n' "$variant" "$(date -u +%FT%TZ)" "$health" "$availability" "$checked_at"
    if [[ $health == healthy && $availability == available && -n $checked_at ]]; then
      last_checked=$checked_at
      break
    fi
    sleep 1
  done
  [[ -n $last_checked ]] || { echo "$variant: no healthy baseline within 30 seconds" >&2; return 1; }
  printf 'variant=%s instance=%s redirect=%s baseline=%s\n' "$variant" "$instance_id" "$target" "$last_checked"
  deadline=$(( $(date +%s) + 30 ))
  while (( changes < 2 )) && (( $(date +%s) < deadline )); do
    sleep 1
    current=$(admiralctl instances show "$instance_id")
    read -r health availability checked_at < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x.get("health_status", ""),x.get("effective_availability", ""),x.get("last_health_checked_at", ""))' <<<"$current")
    printf 'variant=%s utc=%s health=%s availability=%s checked_at=%s target_hits=%s\n' \
      "$variant" "$(date -u +%FT%TZ)" "$health" "$availability" "$checked_at" "$(wc -l < "$target_log")"
    [[ $health == healthy && $availability == available ]] || { echo "$variant: HTTP 302 was not accepted as declared" >&2; return 1; }
    if [[ $checked_at != "$last_checked" ]]; then
      ((changes+=1))
      last_checked=$checked_at
    fi
    [[ ! -s $target_log ]] || { echo "$variant: redirect target received a request" >&2; return 1; }
  done
  [[ $changes -ge 2 ]] || { echo "$variant: fewer than two periodic Fleet health reports" >&2; return 1; }
  printf 'variant=%s target_requests=0 periodic_reports=%s result=PASS\n' "$variant" "$changes"
  admiralctl instances deprovision "$instance_id" --force --wait --wait-timeout 5m --output json >"$work_dir/${variant}-deprovision.json"
  instance_ids=()
  resources=$(sudo -u admiral-apps -- env HOME=/var/lib/admiral-apps XDG_RUNTIME_DIR="/run/user/$uid" \
    podman ps -a --filter "name=$instance_id" --format '{{.Names}}|{{.Status}}')
  [[ -z $resources ]] || { printf '%s\n' "$resources"; return 1; }
}

printf 'issue=271 os=%s candidate=Epoch3-Release5 node_ip=%s start_utc=%s\n' "$os" "$node_ip" "$(date -u +%FT%TZ)"
run_variant loopback "http://127.0.0.1:18081/leak"
run_variant node-address "http://${node_ip}:18081/leak"
[[ ! -s $target_log ]] || { cat "$target_log"; echo 'redirect target received requests' >&2; exit 1; }
printf 'target_listener_requests=%s\n' "$(wc -l < "$target_log")"
echo 'issue_271_redirect_health_checks=PASS'
cp "$target_log" "$work_dir/redirect-target-final.log"
sha256sum "$work_dir"/*.log > "$work_dir/SHA256SUMS"
printf 'evidence_dir=%s\n' "$work_dir"
