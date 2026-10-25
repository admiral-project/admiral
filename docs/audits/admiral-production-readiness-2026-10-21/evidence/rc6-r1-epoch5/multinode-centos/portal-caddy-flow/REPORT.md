# RC6 Epoch 5 independent Portal customer flow

**Result:** scoped end-to-end flow PASS on CentOS Stream 10 x86_64; this is not a Multi-Node cell PASS.

- Candidate: native `5:0.0.1rc6-1.el10` package set, exact identities and hashes in [`../../CANDIDATE.md`](../../CANDIDATE.md) and candidate manifests.
- Guests: Admin `10.77.0.20`, Worker `10.77.0.21`, independent Portal `10.77.0.22`.
- Route: Portal guest resolved `portal.rc6.test` through Admin Caddy. The test used the lab CA and did not disable TLS verification.
- Reproduction helper: [`../../../../scripts/rc6/independent-portal-caddy-launch.py`](../../../../scripts/rc6/independent-portal-caddy-launch.py), which lowercases the generated UTC timestamp in its synthetic email. The first failed attempt is retained in `attempt-1-failure.md`; the corrected full flow output is `attempt-2-output.log`.

## Observations

1. Registration created a pending account; login was rejected before approval.
2. Admin approved the generated Harbor account; the published free catalog was visible to that customer.
3. Customer deployment created instance `inst_0eef6e5b468e70e2` on Worker `rc6e5cs-worker`; provisioning operation `op_fbdff6fb8b513a43` succeeded.
4. App hostname `e2e-portal-free188693.apps.rc6.test` returned HTTP 200 through Admin Caddy with TLS verify result 0 (`app-route.log`).
5. A SQL marker was inserted and read back in the workload database (`sql-marker.log`).
6. Deprovision operation `op_10fb9658c11e0d46` succeeded. Worker rootless Podman inventory then contained only the pre-existing unrelated test instance; there were no containers matching this instance. The Harbor worker reconciled the terminal state, and the disposable account/subscription/app rows were removed (`cleanup-attempt2.log`).

## Issue #299 harness correction

The initial launcher generated mixed-case `T`/`Z` in the UTC timestamp, while Harbor persisted lower-case email addresses. The first run's failed assertion and DB diagnosis are retained in `attempt-1-failure.md`. Lowercasing the generated suffix fixed the harness; the corrected registration-to-deployment flow passed on the same installed Epoch 5 candidate. This is a validation-script correction, not a product RPM fix. See root issue [#299](https://github.com/admiral-project/admiral/issues/299).

## New issue #300

During safe cleanup, a second deprovision request after the first terminal success created a second successful operation/task (`op_9855ef8118cabab1`, `deprovision-attempt2.json`) for the already deprovisioned instance. The runtime remained clean, but duplicate terminal actions are not idempotent at the operation layer. This is tracked as [#300](https://github.com/admiral-project/admiral/issues/300). Do not count #300 as fixed in the Epoch 5 RPMs. A minimal Admirald guard and regression test have been added to source commit `aec9914`; the RPM candidate must be rebuilt and tested before counting it as fixed.

The SQL marker log and app route log were captured before teardown. A post-teardown marker command correctly reported that the database container no longer existed; that expected cleanup result is separate from the successful pre-teardown marker proof.

All logs are scoped to synthetic `example.test` identities and contain no credentials. SHA-256 values are recorded in the directory manifest.
