# Admiral beta16 — Security audit findings

Date: 2026-07-17
Auditor: automated deep review (opencode)
Scope: all source code, Ansible playbooks, installer, packaging, systemd units
Release: 0.0.1beta16 single-node

## Maintainer validation (2026-07-17)

The original automated report was checked against the current source. Its
severity counts and several recommendations were not reliable enough to use as
an implementation plan without validation.

| Finding | Validation | Disposition |
|---------|------------|-------------|
| ADM-SEC-080 | Confirmed | Fixed: the password is sent to `psql` on stdin, the role name is constrained, and the secret-bearing task uses `no_log`. |
| ADM-SEC-081 | Confirmed | Fixed with a systemd credential: the source INI is `0600 root:root` and is projected only into the `admirald` service namespace. The service also receives a restricted `/proc` view. |
| ADM-SEC-082 | Defense-in-depth | Fixed with `no_log`. Ansible does not normally print rendered template contents, so the report's claim of unconditional key logging was overstated. |
| ADM-SEC-083 | False positive | Rejected. `SharedVolumes[].Mount` is the destination inside the container; the host source is a generated named Podman volume, not the supplied path. Paths such as `/etc` are valid container destinations and do not mount host `/etc`. |
| ADM-SEC-084 | Exposure confirmed; proposed derivation unnecessary | Fixed by removing the worker key endpoint and all Fleet-side distribution. Queue payloads are decrypted only by `admirald`; authenticated workers receive plaintext only after a node-scoped claim over TLS. Compromising a worker no longer reveals the queue-at-rest key. |
| ADM-SEC-085 | False positive | Rejected. Arguments are passed directly to `exec.CommandContext`, so shell metacharacters have no host-shell semantics. Trusted shell execution is explicit and occurs inside the target rootless container. |
| ADM-SEC-086 | Confirmed | Fixed: backup and downloaded restore artifacts are atomically created with mode `0600`. This matters because the RPM currently makes the backup directory traversable/readable. |
| ADM-SEC-087 | Partially confirmed | Fixed for control-plane-generated internal restores by requiring checksum verification. The explicit administrative API option remains intentional and documented. |
| ADM-SEC-088 | Confirmed, low impact | Fixed: the WireGuard peer directory is reconciled to mode `0700`. |

Installer review also found and fixed two issues outside the original list:

- Fedora accepted production installation modes despite being supported only
  for `--dev-node`; unsupported modes are now rejected.
- An existing `admiral-common` package prevented reconciliation from loading
  current repository playbooks; the installer now installs or updates it
  before invoking Ansible.
- **ADM-SEC-089 (Critical, packaging):** the beta17-2 specs referenced component
  commits from before the final security fixes, and RPM metadata declared
  secret-bearing INI/environment files as mode `0644`. Release references now
  match the committed submodules, and all credential configuration files are
  packaged as `0600 root:root` so an RPM upgrade cannot reopen their modes.
  Every individual Admiral RPM target now runs the release-reference gate, and
  the gate also detects stale `admiral-common` installer/Ansible payload pins.
- **ADM-SEC-090 (Critical, PayPal):** the postback signature request sent
  `webhook_event` as a JSON string, while PayPal's API schema requires an
  object. This could reject every genuine live webhook and prevent paid
  subscriptions from being confirmed. Harbor now parses and validates the raw
  request body, then sends the resulting object in the verification request.
- **ADM-SEC-091 (Critical, PayPal):** live checkout stored only an `Order`, but
  the webhook returned 404 unless a `Subscription` already existed. Since the
  live browser return deliberately waits for webhook confirmation, no code
  created that subscription and genuine purchases could never provision. The
  webhook now materializes the subscription from its locked matching order and
  continues through the existing idempotent provisioning path. Provisioning is
  now gated specifically on `PAYMENT.SALE.COMPLETED`; subscription activation
  alone no longer grants service before a confirmed sale. Completed-sale
  amount and currency must exactly match the stored billing contract before
  any state change, invoice, payment record, or provisioning occurs.

No RPM build or unit-test execution is claimed by this validation record.

## Executive summary

Deep security review of the full Admiral codebase covering admirald,
admiral-fleet, admiralctl, admiral-flagship, admiral-harbor, installer
scripts, Ansible roles, and RPM packaging. 2 critical, 4 high, 2 medium,
and 3 low findings. The Go source components (admirald, fleet, ctl) are
in good shape: Ed25519 task signing is bilateral and enforced, SQL is
parameterized, shell injection is prevented, rootless containers are
mandated, and systemd hardening is comprehensive. The critical issues are
in the Ansible provisioning layer.

