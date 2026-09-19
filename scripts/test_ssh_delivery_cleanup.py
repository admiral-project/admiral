#!/usr/bin/env python3
"""Tests for safe SSH delivery artifact cleanup."""

from pathlib import Path
from unittest import mock
import importlib.util

import pytest


SCRIPT = Path(__file__).with_name("admiral_ssh_delivery_cleanup.py")
SPEC = importlib.util.spec_from_file_location("admiral_ssh_delivery_cleanup", SCRIPT)
assert SPEC and SPEC.loader
CLEANUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLEANUP)


def _create_delivery_key(tmp_path: Path, node_id: str = "worker-01") -> Path:
    key_dir = tmp_path / "ssh-delivery"
    key_dir.mkdir()
    key = key_dir / f"{node_id}.ed25519"
    key.write_text("private key placeholder")
    (key_dir / f"{node_id}.ed25519.pub").write_text("public key placeholder")
    return key


def test_dry_run_reports_targets_without_removing_them(tmp_path, capsys) -> None:
    key = _create_delivery_key(tmp_path)

    result = CLEANUP.main(["--key-dir", str(key.parent), "--node-id", "worker-01"])

    assert result == 0
    assert key.exists()
    assert "dry-run" in capsys.readouterr().out


def test_apply_requires_an_alternate_operator_key(tmp_path) -> None:
    key = _create_delivery_key(tmp_path)

    result = CLEANUP.main(
        ["--key-dir", str(key.parent), "--node-id", "worker-01", "--apply"]
    )

    assert result == 2
    assert key.exists()


def test_apply_uses_only_exact_targets_and_is_idempotent(tmp_path) -> None:
    key = _create_delivery_key(tmp_path)
    replacement = tmp_path / "operator.ed25519"
    replacement.write_text("replacement key")
    replacement.chmod(0o600)

    with mock.patch.object(CLEANUP, "_check_replacement"), mock.patch.object(
        CLEANUP, "_secure_remove"
    ) as secure_remove:
        result = CLEANUP.main(
            [
                "--key-dir",
                str(key.parent),
                "--node-id",
                "worker-01",
                "--replacement-key",
                str(replacement),
                "--apply",
            ]
        )

    assert result == 0
    assert secure_remove.call_count == 2

    with mock.patch.object(CLEANUP, "_check_replacement"):
        missing_result = CLEANUP.main(
            [
                "--key-dir",
                str(key.parent),
                "--node-id",
                "worker-02",
                "--replacement-key",
                str(replacement),
                "--apply",
            ]
        )
    assert missing_result == 0


def test_cleanup_rejects_the_platform_secrets_file() -> None:
    with pytest.raises(ValueError, match="refusing to remove"):
        CLEANUP._targets(Path("/tmp"), [], ["/etc/admiral/secrets"])
