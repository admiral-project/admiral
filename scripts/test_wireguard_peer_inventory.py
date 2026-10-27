#!/usr/bin/env python3
"""Tests for strict, fingerprint-pinned Worker-to-Portal Ansible inventory."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "admiral_wireguard_peer_inventory.py"
SPEC = importlib.util.spec_from_file_location("admiral_wireguard_peer_inventory", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
INVENTORY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INVENTORY)


class WireGuardPeerInventoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.known_hosts = self.root / "know_host.yaml"
        self.ssh_directory = self.root / "ssh-delivery"
        self.ssh_directory.mkdir(mode=0o700)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_nodes(self, nodes: dict[str, dict[str, str]]) -> list[dict[str, str]]:
        import yaml

        self.known_hosts.write_text(yaml.safe_dump({"version": 1, "nodes": nodes}), encoding="utf-8")
        return INVENTORY._load_nodes(self.known_hosts)

    def credentials(self, node_id: str, host: str) -> None:
        key = self.ssh_directory / f"{node_id}.ed25519"
        key.write_text("private-key-placeholder\n", encoding="utf-8")
        key.chmod(0o600)
        pin = self.ssh_directory / f"{node_id}.known_hosts"
        pin.write_text(f"{host} ssh-ed25519 AAAATEST\n", encoding="utf-8")
        pin.chmod(0o600)

    def test_preflight_does_not_require_direct_peers_before_opposite_role_exists(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                }
            }
        )

        required = INVENTORY.preflight(
            nodes,
            role="worker",
            current_node_id="worker-1",
            admin_endpoint="192.0.2.1",
            ssh_directory=self.ssh_directory,
        )

        self.assertFalse(required)

    def test_preflight_requires_credentials_for_every_existing_spoke_when_roles_pair(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                },
            }
        )
        self.credentials("worker-1", "192.0.2.10")

        with self.assertRaisesRegex(INVENTORY.InventoryError, "portal-1.*rerun spoke onboarding"):
            INVENTORY.preflight(
                nodes,
                role="worker",
                current_node_id="worker-1",
                admin_endpoint="192.0.2.1",
                ssh_directory=self.ssh_directory,
            )

    def test_preflight_ignores_admin_colocated_portal_without_spoke_credentials(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "admin-portal": {
                    "node_id": "admin-portal",
                    "node_role": "portal",
                    "public_ip": "192.0.2.1",
                    "status": "active",
                },
            }
        )

        required = INVENTORY.preflight(
            nodes,
            role="worker",
            current_node_id="worker-1",
            admin_endpoint="192.0.2.1",
            ssh_directory=self.ssh_directory,
        )

        self.assertFalse(required)

    def test_preflight_requires_independent_portal_but_skips_admin_colocated_portal(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "admin-portal": {
                    "node_id": "admin-portal",
                    "node_role": "portal",
                    "public_ip": "192.0.2.1",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                },
            }
        )
        self.credentials("portal-1", "192.0.2.20")

        required = INVENTORY.preflight(
            nodes,
            role="worker",
            current_node_id="worker-1",
            admin_endpoint="192.0.2.1",
            ssh_directory=self.ssh_directory,
        )

        self.assertTrue(required)

    def test_build_inventory_uses_node_specific_keys_and_pinned_strict_ssh(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "portal.example.test",
                    "status": "active",
                },
            }
        )
        self.credentials("worker-1", "192.0.2.10")
        self.credentials("portal-1", "portal.example.test")

        inventory = INVENTORY.build_inventory(
            nodes,
            admin_endpoint="admin.example.test",
            current_node_id="portal-1",
            ssh_directory=self.ssh_directory,
        )

        hosts = inventory["all"]["children"]
        self.assertEqual(set(hosts["workers"]["hosts"]), {"worker-1"})
        self.assertEqual(set(hosts["portal"]["hosts"]), {"portal-1"})
        self.assertEqual(hosts["admin"]["hosts"]["admin"]["ansible_connection"], "local")
        worker = hosts["workers"]["hosts"]["worker-1"]
        self.assertEqual(worker["ansible_host"], "192.0.2.10")
        self.assertEqual(worker["ansible_ssh_private_key_file"], str(self.ssh_directory / "worker-1.ed25519"))
        self.assertIn("StrictHostKeyChecking=yes", worker["ansible_ssh_common_args"])
        self.assertIn(str(self.ssh_directory / "worker-1.known_hosts"), worker["ansible_ssh_common_args"])
        self.assertNotIn("StrictHostKeyChecking=no", worker["ansible_ssh_common_args"])

    def test_build_inventory_skips_admin_colocated_portal(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "admin-portal": {
                    "node_id": "admin-portal",
                    "node_role": "portal",
                    "public_ip": "192.0.2.1",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                },
            }
        )
        self.credentials("worker-1", "192.0.2.10")
        self.credentials("portal-1", "192.0.2.20")

        inventory = INVENTORY.build_inventory(
            nodes,
            admin_endpoint="192.0.2.1",
            current_node_id="worker-1",
            ssh_directory=self.ssh_directory,
        )

        hosts = inventory["all"]["children"]
        self.assertEqual(set(hosts["workers"]["hosts"]), {"worker-1"})
        self.assertEqual(set(hosts["portal"]["hosts"]), {"portal-1"})

    def test_build_rejects_a_host_pin_for_a_different_address(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                },
            }
        )
        self.credentials("worker-1", "192.0.2.11")
        self.credentials("portal-1", "192.0.2.20")

        with self.assertRaisesRegex(INVENTORY.InventoryError, "does not match public_ip"):
            INVENTORY.build_inventory(
                nodes,
                admin_endpoint="192.0.2.1",
                current_node_id="portal-1",
                ssh_directory=self.ssh_directory,
            )

    def test_build_rejects_group_accessible_private_key(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                },
            }
        )
        self.credentials("worker-1", "192.0.2.10")
        self.credentials("portal-1", "192.0.2.20")
        (self.ssh_directory / "worker-1.ed25519").chmod(0o640)

        with self.assertRaisesRegex(INVENTORY.InventoryError, "not be accessible by group"):
            INVENTORY.build_inventory(
                nodes,
                admin_endpoint="192.0.2.1",
                current_node_id="portal-1",
                ssh_directory=self.ssh_directory,
            )

    def test_removal_inventory_rejects_an_admin_node(self) -> None:
        nodes = [{"node_id": "admin-1", "role": "admin", "public_ip": "192.0.2.1"}]

        with self.assertRaisesRegex(INVENTORY.InventoryError, "Worker or Portal"):
            INVENTORY.build_inventory(
                nodes,
                admin_endpoint="192.0.2.1",
                current_node_id=None,
                exclude_node_id="admin-1",
                allow_unpaired=True,
                ssh_directory=self.ssh_directory,
            )

    def test_build_waits_for_the_current_spoke_registration(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                }
            }
        )

        with self.assertRaisesRegex(INVENTORY.InventoryError, "not active in know_host.yaml yet"):
            INVENTORY.build_inventory(
                nodes,
                admin_endpoint="192.0.2.1",
                current_node_id="portal-1",
                ssh_directory=self.ssh_directory,
            )

    def test_removal_inventory_excludes_node_and_allows_empty_worker_group(self) -> None:
        nodes = self.write_nodes(
            {
                "worker-1": {
                    "node_id": "worker-1",
                    "node_role": "worker",
                    "public_ip": "192.0.2.10",
                    "status": "active",
                },
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                },
            }
        )
        self.credentials("portal-1", "192.0.2.20")

        inventory = INVENTORY.build_inventory(
            nodes,
            admin_endpoint="192.0.2.1",
            current_node_id=None,
            exclude_node_id="worker-1",
            allow_unpaired=True,
            ssh_directory=self.ssh_directory,
        )

        groups = inventory["all"]["children"]
        self.assertEqual(groups["workers"]["hosts"], {})
        self.assertEqual(set(groups["portal"]["hosts"]), {"portal-1"})

    def test_removal_inventory_rejects_unknown_or_invalid_excluded_node(self) -> None:
        nodes = self.write_nodes(
            {
                "portal-1": {
                    "node_id": "portal-1",
                    "node_role": "portal",
                    "public_ip": "192.0.2.20",
                    "status": "active",
                }
            }
        )
        self.credentials("portal-1", "192.0.2.20")
        for node_id in ("missing-1", "../portal-1"):
            with self.subTest(node_id=node_id):
                with self.assertRaises(INVENTORY.InventoryError):
                    INVENTORY.build_inventory(
                        nodes,
                        admin_endpoint="192.0.2.1",
                        current_node_id=None,
                        exclude_node_id=node_id,
                        allow_unpaired=True,
                        ssh_directory=self.ssh_directory,
                    )


if __name__ == "__main__":
    unittest.main()
