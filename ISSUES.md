# Admiral installer security findings

Status: open findings from the July 2026 review. Each finding now has a
corresponding GitHub issue in the correct component repository.
Updated 2026-07-15.

## GitHub reconciliation (2026-07-15)

The referenced repositories were checked with `gh issue list --state open`.
There are 86 documented tickets still open. ADM-SEC-007 has a code remediation
on `main` but remains open pending acceptance validation and GitHub closure.
The following documented issues
are closed on GitHub; their evidence remains below for auditability and each
is marked accordingly: ADM-SEC-003 through ADM-SEC-006, ADM-SEC-011,
ADM-SEC-013, ADM-SEC-020, ADM-SEC-051, ADM-SEC-052, ADM-SEC-071 through
ADM-SEC-073, ADM-QUAL-020, and ADM-QUAL-021.

The open dependency-maintenance issues below are outside the July review and
do not yet have an entry in this document:

- `admiral-fleet#1`, `admiralctl#1`, and `admirald#1`: Go toolchain update.
- `admiral-harbor#1` and `admiral-flagship#1`: Flask version pin.
- `admiral-harbor#12` and `admiral-flagship#7`: Werkzeug version pin.

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


## Installer setup findings addressed in this change

The findings directly related to initial setup through `scripts/install.sh`,
the Ansible playbooks, the Makefile, and packaging support are ADM-SEC-003,
ADM-SEC-004, ADM-SEC-005, ADM-SEC-006, ADM-SEC-011, ADM-SEC-013,
ADM-SEC-051, ADM-SEC-052, ADM-SEC-072, and ADM-SEC-073. The supported targets remain
`--admin-node`, `--portal-node`, `--worker-node`, and `--admin-portal-node`,
while preserving the co-located
`--single-node` and explicitly insecure `--dev-node` setups.

Applied hardening approach:

- keep bootstrap and persistent SSH identities separate by allowing root only
  for first contact, then verifying the persisted `opsa_*` account and
  passwordless sudo before installing the root-login lockdown;
- require an operator-provided SSH host key fingerprint before first spoke
  connection and trust only the scanned key that matches that fingerprint;
- pass Ansible variables through a root-only temporary JSON file instead of the
  process command line, exclude the controller admin token from spoke variables,
  and use cleanup traps for normal and interrupted runs;
- validate option values before assignment, revalidate spoke IDs and WireGuard
  addresses resolved from `know_host.yaml`, keep installer state as JSON, and
  generate remote inventory with a JSON serializer instead of a shell heredoc;
- make audit rule fallback and verification blocking, flush service handlers
  before dependent bootstrap commands, use at least PostgreSQL `sslmode=prefer`
  for Harbor, and verify downloaded third-party source tarballs by SHA256.

## Severity definitions

- **Critical**: can expose cluster-wide secrets, destroy the source of truth,
  or defeat a primary trust boundary.
- **High**: breaks a supported secure topology or leaves an advertised
  security control ineffective.
- **Medium**: weakens defense in depth, idempotence, or release assurance.
- **Low**: primarily affects clarity, cleanup, or operator safety.

## Resolved findings

### ADM-SEC-028 — Root login permitted with password authentication

- **Severity:** Critical
- **Affected modes:** all modes
- **Evidence:** SSH hardening baseline (`50-admiral-hardening.conf`) did not
  set `PermitRootLogin`. Default sshd behavior allowed password-based root
  login.
- **Resolution:** Added `PermitRootLogin prohibit-password` to the SSH
  hardening baseline in `ansible/roles/admiral_common/tasks/main.yml`.
  The security checklist in `scripts/install.sh` now verifies this setting.
- **Resolved in:** `eb62851` (2026-07-14)

### ADM-SEC-029 — No non-root SSH admin user created during installation

- **Severity:** High
- **Affected modes:** all modes
- **Evidence:** The installer created no system user for SSH access. Operators
  had to rely on root or manually created users.
- **Resolution:** The installer now creates a non-root SSH admin user
  (`opsa_<random>`) with wheel group membership and NOPASSWD sudo on every
  node. The username is stored in `/etc/admiral/secrets` as `ADMIRAL_SSH_USER`
  and is consistent across cluster nodes. SSH public key is auto-detected or
  extracted from `--ssh-key` and deployed via `authorized_key` module.
- **Resolved in:** `8845c78`, `fcf31a3`, `bac509d` (2026-07-14)

### ADM-SEC-001 — Shared admin and portal installation can delete the secret inventory

- **Severity:** Critical
- **Resolution:** Replaced service-based shared-host detection with an explicit,
  persistent `admin-portal` host profile. The supported shared topology now
  starts with `--admin-portal-node`; it retains admin-owned secrets, CA
  material, services, and the admin security profile. Dedicated `portal-node`
  and `worker-node` runs remain the only profiles that remove the central
  secret inventory. The unsupported historical `--admin-node` followed by
  `--portal-node` transition is rejected before the play changes host state.
- **Resolved in:** `daf5b64` (2026-07-14)

### ADM-SEC-002 — Shared admin and portal receives the wrong firewall and egress profile

- **Severity:** Critical
- **Resolution:** The explicit `admin-portal` profile uses the admin ingress
  and egress policy. Firewall reconciliation now derives the complete allowed
  public service and port set from the effective profile, removes every other
  permanent public rule, and then applies the declared rules. This converges
  clean, previously configured, and polluted firewalld states.
- **Resolved in:** `daf5b64`, `8c0e185` (2026-07-14)

## Findings

### ADM-SEC-003 — Non-root inter-node SSH flow is incomplete

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/32

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

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/33

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

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/34

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

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/35

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

- **GitHub status:** Open; the reported token exposure is remediated in
  `2af08c7`. The installer contract test passes, but E2E acceptance validation
  and issue closure remain pending.

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/36

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/37

- **Severity:** Critical
- **Affected modes:** dedicated `--portal-node`
- **Evidence:** `scripts/install.sh` reads `ADMIRAL_POSTGRES_PASSWORD` from the
  admin secret inventory and passes it as the portal's local PostgreSQL
  password. Specifically, the installer decides whether the portal shares the
  admin host by testing local `caddy` and `admirald` services. Remote spoke
  installation is launched from that admin host, so the test is normally true
  even when Ansible targets a dedicated portal. The common role also allows
  role `admiral` from all of
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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/38

- **Severity:** High
- **Affected modes:** `--worker-node`, dedicated `--portal-node`
- **Evidence:** The spoke egress policy in
  `ansible/roles/admiral_firewall/tasks/main.yml` permits established traffic,
  loopback, `10.99.0.0/24`, outbound TCP/22, and UDP/51820 before rejecting the
  rest. Although the current nftables template permits the WireGuard transport
  port, it does not permit DNS. `--admin-endpoint` accepts a hostname and the
  generated WireGuard configuration uses that value as its endpoint, so the
  initial handshake cannot resolve the hub after the firewall role is applied.
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

### ADM-SEC-049 — Spoke egress policy blocks required product traffic

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/53

- **Severity:** High
- **Affected modes:** `--worker-node`, dedicated `--portal-node`
- **Evidence:** `ansible/roles/admiral_firewall/templates/admiral-egress.nft.j2`
  permits spokes only loopback, established traffic, `10.99.0.0/24`, TCP/22,
  and UDP/51820, then rejects all other output.
- **Impact:** Workers cannot reliably resolve registries or pull OCI images over
  HTTPS. Harbor cannot contact PayPal, external SMTP/API email providers, or
  other documented Internet services. A successful installation can therefore
  leave the advertised workload and billing flows unusable.
- **Recommendation:** Define explicit per-role outbound requirements. Permit DNS
  only to configured resolvers and HTTPS only where the worker/portal contract
  requires it; add narrowly scoped SMTP or provider API rules for configured
  notification delivery. Keep the final default deny.
- **Acceptance criteria:**
  - A worker can resolve and pull an allowed image while disallowed egress is
    rejected.
  - A portal can reach the configured PayPal and notification endpoints.
  - Required destinations and ports are configurable and documented.
  - Negative egress tests cover IPv4 and IPv6.

### ADM-SEC-050 — WireGuard peer exchange playbook operates on the wrong hosts

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/54

