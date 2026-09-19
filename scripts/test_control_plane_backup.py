#!/usr/bin/env python3
"""Contract checks for the encrypted control-plane backup workflow."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKUP = (ROOT / "scripts/admiral_control_plane_backup.sh").read_text(encoding="utf-8")
GUIDE = (ROOT / "docs/sysadmin_guide.md").read_text(encoding="utf-8")
SERVICE = (ROOT / "packaging/systemd/admiral-control-plane-backup.service").read_text(encoding="utf-8")
TIMER = (ROOT / "packaging/systemd/admiral-control-plane-backup.timer").read_text(encoding="utf-8")


def test_backup_contains_all_control_plane_databases_and_runtime_material() -> None:
    assert "for database in admiral admiral_queue admiral_harbor" in BACKUP
    assert 'cp -a "$SECRETS_FILE"' in BACKUP
    assert 'cp -a /etc/admiral/tls' in BACKUP
    assert 'cp -a /etc/wireguard/wg-admiral.conf' in BACKUP


def test_backup_encrypts_checksums_and_requires_sse() -> None:
    assert "--symmetric --cipher-algo AES256" in BACKUP
    assert "sha256sum \"$encrypted\"" in BACKUP
    assert 'x-amz-server-side-encryption: AES256' in BACKUP
    assert "remote_length" in BACKUP
    assert "local_length" in BACKUP


def test_backup_is_packaged_and_recovery_runbook_is_actionable() -> None:
    assert "ExecStart=/usr/bin/admiral-control-plane-backup" in SERVICE
    assert "ReadWritePaths=/var/lib/admiral/control-plane-backups" in SERVICE
    assert "OnCalendar=*-*-* 03:00:00 UTC" in TIMER
    assert "pg_restore" in GUIDE
    assert "sha256sum -c" in GUIDE
    assert "control-plane recovery validation" in GUIDE.lower()
