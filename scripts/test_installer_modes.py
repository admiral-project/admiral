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
FLEET_TASKS = ROOT / "ansible" / "roles" / "admiral_fleet" / "tasks" / "main.yml"
HARBOR_TASKS = ROOT / "ansible" / "roles" / "admiral_harbor" / "tasks" / "main.yml"
AUDIT_TASKS = ROOT / "ansible" / "roles" / "admiral_auditd" / "tasks" / "main.yml"
COMMON_TASKS = ROOT / "ansible" / "roles" / "admiral_common" / "tasks" / "main.yml"
FAIL2BAN_TASKS = ROOT / "ansible" / "roles" / "admiral_fail2ban" / "tasks" / "main.yml"
ADMIRALD_TASKS = ROOT / "ansible" / "roles" / "admirald" / "tasks" / "main.yml"
FLAGSHIP_TASKS = ROOT / "ansible" / "roles" / "admiral_flagship" / "tasks" / "main.yml"
SYSADMIN_GUIDE = ROOT / "docs" / "sysadmin_guide.md"
MAKEFILE = ROOT / "Makefile"


class InstallerModeTests(unittest.TestCase):
    def test_all_tier_one_el10_distributions_are_accepted(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("rhel|centos|rocky|almalinux)", content)
        self.assertIn('[[ "$MAJOR" -ge 10 ]]', content)

    def test_fedora_is_limited_to_dev_mode(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("fedora)", content)
        self.assertIn('[[ "$INSTALL_DEV_MODE" == "true" ]]', content)
        self.assertIn("Fedora is supported only with --dev-node", content)

    def test_admiral_common_is_reconciled_to_current_repository_version(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('dnf install -y admiral-common', content)
        self.assertNotIn('if ! rpm -q admiral-common', content)

    def test_installer_help_lists_explicit_admin_portal_mode(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--help"],
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("--admin-portal-node", result.stdout)
        self.assertIn("--yes", result.stdout)

    def test_dev_mode_requires_explicit_noninteractive_confirmation(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--dev-node"],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--dev-node requires --yes", result.stderr)

    def test_admin_modes_require_explicit_public_ip(self) -> None:
        for mode in ("--admin-node", "--admin-portal-node"):
            with self.subTest(mode=mode):
                result = subprocess.run(
                    ["bash", str(INSTALLER), mode],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requires --public-ip", result.stderr)

    def test_every_value_option_reports_a_missing_value(self) -> None:
        for option in (
            "--node-id",
            "--public-ip",
            "--wireguard-ip",
            "--admin-endpoint",
            "--ssh-user",
            "--ssh-key",
            "--ssh-fingerprint",
        ):
            with self.subTest(option=option):
                result = subprocess.run(
                    ["bash", str(INSTALLER), "--single-node", option],
                    check=False,
                    capture_output=True,
                    text=True,
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"{option} requires a value.", result.stderr)

    def test_empty_option_value_is_rejected(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--single-node", "--node-id", ""],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--node-id requires a value.", result.stderr)

    def test_unknown_option_is_rejected(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--single-node", "--not-an-option"],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unknown argument: --not-an-option", result.stderr)

    def test_malformed_ssh_fingerprint_is_rejected(self) -> None:
        result = subprocess.run(
            [
                "bash",
                str(INSTALLER),
                "--single-node",
                "--ssh-fingerprint",
                "SHA256:not-a-complete-fingerprint",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("complete OpenSSH SHA256 fingerprint", result.stderr)

    def test_remote_ssh_uses_only_the_verified_temporary_host_key(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("TMP_KNOWN_HOSTS=", content)
        self.assertIn("UserKnownHostsFile=$TMP_KNOWN_HOSTS", content)
        self.assertIn("UserKnownHostsFile={os.environ['TMP_KNOWN_HOSTS']}", content)
        self.assertNotIn('KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"', content)
        self.assertNotIn('ssh -i "$INSTALL_TARGET_SSH_KEY"', content)

    def test_spoke_extra_vars_exclude_controller_admin_token(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        fleet = FLEET_TASKS.read_text(encoding="utf-8")
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")

        self.assertNotIn("SECRETS_ADMIRAL_TOKEN", installer)
        self.assertNotIn("SECRETS_TASK_ENCRYPTION_KEY", installer)
        self.assertNotIn("ADMIRAL_TASK_ENCRYPTION_KEY", fleet)
        self.assertNotIn('read_admiral_secret "ADMIRAL_POSTGRES_PASSWORD"', installer)
        self.assertIn('SECRETS_HARBOR_POSTGRES_USER="admiral_portal"', installer)
        self.assertNotIn("ADMIRAL_ADMIN_TOKEN", fleet)
        self.assertNotIn("ADMIRAL_ADMIN_TOKEN", harbor)
        self.assertIn("ADMIRAL_TASK_PUBLIC_KEY={{ admiral_task_public_key_value }}", fleet)
        self.assertIn("fleet_existing_node_token not in ['', '__REQUIRED__']", fleet)
        self.assertIn("admiral_fleet_token_value | default", fleet)
        self.assertIn("no_log: true", fleet)
        self.assertIn("no_log: true", harbor)

    def test_service_configuration_changes_are_applied_before_dependents(self) -> None:
        fleet = FLEET_TASKS.read_text(encoding="utf-8")
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")
        flagship = FLAGSHIP_TASKS.read_text(encoding="utf-8")

        self.assertIn("Apply admiral-fleet configuration changes before registration", fleet)
        self.assertIn("Apply admiral-harbor configuration changes before bootstrap commands", harbor)
        self.assertIn("Apply admiral-flagship configuration changes before validation", flagship)
        self.assertIn("meta: flush_handlers", fleet)
        self.assertIn("meta: flush_handlers", harbor)
        self.assertIn("meta: flush_handlers", flagship)

    def test_dev_to_single_removes_insecure_overrides_and_ports(self) -> None:
        admirald = ADMIRALD_TASKS.read_text(encoding="utf-8")
        flagship = FLAGSHIP_TASKS.read_text(encoding="utf-8")
        firewall = FIREWALL_TASKS.read_text(encoding="utf-8")

        self.assertIn("Remove development mode override on secure reconciliation", admirald)
        self.assertIn("Remove legacy admiral-flagship systemd override", flagship)
        self.assertIn("40000-49999/tcp", firewall)
        self.assertIn("difference(admiral_allowed_public_ports)", firewall)

    def test_audit_fallback_and_all_expected_keys_are_blocking(self) -> None:
        content = AUDIT_TASKS.read_text(encoding="utf-8")

        self.assertIn("when: audit_augenrules.rc != 0", content)
        for key in (
            "admiral_config",
            "admiral_secrets",
            "admiral_tls",
            "admiral_data",
            "admiral_wireguard",
        ):
            self.assertIn(f"'{key}' not in admiral_audit_rules_effective.stdout", content)

    def test_external_sources_are_checksum_verified(self) -> None:
        content = MAKEFILE.read_text(encoding="utf-8")

        self.assertIn("define download_checked", content)
        self.assertIn("sha256sum -c -", content)
        self.assertEqual(content.count("$(call download_checked,"), 6)

    def test_harbor_database_requires_tls(self) -> None:
        content = HARBOR_TASKS.read_text(encoding="utf-8")

        self.assertIn("sslmode=require", content)
        self.assertNotIn("sslmode=prefer", content)
        self.assertNotIn("sslmode=disable", content)

    def test_harbor_scoped_token_is_configured_on_both_sides(self) -> None:
        admirald = ADMIRALD_TASKS.read_text(encoding="utf-8")
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn(
            "harbor_api_token = {{ admirald_harbor_api_token | default(admiral_harbor_api_token_value) }}",
            admirald,
        )
        self.assertIn(
            "ADMIRAL_HARBOR_API_TOKEN={{ admiral_harbor_api_token_value }}",
            harbor,
        )
        self.assertIn("harborctl ping", installer)

    def test_single_node_requires_all_harbor_timers(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        runtime_checks = installer.split("# --- 11. verify core runtime ---", 1)[1]
        service_matrix = runtime_checks.split('case "$INSTALL_MODE" in', 1)[1]
        single_node_services = service_matrix.split("single-node)", 1)[1].split(";;", 1)[0]

        self.assertIn("admiral-harbor-worker.timer", single_node_services)
        self.assertIn("admiral-harbor-catalog-sync.timer", single_node_services)

    def test_dedicated_portal_verifies_harbor_authentication_remotely(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('portal-node)\n        info "Verifying remote Harbor authentication', installer)
        self.assertIn('"sudo -n /usr/bin/harborctl ping"', installer)
        self.assertIn("Remote Harbor cannot authenticate with the Admiral API", installer)

    def test_sysadmin_guide_provisions_spokes_from_admin(self) -> None:
        content = SYSADMIN_GUIDE.read_text(encoding="utf-8")

        self.assertIn("All worker and dedicated portal provisioning is initiated", content)
        self.assertIn("sudo admiral_install --portal-node", content)
        self.assertIn("sudo admiral_install --worker-node", content)
        self.assertIn("--admin-portal-node", content)
        self.assertIn("--single-node", content)
        self.assertIn("--dev-node", content)

    def test_playbook_uses_persistent_roles_without_service_detection(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("/etc/admiral/role", content)
        self.assertIn("'admin-portal-node': 'admin-portal'", content)
        self.assertNotIn("admiral_portal_shares_admin_host", content)
        self.assertNotIn("systemctl is-active --quiet", content)

    def test_role_preflight_runs_before_package_or_repository_changes(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        mutation_offset = installer.index("dnf install -y epel-release")

        self.assertLess(installer.index('preflight_local_node_role "$REQUESTED_NODE_ROLE"'), mutation_offset)
        self.assertLess(installer.index('preflight_remote_node_role "$REQUESTED_NODE_ROLE"'), mutation_offset)
        self.assertIn("Refusing to modify packages or repositories", installer)

    def test_secure_role_preflight_preserves_dev_mode_behavior(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('if [[ "$INSTALL_DEV_MODE" != "true" ]]', installer)
        self.assertIn('[[ "$requested_role" == "single" ]] && return 0', installer)

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

    def test_spoke_egress_allows_only_declared_dns_and_https_endpoints(self) -> None:
        content = FIREWALL_TASKS.read_text(encoding="utf-8")

        template = (ROOT / "ansible" / "roles" / "admiral_firewall" / "templates" / "admiral-egress.nft.j2").read_text(encoding="utf-8")

        self.assertIn("tcp dport 53 accept", template)
        self.assertIn("udp dport 53 accept", template)
        self.assertIn("tcp dport { 443, 587 } accept", template)
        self.assertIn("Kubernetes model", template)
        self.assertIn("ip daddr 10.99.0.0/24 accept", template)

    def test_secure_checklist_validates_runtime_controls(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("ss -H -lntu", installer)
        self.assertIn("auditctl -l", installer)
        self.assertIn("fail2ban-client ping", installer)
        self.assertIn("fail2ban-client get sshd actions", installer)
        self.assertIn("dnf-automatic.timer", installer)
        self.assertIn("nft list chain inet admiral_egress output", installer)

    def test_security_updates_and_effective_bans_are_enforced(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        common = COMMON_TASKS.read_text(encoding="utf-8")
        fail2ban = FAIL2BAN_TASKS.read_text(encoding="utf-8")

        self.assertIn("Apply available security updates", common)
        self.assertIn("security: true", common)
        self.assertIn("name: dnf-automatic", common)
        self.assertIn("name: dnf-automatic.timer", common)
        self.assertIn("ansible_distribution in ['RedHat', 'CentOS', 'Rocky', 'AlmaLinux']", common)
        self.assertIn("ansible_distribution_major_version | int == 10", common)
        self.assertIn("not (admiral_dev_mode | default(false) | bool)", common)
        self.assertIn("banaction = nftables[type=allports]", fail2ban)
        self.assertIn("Exercise Fail2ban nftables enforcement", fail2ban)
        self.assertIn("nft list ruleset", fail2ban)
        self.assertIn("gpgcheck", installer)


if __name__ == "__main__":
    unittest.main()
