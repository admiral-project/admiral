#!/usr/bin/env bash
# Run the RC6 HTTP health-redirect regression on one installed diagnostic guest.
set -euo pipefail
umask 077
[[ $# -eq 6 ]] || { echo 'usage: issue-271-single.sh {rocky|fedora} USER@GUEST NODE_IP SSH_KEY KNOWN_HOSTS OUTPUT_DIR' >&2; exit 2; }
os=$1 guest=$2 node_ip=$3 key=$4 known_hosts=$5 output_dir=$6
[[ $os == rocky || $os == fedora ]] || { echo 'unsupported OS' >&2; exit 2; }
[[ -r $key && -r $known_hosts ]] || { echo 'SSH key or known_hosts is unreadable' >&2; exit 2; }
[[ $node_ip =~ ^[0-9.]+$ ]] || { echo 'invalid node IP' >&2; exit 2; }
mkdir -m 0700 -p "$output_dir"
run_tag=${RC6_ISSUE_271_RUN_TAG:-$(date -u +%Y%m%dT%H%M%SZ)-$$}
[[ $run_tag =~ ^[A-Za-z0-9_.-]{1,24}$ ]] || { echo 'invalid RC6_ISSUE_271_RUN_TAG' >&2; exit 2; }
candidate=${RC6_CANDIDATE_LABEL:-unspecified}
repo_root=$(git rev-parse --show-toplevel)
guest_script="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/scripts/rc6/issue-271-guest.sh"
server_source="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/fixtures/redirect-health-server.go"
ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$tmp/redirect-health-server" "$server_source"
tar --owner=0 --group=0 --numeric-owner -C "$tmp" -cf "$tmp/rootfs.tar" redirect-health-server
work_dir="/var/tmp/rc6-271-${os}-${run_tag}"
scp "${ssh_args[@]}" "$tmp/rootfs.tar" "$guest:/tmp/rc6-271-rootfs-${run_tag}.tar"
scp "${ssh_args[@]}" "$guest_script" "$guest:/tmp/issue-271-guest-${run_tag}.sh"
ssh "${ssh_args[@]}" "$guest" "cd / && sudo install -d -o validator -g admiral-apps -m 0750 '$work_dir'"
ssh "${ssh_args[@]}" "$guest" "cd / && sudo install -o admiral-apps -g admiral-apps -m 0644 '/tmp/rc6-271-rootfs-${run_tag}.tar' '$work_dir/rootfs.tar'"
ssh "${ssh_args[@]}" "$guest" "cd / && sudo rm -f '/tmp/rc6-271-rootfs-${run_tag}.tar'"
log="$output_dir/redirect-health.log"
printf 'issue=271 os=%s candidate=%s run_tag=%s start_utc=%s\n' \
  "$os" "$candidate" "$run_tag" "$(date -u +%FT%TZ)" > "$log"
status=0
ssh "${ssh_args[@]}" "$guest" "cd / && bash '/tmp/issue-271-guest-${run_tag}.sh' '$os' '$node_ip' '$run_tag' '$candidate'" 2>&1 | tee -a "$log" || status=$?
if ssh "${ssh_args[@]}" "$guest" "cd / && sudo tar -C /var/tmp -czf '/tmp/rc6-271-${run_tag}.tar.gz' 'rc6-271-${os}-${run_tag}'" \
    && scp "${ssh_args[@]}" "$guest:/tmp/rc6-271-${run_tag}.tar.gz" "$output_dir/guest-evidence.tar.gz"; then
  ssh "${ssh_args[@]}" "$guest" "cd / && sudo rm -rf '$work_dir' '/tmp/rc6-271-${run_tag}.tar.gz' '/tmp/issue-271-guest-${run_tag}.sh'"
else
  status=1
fi
(cd "$output_dir" && sha256sum redirect-health.log guest-evidence.tar.gz > SHA256SUMS) || status=$?
[[ $status -eq 0 ]] || exit "$status"
printf 'issue_271_result=PASS output=%s\n' "$output_dir"
