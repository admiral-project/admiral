# Admiral installer security findings

Status: open findings from the July 2026 review of `scripts/install.sh`, the
Ansible roles, systemd units, and RPM specifications.

This document tracks product defects and hardening gaps. It intentionally does
not record host-specific configuration drift or any real credentials, node
identifiers, or public addresses.

## Supported behavior that must be preserved

`--single-node` is a supported, secure-by-default mode for development,
integration, and evaluation on one host. It is not the recommended production
topology, but fixes in this document must not break it. In particular, it must
continue to:

- install and run PostgreSQL, Caddy, Admirald, Fleet, Flagship, Harbor, and
  Cockpit;
- keep Admirald, Fleet HTTP, Flagship, Harbor, PostgreSQL, Cockpit, and the
  Caddy admin API off the public interface;
- register distinct local worker and portal nodes;
- use `ADMIRAL_SINGLE_NODE=true` only for the secure single-node mode;
- use PayPal sandbox rather than mock mode;
- provision and operate rootless Podman workloads; and
- support an idempotent second installation without rotating secrets or
  duplicating registrations.

`--dev-node` is a separate, deliberately insecure mode. It must remain clearly
identified, temporary, and unsuitable for production.

The supported production topologies are:

1. an admin and portal sharing one host, with separate workers; and
2. separate admin, portal, and worker hosts.

The normative production network contract for this review is:

| Host profile | Public ingress | Private ingress and inter-node traffic |
|---|---|---|
| Admin | SSH, UDP/51820, HTTP/HTTPS through Caddy | Admirald, Flagship, Cockpit, PostgreSQL, and the Caddy admin API are never reached through a public address |
| Dedicated portal | SSH and UDP/51820 only | Harbor is reached by admin Caddy through its WireGuard address; PostgreSQL remains local |
| Worker | SSH and UDP/51820 only | Fleet and workload upstream ports are reached by the admin through WireGuard |
| Single-node | SSH and HTTP/HTTPS through Caddy; WireGuard only when multinode expansion is enabled | All component traffic remains on loopback |

In a production multinode deployment, a missing or unreachable WireGuard
address must fail closed. Code must not silently fall back to a node's public or
general interface address.

## Severity definitions

- **Critical**: can expose cluster-wide secrets, destroy the source of truth,
  or defeat a primary trust boundary.
- **High**: breaks a supported secure topology or leaves an advertised
  security control ineffective.
- **Medium**: weakens defense in depth, idempotence, or release assurance.
- **Low**: primarily affects clarity, cleanup, or operator safety.

## Findings

### ADM-SEC-001 — Shared admin and portal installation can delete the secret inventory

- **Severity:** Critical
- **Affected modes:** `--admin-node` followed by `--portal-node` on the same
  host
- **Evidence:** `ansible/site.yml` detects that Portal shares the admin host,
  but `ansible/roles/admiral_common/tasks/main.yml` unconditionally removes
  `/etc/admiral/secrets` for every `portal-node` and `worker-node` run.
- **Current behavior:** A portal run targeting the existing admin host enters
  the non-admin cleanup path. With the current local SSH-user work it can then
  fail on an undefined variable after the secret file has already been
  removed.
- **Impact:** `/etc/admiral/secrets` is the documented recovery source for
  encryption keys, signing material, bootstrap credentials, and database
  credentials. Its removal can make the installation unrecoverable.
- **Recommendation:** Define an explicit effective host profile before roles
  execute. A portal sharing the admin host must retain admin-owned secrets, CA
  material, firewall policy, and services. Move destructive cleanup behind an
  assertion that the target is a dedicated spoke. Back up the secret inventory
  atomically before any role transition.
- **Acceptance criteria:**
  - Installing Portal onto an admin host preserves the inode contents, owner,
    mode, and checksum of `/etc/admiral/secrets`.
  - A forced failure at every later playbook stage also preserves the file.
  - Dedicated portal and worker nodes finish without a central secret
    inventory or CA private key.
  - Re-running both admin and portal reconciliation succeeds.

### ADM-SEC-002 — Shared admin and portal receives the wrong firewall and egress profile

- **Severity:** Critical
- **Affected modes:** shared `--admin-node` + `--portal-node`
- **Evidence:** `ansible/roles/admiral_firewall/tasks/main.yml` selects admin
  or spoke egress from `admiral_install_mode`. A shared portal still has the
  literal mode `portal-node`, so the role removes admin egress rules and
  installs the spoke rules. Public HTTP/HTTPS survives only when left behind by
  the earlier admin run.
