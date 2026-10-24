# Admiral release validation — x86_64

Audit ID: `ADM-AUDIT-2026-10-21`. The active release gate covers Rocky Linux 10, CentOS Stream 10 and Fedora Rawhide on x86_64, each in Single-Node and Multi-Node modes (six cells). Every Multi-Node cell uses three real guests of the same OS: one admin node and two workers.

## Active candidate — Release 74

**Release 74 has not been built; matrix status is 0/6.** The Release 73 candidate and earlier runtime evidence do not count toward Release 74. The six-cell checklist is tracked in [master issue #277](https://github.com/admiral-project/admiral/issues/277). Release 74 RPMs remain gated on issue triage, fixes, local tests and green CI. The successful Python dependency builds and historical R73 evidence are recorded in [dependency refresh evidence](evidence/python-dependency-refresh-20261024.md) and the [R73 candidate record](evidence/release73-candidate.md).

Earlier R73 Single-Node and Multi-Node reports remain historical, candidate-specific evidence only. Fedora must use native Fedora packages/tooling, and EL10 guests must use EL10 RPMs. Do not bypass DNF dependency resolution or cross-install binaries.

## Reports

- [Architecture review](ARCHITECTURE_REVIEW.md)
- [Test matrix](TEST_MATRIX.md)
- [Single-Node report](SINGLE_NODE_REPORT.md)
- [Multi-Node report](MULTI_NODE_REPORT.md)
- [Security review](SECURITY_REVIEW.md)
- [Resilience report](RESILIENCE_REPORT.md)
- [Performance report](PERFORMANCE_REPORT.md)
- [Findings](FINDINGS.md)
- [Production readiness](PRODUCTION_READINESS.md)

## Reproducing the lab

Run `scripts/host-preflight.sh` on the isolated KVM host. Use the updated QCOW2 seeds under `/var/lib/libvirt/images/admiral-validation/seeds/` and isolated libvirt networks. Configure the candidate repository explicitly for each test lab; repository configuration is not baked into the OS seed. `scripts/create-audit-vm.sh` creates a 2-vCPU/2-GiB guest, generates a unique Ed25519 SSH host key on the trusted host, and writes mode-0600 cloud-init and known-host files. Preserve raw evidence in the ignored validation directory with mode 0600; scan logs for credentials before copying sanitized records into this audit.

For a fresh Single-Node guest, run `scripts/install-single-node-audit.sh el10 ...` or `scripts/install-single-node-audit.sh fedora ...`. The helper installs the native candidate through normal DNF resolution and invokes `admiral-install --single-node --validation-seed`; it records install time, package NEVRA changes and the transaction. Updated seeds avoid repeating OS updates. Preserve failed attempts and do not use production services.

For each Multi-Node cell, keep the isolated underlay (`10.77.0.0/24`) separate from the WireGuard overlay (`10.99.0.0/24`). Enroll workers with `scripts/install-worker-audit.sh`, strict SSH host-key pins and the exact native candidate repository. Capture hub and worker inventories, health, workload placement on each worker, SQL markers, HTTP 200, idempotent retries, worker recovery/rejoin, controlled node removal and cleanup.

Only complete evidence from the exact R73 RPM set can pass a cell. A functional cell pass does not certify all production security, resilience or performance properties.
