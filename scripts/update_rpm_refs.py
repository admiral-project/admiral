#!/usr/bin/env python3
"""Pin RPM and Makefile source references without changing release metadata."""

from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = (
    ("ADMIRALD_COMMIT", "admirald", "admirald.spec"),
    ("FLEET_COMMIT", "admiral-fleet", "admiral-fleet.spec"),
    ("ADMIRALCTL_COMMIT", "admiralctl", "admiralctl.spec"),
    ("FLAGSHIP_COMMIT", "admiral-flagship", "admiral-flagship.spec"),
    ("HARBOR_COMMIT", "admiral-harbor", "admiral-harbor.spec"),
)


def git_head(path):
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def replace_once(path, pattern, replacement):
    original = path.read_text()
    updated, count = re.subn(pattern, replacement, original, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"expected one source reference in {path}, found {count}")
    if updated != original:
        path.write_text(updated)


def main():
    makefile = ROOT / "Makefile"
    for variable, directory, spec_name in COMPONENTS:
        commit = git_head(ROOT / directory)
        replace_once(
            makefile,
            rf"^{variable} := [0-9a-f]{{40}}$",
            f"{variable} := {commit}",
        )
        replace_once(
            ROOT / "packaging" / "rpm" / spec_name,
            r"^%global commit [0-9a-f]{40}$",
            f"%global commit {commit}",
        )

    replace_once(
        ROOT / "packaging" / "rpm" / "admiral-common.spec",
        r"^%global commit [0-9a-f]{40}$",
        f"%global commit {git_head(ROOT)}",
    )
    print("RPM source references updated; release and changelog were not modified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as exc:
        raise SystemExit(f"update RPM refs failed: {exc}") from exc
