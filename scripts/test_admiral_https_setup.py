import importlib.util
import os
import subprocess
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import pytest


SPEC = importlib.util.spec_from_file_location(
    "admiral_https_setup", Path(__file__).with_name("admiral_https_setup.py")
)
HTTPS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HTTPS)


def test_deploy_certificate_keeps_certbot_sources_unchanged(tmp_path):
    source_dir = tmp_path / "letsencrypt" / "live" / "apps.example.com"
    source_dir.mkdir(parents=True)
    cert = source_dir / "fullchain.pem"
    key = source_dir / "privkey.pem"
    cert.write_text("certificate")
    key.write_text("private-key")
    os.chmod(cert, 0o600)
    os.chmod(key, 0o600)

    deployed = tmp_path / "admiral-tls"
    with mock.patch.object(HTTPS.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=os.getgid())), mock.patch.object(HTTPS.os, "chown", return_value=None):
        deployed_cert, deployed_key = HTTPS._deploy_readonly_certificate(cert, key, str(deployed))

    assert cert.read_text() == "certificate"
    assert key.read_text() == "private-key"
    assert os.stat(cert).st_mode & 0o777 == 0o600
    assert os.stat(key).st_mode & 0o777 == 0o600
    assert Path(deployed_cert).read_text() == "certificate"
    assert Path(deployed_key).read_text() == "private-key"
    assert os.stat(deployed_key).st_mode & 0o777 == 0o640
    assert os.stat(deployed).st_mode & 0o777 == 0o750


def test_letsencrypt_deploy_hook_replaces_the_admiral_copy_atomically():
    hook = Path(__file__).with_name("admiral_letsencrypt_deploy_hook.sh").read_text()
    assert "CERTBOT_RENEWED_LINEAGE" in hook
    assert "renewed lineage is not the expected apps-domain lineage" in hook
    assert "openssl x509" in hook
    assert "openssl pkey" in hook
    assert "SSL server : Yes" in hook
    assert "renewal healthcheck failed\"" in hook
    assert "mktemp \"$deploy_dir/fullchain.pem." in hook
    assert "fullchain.pem.bak" in hook
    assert "mv -f -- \"$tmp_cert\" \"$deploy_dir/fullchain.pem\"" in hook
    assert "install -o root -g caddy -m 0640" in hook
    assert "systemctl restart caddy admirald" in hook
    assert "systemctl is-active --quiet caddy" in hook
    assert "systemctl is-active --quiet admirald" in hook


