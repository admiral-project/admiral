#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build a clean, fully updated OS seed with the runtime requirements of the
# selected Admiral release. This script never installs Admiral RPMs or enables
# Admiral services; it selects the Fedora or EL10 repository family explicitly.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: create_seed_os.sh {fedora|rocky|alma|centos} VM_NAME NAT_IP NAT_MAC BASE_IMAGE OUTPUT_SEED VALIDATOR_PUBKEY [RELEASE]

Required environment:
  ADMIRAL_AUDIT_SSH_PRIVATE_KEY  SSH private key matching VALIDATOR_PUBKEY

Optional environment:
  ADMIRAL_AUDIT_ROOT             libvirt audit directory
                                 (default: /var/lib/libvirt/images/admiral-validation)
  ADMIRAL_PROJECT_ROOT           Admiral checkout (auto-detected by default)
EOF
  exit 2
}

[[ $# -eq 7 || $# -eq 8 ]] || usage
os=$1
name=$2
nat_ip=$3
nat_mac=$4
base_image=$5
output_seed=$6
validator_pubkey=$7
release=${8:-73}
[[ $EUID -eq 0 ]] || { echo 'run as root' >&2; exit 1; }
[[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || { echo 'invalid VM name' >&2; exit 2; }
[[ $release =~ ^[0-9]+$ ]] || { echo 'invalid Admiral release number' >&2; exit 2; }
[[ $nat_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'invalid NAT IPv4 address' >&2; exit 2; }
[[ $nat_mac =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { echo 'invalid NAT MAC address' >&2; exit 2; }
[[ -r $base_image && ! -L $base_image ]] || { echo "base image is missing or a symlink: $base_image" >&2; exit 1; }
[[ -r $validator_pubkey && ! -L $validator_pubkey ]] || { echo "validator public key is missing or a symlink: $validator_pubkey" >&2; exit 1; }
ssh_private_key=${ADMIRAL_AUDIT_SSH_PRIVATE_KEY:-}
[[ -n $ssh_private_key && -r $ssh_private_key && ! -L $ssh_private_key ]] || {
  echo 'set ADMIRAL_AUDIT_SSH_PRIVATE_KEY to the validator private key' >&2
  exit 2
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_root=${ADMIRAL_PROJECT_ROOT:-$(git -C "$script_dir/../../../.." rev-parse --show-toplevel)}
audit_root=${ADMIRAL_AUDIT_ROOT:-/var/lib/libvirt/images/admiral-validation}
vm_creator="$script_dir/create-audit-vm.sh"
guest_preparer="$script_dir/prepare-audit-seed-guest.sh"
validation_dir="$project_root/packaging/build/validation/rc5-r${release}"

case "$os" in
  fedora)
    family=fedora
    repo_file="$validation_dir/admiral-local-fedora.repo"
    rpm_build="$validation_dir/fedora/RPMS"
    expected_os_id=fedora
    required_repos=(rawhide copr:copr.fedorainfracloud.org:admiral-project:admiral)
    forbidden_suffix=el10
    expected_suffix=fc46
    ;;
  rocky)
    family=el10
    repo_file="$validation_dir/admiral-local-el10.repo"
    rpm_build="$validation_dir/el10/RPMS"
    expected_os_id=rocky
    required_repos=(baseos appstream crb epel copr:copr.fedorainfracloud.org:admiral-project:admiral)
    forbidden_suffix=fc46
    expected_suffix=el10
    ;;
  alma)
    family=el10
    repo_file="$validation_dir/admiral-local-el10.repo"
    rpm_build="$validation_dir/el10/RPMS"
    expected_os_id=almalinux
    required_repos=(baseos appstream crb epel copr:copr.fedorainfracloud.org:admiral-project:admiral)
    forbidden_suffix=fc46
    expected_suffix=el10
    ;;
  centos)
    family=el10
    repo_file="$validation_dir/admiral-local-el10.repo"
    rpm_build="$validation_dir/el10/RPMS"
    expected_os_id=centos
    required_repos=(baseos appstream crb epel copr:copr.fedorainfracloud.org:admiral-project:admiral)
    forbidden_suffix=fc46
    expected_suffix=el10
    ;;
  *) usage ;;
esac

[[ -r $repo_file && ! -L $repo_file ]] || { echo "missing candidate repository configuration: $repo_file" >&2; exit 1; }
[[ -d $rpm_build && ! -L $rpm_build ]] || { echo "missing $family RPM build directory: $rpm_build" >&2; exit 1; }
[[ -x $vm_creator && -r $guest_preparer ]] || { echo 'audit VM preparation helpers are missing' >&2; exit 1; }
grep -Eq '^[[:space:]]*gpgcheck[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$repo_file" || {
  echo "candidate repository must enforce package signature checks: $repo_file" >&2
  exit 1
}
grep -Eq '^[[:space:]]*repo_gpgcheck[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$repo_file" || {
  echo "candidate repository must enforce metadata signature checks: $repo_file" >&2
  exit 1
}

mapfile -t candidate_rpms < <(find "$rpm_build" -type f -name '*.rpm' -print | sort)
admiral_rpms=()
for rpm_file in "${candidate_rpms[@]}"; do
  rpm_name=$(rpm -qp --qf '%{NAME}' "$rpm_file")
  case "$rpm_name" in
    admiral-common|admirald|admiral-fleet|admiralctl|admiral-flagship|admiral-harbor)
      admiral_rpms+=("$rpm_file")
      ;;
  esac
