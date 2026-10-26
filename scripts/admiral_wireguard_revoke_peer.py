#!/usr/bin/env python3
"""Reconcile spoke peers, then remove a registered node's hub peer.

This program is started by a root-owned systemd socket unit. It accepts one
identity-checked JSON request and never prints peer keys or command output.
"""

from __future__ import annotations

import fcntl
import json
import os
import pwd
import re
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

import ipaddress
import yaml


INTERFACE = "wg-admiral"
CONFIG = Path("/etc/wireguard/wg-admiral.conf")
PEER_DIR = Path("/etc/wireguard/peers.d")
LOCK = Path("/run/lock/admiral-wireguard-peer-add.lock")
MAX_REQUEST_BYTES = 512
COMMAND_TIMEOUT_SECONDS = 2
INVENTORY_TIMEOUT_SECONDS = 3
ANSIBLE_TIMEOUT_SECONDS = 12
KNOWN_HOSTS = Path("/var/lib/admiral/know_host.yaml")
SSH_DIRECTORY = Path("/var/lib/admiral/ssh-delivery")
INSTALL_STATE = Path("/etc/admiral/install.env")
INVENTORY_HELPER = "/usr/bin/admiral-wireguard-peer-inventory"
ANSIBLE_PLAYBOOK = "/usr/bin/ansible-playbook"
PEER_PLAYBOOK = Path("/usr/share/admiral/ansible/wireguard-peers.yml")
NODE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")


class RevocationError(RuntimeError):
    """A peer could not be safely revoked."""


Runner = Callable[..., subprocess.CompletedProcess[str]]


