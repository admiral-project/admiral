# Security review status — issue #307 (incomplete)

**Date:** 2026-10-27 UTC
**Status:** Partial review only. The expected #307 security verification is **not complete**, and no overall security verdict is made.
**Scope:** The issue's A–L checklist is the expected security-verification scope. Reuse historical evidence only when its source, configuration, and control still apply; avoid repeating the six-cell functional matrix solely to produce this security report. Focused regression checks below are evidence for only the areas they cover; they do not satisfy the untested runtime isolation and baseline checks. `UserNS=auto` is research; adopting it is not a closure requirement.

## Executive result

No new, confirmed security regression was found in the limited source and tests reviewed here. The IPv6 changes render valid WireGuard and nftables configuration and pass their targeted tests. The migration change passes its database-backed cutover and rollback tests. Selected tenant-ownership and backup-authorization tests also pass. These results do not establish that the full #307 checklist passes.

The expected review includes architecture and trust boundaries, two real customers sharing a Worker, effective SELinux/MCS and Podman controls, systemd user-manager access, Fleet privileged operations, Ansible's effective baseline, network exposure, secrets/backups, and tenant authorization. Several controls remain `NOT TESTED` on installed R18 packages. In particular, there is no live Multi-Node run with two tenants. The #307 closure criterion is therefore **not met**. The focused regression results below remain useful partial evidence; they cannot be used as a security certification or to close the issue. Reuse prior evidence only where its source, configuration, and control remain applicable, preserving every evidence limit. `UserNS=auto` adoption is not a closure requirement.

## Coverage against the expected #307 scope

| Issue section | Current status | Evidence and remaining work |
| --- | --- | --- |
| A. Architecture and trust boundaries | PARTIAL | Service identities, units, and selected product boundaries were reviewed below. A complete trust-boundary diagram and compromised-container versus `admiral-apps` impact analysis are still required. |
| B. Two-customer isolation on one Worker | NOT TESTED | A disposable Podman prototype is not an Admiral-managed two-customer Worker. Cross-volume, secret, socket, network, and resource-limit negatives must be exercised with actual Admiral workloads. |
| C. `UserNS=auto` research | PARTIAL | Documentation review and a disposable PostgreSQL prototype support postponing optional adoption. MariaDB/MySQL, full Admiral lifecycle, and migration compatibility were not tested. |
| D. SELinux and storage isolation | NOT TESTED on installed R18 | Historical checks exist, but effective Enforcing persistence, MCS labels, volume labels, and cross-customer file access were not confirmed on an installed R18 system. |
| E. Podman and Quadlet | PARTIAL | Renderer and unit source were reviewed. Effective capabilities, seccomp, SELinux labels, cgroups, pids limits, OOM behavior, and generated directory permissions were not measured on installed R18. |
| F. systemd user manager | PARTIAL | Service boundaries were reviewed statically. Live access to the user bus, Podman socket, units, and cgroups from customer workloads remains untested on R18. |
| G. Fleet privileged operations | PARTIAL | Recent migration and selected authorization paths were reviewed and tested. The complete lifecycle/setup/backup helpers, path and symlink handling, cleanup scope, and runtime privilege boundary still need evidence. |
| H. Ansible security baseline | PARTIAL | Selected networking/firewall templates and syntax were checked. Effective host configuration, idempotent reapplication, SSH, auditd, Fail2ban, file permissions, and dev-mode separation were not verified across the roles. |
| I. Network, WireGuard, and exposure | PARTIAL | IPv6 rendering and targeted regressions passed. No routed public IPv6 exists in this lab; current-candidate exposure, role-specific firewall state, revocation, and reboot recovery remain untested. |
| J. Secrets and backups | PARTIAL | Selected backup ownership/policy tests passed. Runtime secret isolation, secret canaries, storage credential scope, manipulated paths/objects, and real backup integrity/restore remain untested. |
| K. Tenant authorization | PARTIAL | Selected API ownership tests passed. Representative negative requests against two real customers on the deployed Multi-Node cluster remain untested. |
| L. Proportional Multi-Node validation | NOT TESTED on installed R18 | Requires independent Admin, Worker, and Portal plus two customers on the same Worker, with effective isolation checks and backup/restore/deprovision. R18 is built and signed, but there is no running validation cluster on this host. |

