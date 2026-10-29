#!/usr/bin/env python3
"""Run one validation flow while stopping before host/guest resource floors."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path('/var/lib/libvirt/images/admiral-validation')
GUESTS = {
    'admin': ('192.168.122.20', ROOT / 'cloud-init/rc6e5r18-ipv6-admin/known_hosts'),
    'worker': ('192.168.122.21', ROOT / 'cloud-init/rc6e5r18-ipv6-worker/known_hosts'),
    'portal': ('192.168.122.22', ROOT / 'cloud-init/rc6e5r18-ipv6-portal/known_hosts'),
}
KEY = ROOT / 'keys/validator_ed25519'
MIN_HOST_KIB = 2150 * 1024
MIN_GUEST_KIB = 280 * 1024
MIN_HOST_DISK = 30 * 1024**3
MIN_GUEST_DISK = 2 * 1024**3
MAX_RUNTIME = 240


def guest_resources(address: str, known_hosts: Path) -> dict[str, int]:
    remote = "awk '/MemAvailable:/ {print $2}' /proc/meminfo; df -Pk / | awk 'NR==2 {print $4}'"
    result = subprocess.run(
        ['ssh', '-i', str(KEY), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
         '-o', 'ConnectTimeout=4', '-o', 'StrictHostKeyChecking=yes',
         '-o', f'UserKnownHostsFile={known_hosts}', f'validator@{address}', remote],
        capture_output=True, text=True, timeout=6, check=True,
    )
    values = [int(line) for line in result.stdout.splitlines() if line.strip()]
    if len(values) != 2:
        raise RuntimeError(f'unexpected resource response from {address}')
    return {'mem_available_kib': values[0], 'disk_available_bytes': values[1] * 1024}


def snapshot() -> dict[str, object]:
    host_mem = next(int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()
                    if line.startswith('MemAvailable:'))
    guests = {name: guest_resources(address, hosts) for name, (address, hosts) in GUESTS.items()}
    return {
        'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'host_mem_available_kib': host_mem,
        'host_disk_available_bytes': shutil.disk_usage('/var/lib/libvirt/images').free,
        'guests': guests,
    }


def stop_group(process: subprocess.Popen[bytes], reason: str) -> int:
    print(f'guard_stop_reason={reason}', flush=True)
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        return process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        return process.wait(timeout=5)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit('usage: resource-guard-flow.py FLOW_SCRIPT OUTPUT_LOG')
    flow = Path(sys.argv[1]).resolve()
    output_log = Path(sys.argv[2]).resolve()
    record_path = output_log.with_suffix('.resources.jsonl')
    started = time.monotonic()
    with output_log.open('w', encoding='utf-8') as output:
        process = subprocess.Popen(['bash', str(flow)], stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        reason = ''
        with record_path.open('w', encoding='utf-8') as records:
            while process.poll() is None:
                try:
                    state = snapshot()
                except Exception as exc:
                    state = {'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                             'probe_error': type(exc).__name__}
                    reason = 'resource-probe-failed'
                records.write(json.dumps(state, sort_keys=True) + '\n')
                records.flush()
                if not reason and 'probe_error' not in state:
                    if int(state['host_mem_available_kib']) < MIN_HOST_KIB:
                        reason = 'host RAM below 2150 MiB guard'
                    elif int(state['host_disk_available_bytes']) < MIN_HOST_DISK:
                        reason = 'host disk below 30 GiB guard'
                    else:
                        for name, guest in state['guests'].items():
                            if guest['mem_available_kib'] < MIN_GUEST_KIB:
                                reason = f'{name} RAM below 280 MiB guard'
                                break
                            if guest['disk_available_bytes'] < MIN_GUEST_DISK:
                                reason = f'{name} disk below 2 GiB guard'
                                break
                    if time.monotonic() - started > MAX_RUNTIME:
                        reason = 'flow exceeded four-minute guard'
                if reason:
                    code = stop_group(process, reason)
                    break
                time.sleep(8)
            else:
                code = process.returncode or 0
    print(f'flow_exit_code={code}')
    print(f'resource_samples={sum(1 for _ in record_path.open(encoding="utf-8"))}')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
