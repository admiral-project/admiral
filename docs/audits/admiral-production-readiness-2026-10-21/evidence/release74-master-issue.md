# Release 74 validation gate — functional E2E

This tracker supersedes [#200](https://github.com/admiral-project/admiral/issues/200). The prior gate included AlmaLinux, whose configured COPR build environment skipped the Go RPMs; this environment limitation is tracked separately in #276. The active release scope is now **Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide**, x86_64, Single-Node and Multi-Node.

## Matrix status (updated 2026-10-24)

| OS | Single-Node | Multi-Node |
|---|---|---|
| Rocky Linux 10 x86_64 | Historical R74 PASS — invalidated for active release gate | Historical R74 PASS — invalidated for active release gate |
| CentOS Stream 10 x86_64 | Historical R74 PASS — invalidated for active release gate | **FAIL** — node removal deleted terminal instance and operation history |
| Fedora Rawhide x86_64 | Historical R74 PASS — invalidated for active release gate | NOT TESTED |

**Release 74 status: 0/6 PASS for the active release decision.** The three Single-Node cells passed together on exact R74; Rocky Multi-Node also passed its scoped six-item gate before the new defect was found. The subsequent CentOS Stream Multi-Node run reproduced data loss on normal idle-node removal, now tracked by [#278](https://github.com/admiral-project/admiral/issues/278). Per the gate rule, this actionable finding invalidates the preceding R74 candidate run as a whole. These results remain historical evidence for R74 only. A rebuilt candidate must rerun all six cells from fresh guests. See [`release74-single-node-rerun-20261024.md`](release74-single-node-rerun-20261024.md), [`release74-rocky-multinode-progress-20261024.md`](release74-rocky-multinode-progress-20261024.md), and [`release74-centos-multinode-progress-20261024.md`](release74-centos-multinode-progress-20261024.md).

The six-item preflight below is a shared per-cell checklist. It was completed for the historical R74 Single-Node cells and the R74 Rocky/CentOS Multi-Node guests, but those results cannot be carried forward to a rebuilt candidate. The Single-Node checklist below records the historical R74 procedure only.

## Required preflight for every cell

- [ ] For the next candidate, record root commit, all five component SHAs, green CI run links, RPM NEVRAs and SHA-256 values.
- [ ] Clone the current updated OS seed into a fresh disposable VM. Record image hash, OS release, kernel, architecture, VM role, and UTC start time.
- [ ] Verify the guest has no Admiral RPMs or runtime resources before the test.
- [ ] Configure the candidate repository in the lab, not in the seed. Keep repositories and RPMs native to the guest OS.
- [ ] Install the exact six coordinated Release 74 Admiral RPMs with normal signed DNF dependency resolution. No `--nodeps`, `--force`, vendor override, or cross-distribution RPMs.
- [ ] Record exact package transaction, signatures, NEVRAs, and test logs. Redact secrets before publishing evidence.

## Single-Node checklist

- [x] Run the supported secure `admiral-install --single-node` flow and record the complete Ansible recap; require exit code 0, failed=0, unreachable=0.
- [x] Verify all expected services, TLS/API/portal health, SELinux enforcing, and no failed units.
- [x] Provision a real workload and verify running/healthy/available state, HTTP 200, and a persistent PostgreSQL marker.
- [x] Replay the same idempotency key; verify no duplicate operation, task, instance, or runtime resources.
- [x] Exercise update/resize and stop/start/restart; verify configuration and data continuity.
- [x] Create a backup, restore it, verify checksum and marker, and reject restore in an invalid lifecycle state.
- [x] Reboot the VM; verify changed boot ID, service convergence, HTTP 200, and marker persistence.
- [x] Deprovision and verify no test containers, pods, volumes, Quadlets, units, files, or database-owned runtime records remain.

## Multi-Node checklist

Each cell requires three real VMs of the same OS: one admin/control-plane node and two workers.

- [ ] Install and securely enroll both workers; verify authenticated registration, heartbeat, WireGuard handshakes, firewall/SELinux baseline, and empty initial workload inventory.
- [ ] Place a workload on each worker in turn; verify node assignment, healthy state, HTTP 200 over the overlay, and independent SQL markers.
- [ ] Replay same-key requests and run concurrent same-key provision plus conflicting update/delete; verify a single consistent result and complete cleanup.
- [ ] Reboot an active worker and exercise a controlled WireGuard disconnect/rejoin; verify unavailable/offline reporting, authenticated recovery, persistence, and no duplicate execution.
- [ ] Confirm removal of an active node is refused; deprovision workloads, remove an idle worker, and verify inventory/resource cleanup.
- [ ] Reboot the hub with an active workload; verify worker reconnection, fresh state convergence, HTTP 200, and marker persistence.

## Cell decision and evidence

A cell is PASS only when every applicable check above passes on the same unchanged candidate and has reproducible evidence. Missing or failed checks are NOT TESTED, BLOCKED, or FAIL, never PASS. A newly found actionable defect invalidates the preceding candidate run for the active release decision; no result from that candidate carries to a rebuilt release. A Single-Node result does not imply Multi-Node success; one OS result does not imply another.

For every check, record ID, type (static/unit/integration/E2E/resilience), procedure, expected and observed result, PASS/FAIL/BLOCKED/NOT TESTED, duration, logs, and sanitized evidence hashes. Do not delete evidence of failures. This six-cell functional gate does not claim full security, performance, HA, or production-readiness certification.

## Related open issues

- [#276 build(rpm): Alma x86_64_v2 COPR chroot skips Go packages](https://github.com/admiral-project/admiral/issues/276)
- [#274 build(rpm): pin typing-extensions for SQLAlchemy build checks](https://github.com/admiral-project/admiral/issues/274)
- [#273 R73 audit: record checks behind the four Single-Node PASS cells](https://github.com/admiral-project/admiral/issues/273)
- [#272 revoke WireGuard peer when removing a worker](https://github.com/admiral-project/admiral/issues/272)
- [#271 prevent HTTP health checks from following redirects](https://github.com/admiral-project/admiral/issues/271)
- [#270 verify staged seed helper RPM signatures](https://github.com/admiral-project/admiral/issues/270)
- [#269 apply EPEL pyOpenSSL compatibility pin to AlmaLinux](https://github.com/admiral-project/admiral/issues/269)
- [#267 return conflict when removing a node with active instances](https://github.com/admiral-project/admiral/issues/267)
- [#278 preserve instance and operation history on node removal](https://github.com/admiral-project/admiral/issues/278)
- [#260 avoid stale available state after declared service stops](https://github.com/admiral-project/admiral/issues/260)
- [#259 detect stale healthy availability after user systemd restart](https://github.com/admiral-project/admiral/issues/259)
- [#258 provide SQLAlchemy 2.0.31 or newer in EL10 COPR](https://github.com/admiral-project/admiral/issues/258)
- [#257 publish supported Mistune version to Admiral COPR](https://github.com/admiral-project/admiral/issues/257)
- [#256 invalidate pre-boot health observations before Single-Node recovery](https://github.com/admiral-project/admiral/issues/256)
- [#255 prevent queued status from overwriting completion](https://github.com/admiral-project/admiral/issues/255)
- [#251 align Multi-Node guide with the x86_64 release matrix](https://github.com/admiral-project/admiral/issues/251)
- [#250 distinguish private underlay and WireGuard overlay IPs](https://github.com/admiral-project/admiral/issues/250)
- [#249 document root context for runtime probes](https://github.com/admiral-project/admiral/issues/249)
- [#246 preserve service secrets during resize and reactivation](https://github.com/admiral-project/admiral/issues/246)
- [#242 remove SQLAlchemy and Alembic deprecation warnings](https://github.com/admiral-project/admiral/issues/242)
- [#240 avoid retrying capacity policy rejections](https://github.com/admiral-project/admiral/issues/240)
- [#237 mark stale runtime observations unavailable](https://github.com/admiral-project/admiral/issues/237)
- [#236 define provision readiness during cold service startup](https://github.com/admiral-project/admiral/issues/236)
- [#235 report OS updates applied when using refreshed seeds](https://github.com/admiral-project/admiral/issues/235)
- [#234 migrate injected distribution facts for ansible-core compatibility](https://github.com/admiral-project/admiral/issues/234)
- [#231 keep reports aligned with active release matrix](https://github.com/admiral-project/admiral/issues/231)
- [#229 do not replay terminal-operation tasks after restart](https://github.com/admiral-project/admiral/issues/229)
- [#228 fail deprovision when Podman resources remain](https://github.com/admiral-project/admiral/issues/228)
- [#224 parameterize hub IP in worker and portal firewall rules](https://github.com/admiral-project/admiral/issues/224)
- [#216 persist SELinux enforcing mode across reboots](https://github.com/admiral-project/admiral/issues/216)
- [#213 reissue CA-signed TLS leaf after dev-to-production reconvergence](https://github.com/admiral-project/admiral/issues/213)
- [#205 keep Fleet from mutating common-owned data roots](https://github.com/admiral-project/admiral/issues/205)
- [#202 secure volume backup artifact file mode](https://github.com/admiral-project/admiral/issues/202)
- [#201 provide patched Flask RPM for EL10](https://github.com/admiral-project/admiral/issues/201)
- [#191 preserve Harbor systemd drop-in RPM mode](https://github.com/admiral-project/admiral/issues/191)
- [#190 preserve cancelled subscription state during worker sync](https://github.com/admiral-project/admiral/issues/190)
- [#182 allow authenticated Harbor upload restore over private WireGuard origin](https://github.com/admiral-project/admiral/issues/182)
- [#181 enforce tier permissions for customer backups and restores](https://github.com/admiral-project/admiral/issues/181)
- [#106 verify the PayPal sandbox E2E flow](https://github.com/admiral-project/admiral/issues/106)
