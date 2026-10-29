#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
evidence_dir="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r26/runtime/centos-multi"
key="/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519"
known_hosts="/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-portal/known_hosts"
output="$evidence_dir/security-harbor-ready-bind-20261029.log"
domain="rc6e5r18-ipv6-portal"
ip="192.168.122.22"
network_mac="52:54:00:e5:18:c3"

umask 077

graceful_shutdown() {
  if [[ "$(virsh domstate "$domain" 2>/dev/null || true)" != "running" ]]; then
    return
  fi
  virsh shutdown "$domain" >/dev/null 2>&1 || true
  for _ in $(seq 1 18); do
    if [[ "$(virsh domstate "$domain" 2>/dev/null || true)" == "shut off" ]]; then
      printf 'graceful_shutdown=verified\n' >>"$output"
      return
    fi
    sleep 5
  done
  printf 'graceful_shutdown=still_running_after_90s_manual_attention_required\n' >>"$output"
}
trap graceful_shutdown EXIT INT TERM

{
  printf 'probe_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'candidate=RC6 E5 R26 CentOS Stream 10 x86_64 Multi-Node Portal\n'
  printf 'scope=read-only Harbor active-state wait and effective listener capture\n'
  virsh start "$domain" >/dev/null
  sleep 3
  virsh detach-interface "$domain" --type network --mac "$network_mac" --live >/dev/null

  ready=false
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
    exit 1
  fi

  ssh -i "$key" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=5 \
    -o "UserKnownHostsFile=$known_hosts" \
    "validator@$ip" 'sudo -n bash -s' <<'REMOTE'
set -u
source /etc/os-release
printf 'guest_os=%s %s\n' "$ID" "$VERSION_ID"
printf 'installed_harbor_rpm='
rpm -q admiral-harbor 2>&1 || true
printf 'wireguard_address_begin\n'
ip -o -4 addr show dev wg-admiral 2>&1 || true
printf 'wireguard_address_end\n'
active=false
for attempt in $(seq 1 36); do
  state="$(systemctl show admiral-harbor -p ActiveState --value 2>/dev/null || true)"
  substate="$(systemctl show admiral-harbor -p SubState --value 2>/dev/null || true)"
  printf 'harbor_state_attempt=%s active=%s substate=%s\n' "$attempt" "$state" "$substate"
  if [[ "$state" == active ]]; then
    active=true
    break
  fi
  sleep 5
done
printf 'harbor_active=%s\n' "$active"
printf 'harbor_unit_state_begin\n'
systemctl show admiral-harbor \
  -p LoadState -p ActiveState -p SubState -p UnitFileState \
  -p Result -p ExecMainCode -p ExecMainStatus -p NRestarts \
  -p FragmentPath -p ExecStartPre -p ExecStart 2>&1 || true
printf 'harbor_unit_state_end\n'
printf 'listening_sockets_begin\n'
ss -H -lntp
printf 'listening_sockets_end\n'
printf 'harbor_journal_begin\n'
journalctl -u admiral-harbor -b -n 25 --no-pager -o short-precise 2>&1 \
  | sed -E 's/(password|token|secret|credential)([=: ]+)[^ ]+/\1\2[REDACTED]/Ig' || true
printf 'harbor_journal_end\n'
REMOTE

  graceful_shutdown
} >"$output" 2>&1

python3 - "$output" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
active = "harbor_active=true" in text
section = text.split("listening_sockets_begin\n", 1)[1].split("listening_sockets_end", 1)[0]
addresses = [line.split()[3] for line in section.splitlines() if len(line.split()) >= 4]
matches = [address for address in addresses if address.endswith(":5001")]
expected = "10.99.0.3:5001"
with path.open("a") as output:
    output.write(f"assessment_harbor_active={'PASS' if active else 'PARTIAL'}\n")
    output.write(f"assessment_harbor_bind={'PASS' if active and matches == [expected] else 'PARTIAL'}\n")
    output.write(f"assessment_harbor_port_5001_matches={matches!r}\n")
PY

cat "$output"
