# Current triage snapshot — 2026-10-27 13:59 UTC

This snapshot supersedes the 2026-10-26 open-issue inventory later in this
historical review.

## Release state

- Current packaged candidate: RC6 Epoch 5 Release 17; all six RPMs were built
  natively for EL10 and Fedora Rawhide (`.el10` and `.fc46` respectively),
  signed, and recorded with NEVRA/SHA-256 in the
  [R17 evidence](evidence/rc6-e5-r17/CANDIDATE.md). Root CI run 40497925910 is
  green on the exact R17 root SHA. Exact-candidate issue acceptance passed for
  #182 and #291 on the existing Rocky Admin + independent Portal + Worker
  topology. The [R17 open-issue report](evidence/rc6-e5-r17/ISSUE-228-271-294-REPORT.md)
  records exact-candidate acceptance for #228 and #294 as well.
- R16 is invalidated for #291 after the second supported remove-and-rejoin
  sequence timed out before peer reconciliation. Its records remain under
  [R16 evidence](evidence/rc6-e5-r16/CANDIDATE.md).
- R16 did pass remove/revocation/denial and a first rejoin. The repeated
  rejoin exposed a second ordering defect: the registering node was omitted
  from the peer inventory until it became `active`, while it could not become
  active before the WireGuard peer and heartbeat were restored.
- Root product fix `ba59c45d647bd354c878d7e61497896746a88c2b` admits only the
  exact currently registering node to the pre-heartbeat peer inventory. The
  root regression suite passed 189 tests locally. All six Release 17 specs now
  reference this source; `scripts/validate-release-refs.py` passes. R17 root CI,
  both distro builds, and the #182/#291 exact-package runtime checks are green.
- Full runtime release matrix: **0/6 cells complete**. Rocky Multi-Node has
  partial R15 evidence; the full cell checklist and the other five cells remain
  pending.
- GitHub root issues: **3 open**: #106, #255, #271. **287 are closed**.
  #228 and #294 were closed after exact R17 acceptance; #182 and #291 also
  closed after exact R17 acceptance, and #289 after its R15 acceptance.
- R17 exact-candidate issue closures recorded here: **4** (#182, #228, #291,
  #294). Gold remains ineligible while any issue is open or any matrix cell is
  incomplete.
- Exact R17 issue probes pass for #228 on Rocky Single-Node and Multi-Node
  (injected Podman cleanup failures, retry convergence, plus clean controls),
  #271 on Rocky Single-Node and Multi-Node, and #294 on Rocky Single-Node and
  Multi-Node. The hashed raw evidence and combined report are published. These
  probes do not credit a full release-matrix cell.
- Host resources at 2026-10-27 13:56 UTC: 2.2 GiB available RAM and 45 GiB
  free disk. The three original guests and one temporary Rocky Single-Node guest
  remain running; the temporary guest has 793 MiB available RAM and 6.3 GiB
  free disk. Validation remains serial and resource-capped.

## Open-issue triage

| Issue | Current evidence | Remaining acceptance |
|---|---|---|
| #106 | No verified PayPal sandbox transaction, webhook, or lifecycle evidence; GitHub's latest review keeps this as an external gate. | On a clean candidate guest, complete sandbox checkout, verify signed/fresh/idempotent webhook, provision, lifecycle changes, cancel/refund, and publish the playbook/evidence. |
| #255 | The conditional queue-state fix and deterministic migration regression are reviewed; no R17 live Multi-Node migration timeline is recorded. | Complete a real restore/cutover on two Workers, preserve the logical instance ID, and capture operation states showing no backward transition to `queued`. |
| #271 | Exact R17 Rocky Single-Node and Multi-Node redirect probes passed for loopback and Worker-address targets; the target received zero requests over repeated periodic checks. | Complete the exact R17 CentOS Stream Multi-Node probe, then publish the evidence and close. |

## Closed since the previous snapshot

| Issue | Exact-candidate or prior acceptance |
|---|---|
| #182 | R17 Rocky Multi-Node Harbor customer flow passed backup, owner download, upload, paused restore, SQL marker verification, resume to running/healthy/available, and both Worker-IP and metadata-origin rejection controls. The restore operation succeeded and the operation count remained unchanged across negatives. See the [R17 runtime report](evidence/rc6-e5-r17/ISSUE-182-291-REPORT.md), [raw logs](evidence/rc6-e5-r17/runtime/issue-182-r17-20261027/), and [GitHub closure](https://github.com/admiral-project/admiral/issues/182). Harbor's local request row still awaited scheduled reconciliation at capture time; the authoritative Admiral operation and workload state passed. This issue-specific pass does not count as a matrix cell. |
| #291 | Two R17 no-force Worker remove/rejoin cycles passed. Packaged `admiral-install` automatically restored exact Worker↔Portal peers and Portal firewall authorization; removal revoked them and denied Worker access. Heartbeat, handshakes, permanent SSH, and strict-CA Worker-to-Portal HTTPS passed. See the [R17 runtime report](evidence/rc6-e5-r17/ISSUE-182-291-REPORT.md), [raw cycle logs](evidence/rc6-e5-r17/runtime/issue-291/remove-rejoin-r17-20261027/), and [GitHub closure](https://github.com/admiral-project/admiral/issues/291). This issue-specific pass does not count as a matrix cell. |
| #228 | Rocky Single-Node and Multi-Node R17 post-fix fault injections returned failed deprovision with retained resources/retry state; restored Podman retries converged to empty inventories. Clean controls passed on both topologies. See the [R17 report](evidence/rc6-e5-r17/ISSUE-228-271-294-REPORT.md), [raw Single-Node evidence](evidence/rc6-e5-r17/runtime/issue-228-r17-rocky-sn-20261027/), [raw Multi-Node evidence](evidence/rc6-e5-r17/runtime/issue-228-r17-rocky-mn-20261027T145000Z/), and [GitHub closure](https://github.com/admiral-project/admiral/issues/228). |
| #294 | Rocky Single-Node and Multi-Node exact R17 startup probes both reconciled stale persisted state before fresh Fleet metrics and recovered after Fleet restarted. See the [R17 report](evidence/rc6-e5-r17/ISSUE-228-271-294-REPORT.md), [raw Single-Node evidence](evidence/rc6-e5-r17/runtime/issue-294-r17-rocky-single-20261027/), [raw Multi-Node evidence](evidence/rc6-e5-r17/runtime/issue-294-r17-multinode-20261027/), and [GitHub closure](https://github.com/admiral-project/admiral/issues/294). |
| #289 | Four independent Harbor customer flows passed on Rocky Multi-Node: two through Admin Caddy and two directly over Portal WireGuard. Each covered pending signup/login rejection, approval, catalog publication, deployment, healthy/available state, and deprovision. Strict HTTPS probes returned HTTP 200; cleanup left no app routes or rootless Podman resources. The [R15 report](evidence/rc6-e5-r15/ISSUE-289-REPORT.md), hashed raw evidence, and [GitHub closure](https://github.com/admiral-project/admiral/issues/289) are published. This issue-specific pass does not credit a matrix cell. |

Three issues remain open at the time of this snapshot. Do not declare Gold while
any issue remains open or any of the six exact-candidate cells is incomplete.
The #291 installer integration and peer reconciliation fix are included in R17;
no product changes occurred during these issue-specific validation runs.

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