- **Severity:** High
- **Affected modes:** multinode deployments using
  `ansible/wireguard-peers.yml`
- **Evidence:** The task named `Write spoke peer config to hub` runs on
  `workers:portal` without `delegate_to`, so it writes `peers.d` files on each
  spoke. The subsequent `query('fileglob', ...)` enumerates the Ansible
  controller filesystem rather than the hub. Both private-key reads use
  `lookup('file', '/etc/wireguard/admiral.key')`, which also reads the controller
  rather than the host being configured.
- **Impact:** The hub may receive no peer configuration, deployments can fail
  depending on the controller filesystem, and the wrong private key can be
  installed on a node. Reusing a private key across nodes also destroys their
  WireGuard identity separation.
- **Recommendation:** Delegate hub writes explicitly, enumerate remote peer
  files with `find`, and read each node's private key on that node using
  `slurp` with `no_log: true`. Prefer deriving and distributing public keys
  without returning private keys to the controller.
- **Acceptance criteria:**
  - Peer fragments exist only on the hub.
  - Every node retains a unique private key and the controller needs no local
    `/etc/wireguard/admiral.key`.
  - A clean external controller can run the playbook successfully.
  - Re-running the playbook is idempotent and produces a working handshake for
    every declared spoke.

### ADM-SEC-051 — Audit rule fallback is unreachable

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/55

- **Severity:** Medium
- **Affected modes:** all modes when `augenrules --load` fails
- **Evidence:** `ansible/roles/admiral_auditd/tasks/main.yml` registers the
  `augenrules` result with `failed_when: false`, then guards the `auditctl`
  fallback with `when: audit_augenrules is failed`. Ansible deliberately marks
  the first task successful regardless of its return code, so the fallback is
  never selected.
- **Impact:** Installation can report success while Admiral's audit watches are
  not loaded, leaving a documented security control ineffective until reboot or
  manual intervention.
- **Recommendation:** Run the fallback when `audit_augenrules.rc != 0` and fail
  installation if both loaders fail. Verify the effective rules after loading.
- **Acceptance criteria:**
  - A forced `augenrules` failure invokes `auditctl -R`.
  - Failure of both mechanisms stops installation with an actionable error.
  - Successful installation verifies the expected Admiral audit keys.

### ADM-SEC-052 — Installer options do not validate that a value follows

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/56

- **Severity:** Low
- **Affected modes:** all command-line modes
- **Evidence:** Options such as `--node-id`, `--public-ip`, `--wireguard-ip`,
  `--admin-endpoint`, `--ssh-user`, `--ssh-key`, and `--ssh-fingerprint` call
  `shift` and immediately read `$1`. With `set -u`, an option at the end of the
  command terminates with Bash's `unbound variable` error.
- **Impact:** Operators receive an internal shell error rather than a clear
  usage diagnostic, complicating automation and troubleshooting.
- **Recommendation:** Validate `[[ $# -ge 2 ]]` for every value-bearing option,
  preferably through one parsing helper that reports the option name.
- **Acceptance criteria:**
  - Every missing value exits nonzero with `Option <name> requires a value` and
    no package or host changes.
  - Parser tests cover every option, unknown options, empty strings, and normal
    invocations.

### ADM-SEC-010 — Egress restrictions are bypassable over IPv6

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/39

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

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/40

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/41

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

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/42

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/43

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/44

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/45

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/46

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/47

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/48

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

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/49

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

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/41

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

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/22

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

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/42

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

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/23

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/50

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/51

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

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/52

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

### ADM-SEC-030 — InsecureSkipVerify hardcoded in Go TLS clients

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/24

- **Severity:** Medium
- **Affected modes:** all modes using HTTPS internal connections
- **Evidence:** `InsecureSkipVerify: true` appears in:
  - `admirald/internal/api/api.go:303`
  - `admirald/internal/api/handlers_nodes.go:531`
- **Impact:** TLS certificate verification is bypassed for outbound
  connections. A MITM attacker on the WireGuard network could intercept
  internal traffic between admirald and portal/harbor.
- **Recommendation:** Configure Go TLS clients with Admiral's CA certificate
  (`/etc/admiral/tls/ca.pem`). Reserve `InsecureSkipVerify` for dev-node
  only. Add a production-mode guard in Go code.
- **Acceptance criteria:**
  - Production Go TLS clients verify against Admiral CA.
  - dev-node retains insecure skip verify for local self-signed certs.
  - No `InsecureSkipVerify` in production code paths.

### ADM-SEC-031 — panic() in secrets manager on HKDF failure

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/25

- **Severity:** Medium
- **Affected modes:** all modes
- **Evidence:** `admirald/internal/secrets/secrets.go:36` calls `panic()`
  when HKDF key derivation fails.
- **Impact:** A panic in a library function crashes the entire process
  without graceful error handling.
- **Recommendation:** Propagate the error instead of panicking. Return
  `fmt.Errorf("derive key: %w", err)` to the caller.
- **Acceptance criteria:**
  - HKDF failure returns an error, not a panic.
  - Caller handles the error gracefully.
  - No `panic()` calls remain in library code.

### ADM-SEC-032 — Session HMAC key is ephemeral and lost on restart

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/26

- **Severity:** Medium
- **Affected modes:** all modes
- **Evidence:** `admirald/internal/api/api.go:49-53` generates a random
  HMAC key at startup. Logs warning: "Using volatile ephemeral session
  HMAC key. Admin sessions will not survive a restart."
- **Impact:** All admin sessions are invalidated when admirald restarts.
  Operators must re-login after any service restart.
- **Recommendation:** Generate a persistent HMAC key during installation
  and store it in `/etc/admiral/secrets` as `ADMIRAL_SESSION_HMAC_KEY`.
  Load from config at startup.
- **Acceptance criteria:**
  - Sessions survive admirald restart.
  - HMAC key is persisted and loaded from config.
  - Missing key triggers a warning, not a failure.

## Source-code findings (component review, 2026-07-14)

These findings cover the runtime component source (`admirald`, `admiral-fleet`,
`admiralctl`, `admiral-flagship`, `admiral-harbor`), as opposed to the installer
and packaging findings above. They follow the same severity definitions. Code
IDs continue the ADM-SEC sequence; quality-only findings use ADM-QUAL.

### ADM-SEC-033 — Harbor instance actions are not scoped to the calling customer (IDOR)

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/27

- **Severity:** Critical
- **Affected components:** `admiral-harbor` → `admirald` API
- **Evidence:** `admirald/internal/api/handlers_instances.go:14-52`
  (`HandleCustomerAppAction`, POST `/api/v1/customer-apps/action`, behind
  `HarborAuthMiddleware`). The handler validates `req.InstanceID` and `req.Action`
  but performs **no customer-scoping check**. The GET handlers in the same file
  (`HandleCustomerAppByID`, ~lines 529-566) do verify `X-Admiral-Customer-ID`.
- **Current behavior:** A single shared harbor token (`HarborAPIToken`,
  `config.go`) can start, stop, pause, deprovision, or resize **any** customer's
  instance by supplying an arbitrary `InstanceID`.
- **Impact:** Cross-tenant takeover/sabotage of customer workloads.
- **Recommendation:** Require and verify `X-Admiral-Customer-ID` against
  `inst.CustomerID` before performing the action, mirroring the GET handlers.
- **Acceptance criteria:**
  - An action request whose `X-Admiral-Customer-ID` does not match the instance
    owner returns 403.
  - Existing single-tenant behavior is preserved.

### ADM-SEC-034 — Harbor token can provision apps for an arbitrary `customer_id`

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/28

- **Severity:** High
- **Affected components:** `admiral-harbor` → `admirald` API
- **Evidence:** `admirald/internal/api/handlers_instances.go:299-328`
  (`HandleCustomerApps` POST, behind `HarborAuthMiddleware`) reads
  `req.CustomerID` from the request body and provisions without verifying the
  harbor caller owns that customer.
- **Impact:** A harbor caller can create workloads billed to any tenant.
- **Recommendation:** Bind the harbor caller to a customer identity derived from
  the authenticated token and reject `customer_id` values that do not match.
