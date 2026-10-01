# Harbor functional validation

## Status — 2026-09-30

**PENDING: complete Harbor functional validation has not been demonstrated.**

The [RC4 r12 report](0.0.1rc4.tier2.validation.md) records a passing
infrastructure and Golden WordPress matrix. Harbor HTTP 200 and authenticated
communication checks do not establish complete customer or billing behavior.
Those results apply to the exact recorded RPM hashes, not subsequent changes.

Commit `27000b7cc9e147338f5e6cc2573fbd599798945b` changes
`ProtectHome=read-only` for catalog synchronization and reconciliation. Runtime
validation of both packaged services after that change remains required.

## Current verification limits — RC5 Release 5

The Harbor Python suite passes **323 tests** in the current checkout, with nine
SQLAlchemy legacy API warnings. Black, Ruff and Flake8 pass on the changed
Python files. These are source-level checks; they do not validate packaged
systemd units, PostgreSQL, or running Harbor services. The r4 package results
are invalidated by the r5 source fixes, and all r5 runtime cells remain pending
until the six Release 5 RPMs are built and installed on fresh guests.

The sandbox cannot access the host system bus or libvirt socket, so an
authoritative host service/VM inventory is still pending. MinIO remains in the
runtime acceptance scope as a locally hosted S3-compatible service for real
backup/restore flows; it will run on an existing validation guest to stay
within the three-VM limit. PayPal live payment and other flows requiring
external accounts/services remain separate gates.

## Required acceptance evidence

All rows below are pending. Execute against an isolated test deployment with
production security settings and record the exact sources and RPM hashes.
Use distinct customers to verify authorization boundaries. Do not include
credentials, tokens, private keys, or database URLs in evidence.

| Area | Required real flow and acceptance evidence |
|---|---|
| Packaged services | Start web, catalog-sync and worker with PostgreSQL and their shipped hardening; record exit status and sanitized journal. Confirm both timers execute their jobs successfully. |
| Catalog | Synchronize from admirald; verify visible apps, plans and prices. Repeat sync and confirm no duplicate records; check upstream removal and recovery from an API failure. |
| Identity | Registration, login, logout, profile and implemented recovery flows; confirm unauthenticated access fails and one customer cannot read or operate another customer's resources. |
| Purchase | Select a plan, accept applicable terms, complete PayPal sandbox approval and receive a verified webhook. Confirm subscription, invoice and customer ownership are consistent. |
| Payment safety | Reject invalid signatures; replay valid events and exercise return/webhook ordering without duplicate billing or provisioning. Verify abandoned and failed payments do not authorize provisioning. |
| Provisioning | Paid order creates exactly one instance through admirald; setup completes and the customer can access the application and its authorized credentials. |
| Customer operations | Exercise exposed lifecycle actions, backup/download/upload and restore through Harbor; verify real workload state, restored data and authorization for each action. |
| MinIO backup/restore | Run a local MinIO S3 endpoint on one of the three guests; upload a real database/volume backup, verify object size and checksum, restore it, and prove post-backup data is reverted. |
| Subscription changes | Exercise exposed plan changes and cancellation, including the prepaid period, overdue reconciliation and eventual cleanup. Record audit and provider state. |
| Worker and email | Execute reconciliation against actual state; verify retry behavior, no duplicate actions and delivery of configured transactional notifications. |
| Support and billing UI | Create and inspect support requests; verify invoice/receipt values and customer isolation. |
| Recovery | Restart services during pending work, then confirm consistent state and successful retry without duplicate resources. |
| Live PayPal release gate | Record a separately authorized real payment and its verified callback, billing records and provisioning outcome. Sandbox success alone does not satisfy this gate. |

For each executed scenario, record date, distribution, topology, exact candidate,
steps, expected and actual outcome, operation identifiers, sanitized evidence
location, and cleanup result. Mark unexecuted scenarios PENDING and failures
FAIL; do not promote a health check or a mocked test to functional PASS.

Complete validation requires the applicable flows in both single-node and
multi-node deployments. Changes to the coordinated RPM candidate require new
evidence under the [release validation runbook](../release_validation.md).
