#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Reboot a disposable Single-Node guest and verify runtime/data convergence.
set -euo pipefail
[[ $# -eq 6 ]] || {
  echo "usage: $0 {fedora|rocky|alma|centos} GUEST_NAME USER@GUEST SSH_KEY KNOWN_HOSTS CUSTOMER" >&2
  exit 2
}
os=$1 guest_name=$2 target=$3 ssh_key=$4 known_hosts=$5 customer=$6
case "$os" in fedora|rocky|alma|centos) ;; *) echo 'unsupported OS key' >&2; exit 2 ;; esac
release=${ADMIRAL_RC_RELEASE:-26}
[[ $release =~ ^[0-9]+$ ]] || { echo 'invalid Admiral release label' >&2; exit 2; }
marker="r${release}-reboot-persisted"
[[ $guest_name =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || { echo 'invalid guest name' >&2; exit 2; }
[[ $customer =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo 'invalid customer' >&2; exit 2; }
[[ -r $ssh_key && -r $known_hosts ]] || { echo 'SSH identity or known_hosts is unavailable' >&2; exit 1; }
repo_root=${RC6_REPO_ROOT:-$(git rev-parse --show-toplevel)}
fixture="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-backup.yaml"
[[ -r $fixture ]] || { echo "fixture not found: $fixture" >&2; exit 1; }
ssh_args=(-i "$ssh_key" -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" -o ConnectTimeout=5)
ssh_guest() { ssh "${ssh_args[@]}" "$target" "$@"; }
idempotency_key="r${release}-${os}-reboot-$(date -u +%Y%m%dT%H%M%SZ)-$$"
previous_boot_id=$(ssh_guest 'cat /proc/sys/kernel/random/boot_id')
printf 'test=R%s-%s-SN-REBOOT guest=%s start_utc=%s\n' "$release" "$os" "$guest_name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'idempotency_key=%s\n' "$idempotency_key"
printf 'boot_id_before=%s\n' "$previous_boot_id"
ssh_guest 'sudo install -o root -g root -m 0644 /dev/stdin /tmp/audit-e2e-backup.yaml' < "$fixture"
set +e
ssh_guest 'sudo bash -s --' <<REMOTE
set -euo pipefail
cd /
printf 'pre_reboot_setup_started_utc=%s\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
os='$os'
customer='$customer'
idempotency_key='$idempotency_key'
run_dir="/var/tmp/adm-r${release}-${os}-host-reboot"
install -d -m 0700 "\$run_dir"
cp /tmp/audit-e2e-backup.yaml "\$run_dir/fixture.yaml"
chmod 0600 "\$run_dir/fixture.yaml"
admiralctl apps apply --file "\$run_dir/fixture.yaml" > "\$run_dir/apply.log" 2>&1
admiralctl instances provision --app e2e-backup --tier small --customer "\$customer" --idempotency-key "\$idempotency_key" --wait --wait-timeout 10m --quiet --output json > "\$run_dir/provision.json"
python3 - "\$run_dir/provision.json" "\$run_dir/identity.txt" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
if x.get('status')!='succeeded' or not x.get('instance_id'): raise SystemExit('initial provision failed')
with open(sys.argv[2],'w',encoding='utf-8') as f:
 f.write(x['instance_id']+'\\n'+str(x.get('id') or x.get('operation_id'))+'\\n')
print('provision_status=',x.get('status'),'instance_id=',x.get('instance_id'),'operation_id=',x.get('id') or x.get('operation_id'))
PY
instance_id=\$(head -n1 "\$run_dir/identity.txt")
uid=\$(id -u admiral-apps)
db_container="admiral-\${instance_id}-db"
false_healthy_before_db_ready=0
db_ready=0
for attempt in \$(seq 1 60); do
  admiralctl instances show "\$instance_id" > "\$run_dir/instance-during-startup.json"
  fields=\$(python3 - "\$run_dir/instance-during-startup.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)
  db_state=\$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman inspect --format '{{.State.Status}}' "\$db_container" 2>/dev/null || printf absent)
  db_probe=\$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman exec "\$db_container" pg_isready -h 127.0.0.1 -p 5432 2>&1 || true)
  [[ \$db_state == running && \$db_probe == *'accepting connections'* ]] && db_ready=1
  printf 'provision_readiness_poll=%s utc=%s api=%s db_state=%s db_ready=%s\\n' "\$attempt" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$fields" "\$db_state" "\$db_ready"
  read -r technical health availability <<< "\$fields"
  if [[ \$db_ready -eq 0 && \$health == healthy && \$availability == available ]]; then
    false_healthy_before_db_ready=1
    echo 'false healthy/available reported while declared PostgreSQL service was not ready'
  fi
  [[ \$db_ready -eq 1 ]] && break
  [[ \$attempt -lt 60 ]] || { echo 'PostgreSQL did not become ready within 60 seconds' >&2; exit 1; }
  sleep 1
done
printf '%s\\n' "\$false_healthy_before_db_ready" > "\$run_dir/false-healthy-before-db-ready.txt"
echo "database_readiness_seconds_tested=\$attempt"
printf "CREATE TABLE IF NOT EXISTS admiral_reboot_marker (value TEXT PRIMARY KEY); TRUNCATE admiral_reboot_marker; INSERT INTO admiral_reboot_marker(value) VALUES ('${marker}');\\n" | runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman exec -i "\$db_container" sh -c 'export PGPASSWORD="\$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "\$POSTGRES_USER" -d "\$POSTGRES_DB" -v ON_ERROR_STOP=1' > "\$run_dir/marker-before-reboot.txt"
cat "\$run_dir/marker-before-reboot.txt"
printf 'reboot_requested_utc=%s instance_id=%s operation_id=%s\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$instance_id" "\$(tail -n1 "\$run_dir/identity.txt")"
sync
printf 'reboot_request_issued_utc=%s\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
systemctl reboot --no-block
REMOTE
reboot_rc=$?
set -e
if [[ $reboot_rc -ne 0 && $reboot_rc -ne 255 ]]; then
  echo "pre-reboot SSH command exit=$reboot_rc (expected 0 or disconnect 255)" >&2
  exit "$reboot_rc"
fi
printf 'reboot_ssh_exit=%s (disconnect after reboot request is expected)\n' "$reboot_rc"
reconnected=0
for attempt in $(seq 1 90); do
  current_boot_id=$(ssh_guest 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
  if [[ -n $current_boot_id && $current_boot_id != "$previous_boot_id" ]]; then
    echo "reboot_confirmed_attempt=$attempt boot_id_after=$current_boot_id utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reconnected=1
    break
  fi
  sleep 2
done
[[ $reconnected -eq 1 ]] || { echo 'guest SSH did not return within 180s; preserve guest and logs' >&2; exit 1; }
ssh_guest 'sudo bash -s --' <<REMOTE
set -euo pipefail
cd /
os='$os'
run_dir="/var/tmp/adm-r${release}-${os}-host-reboot"
instance_id=\$(head -n1 "\$run_dir/identity.txt")
operation_id=\$(tail -n1 "\$run_dir/identity.txt")
printf 'post_reboot_start_utc=%s instance_id=%s operation_id=%s\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$instance_id" "\$operation_id"
recovered=0
uid=\$(id -u admiral-apps)
for attempt in \$(seq 1 60); do
  if ! admiralctl instances show "\$instance_id" > "\$run_dir/instance-after-reboot.json" 2> "\$run_dir/api-poll.stderr"; then
    printf 'post_reboot_poll=%s api=unavailable utc=%s\\n' "\$attempt" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sleep 5
    continue
  fi
  fields=\$(python3 - "\$run_dir/instance-after-reboot.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('technical_status',''),x.get('health_status',''),x.get('effective_availability',''))
PY
)
  read -r technical health availability <<< "\$fields"
  runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman ps --all --filter name="\$instance_id" --format '{{.Names}}|{{.Status}}' > "\$run_dir/containers-after-reboot.txt"
  running_count=\$(grep -c '|Up ' "\$run_dir/containers-after-reboot.txt" || true)
  db_container="admiral-\${instance_id}-db"
  db_probe=\$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman exec "\$db_container" pg_isready -h 127.0.0.1 -p 5432 2>&1 || true)
  db_ready=0
  [[ \$db_probe == *'accepting connections'* ]] && db_ready=1
  printf 'post_reboot_poll=%s utc=%s status=%s running_containers=%s db_ready=%s\\n' "\$attempt" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$fields" "\$running_count" "\$db_ready"
  if [[ \$health == healthy && \$availability == available && ( \$running_count -lt 3 || \$db_ready -eq 0 ) ]]; then
    echo 'false healthy/available state while a required runtime service is not ready' >&2
    exit 1
  fi
  if [[ \$technical == running && \$health == healthy && \$availability == available && \$running_count -eq 3 && \$db_ready -eq 1 ]]; then
    recovered=1
    break
  fi
  [[ \$attempt -lt 60 ]] || { echo 'instance did not recover within 5 minutes' >&2; exit 1; }
  sleep 5
done
[[ \$recovered -eq 1 ]] || exit 1
app_container="admiral-\${instance_id}-app"
port=\$(runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman port "\$app_container" 80/tcp | head -n1 | awk -F: '{print \$NF}')
[[ \$port =~ ^[0-9]+\$ ]] || { echo 'app port mapping missing after reboot' >&2; exit 1; }
http=\$(curl --silent --show-error --max-time 5 --output "\$run_dir/http-after-reboot.txt" --write-out '%{http_code}' "http://127.0.0.1:\$port/")
printf 'post_reboot_http=%s port=%s\\n' "\$http" "\$port"
[[ \$http == 200 ]] || { echo 'HTTP failed after reboot' >&2; exit 1; }
db_container="admiral-\${instance_id}-db"
printf 'SELECT value FROM admiral_reboot_marker;\\n' | runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman exec -i "\$db_container" sh -c 'export PGPASSWORD="\$POSTGRES_PASSWORD"; exec psql -h 127.0.0.1 -U "\$POSTGRES_USER" -d "\$POSTGRES_DB" -At -v ON_ERROR_STOP=1' > "\$run_dir/marker-after-reboot.txt"
cat "\$run_dir/marker-after-reboot.txt"
[[ \$(tr -d '\\r\\n' < "\$run_dir/marker-after-reboot.txt") == ${marker} ]] || { echo 'SQL marker was not preserved' >&2; exit 1; }
admiralctl instances deprovision "\$instance_id" --force --wait --wait-timeout 10m --output json > "\$run_dir/deprovision.json"
cat "\$run_dir/deprovision.json"
runuser -u admiral-apps -- env XDG_RUNTIME_DIR="/run/user/\$uid" podman ps --all --filter name="\$instance_id" --format '{{.Names}}' > "\$run_dir/containers-after-cleanup.txt"
[[ ! -s "\$run_dir/containers-after-cleanup.txt" ]] || { cat "\$run_dir/containers-after-cleanup.txt"; exit 1; }
echo 'host_reboot_recovery_and_sql_marker=PASS'
if [[ \$(cat "\$run_dir/false-healthy-before-db-ready.txt") == 1 ]]; then
  echo 'provision_readiness_consistency=FAIL: API reported healthy/available before PostgreSQL accepted connections' >&2
  exit 1
fi
echo 'provision_readiness_consistency=PASS'
printf 'post_reboot_end_utc=%s\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REMOTE
