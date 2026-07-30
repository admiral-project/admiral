#!/usr/bin/env python3
"""Allocate and validate subordinate IDs for Admiral's rootless workload user."""

from __future__ import annotations

import argparse
import pathlib
import pwd
import re
import subprocess
import sys
from dataclasses import dataclass


DEFAULT_COUNT = 131072
LOGIN_DEFS = pathlib.Path("/etc/login.defs")
SUBUID = pathlib.Path("/etc/subuid")
SUBGID = pathlib.Path("/etc/subgid")


@dataclass(frozen=True)
class Range:
    owner: str
    start: int
    count: int

    @property
    def end(self) -> int:
        return self.start + self.count - 1


def parse_ranges(path: pathlib.Path) -> list[Range]:
    ranges: list[Range] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc

    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line:
            continue
        fields = line.split(":")
        if len(fields) != 3:
            raise ValueError(f"{path}:{number}: malformed subordinate ID entry")
        owner, start_raw, count_raw = fields
        try:
            start = int(start_raw)
            count = int(count_raw)
        except ValueError as exc:
            raise ValueError(
                f"{path}:{number}: start and count must be integers"
            ) from exc
        if not owner or start < 0 or count <= 0:
            raise ValueError(f"{path}:{number}: invalid subordinate ID entry")
        ranges.append(Range(owner, start, count))
    return ranges


def login_def_value(path: pathlib.Path, key: str) -> int:
    pattern = re.compile(rf"^\s*{re.escape(key)}\s+(\d+)\s*(?:#.*)?$")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc
    for line in lines:
        match = pattern.match(line)
        if match:
            return int(match.group(1))
    raise ValueError(f"{path}: required setting {key} is missing")


def validate_target(path: pathlib.Path, ranges: list[Range], user: str) -> int:
    target = [item for item in ranges if item.owner == user]
    others = [item for item in ranges if item.owner != user]
    for index, own in enumerate(target):
        for duplicate in target[index + 1 :]:
            if own.start <= duplicate.end and duplicate.start <= own.end:
                raise ValueError(
                    f"{path}: {user} has overlapping ranges "
                    f"{own.start}:{own.count} and {duplicate.start}:{duplicate.count}"
                )
    for own in target:
        for other in others:
            if own.start <= other.end and other.start <= own.end:
                raise ValueError(
                    f"{path}: {user} range {own.start}:{own.count} overlaps "
                    f"{other.owner} range {other.start}:{other.count}"
                )
    return sum(item.count for item in target)


def find_available_range(
    ranges: list[Range], minimum: int, maximum: int, count: int
) -> tuple[int, int]:
    if maximum - minimum + 1 < count:
        raise ValueError("configured subordinate ID interval is too small")
    candidate = minimum
    for item in sorted(ranges, key=lambda entry: entry.start):
        if item.end < candidate:
            continue
        if item.start > candidate and item.start - candidate >= count:
            return candidate, candidate + count - 1
        candidate = max(candidate, item.end + 1)
    if candidate + count - 1 <= maximum:
        return candidate, candidate + count - 1
    raise ValueError(f"no contiguous subordinate ID range of {count} IDs is available")


def ensure_range(
    *,
    path: pathlib.Path,
    user: str,
    count: int,
    minimum: int,
    maximum: int,
    usermod_option: str,
) -> None:
    ranges = parse_ranges(path)
    allocated = validate_target(path, ranges, user)
    if allocated >= count:
        return
    if allocated:
        raise ValueError(
            f"{path}: {user} has only {allocated} subordinate IDs; "
            f"{count} are required"
        )

    start, end = find_available_range(ranges, minimum, maximum, count)
    subprocess.run(
        ["/usr/sbin/usermod", usermod_option, f"{start}-{end}", user],
        check=True,
    )
    allocated = validate_target(path, parse_ranges(path), user)
    if allocated < count:
        raise ValueError(f"{path}: usermod did not allocate the required range")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Safely prepare subordinate IDs for Admiral rootless workloads."
    )
    parser.add_argument("--user", default="admiral-apps")
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT)
    args = parser.parse_args()

    if args.count <= 0:
        parser.error("--count must be positive")
    try:
        pwd.getpwnam(args.user)
        ensure_range(
            path=SUBUID,
            user=args.user,
            count=args.count,
            minimum=login_def_value(LOGIN_DEFS, "SUB_UID_MIN"),
            maximum=login_def_value(LOGIN_DEFS, "SUB_UID_MAX"),
            usermod_option="--add-subuids",
        )
        ensure_range(
            path=SUBGID,
            user=args.user,
            count=args.count,
            minimum=login_def_value(LOGIN_DEFS, "SUB_GID_MIN"),
            maximum=login_def_value(LOGIN_DEFS, "SUB_GID_MAX"),
            usermod_option="--add-subgids",
        )
    except (KeyError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"rootless subordinate ID setup failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
