#!/usr/bin/env python3
"""Ensure RPM source references match the exact checked-out submodules."""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPONENTS = {
    "admirald": "admirald",
    "admiral-fleet": "admiral-fleet",
    "admiralctl": "admiralctl",
    "admiral-flagship": "admiral-flagship",
    "admiral-harbor": "admiral-harbor",
}


def head(path: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT / path), "rev-parse", "HEAD"], text=True).strip()


def spec_ref(name: str) -> str:
    text = (ROOT / "packaging" / "rpm" / f"{name}.spec").read_text()
    match = re.search(r"^%global commit ([0-9a-f]{40})$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"{name}.spec has no %global commit")
    return match.group(1)


def main() -> int:
    failures = []
    for name, path in COMPONENTS.items():
        expected, actual = head(path), spec_ref(name)
        if expected != actual:
            failures.append(f"{name}: spec={actual}, checkout={expected}")
    if failures:
        print("RPM source reference validation failed:", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("RPM source references match checked-out component commits.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
