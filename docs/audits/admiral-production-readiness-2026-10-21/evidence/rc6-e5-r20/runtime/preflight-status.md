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
