#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install the exact candidate and run the supported secure installer.
set -euo pipefail
[[ $# -eq 7 ]] || {
  echo "usage: $0 {el10|fedora} SSH_KEY KNOWN_HOSTS USER@GUEST NODE_IP NODE_ID OUTPUT_LOG" >&2
  echo "set ADMIRAL_AUDIT_REPO_SOURCE=copr|local (default: copr)" >&2
  exit 2
}
distro=$1 ssh_key=$2 known_hosts=$3 target=$4 node_ip=$5 node_id=$6 output=$7
release=${ADMIRAL_RC_RELEASE:-21}
version=${ADMIRAL_RC_VERSION:-0.0.1rc6}
epoch=${ADMIRAL_RC_EPOCH:-5}
candidate_id=${ADMIRAL_RC_DIR:-${version#0.0.1}-e${epoch}-r${release}}
repo_source=${ADMIRAL_AUDIT_REPO_SOURCE:-copr}
[[ $release =~ ^[0-9]+$ ]] || { echo "invalid Admiral RPM Release: $release" >&2; exit 2; }
[[ $epoch =~ ^[0-9]{1,4}$ ]] || { echo "invalid Admiral RPM Epoch: $epoch" >&2; exit 2; }
[[ $version =~ ^0\.0\.1rc[0-9]+$ ]] || { echo "invalid Admiral version: $version" >&2; exit 2; }
[[ $repo_source == copr || $repo_source == local ]] || { echo "invalid Admiral RPM source: $repo_source" >&2; exit 2; }
[[ $node_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo "invalid node id" >&2; exit 2; }
[[ $node_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid guest IPv4" >&2; exit 2; }
case "$distro" in
  el10) repo_name=admiral-local-el10.repo; rpm_suffix=el10 ;;
  fedora) repo_name=admiral-local-fedora.repo; rpm_suffix=fc46 ;;
  *) echo "unsupported distribution profile: $distro" >&2; exit 2 ;;
esac
repo_file=${ADMIRAL_AUDIT_REPO_FILE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)/packaging/build/validation/$candidate_id/$repo_name}
if [[ $repo_source == local ]]; then
  [[ -r $repo_file ]] || { echo "local candidate repository config not found: $repo_file" >&2; exit 1; }
fi
repo_dir=${ADMIRAL_AUDIT_REPO_DIR:-}
if [[ $repo_source == local && -n $repo_dir ]]; then
  [[ -d $repo_dir && ! -L $repo_dir && -s $repo_dir/repodata/repomd.xml ]] || {
    echo "local candidate RPM repository is incomplete: $repo_dir" >&2
    exit 1
  }
  if find "$repo_dir" -type l -print -quit | grep -q .; then
    echo "refusing symlinks in local candidate RPM repository: $repo_dir" >&2
    exit 1
  fi
fi
[[ -r $ssh_key && -r $known_hosts ]] || { echo "SSH identity or known-hosts file not readable" >&2; exit 1; }
mkdir -p "$(dirname "$output")"
umask 077
ssh_args=(-i "$ssh_key" -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
{
  printf 'audit_start_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'candidate=%s-%s epoch=%s\n' "$version" "$release" "$epoch"
  if [[ $repo_source == local ]]; then
    if [[ -n $repo_dir ]]; then
      remote_repo_dir=/var/tmp/admiral-audit-local-repo
      ssh "${ssh_args[@]}" "$target" sudo install -d -o root -g root -m 0755 "$remote_repo_dir"
      tar -C "$repo_dir" -cf - . | ssh "${ssh_args[@]}" "$target" \
        sudo tar --no-same-owner -xf - -C "$remote_repo_dir"
      printf 'local_repo_staged=%s\n' "$remote_repo_dir"
    fi
    remote_repo_tmp=$(ssh "${ssh_args[@]}" "$target" 'umask 077; mktemp /tmp/admiral-local.repo.XXXXXX')
    [[ $remote_repo_tmp =~ ^/tmp/admiral-local\.repo\.[[:alnum:]]{6}$ ]] || {
      echo 'guest returned an unexpected candidate repository staging path' >&2
      exit 1
    }
    scp "${ssh_args[@]}" "$repo_file" "$target:$remote_repo_tmp"
    ssh "${ssh_args[@]}" "$target" sudo install -o root -g root -m 0644 \
      "$remote_repo_tmp" /etc/yum.repos.d/admiral-local.repo
    ssh "${ssh_args[@]}" "$target" rm -f -- "$remote_repo_tmp"
  fi
  ssh "${ssh_args[@]}" "$target" sudo bash -s -- "$distro" "$version" "$release" "$rpm_suffix" "$epoch" "$repo_source" <<'REMOTE'
set -euo pipefail
distribution=$1 expected_version=$2 expected_release=$3 rpm_suffix=$4 expected_epoch=$5 repo_source=$6
if [[ $distribution == fedora ]]; then
  dnf install -y dnf5-plugins
else
  dnf install -y dnf-plugins-core
fi
if [[ $distribution == el10 ]]; then
  dnf install -y epel-release
  dnf config-manager --set-enabled crb
fi
if [[ $repo_source == copr ]]; then
  dnf copr enable -y admiral-project/admiral
fi
packages=()
for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
  packages+=("${package}-${expected_version}-${expected_release}.${rpm_suffix}")
done
python_helpers=(python3-alembic python3-flask python3-flask-alembic python3-flask-login python3-flask-sqlalchemy python3-mistune python3-sqlalchemy python3-typing-extensions)
python_before=$(rpm -q --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "${python_helpers[@]}" | sort)
dnf install -y --disablerepo='copr:*' "${packages[@]}"
for package in admiral-common admirald admiralctl admiral-fleet admiral-harbor admiral-flagship; do
  actual=$(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' "$package")
  [[ $actual == "${expected_epoch}:${expected_version}-${expected_release}.${rpm_suffix}" ]] || { echo "$package has unexpected EVR: $actual" >&2; exit 1; }
done
python_after=$(rpm -q --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "${python_helpers[@]}" | sort)
[[ $python_before == "$python_after" ]] || {
  echo 'Python helper RPM baseline changed during Admiral installation' >&2
  diff -u <(printf '%s\n' "$python_before") <(printf '%s\n' "$python_after") || true
  exit 1
}
printf 'python_helper_baseline_unchanged\n%s\n' "$python_after"
REMOTE
  ssh "${ssh_args[@]}" "$target" sudo bash -s -- "$node_ip" "$node_id" <<'REMOTE'
set -euo pipefail
node_ip=$1 node_id=$2
rpm_before=$(mktemp)
rpm_after=$(mktemp)
trap 'rm -f -- "$rpm_before" "$rpm_after"' EXIT
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort >"$rpm_before"
install_start_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
install_started=$SECONDS
set +e
admiral-install --single-node --validation-seed --public-ip "$node_ip" \
  --ssh-public-key /home/validator/validator.pub --node-id "$node_id"
install_rc=$?
set -e
install_elapsed=$((SECONDS - install_started))
install_end_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort >"$rpm_after"
printf 'installer_start_utc=%s installer_end_utc=%s installer_elapsed_seconds=%s installer_exit_code=%s\n' \
  "$install_start_utc" "$install_end_utc" "$install_elapsed" "$install_rc"
printf 'package_nevra_delta_begin (minus=before, plus=after)\n'
diff -u "$rpm_before" "$rpm_after" || true
printf 'package_nevra_delta_end\n'
dnf history info last | sed -n '/^Transaction ID/,$p' | tail -n 30 || true
  if [[ $install_rc -eq 0 ]]; then
    audit_user=${SUDO_USER:-}
    [[ -n $audit_user && $audit_user != root ]] || {
      echo 'cannot initialize the audit CLI: sudo caller is not an unprivileged operator' >&2
      exit 1
    }
    audit_home=$(getent passwd "$audit_user" | cut -d: -f6)
    audit_group=$(id -gn "$audit_user")
    [[ -n $audit_home && -n $audit_group ]] || {
      echo "cannot resolve home and group for audit operator $audit_user" >&2
      exit 1
    }
    cli_config_dir="$audit_home/.config/admiralctl"
    install -d -o "$audit_user" -g "$audit_group" -m 0700 "$cli_config_dir"
    install -o "$audit_user" -g "$audit_group" -m 0644 \
      /etc/admiral/tls/ca.pem "$cli_config_dir/ca.pem"
    . /etc/admiral/flagship.env
    [[ -n ${ADMIRAL_INTERNAL_TOKEN:-} && -n ${ADMIRAL_API_URL:-} ]] || {
      echo 'cannot initialize the audit CLI: generated control-plane credentials are missing' >&2
      exit 1
    }
    runuser -u "$audit_user" -- env HOME="$audit_home" \
      ADMIRAL_OPERATOR_TOKEN="$ADMIRAL_INTERNAL_TOKEN" \
      admiralctl init --server "$ADMIRAL_API_URL" \
      --ca-cert "$cli_config_dir/ca.pem"
    runuser -u "$audit_user" -- env HOME="$audit_home" \
      admiralctl status --output json >/dev/null
    unset ADMIRAL_INTERNAL_TOKEN
  fi
exit "$install_rc"
REMOTE
  printf 'audit_end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} 2>&1 | tee "$output"
chmod 0600 "$output"
