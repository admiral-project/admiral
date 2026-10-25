"""Ansible filters for deriving the Admiral WireGuard hub address."""

from __future__ import annotations

import ipaddress
import re


def wireguard_hub_ip(subnet: str) -> str:
    """Return the first IPv4 address in a WireGuard subnet for the hub."""
    try:
        network = ipaddress.ip_network(str(subnet), strict=False)
    except ValueError as exc:
        raise ValueError(f"invalid Admiral WireGuard subnet {subnet!r}: {exc}") from exc

    if network.version != 4:
        raise ValueError(f"Admiral WireGuard subnet must be IPv4, got {network.version}")
    private_networks = (
        ipaddress.ip_network("10.0.0.0/8"),
        ipaddress.ip_network("172.16.0.0/12"),
        ipaddress.ip_network("192.168.0.0/16"),
    )
    if not any(network.subnet_of(private) for private in private_networks):
        raise ValueError("Admiral WireGuard subnet must be inside an RFC1918 private range")
    if network.num_addresses < 2:
        raise ValueError("Admiral WireGuard subnet must contain a hub and at least one peer address")

    return str(network.network_address + 1)


def stale_wireguard_harbor_rules(
    rules: list[str], worker_ips: list[str], subnet: str, hub_ip: str
) -> list[str]:
    """Return stale exact-source Worker-to-Harbor rules from the WireGuard subnet."""
    network = ipaddress.ip_network(str(subnet), strict=False)
    if network.version != 4:
        raise ValueError("Admiral WireGuard subnet must be IPv4")
    hub = ipaddress.ip_address(str(hub_ip))
    desired = {ipaddress.ip_address(str(value)) for value in worker_ips}
    rule_pattern = re.compile(r'\bsource address="([^\"]+)"')
    harbor_port = 'port port="5001" protocol="tcp" accept'
    stale: list[str] = []
    for rule in rules:
        if harbor_port not in rule:
            continue
        match = rule_pattern.search(rule)
        if match is None:
            continue
        try:
            source = ipaddress.ip_network(match.group(1), strict=False)
        except ValueError:
            continue
        if (
            source.version == 4
            and source.prefixlen == 32
            and source.subnet_of(network)
            and source.network_address != hub
            and source.network_address not in desired
        ):
            stale.append(rule)
    return stale


class FilterModule:
    def filters(self) -> dict[str, object]:
        return {
            "wireguard_hub_ip": wireguard_hub_ip,
            "stale_wireguard_harbor_rules": stale_wireguard_harbor_rules,
        }
