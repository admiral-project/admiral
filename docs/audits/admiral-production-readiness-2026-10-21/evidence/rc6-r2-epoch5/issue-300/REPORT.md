# Issue #300 — repeat deprovision after terminal success

- **Finding:** `ADM-300` — duplicate terminal deprovision actions enqueue duplicate operations.
- **Severity:** MEDIUM (a repeated request creates redundant task/audit records; both tested tasks completed and cleanup remained safe).
- **Component / scope:** Admirald customer action API; CentOS Stream 10 x86_64, independent Portal Multi-Node lab.
- **Fix candidate:** exact local `Epoch 5: 0.0.1rc6-2.el10` candidate, built from `admirald` commit `aec9914c5909af7f66407b6c3dd0822576cc66dc`.
- **Runtime environment:** CentOS Stream 10 x86_64, three independent guests: Admin `rc6e5cs-admin`, Worker `rc6e5cs-worker`, and Harbor Portal `rc6e5cs-portal`.
- **Instance:** synthetic Harbor flow `inst_cb9cc691f7fa68a6` on `rc6e5cs-worker`.

## Reproduction and observed result

1. Provision a free test workload through the independent Harbor portal; provision operation `op_c692df2e536c830f` succeeded and the instance became healthy/running on the Worker.
2. Verify the workload route from the Portal guest using the configured CA; HTTPS returned `200` with certificate verification enabled (`tls_verify=0`).
3. Deprovision with `admiralctl instances deprovision inst_cb9cc691f7fa68a6 --force --wait --wait-timeout 5m --output json`. It completed successfully as operation `op_bc3f1bc97b3a95b9` / task `task_52c5c74850302ff9`.
4. Repeat the same command after the first operation was terminal. The request returned HTTP 409 `Instance is already deprovisioned`; the operations list contains only the original deprovision for this instance and no second task.
5. The Worker had no remaining resources for the test instance (`target_instances=[]`); three unrelated containers remained. Harbor worker reconciliation completed with zero errors and the test customer/subscription/app fixtures were removed.

Raw evidence is in `../multinode-centos/`: `issue-300-provision-convergence.log`, `issue-300-app-route.log`, `issue-300-deprovision-first.json`, `issue-300-deprovision-repeat.log`, `issue-300-worker-residuals.txt`, `portal-worker-sync-after-deprovision.log`, and `portal-flow-cleanup.log`. Candidate NEVRAs and RPM SHA-256 values are in `../el10/x86_64/RPM-MANIFEST.tsv`; installed package/service snapshots are `admin-post-upgrade.log`, `worker-post-upgrade.log`, and `portal-post-upgrade.log`.

## Cause and minimal correction

Confirmed in the handler: `HandleCustomerAppAction` blocked concurrent running operations but did not reject `technical_status=deprovisioned`; therefore a later request reached operation creation. Added a terminal-state guard for repeated deprovision and a handler regression that asserts HTTP 409 and zero newly created operations.

- Source commit: `admirald` `aec9914c5909af7f66407b6c3dd0822576cc66dc`, signed-off and pushed to `main`.
- Local verification: `go test ./...` passed; output is `go-test-all.log`.
- Component GitHub CI: green for the source commit in run `40246882821`.
- RPM and installed-runtime regression: PASS for this exact Release 2 package set and this CentOS Stream 10 three-guest scenario. This is targeted issue evidence only; it does not pass a complete Multi-Node matrix cell.

Regression acceptance met for this recorded scenario: first deprovision succeeded, repeat returned HTTP 409 without creating another operation/task, and the target runtime resources were absent afterward. No PayPal/provider call is part of this scenario.

No customer, credentials, or production data were used. The test Harbor customer/subscription/app rows were cleaned after operation completion.
