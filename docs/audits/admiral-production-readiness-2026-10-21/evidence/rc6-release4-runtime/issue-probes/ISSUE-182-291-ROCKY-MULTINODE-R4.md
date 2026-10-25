# RC6 Release 4 — Rocky Multi-Node #182 / #291 targeted evidence

**Result: targeted PASS for #182 and #291 on the exact RC6 Release 4 candidate. This is not a completed Multi-Node matrix cell.** Issues remain open; no issue was closed by this run.

## Candidate and topology

- Candidate: `0.0.1rc6-4`, x86_64, no explicit RPM Epoch, native EL10 packages.
- Candidate source identity: root package source archive `d50f8f323597140cafa1cefab69744cc56c6831f`; component pins are in [`RC6 Release 4 build evidence`](../../rc6-release4-build/CANDIDATE.md).
- Installed packages on Admin: all six RPMs; Worker: `admiral-common`, `admiral-fleet`; Portal: `admiral-common`, `admiral-harbor`. All installed EVRs were `0.0.1rc6-4.el10` and the role package verification was clean.
- Three separate Rocky Linux 10.2 x86_64 VMs:
  - Admin `rc6r4rocky-admin-mn`: underlay `10.77.0.20`, WireGuard `10.99.0.1`.
  - Worker `rc6r4rocky-worker-mn`: underlay `10.77.0.21`, WireGuard `10.99.0.2`.
  - Independent Portal `rc6r4rocky-portal-mn`: underlay `10.77.0.22`, WireGuard `10.99.0.3`.
- Installer playbooks completed for Worker (`ok=153 changed=50 unreachable=0 failed=0`) and Portal (`ok=196 changed=76 unreachable=0 failed=0`). Admin, Worker, and Portal registered active/healthy in the control plane. Harbor `/health` returned HTTP 200. The release key and installed RPM signatures were verified during deployment.
- Harbor customer test traffic used the Portal's registered WireGuard IP with the lab CA. The HTTP Host header was `portal.rc6.test`; TLS certificate verification was against the IP SAN, not that test alias.

## #291 — Worker to independent Portal network

**PASS after applying the package-delivered post-install peer reconciliation helper.**

1. Before reconciliation, Worker and Portal each had only the Admin peer. The Worker route resolved to `wg-admiral`, but there was no spoke-to-spoke peer. Restore operation `op_9753ca0311a474fb` failed with `connect: no route to host`; this failure is retained as a candidate observation.
2. The installed playbook `/usr/share/admiral/ansible/wireguard-peers.yml` matched the repository candidate source SHA-256 `942ccc2d481d8e33b8990cc6d4c262496d5871583feda437efe505c8023ed0c3`.
3. The three-role inventory was reconciled with that packaged playbook. The first invocation used an unsuitable Admin self-SSH identity and made no changes (`unreachable=1`); it was corrected to use the already pinned Admin validation identity. The successful run reported:
   - Admin: `ok=15 changed=2 unreachable=0 failed=0`.
   - Worker: `ok=16 changed=4 unreachable=0 failed=0`.
   - Portal: `ok=23 changed=6 unreachable=0 failed=0`.
4. Worker and Portal then each had the exact peer for the other spoke. Portal firewalld allowed Harbor TCP/5001 from Admin `10.99.0.1` and registered Worker `10.99.0.2/32`.
5. Worker reached Portal HTTPS with the lab CA and received HTTP 200 `{"status":"healthy"}`.
6. A second packaged-playbook run was idempotent: Admin `changed=0`, Worker `changed=0`, Portal `changed=0`; all three had `unreachable=0 failed=0`.

This validates the packaged manual post-install helper on this topology. It does not show that peer exchange happens automatically during the three separate installer invocations.

## #182 — customer uploaded-backup restore

**PASS for the targeted customer upload/restore path on this exact candidate.**

