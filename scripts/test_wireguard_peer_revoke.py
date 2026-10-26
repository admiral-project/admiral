#!/usr/bin/env python3
"""Unit tests for the privileged WireGuard peer revocation helper."""

from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "admiral_wireguard_revoke_peer", ROOT / "scripts" / "admiral_wireguard_revoke_peer.py"
)
assert SPEC is not None and SPEC.loader is not None
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class WireGuardPeerRevokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp_dir.name)
        self.config = self.root / "wg-admiral.conf"
        self.peer_dir = self.root / "peers.d"
        self.peer_dir.mkdir()
        self.lock = self.root / "run" / "admiral-wireguard-peer-add.lock"
        self.config.write_text(
            "[Interface]\nAddress = 10.99.0.1/24\nPrivateKey = hidden\n\n"
            "# ADMIRAL WORKER PEER worker-001\n[Peer]\n"
            "PublicKey = public-key-worker-001\nAllowedIPs = 10.99.0.3/32\n",
            encoding="utf-8",
        )
        (self.peer_dir / "worker-001.conf").write_text(
            "[Peer]\nPublicKey = public-key-worker-001\nAllowedIPs = 10.99.0.3/32\n",
            encoding="utf-8",
        )
        self.live_peers = {"public-key-worker-001": "10.99.0.3/32"}
        self.commands: list[list[str]] = []

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def runner(self, command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
        self.commands.append(command)
        if command[:5] == ["ip", "-o", "-4", "addr", "show"]:
            return subprocess.CompletedProcess(command, 0, "2: wg-admiral inet 10.99.0.1/24 scope global wg-admiral\n", "")
        if command == ["wg", "show", "interfaces"]:
            return subprocess.CompletedProcess(command, 0, "wg-admiral\n", "")
        if command == ["wg", "show", "wg-admiral", "allowed-ips"]:
            rows = "".join(f"{key}\t{value}\n" for key, value in self.live_peers.items())
            return subprocess.CompletedProcess(command, 0, rows, "")
        if command[:3] == ["wg", "set", "wg-admiral"]:
            key = command[4]
            self.live_peers.pop(key, None)
            return subprocess.CompletedProcess(command, 0, "", "")
        raise AssertionError(f"unexpected command: {command}")

    def test_revokes_live_and_persistent_peer_idempotently(self) -> None:
        result = HELPER.revoke_peer(
            "10.99.0.3",
            config=self.config,
            peer_dir=self.peer_dir,
            lock=self.lock,
            run=self.runner,
        )

        self.assertEqual(result["live_peers_removed"], 1)
        self.assertEqual(result["persistent_peer_entries_removed"], 2)
        self.assertNotIn("10.99.0.3/32", self.config.read_text(encoding="utf-8"))
        self.assertFalse((self.peer_dir / "worker-001.conf").exists())
        self.assertEqual(self.live_peers, {})
        self.assertTrue(self.lock.exists())

        second = HELPER.revoke_peer(
            "10.99.0.3",
            config=self.config,
            peer_dir=self.peer_dir,
            lock=self.lock,
            run=self.runner,
        )
        self.assertEqual(second["live_peers_removed"], 0)
        self.assertEqual(second["persistent_peer_entries_removed"], 0)

    def test_refuses_a_peer_with_additional_routes_without_mutating_state(self) -> None:
        self.config.write_text(
            "[Interface]\nAddress = 10.99.0.1/24\nPrivateKey = hidden\n\n"
            "[Peer]\nPublicKey = public-key-worker-001\n"
            "AllowedIPs = 10.99.0.3/32, 10.88.0.0/16\n",
            encoding="utf-8",
        )
        before = self.config.read_text(encoding="utf-8")

        with self.assertRaisesRegex(HELPER.RevocationError, "additional AllowedIPs"):
            HELPER.revoke_peer(
                "10.99.0.3",
                config=self.config,
                peer_dir=self.peer_dir,
                lock=self.lock,
                run=self.runner,
            )

        self.assertEqual(self.config.read_text(encoding="utf-8"), before)
        self.assertEqual(self.live_peers, {"public-key-worker-001": "10.99.0.3/32"})
        self.assertFalse(any(command[:2] == ["wg", "set"] for command in self.commands))

    def test_refuses_a_live_supernet_route_before_mutating_persistent_state(self) -> None:
        self.config.write_text(
            "[Interface]\nAddress = 10.99.0.1/24\nPrivateKey = hidden\n",
            encoding="utf-8",
        )
        (self.peer_dir / "worker-001.conf").unlink()
        self.live_peers["public-key-worker-001"] = "10.99.0.0/24"
        before_config = self.config.read_text(encoding="utf-8")

        with self.assertRaisesRegex(HELPER.RevocationError, "additional AllowedIPs"):
            HELPER.revoke_peer(
                "10.99.0.3",
                config=self.config,
                peer_dir=self.peer_dir,
                lock=self.lock,
                run=self.runner,
            )

        self.assertEqual(self.config.read_text(encoding="utf-8"), before_config)
        self.assertEqual(self.live_peers, {"public-key-worker-001": "10.99.0.0/24"})
        self.assertFalse(any(command[:2] == ["wg", "set"] for command in self.commands))

    def test_ignores_unrelated_live_peer_without_allowed_ips(self) -> None:
        self.live_peers["public-key-without-routes"] = "(none)"

        result = HELPER.revoke_peer(
            "10.99.0.3",
            config=self.config,
            peer_dir=self.peer_dir,
            lock=self.lock,
            run=self.runner,
        )

        self.assertEqual(result["live_peers_removed"], 1)
        self.assertEqual(self.live_peers, {"public-key-without-routes": "(none)"})

    def test_rejects_non_private_or_non_ipv4_addresses(self) -> None:
        for address in ("203.0.113.5", "10.99.0.1", "2001:db8::1", "not-an-ip"):
            with self.subTest(address=address):
                with self.assertRaises(HELPER.RevocationError):
                    HELPER.revoke_peer(
                        address,
                        config=self.config,
                        peer_dir=self.peer_dir,
                        lock=self.lock,
                        run=self.runner,
                    )

    def test_updates_persistent_state_when_wireguard_is_down(self) -> None:
        def down_runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            self.commands.append(command)
            if command[:5] == ["ip", "-o", "-4", "addr", "show"]:
                return subprocess.CompletedProcess(command, 1, "", "Device does not exist")
            if command == ["wg", "show", "interfaces"]:
                return subprocess.CompletedProcess(command, 0, "", "")
            raise AssertionError(f"unexpected command while interface is down: {command}")

        result = HELPER.revoke_peer(
            "10.99.0.3",
            config=self.config,
            peer_dir=self.peer_dir,
            lock=self.lock,
            run=down_runner,
        )

        self.assertEqual(result["live_peers_removed"], 0)
        self.assertEqual(result["persistent_peer_entries_removed"], 2)
        self.assertNotIn("10.99.0.3/32", self.config.read_text(encoding="utf-8"))
        self.assertFalse((self.peer_dir / "worker-001.conf").exists())

    def test_removal_request_requires_exact_active_node_identity(self) -> None:
        inventory = self.root / "know_host.yaml"
        inventory.write_text(
            "version: 1\nnodes:\n  worker-001:\n    node_id: worker-001\n"
            "    node_role: worker\n    wireguard_ip: 10.99.0.3\n    status: active\n",
            encoding="utf-8",
        )
        raw = json.dumps(
            {"node_id": "worker-001", "node_role": "worker", "wireguard_ip": "10.99.0.3"}
        ).encode() + b"\n"

        node_id, target = HELPER._load_removal_request(raw, known_hosts=inventory)

        self.assertEqual(node_id, "worker-001")
        self.assertEqual(str(target), "10.99.0.3")
        for request in (
            {"node_id": "worker-001", "node_role": "portal", "wireguard_ip": "10.99.0.3"},
            {"node_id": "worker-001", "node_role": ["worker"], "wireguard_ip": "10.99.0.3"},
            {"node_id": "worker-001", "node_role": "worker", "wireguard_ip": "10.99.0.4"},
            {"node_id": "../worker-001", "node_role": "worker", "wireguard_ip": "10.99.0.3"},
        ):
            with self.subTest(request=request), self.assertRaises(HELPER.RevocationError):
                HELPER._load_removal_request(json.dumps(request).encode() + b"\n", known_hosts=inventory)

    def test_unreachable_spoke_keeps_hub_peer_revocation_unapplied(self) -> None:
        lock_path = self.root / "peer.lock"
        lock_path.touch()
        lock_fd = os.open(lock_path, os.O_RDWR)
        inventory = self.root / "inventory.json"
        vars_file = self.root / "vars.json"
        config = self.root / "wg-admiral.conf"
        inventory.write_text("{}\n", encoding="utf-8")
        vars_file.write_text("{}\n", encoding="utf-8")
        config.write_text("[Interface]\nAddress = 10.99.0.1/24\n", encoding="utf-8")

        with mock.patch.object(
            HELPER, "_load_removal_request", return_value=("worker-001", HELPER.ipaddress.ip_address("10.99.0.3"))
        ), mock.patch.object(HELPER, "_acquire_peer_lock", return_value=lock_fd), mock.patch.object(
            HELPER, "_build_removal_inventory", return_value=(inventory, vars_file)
        ), mock.patch.object(HELPER, "_interface_network", return_value=(True, HELPER.ipaddress.ip_network("10.99.0.0/24"))), mock.patch.object(
            HELPER, "_run_peer_playbook", side_effect=HELPER.RevocationError("unreachable")
        ), mock.patch.object(HELPER, "CONFIG", config), mock.patch.object(HELPER, "_revoke_peer_under_lock") as revoke:
            with self.assertRaisesRegex(HELPER.RevocationError, "unreachable"):
                HELPER._remove_node_and_reconcile(b"request\n")

        revoke.assert_not_called()
        with self.assertRaises(OSError):
            os.fstat(lock_fd)

    def test_removal_inventory_excludes_target_and_keeps_strict_host_key_policy(self) -> None:
        inventory_output = {
            "all": {
                "children": {
                    "admin": {"hosts": {"admin": {"ansible_connection": "local"}}},
                    "workers": {"hosts": {}},
                    "portal": {
                        "hosts": {
                            "portal-001": {
                                "ansible_ssh_common_args": "-o StrictHostKeyChecking=yes"
                            }
                        }
                    },
                }
            }
        }
        install_state = self.root / "install.env"
        install_state.write_text(
            json.dumps(
                {
                    "ADMIRAL_PUBLIC_IP": "192.0.2.1",
                    "ADMIRAL_WIREGUARD_SUBNET": "10.99.0.0/24",
                    "ADMIRAL_WIREGUARD_HUB_IP": "10.99.0.1",
                }
            ),
            encoding="utf-8",
        )
        result = subprocess.CompletedProcess([], 0, json.dumps(inventory_output), "")
        with mock.patch.object(HELPER.subprocess, "run", return_value=result) as run:
            inventory_path, vars_path = HELPER._build_removal_inventory(
                "worker-001",
                temp_directory=self.root,
                known_hosts=self.root / "know_host.yaml",
                ssh_directory=self.root / "ssh-delivery",
                install_state=install_state,
            )

        self.assertIn("--exclude-node-id", run.call_args.args[0])
        self.assertIn("worker-001", run.call_args.args[0])
        self.assertIn("--allow-unpaired", run.call_args.args[0])
        self.assertEqual(json.loads(inventory_path.read_text(encoding="utf-8")), inventory_output)
        self.assertEqual(
            json.loads(vars_path.read_text(encoding="utf-8")),
            {"admiral_wireguard_subnet": "10.99.0.0/24", "admiral_wireguard_hub_ip": "10.99.0.1"},
        )
        self.assertEqual(inventory_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(vars_path.stat().st_mode & 0o777, 0o600)

    def test_removal_inventory_rejects_an_inventory_that_keeps_target_or_weakens_ssh(self) -> None:
        state = self.root / "install.env"
        state.write_text(
            json.dumps(
                {
                    "ADMIRAL_PUBLIC_IP": "192.0.2.1",
                    "ADMIRAL_WIREGUARD_SUBNET": "10.99.0.0/24",
                    "ADMIRAL_WIREGUARD_HUB_IP": "10.99.0.1",
                }
            ),
            encoding="utf-8",
        )
        invalid_inventories = (
            {"all": {"children": {"workers": {"hosts": {"worker-001": {}}}, "portal": {"hosts": {}}}}},
            {
                "all": {
                    "children": {
                        "workers": {"hosts": {}},
                        "portal": {
                            "hosts": {
                                "portal-001": {
                                    "ansible_ssh_common_args": "-o StrictHostKeyChecking=no"
                                }
                            }
                        },
                    }
                }
            },
        )
        for payload in invalid_inventories:
            with self.subTest(payload=payload), mock.patch.object(
                HELPER.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], 0, json.dumps(payload), ""),
            ), self.assertRaises(HELPER.RevocationError):
                HELPER._build_removal_inventory(
                    "worker-001",
                    temp_directory=self.root,
                    known_hosts=self.root / "know_host.yaml",
                    ssh_directory=self.root / "ssh-delivery",
                    install_state=state,
                )

    def test_peer_playbook_failure_is_reported_without_echoing_command_output(self) -> None:
        playbook = self.root / "wireguard-peers.yml"
        playbook.write_text("---\n", encoding="utf-8")
        inventory = self.root / "inventory.json"
        vars_file = self.root / "vars.json"
        inventory.write_text("{}\n", encoding="utf-8")
        vars_file.write_text("{}\n", encoding="utf-8")
        failed = mock.Mock()
        failed.returncode = 2
        with mock.patch.object(HELPER, "PEER_PLAYBOOK", playbook), mock.patch.object(
            HELPER.subprocess, "Popen", return_value=failed
        ):
            with self.assertRaisesRegex(HELPER.RevocationError, "node remains registered") as caught:
                HELPER._run_peer_playbook(inventory, vars_file)
        self.assertNotIn("secret output", str(caught.exception))

    def test_peer_playbook_timeout_stops_its_process_group(self) -> None:
        playbook = self.root / "wireguard-peers.yml"
        playbook.write_text("---\n", encoding="utf-8")
        inventory = self.root / "inventory.json"
        vars_file = self.root / "vars.json"
        inventory.write_text("{}\n", encoding="utf-8")
        vars_file.write_text("{}\n", encoding="utf-8")
        process = mock.Mock()
        process.pid = 12345
        process.returncode = -15
        process.communicate.side_effect = [
            subprocess.TimeoutExpired("ansible-playbook", 1),
            ("", ""),
        ]
        with mock.patch.object(HELPER, "PEER_PLAYBOOK", playbook), mock.patch.object(
            HELPER.subprocess, "Popen", return_value=process
        ), mock.patch.object(HELPER.os, "killpg") as killpg:
            with self.assertRaisesRegex(HELPER.RevocationError, "timed out and was stopped"):
                HELPER._run_peer_playbook(inventory, vars_file)

        killpg.assert_called_once_with(12345, HELPER.signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