def _run(command: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RevocationError(f"could not run {Path(command[0]).name}") from exc


def _parse_target(value: str) -> ipaddress.IPv4Address:
    try:
        target = ipaddress.ip_address(value)
    except ValueError as exc:
        raise RevocationError("WireGuard peer address is invalid") from exc
    if (
        not isinstance(target, ipaddress.IPv4Address)
        or target.is_unspecified
        or target.is_loopback
        or target.is_multicast
        or target.is_link_local
    ):
        raise RevocationError("WireGuard peer address must be a unicast IPv4 address")
    return target


def _interface_network(
    target: ipaddress.IPv4Address,
    config_text: str,
    run: Runner,
) -> tuple[bool, ipaddress.IPv4Network]:
    result = run(["ip", "-o", "-4", "addr", "show", "dev", INTERFACE])
    interface_present = result.returncode == 0
    if not interface_present:
        listed = run(["wg", "show", "interfaces"])
        if listed.returncode != 0:
            raise RevocationError("could not determine whether the hub WireGuard interface is active")
        if INTERFACE in listed.stdout.split():
            raise RevocationError("could not inspect the active hub WireGuard address")
    candidates: list[str] = []
    if interface_present:
        candidates.extend(re.findall(r"\binet\s+(\d+(?:\.\d+){3}/\d+)\b", result.stdout))
    if not candidates:
        candidates.extend(re.findall(r"(?m)^\s*Address\s*=\s*(\d+(?:\.\d+){3}/\d+)\s*$", config_text))
    for candidate in candidates:
        try:
            network = ipaddress.ip_interface(candidate).network
        except ValueError:
            continue
        if target in network:
            if any(ipaddress.ip_interface(item).ip == target for item in candidates if _valid_interface(item)):
                raise RevocationError("refusing to revoke the hub interface address")
            return interface_present, network
    raise RevocationError("peer address is outside the configured WireGuard subnet")


def _valid_interface(value: str) -> bool:
    try:
        ipaddress.ip_interface(value)
    except ValueError:
        return False
    return True


def _peer_sections(text: str) -> list[tuple[int, int, list[str]]]:
    lines = text.splitlines(keepends=True)
    headers = [index for index, line in enumerate(lines) if re.match(r"^\s*\[[^]]+\]\s*(?:#.*)?$", line)]
    sections: list[tuple[int, int, list[str]]] = []
    for position, start in enumerate(headers):
        end = headers[position + 1] if position + 1 < len(headers) else len(lines)
        if re.match(r"^\s*\[Peer\]\s*(?:#.*)?$", lines[start], re.IGNORECASE):
            sections.append((start, end, lines))
    return sections


def _section_matches_peer(section: list[str], target: ipaddress.IPv4Address) -> bool:
    values: list[str] = []
    for line in section:
        if re.match(r"^\s*\[Peer\]\s*(?:#.*)?$", line, re.IGNORECASE):
            continue
        match = re.match(r"^\s*AllowedIPs\s*=\s*([^#]+)", line, re.IGNORECASE)
        if match:
            values.append(match.group(1).strip())
    if not values:
        return False
    entries = [entry.strip() for value in values for entry in value.split(",") if entry.strip()]
    networks: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    try:
        networks = [ipaddress.ip_network(entry, strict=False) for entry in entries]
    except ValueError as exc:
        raise RevocationError("WireGuard peer configuration has an invalid AllowedIPs value") from exc
    matches = [network for network in networks if network.version == 4 and target in network]
    if not matches:
        return False
    if len(networks) != 1 or len(matches) != 1 or matches[0] != ipaddress.ip_network(f"{target}/32"):
        raise RevocationError("peer has additional AllowedIPs; refusing to remove unrelated routes")
    return True


def _remove_peer_sections(text: str, target: ipaddress.IPv4Address) -> tuple[str, int]:
    lines = text.splitlines(keepends=True)
    remove: set[int] = set()
    removed = 0
    headers = [index for index, line in enumerate(lines) if re.match(r"^\s*\[[^]]+\]\s*(?:#.*)?$", line)]
    for position, start in enumerate(headers):
        end = headers[position + 1] if position + 1 < len(headers) else len(lines)
        if not re.match(r"^\s*\[Peer\]\s*(?:#.*)?$", lines[start], re.IGNORECASE):
            continue
        if not _section_matches_peer(lines[start:end], target):
            continue
        section_start = start
        if start > 0 and re.match(r"^\s*#\s*ADMIRAL WORKER PEER\b", lines[start - 1], re.IGNORECASE):
            section_start -= 1
        remove.update(range(section_start, end))
        removed += 1
    return "".join(line for index, line in enumerate(lines) if index not in remove), removed


def _atomic_replace(path: Path, content: str) -> None:
    metadata = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(metadata.st_mode):
        raise RevocationError(f"refusing to edit non-regular WireGuard configuration {path.name}")
    if metadata.st_uid != os.geteuid() or metadata.st_gid != os.getegid():
        raise RevocationError(f"WireGuard configuration {path.name} is not owned by the helper user")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.revoke.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, stat.S_IMODE(metadata.st_mode))
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except Exception:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def _update_persistent_config(target: ipaddress.IPv4Address, config: Path, peer_dir: Path) -> int:
    paths: list[Path] = []
    if config.exists():
        if config.is_symlink():
            raise RevocationError("hub WireGuard configuration must not be a symbolic link")
        paths.append(config)
    if peer_dir.exists():
        paths.extend(sorted(peer_dir.glob("*.conf")))
    changes: list[tuple[Path, str, int]] = []
    total_removed = 0
    for path in paths:
        if path.is_symlink():
            continue
        if not path.is_file():
            continue
        try:
            original = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise RevocationError(f"could not read WireGuard configuration {path.name}") from exc
        updated, removed = _remove_peer_sections(original, target)
        if removed:
            changes.append((path, updated, removed))
            total_removed += removed
    for path, updated, _ in changes:
        if path.parent == peer_dir and not any(line.strip() and not line.lstrip().startswith("#") for line in updated.splitlines()):
            path.unlink()
            directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        else:
            _atomic_replace(path, updated)
    return total_removed


def _live_peer_keys(target: ipaddress.IPv4Address, run: Runner) -> list[str]:
    result = run(["wg", "show", INTERFACE, "allowed-ips"])
    if result.returncode != 0:
        raise RevocationError("could not inspect live WireGuard peers")
    keys: list[str] = []
    target_cidr = f"{target}/32"
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        if fields[1] == "(none)":
            continue
        allowed = [item.strip() for item in fields[1].split(",") if item.strip()]
        routes: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
        try:
            routes = [ipaddress.ip_network(item, strict=False) for item in allowed]
        except ValueError as exc:
            raise RevocationError("live WireGuard peer has an invalid AllowedIPs value") from exc
        matching = [route for route in routes if route.version == 4 and target in route]
        if matching:
            if len(routes) != 1 or len(matching) != 1 or str(matching[0]) != target_cidr:
                raise RevocationError("live peer has additional AllowedIPs; refusing to remove unrelated routes")
            keys.append(fields[0])
    return keys


