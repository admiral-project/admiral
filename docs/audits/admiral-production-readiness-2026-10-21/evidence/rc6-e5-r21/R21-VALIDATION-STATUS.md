# RC6 E5 R21 validation status

Updated 2026-10-28 UTC. This report records issue and CI status for the frozen R21 package candidate; it is not a Gold declaration.

## Candidate

- Release: `5:0.0.1rc6-21` (EL10: `.el10`; Fedora Rawhide: `.fc46`). All six RPMs are Release 21.
- The six RPMs were built for their native OS families. Fedora packages were compiled on Fedora Rawhide from the selected source refs; EL10 binaries were not used on Fedora.
- R21 contains the `admirald` product fix `04ec1dd7d5de87906e7560194e94fa4afe087354`. The source SHAs and package checksums are recorded in `source-pins.txt`, `el10/RPM-MANIFEST.tsv`, `el10/SHA256SUMS`, `fedora/RPM-MANIFEST.tsv`, and `fedora/SHA256SUMS`.
- The R21 package build is the product candidate. Later validation-harness and documentation corrections do not change its RPMs or invalidate it.

## GitHub CI

All six workflows completed successfully on the listed exact SHAs:

| Repository | SHA | Result |
|---|---|---|
| `admiral` | `bbf5ac6baba3b473d38a92253b83424f8fdc93a0` | PASS |
| `admirald` | `04ec1dd7d5de87906e7560194e94fa4afe087354` | PASS |
| `admiral-fleet` | `11f788c7efbfd9ea77e2e461a0e53874393c946a` | PASS |
| `admiralctl` | `d0e98414115c9628e59b33678cfcbd9bc0e342d5` | PASS |
| `admiral-flagship` | `9d26a3b0e1e8827b066566fb2ecb98f5cd580a74` | PASS |
| `admiral-harbor` | `48280fdd5ee2779e68edc7873e605c0d80dc60e7` | PASS |

The root packaging commit `fa4838bc4438e9757ffcbdf1a8a1173c3c666cf8` had a harness/gitlink failure. The harness was corrected in `f1f5fda3915de88c5f6735c6141cbf67938564bb`; the root workflow is green on `bbf5ac6`. The correction did not alter installed product artifacts.

## Issue #305 example runs

The R21 example retests used the existing CentOS Stream 10 x86_64 Single-Node VM. No VM was created.

| Example | R21 result | Notes |
|---|---|---|
| `e2e-whoami` | PASS | Lifecycle, PostgreSQL backup/restore with checksum and marker, HTTP 200, cleanup. |
| Uptime Kuma | PASS | Lifecycle and volume restore; `/dashboard` returned HTTP 200; cleanup. |
| Listmonk | PASS | Lifecycle, PostgreSQL marker restore with checksum, HTTP 200, cleanup. See `runtime/listmonk-r21-20261028T052811Z-3042215/REPORT.md`. |
| Vaultwarden | PASS | Lifecycle, volume restore with checksum, HTTP 200, cleanup. |
| WordPress | PASS | DB and volume markers restored with checksums; canonical `Host: localhost` returned HTTP 200; cleanup. A request without that Host header redirects to the configured canonical URL. |
| ERPNext | INCOMPLETE | On official `v15.124.1` amd64 image, setup timed out waiting for `redis-queue`; resource monitor stopped when guest free disk crossed the 1.5 GiB safety floor. No guest OOM was observed. Cleanup succeeded; pause/restart/backup/restore were not run. This does not isolate an Admiral defect. |
| NOW-LMS | BLOCKED BY PUBLISHED IMAGE | Quay `v1.3.4` previously failed in its own migration (`relation "curso" does not exist`). Quay had no newer published image to retry on the date checked. |
| Cacao Accounting | NON-MANDATORY | Attempted and recorded separately. Passing it is not required for #305 or this release gate. |

The host had approximately 32 GiB disk and 4.8 GiB available RAM after ERPNext cleanup. The guest was restored to its 1.5 GiB configuration, retained about 11 GiB free disk, and had R21 RPMs and core services active. No new VM was created.

The issue results and clarification were recorded in [#305 comments 6462156693](https://github.com/admiral-project/admiral/issues/305#issuecomment-6462156693) and [6462253034](https://github.com/admiral-project/admiral/issues/305#issuecomment-6462253034).

## Release gate

The required runtime matrix remains **0/6**: Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide, each in Single-Node and Multi-Node. The targeted #305 example runs do not count as release matrix cells. Issue #305 remains open for ERPNext and NOW-LMS follow-up. PayPal issue #106 is outside this release-validation scope.

**R21 is not Gold.** No product change was made by this report update, so `CANDIDATE_INVALIDATED = NO`.