- **Impact:** The shared admin can lose required DNS and HTTP/HTTPS egress,
  while its ingress policy depends on previous state instead of the declared
  topology. A fresh or partially reconciled host is unpredictable.
- **Recommendation:** Calculate one effective firewall profile (`admin`,
  `worker-spoke`, or `portal-spoke`) in pre-tasks and use it consistently.
  Declare the complete desired service and port set rather than relying on
  existing rules.
- **Acceptance criteria:**
  - A shared portal retains the admin ingress and egress policy.
  - A dedicated portal exposes only SSH and WireGuard publicly.
  - Starting from an empty, admin-configured, or intentionally polluted
    firewalld state converges to the same expected rules.

### ADM-SEC-003 — Non-root inter-node SSH flow is incomplete

- **Severity:** High
- **Affected modes:** `--worker-node`, `--portal-node`, and reinstallation of
  either spoke type
- **Evidence:** `admiral_ssh_admin_user` is generated inside the
  admin/single-node secrets block in
  `ansible/roles/admiral_common/tasks/main.yml`, but the subsequent user tasks
  run for all modes. `scripts/install.sh` passes only the public key to the
  spoke, defaults `--ssh-user` to root, and does not pass the cluster username.
  Post-play SSH commands read `/etc/wireguard/admiral.key` and
  `/etc/admiral/*.env` directly and run privileged diagnostics without
  `sudo`.
- **Current behavior:** A new spoke can fail because the username is undefined.
  Selecting the new non-root user for a later run also fails when post-play
  commands access root-only files.
- **Impact:** The change does not yet achieve non-root operation between
  nodes and can break both supported multinode topologies.
- **Recommendation:** Read the generated username safely from the controller's
  secret inventory, validate it, and pass it to the play. Separate the
  bootstrap transport user from the persistent operations user. Route every
  privileged remote operation through a small `sudo` wrapper and verify
  `sudo -n` before transmitting secrets. After validating a real login using
  the installed key, set `PermitRootLogin no`; subsequent runs should default
  to the persisted non-root user.
- **Acceptance criteria:**
  - Initial bootstrap may use root with a key, but ends with effective
    `PermitRootLogin no`.
  - The generated `opsa_*` account is identical across cluster nodes, has only
    the intended authorized keys, and supports `sudo -n`.
  - A complete second worker or portal installation succeeds using only that
    account.
  - Failure before the login verification leaves key-based root recovery
    available rather than locking out the operator.
  - `--single-node` remains functional and does not require remote SSH to
    itself.

### ADM-SEC-004 — Bootstrap host identity is trusted without independent verification

- **Severity:** Critical
- **Affected modes:** `--worker-node`, `--portal-node`
- **Evidence:** `scripts/install.sh` obtains a key using `ssh-keyscan`, appends
  it to `known_hosts`, and then uses `StrictHostKeyChecking=yes`. The
  independently obtained `--ssh-fingerprint` is optional and is checked only
  after the scanned key has been persisted.
- **Impact:** An attacker able to intercept the first connection can supply
  both the scanned and SSH host keys. Strict checking then confirms the
  attacker's unverified key while the installer transmits cluster material.
- **Recommendation:** Require either an operator-supplied fingerprint or an
  already trusted `known_hosts` entry. Verify the complete scanned key set in a
  temporary file before modifying persistent trust. Do not describe automatic
  `ssh-keyscan` as MITM protection.
- **Acceptance criteria:**
  - An unknown host without a fingerprint fails before any authenticated
    connection or secret transfer.
  - A mismatch leaves `known_hosts` unchanged.
  - Matching Ed25519, ECDSA, and RSA fingerprints are handled explicitly and
    tested.

### ADM-SEC-005 — Cluster secrets are exposed through the Ansible process command line

- **Severity:** High
- **Affected modes:** remote worker and portal bootstrap
- **Evidence:** `scripts/install.sh` places administrative tokens, encryption
  keys, database credentials, and Harbor credentials in a JSON string passed
  as `ansible-playbook --extra-vars "$EXTRA_VARS_JSON"`.
- **Impact:** Command-line arguments may be observable through process
  inspection, audit logs, diagnostics, or failure reports. The worker also
  receives variables needed only by controller-delegated tasks.
- **Recommendation:** Put only the minimum variables for each target in a
  root-owned `0600` temporary file or supported encrypted input mechanism.
  Use a cleanup trap for success, failure, and signals. Keep controller-only
  registration credentials out of remote host variables and mark every
  sensitive Ansible task `no_log: true`.
