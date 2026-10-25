# RC6 Release 1 Rocky independent Portal — issue #289

**Result: PASS for the issue-specific direct-origin runtime check. This is not a Multi-Node matrix-cell pass.**

## Candidate and environment

- Candidate: `0.0.1rc6-1.el10`, RPM Epoch 0 (no explicit Epoch); exact Harbor package identity recorded in `issue-289-portal-candidate.txt`.
- Root source: `267da7ebd739a0703c276ec8d4770ffa31a45f25`; root CI run [40194076634](https://github.com/admiral-project/admiral/actions/runs/40194076634) succeeded.
- OS/topology: Rocky Linux 10.2 x86_64, independent Portal guest `rc6r1rocky-portal-r2`; request path was directly to `https://10.99.0.3:5001` over WireGuard, with TLS verification using `/etc/admiral/tls/ca.pem`.
- All six EL10 package NEVRAs and SHA-256 values are in `candidate-rpm-manifest-el10.tsv`; root and component source SHAs are in `candidate-identity.txt`.
- Reproducer: [`issue-289-direct-portal.py`](../../../../scripts/rc6/issue-289-direct-portal.py); script SHA is recorded in `issue-289-direct-portal-script.sha256`.

## Procedure and observed result

The probe read the bootstrap admin credential from the Portal's protected `/etc/admiral/harbor.env` without printing or storing credential values. It created a synthetic pending customer, authenticated as Harbor admin, and submitted approval and catalog-sync POSTs directly to the independent Portal origin.

| Mutation | Status | Location | Content-Length | Body bytes | Redirect follow-up |
|---|---:|---|---:|---:|---:|
| Customer approval | 303 | `/admin/review-user` | 0 | 0 | HTTP 200 |
| Catalog sync | 303 | `/admin/` | 0 | 0 | HTTP 200 |

The approved test customer could log in successfully. The successful run is captured in `issue-289-direct-portal-run.log`. Two synthetic customer accounts were created and approved during the final and preserved harness runs; no workload was deployed by this probe.

Earlier probe-helper failures and their confirmed causes are preserved in `HARNESS_ATTEMPTS.md`; they were harness defects, not product failures.

This confirms the response framing and normal redirect-following behavior for #289 on the exact RC6 Release 1 Harbor RPM, directly over WireGuard. It does not grant a cell pass. The formal matrix remains **0/6** until all applicable checks pass for each OS/mode cell on the unchanged candidate.
