# RC6 E5 R20 — Issue #255 live migration result

**Result: PASS for the issue-specific Rocky Linux 10.2 x86_64 multi-node migration gate.** This run is not one of the six full release-matrix cells.

## Candidate and setup

- Release candidate: RC6 E5 R20, signed EL10 RPMs `5:0.0.1rc6-20.el10`.
- Root candidate: `ba7c4396743e84baae0b4de9f89f91ff5503a33b`; `admirald`: `4472cd8defc2de9c649ddbc1108a0aa64c0f1859`.
- Existing Rocky lab: admin `10.77.0.10`, source worker `10.77.0.11`, target worker `10.77.0.13`.
- No VMs were created or started. The existing R18 source fixture and its nonterminal operations were left untouched.
- A first disposable fixture asking for 512 MiB was rejected before instance creation because the source node had only 263,726,694 bytes of RAM commit headroom (`800,597,606` limit minus `536,870,912` committed). The rejected app was deactivated; see the preceding `issue-255-r20-...002529z...` directory.
- The successful disposable fixture used a 128 MiB tier, which fit the observed node capacity. It used the existing SeaweedFS S3 endpoint and PostgreSQL 16; volume backups were disabled, so there was no local artifact staging.

## End-to-end result

- Instance and logical ID: `inst_64fdb1a0175e15cf`.
- Migration operation: `op_03dbe012bf1d82c4`, status `succeeded`, final step `completed`.
- The sequence completed as `backup_database` → source pause → target provision → `restore_backup` → target `resume_app` → cutover → source deprovision. `resume_app` succeeded before cutover, and source deprovision followed cutover.
- Fresh backup `bk_cff8fdd07096c6ea` succeeded with backend `s3`, storage key, SHA-256 checksum, and 695-byte payload. The target restored the PostgreSQL marker `2552071`.
- The same logical ID was healthy and available on target `rc6e5r18-r255-worker2`; no container for the test instance remained running on source after cutover.
- The operation timeline contains 58 samples at 0.75-second intervals (maximum gap 0.754795 seconds). The migration and every observed child operation reached success; no operation regressed from `running` or a terminal state to `queued`.
- The disposable instance was deprovisioned successfully after verification, and its app definition was deactivated.

## Resource telemetry

The monitor sampled host and all three guest RAM and root-disk availability every 15 seconds during the migration. Across three samples, minimum host availability was 2,650,812 KiB RAM and 58,476,232,704 bytes disk; minimum guest RAM was 293,032 KiB (admin), 355,828 KiB (source), and 470,996 KiB (target). No caution threshold was crossed. The post-run host snapshot showed about 2.5 GiB available RAM and 55 GiB free disk.

## Scope

This is live end-to-end evidence for #255 on R20. It does not complete the six-cell release matrix: all six R19 cells remain invalid after the R20 product change, and the R20 matrix remains **0/6** until the full Single-Node and Multi-Node cells pass on Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide. This run alone does not declare Gold.

The detailed inputs and raw outputs are in this directory. `SHA256SUMS` covers the captured evidence files.
