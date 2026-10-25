# Issue #181 — RC6 Release 1 customer backup-policy E2E

**Result: PASS for the issue-specific Rocky Linux 10 Multi-Node runtime acceptance check. This is not a Multi-Node cell pass and does not complete the wider audit.**

## Candidate and topology

- Candidate: `0.0.1rc6-1`, no explicit RPM Epoch; root commit `267da7ebd739a0703c276ec8d4770ffa31a45f25`.
- Root CI: [40194076634](https://github.com/admiral-project/admiral/actions/runs/40194076634), success.
- Platform: Rocky Linux 10.2 x86_64.
- Topology: three separate guests, Admin `10.77.0.2`, Worker `10.77.0.3`, independent Portal `10.77.0.4`; WireGuard addresses `.1`, `.2`, `.3` in `10.99.0.0/24`.
- Harbor component SHA: `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`. Exact component pins and signed EL10 RPM NEVRAs/SHA-256 values are in `candidate-identity.txt` and `candidate-rpm-manifest-el10.tsv`. Installed package identities on all three roles are captured in `admin-rpm-identity.txt`, `worker-rpm-identity.txt`, and `portal-rpm-identity.txt`.
- Instance: `inst_3a30af3669ba8757`, Admiral customer `hcus_7b171dc8d8c340ff`; tier snapshot has `manual_backups=true`, `backup_database=false`, `backup_volumes=true`, and `restore_allowed=false`.

## Procedure and observed result

The test created and approved a synthetic Harbor customer, published the disposable `e2e-backup-policy` catalog app, and deployed it through the independent Portal to the Worker. The exact installed candidate converged to `running/healthy/available` before the policy checks.

- Harbor hid the disallowed database-backup action and restore form.
- A forged database-backup form was denied. The customer-scoped Admiral API returned HTTP 403 with `Manual database backups are disabled for this tier`.
- After pausing the instance, a forged restore form was denied. The customer-scoped API returned HTTP 403 with `Restore is disabled for this tier`.
- A second approved customer received HTTP 404 for the owner's instance.
- At the post-policy snapshot, Admiral had only the successful provision and test-pause operations for this instance; no backup or restore operation existed. Harbor's `uploaded_backup` and `restore_request` counts for the test customer/instance were both zero (`operations-after-policy.json`, `harbor-backup-restore-inventory-after.json`).
- Test cleanup deprovisioned the instance successfully. The instance reached `deprovisioned`, and Worker containers, pods, and volumes were empty. Cleanup output and inventories are retained.

Raw run output is `issue-181-run.log`. The reproducible policy and portal helpers are in `scripts/rc6/backup-policy-customer-probe.py` and `scripts/rc6/independent-portal-customer-flow.py`; their hashes are recorded in `reproducer-scripts.sha256`. `run-issue-181.py` generates throwaway credentials in memory and reads service credentials only from the guest's protected systemd environment file; it does not write credentials to evidence.

## Harness attempts and limits

An initial launcher attempt failed while sourcing the systemd environment file and made no customer/API changes. A subsequent probe initially supplied Harbor's integer user ID instead of the Admiral public customer ID; the API correctly returned `403 access denied`, so that attempt was not counted. It was cleaned up. The final passing run queried the public `hcus_...` ID read-only from Harbor's database and completed the checks above. Details are in `HARNESS_ATTEMPTS.md`.

This evidence is limited to #181 on the exact Rocky Release 1 candidate. Issues #190 packaged-worker runtime acceptance and the remaining Single-Node/Multi-Node release checks remain separate gates. The formal six-cell matrix remains **0/6 complete**.
