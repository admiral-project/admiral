#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run the supported worker or dedicated portal bootstrap from an admin node.
set -euo pipefail
[[ $# -eq 10 || $# -eq 11 ]] || {
  echo "usage: $0 ADMIN_SSH_KEY HUB_KNOWN_HOSTS SPOKE_KNOWN_HOSTS HUB_UNDERLAY_IP HUB_WIREGUARD_IP SPOKE_UNDERLAY_IP NODE_ID SPOKE_WIREGUARD_IP HOST_FINGERPRINT OUTPUT_LOG [worker|portal]" >&2
  exit 2
}
admin_key=$1 hub_known_hosts=$2 worker_known_hosts=$3 hub_underlay_ip=$4 hub_wg_ip=$5 worker_ip=$6
node_id=$7 wg_ip=$8 fingerprint=$9 output=${10}
role=${11:-worker}
[[ $role == worker || $role == portal ]] || { echo "unsupported spoke role: $role" >&2; exit 2; }
[[ $node_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || { echo "invalid node id" >&2; exit 2; }
[[ $hub_underlay_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && $hub_wg_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && $worker_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid IPv4 address" >&2; exit 2; }
[[ $wg_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid worker WireGuard address" >&2; exit 2; }
[[ $fingerprint =~ ^SHA256:[A-Za-z0-9+/]+$ ]] || { echo "invalid SSH fingerprint" >&2; exit 2; }
[[ -r $admin_key && -r $hub_known_hosts && -r $worker_known_hosts ]] || {
  echo "admin SSH identity or pinned known-hosts file is unreadable" >&2
  exit 1
}
command -v ssh >/dev/null
command -v ssh-keygen >/dev/null
command -v python3 >/dev/null

umask 077
mkdir -p "$(dirname "$output")"
(set -o noclobber; : >"$output") || {
  echo "refusing to overwrite existing audit log: $output" >&2
  exit 1
}
start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
temp_dir=$(mktemp -d)
chmod 0700 "$temp_dir"
bootstrap_private_key="$temp_dir/${role}-bootstrap.ed25519"
bootstrap_public_key=""
hub_bootstrap_key=""
worker_bootstrap_installed=0
rc=1
candidate_version=${ADMIRAL_RC_VERSION:-0.0.1rc6}
candidate_release=${ADMIRAL_RC_RELEASE:-2}
candidate_epoch=${ADMIRAL_RC_EPOCH:-5}
candidate_dist_tag=${ADMIRAL_RC_DIST_TAG:-el10}
[[ $candidate_version =~ ^0\.0\.1rc[0-9]+$ ]] || { echo 'invalid Admiral RPM version' >&2; exit 2; }
[[ $candidate_release =~ ^[0-9]+$ && $candidate_epoch =~ ^[0-9]{1,4}$ ]] || {
  echo 'invalid Admiral RPM release or epoch' >&2
  exit 2
}
[[ $candidate_dist_tag == el10 || $candidate_dist_tag == fc46 ]] || { echo 'invalid Admiral RPM dist tag' >&2; exit 2; }

ssh_to() {
  local ip=$1 known_hosts=$2
  shift 2
  ssh -i "$admin_key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "validator@$ip" "$@"
}

if [[ -n ${ADMIRAL_LOCAL_REPO_CONFIG:-} ]]; then
  [[ -r $ADMIRAL_LOCAL_REPO_CONFIG ]] || {
    echo "candidate repository configuration is unreadable: $ADMIRAL_LOCAL_REPO_CONFIG" >&2
    exit 1
  }
  repo_dir=${ADMIRAL_LOCAL_REPO_DIR:-}
  if [[ -n $repo_dir ]]; then
    [[ -d $repo_dir && ! -L $repo_dir && -s $repo_dir/repodata/repomd.xml ]] || {
      echo "local candidate RPM repository is incomplete: $repo_dir" >&2
      exit 1
    }
    if find "$repo_dir" -type l -print -quit | grep -q .; then
      echo "refusing symlinks in local candidate RPM repository: $repo_dir" >&2
      exit 1
    fi
    remote_repo_dir=/var/tmp/admiral-audit-local-repo
    ssh_to "$worker_ip" "$worker_known_hosts" sudo install -d -o root -g root -m 0755 "$remote_repo_dir"
    tar -C "$repo_dir" -cf - . | ssh_to "$worker_ip" "$worker_known_hosts" \
      sudo tar --no-same-owner -xf - -C "$remote_repo_dir"
  fi
  remote_repo_tmp=$(ssh_to "$worker_ip" "$worker_known_hosts" 'umask 077; mktemp /tmp/admiral-local.repo.XXXXXX')
  [[ $remote_repo_tmp =~ ^/tmp/admiral-local\.repo\.[[:alnum:]]{6}$ ]] || {
    echo 'spoke returned an unexpected candidate repository staging path' >&2
    exit 1
  }
  scp -i "$admin_key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$worker_known_hosts" \
    "$ADMIRAL_LOCAL_REPO_CONFIG" "validator@$worker_ip:$remote_repo_tmp"
  ssh_to "$worker_ip" "$worker_known_hosts" \
    sudo install -o root -g root -m 0644 "$remote_repo_tmp" /etc/yum.repos.d/admiral-local.repo
  ssh_to "$worker_ip" "$worker_known_hosts" rm -f -- "$remote_repo_tmp"
fi

capture_rpm_manifest() {
  local ip=$1 known_hosts=$2
  ssh_to "$ip" "$known_hosts" \
    "rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\\n' | sort"
}

python_package_baseline() {
  printf '%s\n' "$1" | awk '$1 ~ /^python3-/ { print }' | sort
}

changed_python_baseline() {
  local before=$1 after=$2
  comm -23 \
    <(python_package_baseline "$before") \
    <(python_package_baseline "$after")
}

verify_candidate_rpms() {
  local ip=$1 known_hosts=$2 node_role=$3
  ssh_to "$ip" "$known_hosts" sudo bash -s -- \
    "$candidate_version" "$candidate_release" "$candidate_epoch" "$candidate_dist_tag" "$node_role" <<'REMOTE'
set -euo pipefail
version=$1 release=$2 epoch=$3 dist_tag=$4 role=$5
case "$role" in
  admin) required=(admiral-common admirald admiralctl admiral-flagship) ;;
  worker) required=(admiral-common admiral-fleet) ;;
  portal) required=(admiral-common admiral-harbor) ;;
  *) echo "unsupported node role: $role" >&2; exit 2 ;;
esac
for package in "${required[@]}"; do
  rpm -q "$package" >/dev/null || { echo "required role RPM is missing: $package" >&2; exit 1; }
done
for package in admiral-common admirald admiral-fleet admiralctl admiral-harbor admiral-flagship; do
  if rpm -q "$package" >/dev/null 2>&1; then
    actual=$(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$package")
    [[ $actual == "$epoch:$version-$release.$dist_tag" ]] || {
      echo "$package has unexpected candidate EVR: $actual" >&2
      exit 1
    }
  fi
done
REMOTE
}

remove_worker_bootstrap_key() {
  [[ -n $bootstrap_public_key ]] || return 0
  local public_key_b64
  public_key_b64=$(printf '%s' "$bootstrap_public_key" | base64 -w0)
  ssh_to "$worker_ip" "$worker_known_hosts" \
    "python3 -c 'import base64,os,pathlib,stat,sys,tempfile; p=pathlib.Path.home()/\".ssh\"; a=p/\"authorized_keys\"; key=base64.b64decode(sys.argv[1]).decode(); p.mkdir(mode=0o700,exist_ok=True); os.chmod(p,0o700); s=a.lstat() if a.exists() or a.is_symlink() else None; (s is None or (stat.S_ISREG(s.st_mode) and not stat.S_ISLNK(s.st_mode))) or sys.exit(3); lines=a.read_text().splitlines() if s else []; kept=[line for line in lines if line != key]; fd,tmp=tempfile.mkstemp(prefix=\".authorized_keys.audit-\",dir=p); os.close(fd); pathlib.Path(tmp).write_text(\"\\n\".join(kept)+(\"\\n\" if kept else \"\")); os.chmod(tmp,0o600); os.replace(tmp,a)' '$public_key_b64'" \
    >/dev/null 2>&1
}

cleanup() {
  local saved_rc=$?
  trap - EXIT
  if [[ -n $hub_bootstrap_key ]]; then
    ssh_to "$hub_underlay_ip" "$hub_known_hosts" "rm -f -- '$hub_bootstrap_key'" >/dev/null 2>&1 || {
      echo "warning: could not remove temporary private key from the hub: $hub_bootstrap_key" >&2
      [[ $saved_rc -ne 0 ]] || saved_rc=1
    }
  fi
  if [[ $worker_bootstrap_installed -eq 1 ]]; then
    remove_worker_bootstrap_key || {
      echo "warning: could not remove temporary validator key from worker $worker_ip" >&2
      [[ $saved_rc -ne 0 ]] || saved_rc=1
    }
  fi
  chmod 0600 "$output" 2>/dev/null || true
  rm -rf -- "$temp_dir"
  exit "$saved_rc"
}
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N '' -C "admiral-audit-$role-$node_id" -f "$bootstrap_private_key"
chmod 0600 "$bootstrap_private_key" "$bootstrap_private_key.pub"
bootstrap_public_key=$(<"$bootstrap_private_key.pub")

# Grant only this temporary key to the spoke's existing validator account.
bootstrap_public_key_b64=$(printf '%s' "$bootstrap_public_key" | base64 -w0)
ssh_to "$worker_ip" "$worker_known_hosts" \
  "python3 -c 'import base64,os,pathlib,stat,sys,tempfile; p=pathlib.Path.home()/\".ssh\"; a=p/\"authorized_keys\"; key=base64.b64decode(sys.argv[1]).decode(); p.mkdir(mode=0o700,exist_ok=True); os.chmod(p,0o700); s=a.lstat() if a.exists() or a.is_symlink() else None; (s is None or (stat.S_ISREG(s.st_mode) and not stat.S_ISLNK(s.st_mode))) or sys.exit(3); lines=a.read_text().splitlines() if s else []; (key in lines) or lines.append(key); fd,tmp=tempfile.mkstemp(prefix=\".authorized_keys.audit-\",dir=p); os.close(fd); pathlib.Path(tmp).write_text(\"\\n\".join(lines)+\"\\n\"); os.chmod(tmp,0o600); os.replace(tmp,a)' '$bootstrap_public_key_b64'"
worker_bootstrap_installed=1

hub_bootstrap_key=$(ssh_to "$hub_underlay_ip" "$hub_known_hosts" \
  'umask 077; install -d -m 0700 /home/validator/.ssh; mktemp /home/validator/.ssh/.admiral-bootstrap.XXXXXXXX')
[[ $hub_bootstrap_key =~ ^/home/validator/\.ssh/\.admiral-bootstrap\.[A-Za-z0-9]+$ ]] || {
  echo "hub returned an unexpected temporary key path" >&2
  exit 1
}
ssh_to "$hub_underlay_ip" "$hub_known_hosts" "cat > '$hub_bootstrap_key' && chmod 0600 '$hub_bootstrap_key'" \
  <"$bootstrap_private_key"

hub_rpm_before=$(capture_rpm_manifest "$hub_underlay_ip" "$hub_known_hosts")
worker_rpm_before=$(capture_rpm_manifest "$worker_ip" "$worker_known_hosts")
install_start_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
install_started=$SECONDS
set +e
# The admin endpoint is the hub's reachable underlay address. The installer
# derives the overlay address separately from the configured WireGuard subnet.
ssh_to "$hub_underlay_ip" "$hub_known_hosts" \
  "sudo -n admiral-install --${role}-node --validation-seed --yes --node-id '$node_id' --public-ip '$worker_ip' --wireguard-ip '$wg_ip' --admin-endpoint '$hub_underlay_ip' --ssh-user validator --ssh-key '$hub_bootstrap_key' --ssh-fingerprint '$fingerprint'" \
  >"$output" 2>&1
rc=$?
set -e
install_elapsed=$((SECONDS - install_started))
install_end_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set +e
hub_rpm_after=$(capture_rpm_manifest "$hub_underlay_ip" "$hub_known_hosts")
hub_rpm_status=$?
worker_rpm_after=$(capture_rpm_manifest "$worker_ip" "$worker_known_hosts")
worker_rpm_status=$?
set -e
{
  printf 'candidate=%s-%s epoch=%s dist_tag=%s spoke_role=%s node=%s\n' \
    "$candidate_version" "$candidate_release" "$candidate_epoch" "$candidate_dist_tag" "$role" "$node_id"
  printf 'installer_start_utc=%s installer_end_utc=%s installer_elapsed_seconds=%s ssh_exit_code=%s\n' \
    "$install_start_utc" "$install_end_utc" "$install_elapsed" "$rc"
  printf 'hub_package_nevra_delta_begin (minus=before, plus=after)\n'
  if [[ $hub_rpm_status -eq 0 ]]; then
    diff -u <(printf '%s\n' "$hub_rpm_before") <(printf '%s\n' "$hub_rpm_after") || true
  else
    printf 'hub package inventory unavailable after installer; ssh_exit_code=%s\n' "$hub_rpm_status"
  fi
  printf 'hub_package_nevra_delta_end\n'
  printf 'worker_package_nevra_delta_begin (minus=before, plus=after)\n'
  if [[ $worker_rpm_status -eq 0 ]]; then
    diff -u <(printf '%s\n' "$worker_rpm_before") <(printf '%s\n' "$worker_rpm_after") || true
  else
    printf 'worker package inventory unavailable after installer; ssh_exit_code=%s\n' "$worker_rpm_status"
  fi
  printf 'worker_package_nevra_delta_end\n'
} >>"$output"

if [[ $rc -eq 0 ]]; then
  verify_candidate_rpms "$hub_underlay_ip" "$hub_known_hosts" admin
  verify_candidate_rpms "$worker_ip" "$worker_known_hosts" "$role"
  hub_python_changed=$(changed_python_baseline "$hub_rpm_before" "$hub_rpm_after")
  worker_python_changed=$(changed_python_baseline "$worker_rpm_before" "$worker_rpm_after")
  if [[ -n $hub_python_changed ]]; then
    echo 'pre-existing hub Python RPMs changed during spoke installation' >&2
    printf '%s\n' "$hub_python_changed"
    rc=1
  fi
  if [[ -n $worker_python_changed ]]; then
    echo 'pre-existing spoke Python RPMs changed during installation' >&2
    printf '%s\n' "$worker_python_changed"
    rc=1
  fi
fi

if [[ $rc -eq 0 ]]; then
  if [[ $role == worker ]]; then
    if ! ssh_to "$worker_ip" "$worker_known_hosts" \
      "sudo grep -Fx 'ADMIRAL_API_URL=https://$hub_wg_ip:8080' /etc/admiral/fleet.env" >/dev/null; then
      echo "worker Fleet API URL does not use the expected hub WireGuard overlay $hub_wg_ip" >&2
      rc=1
    elif ! ssh_to "$worker_ip" "$worker_known_hosts" sudo systemctl is-active --quiet admiral-fleet.service; then
      echo 'worker Fleet service is not active' >&2
      rc=1
    elif ssh_to "$worker_ip" "$worker_known_hosts" sudo systemctl is-active --quiet admiral-harbor.service; then
      echo 'worker unexpectedly serves Harbor' >&2
      rc=1
    fi
  else
    if ! ssh_to "$worker_ip" "$worker_known_hosts" \
      "sudo grep -Fx 'ADMIRAL_API_URL=https://$hub_wg_ip:8080' /etc/admiral/harbor.env" >/dev/null; then
      echo "portal Harbor API URL does not use the expected hub WireGuard overlay $hub_wg_ip" >&2
      rc=1
    elif ! ssh_to "$worker_ip" "$worker_known_hosts" sudo systemctl is-active --quiet admiral-harbor.service; then
      echo 'portal Harbor service is not active' >&2
      rc=1
    elif ssh_to "$worker_ip" "$worker_known_hosts" sudo systemctl is-active --quiet admiral-fleet.service; then
      echo 'portal unexpectedly serves worker Fleet' >&2
      rc=1
    fi
  fi
fi

if [[ $rc -eq 0 ]]; then
  health_timeout=${ADMIRAL_SPOKE_HEALTH_TIMEOUT:-300}
  [[ $health_timeout =~ ^[0-9]+$ ]] || { echo 'invalid spoke health timeout' >&2; rc=1; }
  health_deadline=$((SECONDS + health_timeout))
  while [[ $rc -eq 0 ]]; do
    nodes_json=$(ssh_to "$hub_underlay_ip" "$hub_known_hosts" \
      'admiralctl nodes list --output json')
    if node_state=$(printf '%s\n' "$nodes_json" | python3 -c '
import json,sys
nodes=json.load(sys.stdin)
node_id,role=sys.argv[1:]
matches=[node for node in nodes if node.get("id")==node_id]
if len(matches)!=1 or matches[0].get("node_role")!=role:
    raise SystemExit(f"expected one node {node_id!r} with role {role!r}; got {matches!r}")
print("{}\t{}".format(matches[0].get("status", ""), matches[0].get("health_status", "")))
' "$node_id" "$role"); then
      :
    else
      echo "node $node_id is missing or has the wrong role (expected $role)" >&2
      rc=1
      break
    fi
    IFS=$'\t' read -r node_status node_health <<<"$node_state"
    if [[ $node_status == active && $node_health == healthy ]]; then
      printf 'verified_node_id=%s verified_node_role=%s node_status=%s node_health=%s\n' \
        "$node_id" "$role" "$node_status" "$node_health"
      break
    fi
    if (( SECONDS >= health_deadline )); then
      echo "node $node_id did not become active/healthy within ${health_timeout}s (status=$node_status health=$node_health)" >&2
      rc=1
      break
    fi
    sleep 5
  done
fi

if [[ $rc -eq 0 ]]; then
  if ! ssh_to "$worker_ip" "$worker_known_hosts" true >/dev/null 2>&1; then
    echo "cannot verify bootstrap-key revocation: pinned validator access to worker is unavailable" >&2
    rc=1
  elif ssh -i "$bootstrap_private_key" -o IdentitiesOnly=yes -o BatchMode=yes \
      -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$worker_known_hosts" \
      "validator@$worker_ip" true >/dev/null 2>&1; then
    echo "worker installer returned success but the temporary validator credential still works" >&2
    rc=1
  else
    echo "verified temporary bootstrap key is rejected while pinned validator access remains available"
  fi
fi

end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf 'start_utc=%s end_utc=%s ssh_exit_code=%s\n' "$start" "$end" "$rc"
python3 - "$output" <<'PY'
import re,sys
from pathlib import Path
for line in Path(sys.argv[1]).read_text(errors='replace').splitlines():
    if re.search(r'(?i)(secret|password|token|private|credential|fingerprint|signing[_ -]?key)', line):
        continue
    if line.startswith('TASK [') or 'PLAY RECAP' in line or re.search(r'localhost\s+: ok=', line) or 'Admiral installation completed.' in line or '[FATAL]' in line or 'ERROR!' in line:
        print(line[:220])
PY
exit "$rc"
