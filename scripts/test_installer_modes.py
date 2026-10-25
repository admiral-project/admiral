#!/usr/bin/env python3
"""Contract checks for explicit Admiral installer node modes."""

from __future__ import annotations

import pathlib
import os
import re
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts" / "install.sh"
PLAYBOOK = ROOT / "ansible" / "site.yml"
FIREWALL_TASKS = ROOT / "ansible" / "roles" / "admiral_firewall" / "tasks" / "main.yml"
FLEET_TASKS = ROOT / "ansible" / "roles" / "admiral_fleet" / "tasks" / "main.yml"
SELINUX_TASKS = ROOT / "ansible" / "roles" / "admiral_selinux" / "tasks" / "main.yml"
SSH_TUNNEL_TASKS = ROOT / "ansible" / "roles" / "admiral_ssh_tunnel" / "tasks" / "main.yml"
WIREGUARD_TASKS = ROOT / "ansible" / "roles" / "admiral_wireguard" / "tasks" / "main.yml"
HARBOR_TASKS = ROOT / "ansible" / "roles" / "admiral_harbor" / "tasks" / "main.yml"
AUDIT_TASKS = ROOT / "ansible" / "roles" / "admiral_auditd" / "tasks" / "main.yml"
COMMON_TASKS = ROOT / "ansible" / "roles" / "admiral_common" / "tasks" / "main.yml"
COMMON_SPEC = ROOT / "packaging" / "rpm" / "admiral-common.spec"
FAIL2BAN_TASKS = ROOT / "ansible" / "roles" / "admiral_fail2ban" / "tasks" / "main.yml"
ADMIRALD_TASKS = ROOT / "ansible" / "roles" / "admirald" / "tasks" / "main.yml"
FLAGSHIP_TASKS = ROOT / "ansible" / "roles" / "admiral_flagship" / "tasks" / "main.yml"
SYSADMIN_GUIDE = ROOT / "docs" / "sysadmin_guide.md"
MAKEFILE = ROOT / "Makefile"
FLEET_CONFIG = ROOT / "packaging" / "config" / "fleet.env"


