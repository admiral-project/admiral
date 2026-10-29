#!/usr/bin/env python3
"""Monitor the existing Fedora Single guest and host release resources."""

from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import time


ROOT = Path("/var/lib/libvirt/images/admiral-validation")
KEY = ROOT / "keys/validator_ed25519"
GUESTS = {
    "single": (
        "192.168.122.21",
        ROOT / "cloud-init/rc6e5r18-ipv6-worker/known_hosts",
    ),
}
OUT = Path(__file__).with_name("resource-monitor-single-resume.jsonl")
INTERVAL_SECONDS = 10
GIB = 1024**3
MIB = 1024**2
HOST_MIN_RAM = int(2.5 * GIB)
HOST_MIN_DISK = 32 * GIB
GUEST_MIN_RAM = 512 * MIB
GUEST_MIN_DISK = 2 * GIB


def guest_resources(address: str, known_hosts: Path) -> dict[str, int | str | None]:
    command = (
        "awk '/MemAvailable:/ { print $2 * 1024 }' /proc/meminfo; "
        "df -B1 --output=avail / | tail -n 1"
    )
    try:
        result = subprocess.run(
            [
                "ssh",
                "-i",
                str(KEY),
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                "ConnectTimeout=4",
                "-o",
                f"UserKnownHostsFile={known_hosts}",
                "validator@" + address,
                command,
            ],
            capture_output=True,
            text=True,
            timeout=6,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {"error": "ssh probe exceeded 6 seconds"}
    if result.returncode != 0:
        return {"error": result.stderr.strip()[-400:] or f"ssh exit {result.returncode}"}
    values = [int(line.strip()) for line in result.stdout.splitlines() if line.strip().isdigit()]
    if len(values) < 2:
        return {"error": f"unexpected guest resource output: {result.stdout[-200:]}"}
    return {"mem_available_bytes": values[0], "disk_available_bytes": values[1]}


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("a", encoding="utf-8", buffering=1) as stream:
        index = 0
        while True:
            index += 1
            mem_available = next(
                int(line.split()[1]) * 1024
                for line in Path("/proc/meminfo").read_text().splitlines()
                if line.startswith("MemAvailable:")
            )
            stat = os.statvfs("/var/lib/libvirt/images")
            host = {
                "mem_available_bytes": mem_available,
                "disk_available_bytes": stat.f_bavail * stat.f_frsize,
            }
            guests = {
                name: guest_resources(address, known_hosts)
                for name, (address, known_hosts) in GUESTS.items()
            }
            alerts = []
            if mem_available < HOST_MIN_RAM:
                alerts.append(f"host RAM below {HOST_MIN_RAM / GIB:g} GiB")
            if host["disk_available_bytes"] < HOST_MIN_DISK:
                alerts.append(f"host disk below {HOST_MIN_DISK / GIB:g} GiB")
            for name, values in guests.items():
                if "mem_available_bytes" in values and values["mem_available_bytes"] < GUEST_MIN_RAM:
                    alerts.append(f"{name} RAM below {GUEST_MIN_RAM / MIB:g} MiB")
                if "disk_available_bytes" in values and values["disk_available_bytes"] < GUEST_MIN_DISK:
                    alerts.append(f"{name} disk below {GUEST_MIN_DISK / GIB:g} GiB")
            record = {
                "sample": index,
                "utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "host": host,
                "guests": guests,
                "alerts": alerts,
            }
            stream.write(json.dumps(record, sort_keys=True) + "\n")
            print(
                f"sample={index} host_mem_available_mib={mem_available // MIB} "
                f"host_disk_available_gib={host['disk_available_bytes'] // GIB} "
                f"guests={guests} alerts={alerts}",
                flush=True,
            )
            time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
