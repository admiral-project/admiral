#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install the exact local RC candidate as an isolated admin/portal hub.
set -euo pipefail

[[ $# -eq 6 || $# -eq 7 ]] || {
  echo "usage: $0 SSH_KEY KNOWN_HOSTS USER@GUEST UNDERLAY_IP NODE_ID OUTPUT_LOG [el10|fedora]" >&2
  exit 2
}
ssh_key=$1 known_hosts=$2 target=$3 underlay_ip=$4 node_id=$5 output=$6
distro=${7:-el10}
release=${ADMIRAL_RC_RELEASE:-1}
version=${ADMIRAL_RC_VERSION:-0.0.1rc6}
candidate_id=${ADMIRAL_RC_DIR:-${version#0.0.1}-r${release}}
[[ $release =~ ^[0-9]+$ ]] || { echo "invalid Admiral RPM Release: $release" >&2; exit 2; }
[[ $version =~ ^0\.0\.1rc[0-9]+$ ]] || { echo "invalid Admiral version: $version" >&2; exit 2; }
[[ $underlay_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid underlay IPv4" >&2; exit 2; }
[[ $node_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo "invalid node id" >&2; exit 2; }
[[ -r $ssh_key && -r $known_hosts ]] || { echo "SSH identity or known-hosts file is unreadable" >&2; exit 1; }
case "$distro" in
  el10) repo_name=admiral-local-el10.repo; rpm_suffix=el10 ;;
  fedora) repo_name=admiral-local-fedora.repo; rpm_suffix=fc46 ;;
  *) echo "unsupported distribution profile: $distro" >&2; exit 2 ;;
esac
repo_file=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)/packaging/build/validation/$candidate_id/$repo_name
[[ -r $repo_file ]] || { echo "local $distro candidate repository is missing: $repo_file" >&2; exit 1; }
mkdir -p "$(dirname "$output")"
umask 077
ssh_args=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts")

{
  printf 'audit_start_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  remote_repo_tmp=$(ssh "${ssh_args[@]}" "$target" 'umask 077; mktemp /tmp/admiral-local.repo.XXXXXX')
  [[ $remote_repo_tmp =~ ^/tmp/admiral-local\.repo\.[[:alnum:]]{6}$ ]] || {
    echo 'guest returned an unexpected candidate repository staging path' >&2
    exit 1
  }
  scp "${ssh_args[@]}" "$repo_file" "$target:$remote_repo_tmp"
  ssh "${ssh_args[@]}" "$target" sudo install -o root -g root -m 0644 \
    "$remote_repo_tmp" /etc/yum.repos.d/admiral-local.repo
  ssh "${ssh_args[@]}" "$target" rm -f -- "$remote_repo_tmp"
  ssh "${ssh_args[@]}" "$target" sudo bash -s -- "$version" "$release" "$distro" "$rpm_suffix" <<'REMOTE'
set -euo pipefail
version=$1 release=$2 distro=$3 rpm_suffix=$4
dnf install -y dnf-plugins-core
if [[ $distro == el10 ]]; then
  dnf install -y epel-release
  dnf config-manager --set-enabled crb
fi
dnf copr enable -y admiral-project/admiral

echo 'PUBLIC_REPOSITORY_DEPENDENCY_QUERY_BEGIN'
dnf --disablerepo=admiral-local repoquery --available --latest-limit=1 \
  --qf '%{name}-%{version}-%{release}.%{arch} %{repoid}' python3-flask python3-mistune
echo 'PUBLIC_REPOSITORY_DEPENDENCY_QUERY_END'

packages=()
for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
  packages+=("${package}-${version}-${release}.${rpm_suffix}")
done
# The immutable OS seed already contains the coherent, tested Python runtime
# baseline. Keep it unchanged: install the exact Admiral NEVRAs with ordinary
# DNF dependency resolution, without updating or reinstalling support RPMs.
dnf install -y "${packages[@]}"

for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
  actual=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' "$package")
  [[ $actual == "${version}-${release}.${rpm_suffix}."* ]] || {
    echo "$package has unexpected NEVRA: $actual" >&2
    exit 1
  }
done
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' python3-flask python3-mistune
REMOTE

ssh "${ssh_args[@]}" "$target" sudo bash -s -- "$underlay_ip" "$node_id" "$version" "$release" "$rpm_suffix" <<'REMOTE'
set -euo pipefail
underlay_ip=$1 node_id=$2 version=$3 release=$4 rpm_suffix=$5
before=$(mktemp)
after=$(mktemp)
trap 'rm -f -- "$before" "$after"' EXIT
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort >"$before"
install_start_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
install_started=$SECONDS
set +e
admiral-install --admin-portal-node --validation-seed --public-ip "$underlay_ip" \
  --ssh-public-key /home/validator/validator.pub --node-id "$node_id"
install_rc=$?
set -e
install_elapsed=$((SECONDS - install_started))
install_end_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort >"$after"
printf 'installer_start_utc=%s installer_end_utc=%s installer_elapsed_seconds=%s installer_exit_code=%s\n' \
  "$install_start_utc" "$install_end_utc" "$install_elapsed" "$install_rc"
printf 'package_nevra_delta_begin (minus=before, plus=after)\n'
diff -u "$before" "$after" || true
printf 'package_nevra_delta_end\n'
if [[ $install_rc -eq 0 ]]; then
  for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
    case "$package" in
      admiral-common|admiral-harbor|admiral-flagship) expected_arch=noarch ;;
      *) expected_arch=x86_64 ;;
    esac
    actual=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$package")
    expected="$package-${version}-${release}.${rpm_suffix}.$expected_arch"
    [[ $actual == "$expected" ]] || {
      echo "$package is not the exact Release ${release}.${rpm_suffix} candidate after install: $actual" >&2
      exit 1
    }
  done
  rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' python3-flask python3-mistune
  audit_user=${SUDO_USER:-}
  [[ -n $audit_user && $audit_user != root ]] || {
    echo 'cannot initialize audit CLI: sudo caller is not an unprivileged operator' >&2
    exit 1
  }
  audit_home=$(getent passwd "$audit_user" | cut -d: -f6)
  audit_group=$(id -gn "$audit_user")
  [[ -n $audit_home && -n $audit_group ]] || { echo 'cannot resolve audit operator account' >&2; exit 1; }
  cli_config_dir="$audit_home/.config/admiralctl"
  install -d -o "$audit_user" -g "$audit_group" -m 0700 "$cli_config_dir"
  install -o "$audit_user" -g "$audit_group" -m 0644 /etc/admiral/tls/ca.pem "$cli_config_dir/ca.pem"
  . /etc/admiral/flagship.env
  [[ -n ${ADMIRAL_INTERNAL_TOKEN:-} && -n ${ADMIRAL_API_URL:-} ]] || {
    echo 'cannot initialize audit CLI: generated control-plane credentials are missing' >&2
    exit 1
  }
  runuser -u "$audit_user" -- env HOME="$audit_home" ADMIRAL_OPERATOR_TOKEN="$ADMIRAL_INTERNAL_TOKEN" \
    admiralctl init --server "$ADMIRAL_API_URL" --ca-cert "$cli_config_dir/ca.pem"
  runuser -u "$audit_user" -- env HOME="$audit_home" ADMIRAL_OPERATOR_TOKEN="$ADMIRAL_INTERNAL_TOKEN" \
    admiralctl status --output json >/dev/null
  unset ADMIRAL_INTERNAL_TOKEN
fi
exit "$install_rc"
REMOTE
  printf 'audit_end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} 2>&1 | tee "$output"
chmod 0600 "$output"