## Severity definitions

- **Critical**: can expose cluster-wide secrets or defeat a primary trust boundary.
- **High**: breaks a supported secure topology or leaves an advertised control ineffective.
- **Medium**: weakens defense in depth or idempotence.
- **Low**: primarily affects clarity, cleanup, or operator safety.

## Findings

### ADM-SEC-080 — PostgreSQL password exposed in shell command arguments and Ansible logs

- **Severity:** Critical
- **Affected components:** `ansible/roles/admiral_common/tasks/main.yml`
- **Evidence:** Lines 824-828 embed `admiral_postgres_password` directly in a
  `shell:` cmd string passed to `psql -c "ALTER ROLE ... PASSWORD '...'"`.
  The task lacks `no_log: true`. Two issues:
  1. The password is visible in `/proc/*/cmdline` to any local user while the
     `psql` process is running.
  2. Ansible logs the full shell command including the plaintext password to the
     control node console and any configured log destinations.
- **Impact:** PostgreSQL credential disclosure to any local user or log
  aggregation system during installation.
- **Recommendation:** (1) Add `no_log: true` to the three `shell:` tasks at
  lines 824, 836, and 848 immediately. (2) Refactor to use a temporary SQL
  file (`psql -f`) or the `community.postgresql.postgresql_user` module
  instead of interpolating the password into a shell command string.
- **Acceptance criteria:**
  - The password never appears in `/proc/*/cmdline` or Ansible output.
  - `no_log: true` is present on all PostgreSQL role and database creation
    tasks.
  - No secret value is interpolated into a `shell:` command string.

### ADM-SEC-081 — `admirald.ini` contains all platform secrets with group-readable permissions

- **Severity:** Critical
- **Affected components:** `ansible/roles/admirald/tasks/main.yml`
- **Evidence:** The `admirald.ini` template (lines 14-44) contains
  `admin_token`, `harbor_api_token`, `token_pepper`, `secrets_key`,
  `signing_key` (Ed25519 private key), `task_encryption_key`,
  `session_hmac_key`, `flagship_admin_pswd`, and database passwords with
  connection strings. File permissions are `mode: "0640" owner: root group:
  admiral`.
- **Impact:** Any process running as the `admiral` group (including
  `admiral-harbor`, `admiral-fleet`, and `admiral-flagship`) can read every
  secret in the platform, including the Ed25519 signing key and admin token.
  A compromise of any service as this user exposes the entire trust chain.
- **Recommendation:** Change permissions to `mode: "0600" owner: root group:
  root`. Services that need specific secrets should receive them through their
  own environment files or a dedicated secret endpoint, not by reading the
  central INI.
- **Acceptance criteria:**
  - `admirald.ini` has mode `0600` and owner `root:root`.
  - No service process reads the INI as a group member.
  - Individual services receive only the secrets they need.

### ADM-SEC-082 — WireGuard private key template deployment missing `no_log: true`

- **Severity:** High
- **Affected components:** `ansible/roles/admiral_wireguard/tasks/main.yml`
- **Evidence:** The template task at line 138 renders
  `wg-admiral.conf.j2` which contains
  `PrivateKey = {{ admiral_wg_private_key.stdout }}`. The task does not have
  `no_log: true`. The earlier key-generation tasks at lines 17 and 24 do have
  `no_log: true`, but the template deployment does not.
- **Impact:** The WireGuard private key is logged in Ansible output to the
  control node console and any configured log destinations.
- **Recommendation:** Add `no_log: true` to the template task at line 138.
- **Acceptance criteria:**
  - The WireGuard private key never appears in Ansible output or logs.

### ADM-SEC-083 — Fleet shared volume mount paths are not validated against sensitive host directories

- **Severity:** High
- **Affected components:** `admiral-fleet/internal/quadlet/renderer.go`
- **Evidence:** `svc.SharedVolumes[].Mount` is taken from the task payload
  and written into Quadlet `.container` files as
  `Volume=<name>:<mount>` at lines 239-241 without path validation.
  There is no allowlist or denylist of mount destinations.
