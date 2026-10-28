# RC6 E5 R20 CI status

Updated 2026-10-28 UTC.

- Root Release 20 run `40607198151` failed in `scripts/test_audit_release_defaults.py`: four assertions found audit installer defaults at Release 19 while the six RPM specs were at Release 20. The remaining regression assertions passed.
- Updated the eight affected candidate installer and RC6 runner defaults to Release 20. This is validation tooling; it does not change product binaries or invalidate a runtime cell.
- Focused local verification after the adjustment: `python3 -m pytest -q scripts/test_audit_release_defaults.py` — **12 passed**.
- `admirald` draft PR [#64](https://github.com/admiral-project/admirald/pull/64) has its CI run `40607276943` in progress. No green status is claimed yet.
- The corrected root branch push will trigger a new run for PR #303. Its result remains pending.
