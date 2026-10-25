# Issue #181 — customer backup-policy E2E evidence

**Result: PASS for the issue-specific Rocky Linux 10 Multi-Node scenario.** The issue remains open; this is scoped evidence on a local diagnostic package set, not a completed matrix cell or release approval.

## Candidate and environment

- Candidate: local-only RPMs `Epoch 2:0.0.1rc6-4.el10`; package NEVRA and SHA-256 values are recorded in [`rc6-epoch2-rocky-el10-rpm-manifest.tsv`](../rc6-epoch2-rocky-el10-rpm-manifest.tsv). Manifest SHA-256: `95e65238e751825fbc82786ca4d86aa777ee607cfba341ef39686e2c4de4fdc4`.
- Source pins at build time: `admirald 421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`, `admiral-fleet fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`, `admiralctl fa2a65e866310bd82bea78859804b6c3aea7989a`, `admiral-flagship b7325bbc71fc474a521496e593b2967e4d555ac1`, `admiral-harbor dd4818b6e2bc53eea4495fc5e374a4893cfcb107` (includes Harbor UI fix `034924d`).
- OS and architecture: Rocky Linux 10.2 x86_64 on all guests.
- Topology: Admin `192.168.122.208` / WG `10.99.0.1`; Worker `192.168.122.209` / WG `10.99.0.2`; independent Portal `192.168.122.249` / WG `10.99.0.100`.
- Portal requests used `https://portal.rc6.test` through Caddy with an explicit lab CA. The E2E clients used certificate verification; no TLS verification bypass was used.
- The six installed packages were verified on their respective roles. The exact `rpm -qa` captures are in `run-b/`.

## Procedure and observed result

The disposable app definition `fixtures/e2e-backup-policy.yaml` stores a tier snapshot with `manual_backups=true`, `backup_database=false`, `backup_volumes=true`, and `restore_allowed=false`. Its app service declares a volume backup target and its database declares a database backup target.

The harness performed customer registration, verified that a pending account could not log in, approved it through Harbor administration, published the app, and deployed it from the independent Portal to the Worker. Provisioning converged to `running/healthy/available` before the policy probe.

The probe then verified:

1. Harbor omitted the database “Request backup” control and the restore form.
2. A forged Harbor database-backup form was denied. The same customer-scoped Admiral API request returned HTTP 403 with `Manual database backups are disabled for this tier`.
3. After pausing the instance, a forged Harbor remote-restore form was denied. The customer-scoped Admiral API request returned HTTP 403 with `Restore is disabled for this tier`.
4. A second approved customer received HTTP 404 for the first customer's instance.
5. Before/after inventory in `run-a/` shows only the provision and pause operations, zero backup records, and zero restore-request rows. The repeated run in `run-b/` produced the same policy result.
6. Deprovision succeeded. The instance became `deprovisioned`; the Worker had no remaining containers, pods, or volumes.

The successful combined run is `run-a/`; `run-b/` is an additional full pass through the final reusable probe helper. Both used the same Epoch 2/R4 package bytes and source pins. An earlier diagnostic invocation encountered a duplicate secondary test account and was not counted as a pass; it is excluded from these evidence directories.

## Reproduction

From the repository root, on the isolated Portal guest after applying the fixture and provisioning an instance for the owning customer:

```bash
python3 docs/audits/admiral-production-readiness-2026-10-21/scripts/rc6/backup-policy-customer-probe.py
```

Provide the `HARBOR_TEST_*` environment variables listed at the top of that script. Credentials are test-only and must be supplied from a protected environment file; do not put them in this repository or evidence bundle. Set `HARBOR_TEST_CA_CERT` to the lab CA and `HARBOR_TEST_ADMIRAL_CA_CERT` to the CA used by the Harbor-to-Admirald connection.

## Interpretation

This confirms the `manual=true / database=false / volume=true` UI and API regression on a real Rocky three-guest deployment. The denied requests created neither backup nor restore work. This does not validate Harbor-upload restore (#182), stale-task replay after restart (#229), any other OS, any Single-Node cell, or the complete functional matrix. Epoch-bearing RPMs are diagnostic only and are not publishable release artifacts.
