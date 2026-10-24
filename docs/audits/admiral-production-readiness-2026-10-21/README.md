# Admiral release validation — x86_64

Audit ID: `ADM-AUDIT-2026-10-21`. The active release gate covers Rocky Linux 10, CentOS Stream 10 and Fedora Rawhide on x86_64, each in Single-Node and Multi-Node modes (six cells). Every Multi-Node cell uses three real guests of the same OS: one admin node and two workers.

## Active candidate — Release 74

**Release 74 is built; matrix status is 3/6 complete cells PASS.** Rocky Linux 10, CentOS Stream 10 and Fedora Rawhide each passed the Single-Node functional gate together on fresh VMs. Rocky Multi-Node has seven scoped scenarios passed on three real guests, but its full cell remains incomplete; CentOS Stream and Fedora Rawhide Multi-Node remain NOT TESTED. Candidate identity and Single-Node evidence are in [`release74-single-node.md`](evidence/release74-single-node.md) and [`release74-single-node-rerun-20261024.md`](evidence/release74-single-node-rerun-20261024.md). Rocky's scoped Multi-Node runs, limitations and hashes are in [`release74-rocky-multinode-progress-20261024.md`](evidence/release74-rocky-multinode-progress-20261024.md). The active checklist is tracked in [master issue #277](https://github.com/admiral-project/admiral/issues/277).

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

Release 74 cell results apply only to the exact R74 source and native RPM sets in the linked evidence. A functional cell pass does not certify all production security, resilience or performance properties. Reproduction scripts for this pass are in [`scripts/r74/`](scripts/r74/).
