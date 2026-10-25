# Issue #297 — dev-node Fail2ban readiness

**Result:** PASS for this issue-specific Rocky dev-node case. This is not a release-matrix cell.

## Candidate and environment

- Root source: `05bafe246f3782b50c80a601d49a9a160a2712bf`.
- Diagnostic package: `admiral-common-100:0.0.1rc6-3.el10.noarch` (RPM SHA-256 `67f22b49ff97181ec69af83beb9abc9a55512ba900bbf153df6af6e9777f5c5b`).
- Guest: `rc6e99rocky-devnode`, Rocky Linux 10.2 x86_64, dev-node role.
- Test: reran `admiral-install --dev-node --yes --validation-seed` after installing the Epoch 100 RPM; checked installer completion and final service readiness.

## Expected and observed

Dev mode does not install or enable Fail2ban, so installer readiness must not require it. The install playbook completed and the installer printed its completion summary. Final guest probes showed the Admiral services active and `fail2ban_unit=inactive`, which is expected in dev mode. The run did not fail at the prior `Service fail2ban is not active after remote setup` check.

## Evidence

- Runtime log: [`epoch100-dev-rerun.log`](epoch100-dev-rerun.log), SHA-256 `70db48855b2b998f32030f29ff15667214d76fc32038d502b4dd20977dbe7d4c`.
- Local tests: [`local-tests-after-fix.log`](local-tests-after-fix.log), 160 passed, SHA-256 `9ee1736a12462bc2e87bf329608270c077e85370e3f33749f188941916f85773`.
- The source fix is in root commit `05bafe246f3782b50c80a601d49a9a160a2712bf`; root CI run 40224487657 passed.

## Limits

This targeted dev-node check confirms the readiness regression only. It does not validate secure Single-Node, Multi-Node, or any RC6 release cell.
