#!/usr/bin/env bash
# Run the R17 #228 Podman-removal fault injection against a registered Rocky
# Multi-Node worker. Product RPMs are not changed by this harness.
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: $0 SSH_KEY ADMIN_KNOWN_HOSTS WORKER_KNOWN_HOSTS ADMIN_IP WORKER_IP FIXTURE OUTPUT_DIR" >&2
  exit 2
fi

ssh_key=$1
admin_known=$2
worker_known=$3
admin_ip=$4
worker_ip=$5
fixture=$6
run_dir=$7
[[ $run_dir == /* ]] || { echo 'OUTPUT_DIR must be absolute' >&2; exit 2; }
[[ -r $fixture ]] || { echo 'fixture must be readable' >&2; exit 2; }
install -d -m 0700 "$run_dir"
umask 077

admin=validator@$admin_ip
worker=validator@$worker_ip
ssh_admin() {
  ssh -i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$admin_known" \
    "$admin" "cd / && $*"
}
ssh_worker() {
  ssh -i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$worker_known" \
    "$worker" "cd / && $*"
}
adminctl() {
  ssh_admin "sudo -u validator env HOME=/home/validator admiralctl $*"
}
worker_podman() {
  local command=$1
  ssh_worker "sudo bash -c 'cd /tmp; uid=\$(id -u admiral-apps); runuser -u admiral-apps -- env XDG_RUNTIME_DIR=/run/user/\$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$uid/bus podman $command'"
}

restore_needed=false
instance_id=
restore_podman() {
  if [[ $restore_needed == true ]]; then
    ssh_worker sudo bash -s -- "$instance_id" \
      < "$(dirname "$0")/../restore-podman-after-injection.sh" \
      > "$run_dir/podman-restore.log" 2>&1 || true
    restore_needed=false
  fi
}
trap restore_podman EXIT INT TERM

printf 'issue=228\ncandidate=RC6-E5-R17\ntopology=Multi-Node\nos=Rocky Linux 10.2 x86_64\nstart_utc=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$run_dir/metadata.txt"
git -C "$(git rev-parse --show-toplevel)" rev-parse HEAD > "$run_dir/root-head.txt"
ssh_admin "rpm -q admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor" \
  > "$run_dir/admin-rpms.txt"
ssh_worker 'rpm -q admiral-common admiral-fleet' > "$run_dir/worker-rpms.txt"
ssh_admin 'sudo -u validator env HOME=/home/validator admiralctl nodes list --output json' \
  > "$run_dir/nodes-before.json"
ssh_worker 'free -b; df -B1 /' > "$run_dir/worker-resources-before.txt"
ssh_worker 'sudo sha256sum /usr/bin/podman' > "$run_dir/podman-before.sha256"

scp -q -i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$admin_known" \
  "$fixture" "$admin:/tmp/audit-e2e-whoami.yaml"
adminctl "apps apply --file /tmp/audit-e2e-whoami.yaml" > "$run_dir/apply.log" 2>&1
adminctl "apps activate --name e2e-whoami" > "$run_dir/activate.log" 2>&1
customer="r17-issue-228-rocky-mn-$(date -u +%Y%m%dT%H%M%SZ)-customer"
idempotency="r17-issue-228-rocky-mn-$(date -u +%Y%m%dT%H%M%SZ)"
set +e
adminctl "instances provision --app e2e-whoami --tier small --customer $customer --node rc6e5r15-rocky-worker --idempotency-key $idempotency --wait --wait-timeout 10m --quiet --output json" \
  > "$run_dir/provision.json" 2> "$run_dir/provision.stderr"
provision_rc=$?
set -e
[[ $provision_rc -eq 0 ]] || { cat "$run_dir/provision.stderr" >&2; exit 1; }
instance_id=$(python3 - "$run_dir/provision.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
if result.get("status") != "succeeded":
    raise SystemExit(f"provision status is {result.get('status')!r}")
if result.get("node_id") != "rc6e5r15-rocky-worker":
    raise SystemExit(f"unexpected worker: {result.get('node_id')!r}")
print(result["instance_id"])
PY
)
[[ $instance_id =~ ^inst_[0-9a-f]{16}$ ]] || { echo 'unexpected instance ID' >&2; exit 1; }
printf 'instance_id=%s\n' "$instance_id" >> "$run_dir/metadata.txt"
ssh_worker sudo bash -s -- "$instance_id" \
  < "$(dirname "$0")/../inject-podman-removal-failure.sh" \
  > "$run_dir/injection-setup.log" 2>&1
restore_needed=true

set +e
adminctl "instances deprovision $instance_id --force --wait --wait-timeout 10m --output json" \
  > "$run_dir/deprovision-injected.json" 2> "$run_dir/deprovision-injected.stderr"
injected_rc=$?
set -e
printf 'injected_deprovision_exit=%s\n' "$injected_rc" >> "$run_dir/metadata.txt"
[[ $injected_rc -ne 0 ]] || { echo 'injected deprovision unexpectedly succeeded' >&2; exit 1; }

ssh_admin 'sudo -u validator env HOME=/home/validator admiralctl instances list --output json' \
  > "$run_dir/instances-after-injection.json"
python3 - "$run_dir/instances-after-injection.json" "$instance_id" <<'PY'
import json, sys
items = json.load(open(sys.argv[1], encoding="utf-8"))
item = next((i for i in items if i.get("id") == sys.argv[2]), None)
if item is None:
    raise SystemExit("injected instance disappeared from control-plane inventory")
if item.get("technical_status") == "deprovisioned":
    raise SystemExit("control plane marked injected instance deprovisioned")
print(json.dumps(item, indent=2, sort_keys=True))
PY
worker_podman 'ps --all --format json' > "$run_dir/containers-after-injection.json"
worker_podman 'pod ps --format json' > "$run_dir/pods-after-injection.json"
worker_podman 'volume ls --format json' > "$run_dir/volumes-after-injection.json"
ssh_worker "sudo cat /var/lib/admiral/audit-podman-fail-$instance_id.log" > "$run_dir/injected-commands.log"
chmod 0600 "$run_dir/injected-commands.log"
sha256sum "$run_dir/injected-commands.log" > "$run_dir/injected-commands.sha256"
python3 - "$run_dir" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for name in ("containers-after-injection.json", "pods-after-injection.json", "volumes-after-injection.json"):
    items = json.load(open(root / name, encoding="utf-8"))
    if not items:
        raise SystemExit(f"expected residual resources missing in {name}")
PY
[[ -s $run_dir/containers-after-injection.json && -s $run_dir/pods-after-injection.json && -s $run_dir/volumes-after-injection.json ]] || {
  echo 'expected residual containers, pod, and volume were not all present' >&2
  exit 1
}
grep -q 'pod rm' "$run_dir/injected-commands.log"
grep -q ' rm ' "$run_dir/injected-commands.log"
grep -q 'volume rm' "$run_dir/injected-commands.log"

restore_podman
ssh_worker "sudo rm -f /var/lib/admiral/audit-podman-fail-$instance_id.log"
ssh_worker 'sudo sha256sum /usr/bin/podman' > "$run_dir/podman-after-restore.sha256"
cmp -s <(awk '{print $1}' "$run_dir/podman-before.sha256") \
  <(awk '{print $1}' "$run_dir/podman-after-restore.sha256") || {
  echo 'Podman binary hash changed after restoration' >&2
  exit 1
}
ssh_worker 'sudo podman --version' > "$run_dir/podman-version-after-restore.txt"

adminctl "instances deprovision $instance_id --force --wait --wait-timeout 10m --output json" \
  > "$run_dir/deprovision-retry.json"
ssh_admin 'sudo -u validator env HOME=/home/validator admiralctl instances list --output json' \
  > "$run_dir/instances-final.json"
worker_podman 'ps --all --format json' > "$run_dir/containers-final.json"
worker_podman 'pod ps --format json' > "$run_dir/pods-final.json"
worker_podman 'volume ls --format json' > "$run_dir/volumes-final.json"
ssh_worker "sudo find /etc/containers/systemd /var/lib/admiral -xdev -iname '*$instance_id*' -print 2>/dev/null || true" \
  > "$run_dir/metadata-residue-final.txt"
ssh_worker 'free -b; df -B1 /' > "$run_dir/worker-resources-after.txt"

python3 - "$run_dir" "$instance_id" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
instance_id = sys.argv[2]
injected = json.load(open(root / "deprovision-injected.json", encoding="utf-8"))
retry = json.load(open(root / "deprovision-retry.json", encoding="utf-8"))
if injected.get("status") != "failed":
    raise SystemExit(f"injected operation status is {injected.get('status')!r}")
if retry.get("status") != "succeeded":
    raise SystemExit(f"retry operation status is {retry.get('status')!r}")
items = json.load(open(root / "instances-final.json", encoding="utf-8"))
item = next((i for i in items if i.get("id") == instance_id), None)
if item is None or item.get("technical_status") != "deprovisioned":
    raise SystemExit("retry did not leave a deprovisioned instance record")
for name in ("containers-final.json", "pods-final.json", "volumes-final.json"):
    if json.load(open(root / name, encoding="utf-8")):
        raise SystemExit(f"residual resource remains in {name}")
if (root / "metadata-residue-final.txt").read_text().strip():
    raise SystemExit("residual instance metadata remains")
print("injected_failure_retained_resources_and_retry_cleanup=PASS")
PY

printf 'end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$run_dir/metadata.txt"
find "$run_dir" -maxdepth 1 -type f -exec chmod 0600 {} +
(
  cd "$run_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
chmod 0600 "$run_dir/SHA256SUMS"
echo "evidence_dir=$run_dir"
