# Harbor functional validation

## Status — 2026-10-02

**PENDING: complete Harbor functional validation has not been demonstrated.**

The current source fix for the Release 9 subscriptions-page HTTP 500 passes
the full Harbor suite (326/326). Its coordinated Release 10 RPM has not yet
been built or installed. Complete installed-flow validation, local
webhook-ordering, and backup/restore remain pending in the fresh Release 10
single-node and multi-node matrix.

The [RC4 r12 report](0.0.1rc4.tier2.validation.md) records a passing
infrastructure and Golden WordPress matrix. Harbor HTTP 200 and authenticated
communication checks do not establish complete customer or billing behavior.
Those results apply to the exact recorded RPM hashes, not subsequent changes.

Commit `27000b7cc9e147338f5e6cc2573fbd599798945b` changes
`ProtectHome=read-only` for catalog synchronization and reconciliation. Runtime
validation of both packaged services after that change remains required.

## Current verification limits — RC5 Release 7

Both Release 7 RPM builds passed their packaged suites: Harbor **323/323** and
Flagship **266/266** on x86_64 and aarch64 builds. Harbor reported 284 existing
Alembic/SQLAlchemy deprecation warnings. These checks do not validate running
systemd services, PostgreSQL integration, or real backup/restore. All ten
Release 7 runtime cells remain pending.

Host inventory on 2026-10-01 before the first Release 7 cell found 7.5 GiB RAM,
5.4 GiB available, 8 GiB swap with 102 MiB used, and 214 GiB free disk. No
guests were running or defined. The two local RPM HTTP endpoints and SMTP
fixture are active. MinIO is provisioned inside a disposable guest so runtime
validation stays within the limit of three guests at 2 GiB each. During Rocky
single-node bootstrap, the host retained at least 3.5 GiB available, swap use
peaked at 157 MiB, and image storage remained above 213 GiB free.
That bootstrap reached Ansible's post-package repository refresh but exceeded
the initial 600-second harness cap; the VM was retired without an Admiral
runtime result. The cap is now 1,200 seconds and Rocky will be repeated from a
fresh overlay.

The runtime gate includes all Admiral-local services and flows. Tests that
require an external provider account or service are excluded by scope. PayPal
provider approval and live payment remain a separate 1.0 gate; locally
executable webhook validation and replay protection remain in scope.

## Required acceptance evidence

All locally testable rows below are pending. Execute against an isolated test deployment with
production security settings and record the exact sources and RPM hashes.
Use distinct customers to verify authorization boundaries. Do not include
credentials, tokens, private keys, or database URLs in evidence.

| Area | Required real flow and acceptance evidence |
|---|---|
| Packaged services | Start web, catalog-sync and worker with PostgreSQL and their shipped hardening; record exit status and sanitized journal. Confirm both timers execute their jobs successfully. |
| Catalog | Synchronize from admirald; verify visible apps, plans and prices. Repeat sync and confirm no duplicate records; check upstream removal and recovery from an API failure. |
| Identity | Registration, login, logout, profile and implemented recovery flows; confirm unauthenticated access fails and one customer cannot read or operate another customer's resources. |
| Purchase | Exercise catalog, plan selection, terms and the full local mock checkout. Confirm subscription, invoice, payment and customer ownership; exclude only calls to the external PayPal service. |
| Payment safety | Exercise local webhook signature validation with fixtures, reject invalid signatures, replay accepted events, and verify return/webhook ordering without duplicate billing or provisioning. Provider-hosted calls are excluded. |
| Provisioning | Paid order creates exactly one instance through admirald; setup completes and the customer can access the application and its authorized credentials. |
| Customer operations | Exercise Harbor lifecycle actions, backup/download/upload and both remote and uploaded restore paths; verify real workload state, restored data, transfer checksum and customer authorization. |
| MinIO backup/restore | Run a local MinIO S3 endpoint on one of the three guests; upload a real database/volume backup, verify object size and checksum, restore it, and prove post-backup data is reverted. Also run the control-plane backup and asynchronous S3 verifier. |
| Subscription changes | Exercise exposed plan changes and cancellation, including the prepaid period, overdue reconciliation and eventual cleanup. Record audit and provider state. |
| Worker and email | Execute reconciliation against actual state; verify retry behavior, no duplicate actions and delivery of configured transactional notifications. |
| Support and billing UI | Create and inspect support requests; verify invoice/receipt values and customer isolation. |
| Recovery | Restart services during pending work, then confirm consistent state and successful retry without duplicate resources. |
| External provider gate | PayPal sandbox approval and live payment require external provider services/accounts and are excluded from this local validation. Live payment remains a separate 1.0 gate. |

