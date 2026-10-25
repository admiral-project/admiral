# RC6 Release 4 Rocky dev-mode and secure reconvergence probes

Date: 2026-10-25 UTC
Environment: fresh Rocky Linux 10.2 x86_64 guest `rc6r4-rocky-devsingle`, cloned from the updated 2026-10-25 Rocky seed.
Candidate: all six native EL10 RPMs, Epoch 0, `0.0.1rc6-4.el10`.
Source archive commit: `d50f8f323597140cafa1cefab69744cc56c6831f`; the package source includes root fixes `2230a20`, `05bafe2`, and `cd98098`.
Guest address: `192.168.122.72`. No production system or external service was used.

## Results

| Issue | Status | Executed procedure and observation |
|---|---|---|
| #296 | PASS, targeted | Installed the exact six candidate RPMs and ran `admiral-install --dev-node --yes --validation-seed`. Fleet registration and the heartbeat/metrics readiness poll completed; the poll passed after two transient retries. The complete installer exited 0. This exercises the localhost Fleet authentication path in dev mode. |
| #297 | PASS, targeted | The same complete dev installer exited 0 with the dev-only Fail2ban service checks skipped. After secure reconvergence, `fail2ban.service` was active. |
| #298 | PASS, targeted | In dev mode, checked `ENV=development` for both Harbor background units and started each one-shot. Both reported `Result=success`, `ExecMainStatus=0`. After secure reconvergence, both reported `ENV=production` and their dev-mode drop-in files were absent. |
| #213 | PASS, targeted | Replaced the dev leaf with an untrusted self-signed leaf; OpenSSL rejected it (`error 18`). Re-ran the secure Single-Node installer on the same guest. It exited 0, reissued the leaf from the local Admiral CA with loopback and guest-IP SANs, and `openssl verify` succeeded for both addresses. Harbor's authenticated client succeeded, Flagship health returned HTTP 200, Fleet was active/healthy, and there were no failed units. |

## Candidate identity and evidence

All six installed RPMs were confirmed on the guest as `0:0.0.1rc6-4.el10`; the exact six NEVRAs and package SHA-256 values are in [`rocky-el10-nevra.tsv`](../../rc6-release4-build/rocky-el10-nevra.tsv) and [`rocky-el10-sha256.txt`](../../rc6-release4-build/rocky-el10-sha256.txt).

- Dev install transcript, covering #296 and #297: `issue-296-297-298-rocky-release4-dev-install.log`, SHA-256 `41c6c11aad240049148d09c715d2373a34ef23e2a4d0be723b07a493b738c0bc`.
- Harbor background one-shots, #298: `issue-298-rocky-release4-background-services.log`, SHA-256 `0390b208e752a6ccb7fe6c2f6f3c4fdff479cb2992a7eb91bdbec6a42480a995`.
- Dev-to-secure reconvergence, #213 and secure cleanup for #298: [`dev-to-single-r4devsingle.log`](../../rc6-r4-rocky-single/issue-213/dev-to-single-r4devsingle.log), SHA-256 `88ddce1af98d7bc2733e3f3c95cbdad6de15e8a70112926051d5044021228607`.

These are issue-specific Release 4 results on Rocky only. They do not validate Fedora or CentOS, do not cover Multi-Node, and do not make a release-matrix cell pass.
