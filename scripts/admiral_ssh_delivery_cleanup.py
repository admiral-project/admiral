#!/usr/bin/env python3
# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

"""Inspect and explicitly remove temporary SSH delivery artifacts.

The command is deliberately dry-run by default.  It accepts individual node
identifiers and artifact paths only; it never recursively removes a directory
or deletes the configured operator key without a replacement key.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

NODE_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
DEFAULT_KEY_DIR = Path("/var/lib/admiral/ssh-delivery")
PROTECTED_SECRET_FILE = Path("/etc/admiral/secrets")


def _artifact_info(path: Path) -> str:
    item = path.lstat()
    mode = stat.S_IMODE(item.st_mode)
    age = datetime.fromtimestamp(item.st_mtime, timezone.utc).isoformat()
    kind = "symlink" if path.is_symlink() else "file"
    return f"{path} ({kind}, mode={mode:04o}, modified={age})"


def _targets(key_dir: Path, node_ids: list[str], extra: list[str]) -> list[Path]:
    paths: list[Path] = []
    for node_id in node_ids:
        if not NODE_ID_RE.fullmatch(node_id):
            raise ValueError(f"invalid node id: {node_id!r}")
        paths.extend(
            [
                key_dir / f"{node_id}.ed25519",
                key_dir / f"{node_id}.ed25519.pub",
            ]
        )
    paths.extend(Path(value) for value in extra)
    unique: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.absolute()
        if resolved == PROTECTED_SECRET_FILE:
            raise ValueError("refusing to remove /etc/admiral/secrets; use the encrypted backup workflow")
        if resolved not in seen:
            seen.add(resolved)
            unique.append(resolved)
    return unique


def _check_replacement(path: Path, targets: list[Path]) -> None:
    if not path.is_file() or path.is_symlink():
        raise ValueError("replacement key must be a regular file")
    if path.absolute() in targets:
        raise ValueError("replacement key cannot be one of the cleanup targets")
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise ValueError("replacement key must not be group/world accessible")
    if shutil.which("ssh-keygen") is None:
        raise ValueError("ssh-keygen is required to verify the replacement key")
    result = subprocess.run(
        ["ssh-keygen", "-lf", str(path), "-E", "sha256"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError("replacement key is not a valid SSH private/public key")


def _secure_remove(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"refusing to remove non-regular artifact: {path}")
    shred = shutil.which("shred")
    if not shred:
        raise ValueError("shred is required for cleanup")
    result = subprocess.run([shred, "--force", "--remove", "--zero", str(path)], check=False)
    if result.returncode != 0:
        raise RuntimeError(f"shred failed for {path}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-dir", type=Path, default=DEFAULT_KEY_DIR)
    parser.add_argument("--node-id", action="append", default=[], help="exact node id to inspect/remove")
    parser.add_argument("--artifact", action="append", default=[], help="additional exact file path")
    parser.add_argument("--replacement-key", type=Path, help="already verified operator key required with --apply")
    parser.add_argument("--apply", action="store_true", help="securely remove the listed artifacts")
    args = parser.parse_args(argv)

    try:
        targets = _targets(args.key_dir, args.node_id, args.artifact)
        if not targets:
            parser.error("at least one --node-id or --artifact is required")
        existing = [path for path in targets if os.path.lexists(path)]
        for path in existing:
            print(_artifact_info(path))
        missing = len(targets) - len(existing)
        if missing:
            print(f"{missing} target(s) are already absent")
        if not args.apply:
            print("dry-run: no artifacts removed; use --apply with --replacement-key after verifying access")
            return 0
        if args.replacement_key is None:
            raise ValueError("--replacement-key is required with --apply")
        _check_replacement(args.replacement_key, targets)
        for path in existing:
            _secure_remove(path)
            print(f"removed securely: {path}")
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"cleanup refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
