# RC5 Release 73 candidate record

**Historical R73 status before the Python dependency refresh: 4/8 PASS, 3/8 PARTIAL, 1/8 NOT TESTED. Superseded by Release 75:** the eight refreshed Python helper packages were published from COPR builds 11202990–11202997, the coordinated Admiral set from 11203001–11203006, and the `0.0.1rc5-75` candidate passed 6/6 active cells (Fedora Rawhide, Rocky Linux 10 and CentOS Stream 10 × Single/Multi-Node). AlmaLinux 10 is Tier 2 and outside the active matrix ([#276](https://github.com/admiral-project/admiral/issues/276)). See [`RELEASE75_VALIDATION_CLOSURE.md`](../RELEASE75_VALIDATION_CLOSURE.md). The refresh itself fixed SQLAlchemy's missing pinned `typing-extensions` build requirement; details remain in [`python-dependency-refresh-20261024.md`](python-dependency-refresh-20261024.md). Do not use the historical R73 matrix as evidence for the refreshed dependency set.

## Scope

Four x86_64 operating systems: Fedora Rawhide, Rocky Linux 10, AlmaLinux 10 and CentOS Stream 10. Each must pass both Single-Node and a real three-guest Multi-Node cell. Fedora receives only native `.fc46` RPMs; the three EL10 systems receive native `.el10` RPMs. No `--nodeps` installation is permitted.

## Selected component refs

The root repository fetched every component `origin/main` before preparing R73. Each selected component SHA below matched its `origin/main`; the source fix in `admirald` is included.

| Repository | Selected SHA | CI |
|---|---|---|
| `admirald` | `83b4dd4db8963ac40a51c00fb9e52a9f2081df5c` | [40080443575](https://github.com/admiral-project/admirald/actions/runs/40080443575), success |
| `admiral-fleet` | `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` | [40069777965](https://github.com/admiral-project/admiral-fleet/actions/runs/40069777965), success |
| `admiralctl` | `fa2a65e866310bd82bea78859804b6c3aea7989a` | [40030034925](https://github.com/admiral-project/admiralctl/actions/runs/40030034925), success |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | [39795263415](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415), success |
| `admiral-harbor` | `dd39e9a74bf658ecf6fd6e9f8bd30b2ddf82d7db` | [39795262318](https://github.com/admiral-project/admiral-harbor/actions/runs/39795262318), success |

## Candidate contents

- Six coordinated Admiral RPMs at `0.0.1rc5-73`.
- #272 fix: controlled worker removal revokes its live and persistent WireGuard peer through a local systemd socket helper before deleting the node record and token. Failed revocation retains the database record/token for retry. Peer addition shares the same lock and confirms the node is still registered.
- `admirald` remains unprivileged; only the root helper service receives `CAP_NET_ADMIN`.
- Every package source ref is pinned to the selected component `origin/main`; the common installer payload is pinned to the root commit recorded after package preparation.

## Build and CI checks

- `go test ./...`, `go test -race ./...` and `go vet ./...` in `admirald`: PASS. The GitHub CI run also passed its PostgreSQL-backed tests.
- All root `scripts/test_*.py` suites: PASS, including installer (76 tests), WireGuard peer add (3), peer revoke (6), and WireGuard role regressions (12).
- `bash -n scripts/install.sh`, Python compilation, Ansible syntax checks for `ansible/site.yml` and `ansible/wireguard-peers.yml`, and staged `systemd-analyze verify`: PASS.
- The first root CI run [40080856232](https://github.com/admiral-project/admiral/actions/runs/40080856232) exposed stale Release 72 defaults in three audit helpers and test fixtures that assumed CI ran as root. Both issues were corrected before the R73 build. Follow-up root CI [40081018598](https://github.com/admiral-project/admiral/actions/runs/40081018598) passed.
- `python3 scripts/validate-release-refs.py`: PASS on root commit `d84c130380ca5db3f73c32762c5f38bcccd75a10`.
- Six coordinated Release 73 RPMs were built for EL10 and Fedora Rawhide. Rocky runtime installs confirmed the exact `.el10` NEVRAs; the four Single-Node runs confirmed their native OS package set. RPM payloads were not changed during runtime validation.
- Rocky seed freshness was rechecked from a fresh clone at 2026-10-24T13:18:39Z: `dnf --refresh check-update` returned 0 with no updates. The seed has the R73 Python dependency set and the Admiral COPR, EPEL, CRB and local signed candidate repositories enabled. Seed hash, package inventory and raw evidence hashes: [`release73-rocky-seed-freshness.md`](release73-rocky-seed-freshness.md).
- CI passed for all five selected component SHAs listed above. See run links in the progress reports; no CI status here is inferred from source inspection.

## Runtime matrix

For the pre-refresh R73 dependency set, four Single-Node cells passed their functional checklist. Rocky, AlmaLinux and CentOS Stream had scoped three-guest runtime evidence; none of the three Multi-Node cells was complete. Historical result: **4/8 PASS, 3/8 PARTIAL, 1/8 NOT TESTED**. These reports do not give cell credit to the refreshed dependency set (currently 0/8). See [`release73-rocky-multinode-progress.md`](release73-rocky-multinode-progress.md), [`release73-alma-multinode-progress.md`](release73-alma-multinode-progress.md), [`release73-centos-multinode-progress.md`](release73-centos-multinode-progress.md), and the acceptance checklist in master issue [#200](https://github.com/admiral-project/admiral/issues/200).

| Platform | Single-Node | Multi-Node |
|---|---|---|
| Fedora Rawhide x86_64 | PASS | NOT TESTED |
| Rocky Linux 10 x86_64 | PASS | PARTIAL — scoped scenarios passed; cell incomplete |
| AlmaLinux 10 x86_64 | PASS | PARTIAL — scoped scenarios passed; cell incomplete |
| CentOS Stream 10 x86_64 | PASS | PARTIAL — both-worker install/placement, same-key concurrency and reboot recovery on both workers passed; remaining cell scenarios outstanding |
