# RC6 Epoch 4 / Release 2 — Harbor issue #190 runtime check

**Overall issue result: FAIL / incomplete.** This diagnostic run proves the installed worker preserves cancellation before the prepaid end date, but it fails to deprovision after expiry. It is not a release matrix cell.

## Exact candidate and environment

- Built candidate root commit: `e4a43dd8b64b999186f2906ce153bce26f31e8f2`.
- Candidate package: six native Fedora Rawhide x86_64 RPMs, `Epoch 4`, `Version 0.0.1rc6`, `Release 2.fc46`. RPMs are local-only diagnostic packages; hashes and source pins are in `../rc6-epoch4-issue-294/fedora-rpm-manifest.tsv` and `fedora-source-pins.txt`.
- Guest: `rc6e4-fedora-single`, Fedora Linux 46 Rawhide x86_64, seed `Fedora-Rawhide-seed-20261025-rc6-updated.x86_64.qcow2`.
- The six RPMs were installed from the native Fedora set. `admirald`, Fleet, Harbor, Flagship, PostgreSQL, and Caddy were active. The Harbor reconciliation worker is a oneshot service invoked by its active systemd timer.
- The node was active, healthy, and available. A real `e2e-whoami` instance was provisioned through Admirald and returned HTTP 200 on its loopback endpoint.

## Procedure and results

The test seeded an isolated local Harbor customer/subscription row for the provisioned instance. The subscription was already `cancelled`, its prepaid end was seven days in the future, and `paypal_subscription_id` was NULL. No PayPal endpoint, account, or sandbox was used.

| Check | Expected | Observed | Status |
|---|---|---|---|
| Workload before expiry | Running and HTTP 200 | `running`; local HTTP endpoint returned 200 | PASS |
| Installed worker before expiry | Preserve local cancellation; do not deprovision | systemd oneshot `Result=success`, exit 0; worker `Actions: 0, Errors: 0`; subscription and commercial status stayed `cancelled`, technical state stayed `running` | PASS |
| Installed worker after expiry | Queue exactly one deprovision | Two runs both logged `Deprovision failed after prepaid period ...: access denied`; each worker reported `Actions: 0, Errors: 1`; no operation was queued and instance remained running | FAIL |
| Control-plane cleanup | Remove test workload and local fixture | Admin deprovision operation `op_3aea9f900fffd33e` succeeded; instance reached `deprovisioned`; local Harbor test rows were deleted; no matching rootless Podman container remained | PASS |

## Investigation

The failure was reproduced twice by starting the installed `admiral-harbor-worker.service` with the same expired local fixture. A direct Harbor-authenticated read of the instance also returned HTTP 403 `access denied`. A system-principal read of that same instance returned customer ID `harbor190-fedora-20261025`, matching the Harbor fixture's `Customer.public_id`; a safe comparison confirmed Harbor's configured API token matches the control plane's Harbor token. The source path in `admirald` returns this error when customer ownership comparison fails. The reason the Harbor-authenticated request is evaluated as a different customer remains **unconfirmed** and needs tracing through the authenticated request on the packaged deployment.

The expired worker path is therefore not accepted as fixed. This may be a separate authorization/integration defect from preserving cancellation. Do not relabel #190 as fully runtime-confirmed until the expired path succeeds on a corrected candidate.

## PayPal scope

PayPal is excluded from this round. The fixture had no PayPal subscription ID; the worker's PayPal reconciler selects only `active` or `past_due` subscriptions with a non-NULL provider ID. No real or sandbox PayPal operation was run. Generic package tests involving mocks are not PayPal validation.

## Reproduction artifacts

- `fixture-before.log`, `fixture-after-future.log`, `fixture-expired.log`, `fixture-after-expiry-failure.log`: local Harbor row state.
- `provision-operation.json`, `workload-before-worker.log`: real workload provisioning and HTTP response.
- `worker-future-run.log`, `worker-expired-run.log`, `worker-expired-retry.log`: installed systemd worker evidence.
- `instance-after-failed-expiry.json`, `admin-cleanup-deprovision.json`, `cleanup-verification.log`: failure state and safe cleanup.
- Reproducible helper: `../../scripts/rc6/issue-190-local-fixture.py`.

Reproduction outline on a fresh Fedora seed with this exact package set:

```bash
sudo admiralctl apps apply --file /tmp/e2e-whoami.yaml
sudo admiralctl instances provision --app e2e-whoami --tier small \
  --customer "$HARBOR190_CUSTOMER_ID" \
  --idempotency-key "$HARBOR190_IDEMPOTENCY_KEY" \
  --node "$HARBOR190_NODE_ID" --wait --wait-timeout 10m --output json
# Set HARBOR190_INSTANCE_ID to the returned instance ID and seed the local row:
sudo systemd-run --quiet --wait --pipe --collect \
  -p EnvironmentFile=/etc/admiral/harbor.env \
  -p EnvironmentFile=-/etc/admiral/harbor.smtp.env \
  -p Environment=PYTHONPATH=/usr/lib/admiral/harbor \
  -p WorkingDirectory=/usr/lib/admiral/harbor -p User=admiral \
  /usr/bin/python3 /var/tmp/issue-190-local-fixture.py seed
sudo systemctl start admiral-harbor-worker.service
# The fixture helper's `expire` action advances only its local test dates.
# Run it, start the worker twice, and inspect logs/state; then use `cleanup`.
```

Formal matrix remains **0/6**. This is a scoped issue check on a diagnostic Epoch build and cannot validate a cell or release.
