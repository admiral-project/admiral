# RC6 E5 R26 — CI status

CI state rechecked on 2026-10-29 UTC. All six selected root/component SHAs still have successful GitHub Actions runs. `admiral-common` is an RPM built from the root Admiral repository; GitHub has no separate `admiral-common` repository in the project.

| Repository / source | SHA | Result | Run |
|---|---|---|---|
| Root package preparation (`admiral`) | `71a2cfc16eedd0f686a5e9d52c3f84414024d412` | **FAIL** — four audit-helper assertions still expected Release 21 | [run 40751401997](https://github.com/admiral-project/admiral/actions/runs/40751401997) |
| Root follow-up (`admiral`), helper-only correction | `b6146a46be93f1a9c242361e27b10dbbb2164bf6` | **PASS** — updated test/audit helper defaults to Release 26 | [run 40751882048](https://github.com/admiral-project/admiral/actions/runs/40751882048) |
| `admirald` | `8efa1dec8e9540210d9f86d016dce4677dcc6543` | **PASS** | [run 40750195193](https://github.com/admiral-project/admirald/actions/runs/40750195193) |
| `admiral-fleet` | `edc0a0d486eb102e9aaa4f250a08f777d7441f12` | **PASS** | [run 40750384923](https://github.com/admiral-project/admiral-fleet/actions/runs/40750384923) |
| `admiralctl` | `d0e98414115c9628e59b33678cfcbd9bc0e342d5` | **PASS** | [run 40584258663](https://github.com/admiral-project/admiralctl/actions/runs/40584258663) |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | **PASS** | [run 39795263415](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415) |
| `admiral-harbor` | `dd4818b6e2bc53eea4495fc5e374a4893cfcb107` | **PASS** | [run 40171847383](https://github.com/admiral-project/admiral-harbor/actions/runs/40171847383) |

The root follow-up changed only audit scripts: eight Release defaults from 21 to 26. It changed no RPM spec, packaged payload, product code, component pin, or R26 RPM. Therefore it does not require another RPM build or runtime-cell restart under the product-change-only invalidation rule. The root package-preparation commit's failed run remains part of the evidence and is not hidden by the follow-up result.