1. Applied the DB-backed `e2e-portal-free` fixture with manual database backups and restore enabled. A first customer-flow attempt showed the fixture's original Free tier had no backup policy; after adding the explicit policy, the old test instance was deprovisioned and a new synthetic customer was used.
2. Through the independent Harbor Portal, customer registration was pending and pending login was rejected; Admin approval succeeded; the customer logged in, saw the catalog, and deployed instance `inst_f29b4c04e6e742a2` on the Worker.
3. Added SQL marker `rc6-r4-issue182-original` to the Worker PostgreSQL database before backup. Customer backup operation `op_d8213233d98b50e8` succeeded. Backup `bk_d024d4cb78980dbe` was 736 bytes, SHA-256 `53703f2d021f3e250475dea6c7908ad5e8f69ead6653ccb3a53981b27c9d9fa0`; PostgreSQL's archive listing contained the marker table.
4. The customer uploaded the backup through Harbor. Upload ID `upbk_70be4ecc8881` was downloaded through the owner-only route; its byte count and SHA-256 exactly matched the source artifact.
5. Restore was initially rejected because the Harbor metadata origin remained the default/unregistered value. After setting the Portal's configured origin to `https://10.99.0.3:5001`, restore failed once with `no route to host` (the #291 condition above). After package-delivered peer/firewall reconciliation, uploaded restore operation `op_15ebcd43cfaf45c0` succeeded.
6. Harbor resume operation `op_e95ab1d1ae50f1a7` succeeded. After the short reconciliation interval, Admiral reported `running/healthy/available` and direct SQL verification returned the original marker `rc6-r4-issue182-original`.
7. While paused, negative restore requests using unregistered Worker origin `https://10.99.0.2:5001` and metadata origin `https://169.254.169.254:5001` were both rejected with `private restore source is not a registered Harbor portal`. The `restore_backup` operation count remained 2 before and after both negative controls.
8. The configured Harbor origin was restored to `https://10.99.0.3:5001`. A second customer resume succeeded; after reconciliation Admiral again reported `running/healthy/available` and the SQL marker remained. Customer instance deprovision operation `op_b58a0459744585fb` succeeded; no instance containers, volumes, or matching Quadlet files remained on Worker. Test backup records were deleted after their metadata and checksum were captured.

## Evidence and limitations

- Sanitized command results and operation IDs: [`ISSUE-182-291-R4-observations.txt`](ISSUE-182-291-R4-observations.txt).
- Reproduction helpers: [`issue-182-harbor-e2e.py`](../../../scripts/rc6/issue-182-harbor-e2e.py), [`issue-182-portal-restore.py`](../../../scripts/rc6/issue-182-portal-restore.py), [`issue-182-worker-marker.sh`](../../../scripts/rc6/issue-182-worker-marker.sh), [`issue-182-worker-marker-check.sh`](../../../scripts/rc6/issue-182-worker-marker-check.sh), [`issue-291-wireguard-peers.ini.example`](../../../scripts/rc6/issue-291-wireguard-peers.ini.example), and [`e2e-portal-free.yaml`](../../../fixtures/e2e-portal-free.yaml).
- Installer logs and raw Ansible output were retained mode `0600` in `/var/lib/admiral/validation/rc6-r4/issue-182/` on the Admin VM. Synthetic credentials and backup artifacts were kept outside Git and removed from temporary paths after the run. The test customer record and uploaded Harbor record remain synthetic lab data on the disposable Portal.
- The exact candidate passed these issue-specific flows only. This run did not execute all Multi-Node matrix checks (concurrency, failover, isolation, resource pressure, host reboot, performance, and the remaining linked-issue checklist); it earns **no complete cell credit**. Under issue #283's current three-OS scope, the formal matrix remains **0/6**. The supplied AGENTS.md text names four OSes/8 cells, which conflicts with the current #283 scope and `TEST_MATRIX.md`; that scope needs one canonical update before the matrix count can be reported unambiguously.
