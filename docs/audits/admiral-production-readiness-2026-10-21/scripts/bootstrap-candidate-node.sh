#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Upgrade an existing audit guest to the exact local Admiral RPM candidate.
set -euo pipefail
[[ $# -eq 4 ]] || { echo "usage: $0 {el10|fedora} SSH_KEY KNOWN_HOSTS USER@GUEST" >&2; exit 2; }
distro=$1 ssh_key=$2 known_hosts=$3 target=$4
release=${ADMIRAL_RC_RELEASE:-75}
[[ $release =~ ^[0-9]+$ ]] || { echo "invalid Admiral RPM Release: $release" >&2; exit 2; }
case "$distro" in
  el10) repo_name=admiral-local-el10.repo; mistune_nevra=python3-mistune-3.4.0-1.el10.noarch ;;
  fedora) repo_name=admiral-local-fedora.repo; mistune_nevra=python3-mistune-3.4.0-1.fc46.noarch ;;
  *) echo "unsupported distribution profile: $distro" >&2; exit 2 ;;
esac
repo_file=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)/packaging/build/validation/rc5-r${release}/$repo_name
[[ -r $repo_file && -r $ssh_key && -r $known_hosts ]] || { echo "candidate repo or SSH input is unavailable" >&2; exit 1; }
ssh_args=(-i "$ssh_key" -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
remote_repo_tmp=$(ssh "${ssh_args[@]}" "$target" 'umask 077; mktemp /tmp/admiral-local.repo.XXXXXX')
[[ $remote_repo_tmp =~ ^/tmp/admiral-local\.repo\.[[:alnum:]]{6}$ ]] || {
  echo 'guest returned an unexpected candidate repository staging path' >&2
  exit 1
}
scp "${ssh_args[@]}" "$repo_file" "$target:$remote_repo_tmp"
ssh "${ssh_args[@]}" "$target" sudo install -o root -g root -m 0644 \
    "$remote_repo_tmp" /etc/yum.repos.d/admiral-local.repo
ssh "${ssh_args[@]}" "$target" rm -f -- "$remote_repo_tmp"
ssh "${ssh_args[@]}" "$target" sudo bash -s -- "$distro" "$mistune_nevra" "$release" <<'REMOTE'
set -euo pipefail
distribution=$1 expected_mistune_nevra=$2 expected_release=$3
dnf install -y dnf-plugins-core
if [[ $distribution == el10 ]]; then
    dnf install -y epel-release
    dnf config-manager --set-enabled crb
fi
dnf copr enable -y admiral-project/admiral
packages=()
for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
    packages+=("${package}-0.0.1rc5-${expected_release}.el10")
done
# Keep this diagnostic upgrade pinned to the isolated candidate repository.
# A broad `dnf clean all` refreshes unrelated public mirrors and can block the
# audit before the candidate transaction starts.
dnf -y --disablerepo='*' --enablerepo=admiral-local install "${packages[@]}"
for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
    rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$package" | grep -Fx "$package-0.0.1rc5-${expected_release}.el10.$(rpm -q --qf '%{ARCH}' "$package")"
done
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' python3-mistune | grep -Fx "$expected_mistune_nevra"
REMOTE
