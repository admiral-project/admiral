# Issue #260 — declared PostgreSQL outage and recovery

**Disposition: targeted diagnostic acceptance passed on Rocky Linux 10.2 and Fedora Rawhide x86_64.** Issue #260 remains open pending validation on the final no-Epoch candidate and the remaining required release environments. These runs do not count as matrix cells.

## Candidate and environment

- Package set: `Epoch 3 / 0.0.1rc6 / Release 5`.
- Rocky NEVRAs: `3:admiral-common-0.0.1rc6-5.el10`, `3:admiral-flagship-0.0.1rc6-5.el10`, `3:admiral-harbor-0.0.1rc6-5.el10` (noarch); `3:admirald-0.0.1rc6-5.el10`, `3:admiral-fleet-0.0.1rc6-5.el10`, `3:admiralctl-0.0.1rc6-5.el10` (x86_64).
- Fedora NEVRAs: same six package names at `3:<name>-0.0.1rc6-5.fc46`.
- Exact package names, architectures, Epoch, Release and SHA-256: [EL10 manifest](RPM-MANIFEST-el10.tsv), [Fedora manifest](RPM-MANIFEST-fedora.tsv).
- Relevant packaged Fleet source: `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` (includes the five-second declared-workload health reconciliation).
- Test harness root checkout at execution: `20e5e5febd4a2d3d64d9ba69412236d9f14fb324`.
- Guests: `rc6e3-rocky-sn` (`192.168.122.153`) and `rc6e3-fedora-sn` (`192.168.122.154`), each on a fresh overlay of the updated x86_64 seed.

## Procedure and acceptance

The reproducible procedure is `scripts/rc6/issue-260-single.sh`, which invokes `scripts/r69/r69-single-db-service-outage-60s.sh`. It provisions the DB-backed fixture, verifies healthy/available and PostgreSQL readiness, writes a SQL marker, waits for a fresh healthy Fleet report, then stops the declared PostgreSQL systemd user unit. During the outage, the guest samples the unit and Podman container every second and launches an API observation every second for 61 samples spanning at least 60 seconds. It then restarts PostgreSQL, verifies API recovery and SQL marker persistence, deprovisions, and checks that no workload containers remain.

Acceptance was evaluated against timestamps measured from the confirmed unit stop: Admiral must leave `healthy/available` within one five-second health tick and must not return to it during the outage. Two runs were phase-aligned by waiting for a new healthy Fleet report immediately before stopping PostgreSQL.

## Results

| Guest/run | Samples / elapsed | First unavailable API observation | Healthy at or after 5 s | Recovery, marker, cleanup |
|---|---:|---:|---:|---|
| Rocky, `rocky-ms60` | 61 / 60,032 ms | 1,036 ms | 0 | PASS |
| Fedora, `fedora-ms60` | 61 / 60,015 ms | 8 ms | 0 | PASS |
| Rocky, phase-aligned `rocky-worst1` | 61 / 60,016 ms | 2,025 ms | 0 | PASS |
| Fedora, phase-aligned `fedora-worst2` | 61 / 60,022 ms | 3,011 ms | 0 | PASS |

Every successful run observed the DB unit inactive and PostgreSQL container absent while reporting unavailable. PostgreSQL returned to accepting connections, the marker `r69-db-outage-persisted` remained, deprovision returned success, and the instance's containers were absent after cleanup.

The full per-second logs and their SHA-256 values are:

- `rocky-ms60/outage-recovery.log` — `a69fee62e6e6c6d2d872b09eeee384e17570bc2b6abb196ddd4291721c9df967`
- `fedora-ms60/outage-recovery.log` — `b43e7b67f5110835a022d8ccb0cfed2dd38069f6f2dcc91bbacf7feb3d15aa7c`
- `rocky-worst1/outage-recovery.log` — `437686f189256b93a110d144fd27f327b8783860558bca6ec0be2353f019ddf2`
- `fedora-worst2/outage-recovery.log` — `cb001282ce908d0dfa8a973a936c7ceefc6f3e439ed917e13f7a631e29190165`

Each run directory also contains `SHA256SUMS`. Earlier 55-second or sequential-sampling attempts are retained as exploratory evidence but excluded from this verdict because they did not meet the current 61-sample, one-second cadence. One Fedora setup attempt failed to establish a fresh healthy baseline; the helper trap deprovisioned it, and it was excluded and rerun.

## Validation scope

This demonstrates the #260 issue-specific outage/recovery behavior on two diagnostic RPM installs. It is **not** a release-matrix pass: the active matrix remains 0/6 until the same final no-Epoch candidate passes Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide in both Single-Node and the required Admin + Worker + independent Portal Multi-Node topology.