done
[[ ${#admiral_rpms[@]} -eq 6 ]] || {
  echo "expected six Admiral $family RPMs in $rpm_build; found ${#admiral_rpms[@]}" >&2
  exit 1
}
for rpm_file in "${candidate_rpms[@]}"; do
  rpm_release=$(rpm -qp --qf '%{RELEASE}' "$rpm_file")
  [[ $rpm_release == *."$expected_suffix" ]] || {
    echo "wrong or cross-platform RPM refused: $rpm_file has release $rpm_release; expected .$expected_suffix" >&2
    exit 1
  }
done

mkdir -p "$audit_root/seeds" "$audit_root/overlays" "$audit_root/cloud-init"
audit_root=$(realpath -e -- "$audit_root")
base_image=$(realpath -e -- "$base_image")
output_seed=$(realpath -m -- "$output_seed")
case "$output_seed" in
  "$audit_root"/seeds/*) ;;
  *) echo "output seed must be inside $audit_root/seeds" >&2; exit 2 ;;
esac
[[ $output_seed != "$base_image" ]] || { echo 'output seed must differ from base image' >&2; exit 2; }
[[ ! -e $output_seed && ! -L $output_seed ]] || { echo "output seed already exists: $output_seed" >&2; exit 1; }

evidence_dir="$validation_dir/runtime/seed-refresh-$(date -u +%Y%m%d)/$os"
mkdir -p "$evidence_dir"
host_log="$evidence_dir/create-seed.log"
exec 9>&1
exec > >(tee -a "$host_log") 2>&1
host_log_tee_pid=$!

printf 'os=%s family=%s release=%s\n' "$os" "$family" "$release"
printf 'vm=%s nat=%s mac=%s\n' "$name" "$nat_ip" "$nat_mac"
printf 'base_image=%s\n' "$base_image"
printf 'base_image_sha256='; sha256sum "$base_image"
printf 'output_seed=%s\n' "$output_seed"
printf 'candidate_rpm_suffix=.%s\n' "$expected_suffix"
printf 'candidate_rpm_nevras:\n'
for rpm_file in "${admiral_rpms[@]}"; do rpm -qp --qf '%{NEVRA}\n' "$rpm_file"; done

export ADMIRAL_AUDIT_BASE_OVERRIDE="$base_image"
bash "$vm_creator" "$os" "$name" "$nat_ip" "$nat_mac" "$validator_pubkey"

known_hosts="$audit_root/cloud-init/$name/known_hosts"
target="validator@$nat_ip"
ssh_args=(-i "$ssh_private_key" -o IdentitiesOnly=yes -o BatchMode=yes
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5)
for attempt in $(seq 1 60); do
  if ssh "${ssh_args[@]}" "$target" true >/dev/null 2>&1; then break; fi
  if [[ $attempt -eq 60 ]]; then
    echo "SSH did not become available in VM $name; leaving VM and its files for diagnosis" >&2
    exit 1
  fi
  sleep 3
done

remote_tmp=$(ssh "${ssh_args[@]}" "$target" 'mktemp -d /tmp/admiral-seed-create.XXXXXX')
[[ $remote_tmp =~ ^/tmp/admiral-seed-create\.[[:alnum:]]{6}$ ]] || {
  echo "unexpected remote temporary directory: $remote_tmp" >&2
  exit 1
}
scp -i "$ssh_private_key" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
  "$guest_preparer" "$repo_file" "$target:$remote_tmp/"

set +e
ssh "${ssh_args[@]}" "$target" 'sudo bash -s' <<REMOTE
set +e
install -o root -g root -m 0755 '$remote_tmp/prepare-audit-seed-guest.sh' /var/tmp/prepare-audit-seed-guest.sh
ADMIRAL_AUDIT_REMOVE_LOCAL_REPO=1 ADMIRAL_AUDIT_LOCAL_REPO_FILE='$remote_tmp/admiral-local-$family.repo' bash '$remote_tmp/prepare-audit-seed-guest.sh' > /var/tmp/admiral-seed-prep.log 2>&1
rc=\$?
tail -100 /var/tmp/admiral-seed-prep.log
exit \$rc
REMOTE
prepare_rc=$?
set -e

scp -i "$ssh_private_key" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
  "$target:/var/tmp/admiral-seed-prep.log" "$evidence_dir/admiral-seed-prep.log" || true
(( prepare_rc == 0 )) || {
  echo "seed package/update preparation failed (status $prepare_rc); leaving VM for diagnosis" >&2
  exit "$prepare_rc"
}

required_repos_env=$(printf '%s ' "${required_repos[@]}")
set +e
ssh "${ssh_args[@]}" "$target" \
  "sudo env EXPECTED_OS_ID='$expected_os_id' FORBIDDEN_SUFFIX='$forbidden_suffix' REQUIRED_REPOS='$required_repos_env' bash -s" <<'REMOTE'
set -uo pipefail
out=/var/tmp/admiral-seed-verification.txt
verify_status=0
{
  date -u +"checked=%Y-%m-%dT%H:%M:%SZ"
  . /etc/os-release
  printf 'os=%s version=%s arch=%s\n' "$ID" "$VERSION_ID" "$(uname -m)"
  [[ $ID == "$EXPECTED_OS_ID" ]] || { echo "unexpected OS ID: $ID"; verify_status=1; }
  [[ $(uname -m) == x86_64 ]] || { echo 'seed architecture is not x86_64'; verify_status=1; }
  printf '\nEnabled repos:\n'
  dnf repolist --enabled
  enabled_repo_ids=$(dnf repolist --enabled | awk 'NR > 1 {print $1}')
  for required_repo in $REQUIRED_REPOS; do
    if ! grep -Fqx "$required_repo" <<<"$enabled_repo_ids"; then
      echo "required repository is not enabled: $required_repo"
      verify_status=1
    fi
  done
  if [[ -e /etc/yum.repos.d/admiral-local.repo ]]; then
    echo 'local candidate repo must be configured manually in each test lab, not baked into this seed'
    verify_status=1
  fi
  printf '\nRequired runtime package inventory:\n'
  if [[ $ID == fedora ]]; then
    auto_update_package=dnf5-plugin-automatic
    dnf_plugin_package=dnf5-plugins
  else
    auto_update_package=dnf-automatic
    dnf_plugin_package=dnf-plugins-core
  fi
  for package in acl ansible-collection-ansible-posix ansible-core audit audit-rules caddy certbot chrony cockpit-bridge curl "$dnf_plugin_package" fail2ban fail2ban-firewalld firewalld gnupg2 openssh-clients openssh-server openssl policycoreutils-python-utils podman postgresql postgresql-server python3 python3-argon2-cffi python3-cryptography python3-flask python3-flask-alembic python3-flask-login python3-flask-sqlalchemy python3-gunicorn python3-mistune python3-psycopg2 python3-sqlalchemy python3-pyyaml python3-requests python3-werkzeug shadow-utils systemd systemd-container wireguard-tools python3-alembic python3-typing-extensions "$auto_update_package"; do
    rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$package" || verify_status=1
  done
  if [[ $ID == rocky || $ID == almalinux ]]; then
    rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' python3-pyOpenSSL || verify_status=1
  fi
  printf '\nAdmiral RPMs (must be absent):\n'
  if rpm -qa --qf '%{NAME}\n' | grep -E '^admiral(-|$)'; then verify_status=1; fi
  printf '\nCross-family RPMs (must be absent):\n'
  if rpm -qa --qf '%{NEVRA}\n' | grep -E "\\.$FORBIDDEN_SUFFIX([_.]|$)"; then verify_status=1; fi
  printf '\nService states (this script issues no enable/start commands):\n'
  for unit in caddy.service postgresql.service podman.socket firewalld.service sshd.service admirald.service admiral-fleet.service admiral-harbor.service admiral-flagship.service; do
    printf '%s enabled=' "$unit"; systemctl is-enabled "$unit" 2>&1 || true
    printf '%s active=' "$unit"; systemctl is-active "$unit" 2>&1 || true
  done
  set +e
  dnf -q check-update
  check_update_status=$?
  set -e
  printf 'check_update_exit=%s\n' "$check_update_status"
  [[ $check_update_status -eq 0 ]] || verify_status=1
} > "$out" 2>&1
cat "$out"
exit "$verify_status"
REMOTE
verify_rc=$?
set -e
scp -i "$ssh_private_key" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
  "$target:/var/tmp/admiral-seed-verification.txt" "$evidence_dir/verification.txt" || true
(( verify_rc == 0 )) || { echo "seed verification failed (status $verify_rc); leaving VM for diagnosis" >&2; exit "$verify_rc"; }
set +e
ssh "${ssh_args[@]}" "$target" 'sudo bash -s' <<REMOTE
set -e
cloud-init clean --logs --machine-id
find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*' -delete
python3 - '$remote_tmp' <<'PY'
from pathlib import Path
import shutil
import sys

path = Path(sys.argv[1])
if path.parent != Path('/tmp') or not path.name.startswith('admiral-seed-create.'):
    raise SystemExit(f'refusing to remove unexpected staging directory: {path}')
shutil.rmtree(path)
PY
python3 - <<'PY'
from pathlib import Path

for name in ('prepare-audit-seed-guest.sh', 'admiral-seed-prep.log', 'admiral-seed-verification.txt'):
    Path('/var/tmp', name).unlink(missing_ok=True)
PY
sync
systemctl poweroff
REMOTE
poweroff_ssh_rc=$?
set -e
printf 'guest_poweroff_ssh_exit_code=%s\n' "$poweroff_ssh_rc"

for attempt in $(seq 1 60); do
  state=$(virsh domstate "$name" 2>/dev/null | tr -d '\r' || true)
  [[ $state == 'shut off' ]] && break
  sleep 2
done
[[ ${state:-unknown} == 'shut off' ]] || {
  echo "VM $name did not shut down; leaving files for diagnosis" >&2
  exit 1
}

overlay="$audit_root/overlays/$name.qcow2"
[[ -f $overlay && ! -L $overlay ]] || { echo "VM overlay missing: $overlay" >&2; exit 1; }
qemu-img check "$overlay"
qemu-img convert -p -f qcow2 -O qcow2 "$overlay" "$output_seed"
chown qemu:qemu "$output_seed"
chmod 0640 "$output_seed"
restorecon -F "$output_seed"
qemu-img check "$output_seed"
printf 'seed_sha256='; sha256sum "$output_seed"
printf 'seed_qemu_info:\n'; qemu-img info "$output_seed"

cat > "$evidence_dir/seed-metadata.txt" <<EOF
os=$os
release=$release
family=$family
base_image=$base_image
output_seed=$output_seed
candidate_rpm_suffix=.$expected_suffix
final_dnf_check_update=0
runtime_requires_installed=yes
local_repo_config_baked=no
local_repo_setup=manual-per-validation-lab
admiral_rpms_installed=no
cross_family_rpms_installed=no
service_enable_commands_issued=no
EOF
printf 'seed_file_sha256=' >> "$evidence_dir/seed-metadata.txt"
sha256sum "$output_seed" >> "$evidence_dir/seed-metadata.txt"
printf 'seed_info:\n' >> "$evidence_dir/seed-metadata.txt"
qemu-img info "$output_seed" >> "$evidence_dir/seed-metadata.txt"

# Remove only successful temporary builder artifacts. Failed runs intentionally
# retain their VM, overlay and cloud-init files for root-cause investigation.
virsh undefine "$name"
virsh net-update default delete ip-dhcp-host \
  "<host mac='$nat_mac' name='$name' ip='$nat_ip'/>" --live --config >/dev/null
python3 - "$audit_root" "$name" <<'PY'
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]).resolve(strict=True)
name = sys.argv[2]
overlay = (root / "overlays" / f"{name}.qcow2").resolve(strict=False)
iso = (root / "cloud-init" / f"{name}.iso").resolve(strict=False)
cloud_dir = root / "cloud-init" / name
for path in (overlay, iso):
    if path.parent != root / ("overlays" if path == overlay else "cloud-init"):
        raise SystemExit(f"refusing cleanup outside audit root: {path}")
    if path.is_symlink():
        raise SystemExit(f"refusing to remove symlink: {path}")
    path.unlink(missing_ok=True)
if cloud_dir.is_symlink() or cloud_dir.resolve(strict=False).parent != root / "cloud-init":
    raise SystemExit(f"refusing to remove unsafe cloud-init directory: {cloud_dir}")
shutil.rmtree(cloud_dir, ignore_errors=False)
PY

printf 'Seed complete: %s\n' "$output_seed"
printf 'Evidence: %s\n' "$evidence_dir"
printf 'evidence_manifest=SHA256SUMS\n'

# Stop writing the tee log before hashing it. Exclude the output manifest so
# its checksum list is verifiable instead of hashing the empty redirected file.
exec 1>&9 2>&1
exec 9>&-
wait "$host_log_tee_pid"
(
  cd "$evidence_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum
) > "$evidence_dir/SHA256SUMS"
chmod 0600 "$evidence_dir/SHA256SUMS"
(
  cd "$evidence_dir"
  sha256sum -c SHA256SUMS --quiet
)
printf 'seed_evidence_manifest_sha256='
sha256sum "$evidence_dir/SHA256SUMS"
