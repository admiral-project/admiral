#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
evidence_dir="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r26/runtime/centos-multi"
key="/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519"
output="$evidence_dir/security-api-listeners-20261029.log"

declare -A ips=(
  [admin]="192.168.122.20"
  [worker]="192.168.122.21"
  [portal]="192.168.122.22"
)
declare -A domains=(
  [admin]="rc6e5r18-ipv6-admin"
  [worker]="rc6e5r18-ipv6-worker"
  [portal]="rc6e5r18-ipv6-portal"
)
declare -A network_macs=(
  [admin]="52:54:00:e5:18:c1"
  [worker]="52:54:00:e5:18:c2"
  [portal]="52:54:00:e5:18:c3"
)

umask 077

cleanup() {
  for role in admin worker portal; do
    domain="${domains[$role]}"
    if [[ "$(virsh domstate "$domain" 2>/dev/null || true)" == "running" ]]; then
      virsh shutdown "$domain" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

probe_role() {
  local role="$1"
  local domain="${domains[$role]}"
  local ip="${ips[$role]}"
  local network_mac="${network_macs[$role]}"
  local known_hosts="/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-$role/known_hosts"

  printf 'role=%s domain=%s ip=%s\n' "$role" "$domain" "$ip"
  virsh start "$domain" >/dev/null
  sleep 3
  virsh detach-interface "$domain" --type network --mac "$network_mac" --live >/dev/null

  local ready=false
  for attempt in $(seq 1 24); do
    if ssh -i "$key" \
      -o IdentitiesOnly=yes \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=yes \
      -o ConnectTimeout=4 \
      -o "UserKnownHostsFile=$known_hosts" \
      "validator@$ip" true >/dev/null 2>&1; then
      printf 'ssh_ready_attempt=%s\n' "$attempt"
      ready=true
      break
    fi
    sleep 5
  done
  if [[ "$ready" != true ]]; then
    printf 'ssh_ready=false\n'
    return 1
  fi

  ssh -i "$key" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=5 \
    -o "UserKnownHostsFile=$known_hosts" \
    "validator@$ip" 'sudo -n bash -s' <<'REMOTE'
set -euo pipefail
source /etc/os-release
printf 'guest_os=%s %s\n' "$ID" "$VERSION_ID"
printf 'admiral_packages=\n'
rpm -qa 'admiral-*' --qf '%{NEVRA}\n' | sort
printf 'listening_sockets_begin\n'
ss -H -lntp
printf 'listening_sockets_end\n'
REMOTE

  virsh shutdown "$domain" >/dev/null
  local stopped=false
  for attempt in $(seq 1 18); do
    if [[ "$(virsh domstate "$domain")" == "shut off" ]]; then
      printf 'graceful_shutdown=verified\n'
      stopped=true
      break
    fi
    sleep 5
  done
  [[ "$stopped" == true ]]
}

{
  printf 'probe_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'candidate=RC6 E5 R26 CentOS Stream 10 x86_64 Multi-Node\n'
  printf 'scope=effective Admiral API TCP listen addresses; one existing VM at a time\n'
  probe_role admin
  probe_role worker
  probe_role portal
  printf 'probe_result=EVIDENCE_CAPTURED\n'
} >"$output" 2>&1

python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
blocks = re.split(r"(?m)^role=", text)[1:]
expected = {
    "admin": {"8080": "10.99.0.1", "2019": "127.0.0.1", "5432": "127.0.0.1"},
    "worker": {"9099": "10.99.0.2"},
    "portal": {"5001": "10.99.0.3"},
}
seen = set()
for block in blocks:
    role = block.split()[0]
    if role not in expected:
        continue
    seen.add(role)
    assert "guest_os=centos 10" in block, role
    assert "graceful_shutdown=verified" in block, role
    listener_text = block.split("listening_sockets_begin\n", 1)[1].split("listening_sockets_end", 1)[0]
    local_addresses = [line.split()[3] for line in listener_text.splitlines() if len(line.split()) >= 4]
    for port, address in expected[role].items():
        matches = [item for item in local_addresses if item.endswith(f":{port}")]
        wanted = f"{address}:{port}"
        assert matches == [wanted], (role, port, matches, wanted)
    api_port = {"admin": "8080", "worker": "9099", "portal": "5001"}[role]
    with Path(sys.argv[1]).open("a") as output:
        output.write(f"assessment_{role}_api_bind=PASS\n")
        if role == "admin":
            output.write("assessment_admin_caddy_admin_and_postgres_loopback=PASS\n")
assert seen == set(expected), seen
with Path(sys.argv[1]).open("a") as output:
    output.write("assessment_result=PASS\n")
PY

cat "$output"
