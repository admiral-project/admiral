# RC6 Epoch 2 Rocky independent Harbor flow — issue #289

Date: 2026-10-25 UTC  
Result: **PASS for the targeted Harbor redirect/customer-flow regression; no matrix-cell credit.**

## Candidate and topology

- Candidate: local diagnostic `Epoch 2, 0.0.1rc6-4.el10`, x86_64/noarch, all six RPMs. This is not the final no-Epoch candidate.
- Root package source: `7f73e81ec68151423c6a09e116c5b49c926efbff`.
- Components: admirald `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`; Fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`; Flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; Harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- Three Rocky Linux 10.2 x86_64 guests: Admin `10.77.0.10` / WireGuard `10.99.0.1`; Worker `10.77.0.11` / WireGuard `10.99.0.2`; dedicated Portal `10.77.0.13` / WireGuard `10.99.0.100`, registered as `portal-001`.
- RPM EVR, architectures, and per-package SHA-256: [`rc6-epoch2-rocky-el10-rpm-manifest.tsv`](rc6-epoch2-rocky-el10-rpm-manifest.tsv). Local repository checksum-list SHA-256: `2937ec0f7991aac59d150620b34c27c564fcdf00c7aed584747209f7f9fde161`.

## Test setup

A test-only CA signed a local certificate with SANs `portal.rc6.test` and `*.apps.rc6.test`. The independent Portal guest resolved `portal.rc6.test` to the Admin Caddy address. Before using the hostname, a harness attempt connected to the Admin by IP and failed TLS with `TLSV1_ALERT_INTERNAL_ERROR` because the client sent IP SNI. This was a harness setup error. The failed attempt is retained in `/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-issue-289-customer-flow.log` (empty stdout; failure was emitted on stderr by the first runner).

The test certificate was installed only on the isolated Admin guest and its CA was added to that guest's trust store for Admiral's health probes. Caddy also needed execute-only ACLs on `/etc/admiral` and `/etc/admiral/tls` to read the configured Admiral CA for upstream TLS. This was test-lab setup, not a source or RPM modification. No public DNS or public ACME endpoint was used.

Strict TLS checks from the Portal guest passed before customer tests:

- `https://portal.rc6.test/auth/register` through Admin Caddy: HTTP 200, certificate verification `0`.
- Both test workload routes through Admin Caddy: HTTP 200, certificate verification `0`.

## Executed flows

The existing `scripts/rc6/independent-portal-customer-flow.py` was run with the Portal guest's Harbor bootstrap credentials read in-process from its root-owned environment file; credentials were not printed or saved. The requested hostname was used for both the URL (TLS SNI) and Host header.

| Test | Path | Signup/pending login | Admin approval and catalog sync | Deployment | Result |
|---|---|---|---|---|---|
| `RC6-MN-HARBOR-FLOW-CADDY-01` | Portal guest → Admin Caddy → dedicated Harbor | Signup pending; pending login rejected | Approval and catalog sync completed; app published | `inst_222d75bf4e08b415`, provision op `op_2fe86e1b7da41edc` | PASS |
| `RC6-MN-HARBOR-FLOW-WG-01` | Portal guest → Harbor over its WireGuard origin | Signup pending; pending login rejected | Approval and catalog sync completed; app published | `inst_ddacc7ca8409adfa`, provision op `op_c68fd1afee71dd98` | PASS |

For both instances, `admiralctl instances show` reported `running/healthy/available` on worker `rc6r4-rocky-worker`; direct PostgreSQL operation rows showed `provision_app|succeeded`. Caddy route health was `healthy`, and strict TLS requests to both `*.apps.rc6.test` hostnames returned HTTP 200. Rootless Podman on the Worker showed each app and infra container running.

Both instances were then deprovisioned successfully (`op_b65af7a594fcbd42` and `op_da8c0c50db51fc18`). Final instance state was `deprovisioned/stopped/unavailable`; each provision/deprovision operation row remained queryable and succeeded. Worker inventory checks found zero instance containers, pods, volumes, or systemd units for either test instance. Their public route rows were removed.

Raw mode-0600 flow outputs on the lab host:

- Caddy path: `/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-issue-289-customer-flow-rerun.log`, SHA-256 `b3affff61d620327e086f7912c8128c791af8b7a8a1490123287e045f0f1d8e9`.
- WireGuard direct path: `/var/lib/libvirt/images/admiral-validation/validation/rc6-r4/epoch2/rocky-issue-289-customer-flow-direct.log`, SHA-256 `ff76b689b82dde6277344ea4c68825a69849c2a04650ccf63527bbf9ec0060f9`.
- The first IP-SNI harness error is retained separately as described above.

The Harbor package `%check` included 352 passing tests on the same source commit; GitHub CI for Harbor `dd4818b6` is green (run `40171847383`). The test helper performed the whole browser-like flow through the real portal; it automatically followed both admin mutation redirects. This targeted result does not establish all independent Portal acceptance items or complete the Rocky Multi-Node cell.

## Build metadata discrepancy

The local build helper wrote `release=1` into its pre-build `source-pins.txt`, although its actual RPM manifest and installed guest package queries prove all six packages were Release 4. Do not use that field as package identity. Exact package identity is established by the recorded RPM NEVRAs/SHA-256 values and the guest RPM queries. The helper is being corrected to write Release from the post-build RPM metadata and to reject mixed Releases.
