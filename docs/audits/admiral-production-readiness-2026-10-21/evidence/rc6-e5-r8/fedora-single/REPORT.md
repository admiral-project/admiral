# RC6 Epoch 5 / Release 8 — Fedora Rawhide Single-Node

**Result: PASS (2/6 formal release cells).** Tested 2026-10-26 on a fresh
Fedora Rawhide x86_64 KVM guest using the signed, frozen `rc6-e5-r8` repository.

## Candidate identity

- Candidate: `rc6-e5-r8`, version `0.0.1rc6`, Epoch `5`, Release `8`.
- The installed Fedora packages use native `.fc46` builds. All six final
  NEVRAs match `fedora/RPM-MANIFEST.tsv`; the final runner checked the exact
  epoch, version, release, and Fedora dist tag.
- Guest: `rc6r8-fedora-single`, 2 vCPU, 2 GiB RAM, booted from
  `Fedora-Rawhide-seed-20261025-rc6-updated.x86_64.qcow2`.
- DNF used the signed local Fedora repository, imported the recorded
  validation key, and installed only Fedora-native Admiral RPMs. No EL10 RPMs
  were used or forced onto Fedora.
- Secure installer: `admiral-install --single-node --validation-seed`;
  Ansible reported `ok=239 changed=99 unreachable=0 failed=0`.
- Installer transcript: `install.log`, SHA-256
  `9f6e02cdffead9430f411beabe6a76c288fe644df26eb232c094087aa266a31b`.

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
   Release 8 `.fc46`.

The runner reported `single_node_lane=os:fedora result:PASS failed_stages:0`.
Full transcript: `lane.log`, SHA-256
`6084e67b5c690b0952c3ea0e98db0781a88d20405e71467fae5e3c222d70486b`.

This result credits only Fedora Rawhide x86_64 Single-Node. Four matrix cells
remain pending; this report does not declare the release Gold.
