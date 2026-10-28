# RC6 Epoch 5 Release 21 candidate

Updated 2026-10-28 UTC. This is a candidate build and targeted validation report, not a Gold declaration.

## Candidate identity

- Root packaging commit: `fa4838bc4438e9757ffcbdf1a8a1173c3c666cf8`.
- Product fix in `admirald`: `04ec1dd7d5de87906e7560194e94fa4afe087354` (`fix(api): propagate nested database credentials`).
- All six packages are Release 21. EL10 NEVRA: `5:0.0.1rc6-21.el10`; Fedora Rawhide NEVRA: `5:0.0.1rc6-21.fc46`.
- Exact component refs and fetched `origin/main` refs are recorded in [`source-pins.txt`](source-pins.txt). `python3 scripts/validate-release-refs.py` passed before and after packaging.

## Native RPM builds and package checks

- Rocky Linux 10.2 x86_64 native host build: all six EL10 RPMs built and their package checks passed. Detailed build output is retained with the local validation artifacts.
- Fedora Rawhide x86_64 build: all six Fedora RPMs compiled inside Fedora Rawhide from the same selected source refs. No EL10 RPM or binary was used. All package checks passed. Detailed build output is retained with the local validation artifacts.
- `admirald`, `admiral-fleet`, and `admiralctl` Go package checks passed on both build targets. Flagship passed 266 tests and Harbor passed 352 tests on each target.
- Per-distro [`RPM-MANIFEST.tsv`](el10/RPM-MANIFEST.tsv) and [`SHA256SUMS`](el10/SHA256SUMS) identify each signed package. Fedora equivalents are in [`fedora/`](fedora/).
- All 12 RPM package signatures and payload digests, both `repomd.xml` signatures, and repository hashes passed verification against fingerprint `8D2E8FC99FB218979157C5DBFCC63E30ED44F66E`; see [`signature-verification.txt`](signature-verification.txt).
- Signed local repositories: `/var/lib/libvirt/images/admiral-validation/repo/rc6-e5-r21/{el10,fedora}/x86_64`.

## Targeted issue #305 validation

Listmonk passed a real end-to-end lifecycle on the existing CentOS Stream 10 x86_64 Single-Node VM, after installing the six R21 EL10 RPMs. The passing run is summarized in [`R21-VALIDATION-STATUS.md`](R21-VALIDATION-STATUS.md):

- Setup completed; instance `inst_6518df8f3b8d40c7` reached `running/healthy/available` with Listmonk v6.1.0.
- Pause, resume, and restart succeeded; HTTP health returned 200 before and after restart and restore.
- PostgreSQL backup `bk_abd36a994015883d` succeeded with SHA-256 `3d4beb0d14eb7fd84c70662bf1654189899b833c2a302ccdfb1f8f5aa6b65d37`. After changing a database marker, restore with checksum verification returned the marker to `original`.
- Deprovision succeeded, the manual backup was deleted, and no workload containers, pods, or volumes remain.
- No VM was created. During the run the host retained at least 4.07 GiB available RAM and 37.08 GiB available disk; the guest retained at least 382 MiB available RAM and 11.39 GiB available disk. The resource monitor recorded no threshold alerts.

The first R21 Listmonk attempt exposed an example-only configuration error: `LISTMONK_app__address` had host and port split across variables, so v6.1 exited with `missing port in address`. The example now sets `LISTMONK_app__address` to `0.0.0.0:9000`; the new run above passed. The nested DB credentials were present in the generated app and setup secrets, and the application connected to PostgreSQL. The YAML/documentation correction did not change an installed Admiral artifact:

- `PRODUCT_CHANGED = NO`
- `CANDIDATE_INVALIDATED = NO`

This targeted Listmonk run is not a release matrix cell. Cacao Accounting is recorded as an unsuccessful prior attempt but, per the user's clarification, passing Cacao is not mandatory. NOW-LMS remains unsuccessful with the pinned upstream image and prevents closing #305 until its lifecycle is resolved or the issue's scope is changed.

The R21 example runs recorded so far are: `e2e-whoami`, Uptime Kuma, Listmonk, Vaultwarden, and WordPress passed full lifecycle; ERPNext did not complete provisioning on the latest image and its lifecycle remains unverified; NOW-LMS v1.3.4 previously failed inside its upstream migration, and Quay has no newer published image to retry. Cacao Accounting was attempted, but passing it is not mandatory per the user's clarification. Details are in [#305 comment 6462253034](https://github.com/admiral-project/admiral/issues/305#issuecomment-6462253034) and [`R21-VALIDATION-STATUS.md`](R21-VALIDATION-STATUS.md). #305 remains open for the unresolved required examples. Current root-repository issue triage is in [`ISSUE-TRIAGE.md`](ISSUE-TRIAGE.md).

## Release status

Because the Listmonk credential fix changed installed Admiral product, R20 runtime cells do not count for R21. The required matrix is still `0/6` for this exact candidate:

| Operating system | Single-Node | Multi-Node |
|---|---|---|
| Rocky Linux 10 x86_64 | PENDING | PENDING |
| CentOS Stream 10 x86_64 | PENDING | PENDING |
| Fedora Rawhide x86_64 | PENDING | PENDING |

GitHub Actions passed for the exact five component source SHAs selected for R21 and the current root validation commit; see [`ci-status.md`](ci-status.md). #305 remains open. #106 (PayPal sandbox) is outside this release validation scope. **R21 is not Gold** because the required six-cell runtime matrix is still 0/6 and #305 is unresolved.