class InstallerModeTests(unittest.TestCase):
    def test_curl_to_bash_source_path_is_safe_with_nounset(self) -> None:
        result = subprocess.run(
            ["bash", "-us"],
            input='SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"\nprintf "%s\\n" "$SCRIPT_SOURCE"\n',
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("unbound variable", result.stderr)

    def test_control_ssh_does_not_consume_curl_streamed_installer(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        helper_body = installer.split("ssh_no_stdin() {", 1)[1].split("\n}", 1)[0]
        helper = "ssh_no_stdin() {" + helper_body + "\n}"

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_bin = temp_path / "bin"
            fake_bin.mkdir()
            ssh_stub = fake_bin / "ssh"
            ssh_stub.write_text("#!/bin/sh\ncat > \"$SSH_STDIN_CAPTURE\"\n", encoding="utf-8")
            ssh_stub.chmod(0o755)
            capture = temp_path / "ssh-stdin"
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
            env["SSH_STDIN_CAPTURE"] = str(capture)
            result = subprocess.run(
                ["bash", "-c", f"{helper}\nssh_no_stdin test-host\nIFS= read -r next || exit 10\nprintf '%s\\n' \"$next\"\n"],
                input="installer remainder\n",
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )
            captured_stdin = capture.read_text(encoding="utf-8")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "installer remainder\n")
        self.assertEqual(captured_stdin, "")

    def test_installer_fails_when_ansible_playbook_fails(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertEqual(installer.count('|| die "Ansible playbook failed'), 2)

    def test_spoke_ansible_temp_uses_target_writable_directory(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        temp_setup = installer.split(
            'ANSIBLE_LOCAL_TEMP="$INSTALLER_TEMP_BASE/ansible-local"', 1
        )[1]
        temp_setup = temp_setup.split("ANSIBLE_GALAXY_CACHE_DIR=", 1)[0]

        self.assertIn(
            '[[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]',
            temp_setup,
        )
        self.assertIn('ANSIBLE_REMOTE_TEMP="/tmp"', temp_setup)
        self.assertIn('ANSIBLE_REMOTE_TEMP="$INSTALLER_TEMP_BASE/ansible-remote"', temp_setup)

    def test_audit_role_installs_el10_rule_utilities_and_loads_rules(self) -> None:
        audit_tasks = AUDIT_TASKS.read_text(encoding="utf-8")

        self.assertIn("- audit-rules", audit_tasks)
        self.assertIn("cmd: augenrules --load", audit_tasks)
        self.assertNotIn("service auditd reload", audit_tasks)
        self.assertIn("path: /sbin/augenrules", audit_tasks)
        self.assertIn("path: /sbin/auditctl", audit_tasks)

    def test_all_tier_one_el10_distributions_are_accepted(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("rhel|centos|rocky|almalinux)", content)
        self.assertIn('is_supported_el_version "${VERSION_ID:-}"', content)
        self.assertNotIn('[[ "$MAJOR" -ge 10 ]]', content)

    def test_el_release_guard_accepts_only_el10(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        helper_body = installer.split("is_supported_el_version() {", 1)[1].split("\n}", 1)[0]
        helper = "is_supported_el_version() {" + helper_body + "\n}"
        shell = helper + """
for version in 10 10.0 10.2; do
    is_supported_el_version "$version" || exit 1
done
for version in 8 9 9.6 11 11.0; do
    if is_supported_el_version "$version"; then exit 2; fi
done
"""
        result = subprocess.run(
            ["bash"],
            input=shell,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fedora_44_and_rawhide_are_supported_without_dev_mode(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("fedora)", content)
        self.assertIn("Fedora 44 or Rawhide is required", content)
        self.assertIn("*rawhide*", content)
        self.assertNotIn("Fedora is supported only with --dev-node", content)
        self.assertNotIn("secure production modes require Enterprise Linux 10", content)

    def test_fedora_uses_dnf5_plugins_for_copr_and_security_updates(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        common = COMMON_TASKS.read_text(encoding="utf-8")

        self.assertIn("DNF_COPR_PLUGIN_PACKAGE=dnf5-plugins", installer)
        self.assertIn("dnf5-plugins", common)
        self.assertIn("dnf5-plugin-automatic", common)
        self.assertIn("dnf5-automatic.timer", common)
        self.assertIn("create: true", common)

    def test_rootless_cgroup_selinux_permission_is_configured_after_fleet_install(self) -> None:
        fleet_tasks = FLEET_TASKS.read_text(encoding="utf-8")
        install_position = fleet_tasks.index("- name: Install admiral-fleet")
        boolean_position = fleet_tasks.index(
            "- name: Read SELinux permission for rootless cgroup management"
        )

        self.assertGreater(boolean_position, install_position)
        self.assertIn("container_manage_cgroup", fleet_tasks)
        self.assertIn("- setsebool", fleet_tasks)
        self.assertIn(
            "ansible_facts.get('selinux', {}).get('status', 'disabled') == 'enabled'",
            fleet_tasks,
        )

    def test_cgroup_selinux_check_only_applies_to_workload_nodes(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn(
            '[[ "$INSTALL_MODE" == "single-node" || "$INSTALL_MODE" == "worker-node" ]]',
            content,
        )
        self.assertIn(
            "getsebool container_manage_cgroup",
            content,
        )

    def test_required_selinux_booleans_do_not_hide_configuration_failures(self) -> None:
        common_tasks = SELINUX_TASKS.read_text(encoding="utf-8")
        fleet_tasks = FLEET_TASKS.read_text(encoding="utf-8")
        common_boolean_tasks = common_tasks.split(
            "- name: Read SELinux permission for reverse proxy connections", 1
        )[1]
        fleet_boolean_tasks = fleet_tasks.split(
            "- name: Read SELinux permission for rootless cgroup management", 1
        )[1].split(
            "- name: Allocate non-overlapping subordinate IDs", 1
        )[0]

        self.assertIn("httpd_can_network_connect", common_tasks)
        self.assertNotIn("failed_when: false", common_boolean_tasks)
        self.assertNotIn("container_manage_cgroup", common_tasks)
        self.assertNotIn("failed_when: false", fleet_boolean_tasks)

    def test_selinux_and_wireguard_security_settings_are_verified_after_setup(self) -> None:
        selinux_tasks = SELINUX_TASKS.read_text(encoding="utf-8")
        wireguard_tasks = WIREGUARD_TASKS.read_text(encoding="utf-8")

        self.assertIn("Read SELinux enforcing runtime state", selinux_tasks)
        self.assertIn("getenforce", selinux_tasks)
        self.assertIn("SELINUX=enforcing", selinux_tasks)
        self.assertIn("admiral_selinux_runtime_final.stdout == 'Enforcing'", selinux_tasks)
        self.assertIn("admiral_selinux_config_final.rc == 0", selinux_tasks)
        self.assertIn("Read runtime IP forwarding state after WireGuard start", wireguard_tasks)
        self.assertIn("admiral_wireguard_forwarding_state.results | map(attribute='stdout') | list == ['0', '0']", wireguard_tasks)

    def test_selinux_disabled_boot_is_persistently_corrected_before_runtime_assert(self) -> None:
        selinux_tasks = SELINUX_TASKS.read_text(encoding="utf-8")

        persist = selinux_tasks.index("- name: Persist SELinux enforcing mode across reboots")
        runtime_assert = selinux_tasks.index("- name: Assert SELinux remains enforcing at runtime and after reboot")
        self.assertLess(persist, runtime_assert)
        self.assertIn("regexp: '^\\s*SELINUX\\s*='", selinux_tasks)
        self.assertIn("If SELinux was disabled previously, reboot and relabel", selinux_tasks)
        self.assertNotIn("- name: Fail when SELinux is disabled", selinux_tasks)

    def test_ssh_tunnel_private_key_is_owned_by_service_user_and_private(self) -> None:
        tasks = SSH_TUNNEL_TASKS.read_text(encoding="utf-8")
        key_task = tasks.split(
            "- name: Make SSH tunnel key readable by the service account only", 1
        )[1].split("\n- name:", 1)[0]

        self.assertIn("owner: admiral", key_task)
        self.assertIn("group: admiral", key_task)
        self.assertIn('mode: "0600"', key_task)
        self.assertNotIn("owner: root", key_task)
        self.assertNotIn('mode: "0640"', key_task)

    def test_custom_wireguard_subnet_reaches_portal_and_flagship_health_allowlists(self) -> None:
        harbor_tasks = HARBOR_TASKS.read_text(encoding="utf-8")
        flagship_tasks = (ROOT / "ansible" / "roles" / "admiral_flagship" / "tasks" / "main.yml").read_text(encoding="utf-8")
        admirald_tasks = (ROOT / "ansible" / "roles" / "admirald" / "tasks" / "main.yml").read_text(encoding="utf-8")

        self.assertIn("ADMIRAL_WIREGUARD_SUBNET={{ admiral_wireguard_subnet }}", harbor_tasks)
        self.assertIn("FLAGSHIP_ALLOWED_HEALTH_IPS=127.0.0.1/32,::1/128,{{ admiral_wireguard_subnet }}", flagship_tasks)
        self.assertIn("wireguard_subnet = {{ admiral_wireguard_subnet }}", admirald_tasks)
        self.assertIn("wireguard_hub_ip = {{ admiral_wireguard_hub_ip }}", admirald_tasks)

    def test_admiral_common_is_reconciled_to_current_repository_version(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")

        self.assertIn('dnf install -y admiral-common', content)
        self.assertNotIn('if ! rpm -q admiral-common', content)
        self.assertRegex(
            common_tasks,
            r"- name: Install admiral-common baseline package",
        )
        # The default keeps reconciling admiral-common to the repository
        # release; defining admiral_common_version pins an exact version.
        self.assertIn("else 'latest'", common_tasks)
        self.assertIn("admiral_common_version", common_tasks)

    def test_installer_help_lists_explicit_admin_portal_mode(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--help"],
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("--admin-portal-node", result.stdout)
        self.assertIn("--yes", result.stdout)
        self.assertIn("--validation-seed", result.stdout)

    def test_validation_seed_flag_is_explicit_and_skips_only_update_transactions(self) -> None:
        result = subprocess.run(
            ["bash", str(INSTALLER), "--validation-seed"],
            check=False,
            capture_output=True,
            text=True,
        )
        installer = INSTALLER.read_text(encoding="utf-8")
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")

        # Parsing the flag without an installation mode must reach the mode
        # validation error, not reject the flag as unknown or mutate the host.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("An installation mode is required", result.stderr)
        self.assertNotIn("Unknown argument", result.stderr)
        self.assertIn('INSTALL_VALIDATION_SEED="false"', installer)
        update_section = installer.split("# Normalize the base operating system", 1)[1].split(
            "# --- 3. verify Python 3 ---", 1
        )[0]
        self.assertIn('if [[ "$INSTALL_VALIDATION_SEED" == "true" ]]', update_section)
        self.assertIn(
            'info "Applying available system updates before Admiral setup..."',
            update_section,
        )
        self.assertIn("dnf -y update --refresh --allowerasing", update_section)
        self.assertIn('warn "Validation seed mode skips base OS and security update transactions;', installer)
        self.assertIn(
            'Skipping OS update transactions for the explicitly selected, recently updated validation seed.',
            installer,
        )
        self.assertIn('d["admiral_validation_seed"] = True', installer)
        security_update_task = common_tasks.split(
            "- name: Apply available security updates", 1
        )[1].split("\n- name:", 1)[0]
        self.assertIn("not (admiral_validation_seed | default(false) | bool)", security_update_task)

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
            "--ssh-public-key",
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

    def test_local_bootstrap_accepts_validated_public_keys(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("--ssh-public-key", content)
        self.assertIn("read_public_key_file()", content)
        self.assertIn("read_invoking_user_public_key()", content)
        self.assertIn("subprocess.run(", content)
        self.assertIn('["ssh-keygen", "-lf", "-"]', content)
        self.assertIn('actual_uid=$(id -u "$invoking_user"', content)
        self.assertIn('"$invoking_home/.ssh/authorized_keys"', content)

    def test_remote_ssh_uses_only_the_verified_temporary_host_key(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("TMP_KNOWN_HOSTS=", content)
        self.assertIn("UserKnownHostsFile=$TMP_KNOWN_HOSTS", content)
        self.assertIn("UserKnownHostsFile={os.environ['TMP_KNOWN_HOSTS']}", content)
        self.assertNotIn('KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"', content)
        self.assertIn("ADMIN_SSH_DELIVERY_KEY=", content)
        self.assertIn('REMOTE_SSH_USER="admiral-ssh"', content)
        self.assertIn("BOOTSTRAP_SSH_PUB_KEY=", content)

    def test_remote_bootstrap_is_retained_until_handshake_then_revoked(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("seq 1 12", content)
        self.assertIn("systemctl restart admiral-fleet", content)
        self.assertIn("systemctl restart admiral-harbor", content)
        self.assertIn("revoke bootstrap SSH access only after complete onboarding", content)
        self.assertIn("Bootstrap SSH credential is still accepted after revocation", content)
        self.assertIn('<<<"PermitRootLogin no"', content)

    def test_spoke_reconvergence_uses_delivery_key_and_skips_bootstrap_probe(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('INSTALL_RECONVERGE_SSH_KEY="true"', content)
        self.assertIn("/var/lib/admiral/ssh-delivery/", content)
        self.assertIn("Using per-node delivery key for spoke reconvergence", content)
        self.assertIn('[[ "$INSTALL_RECONVERGE_SSH_KEY" != "true" ]] && ssh_no_stdin -i', content)

    def test_bootstrap_key_revocation_is_idempotent(self) -> None:
        content = (ROOT / "scripts" / "admiral_revoke_bootstrap_key.py").read_text(encoding="utf-8")

        self.assertIn('print("bootstrap public key was not found in authorized_keys", file=sys.stderr)', content)
        self.assertIn("return 0", content)

    def test_public_listener_check_excludes_private_and_link_local_ranges(self) -> None:
        content = INSTALLER.read_text(encoding="utf-8")

        self.assertNotIn("\npublic_listeners() {", content)

        for pattern in (
            r"^172\\.(1[6-9]|2[0-9]|3[0-1])\\.",
            r"^192\\.168\\.",
            r"^169\\.254\\.",
        ):
            self.assertIn(pattern, content)

    def test_fleet_defaults_do_not_declare_unused_queue_database_url(self) -> None:
        content = FLEET_CONFIG.read_text(encoding="utf-8")

        self.assertNotIn("ADMIRAL_QUEUE_DATABASE_URL", content)

    def test_spoke_uses_fixed_per_node_administrative_identity(self) -> None:
        common = COMMON_TASKS.read_text(encoding="utf-8")
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('admiral_ssh_admin_user: "admiral-ssh"', common)
        self.assertIn("Generate per-node administrative SSH identity on the Admin controller", common)
        self.assertIn("/var/lib/admiral/ssh-delivery/", common)
        self.assertNotIn('SECRETS_SSH_USER=$(read_admiral_secret "ADMIRAL_SSH_USER")', installer)

    def test_spoke_security_check_accepts_final_root_lockdown_on_rerun(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('"$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node"', installer)
        self.assertIn('"$SSHD_EFFECTIVE" == *"permitrootlogin no"*', installer)
        self.assertIn("already onboarded spoke", installer)

    def test_sshd_effective_settings_are_normalized_for_case_insensitive_output(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn(
            'SSHD_EFFECTIVE="$(run_target_cmd "sshd -T" | tr \'[:upper:]\' \'[:lower:]\')"',
            installer,
        )

    def test_spoke_retries_per_node_ssh_after_bootstrap_revocation(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("per_node_ssh_ready=false", installer)
        self.assertIn("for attempt in $(seq 1 10)", installer)
        self.assertIn('ssh_no_stdin "${SSH_OPTIONS[@]}" "${INSTALL_TARGET_SSH_USER}@${INSTALL_PUBLIC_IP}" "sudo -n true"', installer)
        self.assertIn('sleep 1', installer)

    def test_spoke_extra_vars_exclude_controller_admin_token(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        fleet = FLEET_TASKS.read_text(encoding="utf-8")
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")

        self.assertNotIn("SECRETS_ADMIRAL_TOKEN", installer)
        self.assertNotIn("SECRETS_TASK_ENCRYPTION_KEY", installer)
        self.assertNotIn("ADMIRAL_TASK_ENCRYPTION_KEY", fleet)
        self.assertNotIn('read_admiral_secret "ADMIRAL_POSTGRES_PASSWORD"', installer)
        self.assertIn('SECRETS_HARBOR_POSTGRES_USER="admiral_portal"', installer)
        # The controller token is needed only for the registration command;
        # it must not be rendered into the spoke service configuration.
        self.assertIn("ADMIRAL_INTERNAL_TOKEN", fleet)
        self.assertIn("ADMIRAL_INTERNAL_TOKEN", harbor)
        self.assertIn('environment:\n    ADMIRAL_SERVER_URL:', fleet)
        self.assertIn("ADMIRAL_API_URL=", harbor)
        self.assertIn("ADMIRAL_TASK_PUBLIC_KEY={{ admiral_task_public_key_value }}", fleet)
        self.assertIn("fleet_existing_node_token not in ['', '__REQUIRED__']", fleet)
        self.assertIn("admiral_fleet_token_value | default", fleet)
        self.assertIn("no_log: true", fleet)
        self.assertIn("no_log: true", harbor)

    def test_worker_receives_fleet_callback_key_without_logging_it(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('read_admiral_secret "ADMIRAL_FLEET_CALLBACK_KEY"', installer)
        self.assertIn('SECRETS_FLEET_CALLBACK_KEY="$SECRETS_FLEET_CALLBACK_KEY"', installer)
        self.assertIn('d["admiral_fleet_callback_key_value"] = fleet_callback_key', installer)

    def test_service_configuration_changes_are_applied_before_dependents(self) -> None:
        fleet = FLEET_TASKS.read_text(encoding="utf-8")
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")
        flagship = FLAGSHIP_TASKS.read_text(encoding="utf-8")

        self.assertIn("Apply admiral-fleet configuration changes after worker registration", fleet)
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
        dev_mode_task = admirald.split(
            "- name: Set ADMIRAL_ENV=development in dev mode", 1
        )[1].split("\n- name:", 1)[0]
        self.assertIn("Environment=ADMIRAL_DEV_MODE=true", dev_mode_task)
        self.assertIn("Remove legacy admiral-flagship systemd override", flagship)
        self.assertIn(
            "path: /etc/systemd/system/admiral-flagship.service.d/override.conf",
            flagship,
        )
        self.assertNotIn(
            "path: /etc/systemd/system/admiral-flagship.service.d\n    state: absent",
            flagship,
        )
        self.assertIn("40000-49999/tcp", firewall)
        self.assertIn("difference(admiral_allowed_public_ports)", firewall)

    def test_audit_fallback_and_all_expected_keys_are_blocking(self) -> None:
        content = AUDIT_TASKS.read_text(encoding="utf-8")

        self.assertIn(
            "not augenrules_available.stat.exists or (audit_augenrules.rc | default(1)) != 0",
            content,
        )
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
        self.assertEqual(content.count("$(call download_checked,"), 8)
        self.assertIn("FLASK_WHEEL_SHA256 := f4bcbefc124291925f1a26446da31a5178f9483862233b23c0c96a20701f670c", content)

    def test_harbor_database_requires_tls(self) -> None:
        content = HARBOR_TASKS.read_text(encoding="utf-8")

        self.assertIn("sslmode=require", content)
        self.assertNotIn("sslmode=prefer", content)
        self.assertNotIn("sslmode=disable", content)

    def test_harbor_scoped_token_is_configured_on_both_sides(self) -> None:
        admirald = ADMIRALD_TASKS.read_text(encoding="utf-8")
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")
        installer = INSTALLER.read_text(encoding="utf-8")
        harbor_env = (ROOT / "packaging" / "config" / "harbor.env").read_text(encoding="utf-8")

        self.assertIn(
            "harbor_api_token = {{ admirald_harbor_api_token | default(admiral_harbor_api_token_value) }}",
            admirald,
        )
        self.assertIn(
            "ADMIRAL_HARBOR_API_TOKEN={{ admiral_harbor_api_token_value }}",
            harbor,
        )
        self.assertIn("ADMIRAL_HARBOR_API_TOKEN=__REQUIRED__", harbor_env)
        self.assertNotIn("ADMIRAL_INTERNAL_TOKEN=", harbor_env)
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

        self.assertIn('if [[ "$INSTALL_MODE" == "worker-node" || "$INSTALL_MODE" == "portal-node" ]]', installer)
        self.assertIn("for attempt in $(seq 1 12)", installer)
        self.assertIn('"sudo -n /usr/bin/harborctl ping"', installer)
        self.assertIn("restarting admiral-harbor once before retrying", installer)

    def test_sysadmin_guide_provisions_spokes_from_admin(self) -> None:
        content = SYSADMIN_GUIDE.read_text(encoding="utf-8")

        self.assertIn("All worker and dedicated portal provisioning is initiated", content)
        self.assertIn("sudo admiral-install --portal-node", content)
        self.assertIn("sudo admiral-install --worker-node", content)
        self.assertIn("--admin-portal-node", content)
        self.assertIn("--single-node", content)
        self.assertIn("--dev-node", content)

    def test_playbook_uses_persistent_roles_without_service_detection(self) -> None:
        content = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("/etc/admiral/role", content)
        self.assertIn("'admin-portal-node': 'admin-portal'", content)
        self.assertNotIn("admiral_portal_shares_admin_host", content)
        self.assertNotIn("systemctl is-active --quiet", content)

    def test_admiral_config_directory_matches_rpm_service_group(self) -> None:
        playbook = PLAYBOOK.read_text(encoding="utf-8")
        common_spec = COMMON_SPEC.read_text(encoding="utf-8")
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")
        config_directory_check = common_tasks.split(
            "Inspect Admiral configuration directories installed by admiral-common", 1
        )[1].split("\n- name:", 1)[0]
        secret_assertion = common_tasks.split(
            "Enforce bootstrap secret inventory permissions", 1
        )[1].split("\n- name:", 1)[0]
        config_assertion = common_tasks.split(
            "Require the admiral-common RPM directory attributes", 1
        )[1].split("\n- name:", 1)[0]
        installer_state = INSTALLER.read_text(encoding="utf-8").split(
            "# --- 10. persist local installer state for future spoke bootstraps ---", 1
        )[1].split("# --- 10b.", 1)[0]

        self.assertNotIn(
            "Ensure Admiral configuration directory exists before role persistence",
            playbook,
        )
        self.assertIn("stat:\n    path: \"{{ item }}\"", config_directory_check)
        self.assertNotIn("file:", config_directory_check)
        self.assertNotIn("state: directory", config_directory_check)
        self.assertIn("item.stat.gr_name == 'admiral'", config_assertion)
        self.assertIn("item.stat.mode == '0750'", config_assertion)
        self.assertIn(
            "%dir %attr(0750, root, admiral) %{_sysconfdir}/admiral\n", common_spec
        )
        self.assertIn(
            "%dir %attr(0750, root, admiral) %{_sysconfdir}/admiral/tls\n", common_spec
        )
        self.assertIn(
            "%dir %attr(0750, root, admiral) %{_sysconfdir}/admiral/ssh\n", common_spec
        )
        self.assertIn("/etc/admiral/role", playbook)
        self.assertIn("Persist Admiral node role after package-managed setup succeeds", playbook)
        self.assertIn(
            "%dir %attr(0700, root, root) %{_localstatedir}/lib/admiral/ssh-delivery",
            common_spec,
        )
        self.assertIn(
            "%dir %attr(0700, root, root) %{_sysconfdir}/wireguard/peers.d",
            common_spec,
        )
        self.assertIn("admiral_secrets_permissions.stat.mode == '0600'", secret_assertion)
        self.assertIn("admiral_secrets_permissions.stat.pw_name == 'root'", secret_assertion)
        self.assertIn("admiral_secrets_permissions.stat.gr_name == 'root'", secret_assertion)
        self.assertIn("[[ -d /etc/admiral ]] || die", installer_state)
        self.assertNotIn("install -d", installer_state)
        peer_add_helper = (ROOT / "scripts" / "admiral_wireguard_peer_add.py").read_text(encoding="utf-8")
        self.assertIn("peer_dir.is_dir() or peer_dir.is_symlink()", peer_add_helper)
        for task_file in (
            ROOT / "ansible" / "roles" / "admiral_wireguard" / "tasks" / "main.yml",
            ROOT / "ansible" / "roles" / "admiral_fleet" / "tasks" / "main.yml",
            ROOT / "ansible" / "wireguard-peers.yml",
        ):
            self.assertNotIn("path: /etc/wireguard/peers.d\n    state: directory", task_file.read_text(encoding="utf-8"))

    def test_fedora_resolver_dropin_follows_admiral_common_package_install(self) -> None:
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")
        common_spec = COMMON_SPEC.read_text(encoding="utf-8")

        package_install = common_tasks.index(
            "- name: Install admiral-common baseline package"
        )
        resolver_dropin = common_tasks.index(
            "- name: Disable LLMNR on Fedora secure installs"
        )

        self.assertLess(package_install, resolver_dropin)
        self.assertIn(
            "%dir %attr(0755, root, root) %{_sysconfdir}/systemd/resolved.conf.d",
            common_spec,
        )

    def test_setup_directories_are_owned_by_admiral_common_rpm(self) -> None:
        common_spec = COMMON_SPEC.read_text(encoding="utf-8")
        ansible_tasks = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "ansible").rglob("*.yml")
        )
        package_specs = {
            path.name: path.read_text(encoding="utf-8")
            for path in (ROOT / "packaging" / "rpm").glob("admiral*.spec")
        }

        self.assertNotIn("state: directory", ansible_tasks)
        for package_name in (
            "admirald.spec",
            "admiral-flagship.spec",
            "admiral-harbor.spec",
            "admiralctl.spec",
        ):
            self.assertNotRegex(
                package_specs[package_name],
                r"(?m)^(?:%dir .*service\.d|%dir .*admiralctl|%dir .*lib/admiral/harbor)",
            )
        self.assertNotIn('echo "%%dir %{_prefix}/lib/admiral/flagship"', package_specs["admiral-flagship.spec"])
        self.assertNotIn('echo "%%dir %{_prefix}/lib/admiral/harbor"', package_specs["admiral-harbor.spec"])

        for directory in (
            "%dir %attr(0750, root, admiral) %{_sysconfdir}/systemd/system/admirald.service.d",
            "%dir %attr(0750, root, admiral) %{_sysconfdir}/systemd/system/admiral-flagship.service.d",
            "%dir %attr(0750, root, admiral) %{_sysconfdir}/systemd/system/admiral-harbor.service.d",
            "%dir %attr(0700, root, root) %{_sysconfdir}/ssh/sshd_config.d",
            "%dir %attr(0700, root, root) %{_sysconfdir}/nftables",
            "%dir %attr(0750, root, root) %{_sysconfdir}/audit/rules.d",
            "%dir %attr(0700, root, root) /root/.config/admiralctl",
            "%dir %attr(0755, root, root) %{_prefix}/lib/admiral/flagship",
            "%dir %attr(0755, root, root) %{_prefix}/lib/admiral/harbor",
            "%dir %attr(0750, admiral, admiral) %{_localstatedir}/lib/admiral/harbor",
            "%dir %attr(0700, root, root) %{_localstatedir}/lib/admiral/ssh-delivery",
            "%dir %attr(0700, root, root) %{_localstatedir}/lib/admiral/outbox",
            "%dir %attr(0750, admiral-apps, admiral-apps) %{_localstatedir}/lib/admiral/backups",
            "%dir %attr(0750, admiral-apps, admiral-apps) %{_localstatedir}/lib/admiral/restore",
            "%dir %attr(0700, admiral-apps, admiral-apps) %{_localstatedir}/lib/admiral/tmp",
            "%dir %attr(0751, admiral, admiral) %{_localstatedir}/lib/admiral/instances",
            "%dir %attr(0700, root, root) %{_localstatedir}/lib/admiral/control-plane-backups",
        ):
            self.assertIn(directory, common_spec)

        self.assertNotIn("chown -R admiral:admiral %{_localstatedir}/lib/admiral", common_spec)
        self.assertNotIn("chmod 0751 %{_localstatedir}/lib/admiral", common_spec)
        self.assertIn(
            "install -d -o root -g root -m 0755 %{_sysconfdir}/containers/systemd/users/${ADMIRAL_APPS_UID}/admiral",
            common_spec,
        )
        release_lines = [
            next(
                (line for line in package_spec.splitlines() if line.startswith("Release:")),
                "",
            )
            for package_spec in package_specs.values()
        ]
        self.assertEqual(len(package_specs), 6)
        self.assertTrue(all(release_lines))
        self.assertEqual(len(set(release_lines)), 1)

    def test_role_preflight_runs_before_package_or_repository_changes(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        mutation_offset = installer.index("dnf install -y epel-release")

        self.assertLess(installer.index('preflight_local_node_role "$REQUESTED_NODE_ROLE"'), mutation_offset)
        self.assertLess(installer.index('preflight_remote_node_role "$REQUESTED_NODE_ROLE"'), mutation_offset)
        self.assertIn("Refusing to modify packages or repositories", installer)

    def test_spoke_identity_is_resolved_before_local_mutations(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        resolve_offset = installer.index("Resolve the spoke identity before any local package")
        delivery_offset = installer.index('DELIVERY_KEY_CANDIDATE=')
        mutation_offset = installer.index("dnf install -y epel-release")
        self.assertLess(resolve_offset, delivery_offset)
        self.assertLess(resolve_offset, mutation_offset)
        self.assertIn("Could not resolve node ID for role", installer)
        self.assertIn("admiral-known-host", installer)

    def test_spoke_mode_does_not_mutate_controller_packages_or_repositories(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('Spoke mode: leaving local repositories and packages unchanged.', installer)
        self.assertIn('command -v ansible-playbook', installer)
        self.assertIn('rpm -q admiral-common', installer)
        self.assertIn('INSTALL_MODE" != "worker-node"', installer)
        self.assertIn('INSTALL_MODE" != "portal-node"', installer)

    def test_el10_bootstrap_enables_crb_before_installing_admiral_packages(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")

        self.assertIn("dnf config-manager --set-enabled crb", installer)
        self.assertLess(
            installer.index("dnf config-manager --set-enabled crb"),
            installer.index("dnf install -y admiral-common"),
        )
        self.assertIn("Enable EL10 CRB repository", common_tasks)
        self.assertIn("cmd: dnf config-manager --set-enabled crb", common_tasks)

    def test_caddy_uses_epel_without_enabling_caddy_copr(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")

        self.assertNotIn('dnf copr enable -y "@caddy/caddy"', installer)
        self.assertNotIn("Enable Caddy COPR repository", common_tasks)
        self.assertIn("Removing obsolete Caddy COPR repository", installer)
        self.assertIn("Remove obsolete Caddy COPR repository", common_tasks)
        self.assertIn("dnf install -y epel-release", installer)
        self.assertIn("name: epel-release", common_tasks)

        # The Admiral repository remains enabled and its GPG check remains
        # part of the common role's preflight.
        self.assertIn('dnf copr enable -y "admiral-project/admiral"', installer)
        self.assertIn("admiral-project:admiral.repo", common_tasks)
        self.assertNotIn("group_caddy:caddy.repo", common_tasks.split(
            "loop:", 1
        )[-1].split("register: admiral_copr_gpgcheck", 1)[0])

    def test_caddy_admin_api_uses_loopback_port_without_socket_acl(self) -> None:
        common_tasks = COMMON_TASKS.read_text(encoding="utf-8")

        self.assertIn("admin 127.0.0.1:2019", common_tasks)
        self.assertIn("Remove obsolete Caddy Unix socket configuration", common_tasks)
        self.assertNotIn("admin unix//run/caddy/admin.sock", common_tasks)
        self.assertNotIn("setfacl -m u:admiral", common_tasks)

    def test_rpm_baseline_configuration_is_not_treated_as_existing_installation(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        playbook = PLAYBOOK.read_text(encoding="utf-8")

        self.assertIn("rpm -q admiral-common", installer)
        self.assertIn("[[ ! -e /etc/admiral/secrets ]]", installer)
        self.assertIn("printf %s __ADMIRAL_NEW__", installer)
        self.assertIn("Detect fresh admiral-common RPM baseline", playbook)
        self.assertIn("admiral_common_package.rc == 0", playbook)

    def test_secure_role_preflight_preserves_dev_mode_behavior(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        self.assertIn('if [[ "$INSTALL_DEV_MODE" != "true" ]]', installer)
        self.assertIn('[[ "$requested_role" == "single" ]] && return 0', installer)

    def test_single_node_readiness_only_requires_fail2ban_in_secure_mode(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        single_node_case = installer.split("    single-node)", 1)[1].split(
            "\n    admin-node)", 1
        )[0]

        self.assertIn("REQUIRED_SERVICES+=(fail2ban)", single_node_case)
        self.assertIn('if [[ "$INSTALL_DEV_MODE" != "true" ]]', single_node_case)

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

    def test_spoke_egress_allows_required_network_endpoints(self) -> None:
        template = (ROOT / "ansible" / "roles" / "admiral_firewall" / "templates" / "admiral-egress.nft.j2").read_text(encoding="utf-8")

        self.assertIn("tcp dport 53 accept", template)
        self.assertIn("udp dport 53 accept", template)
        self.assertIn("udp dport 123 accept", template)
        self.assertIn("tcp dport { 80, 443, 587, 9000 } accept", template)
        self.assertIn("Kubernetes model", template)
        self.assertIn("ip daddr {{ admiral_wireguard_subnet }} accept", template)

    def test_wireguard_is_segmented_as_a_hub_and_spoke_vpn(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        wireguard_tasks = (
            ROOT / "ansible" / "roles" / "admiral_wireguard" / "tasks" / "main.yml"
        ).read_text(encoding="utf-8")
        wireguard_template = (
            ROOT
            / "ansible"
            / "roles"
            / "admiral_wireguard"
            / "templates"
            / "wg-admiral.conf.j2"
        ).read_text(encoding="utf-8")

        self.assertIn("umask 077", wireguard_tasks)
        self.assertIn("creates: /etc/wireguard/admiral.key", wireguard_tasks)
        self.assertIn("Disable inter-node IP forwarding", wireguard_tasks)
        self.assertIn("value: '0'", wireguard_tasks)
        self.assertIn("AllowedIPs = {{ admiral_wireguard_hub_ip }}/32", wireguard_template)
        self.assertNotIn("AllowedIPs = 10.99.0.0/24", wireguard_template)
        self.assertIn("firewall-cmd --permanent --zone=admiral --get-target", installer)
        self.assertIn("firewall-cmd --zone=trusted --list-interfaces", installer)
        self.assertIn("wg show wg-admiral allowed-ips", installer)
        self.assertIn('"$INSTALL_ADMIN_WIREGUARD_IP/32"', installer)
        self.assertIn("wireguard_hub_ip_for_subnet", installer)

    def test_worker_hub_peer_is_installed_before_fleet_heartbeat_gate(self) -> None:
        fleet = FLEET_TASKS.read_text(encoding="utf-8")
        common_spec = COMMON_SPEC.read_text(encoding="utf-8")

        register = fleet.index("- name: Register node with admirald before starting Fleet")
        add_peer = fleet.index(
            "- name: Add and persist the registered worker peer under the shared WireGuard lock"
        )
        start_fleet = fleet.index("- name: Enable and start admiral-fleet after worker registration")
        heartbeat_gate = fleet.index("- name: Wait for the registered Fleet worker to report a healthy heartbeat")

        self.assertIn("%dir %attr(0700, root, root) %{_sysconfdir}/wireguard/peers.d", common_spec)
        self.assertNotIn("Ensure the hub's durable WireGuard peer directory exists", fleet)
        self.assertLess(register, add_peer)
        self.assertLess(add_peer, start_fleet)
        self.assertLess(start_fleet, heartbeat_gate)
        self.assertIn("/usr/libexec/admiral-wireguard-peer-add", fleet[add_peer:start_fleet])
        self.assertIn("delegate_to: localhost", fleet[add_peer:start_fleet])
        self.assertIn("ADMIRAL_INTERNAL_TOKEN", fleet[add_peer:start_fleet])

        installer = INSTALLER.read_text(encoding="utf-8")
        peer_registration = installer[installer.index("/usr/libexec/admiral-wireguard-peer-add") :]
        self.assertIn('"$SPOKE_NODE_ID" "$SPOKE_WG_IP" "$SPOKE_KEY"', peer_registration)
        self.assertNotIn('wg set wg-admiral peer "$SPOKE_KEY"', peer_registration)

    def test_admin_install_requires_the_wireguard_revocation_socket(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        for profile in ("admin-node", "admin-portal-node"):
            match = re.search(
                rf"(?m)^    {re.escape(profile)}\)\s*\n\s*REQUIRED_SERVICES=\(([^)]*)\)",
                installer,
            )
            self.assertIsNotNone(match, profile)
            self.assertIn("admiral-wireguard-peer-revoke.socket", match.group(1))

    def test_rootless_runtime_is_prepared_and_verified(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        fleet = (
            ROOT / "ansible" / "roles" / "admiral_fleet" / "tasks" / "main.yml"
        ).read_text(encoding="utf-8")
        common_spec = (
            ROOT / "packaging" / "rpm" / "admiral-common.spec"
        ).read_text(encoding="utf-8")

        self.assertIn("Allocate non-overlapping subordinate IDs", fleet)
        self.assertIn("Start persistent rootless user manager", fleet)
        self.assertIn("Wait for rootless user D-Bus", fleet)
        self.assertIn("Verify rootless Podman storage ownership", fleet)
        self.assertIn("/usr/bin/admiral-rootless-subids", installer)
        self.assertIn("systemd-machined.service", installer)
        self.assertIn("DBUS_SESSION_BUS_ADDRESS", installer)
        self.assertNotIn("echo 'admiral-apps:100000:131072'", common_spec)

    def test_common_rpm_removes_generated_rootless_runtime_state(self) -> None:
        common_spec = (
            ROOT / "packaging" / "rpm" / "admiral-common.spec"
        ).read_text(encoding="utf-8")

        self.assertIn("%preun", common_spec)
        self.assertIn("rm -f /usr/lib/tmpfiles.d/admiral-apps.conf", common_spec)
        self.assertIn("semanage fcontext -d -t container_file_t", common_spec)
        self.assertIn("loginctl disable-linger admiral-apps", common_spec)
        self.assertIn("%postun", common_spec)

    def test_secure_checklist_validates_runtime_controls(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        common = COMMON_TASKS.read_text(encoding="utf-8")
        self.assertIn("ss -H -lntu", installer)
        self.assertIn("auditctl -l", installer)
        self.assertIn("fail2ban-client ping", installer)
        self.assertIn("fail2ban-client get sshd actions", installer)
        self.assertIn("dnf5-automatic.timer", installer)
        self.assertIn("dnf-automatic.timer", installer)
        self.assertIn("chronyc tracking", installer)
        self.assertIn("nft list chain inet admiral_egress output", installer)
        for directive in (
            "KbdInteractiveAuthentication no",
            "PermitEmptyPasswords no",
            "X11Forwarding no",
            "AllowAgentForwarding no",
        ):
            self.assertIn(directive, common)
        for effective_setting in (
            "kbdinteractiveauthentication no",
            "permitemptypasswords no",
            "x11forwarding no",
            "allowagentforwarding no",
        ):
            self.assertIn(effective_setting, installer)

    def test_secure_checklist_waits_for_chrony_synchronization(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        clock_check = installer.split('TIME_SYNC=""', 1)[1].split(
            'NFT_EGRESS="$(run_target_cmd', 1
        )[0]

        self.assertIn("for attempt in {1..30}", clock_check)
        self.assertIn('sleep 2', clock_check)
        self.assertIn('"Leap status     : Normal"', clock_check)
        self.assertIn(
            'SECURITY_WARNINGS+=("chronyd has not synchronized the system clock.")',
            clock_check,
        )

    def test_security_updates_and_effective_bans_are_enforced(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        common = COMMON_TASKS.read_text(encoding="utf-8")
        fail2ban = FAIL2BAN_TASKS.read_text(encoding="utf-8")

        self.assertIn("Apply available security updates", common)
        self.assertIn("value: security", common)
        self.assertIn("else 'dnf-automatic' }}", common)
        self.assertIn("else 'dnf-automatic.timer' }}", common)
        self.assertIn(
            "'dnf5-plugin-automatic' if ansible_facts['distribution'] == 'Fedora' else 'dnf-automatic'",
            common,
        )
        self.assertIn(
            "'dnf5-automatic.timer' if ansible_facts['distribution'] == 'Fedora' else 'dnf-automatic.timer'",
            common,
        )
        self.assertIn("ansible_facts['distribution'] in ['RedHat', 'CentOS', 'Rocky', 'AlmaLinux']", common)
        self.assertIn("(ansible_facts['distribution_major_version'] | int) == 10", common)
        self.assertIn("(ansible_facts['distribution_major_version'] | int) >= 44", common)
        self.assertIn("not (admiral_dev_mode | default(false) | bool)", common)
        self.assertIn("name: chrony", common)
        self.assertIn("name: chronyd", common)
        self.assertIn("chronyc waitsync 30", FIREWALL_TASKS.read_text(encoding="utf-8"))
        self.assertIn("banaction = nftables[type=allports]", fail2ban)
        self.assertIn("Wait for the Fail2ban SSH jail to become ready", fail2ban)
        self.assertIn("cmd: fail2ban-client status sshd", fail2ban)
        self.assertIn("until: admiral_fail2ban_ssh_status.rc == 0", fail2ban)
        self.assertIn("Exercise Fail2ban nftables enforcement", fail2ban)
        self.assertIn("nft list ruleset", fail2ban)
        self.assertIn("gpgcheck", installer)

    def test_ansible_facts_are_not_injected_as_top_level_variables(self) -> None:
        fact_variables = (
            "ansible_default_ipv4",
            "ansible_distribution",
            "ansible_distribution_major_version",
            "ansible_distribution_version",
            "ansible_fqdn",
            "ansible_hostname",
            "ansible_selinux",
        )
        ansible_files = tuple((ROOT / "ansible").rglob("*.yml")) + tuple(
            (ROOT / "ansible").rglob("*.yaml")
        ) + tuple((ROOT / "ansible").rglob("*.j2"))

        for path in ansible_files:
            contents = path.read_text(encoding="utf-8")
            for fact_variable in fact_variables:
                with self.subTest(path=path, fact_variable=fact_variable):
                    self.assertNotIn(fact_variable, contents)

    def test_cockpit_bridge_is_installed_without_web_service(self) -> None:
        cockpit = (
            ROOT / "ansible" / "roles" / "admiral_cockpit" / "tasks" / "main.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("name: cockpit-bridge", cockpit)
        self.assertIn("name: cockpit-ws", cockpit)
        self.assertIn("name: cockpit.socket", cockpit)

    def test_admirald_deploys_admiralctl_config_with_internal_token(self) -> None:
        admirald = ADMIRALD_TASKS.read_text(encoding="utf-8")

        self.assertIn("Resolve admiralctl token for control-plane tasks", admirald)
        self.assertIn("admiralctl_token_value:", admirald)
        self.assertIn("admiral_internal_token_value", admirald)
        self.assertIn("Require non-empty token for admiralctl configuration", admirald)
        self.assertIn("admiralctl_token_value is defined", admirald)
        self.assertIn("admiralctl_token_value | length > 0", admirald)
        self.assertIn("token: {{ admiralctl_token_value }}", admirald)

    def test_portal_registration_exports_validated_admin_token(self) -> None:
        harbor = HARBOR_TASKS.read_text(encoding="utf-8")
        registration = harbor.split("- name: Register portal node with admirald", 1)[1]
        routes_sync = harbor.split("- name: Synchronize public routes after portal registration", 1)[1]

        self.assertIn("admiral_admin_token_value", registration)
        self.assertIn('ADMIRAL_INTERNAL_TOKEN: "{{ admiral_admin_token_value }}"', registration)
        self.assertNotIn("admiral_internal_token_value", registration.split("no_log: true", 1)[0])
        self.assertIn('ADMIRAL_INTERNAL_TOKEN: "{{ admiral_admin_token_value }}"', routes_sync)

    def test_spoke_peer_exchange_reads_normalized_controller_token(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        peer_exchange = installer.split("# --- 10b. exchange WireGuard peers for spoke installs ---", 1)[1]

        self.assertIn(
            'CONTROLLER_ADMIN_TOKEN="$(read_admiral_secret ADMIRAL_INTERNAL_TOKEN || true)"',
            peer_exchange,
        )
        self.assertIn(
            'CONTROLLER_ADMIN_TOKEN="$(read_admiral_secret ADMIRAL_ADMIN_TOKEN || true)"',
            peer_exchange,
        )
        self.assertIn('export ADMIRAL_ADMIN_TOKEN="$CONTROLLER_ADMIN_TOKEN"', peer_exchange)
        self.assertLess(
            peer_exchange.index("ADMIRAL_INTERNAL_TOKEN"),
            peer_exchange.index("ADMIRAL_ADMIN_TOKEN"),
        )

    def test_worker_registration_exports_validated_admin_token(self) -> None:
        fleet = FLEET_TASKS.read_text(encoding="utf-8")
        registration = fleet.split("- name: Register node with admirald before starting Fleet", 1)[1].split(
            "- name:", 1
        )[0]

        self.assertIn("admiral_admin_token_value", registration)
        self.assertNotIn('ADMIRAL_INTERNAL_TOKEN: "{{ admiral_internal_token_value }}"', registration)


if __name__ == "__main__":
    unittest.main()