## Candidate and changes reviewed

R17 is historical for its exact payload. Product changes since that package include root IPv6 spoke transport/firewall handling (`10f9301`), Admirald migration backup ordering and peer reconciliation/inventory (`e0d3326` and its required ancestors), Fleet health-check redirect handling (`fc6909f`, included in the selected `11f788c` source), and CLI node-removal reconciliation/app-definition validation (`840ed15`). These invalidate R17. R18 is now the replacement RPM candidate: all six EL10 packages and six native Fedora Rawhide packages were built from the selected source pins, signed, and recorded in [`rc6-e5-r18/CANDIDATE.md`](../rc6-e5-r18/CANDIDATE.md). Root CI is green for the build checkout `793a512` (run `40537161595`) and the later harness-only commit `1ec505b` (run `40541072575`); selected component CI runs and exact SHAs are listed in [`rc6-e5-r18/source-pins.txt`](../rc6-e5-r18/source-pins.txt). The `admiralctl` RPM spec change is a source pin only. No installed systemd unit changed. The R18 packages have not been installed for the current-candidate runtime checks in sections B, D–L; CI and package signing do not substitute for those checks.

Security-relevant changes reviewed:

| Change | Source | Review result |
| --- | --- | --- |
| IPv6 public endpoints for Worker and Portal while retaining private IPv4 WireGuard addressing | `scripts/install.sh:515-532,998-1003`; `ansible/roles/admiral_wireguard/templates/wg-admiral.conf.j2:1,58,68`; `ansible/roles/admiral_fleet/tasks/main.yml:237`; `ansible/roles/admiral_harbor/tasks/main.yml:287` | IPv6 literals are accepted; raw IPv6 WireGuard endpoints are bracketed; the private WireGuard `AllowedIPs` stay IPv4; registration falls back to the private WireGuard IPv4 address when a general-interface IPv4 fact is absent. |
| IPv6 egress activation and family scoping | `ansible/roles/admiral_firewall/templates/admiral-egress.nft.j2:17,33,57`; `scripts/install.sh:998-1003,1030` | IPv6 TCP egress is gated by IPv6 configuration or the explicit IPv6 destination list. The role's existing port policy remains in effect. IPv4 and IPv6 CIDR lists are handled independently. |
| Health-check redirect / SSRF path (#271) | `admiral-fleet/internal/agent/health.go`; `admiral-fleet/internal/executor/executor_provision.go`; tests `TestServiceHTTPHealthCheckDoesNotFollowRedirects` and `TestRunDeclaredServiceHTTPHealthCheckDoesNotFollowRedirects` | Both HTTP probe paths reject redirects instead of following an app-controlled `Location`. The exact selected Fleet source CI is green. This is source/test evidence; exact-candidate E2E confirmation remains outstanding under #271. |
| Peer inventory and node-removal reconciliation | `admirald/internal/api/api.go`; `admirald/internal/api/wireguard_peer.go`; `admiralctl/internal/client/client.go` | The selected source carries reconciliation and inventory updates, and CLI removal waits for reconciliation. These changes were included in green component CI; effective peer, route, and credential revocation on a live cluster remains untested here. |
| Migration backup records and callback ordering | `admirald/internal/api/admin_instances.go:46-80,107-142,325-379` | Migration creates a pending backup record before dispatch, passes its identity to Fleet, waits for record completion/checksum and waits for the resulting technical state before validating/cutting over. These are internal generated operations; this change adds no external authorization route or shell execution. |
| Local app-definition validation without API credentials | `admiralctl/cli/apps.go`; CLI config/client setup | Client construction is skipped only for `apps validate`, which performs local schema validation. Other commands retain normal client/authentication setup; tests cover validation with no API server or operator token. No authorization path was removed or bypassed. |
| Quadlet, systemd, Fleet privilege boundary, and RPM packaging | `admiral-fleet/internal/quadlet/renderer.go`; `packaging/systemd/*.service`; `packaging/rpm/*` | No Quadlet or systemd-unit product change was present. The current RPM spec edits only update package release/source pins; they change no installed security settings. Existing controls were reviewed statically, but effective installed behavior remains unverified on R18. |

## Controls reviewed

### Process and component boundaries

- `admirald` and Harbor systemd units run as `admiral`, with an empty capability set, `NoNewPrivileges=true`, and restricted writable paths (`packaging/systemd/admirald.service:19-33`, `packaging/systemd/admiral-harbor.service:21-26`). Harbor's packaged Gunicorn listener is loopback-bound and TLS-enabled (`admiral-harbor.service:11`).
- Fleet is intentionally a root service to manage the rootless account and its user manager. Its unit has a bounded capability set (`CAP_CHOWN`, `CAP_DAC_OVERRIDE`, `CAP_FOWNER`, `CAP_SETUID`, `CAP_SETGID`), `ProtectSystem=strict`, and restricted writable paths (`packaging/systemd/admiral-fleet.service:21-33`). It retains `NoNewPrivileges=false`, documented in the unit as required for this management path; this setting is pre-existing and was not changed here.
- Generated workload Quadlets use Podman `Network=pasta`, per-instance volumes and secret references, immutable image references by default, and `NoNewPrivileges=true` (`admiral-fleet/internal/quadlet/renderer.go:85-110,265-310`). They do not add a Podman socket or host PID/network namespace. `DropCapability=all` is intentionally absent for supported database entrypoints. No effective capability or seccomp state was measured on an installed candidate during this review.

### Authorization and backup ownership

Six selected Admiral API tests passed against a freshly created PostgreSQL database, which was dropped after the run:

- `TestHandleCustomerAppActionRejectsOtherCustomer`
- `TestCustomerOperationStatusEnforcesOwnership` (owner, other customer, other instance operation, unknown operation)
- `TestHandleCustomerAppsRejectsOtherCustomerProvision`
- `TestCustomerBackupListAndReadAreInstanceScoped`
- `TestCustomerRestoreRejectsBackupOwnedByAnotherCustomer`
- `TestCustomerBackupPolicyBlocksDisabledRestoreAndManualBackup`

These tests exercise API ownership and policy checks in the current source tree. They are not requests across an installed Admin/Portal/Worker cluster and do not prove isolation of workload files, network namespaces, Podman sockets, or secrets.

### Recent migration change

The following tests passed with `DATABASE_URL` set to a newly created, isolated database in the dedicated `admiral-audit-pg-test` container. The database was dropped after completion; no existing test database was truncated:

- `TestRunMigrationRollsBackBeforeCutover`
- `TestRunMigrationCutoverPreservesLogicalInstanceID`

Both tests passed in one focused run (`go test -p 1 ./internal/api -run '^(TestRunMigrationCutoverPreservesLogicalInstanceID|TestRunMigrationRollsBackBeforeCutover)$' -count=1 -v`). The mock publisher simulates task callbacks and backup completion. This verifies database/state ordering and rollback logic, but not real Fleet backup artifacts, cross-node restore, or a live Multi-Node cutover. Issue #255 therefore remains open.

### IPv6 firewall and WireGuard regressions

- `python3 -m pytest -q scripts/test_wireguard_ipv6.py scripts/test_wireguard_peers.py scripts/test_wireguard_peer_inventory.py scripts/test_installer_modes.py`: **117 passed**.
- `bash -n scripts/install.sh`: **PASS**.
- `ansible-playbook --syntax-check ansible/site.yml`: **PASS**; Ansible warned that this syntax-only invocation had no inventory and used implicit localhost. No playbook was applied to a guest.
- The rendered egress nftables configuration passed `nft -c -f -` for Admin, Worker, and Portal, with IPv6 enabled: **3/3 PASS**.
- `git diff --check`: **PASS**.

The public zone is configured by the Ansible firewall role from the node profile; Worker and Portal allow SSH and WireGuard ingress, while HTTP/HTTPS ingress is reserved for Admin/Single-Node. This was inspected in source. Effective inbound IPv6 listeners and firewall state were not checked on a public IPv6 guest. The lab has no globally routed IPv6 path, so #304's connectivity, exposure, reboot, lifecycle, backup/restore, and cleanup acceptance is **NOT TESTED**.

## `UserNS=auto` research and disposable prototype

Official Podman documentation describes `auto` as a generated user namespace, explains the rootless caller's UID mapping, and documents the need for subordinate UID/GID ranges. Quadlet exposes `[Pod] UserNS=` as the corresponding Podman option: [Podman pod create](https://docs.podman.io/en/stable/markdown/podman-pod-create.1.html), [Podman Quadlet](https://docs.podman.io/en/stable/markdown/podman-systemd.unit.5.html), [Podman create and subordinate IDs](https://docs.podman.io/en/latest/markdown/podman-create.1.html).

A disposable Rocky Linux 10 guest was created from the updated x86_64 seed and removed after the experiment. It used 1.5 GiB guest RAM; host capacity remained above the guardrail, and the updated seed was unchanged. Guest Podman was 5.8.2, rootless mode was available, and the host reported cgroup v2. A temporary `admiral-apps` user with subordinate IDs ran two separate pods, each containing a PostgreSQL 16 Alpine container and its own persistent volume.

Observed:

- Pod A mapped container UID 0 to subordinate UID 100000; Pod B mapped container UID 0 to 101024. Each mapping was 1024 IDs in this Podman configuration.
- Both containers were reported `Privileged=false` with private PID mode.
- A marker written by PostgreSQL in A remained after stopping and restarting the container.
- A deliberately adversarial Pod A container, given B's volume path read-only, returned exit status 1 and did not read the canary file. This is a volume-permission smoke test, not a test of an Admiral-managed tenant workload or an escape attack.
- Podman warned that there was no systemd user session and fell back from its systemd cgroup manager to `cgroupfs`. Effective CPU/memory limits, the production user manager, SELinux MCS categories, backup/restore, MariaDB/MySQL, application images, and a migration of existing volumes were not verified.

**Recommendation: postpone adoption; keep `UserNS=auto` as optional hardening.** The prototype establishes feasibility for one PostgreSQL image and basic persistent-volume behavior. It does not establish compatibility across supported application images or Fleet lifecycle/backup workflows, and the clarified issue explicitly says adopting it is not required. Do not add it to product Quadlets as part of this review.

## Historical evidence reused, with limits

[`SECURITY_REVIEW.md`](../../SECURITY_REVIEW.md) records prior SELinux Enforcing, rootless Podman, non-privileged containers, private PID/network namespaces, separate volume paths, selected authentication negatives, and peer-revocation tests. That evidence belongs to older exact candidates and does not prove the current dirty source or effective settings on a replacement RPM.

The same historical review explicitly leaves direct cross-workload database access, filesystem and secret reads, rootless user-bus/socket access, effective capability/seccomp/cgroup state, complete endpoint authorization, secret canaries, and public/peer listener checks unverified. Those items are not relabeled PASS here. The current API tests and small `UserNS=auto` prototype add scoped evidence only.

## Findings and remaining `NOT TESTED` items

**Confirmed new security findings:** none in the reviewed changes. No new GitHub issue is warranted from this evidence.

**Not tested on the current package/candidate:**

1. Actual Admin + independent Portal + Worker Multi-Node runtime with two Admiral tenants on one Worker, including negative cross-tenant database, filesystem, secret, and service access.
2. Effective SELinux Enforcing/MCS labels, seccomp profile, capabilities, process/CPU/memory cgroup limits, user-manager socket visibility, and secret-file permissions on a newly built candidate.
3. Public-IPv6 reachability and exposure negatives for Worker and Portal, reboot/reconciliation, and application/Portal flows. The lab has no routed global IPv6; track this work under #304.
4. Real migration backup artifacts and restore on a Multi-Node candidate for #255.
5. Current RPM dependency advisory triage and a secret canary across process arguments, logs, callbacks, and backup contents. Historical scans have older database timestamps and are not current evidence.

These gaps are not claims of a new regression. They are limits on runtime security evidence for the built R18 candidate, tracked separately from the static review. The active matrix remains **0/6**, and no Gold declaration is eligible.
