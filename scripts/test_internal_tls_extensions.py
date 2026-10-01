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
    assert 'subjectKeyIdentifier=hash' in TASKS
    assert 'authorityKeyIdentifier=keyid,issuer' in TASKS


def test_portal_server_extensions_include_key_identifiers() -> None:
    portal_task = TASKS.split(
        "- name: Write portal-node SAN extensions to controller temporary file",
        1,
    )[1].split("\n- name:", 1)[0]

    assert "subjectKeyIdentifier=hash" in portal_task
    assert "authorityKeyIdentifier=keyid,issuer" in portal_task
