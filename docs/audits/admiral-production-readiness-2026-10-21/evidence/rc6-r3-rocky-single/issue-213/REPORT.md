# Issue #213 — dev-to-secure TLS leaf reissue

**Result:** PASS for the targeted Rocky Linux 10.2 secure Single-Node reconvergence, including an explicit self-signed negative control. This is not a release-matrix cell.

## Candidate and environment

- Root source: `cd98098a02c94fb3976e98c6214409bfe07e130e`.
- Local diagnostic `admiral-common` package: Epoch 101, `0.0.1rc6-3.el10`; the five other installed Admiral packages were `0.0.1rc6-3.el10`.
- Guest: `rc6e99rocky-devnode`, Rocky Linux 10.2 x86_64, disposable KVM VM.

## Procedure and results

1. Captured the existing public TLS leaf metadata and preserved a copy of the public certificate only.
2. Replaced the leaf with a one-day self-signed certificate using the existing leaf key and SAN `DNS:localhost,IP:127.0.0.1`.
3. Verified the negative control failed `openssl verify -CAfile /etc/admiral/tls/ca.pem -verify_ip 127.0.0.1`.
4. Ran `admiral-install --single-node --yes --validation-seed --public-ip 192.168.122.158 --node-id rc6e99rocky-devnode`.
5. Verified the resulting leaf issuer matched the internal CA subject; SAN covered `localhost`, `127.0.0.1`, the guest address, and the single-node WireGuard address. OpenSSL verification passed for both loopback and the guest address.
6. Verified Harbor and Flagship TLS clients using the internal CA (`harborctl ping` succeeded; Flagship health returned HTTP 200), `admiralctl status` reported online/healthy, the Fleet node was active/healthy, and there were no failed systemd units.
7. Confirmed secure reconciliation removed both Harbor dev-mode drop-ins and set the worker/catalog-sync environment back to `ENV=production`.

## Evidence

- Full install and test log: [`epoch101-rocky-negative-reconverge.log`](epoch101-rocky-negative-reconverge.log), SHA-256 `8e38c371d52a9bee78f8921010270175407f1343673f1712acd8174bb74aa788`.
- The issue-specific negative control and dev-mode background service evidence are also attached to GitHub issues #213 and #298.

## Limits

This verifies the Single-Node loopback and guest-address path only. It does not validate the Multi-Node WireGuard SAN/client path or count as a complete Rocky release cell. The local package includes an RPM Epoch for diagnostics and is not the final no-Epoch release candidate.
