# Issue #295 — Fedora Rawhide, RC6 Epoch 5 / Release 8

**Result: the reported 403 did not reproduce; no product defect was found.**
Both the supported Harbor API provision flow and a reproduction of the reported
mixed fixture (Harbor-generated customer, `admiralctl` provision, manually
attached cancelled-subscription rows) succeeded on the exact R8 candidate.
The test used Fedora Rawhide x86_64 and native `.fc46` RPMs. No PayPal service
or sandbox was contacted.

## Candidate and guest

- Candidate `rc6-e5-r8`, `0.0.1rc6`, Epoch 5, Release 8.
- Guest `rc6r8-fedora-single`, Fedora Rawhide x86_64, installed from the signed
  local repository. Final package NEVRAs are recorded in the candidate Fedora
  manifest; the full Single-Node cell also passed on this guest.
- The installed Harbor worker ran as its packaged systemd service. Test helper
  scripts ran under the installed Harbor Python environment and used the
  packaged Harbor API client for customer-scoped reads and operation polling.

## Reproduction results

1. **Harbor-created flow:** registration generated an `hcus_` customer and the
   Harbor API client provisioned the workload. Its authenticated customer
   scoped read passed. Before prepaid expiry, the worker reported zero errors
   and no deprovision operation. After both local test dates were moved into
   the past, the worker queued exactly one operation; it succeeded, a repeat
   worker run did not duplicate it, and the final Harbor state was
   `deprovisioned`.
2. **Reported mixed fixture:** Harbor registration generated the customer ID,
   `admiralctl instances provision` created the instance for that customer,
   and the cancelled `Subscription`/`CustomerApp` rows were attached in
   Harbor's local database with `paypal_subscription_id` unset. Harbor's
   authenticated customer-scoped read returned `PASS` (not 403). Before
   expiry, there were zero deprovision operations. After expiry, the worker
   queued exactly one operation with `Errors: 0`; it reached `succeeded`. A
   second worker run preserved the single-operation count, and Harbor reported
   `deprovisioned`.

Both test customers were deleted after their workloads were deprovisioned.
Direct rootless Podman, systemd-unit, and filesystem checks found no resources
for either test instance. The report does not claim a product fix: the original
403 was not reproduced with the reported combination on the current exact
candidate. This supports closing #295 as not reproducible / false positive,
with no source change.

## Evidence files

- `cli-register.log`, `cli-provision.json`, `cli-fixture-attach.log`: generated
  Harbor customer plus CLI-created instance and attached fixture.
- `cli-preexpiry-worker.log`, `cli-preexpiry-operations.json`: no early
  deprovision.
- `cli-expiry-state.log`, `cli-expiry-worker.log`,
  `cli-expiry-operations.json`, `cli-operation-poll.log`: one successful
  post-expiry deprovision.
- `cli-repeat-worker.log`, `cli-repeat-operations.json`,
  `cli-postexpiry-state.log`: no duplicate and final Harbor state.
- `cli-cleanup.log`, `cli-runtime-cleanup.log`: fixture and runtime cleanup.
- The `preexpiry-*`, `expiry-*`, `operation-poll.log`, `repeat-*`,
  `postexpiry-state.log`, and `runtime-cleanup-verified.log` files record the
  independent supported Harbor API flow.

`SHA256SUMS` covers the report and all collected evidence in this directory.
