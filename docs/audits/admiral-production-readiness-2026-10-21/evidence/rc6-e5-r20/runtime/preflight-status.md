# RC6 E5 R20 Rocky runtime preflight status

Captured 2026-10-28 around 00:09 UTC. No R20 #255 migration was started in this snapshot.

## Signed update applied

The signed EL10 R20 repository was used with `dnf upgrade` on the existing lab nodes:

- Admin `10.77.0.10`: `admiral-common`, `admirald`, `admiralctl`, `admiral-flagship`, and `admiral-harbor` at `5:0.0.1rc6-20.el10`; `admirald` active.
- Source worker `10.77.0.11`: `admiral-common` and `admiral-fleet` at `5:0.0.1rc6-20.el10`; Fleet active.
- Target worker `10.77.0.13`: `admiral-common` and `admiral-fleet` at `5:0.0.1rc6-20.el10`; Fleet active.

Readable DNF transaction captures are `admin-r20-update.log`, `source-worker-r20-update.log`, and `target-worker-r20-update.log` in this directory; raw logs and hashes are preserved as recorded in `../raw-log-hashes.txt`. Repository signature verification and metadata verification passed before updates.

## Existing lab state requiring recovery

The control plane reports these pre-existing operations for disposable R18 fixture instance `inst_9a7a819dcf3c4689`, still running, healthy, and available on source worker `rc6e5r18-ipv6-worker`:

- `op_9917ffdf8f798f67`: migration remains `running`, step `rollback_source_restart`; last update `2026-10-27T19:57:25Z`.
- `op_d4baee700fdfe91d`: its source `start_app` child remains `queued`.
- `op_dd3dbf19b2cccd7d`: node-level `test_backup_storage` operation remains `queued` with an empty `instance_id`.

The admin and both existing workers were updated to R20, but these statuses had not changed by the last observation. No direct database changes were made. The old migration remains nonterminal, so the fixture was not deprovisioned and no second migration was launched against this lab state.

The source worker had 279 MiB available RAM at the last observation, below the 350 MiB migration precondition used by the existing issue-255 guard. The target had 376 MiB available. Host resources remained healthy: about 2.7 GiB available RAM and 55 GiB free disk. Do not count this preflight as an R20 runtime cell or #255 pass.

The R19 failed migration result and its recovery evidence remain at `../rc6-e5-r19/issue-255-r19-issue255-rocky-mn-20261027t225640z/RESULT.md`; that run is valuable evidence for the R20 fix and was not overwritten.


## Follow-up: live R20 #255 validation, 2026-10-28 00:25–00:28 UTC

The 00:09 snapshot above is historical. After the worker RAM precondition recovered, the first attempt requested a 512 MiB fixture but Admiral rejected it before instance creation: the source had 263,726,694 bytes of RAM commit headroom, less than the requested tier. The temporary app was deactivated and removed. See `issue-255-r20-issue255-rocky-mn-20261028t002529z-2689222/RESULT.md`.

A second disposable fixture used a 128 MiB tier. On the existing Rocky 10.2 admin/source/target, the fresh S3 database backup, target restore, `resume_app`, health-gated cutover, and source deprovision all succeeded. The original logical ID remained healthy and available on the target; the database marker survived. The operation timeline had 58 samples and no queued-state regression. Details and checksums are in `issue-255-r20-issue255-rocky-mn-20261028t002633z-2690062/RESULT.md`.

RAM and disk telemetry ran throughout the migration. Minimum observed host availability was 2,650,812 KiB RAM and 58,476,232,704 bytes disk; minimum guest RAM was 293,032 KiB on admin, 355,828 KiB on source, and 470,996 KiB on target. No resource threshold was crossed. No VM was created or started. The old R18 fixture remained running, healthy, and available on the source; its stale operation records were not modified.

GitHub issue [#255 was closed](https://github.com/admiral-project/admiral/issues/255#issuecomment-6457374781) after this validation. This issue-specific pass does not count as a complete R20 Multi-Node release-matrix cell. The matrix remains 0/6 pending all six full runtime cells.
