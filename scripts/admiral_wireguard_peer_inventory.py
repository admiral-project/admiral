#!/usr/bin/env python3
"""Create a pinned Ansible inventory for WireGuard peer reconciliation."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import pathlib
import re
import stat
import sys
from typing import Any

import yaml


DEFAULT_KNOWN_HOSTS = pathlib.Path("/var/lib/admiral/know_host.yaml")
DEFAULT_SSH_DIRECTORY = pathlib.Path("/var/lib/admiral/ssh-delivery")
NODE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
HOST_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$")


class InventoryError(ValueError):
    """Invalid or incomplete trusted spoke inventory."""


def _valid_host(value: Any) -> str:
    if not isinstance(value, str) or not value or any(ch.isspace() for ch in value):
        raise InventoryError("active spoke is missing a valid public_ip")
    try:
        ipaddress.ip_address(value)
    except ValueError:
        if not HOST_RE.fullmatch(value):
            raise InventoryError(f"active spoke has invalid public_ip {value!r}")
    return value


def _same_endpoint(first: str, second: str) -> bool:
    """Return whether two configured endpoints identify the same literal host."""
    try:
        return ipaddress.ip_address(first) == ipaddress.ip_address(second)
    except ValueError:
        return first.rstrip(".").casefold() == second.rstrip(".").casefold()


def _load_nodes(path: pathlib.Path) -> list[dict[str, str]]:
    try:
        with path.open(encoding="utf-8") as stream:
            document = yaml.safe_load(stream)
    except (OSError, yaml.YAMLError) as exc:
        raise InventoryError(f"cannot read Admirald node inventory {path}: {exc}") from exc
    if not isinstance(document, dict) or not isinstance(document.get("nodes"), dict):
        raise InventoryError("know_host.yaml must contain a nodes mapping")

    nodes: list[dict[str, str]] = []
    for inventory_key, entry in document["nodes"].items():
        if not isinstance(entry, dict) or entry.get("status") != "active":
            continue
        role = entry.get("node_role")
        if not isinstance(role, str) or role not in {"worker", "portal"}:
            raise InventoryError(
                f"active node {inventory_key!r} has unsupported node_role {role!r}"
            )
        node_id = entry.get("node_id")
        if not isinstance(node_id, str) or not NODE_ID_RE.fullmatch(node_id):
            raise InventoryError(f"active node {inventory_key!r} has invalid node_id")
        if inventory_key != node_id:
            raise InventoryError(
                f"active node key {inventory_key!r} does not match node_id {node_id!r}"
            )
        nodes.append(
            {
                "node_id": node_id,
                "role": role,
                "public_ip": _valid_host(entry.get("public_ip")),
            }
        )
    return sorted(nodes, key=lambda node: (node["role"], node["node_id"]))


def _require_private_file(path: pathlib.Path, *, label: str) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        raise InventoryError(f"{label} is unavailable at {path}; rerun spoke onboarding") from exc
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
        raise InventoryError(f"{label} must be a regular file owned by the installer user: {path}")
    if info.st_mode & 0o077:
        raise InventoryError(f"{label} must not be accessible by group or other users: {path}")


def _node_credentials(node: dict[str, str], ssh_directory: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    node_id = node["node_id"]
    key_path = ssh_directory / f"{node_id}.ed25519"
    known_hosts_path = ssh_directory / f"{node_id}.known_hosts"
    _require_private_file(key_path, label="per-node SSH private key")
    _require_private_file(known_hosts_path, label="pinned SSH host-key file")
    try:
        pinned_hosts = [
            line.split()[0]
            for line in known_hosts_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    except OSError as exc:
        raise InventoryError(f"cannot read pinned SSH host-key file {known_hosts_path}") from exc
    if not any(node["public_ip"] in host.split(",") for host in pinned_hosts):
        raise InventoryError(
            f"pinned SSH host key for node {node_id!r} does not match public_ip "
            f"{node['public_ip']!r}; rerun spoke onboarding with its verified fingerprint"
        )
    return key_path, known_hosts_path


def preflight(
    nodes: list[dict[str, str]],
    *,
    role: str,
    current_node_id: str,
    admin_endpoint: str,
    ssh_directory: pathlib.Path,
) -> bool:
    if not NODE_ID_RE.fullmatch(current_node_id):
        raise InventoryError("current node ID is invalid")
    _valid_host(admin_endpoint)
    # A Portal hosted on the Admin machine uses the Admin's WireGuard address
    # and route. It is not an independent spoke and must not trigger a direct
    # Worker-to-Portal peer exchange or require a second SSH delivery identity.
    spokes = [node for node in nodes if not _same_endpoint(node["public_ip"], admin_endpoint)]
    opposite_role = "portal" if role == "worker" else "worker"
    peers = [
        node
        for node in spokes
        if node["role"] == opposite_role and node["node_id"] != current_node_id
    ]
    if not peers:
        return False
    # The playbook reconverges every active spoke, not only the opposite role.
    for node in spokes:
        if node["node_id"] != current_node_id:
            _node_credentials(node, ssh_directory)
    return True


def build_inventory(
    nodes: list[dict[str, str]],
    *,
    admin_endpoint: str,
    current_node_id: str | None,
    ssh_directory: pathlib.Path,
    exclude_node_id: str | None = None,
    allow_unpaired: bool = False,
) -> dict[str, Any]:
    _valid_host(admin_endpoint)
    if (current_node_id is None) == (exclude_node_id is None):
        raise InventoryError("specify exactly one of current-node-id or exclude-node-id")
    if exclude_node_id is not None:
        if not NODE_ID_RE.fullmatch(exclude_node_id):
            raise InventoryError("excluded node ID is invalid")
        excluded = [node for node in nodes if node["node_id"] == exclude_node_id]
        if not excluded:
            raise InventoryError(f"node {exclude_node_id!r} is not active in know_host.yaml")
        if excluded[0]["role"] not in {"worker", "portal"}:
            raise InventoryError("only a Worker or Portal can be excluded for peer removal")
        if _same_endpoint(excluded[0]["public_ip"], admin_endpoint):
            raise InventoryError("the Admin-co-located Portal is not an independent spoke")
        nodes = [node for node in nodes if node["node_id"] != exclude_node_id]
    # A Portal hosted on the Admin machine uses the Admin's own WireGuard
    # endpoint and is deliberately omitted from direct spoke reconciliation.
    nodes = [node for node in nodes if not _same_endpoint(node["public_ip"], admin_endpoint)]
    if current_node_id is not None:
        if not NODE_ID_RE.fullmatch(current_node_id):
            raise InventoryError("current node ID is invalid")
        if not any(node["node_id"] == current_node_id for node in nodes):
            raise InventoryError(
                f"node {current_node_id!r} is not active in know_host.yaml yet; "
                "wait for registration and heartbeat before peer reconciliation"
            )
    roles: dict[str, dict[str, dict[str, Any]]] = {"admin": {}, "workers": {}, "portal": {}}
    roles["admin"]["admin"] = {
        "ansible_connection": "local",
        "ansible_host": admin_endpoint,
        "ansible_python_interpreter": "/usr/bin/python3",
    }
    for node in nodes:
        key_path, known_hosts_path = _node_credentials(node, ssh_directory)
        roles["portal" if node["role"] == "portal" else "workers"][node["node_id"]] = {
            "ansible_host": node["public_ip"],
            "ansible_user": "admiral-ssh",
            "ansible_ssh_private_key_file": str(key_path),
            "ansible_ssh_common_args": (
                "-o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=yes "
                f"-o UserKnownHostsFile={known_hosts_path}"
            ),
            "ansible_python_interpreter": "/usr/bin/python3",
            "ansible_become": True,
            "fleet_node_id": node["node_id"],
            "admiral_node_name": node["node_id"],
        }
    if not allow_unpaired and (not roles["workers"] or not roles["portal"]):
        raise InventoryError("peer reconciliation requires at least one active Worker and Portal")
    return {
        "all": {
            "children": {
                "admin": {"hosts": roles["admin"]},
                "workers": {"hosts": roles["workers"]},
                "portal": {"hosts": roles["portal"]},
            }
        }
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--known-hosts", type=pathlib.Path, default=DEFAULT_KNOWN_HOSTS)
    parser.add_argument("--ssh-directory", type=pathlib.Path, default=DEFAULT_SSH_DIRECTORY)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser("preflight", help="check if direct peer sync is needed and safe")
    check_parser.add_argument("--role", choices=("worker", "portal"), required=True)
    check_parser.add_argument("--current-node-id", required=True)
    check_parser.add_argument("--admin-endpoint", required=True)

    inventory_parser = subparsers.add_parser("inventory", help="write strict Ansible JSON inventory")
    inventory_parser.add_argument("--admin-endpoint", required=True)
    inventory_parser.add_argument("--current-node-id")
    inventory_parser.add_argument("--exclude-node-id")
    inventory_parser.add_argument("--allow-unpaired", action="store_true")

    args = parser.parse_args()
    try:
        nodes = _load_nodes(args.known_hosts)
        if args.command == "preflight":
            needed = preflight(
                nodes,
                role=args.role,
                current_node_id=args.current_node_id,
                admin_endpoint=args.admin_endpoint,
                ssh_directory=args.ssh_directory,
            )
            print("required" if needed else "not-required")
            return 0
        inventory = build_inventory(
            nodes,
            admin_endpoint=args.admin_endpoint,
            current_node_id=args.current_node_id,
            ssh_directory=args.ssh_directory,
            exclude_node_id=args.exclude_node_id,
            allow_unpaired=args.allow_unpaired,
        )
        json.dump(inventory, sys.stdout, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    except InventoryError as exc:
        print(f"admiral-wireguard-peer-inventory: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
