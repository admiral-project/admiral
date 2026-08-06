#!/usr/bin/env python3
"""Static regression checks for generated internal TLS certificate policy."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TASKS = (ROOT / "ansible/roles/admiral_common/tasks/main.yml").read_text(encoding="utf-8")


def test_internal_ca_has_ca_constraints() -> None:
    assert 'basicConstraints=critical,CA:TRUE,pathlen:1' in TASKS
    assert 'keyUsage=critical,keyCertSign,cRLSign' in TASKS


def test_internal_server_has_tls_usage_constraints() -> None:
    assert 'basicConstraints=critical,CA:FALSE' in TASKS
    assert 'keyUsage=critical,digitalSignature,keyEncipherment' in TASKS
    assert 'extendedKeyUsage=serverAuth,clientAuth' in TASKS
