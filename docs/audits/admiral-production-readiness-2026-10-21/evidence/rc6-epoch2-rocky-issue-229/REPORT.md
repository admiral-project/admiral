# Issue #229 — terminal task replay after failure and restart

**Result: PASS for the targeted Rocky Linux 10 Multi-Node regression.** The issue remains open; this is issue-specific evidence and does not complete a formal matrix cell or establish release readiness.

## Candidate and topology

- Root release-validation record: `ceda601f73d664122d60361ada97a4e6ddc5d81f`.
- Local diagnostic RPMs: Epoch 2, `0.0.1rc6-4.el10`; not published and not the final no-Epoch candidate.
- OS: Rocky Linux 10.2 x86_64.
- Admin: `192.168.122.208`; Worker: `192.168.122.209`.
- Admin component build: `admirald` source pin `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`, containing the terminal-operation and task validation guards.
- The issue's failure injection used a disposable app whose database service runs `/bin/false`.

## Procedure

1. Applied the failing app definition on Admin and requested provision explicitly on the Worker, waiting for a terminal result.
2. Confirmed the database service failed readiness and the provision operation reached `failed` rather than being reported as successful.
3. Deprovisioned the failed instance and confirmed deprovision operation `op_f6d466d5f5a8bfce` succeeded.
4. Restarted `admirald.service` on Admin and `admiral-fleet.service` on Worker; both returned `active`.
5. Queried the durable queue row for the original task after restart and inspected the Worker's Podman inventory.

## Expected and observed

- Expected: the failed provision remains terminal; after successful cleanup and service restarts the queue does not replay it, the attempt count does not increase, and no workload resources are recreated.
- Observed: provision operation `op_f76c4014c8b714f1` is `failed`; task `task_e32aaa44440fec90` is `cancelled`, attempt count `2/5`, has no lease, and records `operation is terminal: failed`. The same row was observed after both services restarted. Worker `podman ps -a` was empty after deprovision and remained empty after restart. Deprovision operation `op_f6d466d5f5a8bfce` is `succeeded`.
- Outcome: **PASS** for this exact failure/cleanup/restart regression. This does not test in-flight task lease recovery or every queue failure mode.

## Evidence

The lab captured RPM inventories, app apply output, provision/deprovision results, the post-restart queue row, service restart states, empty Worker container inventories, and filtered Admin/Worker journals under:

`/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-issue-229/`

The environment-specific raw evidence is retained on the validation host. The operation, task, and instance IDs above identify the records to reproduce. No secrets are included in this report.

## Scope limitation

This is a targeted issue check on a local diagnostic Epoch 2 RPM set. It is not a formal Rocky Multi-Node cell pass, and does not give credit to any of the six release-matrix cells.
