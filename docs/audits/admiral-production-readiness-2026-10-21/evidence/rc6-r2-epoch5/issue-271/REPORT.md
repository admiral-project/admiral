# Issue #271 — RC6 Epoch 5 / Release 2 reproduction

Date: 2026-10-26 UTC
Result: **PASS on Rocky Linux 10.2 and Fedora Rawhide 46 x86_64**
Candidate: Admiral `Epoch 5: 0.0.1rc6-2`; root commit `e710237fd908feabf17b12fb61d08429deb21e52`.

## Candidate identity

Each guest had the six native packages installed at `5:0.0.1rc6-2` before testing. Rocky used `.el10` RPMs and Fedora used `.fc46` RPMs. Selected component pins:

- admirald `aec9914c5909af7f66407b6c3dd0822576cc66dc`
- admiral-fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`
- admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`
- admiral-flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`
- admiral-harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`

## Procedure and observed result

Ran the tracked `scripts/rc6/issue-271-single.sh` once on each freshly booted Epoch5/R2 Single-Node guest. The test installed a disposable HTTP health-check workload declaring status 302 and redirected to a listener outside the workload. It tested both `127.0.0.1` and the guest address, required at least two periodic Fleet health reports per variant, then deprovisioned and checked that no matching rootless Podman container remained.

| OS / VM | Run tag | Result |
|---|---|---|
| Rocky Linux 10.2 x86_64 / `rc6r2-rocky-sn` (`192.168.122.199`) | `r2rocky271a` | PASS; both redirect variants remained healthy/available, two periodic reports each, listener received 0 requests, cleanup completed. |
| Fedora Rawhide 46 x86_64 / `rc6r2-fedora-sn` (`192.168.122.249`) | `r2fedora271a` | PASS; both redirect variants remained healthy/available, two periodic reports each, listener received 0 requests, cleanup completed. |

The raw host logs retain timestamps, instance IDs, intermediate health states, periodic report timestamps and cleanup result. Each guest archive retains app definition, import/provision/deprovision output, listener logs, and its internal checksum list.

## Evidence hashes

- Rocky `rocky-rerun/redirect-health.log`: `2abea749a68c08612f67929719bc47dd6771a618f5923c0454e6cfbebcb932eb`
- Rocky `rocky-rerun/guest-evidence.tar.gz`: `905c4355ffed98bba7485bfe5f4a071104908a69a4ee0ee5567a483197560af0`
- Fedora `fedora-rerun/redirect-health.log`: `6466937192a0551247bd39a4c59d9182fecd65fec5395ce37118165b3fa7b16e`
- Fedora `fedora-rerun/guest-evidence.tar.gz`: `e02a96a33a22ff30849ca8718e64637ec32a449f54dece0dc8d2f5353fbe44f2`

Hashes are independently recorded in each OS subdirectory's `SHA256SUMS`. This verifies the issue-specific redirect behavior for these two OSes and this exact candidate; it does not prove a complete matrix cell or the same behavior on CentOS Stream or in Multi-Node mode.
