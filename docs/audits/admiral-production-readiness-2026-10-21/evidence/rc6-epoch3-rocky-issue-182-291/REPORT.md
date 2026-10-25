# RC6 Epoch 3 / Release 5 — Rocky networking and uploaded-restore fixes

**Issue-specific targeted result: PASS for #182 and #291 on a three-guest Rocky Linux 10.2 x86_64 lab. Formal release matrix remains 0/6.** The issues remain open for the final no-Epoch RC6 candidate and matrix gates.

## Candidate identity

- Local diagnostic package set: Epoch `3`, `0.0.1rc6-5.el10`, x86_64/noarch; not published.
- Built on Rocky Linux 10.2 x86_64. All six RPMs built, with SRPMs emitted. Build tests: `admirald` Go tests, `admiral-fleet` Go tests, `admiralctl` Go tests, `admiral-flagship` 266 tests, `admiral-harbor` 352 tests; root scripts suite 158 tests passed before the RPM build.
- Root source fix commit `17d49dd6695b2cecc994d1373d0279a3b0031cda`; package pin/release commit `285c728835f91f3bf2c7133c4109ba67070b1414`.
- Root GitHub CI: Main Regression Tests run `40182817759`, conclusion success for `285c728`.
- Component pins matched fetched `origin/main`: admirald `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`; fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`; CLI `fa2a65e866310bd82bea78859804b6c3aea7989a`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`.
- The RPM manifest and SHA-256 values are in `RPM-MANIFEST.tsv` and `SHA256SUMS`.

## Three-node topology and package deployment

- Admin: Rocky 10.2, `192.168.122.208`, WireGuard `10.99.0.1`.
- Worker: Rocky 10.2, `192.168.122.209`, WireGuard `10.99.0.2`.
- Dedicated independent Harbor Portal: Rocky 10.2, `192.168.122.249`, WireGuard `10.99.0.100`.
- Installed the matching Epoch 3 / Release 5 package roles on each guest. Exact inventory is in `NEVRA-INSTALLED.txt`.

## #291 — Worker-to-Portal networking

Ran the `wireguard-peers.yml` playbook extracted from the built `admiral-common` RPM, not from the uncommitted source tree.

- Full topology run: `changed=0` on Admin, Worker, and Portal.
- Removed Worker from the Ansible inventory: the Portal's direct Worker peer was removed and the exact TCP/5001 firewalld rule for `10.99.0.2/32` was removed. Portal had one remaining WireGuard peer (Admin hub). The successful Ansible `Remove stale Worker-to-Portal Harbor rules` task is retained in the raw run log. A standalone post-removal shell query was incorrectly quoted, so this report relies on the successful Ansible removal result for that moment rather than claiming a separate query.
- Restored full inventory: direct peer and exact firewall rule were re-added; Ansible verified the rule. Portal had two peers (Admin hub and Worker). A third full-inventory run was idempotent (`changed=0` on all three nodes).
- Worker HTTPS to Portal health returned HTTP 200 with certificate verification enabled. The Portal firewall's TCP/5001 rules were exactly Admin hub `10.99.0.1` and registered Worker `10.99.0.2/32`; no allow rule existed for `10.99.0.3/32`.
- Negative network probe: temporarily assigned the otherwise unused `10.99.0.3/32` address to the Worker WireGuard interface and bound the HTTPS probe to it. Connection to the Portal timed out (curl exit 28). Removed the temporary address, then the authorized Worker probe again returned healthy.

## #182 — Harbor customer uploaded-backup restore

- Previously uploaded owner backup: 708 bytes, SHA-256 `6af500e4509b8c0f1872ab4c091783071f47c9d1dcb61527f8d28c45a51bf14f`.
- Through Harbor customer UI on the Epoch 3/Release 5 guests, paused the app and requested restore. Operation `op_1aa1ce3f807d45ee` succeeded on the Worker.
- While paused, tested signed restore requests with the external Harbor origin set to unregistered Worker `https://10.99.0.2:5001` and metadata `https://169.254.169.254:5001`. Both were rejected by Admirald with `private restore source is not a registered Harbor portal`. The count of `restore_backup` operations stayed at 3 before/after the controls; neither request queued a task.
- Resume operation `op_c4316c7f741b7fe3` succeeded. Final instance state was `running/healthy/available`; PostgreSQL returned the restored marker `original`.

## Scope

This run proves these issue-specific regressions on the local Epoch 3 / Release 5 Rocky multi-node candidate. It does not complete a Single-Node or Multi-Node release matrix cell, does not validate CentOS Stream or Fedora, and does not replace a fresh-install run on the final no-Epoch candidate. Keep both issues open; use `fix-confirmed` to record issue-specific runtime evidence only.

Secret-bearing credentials and raw backup data remain outside the repository in the restricted lab directory. No secrets are included in these artifacts.
