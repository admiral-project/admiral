# Current triage snapshot — 2026-10-27

This snapshot supersedes the 2026-10-26 open-issue inventory later in this
historical review.

## Release state

- Candidate: RC6 Epoch 5 Release 15; six RPMs built natively for EL10 and Fedora
  Rawhide (`.el10` and `.fc46` respectively), signed, with green component CI
  and green root CI at `e6b7baa`. The exact pins and Release 15 specs used to
  build the candidate are recorded in root commit `cdeb30d`.
- Full runtime release matrix: **0/6 cells complete**. Rocky Multi-Node has
  partial R15 evidence; the full cell checklist and the other five cells remain
  pending.
- GitHub root issues: **7 open**: #106, #182, #228, #255, #271, #291, #294.
  **283 are closed** in total; #289 was closed after its R15 acceptance passed.
- No product change has been made since R15, so its candidate identity remains
  current. Harness and evidence work does not invalidate it.
- Host resources at the latest check: 2.5 GiB available RAM and 49 GiB disk
  free. Rocky Admin guest had about 249 MiB available RAM and 6.7 GiB disk
  free. Validation remains serial to protect the host and guests.

## Open-issue triage

| Issue | Current R15 evidence | Remaining acceptance |
|---|---|---|
| #106 | No verified PayPal transaction or webhook evidence. | PayPal sandbox transaction, verified webhook, and full billing lifecycle. This external gate remains open. |
| #182 | Rocky Multi-Node R15: authenticated customer upload restore completed on the Worker; SQL marker and resumed workload verified; unregistered Worker and metadata origins rejected without creating restore operations. The packaged installer established Worker-to-Portal networking without manual playbook execution. The synthetic instance was deprovisioned successfully. | Complete the linked #291 peer-removal/revocation acceptance and attach the final R15 report. This targeted result is not a matrix-cell pass. |
| #228 | No R15 fault-injection result yet. | Inject Podman delete failures on R15 in Single-Node and Multi-Node; show failure with retry state/resources preserved, restore Podman byte-for-byte, verify retry cleanup, and run uninjected controls. |
| #255 | No R15 real Multi-Node migration result yet. | Complete a real restore/cutover, preserve logical instance ID, and retain a high-frequency operation-state timeline showing no backward transition to `queued`. |
| #271 | Existing issue-specific redirect evidence is on older candidates and Single-Node cells. | Re-run with exact R15 in the remaining release-gate contexts, including CentOS Stream and Multi-Node, and retain zero redirect-target requests. |
| #291 | Rocky Multi-Node R15 installer automatically established the dedicated Worker-to-Portal peer; strict HTTPS and the linked #182 restore passed without manually running the peer playbook. | On R15, verify peer/firewall revocation when removing the Worker and ensure an unregistered source remains denied; retain complete evidence. |
| #294 | No R15 Multi-Node control-plane restart result yet. | Restart the Admin control plane with stale persisted Worker metrics, show unavailable state before fresh metrics, then recovery after a valid heartbeat. |

## Closed since the previous snapshot

| Issue | R15 acceptance |
|---|---|
| #289 | Four independent Harbor customer flows passed on Rocky Multi-Node: two through Admin Caddy and two directly over Portal WireGuard. Each covered pending signup/login rejection, approval, catalog publication, deployment, healthy/available state, and deprovision. Strict HTTPS probes returned HTTP 200; cleanup left no app routes or rootless Podman resources. The [R15 report](evidence/rc6-e5-r15/ISSUE-289-REPORT.md), hashed raw evidence, and [GitHub closure](https://github.com/admiral-project/admiral/issues/289) are published. This issue-specific pass does not credit a matrix cell. |

Seven issues remain open at the time of this snapshot. Do not declare Gold
while any issue remains open or any of the six exact-candidate cells is
incomplete. The only release-invalidating changes are product changes; the
Release 15 helper-default alignment and validation evidence are harness work.

# Open issue closure review — 2026-10-26

Reviewed all 20 open root-repository issues using `gh issue list`, their bodies
and comments, the current component source, and the committed runtime reports.
The user explicitly authorized closing issues with sufficient implementation
and evidence. Closure here means the specific defect is fixed; it does not
credit an R9 matrix cell or declare a release ready. R8 was invalidated by the
HTTPS certificate-extension defect; historical targeted results below retain
their stated candidate identity and are not transferred to R9.

