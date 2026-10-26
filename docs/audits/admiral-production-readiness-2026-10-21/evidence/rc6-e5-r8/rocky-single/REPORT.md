# RC6 Epoch 5 / Release 8 — Rocky Linux 10 Single-Node

**Result: PASS (1/6 formal release cells).** Tested 2026-10-26 on a fresh
Rocky Linux 10.2 x86_64 KVM guest using the frozen `rc6-e5-r8` local repository.

## Candidate identity

- Candidate: `rc6-e5-r8`, version `0.0.1rc6`, Epoch `5`, Release `8`.
- The six installed NEVRAs and RPM SHA-256 values are in the parent
  [`el10/RPM-MANIFEST.tsv`](../el10/RPM-MANIFEST.tsv).
- DNF used the signed local EL10 repository and installed one OS dependency
  (`acl`) alongside the six Admiral RPMs. The install log records the exact
  DNF transaction, GPG key fingerprint, and Ansible recap.
- Guest: `rc6r8-rocky-single`, 2 vCPU, 2 GiB RAM, booted from
  `Rocky-10.2-seed-20261025-rc6-updated.x86_64.qcow2`.
- Secure installer: `admiral-install --single-node --validation-seed`;
  Ansible reported `ok=233 changed=97 unreachable=0 failed=0`.
- Installer evidence: `install.log`, SHA-256
  `c3c582b2302f583cc6fb83cdef27a8696d8022414a58e4006d8a05cddb4ea2d1`.

## Checklist results

The complete Single-Node runner passed all six stages:

1. Workload create, same-key idempotency replay, and clean deprovision.
2. Resize small → medium → small with HTTP 200 and SQL marker continuity.
3. Database backup checksum, rejection of restore while running, paused
   restore, marker recovery, and clean deprovision.
4. Pause/resume, stop/start, restart, and Admirald stop/start recovery.
5. Real VM reboot with changed boot ID; services and workload returned to
   healthy/available, HTTP 200, and persisted SQL marker; clean deprovision.
6. Final service, resource, and package checks: no failed systemd units, no
   rootless containers/pods/volumes, and all six packages still at Epoch 5 /
   Release 8.

The runner reported `single_node_lane=os:rocky result:PASS failed_stages:0`.
Full transcript: `lane.log`, SHA-256
`0bc3619210f3d440d06b3f9eaf99d1c76a142c9a7f3e6683053902ac7f8565ab`.

This result credits only Rocky Linux 10 x86_64 Single-Node. The other five
matrix cells remain pending; this report does not declare the release Gold.