def _revoke_peer_locked(
    value: str,
    *,
    config: Path = CONFIG,
    peer_dir: Path = PEER_DIR,
    lock: Path = LOCK,
    run: Runner = _run,
) -> tuple[dict[str, object], int]:
    target = _parse_target(value)
    if config.is_symlink():
        raise RevocationError("hub WireGuard configuration must not be a symbolic link")
    try:
        config_text = config.read_text(encoding="utf-8")
    except OSError as exc:
        raise RevocationError("hub WireGuard configuration is unavailable") from exc

    interface_present, _ = _interface_network(target, config_text, run)
    lock_fd = _acquire_peer_lock(lock)
    try:
        return _revoke_peer_under_lock(
            target,
            interface_present=interface_present,
            config=config,
            peer_dir=peer_dir,
            run=run,
        ), lock_fd
    except Exception:
        os.close(lock_fd)
        raise


def _acquire_peer_lock(lock: Path = LOCK) -> int:
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        lock_fd = os.open(lock, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    except OSError as exc:
        raise RevocationError("could not open WireGuard peer lock") from exc
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        return lock_fd
    except OSError as exc:
        os.close(lock_fd)
        raise RevocationError("could not lock WireGuard peer configuration") from exc


def _revoke_peer_under_lock(
    target: ipaddress.IPv4Address,
    *,
    interface_present: bool,
    config: Path = CONFIG,
    peer_dir: Path = PEER_DIR,
    run: Runner = _run,
) -> dict[str, object]:
    live_keys = _live_peer_keys(target, run) if interface_present else []
    persistent_removed = _update_persistent_config(target, config, peer_dir)
    live_removed = 0
    if interface_present:
        for key in live_keys:
            result = run(["wg", "set", INTERFACE, "peer", key, "remove"])
            if result.returncode != 0:
                raise RevocationError("WireGuard refused to remove the live peer")
            live_removed += 1
        if _live_peer_keys(target, run):
            raise RevocationError("WireGuard peer remained active after revocation")
    return {
        "success": True,
        "wireguard_ip": str(target),
        "live_peers_removed": live_removed,
        "persistent_peer_entries_removed": persistent_removed,
    }


def _load_removal_request(raw: bytes, known_hosts: Path = KNOWN_HOSTS) -> tuple[str, ipaddress.IPv4Address]:
    if len(raw) > MAX_REQUEST_BYTES or not raw.endswith(b"\n"):
        raise RevocationError("request must be one short JSON line")
    try:
        request = json.loads(raw.decode("ascii"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RevocationError("request must be valid JSON") from exc
    if not isinstance(request, dict) or set(request) != {"node_id", "node_role", "wireguard_ip"}:
        raise RevocationError("request must contain node_id, node_role, and wireguard_ip")
    node_id = request.get("node_id")
    role = request.get("node_role")
    target = _parse_target(str(request.get("wireguard_ip", "")))
    if not isinstance(node_id, str) or not NODE_ID_PATTERN.fullmatch(node_id):
        raise RevocationError("node ID is invalid")
    if not isinstance(role, str) or role not in {"worker", "portal"}:
        raise RevocationError("only registered Worker or Portal nodes can be removed")
    try:
        info = known_hosts.lstat()
        allowed_owners = {0, os.geteuid()}
        try:
            allowed_owners.add(pwd.getpwnam("admiral").pw_uid)
        except KeyError:
            pass
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid not in allowed_owners
            or info.st_mode & 0o022
        ):
            raise RevocationError("control-plane node inventory has unsafe ownership or permissions")
        with known_hosts.open(encoding="utf-8") as stream:
            document = yaml.safe_load(stream)
    except RevocationError:
        raise
    except (KeyError, OSError, yaml.YAMLError) as exc:
        raise RevocationError("could not read the control-plane node inventory") from exc
    nodes = document.get("nodes") if isinstance(document, dict) else None
    entry = nodes.get(node_id) if isinstance(nodes, dict) else None
    if (
        not isinstance(entry, dict)
        or entry.get("node_id") != node_id
        or entry.get("node_role") != role
        or entry.get("status") != "active"
        or entry.get("wireguard_ip") != str(target)
    ):
        raise RevocationError("node identity does not match an active control-plane inventory entry")
    return node_id, target


def _load_install_state(path: Path = INSTALL_STATE) -> tuple[str, str, str]:
    try:
        info = path.lstat()
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid not in {0, os.geteuid()}
            or info.st_mode & 0o022
        ):
            raise RevocationError("installer state must be a regular file")
        with path.open(encoding="utf-8") as stream:
            state = json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        raise RevocationError("installer state is unavailable; rerun the admin install profile") from exc
    if not isinstance(state, dict):
        raise RevocationError("installer state is invalid; rerun the admin install profile")
    endpoint = state.get("ADMIRAL_PUBLIC_IP")
    subnet = state.get("ADMIRAL_WIREGUARD_SUBNET")
    hub_ip = state.get("ADMIRAL_WIREGUARD_HUB_IP")
    if not all(isinstance(value, str) and value for value in (endpoint, subnet, hub_ip)):
        raise RevocationError("installer state lacks WireGuard topology; rerun the admin install profile")
    try:
        network = ipaddress.ip_network(subnet, strict=False)
        hub = ipaddress.ip_address(hub_ip)
        endpoint_ip = ipaddress.ip_address(endpoint)
    except ValueError:
        network = None
        hub = None
        try:
            endpoint_ip = None if not isinstance(endpoint, str) else ipaddress.ip_address(endpoint)
        except ValueError:
            endpoint_ip = None
    if network is None or hub is None or network.version != 4 or hub.version != 4 or hub not in network:
        raise RevocationError("installer WireGuard topology is invalid; rerun the admin install profile")
    if endpoint_ip is None and not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", endpoint):
        raise RevocationError("admin public endpoint in installer state is invalid")
    return endpoint, str(network), str(hub)


def _build_removal_inventory(
    node_id: str,
    *,
    temp_directory: Path,
    known_hosts: Path = KNOWN_HOSTS,
    ssh_directory: Path = SSH_DIRECTORY,
    install_state: Path = INSTALL_STATE,
) -> tuple[Path, Path]:
    endpoint, subnet, hub_ip = _load_install_state(install_state)
    inventory_path = temp_directory / "inventory.json"
    vars_path = temp_directory / "wireguard-vars.json"
    command = [
        INVENTORY_HELPER,
        "--known-hosts",
        str(known_hosts),
        "--ssh-directory",
        str(ssh_directory),
        "inventory",
        "--admin-endpoint",
        endpoint,
        "--exclude-node-id",
        node_id,
        "--allow-unpaired",
    ]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=INVENTORY_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RevocationError("could not build the pinned peer-removal inventory") from exc
    if result.returncode != 0:
        raise RevocationError("peer-removal inventory is incomplete; verify active spoke keys and host-key pins")
    try:
        inventory = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RevocationError("peer-removal inventory helper returned invalid JSON") from exc
    all_group = inventory.get("all") if isinstance(inventory, dict) else None
    hosts = all_group.get("children") if isinstance(all_group, dict) else None
    if not isinstance(hosts, dict):
        raise RevocationError("peer-removal inventory has no valid groups")
    admin_group = hosts.get("admin")
    admin_hosts = admin_group.get("hosts") if isinstance(admin_group, dict) else None
    admin = admin_hosts.get("admin") if isinstance(admin_hosts, dict) else None
    if not isinstance(admin, dict) or admin.get("ansible_connection") != "local":
        raise RevocationError("peer-removal inventory has no local admin host")
    for group in ("workers", "portal"):
        group_definition = hosts.get(group)
        group_hosts = group_definition.get("hosts") if isinstance(group_definition, dict) else None
        if not isinstance(group_hosts, dict) or node_id in group_hosts:
            raise RevocationError("removed node is present in the peer-removal inventory")
        for host in group_hosts.values():
            args = host.get("ansible_ssh_common_args", "") if isinstance(host, dict) else ""
            if "StrictHostKeyChecking=yes" not in args or "StrictHostKeyChecking=no" in args:
                raise RevocationError("peer-removal inventory does not require strict SSH host-key checking")
    inventory_path.write_text(result.stdout, encoding="utf-8")
    os.chmod(inventory_path, 0o600)
    vars_path.write_text(
        json.dumps(
            {
                "admiral_wireguard_subnet": subnet,
                "admiral_wireguard_hub_ip": hub_ip,
            },
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    os.chmod(vars_path, 0o600)
    return inventory_path, vars_path


def _run_peer_playbook(inventory: Path, extra_vars: Path) -> None:
    if not PEER_PLAYBOOK.is_file():
        raise RevocationError("packaged WireGuard peer playbook is unavailable; update admiral-common")
    command = [
        ANSIBLE_PLAYBOOK,
        str(PEER_PLAYBOOK),
        "-i",
        str(inventory),
        "--extra-vars",
        f"@{extra_vars}",
        "--timeout",
        "5",
    ]
    with tempfile.TemporaryDirectory(prefix="admiral-peer-reconcile-") as temp:
        local_temp = Path(temp) / "local"
        galaxy_cache = Path(temp) / "galaxy"
        local_temp.mkdir(mode=0o700)
        galaxy_cache.mkdir(mode=0o700)
        environment = os.environ.copy()
        environment.update(
            {
                "ANSIBLE_LOCAL_TEMP": str(local_temp),
                "ANSIBLE_REMOTE_TEMP": "/tmp",
                "ANSIBLE_GALAXY_CACHE_DIR": str(galaxy_cache),
                "ANSIBLE_HOST_KEY_CHECKING": "True",
                "ANSIBLE_NOCOLOR": "1",
            }
        )
        process = None
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=environment,
                start_new_session=True,
            )
            process.communicate(timeout=ANSIBLE_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired as exc:
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.communicate(timeout=1)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.communicate()
            raise RevocationError("WireGuard spoke reconciliation timed out and was stopped") from exc
        except OSError as exc:
            raise RevocationError("WireGuard spoke reconciliation timed out or could not start") from exc
    if process is None or process.returncode != 0:
        raise RevocationError("WireGuard spoke reconciliation failed; node remains registered and removal is retryable")


def _remove_node_and_reconcile(raw: bytes) -> tuple[dict[str, object], int]:
    node_id, target = _load_removal_request(raw)
    lock_fd = _acquire_peer_lock()
    try:
        with tempfile.TemporaryDirectory(prefix="admiral-peer-inventory-") as temp:
            inventory, extra_vars = _build_removal_inventory(
                node_id,
                temp_directory=Path(temp),
            )
            if CONFIG.is_symlink():
                raise RevocationError("hub WireGuard configuration must not be a symbolic link")
            try:
                config_text = CONFIG.read_text(encoding="utf-8")
            except OSError as exc:
                raise RevocationError("hub WireGuard configuration is unavailable") from exc
            interface_present, _ = _interface_network(target, config_text, _run)
            # First reconcile every remaining spoke. On a network/SSH failure,
            # the node and its hub peer stay registered and usable for retry.
            _run_peer_playbook(inventory, extra_vars)
            response = _revoke_peer_under_lock(
                target,
                interface_present=interface_present,
            )
            response.update({"node_id": node_id, "peer_reconciliation": "succeeded"})
        return response, lock_fd
    except Exception:
        os.close(lock_fd)
        raise


def revoke_peer(
    value: str,
    *,
    config: Path = CONFIG,
    peer_dir: Path = PEER_DIR,
    lock: Path = LOCK,
    run: Runner = _run,
) -> dict[str, object]:
    response, lock_fd = _revoke_peer_locked(
        value,
        config=config,
        peer_dir=peer_dir,
        lock=lock,
        run=run,
    )
    os.close(lock_fd)
    return response


def main() -> int:
    raw = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
    lock_fd = None
    try:
        response, lock_fd = _remove_node_and_reconcile(raw)
    except (UnicodeDecodeError, RevocationError, OSError) as exc:
        response = {"success": False, "error": str(exc)}
    try:
        sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        if response.get("success"):
            # Keep the peer lock until the caller's database transaction has
            # committed and it closes the accepted socket.
            sys.stdin.buffer.read()
        return 0 if response.get("success") else 1
    finally:
        if lock_fd is not None:
            os.close(lock_fd)


if __name__ == "__main__":
    raise SystemExit(main())
