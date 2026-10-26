# Issue #240 — Rocky Linux 10 Single-Node on RC6 R8

**Result: PASS.** The test used candidate `rc6-e5-r8` and the six Epoch 5 /
Release 8 EL10 RPMs in `../../el10/RPM-MANIFEST.tsv`.

The worker was first measured at a 1,430,156,083-byte RAM commit limit. After
reserving one `small` instance (536,870,912 bytes), the node had
893,285,171 bytes left: exactly one more 512 MiB instance fit. Two provisions
with distinct customers and idempotency keys were launched concurrently.

- `rc6-240-b` succeeded as `op_787dde52a38444c2` / `inst_cdead32137c10870`.
- `rc6-240-a` received one structured
  `no_node_available_for_requested_tier` rejection with
  `insufficient_ram_commit_capacity`; it did not print the old three-retry
  error. The failed operation was `op_9d93deb8c57b3c6d`, task
  `task_72551a7e1dd8abb5`.
- The database and durable queue each contain exactly one failed operation /
  task for the rejection (`attempt_count=0`, `max_attempts=0`). There is no
  `provision_request`, customer app, instance, or runtime resource for the
  rejected customer.
- The successful and reserved instances were deprovisioned. Final Podman,
  Quadlet, filesystem and capacity checks were empty; committed RAM returned
  to zero.

The operation inventory, queue rows, CLI stdout/stderr, capacity snapshots,
cleanup transcript, and SHA-256 manifest are in this directory. This validates
the candidate Single-Node acceptance for #240; no product change was made.