- **Acceptance criteria:**
  - No secret value appears in `ps`, `/proc/*/cmdline`, Ansible output, or the
    generated inventory.
  - Worker, dedicated portal, and shared portal receive distinct minimal
    variable sets.
  - Temporary material is removed after successful and interrupted runs.

### ADM-SEC-006 — Installer state is executed as shell code and arguments lack strict validation

- **Severity:** Critical
- **Affected modes:** all modes, especially a later spoke bootstrap
- **Evidence:** `scripts/install.sh` writes `--public-ip` into
  `/etc/admiral/install.env` and later loads that file with `source`. The same
  and other arguments are interpolated into temporary YAML and operational
  commands without a central validation layer.
- **Impact:** A crafted or corrupted state value can become root shell code on
  a later run. Invalid addresses, node IDs, usernames, fingerprints, or key
  paths can also create malformed inventory and unsafe partial installations.
- **Recommendation:** Store installer state as JSON or another non-executable
  format, parse exact keys, and write it atomically with mode `0600` or `0640`.
  Validate IP addresses with `ipaddress`, hostnames and node IDs against
  documented grammars, SSH usernames against system rules, and fingerprints
  against the OpenSSH format. Generate inventory using a serializer rather
  than a shell heredoc.
- **Acceptance criteria:**
  - Metacharacters, newlines, YAML tags, extra assignments, and malformed
    addresses are rejected before package or host changes.
  - Reading installer state never invokes a shell parser.
  - Missing option values produce an actionable installer error.

### ADM-SEC-007 — Harbor retains control-plane administrator credentials

- **Severity:** Critical
- **Affected modes:** `--single-node` and `--portal-node`
- **Evidence:** `ansible/roles/admiral_harbor/tasks/main.yml` writes both
  `ADMIRAL_ADMIN_TOKEN` and the scoped `ADMIRAL_HARBOR_API_TOKEN` into
  `harbor.env`.
- **Impact:** Compromise of the customer-facing portal can yield a platform
  administrator token, violating Harbor's product boundary and turning a
  portal compromise into control-plane compromise.
- **Recommendation:** Make Admirald's scoped Harbor credential sufficient for
  every supported portal operation and remove the administrator token from the
  Harbor environment. Keep administrator credentials only on the controller
  for controller-delegated bootstrap operations.
- **Acceptance criteria:**
  - Harbor starts and completes its supported workflows without an admin
    token.
  - The scoped token is rejected from unrelated admin, node, and
    infrastructure endpoints.
  - Single-node and both production topologies pass E2E tests with the same
    privilege boundary.

### ADM-SEC-008 — Portal reuses the central PostgreSQL credential

- **Severity:** Critical
- **Affected modes:** dedicated `--portal-node`
- **Evidence:** `scripts/install.sh` reads `ADMIRAL_POSTGRES_PASSWORD` from the
  admin secret inventory and passes it as the portal's local PostgreSQL
  password. The common role also allows role `admiral` from all of
  `10.99.0.0/24` to all databases on the admin database server.
- **Impact:** Compromise of the portal can disclose a credential valid against
  the central Admiral databases over WireGuard.
- **Recommendation:** Generate a portal-local database password on the portal
  and use a distinct PostgreSQL role. Do not expose the admin PostgreSQL server
  to the VPN unless a documented consumer requires it; if required, constrain
  source IP, role, database, and TLS verification.
- **Acceptance criteria:**
  - Portal and admin PostgreSQL roles have unrelated credentials.
  - A portal credential cannot authenticate to `admiral` or `admiral_queue`.
  - Default admin PostgreSQL listeners remain loopback-only.
  - Password rotation on one host does not affect the other.

### ADM-SEC-009 — Spoke egress policy can block the WireGuard handshake

- **Severity:** High
- **Affected modes:** `--worker-node`, dedicated `--portal-node`
- **Evidence:** The spoke egress policy in
  `ansible/roles/admiral_firewall/tasks/main.yml` permits established traffic,
  loopback, `10.99.0.0/24`, and outbound TCP/22 before rejecting the rest. The
  initial WireGuard peer handshake is outbound UDP/51820 to the hub's public
  address and is not covered.
- **Impact:** Installation can complete over an already-established SSH
  connection while the runtime VPN never establishes.
