# Issue #298 — Harbor background-service dev environment

**Result:** PASS for the targeted dev-mode runtime and secure-cleanup checks on Rocky. This is not a release-matrix cell.

## Candidate and environment

- Root source: `cd98098a02c94fb3976e98c6214409bfe07e130e`.
- Diagnostic RPM: `admiral-common-101:0.0.1rc6-3.el10.noarch`; SHA-256 `0e1d936d9b6aa29ceb48a672d99619ec4571d061fb6db9cc49f7221d0b22bb96`.
- RPM build log: [`epoch101-rpm-build.log`](epoch101-rpm-build.log), SHA-256 `4c21817aee365ae30873b380d17f6214e544a2356a0ce79b9e6786162e71ee39`.
- Guest: `rc6e99rocky-devnode`, Rocky Linux 10.2 x86_64, disposable KVM VM.

## Procedure and results

1. Installed the locally built Epoch 101 package and reran `admiral-install --dev-node --yes --validation-seed`.
2. Confirmed both `admiral-harbor-worker.service` and `admiral-harbor-catalog-sync.service` have effective `ENV=development` from the package-managed systemd drop-ins.
3. Started both one-shot units and checked `Result=success` and `ExecMainStatus=0`. `inactive` is their expected final systemd state after successful one-shot completion. The worker reported zero actions and zero errors. Catalog sync completed successfully with zero catalog changes.
4. Reconciled the same VM to secure Single-Node as part of #213. Both dev-mode drop-ins were removed and both units returned to `ENV=production`.

## Evidence

- Runtime log, including the retained before-fix catalog-sync failure and both post-fix service runs: [`epoch101-runtime-rerun.log`](epoch101-runtime-rerun.log), SHA-256 `95821985bf9ac55331e6a6b77cf980b09071678c2c230fa701440e035b98760c`.
- Local regression suite: [`local-tests-final.log`](local-tests-final.log), 160 passed plus Ansible syntax check, SHA-256 `a0d54ae02ae39b81a614862492ee6ff9cca9e73d222c30af9bbf306dbcbb07c3`.
- Root commit `cd98098a02c94fb3976e98c6214409bfe07e130e`; root CI run 40224927082 passed.

## Limits

The Harbor worker ran against an empty test queue and catalog sync observed an empty catalog. This proves startup, security initialization, database access, and successful one-shot completion in the dev profile. It does not validate customer workflows, secure-mode behavior beyond removal of the overrides, or an RC6 release cell.
