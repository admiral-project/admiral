#!/usr/bin/env bash
# Repeat the rootless user-systemd restart regression four times on one guest.
set -euo pipefail
umask 077

[[ $# -eq 5 ]] || {
  echo "usage: $0 {rocky|fedora} USER@GUEST SSH_KEY KNOWN_HOSTS OUTPUT_DIR" >&2
  exit 2
}
os=$1 guest=$2 key=$3 known_hosts=$4 output_dir=$5
[[ $os == rocky || $os == fedora ]] || { echo 'unsupported OS' >&2; exit 2; }
[[ -r $key && -r $known_hosts ]] || { echo 'SSH key or known_hosts is unreadable' >&2; exit 2; }
mkdir -m 0700 -p "$output_dir"
ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5)
scenario="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../r68/r68-single-user-systemd-restart.sh"
repo_root=$(git rev-parse --show-toplevel)
fixture="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-backup.yaml"
remote_run_dir="/var/tmp/adm-r68-${os}-user-systemd-restart"
run_tag=${RC6_ISSUE_259_RUN_TAG:-$(date -u +%Y%m%dT%H%M%SZ)-$$}
[[ $run_tag =~ ^[A-Za-z0-9_.-]{1,24}$ ]] || { echo 'invalid RC6_ISSUE_259_RUN_TAG' >&2; exit 2; }

for attempt in 1 2 3 4; do
  customer="rc6-259-${os}-${run_tag}-${attempt}"
  idempotency_key="$customer"
  log="$output_dir/run-${attempt}.log"
  printf 'issue=259 os=%s attempt=%s start_utc=%s\n' "$os" "$attempt" "$(date -u +%FT%TZ)" | tee "$log"
  remote_fixture="/tmp/rc6-259-e2e-backup-${attempt}.yaml"
  scp "${ssh_args[@]}" "$fixture" "$guest:$remote_fixture"
  ssh "${ssh_args[@]}" "$guest" sudo install -o root -g root -m 0600 \
    "$remote_fixture" /tmp/audit-e2e-backup.yaml
  ssh "${ssh_args[@]}" "$guest" rm -f -- "$remote_fixture"
  ssh "${ssh_args[@]}" "$guest" sudo bash -s -- "$os" "$customer" "$idempotency_key" \
    <"$scenario" 2>&1 | tee -a "$log"
  ssh "${ssh_args[@]}" "$guest" sudo mv -- "$remote_run_dir" "${remote_run_dir}-run${attempt}"
  printf 'attempt=%s result=PASS end_utc=%s\n' "$attempt" "$(date -u +%FT%TZ)" | tee -a "$log"
done

(cd -- "$output_dir" && sha256sum run-*.log > SHA256SUMS)
printf 'issue_259_repetitions=4 result=PASS output=%s\n' "$output_dir"
