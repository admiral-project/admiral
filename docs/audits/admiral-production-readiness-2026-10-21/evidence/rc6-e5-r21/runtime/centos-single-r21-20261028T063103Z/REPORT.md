# R21 CentOS Stream 10 x86_64 Single-Node

**Result: PASS for the exact RC6 E5 R21 Single-Node cell.** This does not declare R21 Gold; five release-matrix cells and the required issue work remain open.

## Candidate and installation

- Candidate: RC6 E5 R21, root packaging commit `fa4838bc4438e9757ffcbdf1a8a1173c3c666cf8`, `admirald` source `04ec1dd7d5de87906e7560194e94fa4afe087354`.
- Existing guest: `rc6e5r18-ipv6-admin`, CentOS Stream 10 x86_64. No VM was created.
- The six native EL10 RPM files matched the signed R21 candidate manifest before installation. Final installed NEVRA remained `5:0.0.1rc6-21.el10` for all six packages.
- `admiral-install --single-node --validation-seed` completed successfully. Ansible recap: `ok=197 changed=11 unreachable=0 failed=0 skipped=187 rescued=0 ignored=0`.
- SELinux remained Enforcing; firewalld and the required Admiral, Caddy, and PostgreSQL services were active; there were no failed Admiral-related units.
- The local Worker was active, healthy, and available. Rootless Podman was enabled.

## Runtime checks

- Applied and provisioned the real `e2e-whoami` app. The workload ran in rootless Podman, returned HTTP 200, and wrote a PostgreSQL marker. Repeating the same idempotency key returned the same operation and instance. Deprovision completed with no residual containers, pods, volumes, user units, or instance files.
- Pause, resume, stop, start, and restart all succeeded. After resume, start, and restart, the workload returned to `running/healthy/available` and HTTP 200; pause and stop completed in their expected non-running states.
- PostgreSQL backup succeeded with checksum `f3644411c28aa0f4a09f3fbd6df7c8c9f206c55c14cce38343bb29ce3a8b854a`. Restore while running was rejected with HTTP 409. After pause, checksum-verified restore recovered the original marker and HTTP 200. The temporary backup artifact was deleted, and the instance was deprovisioned cleanly.
- A real VM reboot changed `boot_id` from `05ddb2a1-c229-4c4f-9810-1ed7a0fae1a3` to `e6ceb535-2296-4f72-b2f2-f06ed7bba88b`. Admiral, Fleet, PostgreSQL, and all three workload containers recovered; the persisted SQL marker matched; HTTP returned 200; deprovision and cleanup succeeded.
- Final checks confirmed all six exact R21 EL10 NEVRAs, Enforcing SELinux, active firewall and required services, healthy/available Worker, rootless Podman, and no remaining workload containers, pods, volumes, or backup artifacts.

## Resource monitoring and observation

- Host floors were 2 GiB available RAM and 30 GiB available disk; guest floors were 256 MiB available RAM and 1.5 GiB available disk. No floor was crossed.
- Across the lifecycle, backup/restore, and reboot runs, the minimum host availability was 4,538,056 KiB RAM and 40,171,756 KiB disk; the minimum guest availability was 659,884 KiB RAM and 10,514,644 KiB disk. These stayed above the 2 GiB/30 GiB host floors and 256 MiB/1.5 GiB guest floors. During reboot the guest was unreachable as expected; host monitoring continued, and guest monitoring resumed after boot.
- The final direct guest `df` reported 49% root-filesystem use and about 11 GiB free. Admiral's node record still reported `storage_state=warning` with an 85% message while reporting the same current disk totals/usage as 49% and the node as healthy/available. This mismatch did not fail a checklist item, but should be reviewed separately before Gold.

## Evidence

- [`install.log`](install.log)
- [`post-install-check.txt`](post-install-check.txt)
- [`workload-lifecycle.log`](workload-lifecycle.log)
- [`instance-lifecycle.log`](instance-lifecycle.log)
- [`backup-restore.log`](backup-restore.log)
- [`host-reboot.log`](host-reboot.log)
- [`final-postcheck.txt`](final-postcheck.txt)
- [`instance-lifecycle-resource-monitor.jsonl`](instance-lifecycle-resource-monitor.jsonl)
- [`backup-restore-resource-monitor.jsonl`](backup-restore-resource-monitor.jsonl)
- [`host-reboot-resource-monitor.jsonl`](host-reboot-resource-monitor.jsonl)

`PRODUCT_CHANGED=NO`; the installed R21 candidate was not invalidated by these runtime, harness, or evidence activities.
