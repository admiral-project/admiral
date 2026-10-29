# R26 security checklist follow-up — 2026-10-29

Candidate: Epoch 5, 0.0.1rc6-26, x86_64.  
Admirald: 8efa1dec8e9540210d9f86d016dce4677dcc6543.  
Fleet: edc0a0d486eb102e9aaa4f250a08f777d7441f12.  
Product, RPM, and source pins changed: **no**. Candidate invalidated: **no**.

## Eight controls supported by current R26 evidence

| Checklist control | Evidence and boundary |
|---|---|
| Fleet tasks do not execute arbitrary customer shell on the host | The API accepts fixed task actions and Harbor customer routes accept app slugs, tiers, and fixed lifecycle actions, not raw YAML or host commands. A declared setup_command comes from a trusted app definition and runs through Podman inside the selected app container. Source: admiral-fleet/internal/executor/executor_provision.go; existing setup-command tests passed in the selected Fleet CI. This does not claim that trusted app definitions cannot contain shell syntax. |
| SELinux Enforcing persists across reboot | The R26 Fedora Single report records a real boot-ID change and workload/data recovery; the R26 SELinux assessment records Fedora remaining Enforcing. The Fedora Multi installer logs also assert both runtime mode and persistent boot policy. |
| Security-update policy is configured | The exact Fedora R26 installer logs show automatic security-update support installed, security-only upgrade type selected, downloading/applying enabled, and the service enabled. Apply available security updates was skipped where no update was available; this verifies the configured policy, not a package update being available that day. |
| WireGuard routes and authorized peers support the expected topology | R26 Admin, Worker, and Portal registered and became active/healthy. The installer installed peer registration and role-specific firewall rules; the real Portal and workload flows crossed the expected WireGuard routes. This is positive-path evidence, not an unauthorized-peer attack. |
| Admin is the central Caddy publication point | R26 Multi used Caddy on Admin to route HTTPS to the independent Portal and workload routes. The runtime report records HTTP 200 with strict TLS verification; the local route probe recorded remote Admin 192.168.122.20. |
| A workload cannot query another customer's secrets | The R26 A/B probe ran from both PostgreSQL containers and verified that the peer's secret path/name was unavailable in both directions. It compared password hashes without printing either password. This covers the tested PostgreSQL secrets, not every application log or storage driver. |
| Backup integrity and restoration | The R26 Multi PostgreSQL backup completed with SHA-256 dcdb34736fbb0034374e12bfc8dda6172060f5831815769b42c258e28c99ca70. Checksum-verified restore recovered the original database marker and removed the temporary marker; resume and deprovision succeeded. |
| Server-side role, scope, and task-signature checks | Exact-source API tests cover read/write/admin scope decisions and revoked operator-token usability; Fleet claim tests require and verify signed tasks. The full selected-SHA CI runs passed. This is code/CI evidence, not a live attempt to forge a token in the stopped lab. |

The checklist body now has 78 of 111 controls checked. These eight controls use existing R26 runtime artifacts and exact-source tests; no new VM or runtime workload was started. The full selected-SHA GitHub CI runs are linked from the release tracker and R26-CI-STATUS.md.

## Focused tests and CI scope

On the selected local sources, these tests passed:

- Admirald: GOMAXPROCS=2 go test ./internal/api -run 'Test(ScopeAllows|ScopeAllowsUnknownScope|OperatorTokenUsable)$' -count=1 — package passed.
- Fleet: GOMAXPROCS=2 go test ./internal/agent ./internal/executor -run 'Test(ClaimTaskContext_AllCases|SimulatedExecutorRejectsWrongNode|ProvisionSetupCommandSkippedWhenSetupCompleted|ProvisionSetupCommandSkippedByMarker|ProvisionSetupCommandWaitsForDependenciesToBeReady|ProvisionSetupCommandUsesExtendedTimeout)$' -count=1 — both packages passed.

Two local Admirald integration tests in an earlier combined command were skipped because this host has no DATABASE_URL; they are not counted as locally executed. The exact R26 Admirald GitHub CI run starts PostgreSQL, sets DATABASE_URL, runs go test ./..., and completed successfully. The current issue comments document separate focused handler tests that ran with a test database.

## Still not validated

The 33 unchecked controls still include live A→B management and published-port probes; MariaDB/MySQL and full UserNS lifecycle coverage; volume-label/shared-volume/AVC checks; safe OOM behavior; direct access to the shared user manager and unit-failure isolation; guest SSH/API/secret-file snapshots and playbook reapplication; IPv6 negative exposure and node revocation; health-check network abuse; the live Podman secret driver and external-storage scope; manipulated restore paths; and live cross-node task/token attacks.

The host currently has approximately 5.3 GiB available RAM and 42 GiB free disk; the three existing VMs remain shut off. This follow-up did not induce OOM, start VMs, change product files, rebuild RPMs, or invalidate any R26 cell. #307 remains open and R26 is not declared Gold.