- **Acceptance criteria:**
  - Provisioning fails when the body `customer_id` differs from the
    authenticated harbor identity.
  - Tests cover the mismatch path.

### ADM-SEC-035 — Plaintext app-secret values stored and disclosed via API

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/29

- **Severity:** High
- **Affected components:** `admirald` API + database
- **Evidence:** `admirald/internal/api/handlers_apps.go:253` persists the full
  `yamlContent` (including `secrets[*].value`) into
  `app_definitions.raw_yaml`, and `:200` returns the `AppDefinition` verbatim
  from GET `/api/v1/apps` (reachable by the harbor token, `api.go:83`).
  `pkg/admiral/validation.go:61` explicitly permits literal `secret.Value`.
- **Impact:** Static secret values are persisted in cleartext and exposed to
  harbor callers.
- **Recommendation:** Never store or return literal secret values. Reference
  them through an encrypted column / secrets manager and strip `value` from API
  responses.
- **Acceptance criteria:**
  - `GET /api/v1/apps` never returns a literal secret value.
  - `raw_yaml` does not contain recoverable plaintext secrets.

### ADM-SEC-036 — WireGuard source-IP binding bypassed when `WireguardIP` is empty

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/30

- **Severity:** High
- **Affected modes:** all non-single-node modes
- **Evidence:** `admirald/internal/api/node_auth.go:96-104` only checks source
  IP `if node.WireguardIP != ""`. A worker can blank its own `wireguard_ip` via
  heartbeat (`internal/database/nodes.go:160`,
  `wireguard_ip = COALESCE(NULLIF($4,''), wireguard_ip)`), after which its token
  is accepted from any source IP.
- **Impact:** A leaked node token is usable from any host once the worker clears
  its WireGuard IP, defeating the VPN-source binding.
- **Recommendation:** Require a non-empty WireGuard IP for node auth in
  non-dev/single-node modes and disallow workers from clearing `wireguard_ip`.
- **Acceptance criteria:**
  - A heartbeat that clears `wireguard_ip` is rejected or ignored.
  - Node tokens are only accepted from the registered WireGuard address.

### ADM-SEC-037 — Fleet accepts unsigned tasks when no task signing key is set

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/43

- **Severity:** High
- **Affected modes:** all modes where `TaskPublicKey` is unset
- **Evidence:** `admiral-fleet/internal/agent/agent.go:118`
  (`if a.taskPublicKey != nil && result.Task != nil`). When no public key is
  configured, any task from the claim endpoint is accepted with bearer-token
  auth only.
- **Impact:** If admirald's fleet token leaks, arbitrary tasks can be executed
  on workers with no cryptographic authorization.
- **Recommendation:** Fail closed (or warn loudly and refuse in production) when
  a fleet token is used without a configured task-signing key.
- **Acceptance criteria:**
  - Production refuses unsigned tasks when a signing key is configured.
  - Missing key + unsigned task is logged as a security event.

### ADM-SEC-038 — Fleet task signature has no freshness or replay protection

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/44

- **Severity:** High
- **Affected modes:** all modes
- **Evidence:** `admiral-fleet/internal/agent/agent.go:144-148`
  (`verifyTaskSignature`) includes `SignedAt` in the signed message but never
  compares it against current time.
- **Impact:** A captured, signed task is replayable indefinitely.
- **Recommendation:** Reject tasks whose `SignedAt` is outside a small window
  (e.g. ±15 min) and/or require a unique nonce/sequence per task.
- **Acceptance criteria:**
  - Replayed or stale signed tasks are rejected.
  - A unique task identifier is enforced.

### ADM-SEC-039 — Fleet exposes secrets on the command line via `--env`

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/45

- **Severity:** Medium
- **Affected components:** `admiral-fleet`
- **Evidence:**
  `internal/podman/inspector.go:154,188` and `executor_helpers.go:236,248`
  pass `serviceRuntimeEnv(svc)` (which merges `svc.Secrets`, e.g. DB passwords)
  as `--env KEY=VALUE` to `podman run`. These appear in `/proc/<pid>/cmdline`
  and `ps`. The non-trusted paths correctly use `--env-file`.
- **Impact:** Secret values are visible to any local user able to read process
  listings (and to the shared rootless user).
- **Recommendation:** Build an env-file and pass `--env-file` instead of inline
  `--env` for trusted runs, mirroring the non-trusted path.
- **Acceptance criteria:**
  - Secret values are not present in `podman run` argv.
  - Equivalent behavior via env-file is covered by a test.

### ADM-SEC-040 — PayPal webhook signature verification re-serializes the body

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/13

- **Severity:** Critical
- **Affected components:** `admiral-harbor`
- **Evidence:** `app/paypal.py:358` does
  `webhook_event: json.loads(body) ...` and sends it via `json=verification`
  (`:361-364`). PayPal computes its signature over the **raw** body bytes, so
  re-serializing with `json=` changes spacing/ordering and the CRC32 no longer
  matches.
- **Current behavior:** `verification_status` returns `FAILURE` for **every
  legitimate** webhook, so real (and sandbox) PayPal payments can never be
  confirmed. Forged webhooks are still rejected, but the stated 1.0
  "verified PayPal" requirement is unachievable as written.
- **Impact:** Verified real-PayPal payments cannot work; customers who pay may
  never be provisioned.
- **Recommendation:** Pass the raw body string as `webhook_event`
  (`webhook_event=body`) without `json.loads` first.
- **Acceptance criteria:**
  - A genuine PayPal webhook is verified as `SUCCESS` against the sandbox.
  - A tampered body is rejected.

### ADM-SEC-041 — PayPal webhook lacks transmission-time freshness / replay window

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/14

- **Severity:** High
- **Affected components:** `admiral-harbor`
- **Evidence:** `app/portal.py:295-320` relies solely on
  `BillingEvent.event_id` de-duplication; there is no check that
  `PAYPAL-TRANSMISSION-TIME` is recent, and purged events can be replayed.
- **Impact:** A replayed old event (e.g. `PAYMENT.SALE.COMPLETED`) can recreate
  an Invoice/Payment after its `BillingEvent` row is rotated.
- **Recommendation:** Reject events whose `transmission_time` is older than a
  few minutes; keep the de-dup as defense-in-depth.
- **Acceptance criteria:**
  - A webhook older than the window is rejected.
  - Recent events still process.

### ADM-SEC-042 — Harbor performs state-changing actions on GET requests

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/15

- **Severity:** High
- **Affected components:** `admiral-harbor`
- **Evidence:**
  `app/client.py:553-640` (`billing_return`), `:643-656` (`billing_cancel`),
  `app/auth.py:343-380` (`confirm_email`),
  `app/portal.py:451-469` (`mock_paypal_approve`). These create Invoices,
  Payments, set `order.status="paid"`, and activate accounts from GET.
- **Impact:** CSRF / link-prefetch / login-CSRF surface for billing and account
  activation.
- **Recommendation:** Convert to POST with CSRF protection; confirm_email token
  flow should be POST.
- **Acceptance criteria:**
  - State-changing billing/activation endpoints reject GET.
  - CSRF token is required on the POST forms.

### ADM-SEC-043 — Harbor mock billing lacks an idempotence guard against the webhook path

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/16

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `app/client.py:584-622` provisions and writes Invoice/Payment on
  GET; the async webhook also provisions on `ACTIVATED`. Only `billing_return`
  checks `order.status == "paid"` up front.
- **Impact:** A near-simultaneous return + webhook can create a duplicate
  `CustomerApp`/Invoice (double-provision / double-charge risk).
- **Recommendation:** Guard with a unique constraint / `subscription.instance_id`
  check and wrap provisioning in a transaction.
- **Acceptance criteria:**
  - Concurrent return + webhook produces exactly one instance/invoice.

### ADM-SEC-044 — Flagship falls back to a hard-coded dev `SECRET_KEY` in production

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/8

- **Severity:** High
- **Affected components:** `admiral-flagship`
- **Evidence:** `app/config.py:19-23` falls back to a hard-coded `dev-...`
  default when `ENV != "production"`. `validate_production_config`
  (`app/security.py:197-205`) only refuses the dev default when
  `ENV=production`.
