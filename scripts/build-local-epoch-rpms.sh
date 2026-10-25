#!/usr/bin/env bash
# Build an isolated, local-only RC6 RPM set with a temporary Epoch.
# Never publish these artifacts: final coordinated no-Epoch RC6 packages are rebuilt from the
# unmodified RPM specs after all fixes and evidence are complete.
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
epoch=${1:?usage: $0 EPOCH}
[[ $epoch =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Epoch must be an integer from 1 to 9999' >&2; exit 2; }
[[ $(rpm --eval '%{_target_cpu}') == x86_64 ]] || { echo 'run this helper on a native x86_64 EL10/Fedora builder' >&2; exit 2; }
source /etc/os-release
case "$ID:${VERSION_ID%%.*}" in
  rocky:10) dist_tag=el10 ;;
  fedora:46)
    dnf repolist --enabled -q | grep -i rawhide >/dev/null || {
      echo 'Fedora 46 builder does not have a Rawhide repository enabled' >&2
      exit 2
    }
    dist_tag=fc46
    ;;
  *) echo "unsupported native build host: $PRETTY_NAME" >&2; exit 2 ;;
esac

build_root="$root_dir/packaging/build/local-epoch${epoch}-rc6-${dist_tag}-x86_64"
[[ ! -e $build_root ]] || { echo "refusing to overwrite existing evidence: $build_root" >&2; exit 1; }
spec_dir="$build_root/specs"
top_dir="$build_root/rpmbuild"
repo_dir="$build_root/repo"
mkdir -p "$spec_dir" "$repo_dir" "$build_root/logs"
cp "$root_dir"/packaging/rpm/*.spec "$root_dir/packaging/rpm/admiral-common.sysusers" "$spec_dir/"

python3 - "$spec_dir" "$epoch" <<'PY'
from pathlib import Path
import re
import sys

spec_dir, epoch = Path(sys.argv[1]), sys.argv[2]
packages = (
    "admiral-common",
    "admirald",
    "admiral-fleet",
    "admiralctl",
    "admiral-flagship",
    "admiral-harbor",
)
for package in packages:
    path = spec_dir / f"{package}.spec"
    text = path.read_text(encoding="utf-8")
    if re.search(r"^Epoch:", text, re.MULTILINE):
        raise SystemExit(f"{path.name}: refusing to replace an existing Epoch")
    text, count = re.subn(
        r"^(Name:\s+[^\n]+\n)",
        lambda match: match.group(1) + f"Epoch: {epoch}\n",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"{path.name}: expected exactly one Name header")
    path.write_text(text, encoding="utf-8")
PY

make -C "$root_dir" rpm-admiral \
  RPMDIR="$top_dir" SPECSDIR="$spec_dir" RPM_ARCH=x86_64 \
  2>&1 | tee "$build_root/logs/rpmbuild.log"

packages=(admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor)
for package in "${packages[@]}"; do
  mapfile -t matches < <(find "$top_dir/RPMS" -type f -name "$package-*.rpm" -print)
  [[ ${#matches[@]} -eq 1 ]] || { echo "$package: expected one RPM, found ${#matches[@]}" >&2; exit 1; }
  rpm -qp --qf '%{EPOCHNUM}\n' "${matches[0]}" | grep -Fx "$epoch" >/dev/null
  cp -p "${matches[0]}" "$repo_dir/"
done

package_release=''
for package in "${packages[@]}"; do
  rpm_file=$(find "$repo_dir" -maxdepth 1 -type f -name "$package-*.rpm" -print -quit)
  version_release=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$rpm_file")
  [[ $version_release == 0.0.1rc6-*."$dist_tag" ]] || {
    echo "$package: unexpected candidate EVR $version_release" >&2
    exit 1
  }
  current_release=${version_release#0.0.1rc6-}
  current_release=${current_release%.$dist_tag}
  if [[ -n $package_release && $package_release != "$current_release" ]]; then
    echo "Admiral RPM Release values differ: $package_release and $current_release ($package)" >&2
    exit 1
  fi
  package_release=$current_release
done

{
  printf 'purpose=local-only-epoch-test; not publishable\n'
  printf 'epoch=%s\nversion=0.0.1rc6\nrelease=%s\n' "$epoch" "$package_release"
  printf 'host=%s\ndist_tag=%s\n' "$PRETTY_NAME" "$dist_tag"
  printf 'root_commit=%s\n' "$(git -C "$root_dir" rev-parse HEAD)"
  for component in admirald admiral-fleet admiralctl admiral-flagship admiral-harbor; do
    printf '%s=%s\n' "$component" "$(git -C "$root_dir/$component" rev-parse HEAD)"
  done
} > "$build_root/source-pins.txt"

createrepo_c "$repo_dir" > "$build_root/logs/createrepo.log"
(
  cd "$repo_dir"
  printf 'name\tepoch\tversion\trelease\tarch\tsha256\tfile\n' > RPM-MANIFEST.tsv
  for package in ./*.rpm; do
    rpm -qp --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t' "$package"
    sha256sum -- "$package" | awk '{printf "%s\t%s\n", $1, substr($2, 3)}'
  done >> RPM-MANIFEST.tsv
  sha256sum ./*.rpm > SHA256SUMS
)
printf 'result=PASS\nrepo=%s\nmanifest=%s/RPM-MANIFEST.tsv\n' "$repo_dir" "$repo_dir"
