# RC6 E5 R21 GitHub CI status

Checked 2026-10-28 UTC against the exact component source SHAs recorded in `source-pins.txt` and current root validation commit `bbf5ac6baba3b473d38a92253b83424f8fdc93a0`.

| Repository | SHA checked | Workflow | Result |
|---|---|---|---|
| `admiral` | `bbf5ac6baba3b473d38a92253b83424f8fdc93a0` | Main Regression Tests | PASS |
| `admirald` | `04ec1dd7d5de87906e7560194e94fa4afe087354` | ci | PASS |
| `admiral-fleet` | `11f788c7efbfd9ea77e2e461a0e53874393c946a` | ci | PASS |
| `admiralctl` | `d0e98414115c9628e59b33678cfcbd9bc0e342d5` | ci | PASS |
| `admiral-flagship` | `9d26a3b0e1e8827b066566fb2ecb98f5cd580a74` | ci | PASS |
| `admiral-harbor` | `48280fdd5ee2779e68edc7873e605c0d80dc60e7` | ci | PASS |

The six GitHub workflow runs completed successfully. The root packaging commit `fa4838bc4438e9757ffcbdf1a8a1173c3c666cf8` had an earlier harness/gitlink failure; the validation harness was corrected in `f1f5fda3915de88c5f6735c6141cbf67938564bb`, without changing packaged product, and current root CI is green. CI success does not substitute for the required six-cell runtime matrix, which remains 0/6. No Gold claim is made.