- **Impact:** A real deployment that forgets `ENV=production` silently runs
  with a public, forgeable session-signing key → session/token forgery.
- **Recommendation:** Require an explicit `FLAGSHIP_SECRET_KEY` (no default)
  regardless of `ENV`, or fail closed when unset.
- **Acceptance criteria:**
  - Flagship refuses to start without an explicit secret key.
  - No default session key exists.

### ADM-SEC-045 — Flagship DOM XSS via unescaped `innerHTML` of API errors

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/9

- **Severity:** Medium
- **Affected components:** `admiral-flagship` (SPA JS)
- **Evidence:** `app/static/js/app.js:64` sets `toast.innerHTML = message`
  where `message` is the backend `error` field. Some BFF paths return raw
  `str(e)` (`app/bff/backups.py:112`, `app/bff/catalog.py:172`).
- **Impact:** An attacker-influenced error string reaches `innerHTML` in the
  operator's browser.
- **Recommendation:** Use `toast.textContent = message` (or escape before
  insertion); route all errors through `sanitize_error_message`.
- **Acceptance criteria:**
  - Error text is rendered as text, never parsed as HTML.

### ADM-SEC-046 — `ADMIRAL_INSECURE_SKIP_VERIFY` control is dead in Flagship and Harbor

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/10

- **Severity:** Medium
- **Affected components:** `admiral-flagship`, `admiral-harbor`
- **Evidence:** `app/admiral_client.py:19-26` reads
  `current_app.config["ADMIRAL_INSECURE_SKIP_VERIFY"]`, but
  `app/config.py` never loads that env var, so `_verify()` always returns
  `True` (system CA). `validate_production_config` can never flag it. The
  documented Fedora Tier-2 workaround `ADMIRAL_INSECURE_SKIP_VERIFY=1`
  (AGENTS.md) is therefore non-functional, and self-signed-CA connections to
  admirald fail.
- **Impact:** Misleading configuration; the documented workaround does not work,
  and a real insecure-skip path (if wired) is unvalidated.
- **Recommendation:** Load the var in `Config`, wire it through `_verify()` and
  `validate_production_config`, and fail closed in production.
- **Acceptance criteria:**
  - Setting the var enables TLS skip in dev and is rejected in production.
  - The documented Tier-2 workaround functions.

### ADM-SEC-047 — Adm authentication rate limiter is in-memory and per-instance

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/31

- **Severity:** Medium
- **Affected components:** `admirald`
- **Evidence:** `admirald/internal/api/middleware.go:63,145-164`
  (`AdminAuthMiddleware` uses a local-map `NewRateLimiter()`). Under multi-node
  admirald the limit is not shared and is lost on restart. The fleet limiter is
  DB-backed.
- **Impact:** Admin brute-force protection is bypassable in multi-node and after
  restart.
- **Recommendation:** Use the DB-backed `DBRateLimiter` for admin auth as well.
- **Acceptance criteria:**
  - Failed admin auth attempts are counted across nodes and restarts.

### ADM-SEC-048 — `admiralctl` exposes node token via `--token` flag

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/10

- **Severity:** Medium
- **Affected components:** `admiralctl`
- **Evidence:** `cli/nodes.go:100` (`nodes register --token`) accepts the token
  as a flag with no warning, exposing it in `ps`/`/proc`. Contrast
  `init --token`, which warns at `cli/helpers.go:43`.
- **Impact:** Node token disclosure to local users/process listings.
- **Recommendation:** Read from an env var / interactive prompt like
  `resolveToken`, or print the same warning as `init`.
- **Acceptance criteria:**
  - `nodes register` reads the token from env/prompt by default.
  - A flag still works but warns.

### ADM-SEC-077 — Restore download SSRF protection is bypassable

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/47

- **Severity:** High
- **Affected components:** `admiral-fleet` restore executor
- **Evidence:** `internal/executor/executor_restore.go:219-268` resolves and
  validates the supplied hostname once in `isPrivateHost`, then creates a normal
  `http.Client` which performs a second DNS resolution. The client also follows
  redirects using Go's default policy without validating each redirect target.
- **Impact:** A public hostname can pass validation and later resolve to a
  loopback, private, link-local, or WireGuard address (DNS rebinding). A public
  HTTPS endpoint can also redirect Fleet to an internal HTTPS service. A signed
  restore task can therefore make a worker issue requests across its local and
  management-network trust boundaries.
- **Recommendation:** Resolve once and pin the validated address in a custom
  transport while preserving TLS `ServerName`. Add `CheckRedirect` validation
  for every hop, reject credentials/userinfo, and explicitly define allowed
  restore origins where practical.
- **Acceptance criteria:**
  - DNS rebinding between validation and connection is ineffective.
  - Redirects to loopback, private, link-local, CGNAT, documentation, and
    WireGuard ranges are rejected.
  - IPv4, IPv6, mixed-answer DNS, redirect chains, and hostname certificate
    verification are tested.

### ADM-SEC-078 — Harbor rate limiting is not atomic under concurrency

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/28

- **Severity:** High
- **Affected components:** `admiral-harbor` authentication and token-protected
  routes using `RateLimiter`
- **Evidence:** `app/rate_limit.py:21-31` locks an existing row with
  `FOR UPDATE`, but creates a row when none exists. `RateLimit.identifier` in
  `app/models.py:794` is indexed but not unique. Concurrent first requests can
  therefore create multiple counters for one identifier; subsequent
  `.first()` calls lock and increment only an arbitrary row.
- **Impact:** Parallel authentication attempts can be spread over duplicate
  counters and exceed the configured limit. Duplicate rows also accumulate and
  make enforcement dependent on database row order.
- **Recommendation:** Add a unique constraint on `identifier` and implement the
  counter with an atomic PostgreSQL upsert/update in one transaction. Handle
  serialization or uniqueness conflicts by retrying the rate-limit operation,
  not by allowing the request.
- **Acceptance criteria:**
  - Concurrent requests for one identifier create exactly one row.
  - At most the configured number of attempts is admitted under parallel load
    across multiple Gunicorn workers.
  - Database contention or retry exhaustion fails closed with a controlled
    response.

### ADM-SEC-079 — Flagship's absolute session timeout is sliding and never absolute

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/12

- **Severity:** Medium
- **Affected components:** `admiral-flagship`
- **Evidence:** `_session_is_expired` and `_session_absolute_expired` both read
  `SESSION_STARTED_AT_KEY` (`app/auth.py:99-113`). Every authenticated BFF
  request replaces that same value with the current time
  (`app/__init__.py:123-124`), and `/auth/me` does likewise
  (`app/auth.py:163-166`).
- **Impact:** An active or stolen browser session can remain locally valid
  indefinitely despite the documented `SESSION_ABSOLUTE_TIMEOUT_HOURS` limit.
  Admirald may impose a separate token expiry, but Flagship's advertised
  defense-in-depth control is ineffective and its behavior depends on the
  backend token lifetime.
- **Recommendation:** Store immutable login time and mutable last-activity time
  under separate keys. Never refresh the login timestamp; enforce both limits
  before forwarding any BFF request.
- **Acceptance criteria:**
  - Activity extends only the idle deadline.
  - A continuously active session is rejected after the absolute lifetime.
  - Tests advance time across both limits independently.

## Quality findings (component source review, 2026-07-14)

### ADM-QUAL-001 — `admiralctl` silently swallows `json.Marshal` errors on request bodies

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/13

- **Severity:** Medium
- **Evidence:** `admiralctl/internal/client/client.go:444,468,489,664,786,806,833,878`
  use `body, _ := json.Marshal(...)`. On failure a nil/empty body is sent to
  admirald, producing a confusing downstream error.
- **Recommendation:** Return `fmt.Errorf("marshal ...: %w", err)` instead of
  ignoring the error.

### ADM-QUAL-002 — `admiralctl` operation wait has no timeout and calls `os.Exit` in a helper

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/14

- **Severity:** Medium
- **Evidence:** `internal/client/client.go:573-586` (`WaitForOperation`) loops
  forever on `time.Sleep`; `cli/instances.go:484-495` calls
  `os.Exit(1)` inside a library-style helper.
- **Recommendation:** Add a context/timeout to the wait loop; return errors
  instead of calling `os.Exit`.