- **Recommendation:** Resolve and validate the hub endpoint before applying
  egress policy, then permit UDP/51820 only to those endpoint addresses. Verify
  a handshake and bidirectional API connectivity before declaring the spoke
  installed.
- **Acceptance criteria:**
  - `wg show` reports a recent handshake after bootstrap.
  - UDP/51820 is allowed only to the configured hub endpoint.
  - Failure to establish the VPN makes installation fail with a diagnostic
    that distinguishes DNS, firewall, key, and routing errors.

### ADM-SEC-010 — Egress restrictions are bypassable over IPv6

- **Severity:** High
- **Affected modes:** all secure modes on IPv6-capable hosts
- **Evidence:** Firewalld direct rules are created only for the IPv4 `filter`
  table. The nftables fallback matches `ip daddr` for the Admiral network but
  otherwise has no explicit, tested IPv6 policy equivalent to the documented
  per-role allowlist.
- **Impact:** A process denied an IPv4 destination may reach the same or a
  different destination over IPv6.
- **Recommendation:** Implement equivalent `inet`-family rules for both
  protocols, or explicitly disable IPv6 for Admiral-managed traffic when the
  deployment does not support it. Test DNS responses containing only AAAA
  records.
- **Acceptance criteria:**
  - The same allowed destinations and ports apply to IPv4 and IPv6.
  - Disallowed IPv6 connections are rejected in every secure mode.
  - WireGuard and package/update requirements remain functional.

### ADM-SEC-011 — Transition from dev-node does not fully restore the secure profile

- **Severity:** High
- **Affected modes:** `--dev-node` followed by `--single-node`
- **Evidence:** The Admirald role creates
  `admirald.service.d/dev-mode.conf` in development mode but has no production
  removal task. The firewall removal list does not include the development
  range `40000-49999/tcp` that dev mode adds.
- **Impact:** An operator can run the secure installer successfully while
  retaining a development environment and publicly reachable workload range.
- **Recommendation:** Give dev mode a persisted, explicit marker and define a
  complete inverse transition. Remove every development drop-in, port, service,
  insecure verification flag, and development bind before starting secure
  services.
- **Acceptance criteria:**
  - Dev-to-single produces the same effective units, environment, listeners,
    and firewall as a fresh single-node installation.
  - No development range or direct WSGI listener remains public.
  - The transition preserves application data, secrets, and node
    registrations.

### ADM-SEC-012 — Invalid fail2ban filters disable all jails and failure is ignored

- **Severity:** High
- **Affected modes:** all secure modes; web jails on admin, single, and portal
- **Evidence:** The custom filters in
  `ansible/roles/admiral_fail2ban/tasks/main.yml` match text but contain no
  `<HOST>` failure identifier required by fail2ban. The role catches any setup
  failure in `rescue`, prints a warning, and continues. Fail2ban is absent from
  the installer's required service list.
- **Impact:** SSH, Flagship, and Harbor brute-force protection can all be
  inactive after a nominally successful secure installation.
- **Recommendation:** Emit a stable, parseable client address in authentication
  failure logs, use filters with `<HOST>`, validate them with representative
  positive and negative samples, and run `fail2ban-client -t` before restart.
  Treat a failed service as an installation failure in secure modes.
- **Acceptance criteria:**
  - Configuration validation and service startup are blocking checks.
  - Each enabled jail detects a real failed login containing a client address.
  - A successful login, attacker-controlled username, or unrelated message
    does not match.
  - Proxy-derived addresses are trusted only when the request came through the
    expected local proxy.

### ADM-SEC-013 — Rendered service configuration does not reliably reach the running process

- **Severity:** High
- **Affected modes:** all; confirmed risk in Fleet and Flagship
- **Evidence:** The Fleet and Flagship roles render environment files and then
  request `state: started`, which does not restart an already-running service.
  Harbor restarts only when its systemd override changes, not necessarily when
  `harbor.env` changes.
- **Impact:** A corrected loopback bind, token, CA path, or security flag may
  exist on disk while the process continues with its previous environment.
- **Recommendation:** Register every rendered configuration task and restart
  the owning service through handlers whenever effective input changes. Keep
  restarts idempotent and order them after validation.
- **Acceptance criteria:**
  - Changing each environment or unit file updates `/proc/<pid>/environ` and
    listeners during the same play.
  - An unchanged second run does not restart services.
  - Single-node registration and workloads survive required service restarts.

### ADM-SEC-014 — Security validation is partly warning-only and incomplete

