# RC6 Epoch 2 Rocky Multi-Node issue checks: #278 and #284

Date: 2026-10-25 (UTC)

## Candidate and environment

- Test IDs: `RC6-MN-NODE-REMOVE-HISTORY-01` (#278), `RC6-MN-WORKER-REENROLL-01` (#284)
- Root source commit: `7f73e81ec68151423c6a09e116c5b49c926efbff`
- Component pins: admirald `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`; fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Runtime: three Rocky Linux 10 x86_64 guests on the isolated libvirt test network: Admin `10.77.0.10`, Worker `10.77.0.11`, independent Portal `10.77.0.13`.
- Installed test packages: Epoch 2, `0.0.1rc6-4.el10`; Admin had all six Admiral RPMs, Worker had common+fleet, Portal had common+harbor. The packages were locally built and signed for the isolated lab. This is a diagnostic candidate, not the final no-Epoch release candidate.
- Matrix credit: none. These are targeted issue checks and do not complete the Rocky Multi-Node cell.

## #278 — preserve history on node removal

Expected: refuse removal of a worker with an active instance; after successful deprovision, allow removal of the idle worker while retaining the instance and operation history in PostgreSQL.

Observed: provisioning instance `inst_7c484993b9163884` succeeded and its HTTP route returned 200. Removing the worker while the instance was active was rejected, and the HTTP route remained 200. After deprovision operation `op_6d306be382933bf0` succeeded, idle node removal succeeded. The terminal `customer_apps` row remained queryable with `technical_status=deprovisioned`, `commercial_status=cancelled`, and `node_id=null`. Both successful operation rows (`op_bd8e86ae80cabda6` provision and `op_6d306be382933bf0` deprovision) remained unchanged and queryable. The removed node no longer appeared in node inventory; worker rootless container/pod/volume inventories were empty.

Result: **PASS for this targeted #278 runtime check**. Node re-enrollment afterwards also succeeded; see #284 below.

## #284 — spoke health query and re-enrollment

Expected: the worker installation helper must work from an already unprivileged SSH session, use the supported privilege boundary for the health query, establish the authenticated node registration, and reject the temporary bootstrap credential after enrollment.

Observed: the actual Rocky worker reinstallation/re-enrollment helper exited 0. Its final checks reported node ID `rc6r4-rocky-worker`, role `worker`, `active/healthy`; the temporary bootstrap SSH key was rejected while pinned validator access remained available. Installer Ansible recap: `ok=146 changed=13 unreachable=0 failed=0 skipped=228`. WireGuard handshake and Podman 5.8.2 checks succeeded.

Result: **PASS for the targeted #284 installer/re-enrollment regression**. This is not a full-cell pass.

## Reproduction and artifacts

The #278 command is the `scripts/rc6/multinode-node-removal-history.sh` helper with `RC6_PACKAGE_RELEASE=4`, `DIST_TAG=el10`, `EPOCH=2`, and the three-node Rocky lab endpoints. The helper now accepts a validated `RC6_PACKAGE_RELEASE` environment variable so diagnostic builds can be tested without changing the final-release default (`1`).

Raw mode-0600 logs and JSON snapshots are retained on the lab host at:

`/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-multinode-node-removal/`

The per-file SHA-256 manifest verifies with `sha256sum -c SHA256SUMS`; manifest SHA-256 is `36ab59e94773a03fba2af5d555f4d4dec0cc4284b2f5a89ce235a16ed263feda`. The worker re-enrollment log is retained at `/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-worker-reenroll.log` with mode 0600. The local candidate RPM SHA-256 manifest is in `/var/lib/libvirt/images/admiral-validation/repo/rc6-epoch2/SHA256SUMS`.

The removal run observed transient Fleet readiness retries while PostgreSQL was starting; the service subsequently became healthy and the scripted scenario completed. This report does not characterize startup as retry-free.
