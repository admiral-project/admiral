# RC6 E5 R20 CI status

Status captured 2026-10-28 UTC for the selected package source SHAs and current root release-validation branch.

| Repository | Candidate SHA | CI result | Run |
|---|---|---|---|
| `admiral` root validation branch | `e668cd2b191374c62f69a1b47b4258674a4b8331` | PASS | [40609236603](https://github.com/admiral-project/admiral/actions/runs/40609236603) |
| `admirald` | `4472cd8defc2de9c649ddbc1108a0aa64c0f1859` | PASS | [40607276943](https://github.com/admiral-project/admirald/actions/runs/40607276943), draft PR [#64](https://github.com/admiral-project/admirald/pull/64) |
| `admiral-fleet` | `11f788c7efbfd9ea77e2e461a0e53874393c946a` | PASS | [40534518833](https://github.com/admiral-project/admiral-fleet/actions/runs/40534518833) |
| `admiralctl` | `d0e98414115c9628e59b33678cfcbd9bc0e342d5` | PASS | [40584258663](https://github.com/admiral-project/admiralctl/actions/runs/40584258663) |
| `admiral-flagship` | `9d26a3b0e1e8827b066566fb2ecb98f5cd580a74` | PASS | [40534546152](https://github.com/admiral-project/admiral-flagship/actions/runs/40534546152) |
| `admiral-harbor` | `48280fdd5ee2779e68edc7873e605c0d80dc60e7` | PASS | [40534540993](https://github.com/admiral-project/admiral-harbor/actions/runs/40534540993) |

The initial root run `40607198151` failed four script-default assertions because audit runners still selected Release 19 while all RPM specs had moved to Release 20. The eight stale defaults were corrected in root validation-only tooling; `python3 -m pytest -q scripts/test_audit_release_defaults.py` then passed **12 tests**. Root runs `40607373399`, `40609119582`, and `40609236603` passed on subsequent validation branch commits.

These results cover the selected repository commits and Release 20 build/validation tooling. They do **not** satisfy the six installed-RPM runtime cells. Issue #255’s live R20 multi-node E2E gate passed and the issue was closed; that issue-specific run does not count as one of the six full matrix cells. See `runtime/preflight-status.md` and the linked run evidence.