- **Impact:** If admirald is compromised (or task signing is bypassed), a
  crafted task could instruct fleet to mount `/root/.ssh`, `/etc`, `/proc`,
  or other sensitive host paths into a container. Rootless containers can
  read most host paths even without write access.
- **Recommendation:** Add a `ValidateMountPath` function that rejects paths
  not under `/var/lib/admiral` or `/data`, and explicitly blocks `/`,
  `/etc`, `/root`, `/proc`, `/sys`, `/dev`, and home directories.
- **Acceptance criteria:**
  - Mount paths outside the allowed directories are rejected before
    Quadlet generation.
  - Tests confirm rejection of `/etc`, `/root`, and `/proc` mount paths.
  - The validation runs in fleet, not only in admirald.

### ADM-SEC-084 — Task encryption key is shared across all tasks with no per-task derivation

- **Severity:** High
- **Affected components:** `admirald/internal/api/handlers_nodes.go`
- **Evidence:** `HandleTaskEncryptionKey` (lines 277-302) serves a single
  AES-256-GCM key to any authenticated worker node. Every task in the queue
  is encrypted with the same key. A single node compromise exposes the key
  and allows decryption of the entire task history.
- **Impact:** An attacker who compromises one worker node token can decrypt
  all past and future task payloads, including database credentials, backup
  paths, and instance configuration.
- **Recommendation:** Implement per-task key derivation (e.g., HKDF with the
  task ID as info parameter) so that compromising one task's key does not
  expose others. Alternatively, rotate the key periodically and version the
  ciphertext.
- **Acceptance criteria:**
  - Compromising one task's encryption key does not expose other tasks.
  - Key rotation is possible without losing access to existing task data.
  - The key derivation is documented and tested.

### ADM-SEC-085 — `admiral-fleet` runs `trustedCommand` without `ValidateExecParams`

- **Severity:** Medium
- **Affected components:** `admiral-fleet/internal/podman/inspector.go`
- **Evidence:** `trustedCommand` (lines 619-635) calls `SanitizeArgs` for
  logging only but does not call `ValidateExecParams`. The arguments pass
  directly to `exec.CommandContext` without the shell-metacharacter and
  command-substitution checks that non-trusted paths apply.
- **Impact:** If admirald is compromised and task signing is bypassed, a
  malicious `setup_command` could include shell metacharacters. Mitigated
  by the fact that commands run inside rootless containers, not on the host.
- **Recommendation:** Add `ValidateExecParams` call in `trustedCommand` or
  document why it is intentionally skipped.
- **Acceptance criteria:**
  - Either `ValidateExecParams` is called on trusted paths, or the
    exclusion is documented with a security rationale.

### ADM-SEC-086 — Fleet backup files created with default umask permissions

- **Severity:** Low
- **Affected components:** `admiral-fleet/internal/executor/executor_backup.go`
- **Evidence:** Line 68 uses `e.FS.Create(path)` which creates with mode
  `0666`, reduced by the root service umask (typically `0022` -> `0644`).
  Backup files containing database dumps may be world-readable.
- **Impact:** Local users can read database backup contents.
- **Recommendation:** Use `os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC,
  0600)` for backup file creation.
- **Acceptance criteria:**
  - Backup files are created with mode `0600`.
  - No backup file is readable by non-root users.

### ADM-SEC-087 — Fleet restore checksum verification is opt-in, not default

- **Severity:** Low
- **Affected components:** `admiral-fleet/internal/executor/executor_restore.go`
- **Evidence:** Line 367 requires `task.Restore.VerifyChecksum` to be
  explicitly set to `true`. When not set, the restore artifact is applied
  without integrity verification.
- **Impact:** A corrupted or tampered backup artifact could be applied
  without detection. Mitigated by HTTPS transport and SSRF protections.
- **Recommendation:** Make checksum verification mandatory by default, with
  an explicit opt-out flag for backward compatibility.
- **Acceptance criteria:**
  - Checksum verification is on by default.
  - An explicit flag can disable it when needed.

### ADM-SEC-088 — WireGuard peers directory created with world-readable permissions

- **Severity:** Low
- **Affected components:** `ansible/roles/admiral_wireguard/tasks/main.yml`
- **Evidence:** Line 37 creates `/etc/wireguard/peers.d` with mode `0755`.
  Individual peer files are `0600`, but the directory being world-readable
  reveals filenames to any local user.
