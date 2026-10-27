# Issue #228 — RC6-E5-R17 Rocky Linux 10.2 Multi-Node

**Result: targeted Multi-Node PASS.** The exact R17 RPMs were installed on the
admin and worker guests. This is issue-specific evidence; it does not complete
the Rocky matrix cell or the six-cell release gate. The Single-Node R17 rerun
is still required before closing #228.

## Candidate and topology

- Candidate root: `7a0796ddb898a55e0007a473cd9ea706cd2ecd1f`.
- Candidate component source pins and all six package hashes:
  [`../source-pins.txt`](../../source-pins.txt) and the R17 EL10 package
  manifest in [`../../el10/RPM-MANIFEST.tsv`](../../el10/RPM-MANIFEST.tsv).
- Admin guest: all six `0.0.1rc6-17.el10` RPMs.
- Worker: `admiral-common` and `admiral-fleet` `0.0.1rc6-17.el10`.
- The app was explicitly placed on `rc6e5r15-rocky-worker` and included a
  PostgreSQL 16 service with a persistent Podman volume.

## Fault injection and recovery

Instance `inst_62c55f08e8f91c0c` was deprovisioned while a temporary wrapper
failed only Podman deletion commands naming that instance. The first operation
`op_284363742d82b0a6` returned **failed**. Admiral kept the instance
`stopped`/`unavailable`, and the worker inventory retained the infra container,
pod, and PostgreSQL volume. The injected log records the container, pod, and
volume deletion failures.

The wrapper was removed and `/usr/bin/podman` restored byte-for-byte; both
before and after hashes are
`e84e97e99038d6a40acdd02b6ca77faa57f20525aff82a8566172bdc2d2ebcfb`.
Retry operation `op_1ac2525d1f651cc0` returned **succeeded**. The instance is
`deprovisioned`; final container, pod, volume, and instance-metadata inventories
are empty. The E2E app was deactivated after cleanup.

## Evidence

- `deprovision-injected.json`, `instances-after-injection.json` and the three
  `*-after-injection.json` files: failed state and residual resource inventory.
- `injected-commands.log`, `injection-setup.log`, `podman-before.sha256`,
  `podman-restore.log` and `podman-after-restore.sha256`: controlled fault and
  exact binary restoration.
- `deprovision-retry.json`, `instances-final.json`, the three `*-final.json`
  files and `metadata-residue-final.txt`: successful convergence and empty
  resource inventory.
- `worker-resources-before.txt`, `worker-resources-after.txt` and
  `worker-final-integrity-resources.txt`: guest capacity and service health.
- `issue-228-multinode.sh` and `e2e-whoami.yaml`: harness and workload fixture.
- `SHA256SUMS`: hashes of the evidence files in this directory.

Two earlier harness-only attempts are marked `HARNESS-NOT-COUNTED.txt` in
their own directories. Neither changed product code; the final corrected run
above passed all assertions.
