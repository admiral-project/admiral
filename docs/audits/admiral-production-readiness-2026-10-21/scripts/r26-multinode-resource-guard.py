#!/usr/bin/env python3
"""Monitor an existing RC6 Multi-Node lab and stop guests gracefully."""

from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path("/var/lib/libvirt/images/admiral-validation")
KEY = ROOT / "keys/validator_ed25519"
NODES = {
    "admin": (
        "rc6e5r18-ipv6-admin",
        "192.168.122.20",
        ROOT / "cloud-init/rc6e5r18-ipv6-admin/known_hosts",
    ),
    "worker": (
        "rc6e5r18-ipv6-worker",
        "192.168.122.21",
        ROOT / "cloud-init/rc6e5r18-ipv6-worker/known_hosts",
    ),
    "portal": (
        "rc6e5r18-ipv6-portal",
        "192.168.122.22",
        ROOT / "cloud-init/rc6e5r18-ipv6-portal/known_hosts",
    ),
}

MIB = 1024**2
GIB = 1024**3
HOST_RAM_STOP = 2048 * MIB
HOST_DISK_STOP = 32 * GIB
GUEST_RAM_STOP = 256 * MIB
GUEST_DISK_STOP = 2 * GIB
INTERVAL_SECONDS = 10
UNMONITORED_GRACE_SECONDS = 240
STOP_REQUESTED = False


def request_monitor_stop(_signal: int, _frame: object) -> None:
    global STOP_REQUESTED
    STOP_REQUESTED = True


signal.signal(signal.SIGINT, request_monitor_stop)
signal.signal(signal.SIGTERM, request_monitor_stop)


def run(args: list[str], timeout: int = 8) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, check=False
    )


def host_snapshot() -> dict[str, int]:
    available = next(
        int(line.split()[1]) * 1024
        for line in Path("/proc/meminfo").read_text().splitlines()
        if line.startswith("MemAvailable:")
    )
    stat = os.statvfs("/var/lib/libvirt/images")
    return {
        "mem_available_bytes": available,
        "disk_available_bytes": stat.f_bavail * stat.f_frsize,
    }


def guest_snapshot(ip: str, known_hosts: Path) -> dict[str, int | str]:
    remote = (
        "awk '/MemAvailable:/ {print $2 * 1024}' /proc/meminfo; "
        "df -B1 --output=avail / | tail -n 1"
    )
    result = run(
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
            "ConnectTimeout=5",
            "-o",
            f"UserKnownHostsFile={known_hosts}",
            f"validator@{ip}",
            remote,
        ],
        timeout=8,
    )
    if result.returncode:
        return {"probe_error": f"ssh_exit_{result.returncode}"}
    values = [int(line.strip()) for line in result.stdout.splitlines() if line.strip().isdigit()]
    if len(values) != 2:
        return {"probe_error": "unexpected_probe_output"}
    return {"mem_available_bytes": values[0], "disk_available_bytes": values[1]}


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: r26-multinode-resource-guard.py OUTPUT.jsonl")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.touch(mode=0o600, exist_ok=True)
    os.chmod(output, 0o600)

    first_active: dict[str, float] = {}
    bad_probe_since: dict[str, float] = {}
    shutdown_requested = False
    stop_reasons: list[str] = []

    with output.open("a", encoding="utf-8", buffering=1) as stream:
        while not STOP_REQUESTED:
            now = time.time()
            sample: dict[str, object] = {
                "utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "host": host_snapshot(),
                "guests": {},
                "domains": {},
            }
            active: list[str] = []
            guests = sample["guests"]
            domains = sample["domains"]
            assert isinstance(guests, dict) and isinstance(domains, dict)

            for role, (domain, ip, known_hosts) in NODES.items():
                state_result = run(["virsh", "domstate", domain], timeout=5)
                state = (
                    state_result.stdout.strip()
                    if state_result.returncode == 0
                    else "state_probe_error"
                )
                domains[role] = state
                if state == "running":
                    active.append(role)
                    first_active.setdefault(role, now)
                    guest = guest_snapshot(ip, known_hosts)
                    guests[role] = guest
                    if "probe_error" in guest:
                        bad_probe_since.setdefault(role, now)
                        if now - bad_probe_since[role] > UNMONITORED_GRACE_SECONDS:
                            stop_reasons.append(f"{role}_unmonitored_over_240s")
                    else:
                        bad_probe_since.pop(role, None)
                else:
                    guests[role] = {"state": state}

            host = sample["host"]
            assert isinstance(host, dict)
            if host["mem_available_bytes"] < HOST_RAM_STOP:
                stop_reasons.append("host_ram_below_2048_MiB")
            if host["disk_available_bytes"] < HOST_DISK_STOP:
                stop_reasons.append("host_disk_below_32_GiB")
            for role, guest in guests.items():
                if not isinstance(guest, dict):
                    continue
                if guest.get("mem_available_bytes", GIB) < GUEST_RAM_STOP:
                    stop_reasons.append(f"{role}_ram_below_256_MiB")
                if guest.get("disk_available_bytes", 10 * GIB) < GUEST_DISK_STOP:
                    stop_reasons.append(f"{role}_disk_below_2_GiB")

            warnings: list[str] = []
            if host["mem_available_bytes"] < 3 * GIB:
                warnings.append("host_ram_below_3_GiB")
            if host["disk_available_bytes"] < 35 * GIB:
                warnings.append("host_disk_below_35_GiB")
            for role, guest in guests.items():
                if isinstance(guest, dict) and "mem_available_bytes" in guest:
                    if guest["mem_available_bytes"] < 512 * MIB:
                        warnings.append(f"{role}_ram_below_512_MiB")
            sample["warnings"] = warnings

            if stop_reasons and not shutdown_requested:
                shutdown_requested = True
                sample["stop_reasons"] = sorted(set(stop_reasons))
                requests = []
                for role in active:
                    domain = NODES[role][0]
                    result = run(["virsh", "shutdown", domain], timeout=10)
                    requests.append(
                        {
                            "domain": domain,
                            "requested": result.returncode == 0,
                            "result": "graceful_shutdown_requested"
                            if result.returncode == 0
                            else "request_failed",
                        }
                    )
                sample["shutdown_requests"] = requests

            sample["shutdown_requested"] = shutdown_requested
            stream.write(json.dumps(sample, sort_keys=True) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
            available_gib = host["mem_available_bytes"] / GIB
            print(
                f"{sample['utc']} host_available_gib={available_gib:.2f} "
                f"active={','.join(active) or 'none'} warnings={len(warnings)} "
                f"shutdown_requested={shutdown_requested}",
                flush=True,
            )
            if shutdown_requested and not active:
                return 0
            time.sleep(INTERVAL_SECONDS)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
