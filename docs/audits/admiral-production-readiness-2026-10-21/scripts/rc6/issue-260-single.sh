#!/usr/bin/env bash
# Run the declared PostgreSQL service outage check against one RC6 guest.
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
repo_root=$(git rev-parse --show-toplevel)
fixture="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/e2e-backup.yaml"
scenario="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../r69/r69-single-db-service-outage-60s.sh"
run_tag=${RC6_ISSUE_260_RUN_TAG:-$(date -u +%Y%m%dT%H%M%SZ)-$$}
[[ $run_tag =~ ^[A-Za-z0-9_.-]{1,24}$ ]] || { echo 'invalid RC6_ISSUE_260_RUN_TAG' >&2; exit 2; }
candidate=${RC6_CANDIDATE_LABEL:-unspecified}
customer="rc6-260-${os}-${run_tag}"
idempotency_key="$customer"
remote_fixture="/tmp/rc6-260-e2e-backup.yaml"
log="$output_dir/outage-recovery.log"

printf 'issue=260 os=%s candidate=%s acceptance=61-samples-over-60s-per-second start_utc=%s\n' \
  "$os" "$candidate" "$(date -u +%FT%TZ)" > "$log"
scp "${ssh_args[@]}" "$fixture" "$guest:$remote_fixture"
ssh "${ssh_args[@]}" "$guest" sudo install -o root -g root -m 0600 \
  "$remote_fixture" /tmp/audit-e2e-backup.yaml
ssh "${ssh_args[@]}" "$guest" rm -f -- "$remote_fixture"
ssh "${ssh_args[@]}" "$guest" sudo bash -s -- "$os" "$customer" "$idempotency_key" \
  <"$scenario" 2>&1 | tee -a "$log"
(cd -- "$output_dir" && sha256sum outage-recovery.log > SHA256SUMS)
printf 'issue_260_result=PASS output=%s\n' "$output_dir"
