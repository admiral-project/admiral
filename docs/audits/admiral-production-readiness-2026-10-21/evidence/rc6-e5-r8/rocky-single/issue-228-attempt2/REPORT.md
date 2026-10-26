# Issue #228 — Rocky Linux 10 Single-Node on RC6 R8

**Result: PASS for the Single-Node half.** Candidate `rc6-e5-r8` installed all
six Epoch 5 / Release 8 RPMs from the signed EL10 repo. Package identity and
hashes are in `../../el10/RPM-MANIFEST.tsv`; the fresh installation
and six-cell Single-Node run are documented in `../REPORT.md`.

On 2026-10-26, instance `inst_5d1a7b0052380cc9` was provisioned on
`rc6r8-rocky-single`. A temporary wrapper injected exit 42 for the instance's
`podman rm`, `podman pod rm`, and `podman volume rm` calls. The first
deprovision operation `op_b9c9fa590f6c2363` returned **failed**, preserving the
stopped/unavailable instance, infra container, pod, database volume, Quadlet
units, and instance files. The transcript records the injected calls and
operation error.

The wrapper exit trap restored `/usr/bin/podman` to its original SHA-256
`e84e97e99038d6a40acdd02b6ca77faa57f20525aff82a8566172bdc2d2ebcfb` and mode
`root:root:755`. Retry operation `op_d5030e614a37857c` then succeeded, and the
final inventory had no containers, pods, volumes, Quadlets, or instance files.

Evidence:

- `provision.json`, `deprovision-injected.json`, `deprovision-retry.json`
- `wrapper.log`, `fault-recovery.log`, `residual-state-and-restoration.log`,
  `retry-and-cleanup.log`

Harness notes: the initial invocation stopped before provisioning because the
fixture had not been uploaded. In the next invocation, the product operation
completed with the expected failure, but the follow-up harness assertion used
an unsupported `instances show --output` option and ran rootless inspection
from an inaccessible working directory. The shell trap restored Podman. The
corrected checks resumed against the same failed operation and preserved
resources; they verified the SHA-256, retried deprovision, and confirmed empty
final inventories. These were harness-only issues and did not invalidate R8.

This validates only Rocky Linux 10 Single-Node for #228. Worker Multi-Node
injection remains required before the issue can close.
