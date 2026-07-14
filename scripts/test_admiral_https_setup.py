import importlib.util
import os
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
    with mock.patch.object(HTTPS.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=os.getgid())):
        deployed_cert, deployed_key = HTTPS._deploy_readonly_certificate(cert, key, str(deployed))

    assert cert.read_text() == "certificate"
    assert key.read_text() == "private-key"
    assert os.stat(cert).st_mode & 0o777 == 0o600
    assert os.stat(key).st_mode & 0o777 == 0o600
    assert Path(deployed_cert).read_text() == "certificate"
    assert Path(deployed_key).read_text() == "private-key"
    assert os.stat(deployed_key).st_mode & 0o777 == 0o640
    assert os.stat(deployed).st_mode & 0o777 == 0o750


@pytest.mark.parametrize(
    "target",
    ["", "ftp://portal.example.com", "https://portal.example.com\nEnvironment=BAD=1", "https://:5001"],
)
def test_invalid_upstream_targets_fail(target):
    with pytest.raises(SystemExit):
        HTTPS._validate_target("portal target", target)
