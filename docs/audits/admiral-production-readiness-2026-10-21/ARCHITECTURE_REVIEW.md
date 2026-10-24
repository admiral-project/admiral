# Architecture review — Admiral production-readiness audit
> **Current gate status (2026-10-24):** Release 75 has three of six functional cells PASS: Rocky Linux 10, CentOS Stream 10 and Fedora Rawhide Single-Node. All three Multi-Node cells are NOT TESTED for R75. The six packages were built from the exact pins recorded in [`release75-single-node-20261024.md`](evidence/release75-single-node-20261024.md); the tested VM evidence is candidate-specific. Earlier release results are historical and do not count toward Release 75.
> **Historical R67 status:** Six RPMs are built for Fedora and six for EL10 from the same selected source pins, in separate native builders. Exact packages passed scoped Fedora/Rocky Single-Node install, lifecycle and reboot scenarios, plus a Fedora hub-and-two-worker bootstrap and workload lifecycle on each worker. No R67 cell is complete; matrix remains 0/8.

Audit started: 2026-10-21 UTC<br>
Historical audit candidate: RC5 Release 67 packages built from root commit `833d15aa4f8e96be30d28dad169b9d06a4d9894d`; the exact Fedora packages completed a scoped fresh three-guest bootstrap, placement on each worker, idempotent replay, HTTP/SQL checks and cleanup. R66 is historical and invalidated for release-gate credit. R66 had scoped Single-Node evidence on all four OSes and scoped three-guest Multi-Node evidence on AlmaLinux, CentOS Stream and Rocky Linux; **matrix completion remains 0/8** because none of the eight cells completed the full acceptance set. These observations do not pass a full R67 cell. Root CI is green for the package-preparation commit, and all five selected component pins matched `origin/main` at build time. See [`release67-candidate.md`](evidence/release67-candidate.md), [`release67-fedora-multinode-bootstrap.md`](evidence/release67-fedora-multinode-bootstrap.md), [`release67-fedora-multinode-placement.md`](evidence/release67-fedora-multinode-placement.md) and the historical [`release66-candidate.md`](evidence/release66-candidate.md).

## Scope and evidence rules

The active Release 75 runtime matrix is Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide on x86_64, each in Single-Node and Multi-Node (six cells). AlmaLinux is excluded because the configured COPR build environment omitted the Go RPMs; see #276. The host is x86_64 with KVM, 4 vCPU, 8 GiB RAM and 4 GiB swap. Each Multi-Node cell uses one admin/portal hub and two workers. Results from any earlier candidate are historical only.

Results from a different OS, candidate, or topology do not satisfy a Release 75 target cell.

Evidence is classified as static review, unit test, integration test, end-to-end test, or real fault-injection test. A successful API response alone is not proof of completed work. Each result is recorded in `TEST_MATRIX.md` and the corresponding topology report. No unexecuted scenario is marked PASS.

## Components observed

The coordinated repository contains five Git submodules plus root-owned packaging and installation material:

| Component | Observed responsibility | State and interfaces |
| --- | --- | --- |
| `admirald` | Central control plane, API, commercial and operational state, scheduling, routing, task publication and callback processing | Main PostgreSQL database plus a distinct PostgreSQL `admiral_queue` database; HTTPS API; Caddy Admin API on loopback; task signatures and optional task-payload encryption |
| `admiral-fleet` | Per-worker task execution, local resource inspection, backup/restore, health/storage reporting, reconciliation | Root systemd service with narrow capabilities; Podman rootless user `admiral-apps`; Quadlet files and user systemd units; authenticated HTTPS callbacks; local callback outbox |
| `admiralctl` | Operator CLI for API-backed control and diagnostics | Uses `admirald`; project architecture forbids direct central DB writes |
| `admiral-flagship` | Administrative web UI / BFF | Flask/Gunicorn on loopback, API client to `admirald`, session/CSRF/MFA controls in module |
| `admiral-harbor` | Customer portal and billing workflows; source also contains administrative/business-management views | Flask/Gunicorn on loopback, database and `admirald` client; asynchronous worker/timers; real PayPal payment verification remains a 1.0 item per project context |
| `admiral-common` RPM | Shared operator scripts, Ansible helpers, configuration baselines and package-owned directory tree | No Git submodule; root RPM spec owns fixed directory ownership/modes; Ansible is used for service configuration and node bootstrap |

`admiral-common` is not an additional application/control-plane service. The current source of truth for its package-owned directories is `packaging/rpm/admiral-common.spec`; the Fleet process creates dynamic instance paths below those package roots.

## Topology and control flow

### Single-Node

