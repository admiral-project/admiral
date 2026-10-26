# Issue #181 — RC6 Epoch 5 / Release 2 CentOS Multi-Node policy probe

**Result: PASS for this issue-specific scenario on the exact candidate. This is not a complete Multi-Node cell pass.** Issue #181 remains open; no label or issue state was changed.

## Candidate and topology

- Candidate: Admiral `Epoch 5: 0.0.1rc6-2.el10`, root package-source commit `e710237fd908feabf17b12fb61d08429deb21e52`.
- Exact six RPM NEVRAs and SHA-256 values: [`RPM-MANIFEST.tsv`](../../x86_64/RPM-MANIFEST.tsv).
- Runtime: CentOS Stream 10 x86_64; three distinct KVM guests, Admin `rc6e5cs-admin` (`192.168.122.113`, WireGuard `.1`), Worker `rc6e5cs-worker` (`192.168.122.114`, WireGuard `.2`), and dedicated Harbor Portal `rc6e5cs-portal` (`192.168.122.115`, WireGuard `.3`).
- All role-specific packages remained at Epoch 5 / Release 2; expected Admin, Worker, and Portal services were active and all three guests had no failed system units after test cleanup. See [`role-postchecks.txt`](role-postchecks.txt).
- The Worker had been deliberately removed from the control-plane inventory during the preceding #278 probe. Before the policy run, the supported packaged worker installer re-registered it and verified `active/healthy`, role `worker`, heartbeat/metrics, WireGuard handshake, and temporary bootstrap-key rejection. See [`worker-reregister-summary.md`](worker-reregister-summary.md) and the before/after node inventories.

## Procedure and observed results

Ran the reusable [`issue-181-runner.py`](../../../../scripts/rc6/issue-181-runner.py) on the independent Portal as the `admiral` account with the Portal's protected systemd environment files. The runner generated disposable credentials in memory, registered a customer, confirmed pending login was rejected, approved the customer as Harbor admin, published the `e2e-backup-policy` test app, and deployed it to the Worker. The deployed instance was `inst_4aeb7f6c4dd979fb`.

The exact-candidate probe then observed:

- Backup and restore controls were hidden for the disallowed policy.
- Forged Harbor database-backup action was denied; the customer API returned HTTP 403, `Manual database backups are disabled for this tier`.
- After pausing the instance, forged Harbor restore was denied; the customer API returned HTTP 403, `Restore is disabled for this tier`.
- A second approved customer received HTTP 404 for the owner's instance.
- Before cleanup, Admirald had only the successful `provision_app` and test `pause_app` operations for this instance. No backup record, Harbor uploaded-backup row, or restore-request row existed: [`operations-before-cleanup.json`](operations-before-cleanup.json), [`backups-before-cleanup.json`](backups-before-cleanup.json), [`records-before-cleanup.json`](records-before-cleanup.json).
- Deprovision completed successfully. Harbor's packaged reconciliation worker completed successfully; both generated Harbor customers/subscriptions and the test CustomerApp row were removed. The Worker had no matching containers, pods, volumes, user units, or instance files: [`deprovision.json`](deprovision.json), [`portal-worker-sync.log`](portal-worker-sync.log), [`cleanup.log`](cleanup.log), [`runtime-cleanup.txt`](runtime-cleanup.txt).

The raw runner output is [`probe.log`](probe.log). `SHA256SUMS` covers the committed evidence files. There were no PayPal calls.

## Reproduction

1. Install the exact RPMs listed in the manifest on three CentOS Stream guests and configure Admin + Worker + separate Portal using the packaged installers.
2. Apply `fixtures/e2e-backup-policy.yaml` on Admin with `admiralctl apps apply`.
3. Copy `issue-181-runner.py`, `independent-portal-customer-flow.py`, and `backup-policy-customer-probe.py` together onto Portal.
4. Run as `admiral` from `/usr/lib/admiral/harbor`, with `/etc/admiral/harbor.env` and `/etc/admiral/harbor.smtp.env` loaded, `PYTHONPATH=/usr/lib/admiral/harbor`, and `ADMIRAL_AUDIT_CANDIDATE=5:0.0.1rc6-2.el10`.
5. Before deleting the test customer, capture operation, backup, `UploadedBackup`, and `RestoreRequest` inventories for the generated instance/email. Deprovision; run `admiral-harbor-worker.service` once; then run `cleanup-independent-portal-customer.py` for each generated email.

## Disposition and limits

This is a candidate-specific issue #181 PASS on CentOS Stream 10 Multi-Node. It does not prove the policy on Rocky/Fedora, test #182 upload/restore or #190 prepaid subscription behavior, or complete the CentOS Multi-Node checklist. The formal RC6 matrix remains **0/6** and the release-wide issue gate remains incomplete.
