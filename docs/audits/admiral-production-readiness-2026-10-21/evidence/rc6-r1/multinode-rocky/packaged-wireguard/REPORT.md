# RC6 Release 1 Rocky Multi-Node evidence — issues #182 and #291

## Candidate and environment

- Result scope: issue-specific acceptance checks only; **does not pass a formal matrix cell**.
- Candidate: Admiral `0.0.1rc6-1.el10`, no explicit RPM Epoch, x86_64.
- Root source: `267da7ebd739a0703c276ec8d4770ffa31a45f25`.
- Components: Admirald `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`, Fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`, CLI `fa2a65e866310bd82bea78859804b6c3aea7989a`, Flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`, Harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Root CI for the candidate source is green: [run 40194076634](https://github.com/admiral-project/admiral/actions/runs/40194076634).
- Target: Rocky Linux 10.2 x86_64, three separate guests:
  - Admin `10.77.0.2`, WireGuard `10.99.0.1`
  - Worker `10.77.0.3`, WireGuard `10.99.0.2`
  - independent Portal `10.77.0.4`, WireGuard `10.99.0.3`
- Installed package EVRs and role-specific service activity are recorded in `*-runtime-identity.txt`. All package versions are `0:0.0.1rc6-1.el10`; Admin runs Admirald/Flagship, Worker runs Fleet, Portal runs Harbor. Each guest has the RC6 signing key imported and the local validation DNF repo has `gpgcheck=1` and `repo_gpgcheck=1`; see `candidate-key-trust.txt`.
- Forwarding remained disabled on all three guests (`net.ipv4.ip_forward=0`, `net.ipv6.conf.all.forwarding=0`); see `forwarding-state.txt`.
- The six EL10 package NEVRAs and SHA-256 values are in `candidate-rpm-manifest-el10.tsv` and `candidate-rpm-sha256-el10.txt`; the copied artifacts passed `sha256sum -c`.

## #291 — Worker-to-Portal WireGuard access

**Status: PASS for the issue-specific acceptance checks on this candidate.**

Procedure used the `wireguard-peers.yml` delivered by the installed `admiral-common` RPM. The installed playbook and the root source playbook have the same SHA-256 (`942ccc2d481d8e33b8990cc6d4c262496d5871583feda437efe505c8023ed0c3`). The initial package playbook run completed with zero failed/unreachable tasks. A full rerun was idempotent (`changed=0` on Admin, Worker and Portal).

The Worker-removal reconciliation was exercised in two inventories so both sides were actually updated: Admin+Portal with no Worker removed the Portal's direct Worker peer and exact TCP/5001 rule; Admin+Worker with no Portal removed the direct Portal peer from the Worker. The captured states contain only the Admin peer/rule. Rejoining the full inventory restored both Worker↔Portal peers and the Worker `/32` firewall rule. A further full rerun again reported `changed=0` on all three nodes.

After rejoin, the Worker reached the independent Portal's `/ready` endpoint over WireGuard with HTTP 200 and TLS verification result 0. A temporary WireGuard peer at unregistered address `10.99.0.66/32` established a handshake but had no Portal TCP/5001 allow rule; its HTTPS request timed out (`curl_exit=28`, HTTP status 000). The temporary interface, peer and private key were removed. This retained hub-and-spoke forwarding policy; the Worker/Portal paths use exact `/32` peers.

Evidence: `playbook-run.log`, `idempotent-before-removal.log`, `remove-worker-portal-reconcile.log`, `remove-worker-spoke-reconcile.log`, `worker-removed-*.txt`, `rejoin-worker-reconcile.log`, `idempotent-after-rejoin.log`, `worker-rejoined-*.txt`, `worker-to-portal-after-rejoin.txt`, and `unauthorized-wg-probe.log`.

## #182 — authenticated uploaded-backup restore

**Status: PASS for the issue-specific acceptance checks on this candidate.**

Through the independently installed Portal and strict-TLS Caddy route, a customer signed up, was denied login while pending, was approved, saw the catalog, and deployed the PostgreSQL test application on the Worker. The backup record is `bk_951fe18bf39b4d3e`; its 743-byte artifact SHA-256 is `d7d081ef33f0f5fe04df9f7df8e8329a1969c707a1564659c337fb11d807c193`. Harbor's owner-only download of uploaded backup `upbk_65ee28b65a18` matched the same byte count and SHA-256.

The original database marker was `rc6r1-restore-inst_24654c580b2a348c`. After package-delivered peer/firewall reconciliation, the customer restore operation `op_a6dccefbe8154ecf` succeeded. The Worker database returned the same marker after restore. The customer then resumed the instance; Admirald reported `running/healthy/available`, and the public workload route returned HTTP 200 with TLS verification result 0.

Negative controls used the same customer flow while the instance was paused. Restore origins `https://10.99.0.2:5001` (an unregistered Worker address) and `https://169.254.169.254:5001` were both rejected with `private restore source is not a registered Harbor portal`. Restore operation count remained 3 before and after both controls. Harbor's configured origin was restored to `https://10.99.0.3:5001`. The test instance was paused after evidence capture.

Evidence: `independent-portal-customer-flow.log`, `customer-backup-request.log`, `customer-upload-owner-download.log`, `backup-records.json`, `sql-marker-created-before-backup.log`, `restore-operation-poll2.log`, `instance-after-restore2.json`, `customer-resume-final.log`, `instance-restored-healthy.json`, `restored-sql-marker.log`, `restored-workload-http-result.txt`, `restored-workload-http-body.txt`, `negative-worker-origin.log`, `negative-link-local-origin.log`, `restore-count-before-negative.txt`, `restore-count-after-negative.txt`, and `harbor-origin-after-negative.txt`.

## Preserved failed attempts and classification

- Restore `op_cc2f22c35c9cd560` failed before network reconciliation with `connect: no route to host`. This is the original #291 defect; it was reproduced on this candidate, fixed operationally by running the packaged playbook, and the full restore then passed.
- Restore `op_44c0851afddafefe` failed on a test instance left without its database container after the prior failed restore. The normal customer resume operation recreated the Quadlet workload; the subsequent customer pause/restore completed. This failure was retained and was not counted as a product pass or a release-cell result.
- One negative-origin request was first attempted while the instance was running; Harbor correctly refused because restore requires a paused instance. The test was repeated with the required paused precondition and both negative controls passed.
- An initial post-recovery helper invocation returned no operation and its error was written to stderr rather than the captured stdout file. The operation list confirmed that no work was queued; the subsequent diagnostic-helper invocation queued and completed the restore.
- Initial recursive SCP of the package playbook hit an unreadable Python `__pycache__`; the retry streamed the installed package tree with `sudo tar`, excluding bytecode caches. No test task ran during the failed copy.
- The first evidence query used the wrong firewalld zone name; it did not alter the playbook result. Subsequent checks queried the actual `admiral` zone and captured both removal and rejoin state.
- The host did not have `wg` installed for generating a negative-probe key. The key was generated in `/run` on the Worker and removed at test completion; no private key was retained in evidence.