The installer installs control plane, Fleet, Harbor, Flagship, PostgreSQL, Caddy, Podman and systemd integration on one host. Workloads are still run under the rootless `admiral-apps` account. `admirald` is the source of truth; it publishes a durable Fleet task; Fleet executes local Podman/systemd actions and reports a callback; `admirald` updates operation and instance state and reconciles public routes through Caddy. The service units bind web/API processes to loopback where specified, and Caddy is the public TLS entry point.

### Multi-Node

The implementation and `docs/multi_node_setup_v1.md` describe a star topology: one admin/control-plane hub (the audited profile combines admin and portal roles) with one or more worker spokes. SSH/Ansible is the setup and maintenance channel. WireGuard is the private control/workload channel. Fleet obtains work from `admirald`, reports heartbeats and results, and uses the PostgreSQL-backed queue indirectly through the API. Workload ports are routed through the hub/Caddy to worker WireGuard addresses. Worker-to-worker coordination, multiple control-plane consensus, automatic failover, and multi-region operation are not implemented guarantees.

The documented hub-and-spoke design does not constitute a replicated control plane. Loss of the hub or its PostgreSQL database removes the central task and API authority. In the AlmaLinux three-VM probe, a suspended worker was marked offline after 145 seconds and became unavailable for provisioning; after VM resume it rejoined in 59 seconds. No automatic workload migration was observed or expected. This proves one whole-VM outage/rejoin path only; hub/database failure and network partitions remain untested.

## State, atomicity, and delivery

* Product state is persisted in PostgreSQL and schema changes use migrations. The durable queue is a separate PostgreSQL database. Queue claiming uses a transaction, `FOR UPDATE SKIP LOCKED`, a lease, node ownership, attempt counters and retry/dead-letter states.
* Task payloads are Ed25519-signed; AES-GCM payload encryption is optional and depends on production configuration. Fleet verifies signatures with a configured public key. Fleet API calls use a node bearer credential and HMAC for claim/callback bodies; HTTPS trust is configured through the installed CA.
* The task API has queue-level uniqueness on `task_public_id` and `idempotency_key`; the publisher currently uses the task ID as its idempotency key. This is not equivalent to client request deduplication. Retried operator requests must be tested separately.
* The domain database and queue database are separate transactional resources. They cannot share one PostgreSQL transaction. Node removal code has explicit queue cancellation/compensation helpers; other operation-publication paths must be tested for crash windows and orphan operations/tasks.
* Task delivery is lease-based and therefore at-least-once under worker/process failure. Fleet's in-memory replay set expires after a short window and is lost on restart. Deterministic resource names, setup markers, callback deduplication and reconciliation reduce duplicate effects, but they do not establish exactly-once execution.
* Operation status is advanced from callbacks. The callback handler verifies authenticated node identity and compares callback node/task IDs against the operation before applying state; duplicate callbacks for terminal operations are acknowledged without repeating the transition. Failure windows between queue completion, operation update, instance update, backup-record update and route activation still require injected-failure testing.

## Authentication, authorization, and isolation

* Operator API routes are protected by admin-token middleware; customer/API routes use Harbor-scoped or operator credentials; worker routes use node authentication and role checks. The listener is HTTPS in production and the default address is loopback.
* Admin and web sessions use a signing key; `admirald` can use an ephemeral session HMAC key when none is configured, which intentionally invalidates web sessions after restart. Production configuration should make this behavior explicit.
* Fleet is a root service because it must coordinate systemd and ownership, but the unit constrains Linux capabilities and filesystem access. Workloads run via a rootless Podman account; each instance has separate Podman networking and per-instance volumes/secrets. Quadlet rendering and real host namespace boundaries still require negative tests on guests.
* No complete workload isolation conclusion is drawn from unit tests or separate systemd unit names. Runtime samples on both AlmaLinux workers showed rootless Podman, non-privileged app containers, private PID namespaces, `no-new-privileges`, root-owned Quadlet files and active per-instance user units. Host path/socket and cross-workload access negatives remain untested.
* Secrets may enter API payloads, database state, Podman secrets, protected environment files, backup material, and web settings. Runtime Quadlets referenced Podman secrets without embedding their values; secret canary tests and access-boundary tests remain untested. No secret values are copied into this audit directory.

## External dependencies

Runtime and installation depend on systemd, Podman/Quadlet, PostgreSQL, Caddy, WireGuard, SELinux policy tooling, firewalld/nftables, RPM/DNF, Ansible, DNS/TLS certificate issuance, and optional SMTP/S3/PayPal services. Single-Node does not require a distributed coordination system. Multi-Node depends on working DNS/time synchronization, hub reachability, SSH bootstrap access, WireGuard, TLS identity/trust, and a central database. Loss of external SMTP, PayPal, or S3 can affect those respective workflows; they are not all required to start the core control plane.

The source contains no evidence of Redis as a runtime dependency in the production service graph; PostgreSQL and its durable queue are the documented runtime state stores. This finding is based on repository configuration and package dependencies, not a complete package-manager network capture yet.

