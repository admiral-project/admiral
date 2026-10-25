#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Finalize the disposable Release 75 Fedora Multi-Node cell.
set -euo pipefail

[[ $# -eq 8 ]] || {
  echo "usage: $0 SSH_KEY HUB_KNOWN W1_KNOWN W2_KNOWN HUB_IP W1_IP W2_IP OUTPUT_DIR" >&2
  exit 2
}
ssh_key=$1 hub_known=$2 w1_known=$3 w2_known=$4
hub_ip=$5 w1_ip=$6 w2_ip=$7 output_dir=$8
[[ $output_dir == /* && ! -e $output_dir ]] || {
  echo 'output directory must be an unused absolute path' >&2; exit 2;
}
for input in "$ssh_key" "$hub_known" "$w1_known" "$w2_known"; do
  [[ -r $input ]] || { echo "unreadable SSH input: $input" >&2; exit 1; }
done

umask 077
mkdir -m 0700 -- "$output_dir"
ssh_base=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5)
hub_args=("${ssh_base[@]}" -o "UserKnownHostsFile=$hub_known")
w1_args=("${ssh_base[@]}" -o "UserKnownHostsFile=$w1_known")
w2_args=("${ssh_base[@]}" -o "UserKnownHostsFile=$w2_known")

ssh "${hub_args[@]}" "validator@$hub_ip" sudo bash -s >"$output_dir/hub.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
printf 'os='; . /etc/os-release; printf '%s %s\n' "$ID" "$VERSION_ID"
printf 'arch='; uname -m
printf 'failed_units='; failed=$(systemctl --failed --no-legend --plain); printf '%s\n' "${failed:-none}"; [[ -z $failed ]]
systemctl is-active admirald postgresql wg-quick@wg-admiral
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor | sort
sudo -u validator env HOME=/home/validator admiralctl nodes list --output json
wg show wg-admiral allowed-ips
REMOTE

for role in w1 w2; do
  if [[ $role == w1 ]]; then ip=$w1_ip; known_args=("${w1_args[@]}"); else ip=$w2_ip; known_args=("${w2_args[@]}"); fi
  ssh "${known_args[@]}" "validator@$ip" sudo bash -s >"$output_dir/$role.txt" <<'REMOTE'
set -euo pipefail
cd /tmp
printf 'os='; . /etc/os-release; printf '%s %s\n' "$ID" "$VERSION_ID"
printf 'arch='; uname -m
printf 'failed_units='; failed=$(systemctl --failed --no-legend --plain); printf '%s\n' "${failed:-none}"; [[ -z $failed ]]
systemctl is-active admiral-fleet firewalld wg-quick@wg-admiral
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' admiral-common admiral-fleet | sort
uid=$(id -u admiral-apps); app_home=$(getent passwd admiral-apps | cut -d: -f6)
app_env=(env HOME="$app_home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
failed_user=$(runuser -u admiral-apps -- "${app_env[@]}" systemctl --user --failed --no-legend --plain)
printf 'failed_user_units=%s\n' "${failed_user:-none}"
[[ -z $failed_user ]]
containers=$(runuser -u admiral-apps -- "${app_env[@]}" podman ps -a --format '{{.Names}}')
pods=$(runuser -u admiral-apps -- "${app_env[@]}" podman pod ps --format '{{.Name}}')
volumes=$(runuser -u admiral-apps -- "${app_env[@]}" podman volume ls --format '{{.Name}}')
printf 'containers=%s\npods=%s\nvolumes=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}"
[[ -z $containers && -z $pods && -z $volumes ]]
REMOTE
done

python3 - "$output_dir/hub.txt" "$output_dir/w1.txt" "$output_dir/w2.txt" <<'PY'
import json, pathlib, re, sys
hub, w1, w2 = (pathlib.Path(p).read_text() for p in sys.argv[1:])
for name, text in (("hub", hub), ("w1", w1), ("w2", w2)):
    if "fedora 46" not in text or "arch=x86_64" not in text:
        raise SystemExit(f"{name}: unexpected OS or architecture")
    expected_names = (
        {"admiral-common", "admirald", "admiral-fleet", "admiralctl", "admiral-flagship", "admiral-harbor"}
        if name == "hub" else {"admiral-common", "admiral-fleet"}
    )
    rpms = re.findall(r"^([^\s]+)-0\.0\.1rc5-75\.fc46\.", text, re.M)
    if set(rpms) != expected_names:
        raise SystemExit(f"{name}: expected RPM names {sorted(expected_names)}, found {sorted(rpms)}")
    expected = len(expected_names)
    if len(rpms) != expected:
        raise SystemExit(f"{name}: expected {expected} exact R75 RPMs, found {len(rpms)}")
nodes_match = re.search(r"(?ms)^\[\n.*?^\]$", hub)
if not nodes_match:
    raise SystemExit("hub node inventory JSON missing")
nodes = json.loads(nodes_match.group(0))
ids = {node.get("id") for node in nodes}
if ids != {"adm-r75-fedora-mn-hub-portal", "adm-r75-fedora-mn-w1"}:
    raise SystemExit(f"unexpected final node inventory: {sorted(ids)}")
wg = hub.split("wg-admiral allowed-ips\n", 1)[-1]
if not re.search(r"\b10\.99\.0\.2/32\b", wg) or re.search(r"\b10\.99\.0\.3/32\b", wg):
    raise SystemExit("hub WireGuard peer set does not match the removed W2")
PY

printf 'result=PASS\nfinished_utc=%s\n' "$(date -u +%FT%TZ)" >"$output_dir/result.txt"
(cd "$output_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)
chmod 0600 "$output_dir"/*
echo "fedora_multinode_postrun=PASS evidence=$output_dir"
