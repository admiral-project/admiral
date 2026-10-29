# R26 Rocky Linux 10 Multi-Node runtime report

**Result: PASS**  
**Run date:** 2026-10-29 UTC  
**Candidate:** Epoch 5, `0.0.1rc6-26.el10`, x86_64  
**Product change during validation:** none

## Candidate and installation

The existing Admin, Worker, and Portal domains were reused; no VM domains were created. Each domain was freshly reimaged from the updated Rocky Linux 10.2 seed. The secure role installers completed with zero unreachable hosts and zero failed Ansible tasks:

| Role | Ansible recap |
|---|---|
| Admin | `ok=205 changed=95 unreachable=0 failed=0` |
| Worker target | `ok=182 changed=63 unreachable=0 failed=0` |
| Worker controller / registration | Admin `ok=15 changed=2`; Worker `ok=15 changed=4`; both `unreachable=0 failed=0` |
| Portal target | `ok=197 changed=78 unreachable=0 failed=0` |
| Portal controller / registration | Admin `ok=15 changed=2`; Portal `ok=17 changed=4`; both `unreachable=0 failed=0` |

The installed package identities matched the R26 EL10 manifest. The six EL10 RPMs were not substituted with Fedora packages.

| Package | NEVRA | SHA-256 |
|---|---|---|
| admiral-common | `5:admiral-common-0.0.1rc6-26.el10.noarch` | `9564f02da5a277419efd1099ecefbd9e9fd4b80802b02de0dcd163563658bea2` |
| admiral-flagship | `5:admiral-flagship-0.0.1rc6-26.el10.noarch` | `ab1130e5a827057d61658b9e599934931919e57922a3f3ad0e1aa8a9ce3c5d61` |
| admiral-fleet | `5:admiral-fleet-0.0.1rc6-26.el10.x86_64` | `d694aaabd2842b37c5c8d4faa700387c3f7e34d152f65633a5920afd222577b8` |
| admiral-harbor | `5:admiral-harbor-0.0.1rc6-26.el10.noarch` | `fc519c5195120b6c4cd039e7e644c6343ba512b4ce5098e08c012d4fe02578a2` |
| admiralctl | `5:admiralctl-0.0.1rc6-26.el10.x86_64` | `ca9e60466ef27c4f6fa04519f8ab71143c1b671ef1b487f401a7e884bac4e16f` |
| admirald | `5:admirald-0.0.1rc6-26.el10.x86_64` | `dad9b9f6f97cd120bcac74b8f59d4cf0733a8942ef74895ce516afbca714155b` |

## Runtime checks

- Admin, Worker, and Portal registered and healthy over the test WireGuard mesh. SELinux remained Enforcing on every node.
- Worker ran Fleet and rootless Podman as `admiral-apps`; the effective Podman default was `userns="auto"` with `num_locks=65536`.
- The real `e2e-portal-free` app definition was applied and deployed through Harbor. The app and PostgreSQL 16 database ran in a rootless pod on Worker.
- Harbor registration remained pending until Admin approval; the catalog was published and the customer deployed an instance to Worker.
- Admin Caddy routed `portal.r26.test` to Portal over WireGuard. Both the portal endpoint and workload hostname returned HTTP 200 with strict TLS verification (`ssl_verify_result=0`). No public DNS record was required.
- PostgreSQL marker `R26-ROCKY-MULTI-HARBOR-20261029` remained present after supported instance pause and resume operations. The instance returned to `running/healthy`.
- Supported deprovision succeeded. Worker had no remaining instance containers, pods, volumes, secrets, user units, Quadlets, or instance data paths. The app definition and temporary Caddy fixture were removed from the active test configuration.
- No relevant failed systemd units remained. Exact candidate RPMs remained installed on their role nodes.

The provision, pause, resume, and deprovision operations all reached `succeeded`; instance `inst_4383c925eb9dd555` was assigned to `worker-r26-rocky`.

## Resource guard

The guard sampled host and guest memory plus host and guest disk throughout the successful run. Minimums were host RAM 2114.8 MiB, host free disk 43.94 GiB, Admin RAM 633.5 MiB, Worker RAM 432.9 MiB, and Portal RAM 670.8 MiB. The guard requested no shutdown in the successful run. An earlier Portal-install attempt crossed the guest stop floor and was shut down gracefully; the successful retry used a fresh Portal overlay and completed the full flow.

## Scope

This PASS is for the R26 Rocky Linux 10 Multi-Node runtime cell. It does not claim Gold status or mark the separate #307 security checklist complete.