Source inspected: root `f31943d757ac80bf35d3521221d9873aab570f47`, admirald
`6e4a725d30c0fff877fe2252e843fae687810ae6`, Fleet
`fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`, Harbor
`dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.

## Sufficient evidence for completed/fixed closure

| Issue | Implementation and evidence |
|---|---|
| #181 | Authoritative backup/restore tier checks before enqueue and Harbor controls. [CentOS three-guest R2 probe](evidence/rc6-r2-epoch5/issue-181/centos/REPORT.md): hidden controls, forged requests rejected with 403, other customer rejected with 404, no backup/restore records, clean deprovision. |
| #190 | Harbor worker preserves cancelled local commercial status during remote sync and respects prepaid expiry. [Installed Fedora worker evidence](evidence/rc6-epoch4-issue-295-fedorasingle/REPORT.md) and [R2 follow-up](evidence/rc6-r2-epoch5/issue-295/fedora/REPORT.md): retained workload before expiry, exactly one successful deprovision after expiry, no duplicate. This does not validate PayPal. #295 is no longer open in the queried issue inventory. |
| #201 | Maintained Flask 3.1.3 RPM spec and dependency declarations preserve the security floor. [COPR build and source identities](evidence/python-dependency-refresh-20261024.md), plus [Rocky/Fedora repository resolution](evidence/rc6-release4-runtime/issue-probes/ISSUES-296-298-213-rocky.md) and installed Harbor evidence recorded in the issue. |
| #229 | Claim guards reject terminal, missing, replaced, and deprovisioned work; late terminal callbacks settle queue entries. Existing regression tests accompany the guards. [Rocky Multi-Node failure/deprovision/restart probe](evidence/rc6-epoch2-rocky-issue-229/REPORT.md), together with the earlier Fedora reboot regression recorded in the issue, demonstrates no replay or recreated workload. |
| #257 | Mistune 3.4.0 RPM spec and supported COPR publication exceed the required minimum. [Build/source identities](evidence/python-dependency-refresh-20261024.md), [Rocky/Fedora COPR resolution](evidence/rc6-release4-runtime/issue-probes/ISSUES-296-298-213-rocky.md), and clean-install evidence recorded in the issue address the missing dependency. |
| #278 | Node-removal transaction detaches instance/backup node references and preserves operation history, retaining active-workload protection. [Rocky before/after database evidence](evidence/rc6-epoch2-rocky-multinode-issues-278-284.md) and CentOS R2 evidence recorded in the issue demonstrate preserved terminal history and clean removal. |
| #286 | Reverse-proxy TLS CA serializes as the supported file-provider object with `pem_files`; TLS verification remains enabled. Runtime Caddy 2.10.2 configuration and strict-CA HTTP 200 are recorded in the issue; [three-guest progress report](evidence/rc6-release3-rocky-independent-portal-progress.md) supplies related route evidence. |
| #288 | Bounded, context-cancellable Caddy Admin API readiness retries replace the single startup attempt. [Three-guest restart regression](evidence/rc6-release3-rocky-independent-portal-progress.md): Caddy delayed two seconds, routes recovered before admirald restart completed, no manual sync, strict TLS 200. |

Fresh local check during this review:

```text
cd admirald
go test ./internal/networking -run 'Test.*(Caddy|Seed|Bootstrap|ReverseProxy)' -count=1
ok github.com/admiral-project/admiral/admirald/internal/networking 0.509s
```

Database-backed and VM tests were reviewed as recorded evidence, not rerun here.

## Keep open

| Issue | Missing evidence or unresolved scope |
|---|---|
| #106 | Real PayPal sandbox transaction, verified webhook and full billing lifecycle evidence. |
| #182 | Supported installation must complete uploaded restore without manual network repair; depends on #291 acceptance. |
| #191 | Explicit package verification after install and second reconciliation remains unrecorded in the reviewed acceptance evidence. |
| #228 | R8 Single-Node injection evidence does not complete the required failure permutations and current Multi-Node acceptance. |
| #255 | Real Multi-Node migration/cutover with operation timeline and logical instance-ID continuity. |
| #259 | Reviewed repeated Single-Node probes pass; requested Multi-Node acceptance remains pending. |
| #260 | Reviewed service-stop probes pass on Single-Node; requested Multi-Node probe remains pending. |
| #271 | Redirect controls pass on Single-Node; issue-wide Multi-Node acceptance remains pending. |
| #287 | R8 HTTPS setup failed on valid certificate extensions; R9 contains a further fix but its activation/renewal runtime acceptance is pending. |
| #289 | Intermittent POST response reset requires repeated routed and direct customer-flow runs; one pass per route is insufficient. |
| #291 | Automatic packaged Worker/Portal peer integration needs a fresh three-guest install and restore without manual playbook execution, plus negative access/removal checks. |
| #294 | Stale-startup Single-Node probe passes; explicitly requested Multi-Node control-plane restart remains pending. |

Existing working-tree edits and untracked validation artifacts were preserved.

## GitHub actions

Closed #181, #190, #201, #229, #257, #278, #286 and #288 with
`gh issue close --reason completed`. Each closure includes a comment describing
the implementation, evidence links and release-validation limits. All eight
commands succeeded. No other issue was modified.
