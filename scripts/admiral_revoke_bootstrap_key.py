#!/usr/bin/env python3
"""Remove one bootstrap public key from a user's authorized_keys file."""

from __future__ import annotations

import argparse
import os
import pathlib
import pwd
import re
import sys
import tempfile


USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")


def key_material(line: str) -> str:
    fields = line.strip().split()
    for index, field in enumerate(fields):
        if field.startswith(("ssh-", "ecdsa-", "sk-")):
            return " ".join(fields[index : index + 2])
    return ""


def revoke(username: str, bootstrap_key: str) -> bool:
    if not USER_RE.fullmatch(username):
        raise ValueError("invalid SSH username")
    bootstrap_material = key_material(bootstrap_key)
    if not bootstrap_material:
        raise ValueError("invalid bootstrap public key")

    home = pathlib.Path(pwd.getpwnam(username).pw_dir)
    authorized = home / ".ssh" / "authorized_keys"
    if not authorized.exists():
        return False

    lines = authorized.read_text(encoding="utf-8").splitlines(keepends=True)
    kept = [line for line in lines if key_material(line) != bootstrap_material]
    if kept == lines:
        return False

    metadata = authorized.stat()
    fd, temporary = tempfile.mkstemp(
        prefix=".authorized_keys.", dir=str(authorized.parent), text=True
    )
    try:
        os.fchmod(fd, metadata.st_mode & 0o777)
        os.fchown(fd, metadata.st_uid, metadata.st_gid)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.writelines(kept)
        os.replace(temporary, authorized)
    except (OSError, ValueError):
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Revoke one bootstrap SSH public key from authorized_keys."
    )
    parser.add_argument("username")
    parser.add_argument("public_key")
    args = parser.parse_args()
    try:
        removed = revoke(args.username, args.public_key)
    except (OSError, ValueError, KeyError) as exc:
        print(f"bootstrap SSH revocation failed: {exc}", file=sys.stderr)
        return 1
    if not removed:
        print("bootstrap public key was not found in authorized_keys", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