### ADM-QUAL-003 — `admiralctl` output bypasses `cmd` streams and contains dead code

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/15

- **Severity:** Low
- **Evidence:** `cli/helpers.go:61-80` and `internal/output/output.go:16,19`
  write to `os.Stdout` instead of `cmd.OutOrStdout()`; `cli/helpers.go:33`
  `requireToken()` is never called; `internal/client/client.go:248-251` has a
  duplicated branch in `sanitizeErrorBody`.
- **Recommendation:** Use `cmd.OutOrStdout()`; remove dead code; collapse the
  redundant branch.

### ADM-QUAL-004 — Harbor does not validate email format at registration

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/29

- **Severity:** Medium
- **Evidence:** `app/auth.py:239` (`register`) and `app/client.py:1499`
  (`student_email`) perform no RFC/format check. Malformed addresses flow into
  `Customer.email`, audit logs, and SMTP builders.
- **Recommendation:** Validate with a strict email regex / `email-validator` at
  registration and on enroll.

### ADM-QUAL-005 — Harbor worker marks invoices "paid" without confirming the sale

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/30

- **Severity:** Medium
- **Evidence:** `worker.py:94-119` (`_generate_invoices`) sets
  `status="paid"` immediately on `next_billing_at` elapsed for an active
  PayPal sub, trusting the subscription is current.
- **Recommendation:** Reconcile against actual `PAYMENT.SALE.COMPLETED` before
  marking paid; handle failed-first-sale / mid-cycle cancel.

### ADM-QUAL-006 — Harbor uses a fragile hand-rolled YAML tier parser

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/31

- **Severity:** Low
- **Evidence:** `app/admiral_client.py:102-141` (`parse_tiers_from_yaml`)
  parses `raw_yaml` line-by-line and feeds `price_monthly_cents` used for
  billing.
- **Recommendation:** Parse with a real YAML library to avoid mis-parsing edge
  cases that affect billing amounts.

### ADM-QUAL-007 — `admiralctl` path-traversal guard is ineffective for app file input

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/16

- **Severity:** Low
- **Evidence:** `cli/apps.go:144` calls `filepath.Abs(file)` *before*
  `sanitizeInputFilePath` (`cli/helpers.go:141-150`); an absolute path never
  starts with `".."`, so the guard cannot reject anything on this path.
- **Recommendation:** Check against an allowed base dir or evaluate `../`
  segments in the original input.

### ADM-QUAL-008 — Fleet artifact download during restore is unbounded (DoS / disk fill)

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/48

- **Severity:** Medium
- **Evidence:** `admiral-fleet/internal/executor/executor_restore.go:291`
  (`io.Copy(file, resp.Body)`) and `:195`/`s3.go:83` (`io.ReadAll`) fetch with
  no size cap. The later gzip extraction applies `maxRestoreArtifactBytes`, but
  the raw download is unconstrained.
- **Recommendation:** Wrap the body/data with
  `io.LimitReader(..., maxRestoreArtifactBytes)`.

### ADM-QUAL-009 — Fleet swallows errors and leaves outbox resilience path unused

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/49

- **Severity:** Low
- **Evidence:** `internal/agent/agent.go:242,251,255,295` and
  `health.go:85,100,248` drop errors; `main.go:72` calls `exec.Execute` +
  `SendResult` directly and never routes through `agent.HandleTask`
  (outbox retry), so a `SendResult` failure only logs.
- **Recommendation:** Surface aggregate metrics for dropped reports; route
  execution through `HandleTask` or remove the unused path.

### ADM-QUAL-010 — Flagship swallows backend errors and forwards unvalidated IDs

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/13

- **Severity:** Low
- **Evidence:** `app/bff/nodes.py:78-80` swallows metric-fetch errors;
  `app/bff/instances.py:200-224` and `app/bff/backups.py:154-169` forward
  `customer_id`/`node_id`/`target_app_id` without `validate_resource_id`;
  `app/bff/nodes.py:51-66` forwards raw `node_id`.
- **Recommendation:** Log backend failures with context; validate all IDs with
  `validate_resource_id` before forwarding to admirald.

### ADM-QUAL-011 — Flagship CSP allows third-party script CDNs

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/14

- **Severity:** Low
- **Evidence:** `app/security.py:166-177` permits `script-src` from
  `unpkg.com` and `cdnjs.cloudflare.com`.
- **Recommendation:** Self-host Vue/PatternFly assets and restrict
  `script-src 'self'` to reduce supply-chain XSS risk.

### ADM-QUAL-024 — Fleet has no coordinated shutdown or task cancellation

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/54

- **Severity:** Medium
- **Affected components:** `admiral-fleet`
- **Evidence:** `cmd/admiral-fleet/main.go:35-78` starts the HTTP server and all
  background loops with independent `context.Background()` values, enters an
  unconditional claim loop, and executes each task with another background
  context. There is no `signal.NotifyContext`, shared cancellation, server
  shutdown, or wait for goroutines.
- **Impact:** systemd termination cannot ask a running task to stop cleanly or
  flush its final callback/outbox state. A package upgrade or node shutdown can
  interrupt Podman/systemd mutations mid-operation while the lease renewer and
  callback lifecycle remain inconsistent.
- **Recommendation:** Derive all workers and task execution from one
  signal-aware root context, stop claiming on shutdown, cancel or bound the
  active task according to an explicit policy, stop lease renewal, flush the
  outbox, shut down HTTP, and wait for goroutines within systemd's timeout.
- **Acceptance criteria:**
  - SIGTERM stops new claims immediately and terminates within the configured
    service timeout.
  - Background loops and HTTP serving exit without leaks.
  - An interrupted task is left in an explicit retryable/failed state and does
    not continue renewing its lease.

### ADM-QUAL-025 — Harbor mutates database schema during application startup

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/32

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `app/__init__.py:134-140` runs `alembic.upgrade()` when tables
  exist, or `db.create_all()` followed by `alembic.stamp()` for an empty
  database, as part of the Flask application factory.
- **Impact:** Every Gunicorn process starts with schema-management authority and
  may race migrations during deployment. `create_all()` plus `stamp()` can also
  mark a database current without exercising the actual migration path, hiding
  migration defects until production upgrades. Startup failures become coupled
  to DDL locks and migration duration.
- **Recommendation:** Run migrations once as an explicit RPM/systemd deployment
  step before starting Harbor. Make the application validate the expected
  schema revision and fail clearly without modifying it.
- **Acceptance criteria:**
  - Harbor runtime credentials cannot create or alter schema objects.
  - Concurrent web workers never execute Alembic or `create_all()`.
  - Fresh install and upgrade tests apply the real migrations before service
    startup and reject an incompatible revision.

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
   018, 021, 022, 023, 024, 025, 049, 050).
5. Make secure mode transitions and service reconciliation deterministic
   (ADM-SEC-011, 013, 014).
6. Repair fail2ban and make release tests authoritative (ADM-SEC-012, 015,
   016).
 7. Fix Go code issues: InsecureSkipVerify, panic in secrets, session HMAC
    persistence (ADM-SEC-030, 031, 032).
 8. Update operator documentation only after the artifact-level matrix passes
    (ADM-SEC-020, 026, 027).
 9. Before 1.0: fix the Harbor tenancy model and PayPal verification path
    (ADM-SEC-033, 034, 035, 040, 041, 042, 043).
 10. Close code-level auth/transport gaps: WireGuard binding, fleet task
     signing and replay, flagship secret key and XSS, harbor token exposure
     (ADM-SEC-036, 037, 038, 039, 044, 045, 047, 048).
 11. Address quality findings that affect reliability and billing correctness
     (ADM-QUAL-001, 002, 004, 005, 008).
 12. Make installer failure handling explicit and verifiable (ADM-SEC-051,
     052).
 13. Fix admin audit trail forgery and node identity bypass (ADM-SEC-053,
     054, 055).
 14. Harden secret management: key rotation, outdated deps, session
     invalidation (ADM-SEC-056, 057, 058).
 15. Fix Harbor tenancy, billing correctness, and upload safety
     (ADM-SEC-059, 061, 063, 065, 066, 067, 068, 069).
 16. Harden systemd units and build pipeline (ADM-SEC-071, 072, 073;
     ADM-QUAL-020, 021, 022).
 17. Close CLI and fleet reliability gaps (ADM-SEC-070, 074, 075, 076;
     ADM-QUAL-012 through 019, 023).
 18. Close restore-network, session, and concurrent rate-limit gaps
     (ADM-SEC-077, 078, 079) and make service/database lifecycle explicit
     (ADM-QUAL-024, 025).

