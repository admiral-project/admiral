# Issue #299 — RC6 Epoch 5 / Release 2 independent Portal flow

Date: 2026-10-26 UTC. Candidate: local native CentOS Stream 10 RPMs, Epoch 5, 0.0.1rc6-2.el10, on three KVM guests with separate Admin, Worker, and Harbor Portal roles. Root commit: e710237fd908feabf17b12fb61d08429deb21e52. Exact package identities/hashes are in [RPM-MANIFEST.tsv](../../x86_64/RPM-MANIFEST.tsv).

## Result

The corrected independent-Portal customer flow passed on the exact candidate. The generated email was lowercase: rc6-e5-caddy-20261026t002058z-57b7e2@example.test. The flow passed registration, pending-login rejection, Admin approval, catalog access, and free app deployment. The instance was inst_cb9cc691f7fa68a6 on the Worker. Its Portal-routed app returned HTTP 200 with TLS verification enabled (tls_verify=0). The customer/subscription/app fixtures were removed. No PayPal/provider endpoint was called.

This confirms the audit-harness email normalization correction and the scoped customer flow. It does not by itself pass a complete Multi-Node cell. Issue #299 remains open for release-matrix acceptance.

## Evidence

- portal-caddy-flow.log — registration, approval, catalog and free deployment transcript.
- issue-300-app-route.log — route check on the same instance; HTTP 200, TLS verification result 0.
- portal-flow-cleanup.log — customer and subscription cleanup.
- The surrounding directory contains the exact-candidate Admin/Worker/Portal install and post-upgrade logs.
- SHA-256 values are in SHA256SUMS.
