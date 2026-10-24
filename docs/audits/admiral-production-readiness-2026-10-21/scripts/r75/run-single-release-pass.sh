#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Prepare, install and execute all three Release 75 Single-Node cells together.
set -euo pipefail
umask 077

[[ $# -eq 3 ]] || {
  echo "usage: $0 ROCKY_IP CENTOS_IP FEDORA_IP" >&2
  exit 2
}
[[ $EUID -eq 0 ]] || { echo "run this lab controller as root" >&2; exit 1; }
: "${R75_SSH_KEY:=/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519}"
[[ -r $R75_SSH_KEY ]] || { echo "validator SSH key is unreadable: $R75_SSH_KEY" >&2; exit 1; }
repo_root=$(git rev-parse --show-toplevel)
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
audit_dir="$repo_root/docs/audits/admiral-production-readiness-2026-10-21"
runtime=${R75_RUNTIME_ROOT:-"$repo_root/packaging/build/validation/rc5-r75/runtime/single-pass-$(date -u +%Y%m%dT%H%M%SZ)"}
known_hosts_dir=${R75_KNOWN_HOSTS_DIR:-/var/lib/libvirt/images/admiral-validation/cloud-init}
[[ ! -e $runtime ]] || { echo "refusing to overwrite existing evidence: $runtime" >&2; exit 1; }
mkdir -p "$runtime/single/rocky" "$runtime/single/centos" "$runtime/single/fedora"
chmod 0700 "$runtime" "$runtime/single" "$runtime/single/rocky" "$runtime/single/centos" "$runtime/single/fedora"
exec > >(tee -a "$runtime/orchestrator.log") 2>&1
chmod 0600 "$runtime/orchestrator.log"
finish() {
  local rc=$?
  trap - EXIT
  find "$runtime" -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$runtime/SHA256SUMS"
  chmod 0600 "$runtime/SHA256SUMS"
  if [[ $rc -eq 0 ]]; then
    printf 'single_node_release75_all_three=PASS end_utc=%s evidence=%s\n' "$(date -u +%FT%TZ)" "$runtime"
  else
    printf 'single_node_release75_all_three=FAIL exit=%s end_utc=%s evidence=%s\n' "$rc" "$(date -u +%FT%TZ)" "$runtime"
  fi
  exit "$rc"
}
trap finish EXIT

declare -A ips=( [rocky]="$1" [centos]="$2" [fedora]="$3" )
declare -A ids=( [rocky]=rocky [centos]=centos [fedora]=fedora )
declare -A profiles=( [rocky]=el10 [centos]=el10 [fedora]=fedora )
declare -A suffixes=( [rocky]=el10 [centos]=el10 [fedora]=fc46 )
declare -A guests=( [rocky]=adm-r75-rocky-single [centos]=adm-r75-centos-single [fedora]=adm-r75-fedora-single )
declare -A pids=()
for os in rocky centos fedora; do
  [[ ${ips[$os]} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid $os guest IPv4" >&2; exit 2; }
  known_hosts="$known_hosts_dir/${guests[$os]}/known_hosts"
  [[ -r $known_hosts ]] || { echo "missing pinned SSH host key for $os: $known_hosts" >&2; exit 1; }
  if [[ -e "$runtime/single/$os/seed_preflight.log" || -e "$runtime/single/$os/install.log" || -e "$runtime/single/$os/install_postcheck.log" || -e "$runtime/single/$os/postcheck.log" ]]; then
    echo "refusing existing $os evidence files under $runtime" >&2
    exit 1
  fi
done

ssh_args_for() {
  local os=$1
  printf '%s\n' -i "$R75_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts_dir/${guests[$os]}/known_hosts" \
    -o ConnectTimeout=5
}

preflight_one() {
  local os=$1 ip=${ips[$1]}
  local attempt ssh_ready=0
  local -a ssh_args=()
  mapfile -t ssh_args < <(ssh_args_for "$os")
  for attempt in $(seq 1 90); do
    if ssh "${ssh_args[@]}" "validator@$ip" true >/dev/null 2>&1; then
      ssh_ready=1
      break
    fi
    sleep 2
  done
  [[ $ssh_ready -eq 1 ]] || { echo "SSH did not become ready for $os at $ip within 180 seconds" >&2; return 1; }
  printf 'ssh_ready os=%s ip=%s attempt=%s utc=%s\n' "$os" "$ip" "$attempt" "$(date -u +%FT%TZ)"
  ssh "${ssh_args[@]}" "validator@$ip" sudo bash -s -- "${ids[$os]}" "${suffixes[$os]}" <<'REMOTE'
set -euo pipefail
expected_id=$1 expected_suffix=$2
source /etc/os-release
printf 'utc=%s host=%s os=%s version=%s arch=%s boot_id=%s selinux=%s\n' \
  "$(date -u +%FT%TZ)" "$(hostname -s)" "$ID" "$VERSION_ID" "$(uname -m)" \
  "$(cat /proc/sys/kernel/random/boot_id)" "$(getenforce)"
[[ $ID == "$expected_id" && $(uname -m) == x86_64 && $(getenforce) == Enforcing ]]
for package in admiral-common admirald admiral-fleet admiralctl admiral-harbor admiral-flagship; do
  if rpm -q "$package" >/dev/null 2>&1; then
    echo "unexpected preinstalled Admiral package: $package" >&2
    exit 1
  fi
done
! getent passwd admiral-apps
! getent group admiral-apps
[[ ! -e /etc/yum.repos.d/admiral-local.repo ]]
for package in python3-alembic python3-flask python3-flask-alembic python3-flask-login \
  python3-flask-sqlalchemy python3-mistune python3-sqlalchemy python3-typing-extensions; do
  rpm -q "$package"
done
printf 'enabled_repositories_begin\n'
dnf repolist --enabled
printf 'enabled_repositories_end\n'
if [[ $expected_suffix == el10 ]]; then
  dnf repolist --enabled | grep -Eiq '(^|[[:space:]])epel([[:space:]]|$)'
  dnf repolist --enabled | grep -Eiq '(^|[[:space:]])crb([[:space:]]|$)'
else
  dnf repolist --enabled | grep -Eiq 'rawhide'
fi
printf 'seed_guest_preflight=PASS\n'
REMOTE
}

install_one() {
  local os=$1 distro=${profiles[$1]} ip=${ips[$1]}
  local known_hosts="$known_hosts_dir/${guests[$os]}/known_hosts"
  ADMIRAL_RC_RELEASE=75 ADMIRAL_AUDIT_REPO_SOURCE=local R75_SSH_KEY="$R75_SSH_KEY" \
    bash "$audit_dir/scripts/install-single-node-audit.sh" "$distro" "$R75_SSH_KEY" \
    "$known_hosts" "validator@$ip" "$ip" "adm-r75-$os-single" \
    "$runtime/single/$os/install-helper.log"
}

postcheck_one() {
  local os=$1 ip=${ips[$1]}
  local known_hosts="$known_hosts_dir/${guests[$os]}/known_hosts"
  mapfile -t ssh_args < <(ssh_args_for "$os")
  ssh "${ssh_args[@]}" "validator@$ip" sudo bash -s -- "${ids[$os]}" "${suffixes[$os]}" \
    < "$script_dir/single-node-postcheck.sh" \
    > "$runtime/single/$os/postcheck.log" 2>&1
}

run_parallel_phase() {
  local phase=$1 function=$2 result=0 os
  echo "phase=$phase start_utc=$(date -u +%FT%TZ)"
  for os in rocky centos fedora; do
    ( "$function" "$os" ) >"$runtime/single/$os/$phase.log" 2>&1 & pids[$os]=$!
  done
  for os in rocky centos fedora; do
    if wait "${pids[$os]}"; then
      echo "phase=$phase os=$os result=PASS"
    else
      rc=$?
      echo "phase=$phase os=$os result=FAIL exit=$rc"
      result=1
    fi
  done
  echo "phase=$phase end_utc=$(date -u +%FT%TZ)"
  return "$result"
}

printf 'candidate=Release75 root_commit=%s start_utc=%s\n' \
  "$(git -C "$repo_root" rev-parse HEAD)" "$(date -u +%FT%TZ)"
printf 'seed_provenance=%s\n' "$audit_dir/evidence/ansible-seed-preflight-20261024.md"
printf 'runtime=%s\n' "$runtime"
run_parallel_phase seed_preflight preflight_one
run_parallel_phase install install_one
run_parallel_phase install_postcheck postcheck_one
R75_SSH_KEY="$R75_SSH_KEY" R75_RUNTIME_ROOT="$runtime" R75_KNOWN_HOSTS_DIR="$known_hosts_dir" \
  bash "$script_dir/run-single-pass.sh" "${ips[rocky]}" "${ips[centos]}" "${ips[fedora]}"

