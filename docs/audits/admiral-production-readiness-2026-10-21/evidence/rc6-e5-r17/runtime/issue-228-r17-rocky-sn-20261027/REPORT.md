# Issue #228 — RC6-E5-R17 Rocky Linux 10.2 Single-Node

**Result: targeted Single-Node PASS.** The exact six EL10 R17 RPMs were
installed with the supported `admiral-install --single-node` workflow. The
separate Multi-Node R17 fault-injection run also passed. These issue-specific
probes do not count as complete release-matrix cells.

## Candidate and topology

- Candidate root: `7a0796ddb898a55e0007a473cd9ea706cd2ecd1f`.
- Component source pins and package hashes: the [R17 source pins](../../source-pins.txt),
  [EL10 package manifest](../../el10/RPM-MANIFEST.tsv), and
  [fresh Single-Node install log](../rocky-single-20261027/install.log).
- All six installed packages are `0.0.1rc6-17.el10`.
- Node ID: `rc6e5r17-rocky-single`.
- The E2E fixture ran a Traefik whoami service and PostgreSQL 16 with its
  persistent Podman volume.

## Fault injection and recovery

The deprovision command wrapper failed only Podman deletion calls naming
instance `inst_8b01b676dbc36607`. Operation `op_3c13d218cdf04846` returned
**failed**. Admiral retained the instance as `stopped` and `unavailable`; the
post-failure inventory retained an infra container, pod, and PostgreSQL volume.
The private injected-command log records nine failures across container, pod,
and volume deletion.

After removing the wrapper, `/usr/bin/podman` had the same SHA-256 before and
after restoration:
`e84e97e99038d6a40acdd02b6ca77faa57f20525aff82a8566172bdc2d2ebcfb`.
Retry `op_cb92dc1c71d6f84c` returned **succeeded**. The instance reached
`deprovisioned`; final container, pod, volume, and instance-metadata inventories
were empty. The disposable E2E app was deactivated after cleanup.

## Evidence

- `provision.json`, `deprovision-injected.json`, `instances-after-injection.json`
  and the three `*-after-injection.json` inventories.
- `injected-commands.log`, `injection-setup.log`, `podman-before.sha256`,
  `podman-restore.log` and `podman-after-restore.sha256`.
- `deprovision-retry.json`, `instances-final.json`, the three `*-final.json`
  inventories and `metadata-residue-final.txt`.
- `guest-final.log`, resource snapshots, and app deactivation/list output.
- `issue-228-r17.sh` and `e2e-whoami.yaml` preserve the corrected harness and
  fixture. `SHA256SUMS` covers files in this evidence directory.

## Resource handling

The first installer run briefly needed a 512 MiB swap file while SELinux and
security packages were being configured. After the VM was raised to 1.5 GiB
and rebooted, the temporary swap was removed before this E2E run. No swap was
active during the issue validation. The install and resource logs are under
[`../rocky-single-20261027/`](../rocky-single-20261027/).
