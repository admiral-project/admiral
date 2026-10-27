# Open issue triage — RC6 Epoch 5 Release 18

Snapshot checked on 2026-10-27 16:28 UTC. GitHub has **6 open root issues**.
Release 18 is built and signed, but has no counted runtime matrix cells and is
not Gold.

| Issue | Status on Release 18 | Remaining acceptance |
| --- | --- | --- |
| [#106](https://github.com/admiral-project/admiral/issues/106) | Open. No verified PayPal sandbox transaction or complete billing lifecycle evidence. | Complete the sandbox checkout, signed/fresh/idempotent webhook, provisioning, lifecycle, cancellation and refund flow with sandbox credentials. |
| [#255](https://github.com/admiral-project/admiral/issues/255) | Open. Source fix and database-backed tests pass; R17 had no accepted live migration timeline, and R18 has not had a real Multi-Node cutover. | Run a real restore/cutover, show operation state never regresses to `queued`, and preserve the logical instance ID. |
| [#271](https://github.com/admiral-project/admiral/issues/271) | Open. Redirect fix is in the selected Fleet source and its unit tests pass; no R18 exact-package matrix probes have run. | Verify redirect rejection on the exact R18 packages in the required six runtime cells. |
| [#304](https://github.com/admiral-project/admiral/issues/304) | Open. Source/configuration changes are built in R18; no public-IPv6 end-to-end run has been performed. The lab has no routed public IPv6. | Validate Admin dual-stack with public-IPv6-only Worker and Portal, private IPv4 WireGuard overlay, exposure negatives, reboot, lifecycle, backup/restore and cleanup. |
| [#305](https://github.com/admiral-project/admiral/issues/305) | Open. Local app-definition checks are not runtime lifecycle evidence. The requested 7 GiB guest cannot be allocated safely on this host. | Run setup, pause, restart, backup and restore for all examples on the requested guest. |
| [#307](https://github.com/admiral-project/admiral/issues/307) | Open again because the expected A–L security verification is incomplete. Focused regressions found no confirmed issue in the paths tested, but this is not a checklist pass. | Complete or validly reuse evidence for architecture, two-customer same-Worker isolation, SELinux/storage, Quadlet, user manager, Fleet, effective Ansible baseline, network exposure, secrets/backups and tenant authorization. Perform the proportionate three-node validation. |

## Gate status

- Release 18 package build/signature gate: **PASS, 12/12 RPMs signed and
  verified**.
- Component source CI and latest root harness CI: **PASS**.
- Runtime release matrix: **0/6**.
- Issues closed since the preceding R17 triage snapshot: **0**.
- Gold: **NO**. Open issues and missing runtime cells block the release.

The current host snapshot is 5.2 GiB available RAM, 48 GiB free disk, and no
validation VMs running. Do not interpret a successful build or source CI as
end-to-end, security-isolation, IPv6, or package-install runtime evidence.
