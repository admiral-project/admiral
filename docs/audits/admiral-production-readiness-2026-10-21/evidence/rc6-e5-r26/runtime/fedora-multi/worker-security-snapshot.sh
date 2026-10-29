#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run as root on Worker' >&2; exit 2; }
cd /

instance=${INSTANCE_ID:-inst_9fbe80d771bcb0ce}
uid=$(id -u admiral-apps)
apps_env=(
    HOME=/var/lib/admiral-apps
    XDG_RUNTIME_DIR="/run/user/$uid"
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
)
as_apps() { runuser -u admiral-apps -- env "${apps_env[@]}" "$@"; }

printf 'instance=%s\n' "$instance"
for service in app db infra; do
    container="admiral-${instance}-${service}"
    pid=$(as_apps podman inspect --format '{{.State.Pid}}' "$container")
    printf '%s_process_pid=%s' "$service" "$pid"
    for namespace in net pid ipc user mnt; do
        target="/proc/$pid/ns/$namespace"
        if [[ -e $target ]]; then
            printf ' %s_ns=%s' "$namespace" "$(readlink "$target")"
        fi
    done
    status=$(grep -E '^(NoNewPrivs|Seccomp|CapEff):' "/proc/$pid/status" | tr '\n' ' ')
    printf ' %s\n' "$status"
done

for service in app db; do
    container="admiral-${instance}-${service}"
    as_apps podman inspect --format \
        'container={{.Name}} memory_bytes={{.HostConfig.Memory}} nano_cpus={{.HostConfig.NanoCpus}} cpu_quota={{.HostConfig.CpuQuota}} pids_limit={{.HostConfig.PidsLimit}} privileged={{.HostConfig.Privileged}} pid_mode={{.HostConfig.PidMode}} ipc_mode={{.HostConfig.IpcMode}} network_mode={{.HostConfig.NetworkMode}} cap_add={{.HostConfig.CapAdd}} cap_drop={{.HostConfig.CapDrop}} security_opt={{.HostConfig.SecurityOpt}} process_label={{.ProcessLabel}} mount_label={{.MountLabel}}' \
        "$container"
    as_apps podman inspect --format \
        '{{range .Mounts}}mount={{.Type}} name={{.Name}} source={{.Source}} destination={{.Destination}} rw={{.RW}}{{"\n"}}{{end}}' \
        "$container"
    unit="admiral-${instance}-${service}.service"
    source=$(as_apps systemctl --user show "$unit" -p SourcePath --value)
    if [[ -n $source && -f $source ]]; then
        printf '[quadlet-source %s]\n' "$service"
        sed -n '1,160p' "$source"
    fi
    pid=$(as_apps podman inspect --format '{{.State.Pid}}' "$container")
    printf '%s uid_map=' "$service"
    cat "/proc/$pid/uid_map" | tr '\n' ';'
    printf '\n%s gid_map=' "$service"
    cat "/proc/$pid/gid_map" | tr '\n' ';'
    printf '\n%s process_cgroup=' "$service"
    cat "/proc/$pid/cgroup" | tr '\n' ';'
    cgroup_path=$(awk -F: '$1 == "0" { print $3 }' "/proc/$pid/cgroup")
    cg_dir="/sys/fs/cgroup${cgroup_path}"
    for depth in 1 2 3 4 5; do
        [[ $cg_dir == /sys/fs/cgroup ]] && break
        printf '%s_cgroup_depth_%s=%s' "$service" "$depth" "${cg_dir#/sys/fs/cgroup}"
        for control in memory.max cpu.max pids.max; do
            path="$cg_dir/$control"
            if [[ -r $path ]]; then
                printf ' %s=%s' "${control//./_}" "$(cat "$path")"
            fi
        done
        printf '\n'
        cg_dir=${cg_dir%/*}
    done
done

control_interfaces=$(as_apps podman exec --env CHECK_UID="$uid" \
    "admiral-${instance}-db" sh -ec '
for socket in "/run/user/$CHECK_UID/podman/podman.sock" "/run/podman/podman.sock" "/run/user/$CHECK_UID/bus"; do
    if [ -S "$socket" ]; then echo visible; exit 1; fi
done
if command -v podman >/dev/null 2>&1; then echo podman_cli_present; exit 1; fi
echo absent
')
printf 'container_runtime_control_interfaces=%s\n' "$control_interfaces"

database_ports=$(as_apps podman port "admiral-${instance}-db" 5432/tcp 2>&1 || true)
printf 'database_5432_host_mapping=%s\n' "${database_ports//$'\n'/;}"

quadlet_dir="/etc/containers/systemd/users/$uid/admiral"
if [[ -d $quadlet_dir ]]; then
    for file in "$quadlet_dir/admiral-${instance}.pod" \
        "$quadlet_dir/admiral-${instance}-app.container" \
        "$quadlet_dir/admiral-${instance}-db.container"; do
        if [[ -f $file ]]; then
            printf '\n[quadlet %s]\n' "${file##*/}"
            cat "$file"
        fi
    done
fi

printf 'selinux_mode=%s\n' "$(getenforce)"
printf 'user_manager_delegation:\n'
systemctl show "user@${uid}.service" -p Delegate -p ControlGroup -p Slice
printf 'user_manager_controllers=%s\n' \
    "$(cat "/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service/cgroup.controllers")"
printf 'user_manager_subtree_control=%s\n' \
    "$(cat "/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service/cgroup.subtree_control")"
as_apps podman info --format json | python3 -c '
import json, sys
host = json.load(sys.stdin).get("host", {})
security = host.get("security", {})
print("podman_rootless=" + str(security.get("rootless")))
print("podman_cgroups_version=" + str(host.get("cgroupsVersion")))
print("podman_cgroup_manager=" + str(host.get("cgroupManager")))
'
printf 'rootless_units:\n'
as_apps systemctl --user list-units --all --no-legend \
    "admiral-${instance}-*" --no-pager | awk '{print $1, $3, $4}'
printf 'pod_unit_limits:\n'
as_apps systemctl --user show "admiral-${instance}-pod.service" \
    -p FragmentPath -p SourcePath -p MemoryMax -p CPUQuotaPerSecUSec -p TasksMax -p NoNewPrivileges
printf '\n[pod unit]\n'
as_apps systemctl --user cat "admiral-${instance}-pod.service"
printf '\n[pod inspect]\n'
as_apps podman pod inspect "admiral-${instance}" | python3 -c '
import json, sys
data=json.load(sys.stdin)
if isinstance(data, list): data=data[0]
cfg=data.get("InfraConfig", {})
print("name=" + data.get("Name", ""))
for key in ("HostNetwork", "HostPID", "HostIPC", "CgroupParent", "Memory", "CPUPeriod", "CPUQuota", "PidsLimit", "UsernsMode"):
    value = cfg.get(key) or data.get(key) or ""
    print(f"{key}={value}")
'
