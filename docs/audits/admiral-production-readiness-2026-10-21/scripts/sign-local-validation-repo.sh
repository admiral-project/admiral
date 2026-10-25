#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Sign a staged, distro-native Admiral candidate repo and enable DNF checks.
set -euo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || {
  echo "usage: $0 RPM_RELEASE" >&2
  exit 2
}
[[ -n ${GNUPGHOME:-} && -d $GNUPGHOME ]] || {
  echo "GNUPGHOME must name the protected validation signing keyring" >&2
  exit 2
}
[[ -n ${ADMIRAL_VALIDATION_GPG_KEY_ID:-} ]] || {
  echo "ADMIRAL_VALIDATION_GPG_KEY_ID must name the lab signing key" >&2
  exit 2
}

release=$1
version=${ADMIRAL_RC_VERSION:-0.0.1rc5}
candidate_id=${ADMIRAL_RC_DIR:-${version#0.0.1}-r${release}}
[[ $version =~ ^0\.0\.1rc[0-9]+$ ]] || { echo "invalid Admiral version: $version" >&2; exit 2; }
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
repo_root=${ADMIRAL_VALIDATION_REPO_ROOT:-/var/lib/libvirt/images/admiral-validation/repo}
candidate_repo="$repo_root/$candidate_id"
validation_dir="$project_root/packaging/build/validation/$candidate_id"
public_key="$candidate_repo/RPM-GPG-KEY-admiral-r${release}"
key_url="http://192.168.122.1/${candidate_id}/RPM-GPG-KEY-admiral-r${release}"

for command in rpm rpmsign rpmkeys gpg createrepo_c chcon; do
  command -v "$command" >/dev/null || { echo "required command not found: $command" >&2; exit 1; }
done
[[ -r $public_key ]] || { echo "public signing key not found: $public_key" >&2; exit 1; }
mkdir -p "$validation_dir"
chmod 0700 "$validation_dir"

sign_distro() {
  local distro=$1 tag=$2 directory="$candidate_repo/$1/x86_64"
  local rpmdb=""
  [[ -d $directory ]] || { echo "candidate repo missing: $directory" >&2; return 1; }
  shopt -s nullglob
  local -a rpms=("$directory"/*.rpm)
  shopt -u nullglob
  [[ ${#rpms[@]} -eq 6 ]] || {
    echo "$distro repo has ${#rpms[@]} RPMs; expected exactly six Admiral RPMs" >&2
    return 1
  }

  local rpm_file nevra
  for rpm_file in "${rpms[@]}"; do
    nevra=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_file")
    [[ $nevra == *".$tag."* ]] || { echo "wrong-distro package in $distro repo: $nevra" >&2; return 1; }
  done

  # Keep the verification RPM database in /tmp: SELinux policy on EL10
  # permits rpm_t to create its transaction lock there.
  rpmdb=$(mktemp -d "/tmp/admiral-r${release}-rpmdb-${distro}.XXXXXX")
  chmod 0700 "$rpmdb"
  chcon -t rpmdb_tmp_t "$rpmdb"
  rpm --dbpath "$rpmdb" --initdb
  rpm --dbpath "$rpmdb" --import "$public_key"
  for rpm_file in "${rpms[@]}"; do
    local signature_status
    signature_status=$(rpmkeys --dbpath "$rpmdb" --checksig --verbose "$rpm_file" 2>&1) || {
      echo "$signature_status" >&2
      rm -rf -- "$rpmdb"
      return 1
    }
    if grep -Eq 'Signature.*: OK' <<<"$signature_status"; then
      continue
    fi
    if grep -Eq 'Signature.*(NOKEY|NOT OK|BAD)' <<<"$signature_status"; then
      echo "RPM has an invalid or untrusted existing signature: $rpm_file" >&2
      echo "$signature_status" >&2
      rm -rf -- "$rpmdb"
      return 1
    fi
    GNUPGHOME="$GNUPGHOME" rpmsign --define "_gpg_name $ADMIRAL_VALIDATION_GPG_KEY_ID" --addsign "$rpm_file"
    signature_status=$(rpmkeys --dbpath "$rpmdb" --checksig --verbose "$rpm_file" 2>&1) || {
      echo "$signature_status" >&2
      rm -rf -- "$rpmdb"
      return 1
    }
    grep -Eq 'Signature.*: OK' <<<"$signature_status" || {
      echo "RPM signing verification failed: $rpm_file" >&2
      echo "$signature_status" >&2
      rm -rf -- "$rpmdb"
      return 1
    }
  done
  rm -rf -- "$rpmdb"

  createrepo_c --update --checksum sha256 "$directory" >/dev/null
  local repomd="$directory/repodata/repomd.xml"
  GNUPGHOME="$GNUPGHOME" gpg --batch --yes --armor --detach-sign \
    --local-user "$ADMIRAL_VALIDATION_GPG_KEY_ID" \
    --output "$repomd.asc" "$repomd"
  GNUPGHOME="$GNUPGHOME" gpg --batch --verify "$repomd.asc" "$repomd"

  (
    cd -- "$directory"
    sha256sum ./*.rpm > SHA256SUMS
    printf 'name\tepoch\tversion\trelease\tarch\tsha256\tfile\n' > RPM-MANIFEST.tsv
    for rpm_file in ./*.rpm; do
      rpm -qp --qf '%{NAME}\t%{EPOCH}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' "$rpm_file" |
        while IFS=$'\t' read -r name epoch version rpm_release arch; do
          hash=$(sha256sum "$rpm_file" | awk '{print $1}')
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$epoch" "$version" "$rpm_release" "$arch" "$hash" "${rpm_file#./}" >> RPM-MANIFEST.tsv
        done
    done
  )
  (
    cd -- "$directory"
    sha256sum -c SHA256SUMS
  )
  printf '[%s] signed %s RPMs and repomd.xml with key %s\n' \
    "$distro" "${#rpms[@]}" "$ADMIRAL_VALIDATION_GPG_KEY_ID"
}

sign_distro el10 el10
sign_distro fedora fc46

cat > "$validation_dir/admiral-local-el10.repo" <<EOF
[admiral-local]
name=Admiral ${version} Release ${release} signed local validation (EL10)
baseurl=http://192.168.122.1/${candidate_id}/el10/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${key_url}
priority=1
skip_if_unavailable=0
EOF

cat > "$validation_dir/admiral-local-fedora.repo" <<EOF
[admiral-local]
name=Admiral ${version} Release ${release} signed local validation (Fedora Rawhide)
baseurl=http://192.168.122.1/${candidate_id}/fedora/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${key_url}
priority=1
skip_if_unavailable=0
EOF
chmod 0644 "$validation_dir"/admiral-local-*.repo
echo "Signed candidate repositories and DNF configs are ready at $candidate_repo"
