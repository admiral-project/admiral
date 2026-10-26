# RC6 Epoch 5 / Release 8 — CentOS Stream 10 Single-Node

**Result: PASS (3/6 formal release cells).** Tested 2026-10-26 on a fresh
CentOS Stream 10 x86_64 KVM guest using the signed, frozen `rc6-e5-r8` EL10
repository.

## Candidate identity

- Candidate: `rc6-e5-r8`, version `0.0.1rc6`, Epoch `5`, Release `8`.
- The six installed NEVRAs and SHA-256 values are recorded in
  [`el10/RPM-MANIFEST.tsv`](../el10/RPM-MANIFEST.tsv); final package checks
  confirmed all six remained at Epoch 5 / Release 8.
- Guest: `rc6r8-centos-single`, 2 vCPU, 2 GiB RAM, booted from
  `CentOS-Stream-10-seed-20261025-rc6-updated.x86_64.qcow2`.
- DNF used the signed local EL10 repository and installed the six candidate
  packages without `--nodeps` or cross-distribution RPMs.
- Secure installer: `admiral-install --single-node --validation-seed`;
  Ansible reported `ok=232 changed=97 unreachable=0 failed=0`.
- Installer transcript: `install.log`, SHA-256
  `5b21060d4c0f4c3ef15239b5bbe80041d8040dec9db87f85b35a1b89c9e24c2b`.

## Checklist results

The complete Single-Node runner passed all six stages:

1. Real workload provision, same-key idempotency replay, HTTP 200, and clean
   deprovision.
2. Small → medium → small resize with HTTP 200 and SQL marker continuity.
3. Database backup checksum, rejected restore while running, paused restore,
   marker recovery, and clean deprovision.
4. Pause/resume, stop/start, restart, and Admirald stop/start recovery.
5. Real guest reboot with a changed boot ID; services and workload recovered
   to healthy/available, returned HTTP 200, and preserved the SQL marker.
6. Final service, resource, and package checks: no failed systemd units, no
   rootless containers/pods/volumes, and all six packages remained at Epoch 5 /
   Release 8.

The runner reported `single_node_lane=os:centos result:PASS failed_stages:0`.
Full transcript: `lane.log`, SHA-256
`ff021b200f3fe79eaa7c755734943586711e0ef0ec4c1e637098131742134f0d`.

This result credits only CentOS Stream 10 x86_64 Single-Node. Three matrix
cells remain pending; this report does not declare the release Gold.
