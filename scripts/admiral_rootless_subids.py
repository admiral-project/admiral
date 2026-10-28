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


def validate_target(
    path: pathlib.Path, ranges: list[Range], user: str, uid: int | None = None
) -> int:
    owners = {user}
    if uid is not None:
        owners.add(str(uid))
    target = [item for item in ranges if item.owner in owners]
    others = [item for item in ranges if item.owner not in owners]
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


def find_largest_available_range(
    ranges: list[Range], minimum: int, maximum: int
) -> tuple[int, int]:
    if minimum < 0 or maximum < minimum:
        raise ValueError("configured subordinate ID interval is invalid")

    cursor = minimum
    largest_start = minimum
    largest_count = 0
    for item in sorted(ranges, key=lambda entry: entry.start):
        if item.end < minimum:
            continue
        if item.start > maximum:
            break

        occupied_start = max(item.start, minimum)
        occupied_end = min(item.end, maximum)
        if occupied_start > cursor:
            available_count = occupied_start - cursor
            if available_count > largest_count:
                largest_start = cursor
                largest_count = available_count
        cursor = max(cursor, occupied_end + 1)
        if cursor > maximum:
            break

    if cursor <= maximum:
        available_count = maximum - cursor + 1
        if available_count > largest_count:
            largest_start = cursor
            largest_count = available_count

    if largest_count == 0:
        raise ValueError("no contiguous subordinate ID range is available")
    return largest_start, largest_count


def ensure_ranges(
    *,
    uid_path: pathlib.Path,
    gid_path: pathlib.Path,
    user: str,
    uid: int,
    count: int | str,
    uid_minimum: int,
    uid_maximum: int,
    gid_minimum: int,
    gid_maximum: int,
) -> None:
    uid_ranges = parse_ranges(uid_path)
    gid_ranges = parse_ranges(gid_path)
    uid_allocated = validate_target(uid_path, uid_ranges, user, uid)
    gid_allocated = validate_target(gid_path, gid_ranges, user, uid)

    if bool(uid_allocated) != bool(gid_allocated):
        raise ValueError(
            "subuid and subgid assignments are inconsistent; "
            "refusing to change either file"
        )

    if uid_allocated or gid_allocated:
        if count == "max_available" or (
            uid_allocated >= count and gid_allocated >= count
        ):
            print(
                "preserving existing subordinate ID allocations "
                f"(subuid={uid_allocated}, subgid={gid_allocated})"
            )
            return
        raise ValueError(
            "existing subordinate ID assignments are smaller than requested; "
            "refusing to resize or renumber them"
        )

    if count == "max_available":
        uid_start, uid_count = find_largest_available_range(
            uid_ranges, uid_minimum, uid_maximum
        )
        gid_start, gid_count = find_largest_available_range(
            gid_ranges, gid_minimum, gid_maximum
        )
        count = min(uid_count, gid_count)
        if count <= 0:
            raise ValueError("no common subordinate ID capacity is available")
        uid_end = uid_start + count - 1
        gid_end = gid_start + count - 1
    else:
        uid_start, uid_end = find_available_range(
            uid_ranges, uid_minimum, uid_maximum, count
        )
        gid_start, gid_end = find_available_range(
            gid_ranges, gid_minimum, gid_maximum, count
        )

    subprocess.run(
        [
            "/usr/sbin/usermod",
            "--add-subuids",
            f"{uid_start}-{uid_end}",
            "--add-subgids",
            f"{gid_start}-{gid_end}",
            user,
        ],
        check=True,
    )
    uid_allocated = validate_target(uid_path, parse_ranges(uid_path), user, uid)
    gid_allocated = validate_target(gid_path, parse_ranges(gid_path), user, uid)
    if uid_allocated < count or gid_allocated < count:
        raise ValueError("usermod did not allocate the requested subordinate ID ranges")
    print(
        "allocated subordinate ID ranges "
        f"(subuid={uid_start}:{count}, subgid={gid_start}:{count})"
    )


def validate_allocations(
    *, uid_path: pathlib.Path, gid_path: pathlib.Path, user: str, uid: int
) -> tuple[int, int]:
    uid_allocated = validate_target(uid_path, parse_ranges(uid_path), user, uid)
    gid_allocated = validate_target(gid_path, parse_ranges(gid_path), user, uid)
    if not uid_allocated or not gid_allocated:
        raise ValueError("both subuid and subgid allocations must exist")
    return uid_allocated, gid_allocated


def parse_count(value: str) -> int | str:
    if value == "max_available":
        return value
    try:
        count = int(value)
    except ValueError as exc:
        raise ValueError("count must be a positive integer or max_available") from exc
    if count <= 0:
        raise ValueError("count must be a positive integer or max_available")
    return count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare subordinate IDs using policy supplied by Ansible."
    )
    parser.add_argument("--user", default="admiral-apps")
    policy = parser.add_mutually_exclusive_group(required=True)
    policy.add_argument(
        "--count",
        help="positive ID count or max_available; configured by Ansible",
    )
    policy.add_argument(
        "--validate-only",
        action="store_true",
        help="validate existing subuid/subgid ranges without changing them",
    )
    args = parser.parse_args()

    try:
        account = pwd.getpwnam(args.user)
        if args.validate_only:
            uid_total, gid_total = validate_allocations(
                uid_path=SUBUID,
                gid_path=SUBGID,
                user=args.user,
                uid=account.pw_uid,
            )
            print("validated existing subordinate ID allocations")
        else:
            count = parse_count(args.count)
            uid_minimum = login_def_value(LOGIN_DEFS, "SUB_UID_MIN")
            uid_maximum = login_def_value(LOGIN_DEFS, "SUB_UID_MAX")
            gid_minimum = login_def_value(LOGIN_DEFS, "SUB_GID_MIN")
            gid_maximum = login_def_value(LOGIN_DEFS, "SUB_GID_MAX")
            ensure_ranges(
                uid_path=SUBUID,
                gid_path=SUBGID,
                user=args.user,
                uid=account.pw_uid,
                count=count,
                uid_minimum=uid_minimum,
                uid_maximum=uid_maximum,
                gid_minimum=gid_minimum,
                gid_maximum=gid_maximum,
            )
            uid_total, gid_total = validate_allocations(
                uid_path=SUBUID,
                gid_path=SUBGID,
                user=args.user,
                uid=account.pw_uid,
            )
        print(f"effective subordinate ID counts: subuid={uid_total}, subgid={gid_total}")
    except (KeyError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"rootless subordinate ID setup failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
