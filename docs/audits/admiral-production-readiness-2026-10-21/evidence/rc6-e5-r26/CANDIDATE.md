# RC6 E5 R26 candidate

Candidate package identity: Epoch 5, Version 0.0.1rc6, Release 26. EL10 suffix `.el10`; Fedora Rawhide suffix `.fc46`; architecture x86_64.

R26 contains the Admirald product fix for the R25 resize/backup-policy defect: the validated target tier is retained with the resize operation so successful resize does not erase the tier's backup authorization policy. The fix is in admirald at `8efa1dec8e9540210d9f86d016dce4677dcc6543`, with targeted regression coverage and green exact-SHA CI. The six coordinated RPM specs are all Release 26. Selected refs and origin/main comparisons are in `source-pins.txt`; refs were fetched and compared again immediately before the Fedora build in `source-pins-pre-fedora-build.txt`.

R25 is not an accepted candidate: its Fedora Multi-Node backup-after-resize check found the defect. R25 runtime results remain historical and do not substitute for R26 evidence.

The six `.el10` RPMs were built natively on Rocky Linux 10.2 with `%check` enabled. The six `.fc46` RPMs were built in the cached Fedora Rawhide 46 image, with `%check` enabled and no EL10 RPMs used in the builder. Both builds and all package checks passed. Exact NEVRA, SHA-256 and sizes are recorded in `el10-RPM-MANIFEST.tsv`, `el10-SHA256SUMS`, `fedora/RPM-MANIFEST.tsv`, and `fedora/SHA256SUMS`.

The R26 six-cell runtime matrix is **6/6 PASS** on the exact native RPM candidate. Reports are in `runtime/fedora-single/`, `runtime/fedora-multi/`, `runtime/rocky-multi/`, and `runtime/centos-multi/`. No product code, package, or source pin changed during these runtime validations.

## CI status

All five component repositories have successful CI runs for the selected source SHAs. `admiral-common` is packaged from the root Admiral repository and is not a separate GitHub repository. The root packaging commit `71a2cfc16eedd0f686a5e9d52c3f84414024d412` had a failed CI run: four audit-helper assertions still expected Release 21. Follow-up root commit `b6146a46be93f1a9c242361e27b10dbbb2164bf6` updated only test/audit helper defaults to Release 26 and passed CI. That follow-up changed no RPM payload, spec, product source, or submodule pin, so it did not require a rebuild or runtime retest. See `R26-CI-STATUS.md` for exact runs.

R26 is **not Gold**. Issue #307 remains open at 82/111 checked controls: 82 PASS, 19 PARTIAL, 10 NOT TESTED, and 0 confirmed FAIL. H.8 was newly verified with effective listener captures on CentOS Multi; the full security report and residual-risk register remain in #307. PayPal issue #106 is outside this candidate's release scope because it requires external services. Tracker #308 records all six runtime cells as PASS and remains open for final acceptance. PR #303 is open and unmerged. Complete owner acceptance of the residual security risks and final release acceptance before claiming Gold.
