# Issue #213 — RC6 Epoch 5 Release 7 validation

Result: **PASS** for the supported dev-node → secure single-node certificate recovery on the exact R7 EL10 RPM set. This targeted issue check does not add a release-matrix cell.

## Candidate and environment

- Candidate: `rc6-e5-r7`, version `0.0.1rc6`, Epoch `5`, Release `7`, x86_64.
- Guest: Rocky Linux 10.2 x86_64, `rc6r7-rocky-issue213`, disposable updated seed.
- All six installed RPM NEVRAs and SHA-256 values are recorded in [`../../el10/RPM-MANIFEST.tsv`](../../el10/RPM-MANIFEST.tsv).
- The first install used the candidate's native `.el10` RPMs with `admiral-install --dev-node --yes --validation-seed`; Ansible completed `ok=208 changed=86 unreachable=0 failed=0`, Fleet registered and sent current heartbeat/metrics, and the installer exited successfully.

## Procedure and observations

1. Confirmed the dev-node systemd environment had `ADMIRAL_DEV_MODE=true` and all six packages were `5:0.0.1rc6-7.el10`.
2. Replaced only the disposable guest's Admirald leaf with a self-signed leaf limited to `localhost` and `127.0.0.1`. OpenSSL rejected it against Admiral's CA (`error 18: self-signed certificate`), establishing the negative control.
3. Ran the supported secure reconvergence: `admiral-install --single-node --yes --validation-seed --public-ip 192.168.122.166 --node-id rc6r7-rocky-issue213`.
4. Ansible completed `ok=209 changed=46 unreachable=0 failed=0`. It replaced the untrusted leaf with a CA-signed certificate and removed the dev-only Harbor worker/catalog-sync environment overrides.
5. Verified the leaf against the configured CA for both `127.0.0.1` and `192.168.122.166`; both OpenSSL checks returned `OK`. The SAN contains both IP addresses.
6. Verified the background Harbor units use `ENV=production`; `harborctl ping` succeeded; Flagship health returned HTTP 200 with CA verification; `admiralctl status` reported a healthy control plane; the Worker was active/healthy; and `systemctl --failed` was empty.

No product changes were made during this validation. The temporary guest was used only for this issue-specific transition and is cleaned up after preserving the local evidence.

## Evidence files

- `dev-install.log` — exact-candidate dev install and recap.
- `runtime/dev-to-single-261026-r7.log` — complete secure reconvergence, negative-control and client checks; SHA-256 `d8547fc90a24f7fbef5cd8d181e89e060381609103e1d5a18189699d8e600a15`.
- `runtime/guest-artifacts.tar.gz` — guest-side certificate metadata, negative OpenSSL result, authenticated client outputs, and node inventory; SHA-256 `689b6a953c6a6ede764da5fff340a60e8c93d7f4a00c61ab5f1ef2bb80aacbb6`.
- `SHA256SUMS` — integrity manifest for the published issue-specific evidence.
