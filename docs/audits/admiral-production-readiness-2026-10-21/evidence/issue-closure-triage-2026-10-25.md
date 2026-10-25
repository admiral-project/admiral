# Issue closure triage — 2026-10-25

Scope: the 44 issues open after the 2026-10-24 triage. This review decides,
per issue, whether the Release 75 candidate and its evidence satisfy the
issue's own acceptance criteria, and therefore whether the issue can be closed
or must stay open.

Method: each issue was checked against the exact R75 candidate sources
(`admirald@65afd58`, `admiral-fleet@fc6909f`, `admiralctl@fa2a65e`,
`admiral-flagship@b7325bb`, `admiral-harbor@dd39e9a`, common payload
`3faa349`), the green root and component CI runs for those commits, the COPR
builds, and the raw R75 logs under
`packaging/build/validation/rc5-r75/runtime/`, plus the published evidence in
[`RELEASE75_VALIDATION_CLOSURE.md`](../RELEASE75_VALIDATION_CLOSURE.md).
An issue is closed only when its specific acceptance criterion was executed on
the candidate or when it is a documentation/scope item resolved by this review.

Result:

| Disposition | Count |
|---|---:|
| Closed with evidence | 23 |
| Retained open | 21 |

## Release scope decision

AlmaLinux 10 is Tier 2 and outside the active release matrix. The project COPR
`alma+epel-10-x86_64_v2` chroot does not build the Go RPMs
([#276](https://github.com/admiral-project/admiral/issues/276)), so its two
cells cannot be executed on the exact candidate. The active gate is therefore
six cells: Fedora Rawhide, Rocky Linux 10 and CentOS Stream 10, each in
Single-Node and Multi-Node. `AGENTS.md`, `docs/release_validation.md`,
`docs/multi_node_setup_v1.md` and `README.md` were corrected to state three
operating systems and six required cells. An AlmaLinux result must never be
counted as a gate cell while this limitation stands.

## Closed with evidence (23)

| Issue | Evidence on the R75 candidate | Boundary |
|---|---|---|
| #224 | Fix `dcbf78c` (in `3faa349`): the hub address is derived from the WireGuard subnet by the `wireguard_hub_ip` filter and the worker/portal rich rules no longer contain a literal hub IP. Regression coverage in `scripts/test_wireguard_peers.py` and `scripts/test_installer_modes.py`. The stale `fix-proposed` label and the earlier `needs-work` comment predate the fix. | Installer/firewall template scope; no separate threat-model review. |
| #231 | Corrected the stale matrix text in `evidence/release73-candidate.md`, `evidence/python-dependency-refresh-20261024.md`, `docs/multi_node_setup_v1.md` and `README.md`; each now states the active six-cell R75 status instead of "0/8 / COPR pending" or "Release 74". | Documentation alignment only. |
| #234 | Common payload `be20545` migrates injected distribution facts; none of the six R75 install logs (`multi/*/hub-install.log`, `w*-install.log`, `single-pass-*/single/*/install.log`) contains `INJECT_FACTS` or a deprecation warning, and every installer recap reports `failed=0`. | Ansible-core 2.22/2.24 compatibility path only. |
| #235 | Validation bypass documented in `f711832` and the `admiral-install` man pages; R75 preflight records zero applicable OS updates and every install log carries `installer_start_utc`, `installer_end_utc`, `installer_elapsed_seconds` and the NEVRA delta block. | Reports updates that DNF would apply; it does not force them. |
| #236 | Cold-start/restart coverage: `single-pass-20261024T220905Z/single/*/functional.log` shows provisioning readiness only after `db_ready=1`, and start/restart polls move `running stopped unavailable` → `http=200` → `healthy available` on all three OSes. | Provision readiness semantics; not a capacity conclusion. |
| #237 | WireGuard partition on all three Multi-Node cells reports `availability_reason=runtime_observation_stale` / `heartbeat_stale` with `effective_availability=unavailable`, then recovers after peer restoration. | Availability derivation only; no fault-injection sweep. |
| #242 | Harbor `%check` in the R75 build ran `350 passed` with no warnings, and Harbor starts, migrates and serves in all six cells. | Deprecation cleanup; unrelated warnings would be new issues. |
| #246 | Tier resize `small→medium→small` on all three Single-Node cells reads the SQL marker after each step by authenticating with the regenerated container's `POSTGRES_USER`/`POSTGRES_PASSWORD`, so lost secrets would fail the check (`single-resize-functional.sh`, `functional.log`). | Resize/reactivation secrets; not a full disaster-recovery test. |
| #249 | Harness correction `a7c59c4`: the R75 scripts run the privileged probes with `sudo` because the admin CLI config lives in `/root/.config/admiralctl`. | Harness documentation/behavior only. |
| #250 | R75 separates the libvirt underlay (`10.77.0.x`) from the WireGuard overlay (`10.99.0.x`) and asserts handshakes plus HTTP 200 over the overlay in every Multi-Node cell. | Addressing/reporting clarity; no change to the networking model. |
| #251 | `docs/multi_node_setup_v1.md` now references the Release 75 acceptance matrix, three operating systems and the Alma exclusion. | Documentation alignment only. |
| #256 | `post_reboot_poll=1 running healthy unavailable` with no containers, converging to `available` with SQL persistence on the same guest in all three Single-Node cells. | Reboot window only; not a failover test. |
| #258 | COPR build `11203004` (admiral-harbor) resolves all BuildRequires in a clean `alma+epel-10-x86_64_v2` chroot and passes `%check`; the local EL10 R75 build passed as well. | COPR/build evidence; no AlmaLinux runtime cell (see #276). |
| #267 | Active-worker removal is refused with an actionable message on all three Multi-Node cells (`evidence/node-removal/remove-active-instance.log`), and R70 recorded a single HTTP 409 instead of a retry loop. | Removal conflict path; force removal semantics unchanged. |
| #269 | EPEL pyOpenSSL pin applied by `a7c59c4` in the seed helper with regression coverage in `scripts/test_installer_modes.py`. | AlmaLinux runtime cell not executed because Alma is Tier 2 outside the active matrix. |
| #272 | Fedora R75 postrun shows only the remaining worker peer (`10.99.0.2/32`) after idle removal; Rocky R73 recorded a post-removal hub reboot without the peer; AlmaLinux/CentOS R73 recorded helper-failure retention with successful revoke on retry. | Peer revocation on removal and reboot; broader private-service reachability stays in #277. |
| #273 | The R73 per-check record is retained in `SINGLE_NODE_REPORT.md` and `evidence/release73-candidate.md`, and R75 supersedes the cell-level claim with 3/3 Single-Node PASS. | Documentation of historical checks only. |
| #274 | `python3-sqlalchemy.spec` Release 5 pins `python3dist(typing-extensions) = 4.16` for build and runtime; COPR build `11202996` succeeded in every configured chroot. | RPM dependency scope only. |
| #276 | Documented as an environment limitation: the COPR `alma+epel-10-x86_64_v2` chroot skips the Go RPMs, so AlmaLinux is Tier 2 and outside the active matrix. | Not a product fix. Re-open and re-run both Alma cells if the chroot is repaired and Alma returns to the gate. |
| #279 | Harness fix `fc67320`; the R75 terminal audit passes on all three Single-Node cells with the lifecycle customer ID. | Harness correctness only. |
| #280 | Harness fix `9104ca0`; R75 runner logs are pre-created and retained with their manifests. | Harness correctness only. |
| #281 | Fix `636e52a`; the Fedora R75 seed was created from the active `rc5-r75/{fedora,el10}/RPMS` paths and shut down cleanly. | Seed tooling only. |
| #282 | Fix `1d87058`; the corrected `SHA256SUMS` verifies (`sha256sum` of the manifest `2b939f27…`) and excludes itself. | Evidence integrity only. |

## Retained open (21)

| Issue | Missing acceptance |
|---|---|
| #106 | Real PayPal sandbox end-to-end flow; still the 1.0 payment gate. |
| #181 | Tier permission probe for customer backup/restore (hidden UI action plus API rejection) on the candidate. |
| #182 | Uploaded-backup restore through Harbor on the private WireGuard origin. |
| #190 | Harbor worker sync with a cancelled subscription. |
| #191 | Clean `rpm -V admiral-harbor` plus a second Ansible reconciliation. |
| #201 | Clean DNF transaction for Harbor without pre-installed dependencies. |
| #202 | Volume backup artifact with the required `0600` mode; R75 backs up the database only. |
| #205 | Clean `rpm -V admiral-common` after install and reconciliation. |
| #213 | TLS leaf reissue on `dev`→`single-node` reconvergence. |
| #216 | Persistently permissive SELinux guest with reboot. |
| #228 | Podman fault injection on Single-Node; only Multi-Node variants were exercised. |
| #229 | Terminal-operation task replay on Multi-Node. |
| #240 | Capacity-policy rejection against the R75 RPMs. |
| #255 | `queued`/terminal race on a real guest; unit test only. |
| #257 | Clean DNF transaction for Mistune in a fresh guest. |
| #259 | `user@<uid>.service` restart on the candidate. |
| #260 | Declared-service stop on the candidate; R75 covers reboot and partition only. |
| #270 | Staged-seed `rpmkeys` verification; the R75 Fedora seed used COPR dependencies rather than the local RPMs. |
| #271 | HTTP health-check redirect rejection executed on the candidate; only unit tests exist. |
| #277 | Master tracker for the broader production-readiness audit (isolation, fault injection, resilience, performance). |
| #278 | History preservation on node removal: the fix is in `65afd58`, but `r75-*-node-removal.sh` asserts only inventory, route and resource cleanup, never `customer_apps`/`operations`. Add the assertion to the removal scripts and re-run that check. |

## Applied changes

* 23 issues closed with an evidence comment and the `fixed` label (except #276,
  closed `wontfix` as an environment limitation, and #269, closed `fixed` with
  its Alma runtime cell explicitly outstanding).
* Stale `fix-proposed`, `fix-confirmed` and `needs-work` labels removed from the
  closed issues.
* #277 and #278 remain open; #278 needs the history assertion added to the R75
  node-removal scripts before it can be closed.
