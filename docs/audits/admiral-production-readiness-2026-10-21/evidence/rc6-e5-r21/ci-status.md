# RC6 E5 R21 GitHub CI status

Checked 2026-10-28 UTC against the exact component source SHAs recorded in `source-pins.txt` and current root report commit `726a8f411a4c81a1f0eedf40afad34e282b380b3`.

| Repository | SHA checked | Workflow | Result |
|---|---|---|---|
| `admiral` | `726a8f411a4c81a1f0eedf40afad34e282b380b3` | Main Regression Tests | PASS |
| `admirald` | `04ec1dd7d5de87906e7560194e94fa4afe087354` | ci | PASS |
| `admiral-fleet` | `11f788c7efbfd9ea77e2e461a0e53874393c946a` | ci | PASS |
| `admiralctl` | `d0e98414115c9628e59b33678cfcbd9bc0e342d5` | ci | PASS |
| `admiral-flagship` | `9d26a3b0e1e8827b066566fb2ecb98f5cd580a74` | ci | PASS |
| `admiral-harbor` | `48280fdd5ee2779e68edc7873e605c0d80dc60e7` | ci | PASS |

The six GitHub workflow runs completed successfully for their exact source refs. The root packaging commit `fa4838bc4438e9757ffcbdf1a8a1173c3c666cf8` had an earlier harness/gitlink failure; the validation harness was corrected in `f1f5fda3915de88c5f6735c6141cbf67938564bb`, without changing packaged product, and root CI is green on `726a8f4`. CI success does not substitute for the required six-cell runtime matrix, which is now 1/6. No Gold claim is made.
