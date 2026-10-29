#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
root=/root/admiral
out=$root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r26/fedora
build=$root/packaging/build/validation/rc6-e5-r26/fedora
helpers=/var/lib/libvirt/images/admiral-validation/repo/rc5-r73/fedora/x86_64
key=/var/lib/libvirt/images/admiral-validation/repo/rc5-r73/RPM-GPG-KEY-admiral-r73
name=admiral-r26-fedora-rpm-build
[[ ! -e $out/build-finished ]] || { echo 'build already recorded' >&2; exit 2; }
[[ $(virsh domstate rc6e5r18-ipv6-admin | tr -d '\r') == 'running' ]]
[[ $(virsh domstate rc6e5r18-ipv6-worker | tr -d '\r') == 'shut off' ]]
[[ $(virsh domstate rc6e5r18-ipv6-portal | tr -d '\r') == 'shut off' ]]
mem_kib=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
disk_kib=$(df -Pk /var/lib/libvirt/images | awk 'NR==2 {print $4}')
(( mem_kib >= 2097152 && disk_kib >= 31457280 )) || { echo "Preflight refused: available RAM=${mem_kib} KiB disk=${disk_kib} KiB" >&2; exit 3; }
[[ $(podman image inspect registry.fedoraproject.org/fedora:rawhide --format '{{.Id}}') == '428f565534c378b103a8ec89b338164726967d88fa562966ed69cf5b3af100aa' ]]
bash "$out/monitor-build-resources.sh" "$out" "$name" & monitor_pid=$!
trap 'touch "$out/build-finished"; wait "$monitor_pid" 2>/dev/null || true' EXIT
printf 'build_started_utc=%s\n' "$(date -u +%FT%TZ)" | tee "$out/build-start.txt"
set +e
podman run --rm --pull=never --name "$name" --cpus=1 --memory=1500m --memory-swap=1500m \
  --security-opt label=disable \
  -v "$root:/src:ro" -v "$build:/build:rw" -v "$helpers:/helpers:ro" -v "$key:/admiral-rpm-key:ro" \
  -w /src registry.fedoraproject.org/fedora:rawhide bash -lc '
    set -Eeuo pipefail
    printf "container_os="; . /etc/os-release; printf "%s %s\n" "$NAME" "$VERSION_ID"
    dnf install -y binutils git golang make python3-argon2-cffi python3-cryptography python3-devel python3-gunicorn python3-pytest python3-pyyaml python3-requests python3-werkzeug rpm-build systemd systemd-rpm-macros
    rpm --import /admiral-rpm-key
    for package in /helpers/python3-*.rpm; do
      [[ $(rpm -qp --qf "%{RELEASE}\n" "$package") == *.fc46 ]]
      rpmkeys --checksig --verbose "$package"
    done
    dnf install -y --setopt=localpkg_gpgcheck=1 /helpers/python3-*.rpm
    GOMAXPROCS=1 GOGC=65 GOTOOLCHAIN=auto make -C /src rpm-admiral RPMDIR=/build RPMTOPDIR=/build SPECSDIR=/src/packaging/rpm RPM_ARCH=x86_64
  ' 2>&1 | tee "$out/fedora-rpm-build.log"
rc=${PIPESTATUS[0]}
set -e
touch "$out/build-finished"
set +e
wait "$monitor_pid"
monitor_rc=$?
set -e
trap - EXIT
printf 'build_exit_code=%s\nmonitor_exit_code=%s\nbuild_finished_utc=%s\n' "$rc" "$monitor_rc" "$(date -u +%FT%TZ)" > "$out/build-result.txt"
[[ $rc -eq 0 && $monitor_rc -eq 0 && ! -e $out/BUILD-STOP.txt ]]
