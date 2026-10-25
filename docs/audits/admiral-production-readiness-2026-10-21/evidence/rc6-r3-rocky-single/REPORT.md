# RC6 Release 3 Rocky Linux 10 Single-Node functional lane

**Status:** functional lane PASS; formal matrix cell is not yet complete.

## Candidate and environment

- Root source: `55f67122613f13f13fa254f30a78d444e69b35d3` (`origin/main` at execution).
- RPM set: `0.0.1rc6-3.el10`, Epoch 0, all six Admiral packages.
- Component SHAs: `admirald 0fd76b6c902cfae179cfe6fb3e685c935a350cf7`; `admiral-fleet fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; `admiralctl fa2a65e866310bd82bea78859804b6c3aea7989a`; `admiral-flagship b7325bbc71fc474a521496e593b2967e4d555ac1`; `admiral-harbor dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Guest: fresh `rc6r3rocky-single`, Rocky Linux 10.2 x86_64, 2 vCPU / 2 GiB; overlay created from `/var/lib/libvirt/images/admiral-validation/seeds/Rocky-10.2-seed-20261025-rc6-updated.x86_64.qcow2` (seed SHA-256 `7ea75d0ec238ee8d813b42cfa7b42e73c9f3eb1aaff9b30634b73eba04a968b6`).
- Candidate repo: local EL10 x86_64 repo `rc6-r3-current`; DNF installed exactly the six candidate RPMs and one OS dependency (`acl`). No EPEL/COPR Python helper changed during the Admiral RPM transaction.
- Root GitHub CI for source commit: [40216091290 — success](https://github.com/admiral-project/admiral/actions/runs/40216091290).

## Procedure and result

1. Created a new overlay from the recorded updated seed and booted it on the isolated libvirt network.
2. Installed the six exact local RPM NEVRAs and ran `admiral-install --single-node --validation-seed`.
3. Ran `scripts/rc6/run-single-lane.sh rocky 192.168.122.155 rc6r3rocky-single` with `RC6_PACKAGE_RELEASE=3`, `RC6_EXPECTED_EPOCH=0`, and the Release 3 evidence root.
4. The secure installer completed with `ok=231 changed=96 unreachable=0 failed=0` (417 seconds).
5. The six functional stages all passed:

| Stage | Result | Observed evidence |
|---|---|---|
| Workload create, idempotency replay, deprovision | PASS | Same operation and instance IDs on replay; HTTP 200 and SQL marker; deprovision succeeded; no matching containers, pods, volumes, units or files remained. |
| Resize and data continuity | PASS | `small → medium → small`; HTTP 200 and the same SQL marker after each transition. |
| Database backup/restore | PASS | Restore while running rejected with HTTP 409; paused restore succeeded; original SQL marker and HTTP 200 recovered; deleted backup artifact absent. |
| Instance and Admirald lifecycle | PASS | Pause/resume, stop/start, restart, Admirald stop/start; API and workload returned to HTTP 200 and available. |
| Host reboot and persistence | PASS | Boot ID changed; workload converged by poll 3 with three containers and ready PostgreSQL; HTTP 200 and persisted SQL marker verified; deprovision cleanup succeeded. |
| Final services, RPMs and resource cleanup | PASS | No failed systemd units; six exact `0.0.1rc6-3.el10` NEVRAs; no rootless containers, pods or volumes. |

The lane ended `PASS`, zero failed stages, at `2026-10-25T17:56:41Z`. Protected raw logs are retained on the lab host with mode 0600:

- `/var/lib/libvirt/images/admiral-validation/evidence/rc6-r3-rocky-single/functional/rocky-single/lane.log` — SHA-256 `ba0b98b8026aa684ca434cb47a10d50775e8d6d04512401c107e0c05e03c0d85`.
- `evidence/rc6-r3-rocky-single-install.log` — SHA-256 `aff8532d0928fc2e69aa05d39e2ba9619ed07c257fda86011cbcfde9e18bf2b9`.
- Six installed RPM SHA-256 values are listed in `RPM-SHA256.txt`; the complete package manifest is the local repo's `RPM-MANIFEST.tsv`.

## Additional exact-candidate issue regressions

All three checks used the same installed six-RPM Release 3 set and guest. Raw captures were retained with mode 0600.

| Issue | Procedure and result | Evidence SHA-256 |
|---|---|---|
| #259 | Restarted `user@991.service` four times with a live DB-backed workload. All 4/4 recovered; each SQL marker persisted, no `healthy/available` sample occurred while services were absent/starting, and deprovision cleanup succeeded. | Run logs: `issue-259/run-1.log` `6a3240b37bbe8dea846086ac83c460ca29f3e52495f3097bd0669ff524c7a886`; `run-2.log` `1a189b7ff9801627130d41b11b5483fa1f7952ac7bfc1eabf001d77192972c6b`; `run-3.log` `edad75cbbbeafa71e13df6defee8c8d548dd5570fcfa45525833ef8cf7749709`; `run-4.log` `07be854ad8926d1216d9e43b2b77a30ad6cf49162b09e913f0bae2222864e758`. |
| #260 | Stopped the declared PostgreSQL unit and collected 61 one-second samples over 60.020 s. API moved from healthy/available to failed/unhealthy/unavailable after 3.020 s; there were zero healthy/available samples at or after 5 s. PostgreSQL recovered, the SQL marker persisted, and cleanup succeeded. | `issue-260/outage-recovery.log` `3c2ec4dadeb1c9b430db86b3f8238c986436137d686aa66a1c71399eab64d1c3`. |
| #271 | Tested 302 health-check redirects to both `127.0.0.1` and the guest's reachable NAT address. Each variant observed at least two periodic health reports; the redirect listener recorded zero requests and all instances cleaned up. | `issue-271/redirect-health.log` `ad86c68b48b1a8a74383689cd99c7c2d5066a7676b4df4266ad142bdc8840fff`; guest evidence archive `abbf96b6ae547b947ae8d96b3ff11383da747ab1838c9400513a82318a89a5a4`. |
| #295 | With a Harbor-generated `hcus_…` identity, provisioned through Harbor's packaged client, verified customer-scoped read, and ran the installed Harbor worker before/after a local prepaid-date expiry. No deprovision occurred before expiry; after expiry exactly one `harbor-token` deprovision operation succeeded. A worker rerun left the count at one. The customer had no PayPal subscription ID; no payment endpoint was called. Fixture rows, workload and rootless resources were cleaned up. | `issue-295/setup.log` `83c4b7f07c2bc7c84cd8f37553400baf77d28949fb2ed710a3b6ff6c8be2bdd6`; `pre-expiry.log` `b539f4417781994273841d7ce4605d7a068ac4764d7423aa6e33c61360a545da`; `pre-expiry-worker.log` `c1ea62c9b50de0298ff15eef9023c6b776383c4b0bd9bed0880b1c9c9a540001`; `expiry.log` `5cdda583d540022c3159c97f51d67474cfed996e9451037e7a3806646836a691`; `expired-worker.log` `5151ee3545b734825340598d463264f0cada5941ef5cb8370a157a6eb605ec56`; `post-expiry-rerun.log` `72e87eac8bbbdf722b698069a038edaa961e972cde52fcbdfaf03650481579fe`; `final-cleanup.log` `728cbebc6da6a9b0c7b24bb41389c50e4e09ce3798af164768fbe22371e97f02`. |

The helpers now accept and log an explicit candidate label instead of emitting the stale Epoch 3 / Release 5 label. `bash -n` passed for the modified runners, and the #259–#271 procedures above ran with candidate label `rc6-r3-epoch0-0.0.1rc6-3.el10`.

The first #295 harness attempts failed before exercising Harbor: the systemd environment file was incorrectly sourced as shell, then a transient service could not read a root-owned script, then Python lacked the installed package's `PYTHONPATH`. Each issue was corrected by running the helper as the `admiral` account in a transient systemd unit with the same environment files and working directory as Harbor. The final setup and workflow completed successfully; these were harness setup errors, not product failures. PayPal was not invoked.

## Scope limit

This is the first Release 3 Rocky Single-Node functional lane, not a formal matrix-cell PASS. The release-wide issue-specific acceptance gate in [master issue #283](https://github.com/admiral-project/admiral/issues/283) still requires fresh candidate checks for applicable linked issues. Security/isolation negatives, fault injection, performance, and other audit coverage are also tracked separately. No other OS/mode cell receives credit from this run.