- **Severity:** High
- **Affected modes:** all secure modes
- **Evidence:** `scripts/install.sh` records SELinux, sshd, and firewall
  deviations as non-blocking warnings. The required service list omits
  fail2ban, auditd, firewalld, and WireGuard. Firewall assertions reject
  unexpected entries but do not consistently assert that all required entries
  are present.
- **Impact:** The command can print “installation completed” when controls that
  support the secure-by-default claim are missing or failed.
- **Recommendation:** Define per-mode security invariants and divide them into
  blocking requirements and explicitly optional recommendations. Validate
  effective state, not only files. Print a machine-readable final report and
  return nonzero when a blocking invariant fails.
- **Acceptance criteria:**
  - Each secure mode verifies SELinux, sshd, firewalld/nftables, WireGuard where
    required, auditd, fail2ban, service users, listeners, and file modes.
  - Required services and ports must be both present and exclusive.
  - Dev mode is prominently reported as insecure but does not masquerade as
    `single-node` in the final summary.

### ADM-SEC-015 — RPM builds can succeed with failed or skipped tests

- **Severity:** High
- **Affected components:** Admirald, Fleet, Flagship, and Harbor RPMs
- **Evidence:** The Go `%check` sections append `|| echo` to `go test ./...`.
  Python specs similarly suppress pytest errors and do not consistently declare
  the test runner as a build dependency.
- **Impact:** COPR can publish an RPM after a test regression, including a
  security or installation regression.
- **Recommendation:** Declare all test build requirements and let `%check`
  failures fail the RPM build. If a test cannot run in COPR, separate it by an
  explicit condition with documented justification rather than catching every
  error.
- **Acceptance criteria:**
  - A deliberately failing Go or Python test fails the RPM build.
  - Missing pytest or another required test dependency fails during dependency
    resolution.
  - Architecture-specific exclusions are explicit for both x86_64 and aarch64.

### ADM-SEC-016 — RPM source commits can publish an internally inconsistent release

- **Severity:** High
- **Affected components:** all coordinated Admiral RPMs
- **Evidence:** Each spec pins an independent superproject commit. The current
  `admiral-common` commit predates the local SSH changes, while component specs
  reference other revisions. The installed playbook can therefore differ from
  the repository and documentation used to assess it.
- **Impact:** A release may combine an installer, service binary, unit, and
  documentation that were never tested together. Security fixes present in Git
  may be absent from the published installer.
- **Recommendation:** Generate or validate all spec commit references from one
  release manifest. Require coordinated version/release metadata and run the
  installation matrix against the exact built RPM repository.
- **Acceptance criteria:**
  - CI rejects mismatched release commits or versions.
  - The source commit and checksums of installed playbooks are traceable from a
    release manifest.
  - Promotion requires E2E results for the exact RPM artifacts on EL10 x86_64
    and aarch64.

### ADM-SEC-017 — Network services rely unnecessarily on the firewall as their only boundary

- **Severity:** Medium
- **Affected modes:** primarily `--admin-node`; single-node when a public IP is
  explicitly supplied
- **Evidence:** The Admirald role selects `0.0.0.0` whenever a non-loopback
  public address is supplied. WireGuard is assigned to the fully trusted
  firewalld zone, which permits every service bound to that interface.
- **Impact:** A firewall error or overly trusted VPN peer exposes more host
  services than required.
- **Recommendation:** Bind Admirald to loopback plus the explicit WireGuard
  address where supported, and define role-specific WireGuard ingress rather
  than trusting the complete interface. Keep single-node services on loopback.
- **Acceptance criteria:**
  - Public interfaces have no internal Admiral listeners even if their
    firewalld rules are temporarily removed in a test environment.
  - VPN peers can reach only the ports required by their role and direction.
  - Single-node listener expectations remain unchanged.

### ADM-SEC-018 — WireGuard is opened in modes that do not require a peer

- **Severity:** Medium
- **Affected modes:** standalone `--single-node`, potentially development
- **Evidence:** The firewall role opens UDP/51820 in every mode and the common
  play configures WireGuard for single-node even though local component traffic
  uses loopback.
- **Impact:** It creates unnecessary public attack surface and makes the
  documented exposure contract broader than required for a standalone host.
- **Recommendation:** Open WireGuard only when multinode enrollment is enabled,
  or document and persist an explicit “accept future spokes” setting. Do not
  remove the local single-node registration behavior that depends on loopback.
- **Acceptance criteria:**
  - A standalone single-node host has no public UDP/51820 unless the operator
    enables multinode expansion.
  - Enabling expansion is explicit, idempotent, and does not reinstall or break
    the local worker and portal.

