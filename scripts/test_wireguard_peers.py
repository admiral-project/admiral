#!/usr/bin/env python3
"""Regression checks for the WireGuard peer exchange playbook."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PLAYBOOK = ROOT / "ansible" / "wireguard-peers.yml"
WIREGUARD_ROLE = ROOT / "ansible" / "roles" / "admiral_wireguard"
PEER_LOADER = ROOT / "scripts" / "admiral_wireguard_load_peers.sh"
WIREGUARD_FILTER = ROOT / "ansible" / "filter_plugins" / "admiral_wireguard.py"
WIREGUARD_FILTER_SPEC = importlib.util.spec_from_file_location("admiral_wireguard_filter", WIREGUARD_FILTER)
assert WIREGUARD_FILTER_SPEC is not None and WIREGUARD_FILTER_SPEC.loader is not None
WIREGUARD_FILTER_MODULE = importlib.util.module_from_spec(WIREGUARD_FILTER_SPEC)
WIREGUARD_FILTER_SPEC.loader.exec_module(WIREGUARD_FILTER_MODULE)


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

    def test_peer_preshared_keys_are_generated_preserved_and_hidden(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("wg genpsk", content)
        self.assertIn("node_wg_preshared_key", content)
        self.assertIn("PresharedKey = {{ node_wg_preshared_key }}", content)
        self.assertIn("no_log: true", content)
        self.assertIn("regex_findall('(?m)^PresharedKey", content)
        template = (ROOT / "ansible/roles/admiral_wireguard/templates/wg-admiral.conf.j2").read_text(encoding="utf-8")
        self.assertIn("PresharedKey = {{ admiral_wireguard_preshared_key", template)

    def test_hub_template_preserves_durable_peer_fragments(self) -> None:
        template = (ROOT / "ansible" / "roles" / "admiral_wireguard" / "templates" / "wg-admiral.conf.j2").read_text(encoding="utf-8")
        self.assertIn("admiral_wireguard_role == 'hub'", template)
        self.assertIn("admiral_existing_wireguard_peer_fragments", template)
        self.assertIn("peer.preshared_key", template)

    def test_spoke_reconciliation_preserves_existing_hub_preshared_key(self) -> None:
        tasks = (WIREGUARD_ROLE / "tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("Read existing spoke WireGuard configuration", tasks)
        self.assertIn("Extract the existing hub preshared key from spoke configuration", tasks)
        self.assertIn("admiral_wireguard_hub_public_key | regex_escape", tasks)
        self.assertIn("Preserve the existing hub preshared key during spoke reconciliation", tasks)
        self.assertIn("admiral_wireguard_preshared_key:", tasks)
        self.assertIn("no_log: true", tasks)

    def test_direct_restore_peers_are_exact_and_firewall_rules_are_reconciled(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")
        template = (WIREGUARD_ROLE / "templates/wg-admiral.conf.j2").read_text(encoding="utf-8")

        self.assertIn("Select dedicated Portal and Worker peers for uploaded restores", content)
        self.assertIn("AllowedIPs = {{ peer.wireguard_ip }}/32", template)
        self.assertIn("admiral_wireguard_spoke_peers", template)
        self.assertIn('hosts: "portal:!admin"', content)
        self.assertIn("stale_wireguard_harbor_rules", content)
        self.assertIn("Remove stale Worker-to-Portal Harbor rules", content)
        self.assertIn('source address="{{ item }}/32"', content)
        self.assertIn('port port="5001" protocol="tcp" accept', content)
        self.assertIn("net.ipv4.ip_forward=0", template)

    def test_hub_startup_loads_durable_peer_fragments(self) -> None:
        template = (WIREGUARD_ROLE / "templates" / "wg-admiral.conf.j2").read_text(encoding="utf-8")
        spec = (ROOT / "packaging/rpm/admiral-common.spec").read_text(encoding="utf-8")

        self.assertIn("PostUp = /usr/libexec/admiral-wireguard-load-peers %i", template)
        self.assertIn("install -Dm0755 scripts/admiral_wireguard_load_peers.sh", spec)
        self.assertIn("%{_libexecdir}/admiral-wireguard-load-peers", spec)
        self.assertEqual(template.count("admiral-wireguard-load-peers %i"), 1)

    def test_peer_revocation_socket_is_enabled_only_on_hubs(self) -> None:
        tasks = (WIREGUARD_ROLE / "tasks/main.yml").read_text(encoding="utf-8")
        socket_unit = (ROOT / "packaging/systemd/admiral-wireguard-peer-revoke.socket").read_text(encoding="utf-8")
        service_unit = (ROOT / "packaging/systemd/admiral-wireguard-peer-revoke@.service").read_text(encoding="utf-8")
        helper = (ROOT / "scripts/admiral_wireguard_revoke_peer.py").read_text(encoding="utf-8")

        self.assertIn("name: admiral-wireguard-peer-revoke.socket", tasks)
        self.assertIn("when: admiral_wireguard_role == 'hub'", tasks)
        self.assertIn("when: admiral_wireguard_role != 'hub'", tasks)
        self.assertIn("SocketUser=admiral", socket_unit)
        self.assertIn("SocketMode=0600", socket_unit)
        self.assertIn("CapabilityBoundingSet=CAP_NET_ADMIN CAP_DAC_READ_SEARCH", service_unit)
        self.assertIn("ProtectSystem=strict", service_unit)
        self.assertIn("NoNewPrivileges=yes", service_unit)
        self.assertIn("RuntimeMaxSec=60s", service_unit)
        self.assertIn("AF_INET AF_INET6", service_unit)
        self.assertIn("def revoke_peer(", helper)
        self.assertIn("_run_peer_playbook(inventory, extra_vars)", helper)

    def test_spoke_peer_add_rechecks_registration_under_shared_lock(self) -> None:
        installer = (ROOT / "scripts/install.sh").read_text(encoding="utf-8")
        helper = (ROOT / "scripts/admiral_wireguard_peer_add.py").read_text(encoding="utf-8")
        fleet = (ROOT / "ansible/roles/admiral_fleet/tasks/main.yml").read_text(encoding="utf-8")
        self.assertIn("/usr/libexec/admiral-wireguard-peer-add", installer)
        self.assertIn("export ADMIRAL_INTERNAL_TOKEN=\"$CONTROLLER_ADMIN_TOKEN\"", installer)
        self.assertIn("fcntl.flock(lock_fd, fcntl.LOCK_EX)", helper)
        self.assertIn("_registered_node(item_id, item_ip, os.environ)", helper)
        self.assertIn("/usr/libexec/admiral-wireguard-peer-add", fleet)
        self.assertNotIn("wg set wg-admiral peer", installer)

    def test_installer_serializes_automatic_spoke_reconciliation(self) -> None:
        installer = (ROOT / "scripts/install.sh").read_text(encoding="utf-8")

        self.assertIn("flock -x \"$PEER_LOCK_FD\"", installer)
        self.assertIn("/run/lock/admiral-wireguard-peer-add.lock", installer)
        self.assertIn('PEER_SYNC_REQUIRED="true"', installer)
        self.assertIn('"$ANSIBLE_DIR/wireguard-peers.yml"', installer)

    def test_peer_loader_replays_fragments_in_order_without_leaking_wg_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = pathlib.Path(temp_dir)
            fake_bin = temp / "bin"
            peer_dir = temp / "peers.d"
            fake_bin.mkdir()
            peer_dir.mkdir()
            (peer_dir / "z-worker.conf").write_text("[Peer]\nPresharedKey = secret-z\n", encoding="utf-8")
            (peer_dir / "a-worker.conf").write_text("[Peer]\nPresharedKey = secret-a\n", encoding="utf-8")
            (peer_dir / "ignored.txt").write_text("not a peer", encoding="utf-8")
            calls = temp / "calls"
            wg_stub = fake_bin / "wg"
            wg_stub.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$WG_CALLS\"\nprintf '%s\\n' 'wg secret output' >&2\n",
                encoding="utf-8",
            )
            wg_stub.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
            env["WG_CALLS"] = str(calls)

            result = subprocess.run(
                ["bash", str(PEER_LOADER), "wg-admiral", str(peer_dir)],
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                calls.read_text(encoding="utf-8").splitlines(),
                [
                    f"addconf wg-admiral {peer_dir / 'a-worker.conf'}",
                    f"addconf wg-admiral {peer_dir / 'z-worker.conf'}",
                ],
            )
            self.assertNotIn("secret", result.stdout + result.stderr)

    def test_peer_loader_reports_failures_without_exposing_peer_contents(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = pathlib.Path(temp_dir)
            fake_bin = temp / "bin"
            peer_dir = temp / "peers.d"
            fake_bin.mkdir()
            peer_dir.mkdir()
            (peer_dir / "worker.conf").write_text("PresharedKey = private-material\n", encoding="utf-8")
            wg_stub = fake_bin / "wg"
            wg_stub.write_text("#!/bin/sh\nprintf '%s\\n' 'private-material' >&2\nexit 1\n", encoding="utf-8")
            wg_stub.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"

            result = subprocess.run(
                ["bash", str(PEER_LOADER), "wg-admiral", str(peer_dir)],
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("worker.conf", result.stderr)
            self.assertNotIn("private-material", result.stdout + result.stderr)

    def test_peer_loader_rejects_invalid_interface_and_missing_directory(self) -> None:
        invalid = subprocess.run(
            ["bash", str(PEER_LOADER), "wg0"],
            text=True,
            capture_output=True,
            check=False,
        )
        missing = subprocess.run(
            ["bash", str(PEER_LOADER), "wg-admiral", "/path/that/does/not/exist"],
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(invalid.returncode, 2)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("directory is missing", missing.stderr)

    def test_wireguard_firewall_uses_configured_subnet_and_peer_setup_is_idempotent(self) -> None:
        defaults = (ROOT / "ansible/roles/admiral_wireguard/defaults/main.yml").read_text(encoding="utf-8")
        wireguard_tasks = (ROOT / "ansible/roles/admiral_wireguard/tasks/main.yml").read_text(encoding="utf-8")
        fleet_tasks = (ROOT / "ansible/roles/admiral_fleet/tasks/main.yml").read_text(encoding="utf-8")
        template = (ROOT / "ansible/roles/admiral_wireguard/templates/wg-admiral.conf.j2").read_text(encoding="utf-8")

        self.assertIn('admiral_wireguard_subnet: "10.99.0.0/24"', defaults)
        self.assertEqual(wireguard_tasks.count('{{ admiral_wireguard_subnet }}'), 3)
        self.assertIn('admiral_wireguard_hub_ip: "{{ admiral_wireguard_subnet | wireguard_hub_ip }}"', defaults)
        self.assertEqual(wireguard_tasks.count('source address="{{ admiral_wireguard_hub_ip }}"'), 2)
        self.assertNotIn('source address="10.99.0.1"', wireguard_tasks)
        self.assertIn("admiral_wireguard_subnet.split('/')[-1]", template)
        self.assertIn("AllowedIPs = {{ admiral_wireguard_hub_ip }}/32", template)
        self.assertIn("Require the hub WireGuard interface before registering the worker", fleet_tasks)
        self.assertIn("Add and persist the registered worker peer under the shared WireGuard lock", fleet_tasks)
        self.assertIn("/usr/libexec/admiral-wireguard-peer-add", fleet_tasks)
        self.assertIn("changed_when: admiral_wireguard_peer_add_result.stdout == 'changed'", fleet_tasks)

    def test_wireguard_hub_address_is_derived_from_custom_subnet(self) -> None:
        derive_hub_ip = WIREGUARD_FILTER_MODULE.wireguard_hub_ip

        self.assertEqual(derive_hub_ip("10.99.0.0/24"), "10.99.0.1")
        self.assertEqual(derive_hub_ip("192.168.44.128/26"), "192.168.44.129")
        with self.assertRaisesRegex(ValueError, "must be IPv4"):
            derive_hub_ip("fd00::/64")
        with self.assertRaisesRegex(ValueError, "RFC1918"):
            derive_hub_ip("203.0.113.0/24")
        with self.assertRaisesRegex(ValueError, "at least one peer"):
            derive_hub_ip("10.99.0.4/32")

    def test_stale_portal_harbor_rules_remove_only_unregistered_wireguard_hosts(self) -> None:
        stale_rules = WIREGUARD_FILTER_MODULE.stale_wireguard_harbor_rules
        hub = 'rule family="ipv4" source address="10.99.0.1" port port="5001" protocol="tcp" accept'
        worker = 'rule family="ipv4" source address="10.99.0.2/32" port port="5001" protocol="tcp" accept'
        stale_worker = 'rule family="ipv4" source address="10.99.0.3/32" port port="5001" protocol="tcp" accept'
        other_port = 'rule family="ipv4" source address="10.99.0.4/32" port port="8080" protocol="tcp" accept'
        external = 'rule family="ipv4" source address="192.0.2.8/32" port port="5001" protocol="tcp" accept'

        self.assertEqual(
            stale_rules([hub, worker, stale_worker, other_port, external], ["10.99.0.2"], "10.99.0.0/24", "10.99.0.1"),
            [stale_worker],
        )

    def test_installer_passes_custom_wireguard_network_to_every_ansible_run(self) -> None:
        installer = (ROOT / "scripts" / "install.sh").read_text(encoding="utf-8")
        harbor_tasks = (ROOT / "ansible" / "roles" / "admiral_harbor" / "tasks" / "main.yml").read_text(encoding="utf-8")
        firewall_tasks = (ROOT / "ansible" / "roles" / "admiral_firewall" / "tasks" / "main.yml").read_text(encoding="utf-8")
        egress_template = (ROOT / "ansible" / "roles" / "admiral_firewall" / "templates" / "admiral-egress.nft.j2").read_text(encoding="utf-8")

        self.assertIn(
            'INSTALL_WIREGUARD_SUBNET="${ADMIRAL_WIREGUARD_SUBNET:-$(read_install_state_value ADMIRAL_WIREGUARD_SUBNET || printf \'%s\' \'10.99.0.0/24\')}"',
            installer,
        )
        self.assertIn('"ADMIRAL_WIREGUARD_SUBNET": os.environ["INSTALL_STATE_WIREGUARD_SUBNET"]', installer)
        self.assertIn('"ADMIRAL_WIREGUARD_HUB_IP": os.environ["INSTALL_STATE_WIREGUARD_HUB_IP"]', installer)
        self.assertIn('ADMIRAL_WIREGUARD_SUBNET="$INSTALL_WIREGUARD_SUBNET"', installer)
        self.assertIn('"admiral_wireguard_subnet": os.environ["INSTALL_STATE_WIREGUARD_SUBNET"]', installer)
        self.assertIn('"admiral_wireguard_hub_ip": os.environ["INSTALL_STATE_WIREGUARD_HUB_IP"]', installer)
        self.assertIn('"https://{{ admiral_admin_wireguard_ip | default(admiral_admin_endpoint | default(admiral_wireguard_hub_ip)) }}:8080"', harbor_tasks)
        self.assertEqual(firewall_tasks.count('rule: "-d {{ admiral_wireguard_subnet }} -j ACCEPT"'), 4)
        self.assertIn("ip daddr {{ admiral_wireguard_subnet }} accept", egress_template)


if __name__ == "__main__":
    unittest.main()
