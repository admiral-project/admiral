#!/usr/bin/env python3
"""Read one validated bootstrap value from Admirald's known-host inventory."""

from __future__ import annotations

import argparse
import pathlib
import sys

import yaml


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("role", choices=("worker", "portal"))
    parser.add_argument("field", choices=("node_id", "wireguard_ip"))
    parser.add_argument(
        "path", nargs="?", default="/var/lib/admiral/know_host.yaml"
    )
    args = parser.parse_args()

    try:
        with pathlib.Path(args.path).open(encoding="utf-8") as stream:
            document = yaml.safe_load(stream) or {}
    except (OSError, yaml.YAMLError) as exc:
        print(f"invalid know_host.yaml: {exc}", file=sys.stderr)
        return 2

    if not isinstance(document, dict):
        print("invalid know_host.yaml: top-level document must be a mapping", file=sys.stderr)
        return 2
    next_assignments = document.get("next")
    if not isinstance(next_assignments, dict):
        print("invalid know_host.yaml: missing next mapping", file=sys.stderr)
        return 2
    assignment = next_assignments.get(args.role)
    if not isinstance(assignment, dict):
        return 1
    value = assignment.get(args.field)
    if not isinstance(value, str) or not value.strip():
        return 1
    print(value.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
