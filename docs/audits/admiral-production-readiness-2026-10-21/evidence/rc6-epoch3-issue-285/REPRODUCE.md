# Reproducing issue #285

Use a fresh disposable Single-Node guest and the exact candidate RPM set under test. The audit runner must receive that guest's actual hostname as its third argument. It derives the expected local worker ID from the hostname and checks that the single registered worker is active, healthy, and available before running the workload lifecycle.

For the recorded diagnostic candidate, the relevant invocation was:

```bash
RC6_EXPECTED_EPOCH=3 RC6_PACKAGE_RELEASE=5 \
  docs/audits/admiral-production-readiness-2026-10-21/scripts/rc6/run-single-lane.sh \
  rocky GUEST_IP GUEST_HOSTNAME
```

Repeat with `fedora`. Keep each guest hostname unique and pass it exactly as supplied to the installer. The run log must show `node=GUEST_HOSTNAME`, one matching worker in `nodes.json`, successful create and same-key idempotency replay, successful deprovision, and no matching rootless Podman/systemd resources.

The archived `failed-pre-fix/` logs are the original Release 1 failures. The `passed-e3r5/` logs are the corrected complete Release 5 diagnostic runs. Do not count them as final no-Epoch release-cell evidence.
