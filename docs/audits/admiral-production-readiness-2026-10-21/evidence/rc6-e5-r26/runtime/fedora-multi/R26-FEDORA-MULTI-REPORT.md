# Fedora Rawhide Multi-Node — RC6 E5 R26

Date: 2026-10-28 UTC  
Candidate: Epoch 5, `0.0.1rc6-26.fc46`, x86_64  
Result: **PASS** for the R26 Fedora Rawhide Multi-Node runtime cell. The runtime lane, installer, workload/lifecycle flow, backup/restore, and two-customer A/B evidence below passed on the exact Fedora-native R26 RPMs. The separately scoped R25→R26 security regression review found no regression; that review did not turn checklist items without direct evidence into PASS. See the [R26 security review in #307](https://github.com/admiral-project/admiral/issues/307#issuecomment-6483295945).

## Candidate and topology

- The release candidate contains the Admirald resize/backup-policy fix at `8efa1dec8e9540210d9f86d016dce4677dcc6543`.
- Fedora packages were built natively for Fedora Rawhide 46; no EL10 RPM was used on Fedora. The six-package manifest is `../../fedora/RPM-MANIFEST.tsv`.
- Reused the three existing Fedora guests; no VM was created: Admin `192.168.122.20` / WireGuard `10.99.0.1`, Worker `192.168.122.21` / `10.99.0.2`, Portal `192.168.122.22` / `10.99.0.3`.
- Admin, Worker and Portal Ansible runs completed with `failed=0` and `unreachable=0`; Portal's successful retry was `ok=199 changed=78`. The initial Portal attempt was harness interference and is documented separately.

## Product flow and resize regression

The `e2e-portal-free` application definition was applied through `admiralctl apps apply`; this was an actual deployable fixture, not only a YAML validation. Through Harbor, a synthetic customer signup stayed pending, login was rejected before approval, the admin approved the account, the catalog was published, and the customer deployed the workload on `worker-001`.

The PostgreSQL marker `R26-FEDORA-MULTI-HARBOR-20261028` was written and read successfully. Resizing the instance from `free` to `security-small` succeeded as operation `op_4897b1815f5e187e`. The resulting snapshot retained `app_name`, `free`, and the full backup policy, including `manual_backups=true` and `restore_allowed=true`.

The Caddy portal and workload routes returned HTTP 200 with strict TLS verification (`ssl_verify_result=0`). After restore, the workload route again returned HTTP 200, verified TLS, and reached Admin at `192.168.122.20`.

## S3 backup and restore after resize

Used the pre-existing S3-compatible lab service over HTTPS at `https://192.168.122.1`; no MinIO was installed. The non-AWS endpoint uses path-style requests in the current Fleet implementation even with `force_path_style=false`. Temporary S3 credentials and the lab CA were installed only on the test Admin and Worker services and removed during cleanup.

- `admiralctl backups storage test` succeeded as operation `op_c96f9856e720baad`.
- A PostgreSQL backup after resize succeeded as operation `op_a1e8e0b809c1415b`, backup `bk_7a9b01a69e1fd350`, backend `s3`, size 824 bytes, SHA-256 `dcdb34736fbb0034374e12bfc8dda6172060f5831815769b42c258e28c99ca70`.
- The first restore request returned HTTP 409 because Admiral requires the application to be paused. No restore operation was created by that request. Pausing through Admiral succeeded as `op_f1b84d849a59099f`.
- Changed only the synthetic database marker to a temporary value, then restored `bk_7a9b01a69e1fd350` with checksum verification. Restore succeeded as `op_83744265d741d554`; afterwards the original marker was present and the temporary marker count was zero.
- Resuming succeeded as `op_c169e150fdc9020a`. The instance returned to `running`, `healthy`, `available`; the strict-TLS Caddy route remained HTTP 200.

This directly verifies the R25 resize/backup-policy regression on R26. It does not test volume-backup restore; this fixture's policy has `backup_volumes=false` and exercises PostgreSQL database backup/restore.

## Security checklist evidence on this R26 pod

The installed Worker configuration reported `userns = auto` as the role default, `subid_count=max_available`, `user.max_user_namespaces=32768`, and `kernel.pid_max=4194304`. The live app and PostgreSQL containers were unprivileged, used private PID namespaces, had `NoNewPrivs=1` and seccomp mode 2; the PostgreSQL container had `CapEff=0`. SELinux was Enforcing. The database port was not published, and no container runtime control interface was present in the pod.

The app and database containers within each pod shared a UID/GID map, as expected for services in one pod. The R26 A/B run then provisioned two independent Harbor customers on the same Worker: customer A (`inst_f2af615d40c7ed70`) and customer B (`inst_8ee0351ddf00e745`). Both deployed successfully through Harbor and ran rootless under `admiral-apps` on the exact R26 Fedora packages.

The live pod maps were non-overlapping: A `720896+1024`, B `721920+1024`. The probe confirmed separate network and PID namespaces, distinct SELinux MCS labels, and different PostgreSQL volume paths. Container ownership `999:999` mapped to host `721895:721895` for A and `722919:722919` for B. A could not see B's volume marker, read B's host volume, or write to B's volume. Customer database passwords differed (only hashes were compared); cross-customer secret paths and names were unavailable. Podman and systemd control interfaces were absent from the database containers, and PostgreSQL port 5432 was neither published nor reachable from A. SELinux remained Enforcing. Both customer routes returned HTTP 200 with strict TLS verification.

The per-customer snapshots additionally recorded rootless/unprivileged containers, `NoNewPrivs=1`, seccomp mode 2, PostgreSQL `CapEff=0`, a 256 MiB pod memory limit, one CPU, and `pids_limit=2048` for each service container. The app effective capabilities did not include `CAP_SYS_ADMIN`, `CAP_NET_ADMIN`, or `CAP_SYS_PTRACE`.

This completes the R26 two-customer A/B checks. The clarified #307 objective was to review recent product changes for security regressions and verify affected controls, not to repeat every prior audit or add optional hardening. The R25→R26 code review found no security regression; the open checklist items without direct evidence are explicitly recorded as not tested in the closing review comment. This is not a claim that every A–L checkbox passed. R25 runtime evidence is not counted as R26 release evidence.

## Cleanup and resource record

- The synthetic backup was deleted through Admiral; delete operation `op_9cc55e6123678663` succeeded.
- The synthetic instance was deprovisioned through Admiral; operation `op_939d17db8067b477` succeeded.
- The resize/restore instance was deprovisioned through Admiral; operation `op_939d17db8067b477` succeeded. The two A/B instances were also deprovisioned successfully as `op_d3f81c3eeedf5c71` and `op_4fef8912b67f7f0f`.
- A post-A/B Worker check found no matching containers, pods, volumes, secrets, user units, Quadlets, or instance data paths for either customer, and no cross-client probe files (`worker-security-cleanup-check-r26-ab.log`). The Caddy fixture and test routes were removed; Caddy and Admirald remained active. A new Admin API check confirmed the test domain and temporary certificate are absent; its temporary drop-in, CA anchor, certificate directory, and fixture directory are absent (`caddy-route-cleanup-check-r26-ab.log`).
- Backup storage was reset to local. Temporary S3 EnvironmentFiles, systemd drop-ins and CA anchors were removed. The pre-existing S3 lab service was left running.
- The resource log recorded threshold alerts during the broader validation window: host available RAM minimum 1,910 MiB, Admin 180 MiB, Worker 274 MiB, Portal 221 MiB. Host disk remained at least 34.1 GiB free; guest disk minima were 3.3/3.0/3.3 GiB. No kernel OOM or killed-process entries were found on the host or any of the three guests since 18:00 UTC. When host available RAM briefly fell below 2 GiB during restore cleanup, resume was deferred until the monitor recovered; no process or VM was killed.
- Final recorded monitor sample after A/B cleanup (sample 181, 2026-10-28 21:20:50 UTC): host available RAM 2,521 MiB and disk 33.9 GiB free; Admin 327 MiB, Worker 534 MiB, Portal 354 MiB RAM available. No threshold alerts were active in that sample. The separate Worker cleanup probe reported 507 MiB RAM available and 3.1 GiB disk free. The monitor was stopped after this final sample; no additional workloads were started after cleanup.

## Release status

The targeted R26 resize → S3 backup → checksum-verified restore sequence and the two-customer A/B security probes passed. Fedora Multi is **PASS** after the scoped #307 security regression review concluded with no regression. At the time this report was first written, Fedora Single, Rocky Single, and CentOS Single were also PASS, while Rocky Multi and CentOS Multi were pending (4/6). This is a historical snapshot; see the final matrix update below.

The root packaging commit `71a2cfc16eedd0f686a5e9d52c3f84414024d412` had a red CI run because four audit-helper defaults still named Release 21. Follow-up commit `b6146a46be93f1a9c242361e27b10dbbb2164bf6` changed only test/audit helpers to Release 26 and its root CI is green. No RPM payload, spec, source pin, or product code changed in that follow-up, so R26 RPMs and runtime evidence were not rebuilt or invalidated.

The R24 installer sentinel failure and its effect on release acceptance are already documented in [#308 comment 6477991576](https://github.com/admiral-project/admiral/issues/308#issuecomment-6477991576). That check remains important: the release must pass through the shipped installer, not only have the underlying settings present.

## Final matrix update — 2026-10-29

The Rocky Linux 10 and CentOS Stream 10 Multi-Node cells that were pending when this report was first written have since passed on the same frozen R26 candidate. The final matrix is **6/6 PASS**. This updates only the release-status summary; it does not alter the test result or claim that every #307 security-checklist control passed. No product or RPM change occurred between those cells.

`R26-FEDORA-MULTI-SHA256SUMS.txt` records hashes for this report and the selected runtime evidence. Detailed security snapshots remain local with restricted permissions.