### ADM-SEC-019 — Mode transitions and role exclusivity are order-dependent

- **Severity:** High
- **Affected modes:** shared admin+portal and repeated installation
- **Evidence:** `scripts/install.sh` rejects `--admin-node` when Harbor is
  already active, but the supported shared topology is constructed in the
  opposite order by applying `--portal-node` to an admin host. Role checks use
  currently active services rather than persisted topology.
- **Impact:** The same intended topology is accepted or rejected depending on
  installation order, and an admin reconciliation can become impossible after
  adding Portal.
- **Recommendation:** Persist a declarative host profile and validate allowed
  role combinations against it. Permit admin+portal, forbid worker+portal on
  remote hosts, and reserve the combined admin+worker+portal profile for
  single-node.
- **Acceptance criteria:**
  - Allowed topologies converge regardless of safe installation order.
  - Re-running any constituent role is idempotent.
  - Forbidden combinations fail before packages, secrets, firewall, or
    services are changed.

### ADM-SEC-020 — Documentation overstates guarantees of the current artifacts

- **Severity:** Medium
- **Affected documentation:** installation and sysadmin guides
- **Evidence:** The guide says the installer creates one `opsa_*` user across
  all nodes and that automatic host-key handling prevents MITM, although the
  spoke variable flow is incomplete and the fingerprint is optional. It also
  does not clearly document construction and reconciliation of the shared
  admin+portal topology.
- **Impact:** Operators can believe an unverified or untested control is active
  and can choose an installation sequence that risks the secret inventory.
- **Recommendation:** Update documentation only after the corresponding E2E
  behavior passes. Distinguish initial bootstrap, routine operation,
  break-glass recovery, single-node, dev-node, and both production topologies.
- **Acceptance criteria:**
  - Every security claim links to a blocking verification or test.
  - Examples use the non-root user after bootstrap and require host identity
    verification.
  - The shared and dedicated portal procedures are explicit and repeatable.

### ADM-SEC-021 — Fleet ignores its configured bind address and rejects VPN clients

- **Severity:** High
- **Affected modes:** `--worker-node`; single-node listener isolation
- **Evidence:** `admiral-fleet/internal/agent/http.go` parses only the port from
  `ADMIRAL_FLEET_HTTP_ADDR`, constructs an empty-host bind, and therefore
  listens on all interfaces. Its `ipAllowed` function accepts only loopback.
  Meanwhile, Admirald's worker readiness check expects to reach port 9099 on a
  remote node.
- **Impact:** The socket is broader than the configured secure bind, but a
  legitimate admin request arriving through WireGuard receives `403`. Public
  blocking depends entirely on firewalld and remote readiness cannot operate as
  designed.
- **Recommendation:** Honor the complete configured address. In worker mode,
  bind Fleet to the node's WireGuard address and authorize only the registered
  admin WireGuard address. In single-node, bind and authorize loopback only.
  Authentication should still be required for any endpoint that exposes more
  than a minimal liveness signal.
- **Acceptance criteria:**
  - Worker Fleet listens on `<worker-wg-ip>:9099`, never `0.0.0.0`, `[::]`, or
    the public address.
  - Only the admin WireGuard address can call worker readiness endpoints.
  - Single-node listens on `127.0.0.1:9099` and remains functional.
  - Listener and authorization tests cover IPv4 and IPv6 representations.

### ADM-SEC-022 — Control-plane routing and health checks prefer non-VPN addresses

- **Severity:** High
- **Affected modes:** dedicated worker and portal topologies
- **Evidence:** `admirald/internal/api/handlers_nodes.go` chooses `PublicIP`,
  then `IP`, then `WireguardIP` for readiness. Portal discovery in
  `admirald/internal/api/api.go` uses the same public-first candidate pattern.
  `admirald/internal/networking/manager.go` initially creates instance routes
  with `node.IP` and falls back to it when a WireGuard address is absent.
- **Impact:** Control-plane probes and Caddy routes can attempt public or
  general-interface paths, contradicting the VPN-only contract. Firewalld may
  hide the mistake by making the service merely appear unavailable.
- **Recommendation:** Centralize role-aware address selection. Multinode
  runtime traffic must require `WireguardIP`; do not try public fallbacks.
  Loopback is allowed only for the explicit single-node/shared-local cases.
  Keep public IP solely as bootstrap metadata for SSH and the WireGuard
  endpoint.