## Source-code findings — admirald (control plane, 2026-07-14)

### ADM-SEC-053 — Admin auth middleware does not strip `X-Admiral-Admin-User` on raw token auth

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/32

- **Severity:** High
- **Affected components:** `admirald`
- **Evidence:** `admirald/internal/api/admin_auth.go:26-96`
  (`Server.AdminAuthMiddleware`). When the handler authenticates via the raw
  admin token (line ~51), it does not call `r.Header.Del("X-Admiral-Admin-User")`
  or `r.Header.Del("X-Admiral-Operator")`. The package-level
  `AdminAuthMiddleware` in `middleware.go:68` does strip these headers.
  `handlers.go:149-154` (`operatorFromRequest`) reads the header for audit
  events.
- **Impact:** A client that sends a valid admin token together with
  `X-Admiral-Admin-User: anyuser` propagates a forged operator identity into
  all downstream handlers and audit logs.
- **Recommendation:** Strip `X-Admiral-Admin-User` and `X-Admiral-Operator` in
  the raw-token match path and set a constant admin identity, or pass it as a
  known identity for token-authenticated requests.
- **Acceptance criteria:**
  - Admin token auth never reads operator identity from request headers.
  - Audit events record the token-authenticated identity, not a header value.

### ADM-SEC-054 — `HandleTaskClaim` does not validate `node_id` against authenticated node

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/33

- **Severity:** High
- **Affected components:** `admirald`
- **Evidence:** `admirald/internal/api/handlers_fleet.go:128-163`
  (`HandleTaskClaim`). The handler reads `req.NodeID` from the JSON body and
  uses it to query tasks, but does not verify it matches the authenticated node
  from `NodeAuthMiddleware` (`NodeIDFromContext`).
- **Impact:** An authenticated fleet worker could claim tasks intended for a
  different node by sending a different `node_id` in the body.
- **Recommendation:** Extract `nodeID` from context via `NodeIDFromContext` and
  use it instead of `req.NodeID`, or verify `req.NodeID == nodeID`.
- **Acceptance criteria:**
  - A claim with a `node_id` that does not match the authenticated token
    returns 403.
  - Existing single-node behavior is preserved.

### ADM-SEC-055 — `HandleNodeHeartbeat` uses unauthenticated `req.NodeID` for database operations

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/34

- **Severity:** High
- **Affected components:** `admirald`
- **Evidence:** `admirald/internal/api/handlers_nodes.go:304-354`
  (`HandleNodeHeartbeat`). The handler extracts `req.NodeID` from the JSON body
  and uses it for `GetNode` and `UpdateNodeHeartbeat` without verifying it
  matches `NodeIDFromContext`.
- **Impact:** A node with a valid token can send heartbeats for a different
  `node_id`, potentially updating the wrong node's status, metrics, and storage
  state.
- **Recommendation:** Use the authenticated `nodeID` from context instead of
  `req.NodeID`, or reject requests where they differ.
- **Acceptance criteria:**
  - Heartbeat with mismatched `node_id` returns 403.
  - The authenticated node's ID is used for all state updates.

### ADM-SEC-056 — No encryption key rotation support in admirald or harbor

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/35

- **Severity:** Medium
- **Affected components:** `admirald`, `admiral-harbor`
- **Evidence:** `admirald/internal/secrets/secrets.go:22-28` holds a single
  `masterKey` with no key versioning, re-encryption path, or migration strategy.
  `admiral-harbor/app/secrets_manager.py:14` uses a single Fernet key derived
  from `HARBOR_ENCRYPTION_KEY`. When the key changes, all previously encrypted
  secrets become undecryptable.
- **Impact:** Key rotation is impossible without losing access to existing
  secrets. No disaster recovery path for key compromise.
- **Recommendation:** Implement key versioning (prepend a key ID to ciphertext)
  and support multiple decryption keys for rotation. Document a rotation
  procedure.
- **Acceptance criteria:**
  - Secrets encrypted with an old key are still decryptable after rotation.
  - New secrets are encrypted with the current key.
  - A documented rotation procedure exists.

### ADM-SEC-057 — Outdated `golang.org/x/crypto` with known vulnerabilities

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/36

- **Severity:** Medium
- **Affected components:** `admirald`
- **Evidence:** `admirald/go.mod` pins `golang.org/x/crypto v0.17.0` (Dec
  2023). Multiple security fixes have been published since.
- **Impact:** Potential active CVEs in a security-critical dependency used for
  password hashing and key derivation.
- **Recommendation:** Update to the latest `golang.org/x/crypto` release and run
  `govulncheck` to identify any specific CVEs affecting this code.
- **Acceptance criteria:**
  - `go.mod` references a current `x/crypto` release.
  - `govulncheck` reports no known vulnerabilities.

### ADM-SEC-058 — `HandleAdminChangePassword` does not invalidate other sessions

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/37

- **Severity:** Medium
- **Affected components:** `admirald`
- **Evidence:** `admirald/internal/api/admin_auth.go:244-321`. After a
  successful password change, all other active sessions for the user remain
  valid. There is no mechanism to invalidate other sessions for the same user.
- **Impact:** An attacker who compromised a session will not be kicked out by a
  password change.
- **Recommendation:** After password change, delete all sessions for the
  affected user, or add a `sessions_revoked_at` column and check it in the
  middleware.
- **Acceptance criteria:**
  - After password change, only the current session remains valid.
  - Other sessions for the same user are rejected.

## Source-code findings — admiral-fleet (worker agent, 2026-07-14)

### ADM-SEC-059 — Harbor fiscal evidence upload has no file type or size validation

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/17

- **Severity:** High
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/client.py:1601-1620`
  (`/fiscal-requests/new`). The endpoint accepts any file type without
  validation. The extension is extracted from the original filename with no
  allowlist. There is no file size limit (unlike backup upload which enforces
  `HARBOR_MAX_BACKUP_UPLOAD_BYTES`).
- **Impact:** An attacker could upload `.html`, `.svg`, `.js`, or other
  dangerous files. Unrestricted file size enables denial-of-service via disk
  fill.
- **Recommendation:** Add an extension allowlist (e.g., `{".pdf", ".png",
  ".jpg", ".jpeg"}`), enforce a maximum file size, and consider content-type
  verification. Follow the pattern used in `branding.py:17`
  (`ALLOWED_IMAGE_EXTENSIONS`).
- **Acceptance criteria:**
  - Only allowlisted extensions are accepted.
  - File size is bounded.
  - Disallowed types return a clear error.

### ADM-SEC-060 — Harbor worker crashes skip all subsequent reconciliation steps

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/18

- **Severity:** High
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/worker.py:510-557` (`main()`). Six
  reconciliation steps are called sequentially without individual `try/except`
  blocks. If `_generate_invoices()` raises (e.g., DB connection failure),
  `_enforce_payment_policy`, `_reconcile_paypal_subscriptions`,
  `_reconcile_operations`, `_sync_remote_instances`, and
  `_reconcile_setup_failed` are all skipped.
- **Impact:** Payment enforcement, refund processing, and instance
  synchronization silently stop. Customers are not suspended for non-payment,
  and running instances are not reconciled.
- **Recommendation:** Wrap each step in `try/except` blocks so a failure in one
  step does not prevent the others from running. Log the exception and continue.
- **Acceptance criteria:**
  - A crash in invoice generation does not prevent payment enforcement.
  - Each step logs its own errors independently.
  - The worker continues processing after individual step failures.

