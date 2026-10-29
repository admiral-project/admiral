#!/usr/bin/env bash
set -Eeuo pipefail
out=$1
name=$2
while [[ ! -e $out/build-finished ]]; do
  mem_kib=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
  disk_kib=$(df -Pk /var/lib/libvirt/images | awk 'NR==2 {print $4}')
  running=$(podman inspect --format '{{.State.Running}}' "$name" 2>/dev/null || true)
  printf '{"at":"%s","host_memavailable_kib":%s,"host_disk_available_kib":%s,"builder_running":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$mem_kib" "$disk_kib" "${running:-not-created}" >> "$out/build-resource-monitor.jsonl"
  if (( mem_kib < 2097152 || disk_kib < 31457280 )); then
    printf 'STOP: host_memavailable_kib=%s host_disk_available_kib=%s\n' "$mem_kib" "$disk_kib" > "$out/BUILD-STOP.txt"
    if [[ $running == true ]]; then podman stop --time 30 "$name" >> "$out/build-monitor-actions.log" 2>&1 || true; fi
    exit 1
  fi
  sleep 10
done
