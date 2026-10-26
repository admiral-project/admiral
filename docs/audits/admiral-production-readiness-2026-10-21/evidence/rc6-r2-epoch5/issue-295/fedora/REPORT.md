# Issue #295 — current RC6 Epoch 5 / Release 2 Fedora Rawhide flow

Date: 2026-10-26 UTC. Result is scoped to the exact local candidate Epoch 5: 0.0.1rc6-2.fc46 on Fedora Rawhide x86_64 (rc6r2-fedora-sn, 2 vCPU, 2 GiB RAM), installed from a fresh overlay of the updated Fedora Rawhide seed. Candidate root commit: e710237fd908feabf17b12fb61d08429deb21e52; component pins and RPM NEVRA/SHA-256 are in [the candidate RPM manifest](../../x86_64/RPM-MANIFEST.tsv).

## Result

The originally reported 403 did not reproduce on the current exact candidate using a customer created by Harbor registration and the packaged Harbor API client. No PayPal API or sandbox was called.

- Harbor registration generated customer hcus_f1b22d205549439f; Harbor's authenticated customer-scoped instance read passed for inst_84a6cf7a9377dab1.
- Before expiry, the installed admiral-harbor-worker.service completed with zero errors; the instance remained running and the admin operation inventory contained zero deprovision operations for it.
- After both local test prepaid dates were advanced to 2026-10-25, the installed worker logged Queued deprovision op_335ed98b601f3a77, Actions: 2, Errors: 0. Exactly one deprovision operation existed. Harbor's packaged customer-scoped poller observed it reach succeeded.
- A second worker execution left the deprovision-operation count at one. Harbor's local state became deprovisioned; Podman container, pod, and volume inventories were empty; the Harbor fixture was removed.
- The original synthetic-fixture cause remains unconfirmed. Source code is not changed and this is not claimed as a product fix. Keep #295 open and labeled posible-false-positive until the original fixture's identity mismatch/root cause is reproduced or explained. No matrix-cell result is inferred from this targeted probe.

Implementation trace: admiral-harbor/worker.py::_reconcile_cancelled_subscriptions looks up Customer by the subscription email and passes customer.public_id to admiral_action. The Harbor-generated flow above returned a successful customer-scoped read, then queued and completed the authorized deprovision after expiry.

## Reproduction

On a clean Fedora single-node install of the candidate, install the existing helpers scripts/rc6/issue-295-harbor-flow.py and scripts/rc6/issue-295-poll-operation.py at /tmp. Run them as transient systemd units with User=admiral, WorkingDirectory=/usr/lib/admiral/harbor, EnvironmentFile=/etc/admiral/harbor.env, optional EnvironmentFile=-/etc/admiral/harbor.smtp.env, and PYTHONPATH=/usr/lib/admiral/harbor:

1. Run issue-295-harbor-flow.py with no arguments to register a new Harbor customer, provision e2e-whoami, and create a cancelled subscription with a future prepaid date.
2. Start admiral-harbor-worker.service; record its journal and require zero deprovision operations for the returned instance.
3. Run issue-295-harbor-flow.py expire CUSTOMER_ID; start the worker; require exactly one deprovision operation and zero worker errors.
4. Run issue-295-poll-operation.py OPERATION_ID INSTANCE_ID CUSTOMER_ID 180 under the same transient-unit environment and require succeeded.
5. Start the worker again; require one deprovision total, inspect Harbor state, check rootless Podman resources from /, and run issue-295-harbor-flow.py cleanup CUSTOMER_ID.

The initial cleanup inventory attempt emitted sudo working-directory warnings and is retained as runtime-cleanup.log; it is not counted. The corrected run explicitly changed to /, reported empty container/pod/volume inventories, and is the accepted cleanup evidence in runtime-cleanup-verified.log.

## Evidence

The adjacent SHA256SUMS covers the copied targeted logs, operation records filtered to this instance, and operation ID. The full, access-restricted lab capture remains under /var/lib/libvirt/images/admiral-validation/evidence/rc6-r2-epoch5/issue-295/fedora/.
