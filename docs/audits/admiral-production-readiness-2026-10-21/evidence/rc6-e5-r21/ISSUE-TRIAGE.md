# R21 open-issue triage

Checked against the live `admiral-project/admiral` issue tracker on 2026-10-28. The open-issue search returned two issues in this repository.

| Issue | State | R21 status | Remaining work |
|---|---|---|---|
| [#305](https://github.com/admiral-project/admiral/issues/305) — validate example apps definitions | Open | On R21, `e2e-whoami`, Uptime Kuma, Listmonk, Vaultwarden, and WordPress passed lifecycle checks. Cacao Accounting passing is not mandatory per the user's clarification. | ERPNext provisioning did not complete on the latest pinned image, so its lifecycle is unverified. NOW-LMS v1.3.4 failed in its upstream migration; the public Quay registry has no newer image to retry. See [comment 6462156693](https://github.com/admiral-project/admiral/issues/305#issuecomment-6462156693). |
| [#106](https://github.com/admiral-project/admiral/issues/106) — PayPal sandbox E2E alpha gate | Open | Outside this release-validation scope. | PayPal's verified integration is a separate 1.0 gate. It does not block the current six-cell runtime matrix. |

No issue was closed. R21 is not Gold: #305 remains unresolved and the R21 release runtime matrix is 0/6. #106 remains open but is outside this release-validation scope.
