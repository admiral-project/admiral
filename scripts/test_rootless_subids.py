#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("admiral_rootless_subids.py")
SPEC = importlib.util.spec_from_file_location("admiral_rootless_subids", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class RootlessSubordinateIDTests(unittest.TestCase):
    def write_ranges(self, contents: str) -> pathlib.Path:
        temporary = tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False)
        self.addCleanup(pathlib.Path(temporary.name).unlink)
        temporary.write(contents)
        temporary.close()
        return pathlib.Path(temporary.name)

    def test_finds_first_available_gap(self) -> None:
        ranges = [
            MODULE.Range("first", 524288, 65536),
            MODULE.Range("second", 720896, 65536),
        ]
        self.assertEqual(
            MODULE.find_available_range(ranges, 524288, 1000000, 131072),
            (589824, 720895),
        )

    def test_finds_largest_available_gap(self) -> None:
        ranges = [
            MODULE.Range("first", 524288, 65536),
            MODULE.Range("second", 720896, 65536),
        ]
        self.assertEqual(
            MODULE.find_largest_available_range(ranges, 524288, 1000000),
            (786432, 213569),
        )

    def test_largest_available_gap_respects_login_defs_bounds(self) -> None:
        ranges = [MODULE.Range("other", 10, 5)]
        self.assertEqual(
            MODULE.find_largest_available_range(ranges, 12, 20),
            (15, 6),
        )

    def test_parses_max_available_policy_and_explicit_count(self) -> None:
        self.assertEqual(MODULE.parse_count("max_available"), "max_available")
        self.assertEqual(MODULE.parse_count("32768"), 32768)
        for invalid in ("", "0", "-1", "many"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    MODULE.parse_count(invalid)

    def test_rejects_target_overlap(self) -> None:
        path = self.write_ranges(
            "admiral-apps:524288:131072\nother:589824:65536\n"
        )
        with self.assertRaisesRegex(ValueError, "overlaps other"):
            MODULE.validate_target(
                path, MODULE.parse_ranges(path), "admiral-apps"
            )

    def test_accepts_sufficient_non_overlapping_range(self) -> None:
        path = self.write_ranges(
            "admiral-apps:524288:131072\nother:720896:65536\n"
        )
        self.assertEqual(
            MODULE.validate_target(
                path, MODULE.parse_ranges(path), "admiral-apps"
            ),
            131072,
        )

    def test_validates_numeric_user_owner(self) -> None:
        path = self.write_ranges("991:524288:131072\nother:720896:65536\n")
        self.assertEqual(
            MODULE.validate_target(
                path, MODULE.parse_ranges(path), "admiral-apps", uid=991
            ),
            131072,
        )

    def test_validate_allocations_requires_both_existing_ranges(self) -> None:
        uid_path = self.write_ranges("admiral-apps:100:20\n")
        gid_path = self.write_ranges("991:200:30\n")
        self.assertEqual(
            MODULE.validate_allocations(
                uid_path=uid_path,
                gid_path=gid_path,
                user="admiral-apps",
                uid=991,
            ),
            (20, 30),
        )

        empty_gid_path = self.write_ranges("")
        with self.assertRaisesRegex(ValueError, "both subuid and subgid"):
            MODULE.validate_allocations(
                uid_path=uid_path,
                gid_path=empty_gid_path,
                user="admiral-apps",
                uid=991,
            )

    def test_max_available_uses_common_capacity_and_is_idempotent(self) -> None:
        uid_path = self.write_ranges("other:100:20\n")
        gid_path = self.write_ranges("group:100:30\n")

        def add_user_ranges(argv: list[str], check: bool) -> None:
            self.assertTrue(check)
            uid_range = argv[argv.index("--add-subuids") + 1]
            gid_range = argv[argv.index("--add-subgids") + 1]
            uid_start, uid_end = map(int, uid_range.split("-"))
            gid_start, gid_end = map(int, gid_range.split("-"))
            with uid_path.open("a", encoding="utf-8") as stream:
                stream.write(f"admiral-apps:{uid_start}:{uid_end - uid_start + 1}\n")
            with gid_path.open("a", encoding="utf-8") as stream:
                stream.write(f"admiral-apps:{gid_start}:{gid_end - gid_start + 1}\n")

        with mock.patch.object(MODULE.subprocess, "run", side_effect=add_user_ranges) as run:
            MODULE.ensure_ranges(
                uid_path=uid_path,
                gid_path=gid_path,
                user="admiral-apps",
                uid=991,
                count="max_available",
                uid_minimum=100,
                uid_maximum=199,
                gid_minimum=100,
                gid_maximum=199,
            )
            self.assertEqual(run.call_count, 1)
            MODULE.ensure_ranges(
                uid_path=uid_path,
                gid_path=gid_path,
                user="admiral-apps",
                uid=991,
                count="max_available",
                uid_minimum=100,
                uid_maximum=199,
                gid_minimum=100,
                gid_maximum=199,
            )
            self.assertEqual(run.call_count, 1)

        uid_allocated = MODULE.validate_target(
            uid_path, MODULE.parse_ranges(uid_path), "admiral-apps", 991
        )
        gid_allocated = MODULE.validate_target(
            gid_path, MODULE.parse_ranges(gid_path), "admiral-apps", 991
        )
        self.assertEqual(uid_allocated, 70)
        self.assertEqual(gid_allocated, 70)

    def test_rejects_inconsistent_existing_subuid_and_subgid_assignments(self) -> None:
        uid_path = self.write_ranges("admiral-apps:100:20\n")
        gid_path = self.write_ranges("")
        with self.assertRaisesRegex(ValueError, "assignments are inconsistent"):
            MODULE.ensure_ranges(
                uid_path=uid_path,
                gid_path=gid_path,
                user="admiral-apps",
                uid=991,
                count="max_available",
                uid_minimum=100,
                uid_maximum=199,
                gid_minimum=100,
                gid_maximum=199,
            )

    def test_rejects_duplicate_target_ranges(self) -> None:
        path = self.write_ranges(
            "admiral-apps:524288:131072\nadmiral-apps:524288:131072\n"
        )
        with self.assertRaisesRegex(ValueError, "overlapping ranges"):
            MODULE.validate_target(
                path, MODULE.parse_ranges(path), "admiral-apps"
            )

    def test_rejects_malformed_entries(self) -> None:
        path = self.write_ranges("broken:entry\n")
        with self.assertRaisesRegex(ValueError, "malformed"):
            MODULE.parse_ranges(path)


if __name__ == "__main__":
    unittest.main()
