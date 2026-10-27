from __future__ import annotations

import json
import importlib.util
import pathlib
import re
import subprocess
import sys
import unittest

from jinja2 import Environment


ROOT = pathlib.Path(__file__).resolve().parents[1]
WG_TEMPLATE = ROOT / "ansible/roles/admiral_wireguard/templates/wg-admiral.conf.j2"
EGRESS_TEMPLATE = ROOT / "ansible/roles/admiral_firewall/templates/admiral-egress.nft.j2"
INSTALLER = ROOT / "scripts/install.sh"
FLEET_TASKS = ROOT / "ansible/roles/admiral_fleet/tasks/main.yml"
HARBOR_TASKS = ROOT / "ansible/roles/admiral_harbor/tasks/main.yml"
PEER_INVENTORY = ROOT / "scripts/admiral_wireguard_peer_inventory.py"


class WireGuardIPv6SupportTests(unittest.TestCase):
    def installer_extra_vars(self, overrides: dict[str, str]) -> dict[str, object]:
        script = INSTALLER.read_text(encoding="utf-8")
        marker = "python3 -c '\n"
        start = script.index(marker) + len(marker)
        end = script.index("\n'", start)
        process_env = {
            "INSTALL_MODE": "worker-node",
            "INSTALL_ADMIN_WIREGUARD_IP": "10.99.0.1",
            "ADMIRAL_WIREGUARD_SUBNET": "10.99.0.0/24",
            "INSTALL_PUBLIC_IP": "2001:db8::20",
            "INSTALL_ADMIN_ENDPOINT": "10.99.0.1",
            "INSTALL_NODE_ID": "worker-1",
        }
        process_env.update(overrides)
        result = subprocess.run(
            [sys.executable, "-c", script[start:end]],
            capture_output=True,
            check=False,
            env=process_env,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_wireguard_endpoint_brackets_ipv6_and_preserves_private_ipv4_overlay(self) -> None:
        env = Environment()
        env.filters["regex_findall"] = lambda value, pattern: re.findall(pattern, value, flags=re.MULTILINE)
        rendered = env.from_string(WG_TEMPLATE.read_text(encoding="utf-8")).render(
            admiral_wireguard_role="spoke",
            admiral_wireguard_ip="10.99.0.2",
            admiral_wireguard_subnet="10.99.0.0/24",
            admiral_wg_private_key={"stdout": "test-private-key"},
            admiral_wireguard_port="51820",
            admiral_wireguard_hub_public_key="test-hub-public-key",
            admiral_wireguard_hub_endpoint="2001:db8::1",
            admiral_wireguard_hub_ip="10.99.0.1",
            admiral_wireguard_preshared_key="",
            admiral_wireguard_spoke_peers=[
                {
                    "public_key": "test-peer-public-key",
                    "endpoint": "[2001:db8::2]",
                    "wireguard_ip": "10.99.0.3",
                },
                {
                    "public_key": "test-dns-public-key",
                    "endpoint": "portal.example.test",
                    "wireguard_ip": "10.99.0.4",
                },
            ],
        )

        self.assertIn("Endpoint = [2001:db8::1]:51820", rendered)
        self.assertIn("Endpoint = [2001:db8::2]:51820", rendered)
        self.assertNotIn("[[2001:db8::2]]", rendered)
        self.assertIn("Endpoint = portal.example.test:51820", rendered)
        self.assertIn("AllowedIPs = 10.99.0.1/32", rendered)
        self.assertIn("AllowedIPs = 10.99.0.3/32", rendered)
        self.assertIn("AllowedIPs = 10.99.0.4/32", rendered)

    def test_ipv6_only_public_roles_get_role_scoped_port_egress(self) -> None:
        env = Environment()
        env.filters["bool"] = bool
        template = env.from_string(EGRESS_TEMPLATE.read_text(encoding="utf-8"))
        rendered = template.render(
            admiral_wireguard_subnet="10.99.0.0/24",
            admiral_egress_ipv6_enabled=True,
            admiral_egress_ipv4_destinations=[],
            admiral_egress_ipv6_destinations=[],
            admiral_effective_host_profile="worker",
        )

        self.assertIn("tcp dport { 80, 443, 587, 9000 } accept", rendered)
        self.assertIn("meta nfproto ipv6 tcp dport { 80, 443, 587, 9000 } accept", rendered)
        self.assertIn("udp dport 51820 accept", rendered)
        self.assertIn("icmpv6 type", rendered)
        self.assertIn("reject", rendered)

    def test_ipv6_destination_allowlist_remains_restrictive(self) -> None:
        env = Environment()
        env.filters["bool"] = bool
        template = env.from_string(EGRESS_TEMPLATE.read_text(encoding="utf-8"))
        rendered = template.render(
            admiral_wireguard_subnet="10.99.0.0/24",
            admiral_egress_ipv6_enabled=True,
            admiral_egress_ipv4_destinations=[],
            admiral_egress_ipv6_destinations=["2001:db8:100::/64"],
            admiral_effective_host_profile="worker",
        )

        self.assertIn("ip6 daddr { 2001:db8:100::/64 } tcp dport { 80, 443, 587, 9000 } accept", rendered)
        self.assertIn("meta nfproto ipv4 tcp dport { 80, 443, 587, 9000 } accept", rendered)
        self.assertNotIn("meta nfproto ipv6 tcp dport { 80, 443, 587, 9000 } accept", rendered)

    def test_ipv6_external_tcp_is_not_enabled_without_ipv6_configuration(self) -> None:
        env = Environment()
        env.filters["bool"] = bool
        template = env.from_string(EGRESS_TEMPLATE.read_text(encoding="utf-8"))
        rendered = template.render(
            admiral_wireguard_subnet="10.99.0.0/24",
            admiral_egress_ipv6_enabled=False,
            admiral_egress_ipv4_destinations=[],
            admiral_egress_ipv6_destinations=[],
            admiral_effective_host_profile="worker",
        )

        self.assertNotIn("meta nfproto ipv6 tcp dport", rendered)
        self.assertIn("meta nfproto ipv4 tcp dport { 80, 443, 587, 9000 } accept", rendered)

    def test_ipv6_literal_installer_endpoint_enables_ipv6_firewall(self) -> None:
        extra_vars = self.installer_extra_vars({})
        self.assertTrue(extra_vars["fleet_public_ip_is_ip"])
        self.assertTrue(extra_vars["admiral_egress_ipv6_enabled"])
        self.assertEqual(extra_vars["fleet_public_ip"], "2001:db8::20")
        self.assertEqual(extra_vars["admiral_wireguard_hub_ip"], "10.99.0.1")

    def test_installer_validates_ipv6_literal_endpoints(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")
        start = content.index("validate_ip_or_hostname() {")
        end = content.index("\n}", start) + 2
        validator = content[start:end]
        result = subprocess.run(
            ["bash", "-c", validator + '\nvalidate_ip_or_hostname "$1"', "test", "2001:db8::20"],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dns_endpoint_can_enable_ipv6_firewall_explicitly(self) -> None:
        extra_vars = self.installer_extra_vars(
            {
                "INSTALL_MODE": "portal-node",
                "INSTALL_PUBLIC_IP": "portal.example.test",
                "INSTALL_NODE_ID": "portal-1",
                "ADMIRAL_EGRESS_IPV6_ENABLED": "true",
            }
        )
        self.assertFalse(extra_vars["fleet_public_ip_is_ip"])
        self.assertTrue(extra_vars["admiral_egress_ipv6_enabled"])

    def test_ipv6_only_worker_and_portal_registration_fall_back_to_private_vpn_ipv4(self) -> None:
        env = Environment()
        for tasks in (FLEET_TASKS, HARBOR_TASKS):
            with self.subTest(tasks=tasks.parent.parent.name):
                content = tasks.read_text(encoding="utf-8")
                match = re.search(r'--ip "\{\{ (.*?) \}\}"', content)
                self.assertIsNotNone(match)
                assert match is not None
                expression = env.from_string("{{ " + match.group(1) + " }}")
                self.assertEqual(
                    expression.render(ansible_facts={}, admiral_wireguard_ip="10.99.0.2"),
                    "10.99.0.2",
                )
                self.assertEqual(
                    expression.render(
                        ansible_facts={"default_ipv4": {"address": "192.0.2.20"}},
                        admiral_wireguard_ip="10.99.0.2",
                    ),
                    "192.0.2.20",
                )

    def test_peer_inventory_accepts_ipv6_public_endpoint(self) -> None:
        spec = importlib.util.spec_from_file_location("peer_inventory_ipv6", PEER_INVENTORY)
        self.assertIsNotNone(spec)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module._valid_host("2001:db8::20"), "2001:db8::20")


if __name__ == "__main__":
    unittest.main()
