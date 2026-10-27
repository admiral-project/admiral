# R17 open-issue runtime validation — 2026-10-27

This report records issue-specific probes performed against the unchanged RC6
Epoch 5 / Release 17 product payload. These probes do not complete or credit a
release-matrix cell. The full six-cell matrix remains 0/6.

## Candidate identity

- Root candidate commit: `7a0796ddb898a55e0007a473cd9ea706cd2ecd1f`.
- `admiral-common` payload: `ba59c45d647bd354c878d7e61497896746a88c2b`.
- Rocky Linux 10.2 x86_64 runtime guests used the exact native EL10 Release 17
  packages (`0.0.1rc6-17.el10`); the Single-Node guest had all six RPMs
  installed. Package manifests and hashes remain under this candidate's
  `el10/` evidence directory and in each raw runtime folder.
- Root CI run [40497925910](https://github.com/admiral-project/admiral/actions/runs/40497925910)
  and the pinned component CI runs were green before these docs-only evidence
  edits. No product source or package changed during these probes.

## #228 — fail deprovision if managed Podman resources remain

Post-fix fault injection passed on both Rocky topologies. In Single-Node,
instance `inst_8b01b676dbc36607` had nine managed Podman deletion failures
injected across pod, container, and volume cleanup. Deprovision operation
`op_3c13d218cdf04846` correctly returned `failed`; Admiral retained the stopped,
unavailable instance and its retry state, while the infra container, pod, and
PostgreSQL volume remained visible. In Multi-Node, instance
`inst_62c55f08e8f91c0c` and operation `op_284363742d82b0a6` showed the same
fail-closed result on the registered Worker.

After the fault wrapper was removed, `/usr/bin/podman` matched its pre-test
SHA-256 byte-for-byte on both Workers. Retry operations
`op_cb92dc1c71d6f84c` (Single-Node) and `op_1ac2525d1f651cc0` (Multi-Node)
succeeded. Each instance became deprovisioned, Podman container/pod/volume
inventories were empty, and no instance metadata residue remained.

Clean deprovision controls also passed in both topologies. Operations
`op_b0c8a267631a2e90` and `op_0c376f1aa1e76178` succeeded without injection;
their test instances ended deprovisioned with empty resource inventories.

Raw logs, operation JSON, snapshots, harnesses, and per-directory SHA-256
manifests:

- [Single-Node fault injection](runtime/issue-228-r17-rocky-sn-20261027/REPORT.md)
- [Multi-Node fault injection](runtime/issue-228-r17-rocky-mn-20261027T145000Z/REPORT.md)
- [Single-Node clean control](runtime/issue-228-control-r17-rocky-sn-20261027/)
- [Multi-Node clean control](runtime/issue-228-control-r17-rocky-mn-20261027/)

## #271 — prevent HTTP health probes from following redirects

The exact R17 Rocky Single-Node probe passed for redirects to loopback and the
worker's `10.77.0.140` address. Both workloads stayed `healthy/available` over
at least two updated periodic health reports per variant; each redirect target
received zero requests. Both instances were deprovisioned and the Podman
inventory was empty afterward.

The exact R17 Rocky Multi-Node probe also passed for loopback and the Worker
address, with zero redirected requests, healthy/available state across
periodic reports, successful deprovision, and empty cleanup inventory.

- [Rocky Single-Node raw evidence](runtime/issue-271-r17-rocky-mn-20261027t135432z-1847299/)
- [Rocky Multi-Node raw evidence](runtime/issue-271-r17-rocky-mn-20261027t131756z-1819516/)

The Single-Node directory basename contains the mistaken legacy `rocky-mn`
run-tag. The captured run log declares `topology=rocky-single-node`; its SSH
helpers both target the same installed Single-Node guest, and its baseline and
provision assertions identify `rc6e5r17-rocky-single`. The archived script is
the exact script used. A correction note is included in that directory. The
source harness now generates the correct `rocky-sn` tag.

**Still open:** the issue review also requires the exact R17 CentOS Stream
Multi-Node context. That cell-specific probe has not been run, so #271 remains
open.

## #294 — reconcile stale node health before serving

The exact R17 Rocky Single-Node and Multi-Node startup probes both passed. On
each topology, Fleet and `admirald` were stopped for 125 seconds. `admirald`
was restarted while Fleet remained stopped; before a fresh Fleet report, the
persisted worker was `offline/degraded`, unavailable for provisioning, and
still showed the pre-stop metrics/heartbeat timestamp. Restarting Fleet
restored `active/healthy/available` with a fresh metrics timestamp.

- [Rocky Single-Node raw evidence](runtime/issue-294-r17-rocky-single-20261027/)
- [Rocky Multi-Node raw evidence](runtime/issue-294-r17-multinode-20261027/)

All accepted runtime directories contain SHA-256 manifests. The validation
triage records open issue state and remaining release gates; this report does
not declare Gold.