### ADM-SEC-061 — Harbor `stored_path` exposed to clients in backup data

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/19

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/models.py:499`
  (`UploadedBackup.as_dict()`). Includes `stored_path`, the server filesystem
  path, in client-facing responses.
- **Impact:** Leaks internal server directory structure to clients.
- **Recommendation:** Remove `stored_path` from `as_dict()` or create a
  `safe_dict()` for client-facing responses.
- **Acceptance criteria:**
  - Client API responses do not contain filesystem paths.

### ADM-SEC-062 — No multi-factor authentication (MFA) on admin or customer login

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/20

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/auth.py`, `admiral-harbor/app/admin.py`.
  Neither admin nor customer login supports MFA/TOTP.
- **Impact:** For a platform handling payments, subscriptions, and provisioning,
  single-factor authentication is a significant gap.
- **Recommendation:** Implement TOTP-based MFA for admin users at minimum.
- **Acceptance criteria:**
  - Admin login supports TOTP-based second factor.
  - MFA enrollment and recovery flows are implemented.

### ADM-SEC-063 — No password complexity requirements in harbor

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/21

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/auth.py:240-241` checks only `if not
  password`. Same issue in `admin.py:1433`.
- **Impact:** Users can register with single-character passwords.
- **Recommendation:** Enforce minimum password length (e.g., 12 characters for
  customers, 16 for admins).
- **Acceptance criteria:**
  - Registration and password change enforce minimum length.
  - Weak passwords are rejected with a clear error.

### ADM-SEC-064 — Harbor `RateLimit` table grows unboundedly

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/22

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/rate_limit.py:17-51`. Old `RateLimit` rows
  are never cleaned up.
