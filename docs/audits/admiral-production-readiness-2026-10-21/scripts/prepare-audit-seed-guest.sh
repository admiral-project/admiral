#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Refresh a disposable guest and install Admiral RPM runtime Requires before it
# is flattened into a reusable validation seed. Run as root inside the guest.
set -euo pipefail

os_id=$(. /etc/os-release && printf '%s' "$ID")
version_id=$(. /etc/os-release && printf '%s' "$VERSION_ID")
case "$os_id:$version_id" in
  rocky:10*|almalinux:10*|centos:10*)
    dnf install -y epel-release dnf-plugins-core
    dnf config-manager --set-enabled crb
    # The public EPEL mirror list returned transient checksum/TLS failures in
    # this lab. Use Fedora's canonical HTTPS origin while retaining GPG checks.
    epel_repo=/etc/yum.repos.d/epel.repo
    epel_baseurl='https://dl.fedoraproject.org/pub/epel/$releasever/Everything/$basearch/'
    if ! grep -Fq '# Admiral audit seed canonical EPEL origin' "$epel_repo"; then
      sed -i '/^\[epel\]$/,/^\[/ { s|^metalink=|#metalink=|; s|^baseurl=|#baseurl=|; }' "$epel_repo"
      sed -i "/^\[epel\]$/a # Admiral audit seed canonical EPEL origin\\nbaseurl=$epel_baseurl" "$epel_repo"
    fi
    ;;
  fedora:*)
    dnf install -y dnf5-plugins
    ;;
  *)
    echo "unsupported audit seed OS: $os_id $version_id" >&2
    exit 2
    ;;
esac

dnf copr enable -y admiral-project/admiral

# Release-candidate audit seeds may use an isolated host-served repository to
# keep the RPM's pinned Python dependency set coherent with its exact specs.
# The repo file is staged into the guest before this script is run.
if [[ -n ${ADMIRAL_AUDIT_LOCAL_REPO_FILE:-} ]]; then
  local_repo_file=$ADMIRAL_AUDIT_LOCAL_REPO_FILE
  [[ -f $local_repo_file && ! -L $local_repo_file ]] || {
    echo "invalid local Admiral audit repo file: $local_repo_file" >&2
    exit 1
  }
  install -o root -g root -m 0644 "$local_repo_file" \
    /etc/yum.repos.d/admiral-local.repo
fi

copr_repo=$(find /etc/yum.repos.d -maxdepth 1 -type f \
  -name '*admiral-project*admiral*.repo' -print -quit)
[[ -n "$copr_repo" ]] || { echo "missing Admiral COPR repository file" >&2; exit 1; }
grep -Eq '^[[:space:]]*gpgcheck[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$copr_repo" || {
  echo "Admiral COPR repository does not enforce GPG metadata checks" >&2
  exit 1
}

if [[ "$os_id" == rocky || "$os_id" == almalinux ]]; then
  # Rocky and AlmaLinux 10.2 use the verified EPEL 10.1 pyOpenSSL 25 pin
  # because the current EPEL build requires a cryptography version that is
  # not available from their base repositories. CentOS Stream 10 provides a
  # compatible cryptography version and uses its normal EPEL package set.
  pinned_rpm=/var/tmp/python3-pyOpenSSL-25.0.0-1.el10_1.noarch.rpm
  dnf install -y curl
  curl --fail --location --retry 3 --retry-all-errors --connect-timeout 10 --max-time 90 \
    -o "$pinned_rpm" \
    https://dl.fedoraproject.org/pub/archive/epel/10.1/Everything/x86_64/Packages/p/python3-pyOpenSSL-25.0.0-1.el10_1.noarch.rpm
  printf '%s  %s\n' \
    eb5d2a6be0e47099c63fa042f83afac12021820bfc0d79fa0f9dcd57b71941dc "$pinned_rpm" | sha256sum --check
  # epel-release installs the official EPEL key but does not always import it
  # into RPM's local keyring until a repository package transaction needs it.
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10
  rpmkeys --checksig "$pinned_rpm"
  dnf install -y "$pinned_rpm"
  if ! sed -n '/^\[epel\]$/,/^\[/p' /etc/yum.repos.d/epel.repo | \
      grep -Eq '^excludepkgs=.*(^|[ ,])python3-pyOpenSSL([ ,]|$)'; then
    sed -i '/^\[epel\]$/a excludepkgs=python3-pyOpenSSL' /etc/yum.repos.d/epel.repo
  fi
