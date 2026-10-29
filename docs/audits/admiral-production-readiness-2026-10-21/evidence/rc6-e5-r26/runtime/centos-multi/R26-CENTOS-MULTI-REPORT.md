# R26 CentOS Stream 10 Multi-Node runtime report

**Result: PASS**  
**Run date:** 2026-10-29 UTC  
**Candidate:** Epoch 5, `0.0.1rc6-26.el10`, x86_64  
**Product change during validation:** none

## Candidate and installation

The existing Admin, Worker, and Portal domains were reused; no VM domains were created. Each domain was freshly reimaged from the updated CentOS Stream 10 seed. The secure role installers completed with zero unreachable hosts and zero failed Ansible tasks:

| Role | Ansible recap |
|---|---|
| Admin | `ok=204 changed=95 unreachable=0 failed=0` |
| Worker target | `ok=181 changed=63 unreachable=0 failed=0` |
| Worker controller / registration | Admin `ok=15 changed=2`; Worker `ok=15 changed=4`; both `unreachable=0 failed=0` |
| Portal target | `ok=196 changed=78 unreachable=0 failed=0` |
| Portal controller / registration | Admin `ok=15 changed=2`; Portal `ok=17 changed=4`; both `unreachable=0 failed=0` |

All six exact candidate RPMs were present on Admin; Worker and Portal had the expected role packages. The installed identities matched the R26 EL10 manifest.

| Package | NEVRA | SHA-256 |
|---|---|---|
| admiral-common | `5:admiral-common-0.0.1rc6-26.el10.noarch` | `9564f02da5a277419efd1099ecefbd9e9fd4b80802b02de0dcd163563658bea2` |
| admiral-flagship | `5:admiral-flagship-0.0.1rc6-26.el10.noarch` | `ab1130e5a827057d61658b9e599934931919e57922a3f3ad0e1aa8a9ce3c5d61` |
| admiral-fleet | `5:admiral-fleet-0.0.1rc6-26.el10.x86_64` | `d694aaabd2842b37c5c8d4faa700387c3f7e34d152f65633a5920afd222577b8` |
| admiral-harbor | `5:admiral-harbor-0.0.1rc6-26.el10.noarch` | `fc519c5195120b6c4cd039e7e644c6343ba512b4ce5098e08c012d4fe02578a2` |
| admiralctl | `5:admiralctl-0.0.1rc6-26.el10.x86_64` | `ca9e60466ef27c4f6fa04519f8ab71143c1b671ef1b487f401a7e884bac4e16f` |
| admirald | `5:admirald-0.0.1rc6-26.el10.x86_64` | `dad9b9f6f97cd120bcac74b8f59d4cf0733a8942ef74895ce516afbca714155b` |

## Runtime checks

- Admin, Worker, and Portal used CentOS Stream 10 Coughlan x86_64. All three nodes registered `active/healthy` over WireGuard. SELinux was Enforcing on all nodes.
- Admin ran `admirald`, Flagship, Caddy, and PostgreSQL. Worker ran Fleet and `wg-quick@wg-admiral`. Portal ran Harbor and `wg-quick@wg-admiral`. No relevant failed units were reported.
- Worker ran rootless Podman as `admiral-apps`; `podman info` reported rootless mode. The installed Podman configuration set `userns="auto"` and `num_locks=65536`. `/etc/subuid` and `/etc/subgid` each assigned `admiral-apps:720896:599379105`.
- The actual `e2e-portal-free` definition (`traefik/whoami:v1.10` plus PostgreSQL 16) was applied and deployed through Harbor. The instance ran in a rootless Worker pod and reached `running/healthy`.
- Harbor registration was pending before approval; pre-approval login was rejected. Admin approval enabled catalog publication and customer deployment.
- Caddy on Admin routed `portal.r26.test` to Portal at `https://10.99.0.3:5001` across WireGuard. The portal and workload hostname `e2e-portal-free413017.apps.r26.test` both returned HTTP 200 with strict TLS verification (`ssl_verify_result=0`). This used a local test CA and did not require public DNS.
- PostgreSQL marker `R26-CENTOS-MULTI-HARBOR-20261029` was written before pause and read after resume. Pause `op_56b22956b47e4240` and resume `op_db04f76df3f92984` both succeeded; the instance returned to `running/healthy`.
- Provision `op_ebeef4ab761bbfa8` and deprovision `op_3223b2a837e8c159` succeeded. Cleanup found no instance containers, pods, volumes, secrets, user units, Quadlets, or data paths on Worker.
- The app definition was deactivated and the temporary Caddy route, certificate, ACL changes, CA anchor, and local host alias were removed. Caddy and Admirald remained active.

Instance `inst_c12200c2b472db1a` was assigned to `worker-r26-centos`; the final node list showed both Worker and Portal `active/healthy`.

## Resource guard

The active guard collected 133 samples from Portal boot through final cleanup. Minimums were host RAM 2158 MiB, host free disk 41.33 GiB, Admin RAM 337 MiB, Worker RAM 429 MiB, and Portal RAM 432 MiB. Advisory warnings occurred when host available RAM was below 3 GiB or a guest below 512 MiB. No host/guest stop floor was crossed and the guard requested zero shutdowns. The minimum host margin above its 2 GiB stop floor was about 110 MiB; no additional workload was started after that sample.

## Scope

This PASS is for the R26 CentOS Stream 10 Multi-Node runtime cell. No product/package/source-pin changes occurred. The separate #307 security checklist remains open for completion; this runtime cell does not claim Gold status.