For each executed scenario, record date, distribution, topology, exact candidate,
steps, expected and actual outcome, operation identifiers, sanitized evidence
location, and cleanup result. Mark unexecuted scenarios PENDING and failures
FAIL; do not promote a health check or a mocked test to functional PASS.

Complete validation requires the applicable flows in both single-node and
multi-node deployments. Changes to the coordinated RPM candidate require new
evidence under the [release validation runbook](../release_validation.md).

## RC5 Release 7 runtime evidence — 2026-10-01

Rocky Linux 10.2 x86_64 single-node validation has now exercised Harbor Web,
customer/support isolation, free catalog provisioning, lifecycle actions,
customer backup, MinIO-backed Golden backup/restore, and cleanup with the
Release 7 RPMs. Those gates passed in fresh guests with authenticated local
SMTP and MinIO. The final service audit and API security checks also passed.
This does not complete the Harbor acceptance matrix: no full release cell has
passed, and the other supported operating systems and multi-node topology
remain unvalidated for Release 7.

Two release blockers remain. The control-plane backup unit fails on a clean
install with `226/NAMESPACE` because its declared state directory is absent
(issue [#143](https://github.com/admiral-project/admiral/issues/143)). The
paid local mock-checkout on clean Rocky failed before its approval form: Harbor
redirected to `/mock-paypal/approve`, which returned HTTP 404. The fresh
database default in `app/settings.py` is `https://localhost:5000`, while the
packaged Harbor endpoint is `https://localhost:5001`; `app/paypal.py` builds
the mock URL from the persisted setting. Issue
[#144](https://github.com/admiral-project/admiral/issues/144) records the
reproduction, with a proposed clean-install URL seeding and checkout regression
in [its fix comment](https://github.com/admiral-project/admiral/issues/144#issuecomment-5941785150).
The checkout correction is committed locally in Harbor as
`1f583fc30a8d90323fa510a940381ab594977962`: when no database override exists,
the effective URL comes from `HARBOR_EXTERNAL_URL`, while an explicit saved
URL remains authoritative. A clean-install route regression now verifies the
paid deploy reaches the mock approval form at that origin. Harbor passes
324/324 tests. The fix has not yet been included in an RPM, so these tests do
not replace installed Release 8 validation. No real PayPal endpoint was
contacted.

A fresh CentOS Stream 10 Release 7 guest independently reproduced the same
paid-checkout failure: after mock mode, SMTP-backed registration/approval and
free provisioning passed, the paid deploy followed a 302 to
`/mock-paypal/approve` and received HTTP 404 without `subscription_id` or
`return_url`. Harbor restored its prior PayPal mode and the disposable instance
was deprovisioned. Harbor Web, the broader free provisioning/lifecycle/manual
backup flow, customer isolation, Chromium, API security and final service audit
passed in that cell. The paid failure stopped the extra workflow before its
local webhook-ordering and upload/restore cases. No provider endpoint was
contacted. RC5 Release 7 remains unvalidated; the CentOS evidence is recorded
in the [RC5 validation report](rc5-validation.md).

Release 7 is now superseded. The Release 8 Harbor source commit is pinned for
the next coordinated RPM build; no Release 8 package has been built or
runtime-tested. Fresh Harbor installed-flow, local webhook-ordering, and
upload/restore validation remain pending after that build.

## RC5 Release 9 evidence and Release 10 reset — 2026-10-02

The signed Release 9 Harbor RPM completed clean Rocky 10.2 single-node
registration, local SMTP, free provisioning, customer lifecycle, and the
mock-paid checkout through Harbor's CSRF-protected confirmation and successful
paid provisioning. The database contained the expected paid order, active
subscription, paid invoice, and completed payment; `/client/billing` showed the
paid app. The customer subscriptions page returned HTTP 500.

The confirmed cause is a type mismatch: `Subscription.next_billing_at` is a
persisted ISO string, but the customer subscription list/detail and admin
instance detail templates call `.strftime()` on it. Issue
[#150](https://github.com/admiral-project/admiral/issues/150) tracks the
reproduction and fix. Harbor commit
`5f0353d32868842f93d97db1cd42b272309633e4` renders the stored string directly
in those three views and adds route regressions with a populated billing date.
The full Harbor suite passes **326/326** tests. Ruff is unavailable in the
environment.

The Release 9 Rocky cell passed Golden with real MinIO backup and restore,
Harbor Web and integral workflows, isolation, browser checks, API security,
and final service audit; it failed only at the subscriptions page. No other
Release 9 OS or topology was run, so Harbor has not completed its full runtime
matrix. The coordinated package candidate has moved to Release 10 and must be
rebuilt and revalidated from clean guests across the entire matrix. No real
PayPal endpoint was contacted; the local mock workflow remains in scope.