- **Acceptance criteria:**
  - No production route, readiness probe, heartbeat URL, callback, or portal
    target uses `PublicIP` or `node.IP`.
  - Missing WireGuard metadata produces an actionable fail-closed error.
  - Packet capture tests show application traffic only on `lo` or
    `wg-admiral`, never on the public interface.

### ADM-SEC-023 — Workload ports bind all host interfaces

- **Severity:** High
- **Affected modes:** `--worker-node` and `--single-node`
- **Evidence:** `admiral-fleet/internal/quadlet/renderer.go` renders
  `PublishPort=<host-port>:<container-port>` without a host address. Podman
  consequently publishes on every host interface. Secure modes rely on the
  public firewall not exposing the allocated `40000-49999` range.
- **Impact:** A firewalld failure, alternate zone, container-network rule, or
  operator mistake exposes customer workloads directly and bypasses central
  Caddy TLS and routing.
- **Recommendation:** Add a validated publish address to Fleet configuration
  and the Quadlet renderer. Use the worker WireGuard address in multinode and
  loopback in single-node. Dev-node may deliberately use all interfaces but
  must do so through an explicit value.
- **Acceptance criteria:**
  - Generated worker Quadlets contain
    `PublishPort=<worker-wg-ip>:<host-port>:<container-port>`.
  - Single-node Quadlets publish on loopback and remain reachable by local
    Caddy.
  - Removing the public firewall rule in an isolated negative test still does
    not make a workload reachable through the public address.

### ADM-SEC-024 — Caddy disables TLS verification for private HTTPS upstreams

- **Severity:** High
- **Affected modes:** portal routing and other HTTPS upstream routes
- **Evidence:** `admirald/internal/networking/caddy.go` sets
  `insecure_skip_verify: true` for every HTTPS reverse-proxy target. Portal
  readiness also constructs a TLS client with `InsecureSkipVerify`.
- **Impact:** HTTPS encrypts traffic but does not authenticate the upstream.
  A compromised VPN peer or routing error can impersonate Portal, and the
  behavior undermines the internal CA already provisioned by Admiral.
- **Recommendation:** Configure Caddy and Go health clients with Admiral's CA
  certificate and verify a SAN matching the target WireGuard address or stable
  internal node name. Reserve insecure verification exclusively for dev-node.
- **Acceptance criteria:**
  - Valid CA-signed portal certificates succeed through WireGuard.
  - An unknown CA, wrong SAN, expired certificate, or substituted VPN peer is
    rejected.
  - No production Caddy JSON or Go TLS configuration contains insecure skip
    verification.

### ADM-SEC-025 — The trusted WireGuard zone permits unnecessary lateral access

- **Severity:** Medium
- **Affected modes:** all multinode topologies
- **Evidence:** `ansible/roles/admiral_wireguard/tasks/main.yml` places
  `wg-admiral` in firewalld's fully trusted zone. Spokes route the entire
  `10.99.0.0/24` through the hub and the hub enables IP forwarding.
- **Impact:** A compromised worker can attempt connections to other workers,
  Portal, and every service listening on the admin VPN address. Application
  authentication remains useful, but the network does not enforce Admiral's
  star-shaped least-privilege paths.
- **Recommendation:** Replace the trusted zone with an Admiral-specific zone
  and explicit source/destination policies. Permit worker-to-admin Fleet API
  traffic, admin-to-worker readiness/workload traffic, and admin-to-portal
  traffic. Deny worker-to-worker and worker-to-portal traffic unless a future
  documented feature requires it.
- **Acceptance criteria:**
  - Each required path has an explicit port and direction test.
  - Unrelated peer-to-peer connections fail even with a listening service.
  - Public ingress remains exactly SSH plus WireGuard on spokes and SSH,
    WireGuard, HTTP, and HTTPS on admin.

### ADM-SEC-026 — HTTPS setup gives Caddy ownership of Certbot private material

- **Severity:** High
- **Affected modes:** admin and single-node after `admiral_https_setup`
- **Evidence:** `_ensure_caddy_can_read_letsencrypt_paths` in
  `scripts/admiral_https_setup.py` changes ownership of Let's Encrypt live and
  archive directories, the resolved certificate, and `privkey.pem` to the
  `caddy` user and group. It also changes directory modes throughout that
  subtree.
- **Impact:** A compromised Caddy process can modify certificate material and
  Certbot-managed paths instead of having read-only access. Ownership changes
  can also interfere with renewal assumptions and affect certificates not
  intended to be managed by Admiral.