def test_letsencrypt_deploy_hook_updates_a_renewed_pair(tmp_path):
    lineage = tmp_path / "letsencrypt" / "live" / "apps.example.com"
    lineage.mkdir(parents=True)
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=apps.example.com",
            "-addext",
            "subjectAltName=DNS:apps.example.com,DNS:probe.apps.example.com",
            "-keyout",
            str(lineage / "privkey.pem"),
            "-out",
            str(lineage / "fullchain.pem"),
        ],
        check=True,
        capture_output=True,
    )
    deployed = tmp_path / "deployed"
    (deployed / "fullchain.pem").parent.mkdir()
    (deployed / "fullchain.pem").write_text("old certificate")
    (deployed / "privkey.pem").write_text("old key")
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    calls = tmp_path / "systemctl.calls"
    install_cmd = fake_bin / "install"
    install_cmd.write_text(
        "#!/bin/sh\n"
        "set -eu\n"
        "dir_mode=0\n"
        "mode=\"\"\n"
        "while [ $# -gt 0 ]; do\n"
        "  case \"$1\" in\n"
        "    -d) dir_mode=1; shift ;;\n"
        "    -o|-g) shift 2 ;;\n"
        "    -m) mode=\"$2\"; shift 2 ;;\n"
        "    --) shift; break ;;\n"
        "    -*) shift ;;\n"
        "    *) break ;;\n"
        "  esac\n"
        "done\n"
        "if [ \"$dir_mode\" -eq 1 ]; then\n"
        "  mkdir -p \"$1\"\n"
        "  if [ -n \"$mode\" ]; then chmod \"$mode\" \"$1\"; fi\n"
        "  exit 0\n"
        "fi\n"
        "cp \"$1\" \"$2\"\n"
        "if [ -n \"$mode\" ]; then chmod \"$mode\" \"$2\"; fi\n"
    )
    install_cmd.chmod(0o755)
    systemctl = fake_bin / "systemctl"
    systemctl.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> {calls}\n")
    systemctl.chmod(0o755)

    env = os.environ.copy()
    env.update(
        {
            "CERTBOT_RENEWED_LINEAGE": str(lineage),
            "ADMIRAL_LETSENCRYPT_DEPLOY_DIR": str(deployed),
            "ADMIRAL_NETWORKING_APPS_DOMAIN": "apps.example.com",
            "PATH": f"{fake_bin}:{env['PATH']}",
        }
    )
    result = subprocess.run(
        ["bash", str(Path(__file__).with_name("admiral_letsencrypt_deploy_hook.sh"))],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert (deployed / "fullchain.pem").read_bytes() == (lineage / "fullchain.pem").read_bytes()
    assert (deployed / "privkey.pem").read_bytes() == (lineage / "privkey.pem").read_bytes()
    assert (deployed / "fullchain.pem").stat().st_mode & 0o777 == 0o644
    assert (deployed / "privkey.pem").stat().st_mode & 0o777 == 0o640
    assert calls.read_text().splitlines() == [
        "daemon-reload",
        "restart caddy admirald",
        "is-active --quiet caddy",
        "is-active --quiet admirald",
    ]


def test_letsencrypt_deploy_hook_rejects_unexpected_lineage(tmp_path):
    lineage = tmp_path / "letsencrypt" / "live" / "other.example.com"
    lineage.mkdir(parents=True)
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=apps.example.com",
            "-addext",
            "subjectAltName=DNS:apps.example.com,DNS:probe.apps.example.com",
            "-keyout",
            str(lineage / "privkey.pem"),
            "-out",
            str(lineage / "fullchain.pem"),
        ],
        check=True,
        capture_output=True,
    )
    env = os.environ.copy()
    env.update(
        {
            "CERTBOT_RENEWED_LINEAGE": str(lineage),
            "ADMIRAL_NETWORKING_APPS_DOMAIN": "apps.example.com",
        }
    )
    result = subprocess.run(
        ["bash", str(Path(__file__).with_name("admiral_letsencrypt_deploy_hook.sh"))],
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "renewed lineage is not the expected apps-domain lineage" in result.stderr


def test_letsencrypt_deploy_hook_restores_previous_pair_on_restart_failure(tmp_path):
    lineage = tmp_path / "letsencrypt" / "live" / "apps.example.com"
    lineage.mkdir(parents=True)
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=apps.example.com",
            "-addext",
            "subjectAltName=DNS:apps.example.com,DNS:probe.apps.example.com",
            "-keyout",
            str(lineage / "privkey.pem"),
            "-out",
            str(lineage / "fullchain.pem"),
        ],
        check=True,
        capture_output=True,
    )
    deployed = tmp_path / "deployed"
    deployed.mkdir()
    (deployed / "fullchain.pem").write_text("previous cert")
    (deployed / "privkey.pem").write_text("previous key")

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    calls = tmp_path / "systemctl.calls"
    install_cmd = fake_bin / "install"
    install_cmd.write_text(
        "#!/bin/sh\n"
        "set -eu\n"
        "dir_mode=0\n"
        "mode=\"\"\n"
        "while [ $# -gt 0 ]; do\n"
        "  case \"$1\" in\n"
        "    -d) dir_mode=1; shift ;;\n"
        "    -o|-g) shift 2 ;;\n"
        "    -m) mode=\"$2\"; shift 2 ;;\n"
        "    --) shift; break ;;\n"
        "    -*) shift ;;\n"
        "    *) break ;;\n"
        "  esac\n"
        "done\n"
        "if [ \"$dir_mode\" -eq 1 ]; then\n"
        "  mkdir -p \"$1\"\n"
        "  if [ -n \"$mode\" ]; then chmod \"$mode\" \"$1\"; fi\n"
        "  exit 0\n"
        "fi\n"
        "cp \"$1\" \"$2\"\n"
        "if [ -n \"$mode\" ]; then chmod \"$mode\" \"$2\"; fi\n"
    )
    install_cmd.chmod(0o755)
    systemctl = fake_bin / "systemctl"
    systemctl.write_text(
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$*\" >> {calls}\n"
        "if [ \"$1\" = \"restart\" ]; then\n"
        "  exit 1\n"
        "fi\n"
        "exit 0\n"
    )
    systemctl.chmod(0o755)

    env = os.environ.copy()
    env.update(
        {
            "CERTBOT_RENEWED_LINEAGE": str(lineage),
            "ADMIRAL_LETSENCRYPT_DEPLOY_DIR": str(deployed),
            "ADMIRAL_NETWORKING_APPS_DOMAIN": "apps.example.com",
            "PATH": f"{fake_bin}:{env['PATH']}",
        }
    )
    result = subprocess.run(
        ["bash", str(Path(__file__).with_name("admiral_letsencrypt_deploy_hook.sh"))],
        env=env,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert "previous certificate pair restored" in result.stderr
    assert (deployed / "fullchain.pem").read_text() == "previous cert"
    assert (deployed / "privkey.pem").read_text() == "previous key"


def test_dns_name_match_supports_single_label_wildcards_only():
    assert HTTPS._dns_name_matches("*.apps.example.com", "probe.apps.example.com")
    assert not HTTPS._dns_name_matches("*.apps.example.com", "apps.example.com")
    assert not HTTPS._dns_name_matches("*.apps.example.com", "a.b.apps.example.com")


def test_validate_certificate_names_uses_subject_alt_name_list(monkeypatch):
    monkeypatch.setattr(
        HTTPS,
        "_certificate_dns_names",
        lambda _: ["*.apps.example.com", "apps.example.com"],
    )

    HTTPS._validate_certificate_names("dummy-cert.pem", "apps.example.com")


def test_validate_certificate_names_fails_when_probe_name_missing(monkeypatch):
    monkeypatch.setattr(HTTPS, "_certificate_dns_names", lambda _: ["apps.example.com"])

    with pytest.raises(SystemExit):
        HTTPS._validate_certificate_names("dummy-cert.pem", "apps.example.com")


@pytest.mark.parametrize(
    "target",
    ["", "ftp://portal.example.com", "https://portal.example.com\nEnvironment=BAD=1", "https://:5001"],
)
def test_invalid_upstream_targets_fail(target):
    with pytest.raises(SystemExit):
        HTTPS._validate_target("portal target", target)