## Documentation and implementation discrepancies

1. Root `README.md` describes Harbor as including an “Admin workspace for operators,” while the supplied project contract defines Harbor as a customer portal that does not administer or know infrastructure and assigns infrastructure administration to Flagship. The Harbor tree contains administrative route/template modules. The exact business-versus-infrastructure boundary needs documentation and authorization review; this is a contract/documentation risk, not yet a confirmed privilege defect.
2. Root `README.md` says the repository is functional beta under validation and not yet recommended for production. The user-supplied project context says Beta with Single-Node and Multi-Node E2E validated. The audit treats release readiness as unproven until its own required evidence is complete.
3. Existing project release guidance and this audit's user-directed distribution matrix have different scopes. This audit records the four requested distributions separately; a result from one distribution cannot stand in for another.
4. The networking contract routes public workload traffic through Caddy to a worker private address. Co-resident workloads can share a worker host and access host-published ports unless network and firewall controls prevent it; this must be experimentally checked rather than inferred from the diagram.

## Initial risk inventory

| Risk ID | Area | Initial risk | Evidence still required |
| --- | --- | --- | --- |
| AR-01 | Control-plane availability | Single control-plane/database authority is a single failure domain; no HA/consensus guarantee observed | Hub/database outage and restore test; operational recovery time and manual steps |
| AR-02 | Delivery semantics | Lease expiration and retries permit at-least-once execution | Kill Fleet between side effect and callback; inspect duplicate containers, volumes, backups and operation state |
| AR-03 | Cross-database consistency | Main DB and queue DB are distinct transactional resources | Stop `admirald` at publish/callback boundaries; verify repair/reconciliation |
| AR-04 | Cleanup reporting | Deprovision currently logs some systemd/Podman removal failures and continues; could report success with leftover resources | Real worker fault injection causing a Podman/systemd removal error; verify callback, queue, DB and leftover resources |
| AR-05 | Multi-Node reachability | Hub, WireGuard, DNS and TLS establish central control and routing | Three-guest partitions, latency, worker loss/rejoin, port scans and wrong-identity requests |
| AR-06 | Tenant isolation | Rootless Podman and per-instance namespaces are intended boundaries | Negative cross-instance process/network/storage/secret/socket/capability tests |
| AR-07 | Resource bounds | Tier-based limits and per-node capacity decisions must align with actual cgroups and storage | Inspect generated Quadlets/cgroups and stress memory/CPU/disk on guest |
| AR-08 | Web role boundary | Harbor includes admin routes in addition to customer portal workflows | Route-level auth/session/CSRF review and negative tests for customer/admin principals |
| AR-09 | External integrations | PayPal real payment validation is still an explicit 1.0 item | Outside this infrastructure audit unless a sandbox/integration is explicitly available |
| AR-10 | Go toolchain and dependency advisories | Historical Release 42 binaries used Go 1.26.7; exact R66 RPMs report Go 1.26.10 and `x/text v0.41.0`; all three R66 Go modules have zero reachable `govulncheck` findings, and a live CentOS worker received HTTP 401 over HTTP/2 | [`evidence/release66-go-security-verification.md`](evidence/release66-go-security-verification.md); historical #209 / ADM-F-003 is resolved upstream; broader Python/OS package triage remains incomplete |
| AR-11 | WireGuard peer boot persistence | Worker onboarding stores peer fragments and adds runtime peers, but the standard hub boot unit reads only the main configuration | Rocky hub power-cycle lost peers; see `evidence/rocky-multi-hub-reboot.md` and HIGH finding `ADM-F-005` |
| AR-12 | Stale task replay | Durable lease recovery can re-dispatch a task after its operation is terminal unless claim and callback paths settle stale queue rows | Release 45 Fedora reboot replay recreated Quadlets/resources after failed provision and successful deprovision. Release 46 Fedora Single-Node regression now confirms the task is cancelled and stays absent through reboot; HIGH finding `ADM-F-009` / #229 remains open for Multi-Node runtime evidence. |

## Source references

Key implementation references: `admirald/cmd/admirald/main.go`, `admirald/internal/config/config.go`, `admirald/internal/queue/queue.go`, `admirald/internal/api/api.go`, `admirald/internal/api/handlers_fleet.go`, `admirald/internal/database/operations.go`, `admiral-fleet/cmd/admiral-fleet/main.go`, `admiral-fleet/internal/agent/agent.go`, `admiral-fleet/internal/agent/outbox.go`, `admiral-fleet/internal/executor/executor_provision.go`, `admiral-fleet/internal/executor/executor_deprovision.go`, `admiral-fleet/internal/quadlet/renderer.go`, and `packaging/systemd/*.service`.