- **Impact:** Table growth degrades performance over time.
- **Recommendation:** Add periodic cleanup of expired `RateLimit` rows (e.g., in
  the worker's `main()`).
- **Acceptance criteria:**
  - Expired rate limit rows are deleted periodically.
  - Active rate limits are preserved.

### ADM-SEC-065 — Duplicate invoices possible on worker rerun

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/23

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/worker.py:64-120` (`_generate_invoices`). Does
  not check if an invoice already exists for the current billing period before
  creating one.
- **Impact:** Double-charging customers if the worker runs twice in the same
  billing period.
- **Recommendation:** Add a check before creating an invoice to verify no
  invoice already exists for this subscription and billing period.
- **Acceptance criteria:**
  - Running `_generate_invoices` twice in the same period produces exactly one
    invoice per subscription.

### ADM-SEC-066 — `_calculate_mrr()` references non-existent model attribute

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/24

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/admin.py:355` references
  `sub.tier_amount_cents` which does not exist on the `Subscription` model.
  The correct attribute is `sub.monthly_price_cents`. The `hasattr` check
  always returns `False`, so MRR is always reported as zero.
- **Impact:** MRR dashboard always shows $0.00, providing incorrect business
  intelligence.
- **Recommendation:** Change `sub.tier_amount_cents` to
  `sub.monthly_price_cents`.
- **Acceptance criteria:**
  - MRR calculation uses the correct model attribute.
  - Dashboard displays accurate MRR.

### ADM-SEC-067 — Harbor incident attachment silently discarded

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/25

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/client.py:1245-1254`. Accepts a file
  attachment via `request.files.get("attachment")`, calls `secure_filename()`,
  but never saves the file content to disk. The model only stores
  `attachment_name`.
- **Impact:** Users believe they uploaded an attachment but it is silently lost.
- **Recommendation:** Either save the attachment to disk and store the path, or
  remove the file upload field from the form.
- **Acceptance criteria:**
  - Uploaded attachments are persisted and retrievable, or the upload field is
    removed.

### ADM-SEC-068 — `_export_subscriptions_csv` references non-existent model attributes

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/26

- **Severity:** Medium
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/admin.py:443-453`. References
  `sub.subscription_id`, `sub.customer_name`, `sub.tier`, and `sub.updated_at`,
  none of which exist on the `Subscription` model. Correct fields are
  `sub.external_id`, `sub.customer_email`, `sub.tier_name`, and
  `sub.created_at`.
- **Impact:** CSV export crashes at runtime with `AttributeError`.
- **Recommendation:** Fix attribute names to match the actual model fields.
- **Acceptance criteria:**
  - CSV export completes without errors.
  - Exported data matches the database contents.

### ADM-SEC-069 — Harbor customer search allows wildcard injection

- **GitHub issue:** https://github.com/admiral-project/admiral-harbor/issues/27

- **Severity:** Low
- **Affected components:** `admiral-harbor`
- **Evidence:** `admiral-harbor/app/admin.py:1552-1556`. Uses
  `ilike(f"%{q}%")` without escaping `%` and `_` in the search term `q`.
- **Impact:** A search for `%` matches all records, potentially causing
  performance issues or data exposure.
- **Recommendation:** Escape `%` and `_` in the `q` parameter before using it
  in `ilike()`.
- **Acceptance criteria:**
  - Literal `%` and `_` in search terms are treated as text, not wildcards.

### ADM-SEC-070 — Fleet restore SSRF protection incomplete for IPv6

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/46

- **Severity:** Low
- **Affected components:** `admiral-fleet`
- **Evidence:** `admiral-fleet/internal/executor/executor_restore.go:201-250`.
  `isRestrictedIP` does not cover IPv6 ULA (`fc00::/7`) or IPv6 link-local
  (`fe80::/10`).
- **Impact:** Restore downloads could target IPv6 private addresses.
- **Recommendation:** Add `fc00::/7` and `fe80::/10` to the restricted CIDRs,
  or use Go's `net.IP.IsPrivate()`.
- **Acceptance criteria:**
  - IPv6 private and link-local addresses are blocked for restore downloads.

### ADM-SEC-071 — Systemd units use `ProtectSystem=full` instead of `strict`

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/57

- **Severity:** Medium
- **Affected components:** `packaging/systemd/`
- **Evidence:** All 6 service files use `ProtectSystem=full`, which only makes
  `/usr` and `/boot` read-only. The existing `ReadWritePaths` already grants
  specific write access.
- **Impact:** Services can write to `/etc` and other paths not covered by
  `ReadWritePaths`.
- **Recommendation:** Change to `ProtectSystem=strict` across all units. The
  existing `ReadWritePaths` already provides the needed write access.
- **Acceptance criteria:**
  - All service units use `ProtectSystem=strict`.
  - Services continue to function with the existing `ReadWritePaths`.

### ADM-SEC-072 — Makefile downloads source tarballs without checksum verification

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/58

- **Severity:** Medium
- **Affected components:** `Makefile`
- **Evidence:** `Makefile:92-113`. Source tarballs are downloaded via
  `curl -sL` without any SHA256 verification.
- **Impact:** MITM or compromised CDN could inject malicious source code into
  RPM builds.
- **Recommendation:** Add SHA256 checksum verification for all downloaded
  tarballs.
- **Acceptance criteria:**
  - Every downloaded tarball is verified against an expected checksum.
  - Checksum mismatches fail the build.

### ADM-SEC-073 — Harbor database connection uses `sslmode=disable` for localhost

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/59

- **Severity:** Low
- **Affected components:** `ansible/roles/admiral_harbor/`
- **Evidence:** `ansible/roles/admiral_harbor/tasks/main.yml:113`. Harbor
  database URL uses `sslmode=disable` for localhost connections, while admirald
  uses `sslmode=require`.
- **Impact:** Database traffic is unencrypted even when the database is on a
  different host.
- **Recommendation:** Use `sslmode=prefer` as a minimum for consistency with
  admirald.
- **Acceptance criteria:**
  - Harbor database connections use `sslmode=prefer` or `sslmode=require`.

### ADM-SEC-074 — `admiralctl` reads unbounded response bodies

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/11

- **Severity:** Medium
- **Affected components:** `admiralctl`
- **Evidence:** `admiralctl/internal/client/client.go:166`. Uses
  `io.ReadAll(resp.Body)` without a size limit.
- **Impact:** A compromised or malicious admirald server could send a
  multi-gigabyte response, causing OOM on the client.
- **Recommendation:** Use `io.LimitReader(resp.Body, maxResponseSize)` (e.g.,
  10 MB).
- **Acceptance criteria:**
  - Response body reads are bounded to a reasonable maximum size.

### ADM-SEC-075 — `admiralctl` prints Ed25519 private key seed to stderr

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/12

- **Severity:** Medium
- **Affected components:** `admiralctl`
- **Evidence:** `admiralctl/cli/init.go:48`. The private key seed is printed
  to `cmd.OutOrStderr()` in hex. stderr is commonly captured by terminal
  multiplexers, CI logs, systemd journal, and shell history tools.
- **Impact:** Signing key disclosure to any process that captures stderr.
- **Recommendation:** Write the private key to a file with 0600 permissions
  instead of printing it, or prompt the user for a file path.
- **Acceptance criteria:**
  - Private key material is written to a file, not printed to stderr.
  - The file is created with mode 0600.

### ADM-SEC-076 — Flagship `register_node` forwards raw JSON body without validation

- **GitHub issue:** https://github.com/admiral-project/admiral-flagship/issues/11

- **Severity:** Medium
- **Affected components:** `admiral-flagship`
- **Evidence:** `admiral-flagship/app/bff/nodes.py:55-62`. The endpoint calls
  `request.get_json(force=True, silent=True)` and forwards the entire `body`
  dict to `api_post("/api/v1/nodes", body)`. The `node_id`, `hostname`, and
  `ip` fields are checked for existence but not validated against injection.
- **Impact:** An attacker with a valid session could inject arbitrary JSON
  fields or pass malformed IP addresses / hostnames to admirald.
- **Recommendation:** Validate `node_id` with `validate_resource_id`, `ip` with
  `ipaddress.ip_address()`, and construct an explicit allowlist payload.
- **Acceptance criteria:**
  - Only validated fields are forwarded to admirald.
  - Malformed IPs and hostnames are rejected.

## Quality findings — component source (2026-07-14, continued)

### ADM-QUAL-012 — Missing `rows.Err()` checks after `rows.Next()` loops in admirald

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/38

- **Severity:** Low
- **Evidence:** Multiple database files (`internal/database/apps.go:127-142`,
  `secrets.go:35-51`, `nodes.go:77-93`, etc.) do not check `rows.Err()` after
  `rows.Next()` loops.
- **Impact:** Iteration errors are silently missed.
- **Recommendation:** Add `if err := rows.Err(); err != nil { ... }` after all
  `rows.Next()` loops.
- **Acceptance criteria:**
  - All `rows.Next()` loops are followed by `rows.Err()` checks.

### ADM-QUAL-013 — `randomHex` falls back to predictable timestamp on `rand.Read` failure

- **GitHub issue:** https://github.com/admiral-project/admirald/issues/39

- **Severity:** Low
- **Evidence:** `admirald/internal/queue/queue.go:422-428`. Falls back to
  `time.Now().UnixNano()` if `rand.Read` fails.
- **Impact:** Predictable values undermine uniqueness guarantees.
- **Recommendation:** Return an error instead of silently falling back.
- **Acceptance criteria:**
  - `rand.Read` failure is propagated as an error.

### ADM-QUAL-014 — `admiralctl` exported `NewWithHTTP` bypasses TLS configuration

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/17

- **Severity:** Low
- **Evidence:** `admiralctl/internal/client/client.go:908-916`. Accepts an
  arbitrary `*http.Client`, bypassing the TLS configuration that `New` applies.
- **Impact:** External consumers could create an insecure client.
- **Recommendation:** Unexport it (`newWithHTTP`) or move to a `_test.go` file.
- **Acceptance criteria:**
  - The function is not exported or is in test-only code.

### ADM-QUAL-015 — `admiralctl` `os.Exit(1)` bypasses deferred cleanup

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/18

- **Severity:** Low
- **Evidence:** `admiralctl/cli/instances.go:244,493`. Calls `os.Exit(1)`
  directly, bypassing deferred functions.
- **Impact:** Resource leaks on error paths.
- **Recommendation:** Return errors instead of calling `os.Exit`. Let Cobra
  handle exit codes.
- **Acceptance criteria:**
  - No `os.Exit` calls in command handlers.

### ADM-QUAL-016 — Fleet `collectVolumeTar` defers file close inside Walk callback

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/50

- **Severity:** Low
- **Evidence:** `admiral-fleet/internal/executor/executor_backup.go:347-348`.
  `defer f.Close()` accumulates deferred closes inside the Walk callback.
- **Impact:** All file handles stay open until the entire walk completes.
- **Recommendation:** Close explicitly instead of deferring inside the Walk
  callback.
- **Acceptance criteria:**
  - Files are closed immediately after use in the Walk callback.

### ADM-QUAL-017 — Fleet port allocation has a race condition

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/51

- **Severity:** Low
- **Evidence:** `admiral-fleet/internal/executor/executor_provision.go:533-575`.
  Reads `next_port` from a file, increments, and writes back. Two simultaneous
  tasks could allocate overlapping ports.
- **Impact:** Port conflicts if parallelism is ever added.
- **Recommendation:** Use file locking or atomic compare-and-swap.
- **Acceptance criteria:**
  - Port allocation is atomic or lock-protected.

### ADM-QUAL-018 — Fleet does not drain HTTP response bodies on error paths

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/52

- **Severity:** Low
- **Evidence:** `admiral-fleet/internal/agent/agent.go:101-103` and multiple
  other call sites. Response bodies are not drained before closing on error
  paths.
- **Impact:** HTTP connection reuse is prevented.
- **Recommendation:** Add `io.Copy(io.Discard, resp.Body)` before closing on
  error paths.
- **Acceptance criteria:**
  - All error paths drain the response body before closing.

### ADM-QUAL-019 — Fleet task execution uses `context.Background()` instead of cancellable context

- **GitHub issue:** https://github.com/admiral-project/admiral-fleet/issues/53

- **Severity:** Low
- **Evidence:** `admiral-fleet/internal/agent/agent.go:248`. Uses
  `context.Background()` for task execution.
- **Impact:** Task execution cannot be cancelled via signal handling.
- **Recommendation:** Thread a cancellable context through the task execution
  path.
- **Acceptance criteria:**
  - SIGTERM gracefully stops running tasks.

### ADM-QUAL-020 — Systemd units missing restrictive hardening directives

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/60

- **Severity:** Low
- **Affected components:** `packaging/systemd/`
- **Evidence:** None of the services set `RestrictSUIDSGID=true`,
  `LockPersonality=true`, or `DevicePolicy=closed`.
- **Impact:** Reduced defense in depth.
- **Recommendation:** Add these directives to all service units.
- **Acceptance criteria:**
  - All service units include `RestrictSUIDSGID=true`, `LockPersonality=true`,
    `DevicePolicy=closed`.

### ADM-QUAL-021 — Fleet `ReadWritePaths` includes overly broad `/run/user`

- **GitHub status:** Closed (reconciled 2026-07-15)

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/61

- **Severity:** Low
- **Affected components:** `packaging/systemd/`
- **Evidence:** `admiral-fleet.service:18`. `ReadWritePaths` includes
  `/run/user` which grants access to ALL user runtime directories.
- **Impact:** Fleet can read other users' runtime state.
- **Recommendation:** Scope to `/run/user/<uid>` for the admiral-apps user.
- **Acceptance criteria:**
  - `ReadWritePaths` references only the specific UID directory.

### ADM-QUAL-022 — Makefile Go builds missing `-trimpath`

- **GitHub issue:** https://github.com/admiral-project/admiral/issues/62

- **Severity:** Low
- **Affected components:** `Makefile`
- **Evidence:** `Makefile:42`. Builds with `-ldflags="-s -w"` but no
  `-trimpath`. Binaries contain the build machine's absolute paths.
- **Impact:** Build path leakage in distributed binaries.
- **Recommendation:** Add `-trimpath` to ldflags.
- **Acceptance criteria:**
  - Built binaries do not contain source paths.

### ADM-QUAL-023 — `admiralctl` `--output` flag values are never validated

- **GitHub issue:** https://github.com/admiral-project/admiralctl/issues/19

- **Severity:** Low
- **Affected components:** `admiralctl`
- **Evidence:** Multiple files accept `--output` with arbitrary strings. Invalid
  values silently fall through to table output.
- **Impact:** Confusing behavior when a typo is made.
- **Recommendation:** Validate that the value is `table` or `json` and return an
  error otherwise.
- **Acceptance criteria:**
  - Invalid `--output` values produce a clear error message.
