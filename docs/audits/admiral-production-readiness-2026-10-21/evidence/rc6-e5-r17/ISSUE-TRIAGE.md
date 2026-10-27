# Open issue triage — 2026-10-27

This snapshot reflects the live root issue list checked on 2026-10-27. GitHub
reports **6 open issues**: #106, #255, #271, #304, #305, and #307. Issue #306
is closed. #307 was reopened because the expected security checklist remains
incomplete.
Release R17 remains at **0/6** required x86_64 runtime cells and is **not Gold**.

The exact historical product payload is R17
(`7a0796ddb898a55e0007a473cd9ea706cd2ecd1f`, RPM Release 17). Product source
has since changed in the working tree for #255 and #304, so R17 cannot be
promoted as the release candidate. No replacement RPM candidate has been
built. The next candidate must increment the Release field on all six RPMs,
build six native Fedora RPMs from the same source pins, and pass the complete
validation matrix.

## #106 — PayPal sandbox lifecycle

**Open; external E2E evidence is missing.** The platform flow is implemented,
but closure requires an agency sandbox checkout, a signed and fresh webhook,
idempotent redelivery, paid provisioning, upgrade/downgrade, pause/resume,
cancel, and refund, with the transaction and audit evidence documented. No
sandbox credentials or completed checkout evidence are available in this lab.

## #255 — post-dispatch queued state during migration

**Open; R17 Multi-Node acceptance did not pass.** The exact R17 Rocky Linux
10.2 run provisioned a source workload and began migration to a second Rocky
Worker. The 0.75-second sampler captured 55 observations with a maximum gap of
about 0.758 seconds; no operation regressed to `queued`. Database and volume
backups, source stop, target provision, and target start all reported success.
The migration then rolled back and failed target validation (`instance not
running`). The timeline contains no restore child operation or migration
restore step, so the required restored-data check and cutover did not happen.
Cleanup deprovisioned the test workload. This is a failed acceptance run, not a
pass; investigate the missing restore/target validation path and rerun after a
fix. The R17 source inspection identifies a concrete cause for the missing
restore: `runMigration` dispatches both backup tasks with an empty backup ID
and does not create pending `BackupRecord` rows, while the callback only
updates an existing record and the migration restore loop only reads
successful records. The worker therefore reports successful backup
operations, but the migration has no records to restore. There is also a
status-ordering race to address: `HandleFleetCallback` marks the operation
terminal before updating `customer_apps.technical_status`, while migration
waits only for the operation and immediately validates the instance status.
The trace establishes the failed target validation; the race is a source-level
path consistent with it and should be covered by a deterministic regression.
Raw evidence is under
[`runtime/issue-255-r17-issue255-rocky-mn-20261027t142851z-1874039/`](runtime/issue-255-r17-issue255-rocky-mn-20261027t142851z-1874039/).

## #271 — HTTP health checks must not follow redirects

**Fix confirmed; exact-candidate issue gate still incomplete.** Rocky Linux
10.2 Single-Node and Multi-Node R17 probes passed: redirect listeners on
loopback and the Worker address recorded zero requests while workloads stayed
healthy and available. The required exact-candidate CentOS Stream 10
Multi-Node probe remains outstanding. See
[`ISSUE-228-271-294-REPORT.md`](ISSUE-228-271-294-REPORT.md).

## #304 — IPv6 public transport for Worker and Portal

**Open; implementation regressions pass, but public-IPv6 E2E is outstanding.**
The intended topology is:

- Admin keeps public IPv4 and IPv6.
- Worker and Portal use public IPv6 and do not require public IPv4.
- WireGuard uses IPv6 endpoints as its public transport while retaining the
  existing private IPv4 addresses and routes inside the VPN.
- Worker and Portal internal services remain restricted by the IPv6 firewall;
  public IPv6 must not expose Fleet, Podman, workloads, or Harbor directly.

The working-tree changes bracket IPv6 WireGuard endpoints, keep the private
IPv4 `AllowedIPs`, enable family-scoped IPv6 egress for IPv6 endpoints, and
fall back to the WireGuard IPv4 address during Worker/Portal registration when
the host has no default IPv4 address. Targeted local regression checks pass,
including rendered nftables validation for Admin, Worker, and Portal. These
checks do not establish the E2E acceptance criteria. The current validation
lab has no publicly routed IPv6 Worker or Portal. Required evidence needs
Admin dual-stack plus IPv6-only-public Worker and Portal guests, WireGuard
connectivity with private IPv4 overlay retained, restricted inbound IPv6,
reboot recovery, and the application/Portal lifecycle through Admin.

## #305 — example app definitions

**Open; runtime validation is not started.** Acceptance asks for examples in
`examples/apps` to run on one node with 7 GiB RAM and to complete setup, pause,
restart, backup, and restore, while checking the app-definition documentation.
The most demanding ERPNext example is called out as needing at least 4 GiB for
one app. The host has 7.5 GiB total RAM, 5.4 GiB currently available, and 49
GiB free disk after obsolete validation VMs were removed. A 7 GiB guest plus
the host and its services would still overcommit available RAM. No example
lifecycle E2E has been run; do not count static review as that acceptance.

## #306 — documentation for the coordinated release

**Closed after the coordinated release documentation was updated and CI passed.**
The release branch now documents the active Fedora Rawhide/Rocky 10/CentOS
Stream 10 matrix, Fedora-native RPM requirement, AlmaLinux and AL2023 support
boundaries, current installer requirements, IPv6-only public Worker/Portal
configuration with its pending E2E boundary, and the difference between local
app-definition validation and runtime lifecycle acceptance. It also marks the
RC2 issue page historical and corrects component role/runtime details. Root
CI passes on `dfb239f`; the documentation commits in Fleet PR #90, Harbor PR
#54, and Flagship PR #28 also pass their repository CI. `validate-release-refs.py`
confirms the selected component references match the checked-out SHAs.

## #307 — security verification scope

**Open — expected A–L security review incomplete.** The issue's checklist is
the expected verification scope: architecture boundaries; two real tenants on
one Worker; SELinux/storage; Podman/Quadlet; systemd user manager; Fleet
privileged operations; effective Ansible baseline; network exposure;
secrets/backups; tenant authorization; and a proportional live Multi-Node
validation. Reuse applicable historic evidence and avoid duplicate tests, but
do not mark untested controls PASS. `UserNS=auto` adoption remains optional.

Focused checks of #255 migration, #304 IPv6/WireGuard/firewall, CLI app
validation, and selected ownership controls found no confirmed regression in
those reviewed paths. They do not meet #307's complete expected scope. Current
candidate package/runtime evidence, two-customer isolation negatives, and
effective host security controls remain outstanding. See the
[`partial security review`](../issue-307-20261027/SECURITY-REGRESSION-REPORT.md)
for an A–L coverage table and exact evidence limits. The GitHub issue was
reopened so its state reflects that remaining work.

## Release and resource gates

- Required runtime cells: Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide
  x86_64, each Single-Node and Multi-Node: **0/6**.
- Gold: **not eligible** because issues remain open and the matrix is
  incomplete.
- Latest host observation: 5.4 GiB available RAM and 49 GiB free disk, with no
  validation VMs running. The three updated x86_64 OS seed images remain.
  Keep future builds serial and resource-capped; a 7 GiB guest still needs a
  larger host.
