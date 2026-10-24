#!/usr/bin/env bash
# Release 75 secure Single-Node post-install validation. Run as root.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'usage: single-node-postcheck.sh EXPECTED_OS_ID RPM_SUFFIX' >&2; exit 2; }
expected_os=$1 rpm_suffix=$2
cd /
source /etc/os-release
printf 'guest=%s os=%s version=%s arch=%s boot_id=%s\n' \
  "$(hostname -s)" "$ID" "$VERSION_ID" "$(uname -m)" "$(cat /proc/sys/kernel/random/boot_id)"
[[ $ID == "$expected_os" && $(uname -m) == x86_64 ]]
[[ $(getenforce) == Enforcing ]]
printf 'selinux=%s\n' "$(getenforce)"
packages=(admiral-common admirald admiral-fleet admiralctl admiral-harbor admiral-flagship)
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "${packages[@]}" | sort
for package in "${packages[@]}"; do
  rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$package" | grep -qx "0.0.1rc5-75.${rpm_suffix}"
done
verify_output=$(mktemp)
trap 'rm -f -- "$verify_output"' EXIT
set +e
rpm -V "${packages[@]}" >"$verify_output" 2>&1
verify_rc=$?
set -e
printf 'rpm_verify_exit=%s (Ansible-rendered files are expected to differ)\n' "$verify_rc"
cat "$verify_output"
python3 - "$verify_output" <<'PY'
import pathlib,sys
expected={'/etc/admirald.ini','/etc/admiral/fleet.env','/etc/admiral/harbor.env','/etc/admiral/flagship.env'}
lines=[x.strip() for x in pathlib.Path(sys.argv[1]).read_text().splitlines() if x.strip()]
seen=set()
for line in lines:
    path=line.split()[-1]
    if path not in expected or path in seen:
        raise SystemExit(f'unexpected RPM verification discrepancy: {line}')
    seen.add(path)
if seen!=expected:
    raise SystemExit(f'expected setup-rendered differences {sorted(expected)}, observed {sorted(seen)}')
print('rpm_verify_scope=PASS')
PY
failed=$(systemctl --failed --no-legend --no-pager)
printf 'failed_units=%s\n' "${failed:-none}"
[[ -z $failed ]]
for service in postgresql admirald admiral-fleet caddy admiral-harbor admiral-flagship; do
  state=$(systemctl is-active "$service")
  printf 'service=%s state=%s\n' "$service" "$state"
  [[ $state == active ]]
done
for endpoint in https://127.0.0.1:5001/ready https://127.0.0.1:5000/flagship/api/health; do
  code=$(curl --insecure --connect-timeout 3 --max-time 10 --silent --show-error -o /dev/null -w '%{http_code}' "$endpoint")
  printf 'local_health_endpoint=%s http=%s\n' "$endpoint" "$code"
  [[ $code == 200 ]]
done
admiralctl status
nodes_file=$(mktemp)
trap 'rm -f -- "$verify_output" "$nodes_file"' EXIT
admiralctl nodes list --output json >"$nodes_file"
python3 - "$nodes_file" <<'PY'
import json,sys
nodes=json.load(open(sys.argv[1],encoding='utf-8'))
workers=[x for x in nodes if x.get('node_role')=='worker']
portals=[x for x in nodes if x.get('node_role')=='portal']
for n in nodes:
    print('node={id} role={role} status={status} health={health} available={available}'.format(
        id=n.get('id'),role=n.get('node_role'),status=n.get('status'),
        health=n.get('health_status'),available=n.get('available_for_provisioning')))
if len(workers)!=1 or len(portals)!=1:
    raise SystemExit(f'expected one worker and portal registration; got {len(workers)} and {len(portals)}')
for n in workers+portals:
    if n.get('status')!='active' or n.get('health_status')!='healthy':
        raise SystemExit(f'node is not active and healthy: {n.get("id")}')
if not workers[0].get('available_for_provisioning'):
    raise SystemExit('worker is not available for provisioning')
print('single_node_registration=PASS')
PY
uid=$(id -u admiral-apps)
home=$(getent passwd admiral-apps | cut -d: -f6)
app_env=(env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus")
rootless=$(runuser -u admiral-apps -- "${app_env[@]}" podman info --format '{{.Host.Security.Rootless}}')
printf 'podman_rootless=%s\n' "$rootless"
[[ $rootless == true ]]
containers=$(runuser -u admiral-apps -- "${app_env[@]}" podman ps -a --format '{{.ID}}')
pods=$(runuser -u admiral-apps -- "${app_env[@]}" podman pod ps --format '{{.ID}}')
volumes=$(runuser -u admiral-apps -- "${app_env[@]}" podman volume ls --format '{{.Name}}')
printf 'initial_rootless_containers=%s pods=%s volumes=%s\n' "${containers:-none}" "${pods:-none}" "${volumes:-none}"
[[ -z $containers && -z $pods && -z $volumes ]]
printf 'single_node_postcheck=PASS end_utc=%s\n' "$(date -u +%FT%TZ)"
