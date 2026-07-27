#!/usr/bin/python3

import importlib.util
import pathlib
import sys
import tempfile
import unittest


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