fi

# Refresh the OS and enabled EPEL/Admiral repositories once while building the
# seed. These package names are the union of explicit Requires in the six
# Admiral RPM specs plus SQLAlchemy's versioned Flask-Alembic dependency;
# admiral-common itself is installed later by the installer.
dnf -y update --refresh --allowerasing

packages=(
  ansible-collection-ansible-posix ansible-core caddy certbot curl gnupg2
  openssh-clients openssh-server openssl policycoreutils-python-utils podman
  postgresql postgresql-server python3 python3-argon2-cffi python3-cryptography
  python3-flask python3-flask-alembic python3-flask-login
  python3-flask-sqlalchemy python3-gunicorn python3-mistune python3-psycopg2
  python3-sqlalchemy
  python3-pyyaml python3-requests python3-werkzeug shadow-utils systemd
  systemd-container wireguard-tools
)
dnf install -y "${packages[@]}"

# The current local release-candidate repository carries newer Python RPMs
# than the public COPR snapshot (notably Flask and Mistune). When candidate
# RPMs are staged by the host, install them so the seed satisfies the exact
# package Requires that will be exercised by this release validation.
candidate_python_rpms=()
if [[ -d /var/tmp/admiral-candidate-python-rpms ]]; then
  shopt -s nullglob
  candidate_python_rpms=(/var/tmp/admiral-candidate-python-rpms/*.rpm)
  shopt -u nullglob
fi
if ((${#candidate_python_rpms[@]})); then
  candidate_rpm_key=${ADMIRAL_AUDIT_RPM_GPG_KEY_FILE:-}
  [[ -n $candidate_rpm_key && -f $candidate_rpm_key && ! -L $candidate_rpm_key ]] || {
    echo "staged candidate Python RPMs require ADMIRAL_AUDIT_RPM_GPG_KEY_FILE" >&2
    exit 1
  }
  expected_key_fingerprint=7103D33100F674D0B3DFAD17B943D0C834ED6667
  actual_key_fingerprint=$(gpg --batch --with-colons --show-keys "$candidate_rpm_key" |
    awk -F: '$1 == "fpr" { print $10; exit }')
  [[ $actual_key_fingerprint == "$expected_key_fingerprint" ]] || {
    echo "unexpected Admiral candidate RPM signing key fingerprint: $actual_key_fingerprint" >&2
    exit 1
  }
  rpm --import "$candidate_rpm_key"
  for candidate_rpm in "${candidate_python_rpms[@]}"; do
    signature_status=$(rpmkeys --checksig --verbose "$candidate_rpm" 2>&1) || {
      echo "$signature_status" >&2
      exit 1
    }
    if grep -Eq 'NOKEY|NOT OK|BAD' <<<"$signature_status" ||
        ! grep -Eiq 'signature.*: OK' <<<"$signature_status"; then
      echo "candidate Python RPM signature verification failed: $candidate_rpm" >&2
      echo "$signature_status" >&2
      exit 1
    fi
    printf '%s\n' "$signature_status"
  done
  dnf install -y --setopt=localpkg_gpgcheck=1 "${candidate_python_rpms[@]}"
fi
dnf -y update --refresh --allowerasing

# Local candidate repositories are configured manually for each validation
# lab. Use the signed local repo to install this release's Python RPM set, then
# remove its configuration before generalizing the OS seed.
if [[ ${ADMIRAL_AUDIT_REMOVE_LOCAL_REPO:-0} == 1 ]]; then
  python3 - <<'PY'
from pathlib import Path

repo = Path("/etc/yum.repos.d/admiral-local.repo")
if repo.is_symlink():
    raise SystemExit(f"refusing to remove symlink: {repo}")
repo.unlink(missing_ok=True)
PY
  dnf clean metadata
  if [[ $os_id == fedora ]]; then
    dnf -y update --refresh --allowerasing --allow-vendor-change
  else
    dnf -y update --refresh --allowerasing
  fi
fi

printf 'Prepared audit seed for %s %s at ' "$os_id" "$version_id"
date -u +'%Y-%m-%dT%H:%M:%SZ'
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "${packages[@]}"
if ((${#candidate_python_rpms[@]})); then
  rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    python3-alembic python3-flask python3-flask-alembic python3-flask-login \
    python3-flask-sqlalchemy python3-mistune python3-sqlalchemy \
    python3-typing-extensions
fi
if [[ "$os_id" == rocky || "$os_id" == almalinux ]]; then
  rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' python3-pyOpenSSL
fi
rpm -q --qf 'kernel-core-%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core 2>/dev/null || true
dnf history info last | sed -n '/^Transaction ID/,$p' | tail -n 20

set +e
update_output=/var/tmp/admiral-audit-seed-check-update.txt
dnf -q check-update > "$update_output" 2>&1
check_update_status=$?
set -e
if [[ $check_update_status -eq 100 ]]; then
  if ((${#candidate_python_rpms[@]} == 0)); then
    cat "$update_output"
    echo "updates remain after seed refresh" >&2
    exit 1
  fi
  python3 - "$update_output" "${candidate_python_rpms[@]}" <<'PY'
from pathlib import Path
import subprocess
import sys

update_file = Path(sys.argv[1])
candidate_paths = sys.argv[2:]
pinned = {}
for path in candidate_paths:
    name, evr = subprocess.check_output(
        ["rpm", "-qp", "--queryformat", "%{NAME}\t%{EPOCHNUM}:%{VERSION}", path],
        text=True,
    ).split("\t", 1)
    installed = subprocess.check_output(
        ["rpm", "-q", "--queryformat", "%{EPOCHNUM}:%{VERSION}", name],
        text=True,
    )
    if installed != evr:
        raise SystemExit(f"candidate package version is not installed: {name} {installed} != {evr}")
    pinned[name] = evr

def source_version(evr: str) -> str:
    version = evr.rsplit("-", 1)[0]
    return version if ":" in version else f"0:{version}"

unexpected = []
reported = 0
for line in update_file.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if len(fields) < 2:
        continue
    package_arch, available_evr = fields[0], fields[1]
    name = next((candidate for candidate in pinned if package_arch.startswith(candidate + ".")), None)
    if name is None:
        unexpected.append(line)
        continue
    reported += 1
    if source_version(available_evr) != pinned[name]:
        unexpected.append(line)
    else:
        print(f"same upstream version is pinned for {name}; newer RPM release available: {available_evr}")

if unexpected:
    print("Updates remain outside the candidate's pinned upstream package versions:", file=sys.stderr)
    print("\n".join(unexpected), file=sys.stderr)
    raise SystemExit(1)
if reported == 0:
    raise SystemExit("dnf reported updates but none matched candidate-pinned packages")
PY
elif [[ $check_update_status -ne 0 ]]; then
  cat "$update_output"
  echo "dnf check-update failed with status $check_update_status" >&2
  exit "$check_update_status"
fi
rm -f "$update_output"

dnf clean packages
rm -rf /var/tmp/admiral-candidate-python-rpms
rm -f /var/tmp/python3-pyOpenSSL-25.0.0-1.el10_1.noarch.rpm

# Drop source-instance identity and cloud-init state before flattening the disk.
cloud-init clean --logs --machine-id --seed --configs all
