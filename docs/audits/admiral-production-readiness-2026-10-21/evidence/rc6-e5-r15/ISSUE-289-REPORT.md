# RC6 Epoch 5 Release 15 — issue #289

Date: 2026-10-27 UTC

Result: **PASS for the issue-specific repeated redirect/customer-flow acceptance on Rocky Linux 10 Multi-Node.** This does not pass a full release-matrix cell.

## Candidate and topology

- Candidate: RC6 Epoch 5 Release 15, six RPMs built natively for EL10 and Fedora Rawhide. The tested Rocky guests had the exact `5:0.0.1rc6-15.el10` packages from the candidate manifest.
- Harbor source: `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`; its R15 RPM `%check` passed 352 tests, and the pinned component CI is green.
- Three Rocky Linux 10 x86_64 guests: Admin (`192.168.122.169`, WireGuard `10.99.0.1`), dedicated Portal (`192.168.122.166`, WireGuard `10.99.0.2`), and Worker (`192.168.122.159`, WireGuard `10.99.0.3`).
- Candidate source identities and exact RPM SHA-256 values are in [`CANDIDATE.md`](CANDIDATE.md), [`source-pins.txt`](source-pins.txt), and the [EL10 RPM manifest](el10/RPM-MANIFEST.tsv).

## Executed acceptance

The existing independent-Portal customer flow was run twice through the public Admin Caddy route and twice directly to Harbor over WireGuard. Each run registered a new synthetic customer, verified pending login was rejected, approved the customer, synchronized and published the catalog, and deployed the free app through Harbor. The client followed the admin mutation redirects and completed the expected pages.

| Path | Customer | Instance / hostname | Provision op | Deprovision op | Runtime result |
|---|---:|---|---|---|---|
| Admin Caddy → Portal | 3 | `inst_4da5576e65eec30b` / `e2e-portal-free399871.apps.rc6.test` | `op_cb3a51f0535cca3f` | `op_349c2d9db4b43211` | `running/healthy/available`; route healthy; strict Caddy request HTTP 200, TLS verify 0 |
| Admin Caddy → Portal | 4 | `inst_77876895a8b415fc` / `e2e-portal-free057768.apps.rc6.test` | `op_6464f811221fc95d` | `op_5d7369b1dc03b219` | `running/healthy/available`; route healthy; strict Caddy request HTTP 200, TLS verify 0 |
| Portal → WireGuard origin | 5 | `inst_3d1fb776904dff65` / `e2e-portal-free753748.apps.rc6.test` | `op_c87bd01db4a223ac` | `op_2c14c7e94956a931` | `running/healthy/available`; route healthy |
| Portal → WireGuard origin | 6 | `inst_6e6628be51490b82` / `e2e-portal-free542650.apps.rc6.test` | `op_fcd1a7ac556c8011` | `op_6be515dbf0d0b0a9` | `running/healthy/available`; route healthy; strict Caddy request HTTP 200, TLS verify 0 |

The Portal guest also made a strict-CA request to both ingress paths: Caddy `https://portal.rc6.test/auth/register` and direct `https://10.99.0.2:5001/auth/register` each returned HTTP 200 with TLS verification 0. These results are recorded in [`issue-289-route-probes-retry2.log`](issue-289-route-probes-retry2.log). The per-flow output and cleanup operations are in the adjacent `issue-289-*-flow-*.log` files.

After cleanup, all four instances were `deprovisioned/unavailable`, Admiral had no remaining app routes, and the Worker's rootless Podman container, pod, and volume inventories were empty. See [`issue-289-final-state.log`](issue-289-final-state.log) and [`issue-289-worker-final-inventory.log`](issue-289-worker-final-inventory.log).

## Test fixture notes

The first Caddy setup attempt checked the Admin API before its asynchronous route configuration had converged; it was not counted. The corrected harness waited for the route and certificate, added the lab CA only to the disposable Admin guest's temporary system trust, and then the route and all customer flows passed. The CA anchor, temporary certificate, service drop-in, and Portal `/etc/hosts` mapping were removed afterwards. `admirald` and Caddy were active, with no reference to the temporary certificate. Setup and cleanup logs are preserved adjacent to this report.

This is issue-specific evidence for the exact R15 Harbor package on the Rocky Multi-Node topology. It does not credit the Rocky Multi-Node release cell or any other matrix cell.

## Evidence integrity

[`ISSUE-289-EVIDENCE-SHA256SUMS`](ISSUE-289-EVIDENCE-SHA256SUMS) records hashes for the flow outputs, strict-route checks, and final cleanup inventories.
