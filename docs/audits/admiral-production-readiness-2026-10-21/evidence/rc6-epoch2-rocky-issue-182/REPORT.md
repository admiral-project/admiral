# Issue #182 — Harbor uploaded-backup restore E2E

**Targeted result: PASS after applying the local WireGuard topology fix.** This is issue-specific evidence on a diagnostic RPM set; it does not pass a formal release matrix cell. Issue #182 remains open pending source integration/rebuild and broader candidate gates.

## Environment

- OS: Rocky Linux 10.2 x86_64.
- Topology: Admin `rc6r4-rocky-admin` (`10.99.0.1`), Worker `rc6r4-rocky-worker` (`10.99.0.2`), independent Harbor Portal (`10.99.0.100`).
- Installed RPMs: local diagnostic Epoch 2, `0.0.1rc6-4.el10` on all three guests.
- Go component refs: `admirald@421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`, `admiral-fleet@fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; Harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- The root Ansible WireGuard playbook changes in this worktree were applied to the guests. They are not yet part of a rebuilt candidate RPM set.

## Procedure and results

1. Provisioned the fixture through the independent customer Portal and requested a database backup.
2. Retrieved the Admiral backup record and downloaded the artifact from the Worker. The 708-byte archive SHA-256 was `6af500e4509b8c0f1872ab4c091783071f47c9d1dcb61527f8d28c45a51bf14f`.
3. Uploaded the same archive through the customer Portal. The owner-only download returned the same 708 bytes and SHA-256.
4. First restore attempt failed with `dial tcp 10.99.0.100:5001: connect: no route to host`. Inspection found no direct Worker↔Portal WireGuard peer and no Worker source allow rule for Portal TCP/5001.
5. Applied the local `ansible/wireguard-peers.yml` changes: exact `/32` Worker↔Portal peers and a Portal firewall rule for TCP/5001 from registered Workers. Verified Worker→Portal HTTPS returned HTTP 200 with TLS verification successful.
6. Retried the signed Harbor uploaded restore. Operation `op_89512c9b92c2fed3` succeeded. After customer resume operation `op_63c1e346b7864985`, Admiral reported `running`, `healthy`, `available`. PostgreSQL returned the restored marker `original`.
7. While paused, submitted two negative customer restore requests with Harbor's external origin set first to the unregistered Worker address (`https://10.99.0.2:5001`) and then to link-local metadata (`https://169.254.169.254:5001`). Both were rejected with `private restore source is not a registered Harbor portal`. Total `restore_backup` records remained 2 (the first failed connectivity attempt and the successful retry); neither negative control queued an operation.
8. Restored the configured Portal origin and resumed the app. Final resume operation `op_dccad57ef12c8c9f` succeeded; final instance state was `running`, `healthy`, `available`.

## Evidence and limits

- `backup-record.json`, `restore-operation.json`, `marker-after-restore.txt`, `worker-to-portal-connectivity.txt`, and `negative-origin-results.txt` are sanitized records from the lab run.
- Secret-bearing environment files and raw customer credentials remain only in the mode-0700 external lab directory `/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-issue-182/` and were not copied here.
- The diagnostic RPMs predate the root Ansible fix. This proves the source playbook fix works in this Rocky topology, not that a rebuilt package contains it. A new six-RPM Epoch build and candidate revalidation are still required.
- The release matrix remains **0/6**.
