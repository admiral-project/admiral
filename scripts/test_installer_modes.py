#!/usr/bin/env python3
"""Contract checks for explicit Admiral installer node modes."""

from __future__ import annotations

import pathlib
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts" / "install.sh"
PLAYBOOK = ROOT / "ansible" / "site.yml"
FIREWALL_TASKS = ROOT / "ansible" / "roles" / "admiral_firewall" / "tasks" / "main.yml"


class InstallerModeTests(unittest.TestCase):
    def test_installer_help_lists_explicit_admin_portal_mode(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--help"],
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("--admin-portal-node", result.stdout)

    def test_playbook_uses_persistent_roles_without_service_detection(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("/etc/admiral/role", content)
        self.assertIn("'admin-portal-node': 'admin-portal'", content)
        self.assertNotIn("admiral_portal_shares_admin_host", content)
        self.assertNotIn("systemctl is-active --quiet", content)

    def test_role_transition_is_limited_to_dev_to_single(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("admiral_persisted_node_role == admiral_node_role", content)
        self.assertIn("admiral_persisted_node_role == 'dev' and admiral_node_role == 'single'", content)

    def test_firewall_converges_to_the_declared_host_profile(self) -> None:
        content = FIREWALL_TASKS.read_text(encoding="utf-8")

        self.assertIn("Define allowed public firewall rules for the host profile", content)
        self.assertIn("Remove public services outside the declared host profile", content)
        self.assertIn("Remove public ports outside the declared host profile", content)
        self.assertIn("difference(admiral_allowed_public_services)", content)
        self.assertIn("difference(admiral_allowed_public_ports)", content)


if __name__ == "__main__":
    unittest.main()
