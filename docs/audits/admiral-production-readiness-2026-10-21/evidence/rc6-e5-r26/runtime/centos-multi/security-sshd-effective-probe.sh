#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
evidence_dir="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r26/runtime/centos-multi"
key="/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519"
network_mac="52:54:00:e5:18:c2"
output="$evidence_dir/security-sshd-effective-20261029.log"

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
printf 'sshd_service='
systemctl is-active sshd
printf 'sshd_effective_global=\n'
/usr/sbin/sshd -T | awk '$1 ~ /^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin|authenticationmethods)$/ {print $1 "=" $2}' | sort
printf 'sshd_effective_validator_context=\n'
/usr/sbin/sshd -T -C 'user=validator,host=validator,addr=192.0.2.10' | awk '$1 ~ /^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin|authenticationmethods)$/ {print $1 "=" $2}' | sort
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
  printf 'scope=effective sshd authentication settings; one existing VM at a time\n'
  probe_role admin
  probe_role worker
  probe_role portal
  printf 'probe_result=EVIDENCE_CAPTURED\n'
} >"$output" 2>&1

python3 - "$output" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
sections = {}
current = None
for line in text.splitlines():
    if line.startswith("role="):
        current = line.split()[0].removeprefix("role=")
        sections[current] = {"global": {}, "context": {}, "lines": []}
    elif current is not None:
        sections[current]["lines"].append(line)
        if line == "sshd_effective_global=":
            target = sections[current]["global"]
        elif line == "sshd_effective_validator_context=":
            target = sections[current]["context"]
        elif "target" in locals() and "=" in line:
            key, value = line.split("=", 1)
            if key in {
                "passwordauthentication",
                "kbdinteractiveauthentication",
                "pubkeyauthentication",
                "permitrootlogin",
            }:
                target[key] = value

expected_roles = {"admin", "worker", "portal"}
if set(sections) != expected_roles:
    raise SystemExit(f"role coverage mismatch: {sorted(sections)}")
for role, section in sections.items():
    for mode in ("global", "context"):
        values = section[mode]
        if values.get("passwordauthentication") != "no":
            raise SystemExit(f"{role} {mode}: password authentication is not disabled")
        if values.get("kbdinteractiveauthentication") != "no":
            raise SystemExit(f"{role} {mode}: keyboard-interactive authentication is not disabled")
        if values.get("pubkeyauthentication") != "yes":
            raise SystemExit(f"{role} {mode}: public key authentication is not enabled")
        if values.get("permitrootlogin") not in {"no", "without-password", "prohibit-password"}:
            raise SystemExit(f"{role} {mode}: root login policy is not key-only/disabled")
    if "sshd_service=active" not in section["lines"]:
        raise SystemExit(f"{role}: sshd is not active")
    with Path(sys.argv[1]).open("a") as output:
        output.write(f"assessment_{role}=PASS\n")
with Path(sys.argv[1]).open("a") as output:
    output.write("assessment_result=PASS\n")
PY

cat "$output"