- **Impact:** Information disclosure of peer configuration filenames.
- **Recommendation:** Change directory mode to `0700`.
- **Acceptance criteria:**
  - The peers directory has mode `0700`.

### ADM-SEC-092 — Live PayPal mode remained pinned to sandbox endpoint

- **Severity:** Critical
- **Status:** Fixed on 2026-07-17.
- **Affected components:** `admiral-harbor`, installer, Ansible and RPM configuration.
- **Evidence:** `Config.HARBOR_PAYPAL_BASE_URL` and installed `harbor.env` always
  supplied the sandbox URL. `_base_url()` gave that value priority over the mode
  stored through the admin panel, so changing from sandbox to live continued to
  authenticate and submit requests against sandbox.
- **Impact:** Real-payment activation through the documented admin workflow could
  not work predictably. An operator override could also direct PayPal credentials
  to an arbitrary host.
- **Resolution:** Bind sandbox and live modes to PayPal's fixed official endpoints,
  reject unknown modes, remove the obsolete endpoint setting from installation
  paths, and fail explicitly when non-mock credentials are absent.
- **Acceptance criteria:**
  - Live mode always calls `https://api-m.paypal.com`.
  - Sandbox mode always calls `https://api-m.sandbox.paypal.com`.
  - Unknown modes and absent non-mock credentials fail closed.

### ADM-QUAL-026 — PayPal admin rejected its documented secret-preservation flow

- **Severity:** Medium
- **Status:** Fixed on 2026-07-17.
- **Affected component:** `admiral-harbor` admin PayPal configuration.
- **Evidence:** The password placeholder instructed administrators to leave an
  existing Client Secret blank to preserve it, but the HTML field was always
  required and the POST handler rejected every blank value.
- **Impact:** Updating only the webhook or resaving an unchanged configuration
  required the operator to retrieve and re-enter the PayPal secret unnecessarily.
- **Resolution:** Preserve the encrypted value when mode and Client ID remain
  unchanged. Require a new secret for initial setup, mode changes, or Client ID
  changes so credentials from sandbox and live cannot be mixed silently.

## Positive findings (things that are well-implemented)

| Area | Detail |
|------|--------|
| Task signing | Ed25519 bilateral: admirald signs, fleet verifies with `ed25519.Verify`, 15-min window, replay guard via `seenTasks` map |
| SQL injection | All user-data queries use parameterized queries (`$1`, `$2`) |
| Shell injection | Fleet uses `exec.Command` directly, never shell interpolation |
| SSRF protection | Restore downloads have DNS pinning, IP restriction, HTTPS-only, redirect validation |
| Path traversal | Validated in backup, restore, Quadlet rendering, instance IDs |
| Rootless containers | All workloads run rootless with `NoNewPrivileges=true` |
| Systemd hardening | Comprehensive: `ProtectSystem=strict`, `PrivateTmp`, `CapabilityBoundingSet`, `LockPersonality`, `RestrictSUIDSGID`, `DevicePolicy=closed` |
| Firewall | Deny-by-default with egress controls via nftables |
| SELinux | Enforcing, booleans configured correctly |
| Secret generation | CSPRNG via `openssl rand` for all secrets |
| Secrets file | `/etc/admiral/secrets` has mode 0600, verified with assertions |
| Quadlet sanitization | Strips null bytes, newlines, backticks, dollar signs |
| Env name rejection | Fleet rejects env vars with sensitive names (`SECRET`, `PASSWORD`, etc.) |
| No curl-pipe-bash | Installer is RPM-packaged, no remote code execution pattern |
| GPG verification | Installer refuses COPR repos without `gpgcheck=1` |

## Remaining validation order

1. Run the Harbor unit and integration suites against the pinned commit.
2. Build and reinstall the beta17-6 Harbor RPM.
3. Exercise sandbox checkout and webhook verification end to end.
4. Complete the release blocker with a real PayPal live payment and verify that
   the matching WordPress instance is provisioned exactly once.

## Notes

- This document tracks findings from the 2026-07-17 automated security audit.
- Existing findings in ISSUES.md (ADM-SEC-001 through ADM-SEC-079, ADM-QUAL-001 through ADM-QUAL-025) are not duplicated here.
- The task signature findings (ADM-SEC-037, ADM-SEC-038) from the earlier review have been verified as FIXED in beta16: Ed25519 verification is bilateral, 15-min freshness window is enforced, and duplicate task IDs are rejected.
