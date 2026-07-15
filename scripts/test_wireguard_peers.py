#!/usr/bin/env python3
"""Regression checks for the WireGuard peer exchange playbook."""

from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PLAYBOOK = ROOT / "ansible" / "wireguard-peers.yml"


class WireGuardPeerExchangeTests(unittest.TestCase):
    def test_peer_files_are_managed_on_hub_and_keys_on_nodes(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("delegate_to: \"{{ hub_host }}\"", content)
        self.assertIn("Find peer config files on hub", content)
        self.assertIn("hub_peer_file_paths.files | map(attribute='path') | list", content)
        self.assertIn("Read WireGuard private key from node", content)
        self.assertIn("node_wg_private_key", content)
        self.assertNotIn("query('fileglob'", content)
        self.assertNotIn("lookup('file', '/etc/wireguard/admiral.key')", content)


if __name__ == "__main__":
    unittest.main()
