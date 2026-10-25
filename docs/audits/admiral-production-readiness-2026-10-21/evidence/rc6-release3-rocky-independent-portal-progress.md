# RC6 Release 3 Rocky Linux independent Portal progress

Date: 2026-10-25 UTC  
Test candidate: root package commit `f16456f12d875223a5cf6ced77ad0f201f5153e9`  
Packages: all six Admiral RPMs `0.0.1rc6-3.el10`; exact NEVRAs and SHA-256 values are in [`rc6-release3-el10-nevra.tsv`](rc6-release3-el10-nevra.tsv) and [`rc6-release3-el10-sha256.txt`](rc6-release3-el10-sha256.txt).  
Source pins: `admirald` `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d`; Fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; `admiralctl` `fa2a65e866310bd82bea78859804b6c3aea7989a`; Flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; Harbor `034924d23016a1fda48716c29528076378cf934e`.

## Lab topology

Three fresh Rocky Linux 10.2 x86_64 guests, each installed from the updated Rocky seed with the same Release 3 RPM set:

| Role | Guest | Lab address | Result |
|---|---|---|---|
| Admin | `rc6r3rocky-admin` | `192.168.122.150`, WireGuard `10.99.0.1` | Install PASS; PostgreSQL, Admirald, Caddy and Flagship active |
| Worker | `rc6r3rocky-worker` | `192.168.122.151`, WireGuard `10.99.0.2` | Install PASS; Fleet active and registered |
| Portal | `rc6r3rocky-portal` | `192.168.122.152`, WireGuard `10.99.0.3` | Install PASS; Harbor active and separately registered |

Each installer returned zero with `unreachable=0` and `failed=0`. Logs are `rc6-release3-rocky-admin-install.log`, `rc6-release3-rocky-worker-install.log`, and `rc6-release3-rocky-portal-install.log`. The three install recaps reported Admin `ok=204 changed=91`, Worker `ok=153 changed=49`, and Portal `ok=195 changed=75`.

## Executed scenario results

| Test ID | Procedure and expected result | Observed result | Status |
|---|---|---|---|
| `RC6-R3-ROCKY-MN-PORTAL-INSTALL` | Install Harbor on the independent Portal node; register it as role `portal`; keep workloads on Worker | Harbor ran only on the Portal guest. Admin listed Worker and Portal as active, healthy, and available; Portal used WireGuard `10.99.0.3`. All six exact `0.0.1rc6-3.el10` package versions were present on Admin. | PASS — install/registration subset |
| `RC6-R3-ROCKY-MN-ADMIRALD-API` | Make an authenticated Harbor-to-Admirald request over WireGuard | From the Portal guest, authenticated `GET https://10.99.0.1:8080/api/v1/apps` with the configured CA returned HTTP 200 and one application. No credential values were printed or retained. | PASS — API connectivity subset |
| `RC6-R3-ROCKY-MN-PORTAL-ROUTE` | Route HTTPS through Admin Caddy to Harbor on the separate Portal node; verify the local lab CA | From the Portal guest, `curl --resolve portal.rc6.test:443:192.168.122.150 --cacert <lab-ca> https://portal.rc6.test/auth/register` returned HTTP 200. Admiral route state was active/healthy with no error. | PASS — routed endpoint subset |
| `RC6-R3-ROCKY-288-AUTO-ROUTE-RESTORE` | Stop Caddy; start an `admirald` restart while Caddy is unavailable; start Caddy two seconds later; let `admirald` finish startup; do not manually sync routes; verify persisted routes and HTTPS | At 07:02:53 UTC, `admirald` retried while Caddy was down. By 07:02:56 UTC, both services were active; Caddy Admin API returned 200; Portal and app routes were healthy with no route errors; strict-TLS Portal and workload requests both returned HTTP 200; no bootstrap/route-seed error was logged. | PASS — #288 runtime regression |
| `RC6-R3-ROCKY-MN-WORKER-PROVISION` | Provision the free `e2e-portal-free` app explicitly on the Worker; replay the same idempotency key; verify health, runtime and public response | Provision returned `succeeded`, instance `inst_98e5ea818edb7657`, node `rc6-r3-rocky-worker`. Replay returned the same operation and instance. Admiral reported `running/healthy/available`; rootless Podman showed the instance app and infra containers Up; the public app route returned HTTP 200 and the expected whoami container hostname. | PASS — CLI-to-Worker workload subset |
| `RC6-R3-ROCKY-HARBOR-CUSTOMER-FLOW` | Through the independent Portal, register a customer, reject pending login, approve, sync catalog, publish, and deploy a free app | Registration and pending-login rejection passed. On repeated runs, approval and catalog-sync POSTs intermittently reset. Direct-to-Portal diagnostics observed a 302 with `Content-Length: 223` and zero body bytes; a Caddy run logged an incomplete upstream response and `connection reset by peer`. The Harbor process remained active and an approval may have committed before the client saw the reset. Catalog publication and Harbor customer deployment did not complete. | FAIL — tracked by #289 |

The direct CLI workload test validates the Admin-to-Worker path only; it does not satisfy the Harbor customer deployment check. No complete Rocky Multi-Node cell has passed.

## Test-only setup notes and limits

- Public routing used reserved `.test` names and a local CA only inside the isolated guests. No public DNS or production certificate was configured.
- The first Caddy sync failed because the lab certificate directory did not grant Caddy traversal/read access. After correcting the lab ACL, the Portal route returned HTTP 200. This was a lab setup error, not an Admiral package finding.
- The first route health probe rejected the local self-signed test certificate. Installing that lab CA in the Admin guest trust store and restarting Admirald made the route health check pass. This is test trust configuration; it does not demonstrate certificate issuance or renewal.
- A default `cockpit.rc6.test` route briefly triggered an ACME **staging** rejected-identifier request before the lab configuration was narrowed to explicit Portal/apps/Flagship hosts. The route was removed, the test domain has no public DNS, and no production ACME endpoint was contacted.
- Single-Node Rocky, all Fedora/AlmaLinux/CentOS Stream cells, Portal backup/restore, billing/cancellation, broad isolation, stress, and remaining resilience gates are not tested on Release 3.

## Release decision

The active gate is four x86_64 operating systems × Single-Node/Multi-Node = eight cells. Release 3 remains **0/8 complete** and is no longer eligible for release credit after the Harbor response defect in #289. Preserve these scenario results as Release 3 history; after a fix, build a fresh candidate and rerun affected acceptance checks before any cell is credited.