- **Recommendation:** Keep Certbot state and private keys owned by root. Grant
  Caddy the minimum read/traverse access using a dedicated group or ACL, or
  atomically deploy root-owned copies into an Admiral-specific directory with
  `root:caddy`, directory mode `0750`, and key mode `0640`. Limit changes to the
  selected certificate and never recursively take ownership of Certbot state.
- **Acceptance criteria:**
  - Caddy can read the active certificate and key but cannot replace, truncate,
    rename, or delete them.
  - Certbot renewal succeeds and an atomic deploy hook refreshes Caddy without
    a window containing partial files.
  - Unrelated `/etc/letsencrypt` certificates and directories are unchanged.

### ADM-SEC-027 — HTTPS configuration is not validated or applied transactionally

- **Severity:** Medium
- **Affected modes:** admin and single-node public HTTPS setup
- **Evidence:** `scripts/admiral_https_setup.py` writes a systemd override
  directly, then sequentially restarts Cockpit, Caddy, and Admirald. It does not
  validate the final systemd environment, Caddy configuration, certificate/key
  pair, target URLs, or service health before reporting completion. Its summary
  also claims Admirald remains on loopback even though admin-node configuration
  can bind it to all interfaces.
- **Impact:** An invalid target, certificate, or partial restart can leave the
  public edge unavailable or produce a misleading security summary.
- **Recommendation:** Validate the certificate/key match, certificate names,
  target scheme/host policy, rendered systemd unit, and Caddy JSON before an
  atomic replacement. Preserve the previous override and roll it back if any
  service or HTTPS health check fails. Report effective listeners rather than a
  hard-coded claim.
- **Acceptance criteria:**
  - Invalid inputs fail before changing active configuration.
  - Any failed restart or route health check restores the previous working
    configuration.
  - The final report is derived from effective systemd, socket, firewall, and
    route state.

## Required validation matrix

Closing the findings above requires tests against the exact RPM artifacts, not
only source-tree services.

| Scenario | Required assertions |
|---|---|
| Fresh secure single-node | All components active; internal listeners on loopback; worker and portal registered; PayPal sandbox; security invariants pass |
| Repeated secure single-node | No secret rotation, duplicate nodes, stale environment, unnecessary restart, or workload loss |
| Dev-node | Insecure exposure is explicit and limited to the documented temporary profile |
| Dev-to-single transition | Effective state equals a fresh secure single-node without losing data or registrations |
| Admin plus worker | Verified SSH bootstrap, non-root second run, WireGuard handshake, scoped credentials, no public internal ports |
| Admin plus dedicated portal plus worker | Separate portal database credential, portal reachable through central Caddy over WireGuard, no admin token in Harbor |
| Shared admin plus portal and separate worker | Secret inventory retained, admin firewall retained, repeated admin and portal reconciliation succeeds |
| Interrupted bootstrap | No leaked temporary secrets, no premature root lockout, and an actionable recovery path |
| IPv4 and IPv6 negative tests | Disallowed ingress and egress fail identically |
| VPN-only routing | Packet capture confirms that all inter-node application traffic uses `wg-admiral`; public addresses are used only for SSH bootstrap and WireGuard transport |
| Public exposure contract | Portal/worker expose only SSH and UDP/51820; admin exposes only SSH, UDP/51820, HTTP, and HTTPS |
| RPM build failure injection | Any failed required test prevents publication |
| HTTPS setup and renewal | Root retains certificate ownership; Caddy has read-only access; failed configuration rolls back; renewal keeps routes available |

Tests should run on Tier 1 EL10 for x86_64 and aarch64. Fedora dev-node tests
may be supplementary, but cannot replace the EL10 acceptance gate.

## Recommended remediation order

1. Protect shared-host secrets and fix effective topology/profile selection
   (ADM-SEC-001, 002, 019).
2. Complete and test non-root bootstrap and host identity verification
   (ADM-SEC-003, 004, 006).
3. Remove overprivileged and exposed credentials (ADM-SEC-005, 007, 008).
4. Repair WireGuard and dual-stack firewall behavior (ADM-SEC-009, 010, 017,
   018, 021, 022, 023, 024, 025).
5. Make secure mode transitions and service reconciliation deterministic
   (ADM-SEC-011, 013, 014).
6. Repair fail2ban and make release tests authoritative (ADM-SEC-012, 015,
   016).
7. Update operator documentation only after the artifact-level matrix passes
   (ADM-SEC-020, 026, 027).
