# Issue #285 — Single-Node runner worker identity

**Result: targeted regression passes on the Epoch 3 / Release 5 diagnostic candidate for Rocky Linux 10.2 and Fedora Rawhide 46.** This harness-only issue receives issue-specific evidence; no release matrix cell is credited.

## Fix and candidate identity

- Minimal runner fix: derive the local worker ID from the supplied guest hostname (`node_id="$guest_name"`) in `scripts/rc6/run-single-lane.sh`.
- The corrected complete lanes ran on root commit `20e5e5febd4a2d3d64d9ba69412236d9f14fb324`, the same commit pinned by the diagnostic candidate. The current branch has no changes to either relevant runner since that commit; the script blob is `a3766bf73ea54aa9be954f99fde2c5c4b3335e8b`.
- Candidate: `0.0.1rc6-5`, RPM Epoch 3. Component pins: admirald `421c6007f9cf51a7e3bf23a6e2173bb0a39e27d3`, fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`, admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`, flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`, harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- RPM SHA-256 manifests: [`EL10`](../rc6-epoch3-issue-260/RPM-MANIFEST-el10.tsv) and [`Fedora`](../rc6-epoch3-issue-260/RPM-MANIFEST-fedora.tsv).

## Reproduction and observations

The retained pre-fix Release 1 logs show the lifecycle stage aborting before workload creation with `expected exactly one worker node 'rc6-r1-<os>-sn'; found 0`. The OS installer had registered the worker under the actual guest hostname.

The corrected Release 5 full lanes used guests `rc6e3-rocky-sn` and `rc6e3-fedora-sn`. In each run the runner selected that exact hostname as `node`, the API returned one active, healthy, available worker with the same ID, and workload create/idempotency replay/deprovision passed. The remaining five stages also passed: resize/data continuity, backup/restore/checksum and negative state, service lifecycle, reboot persistence, and final exact RPM/resource checks.

| OS | Corrected lane | Lane SHA-256 | Result |
|---|---|---|---|
| Rocky Linux 10.2 x86_64 | `passed-e3r5/rocky-single-lane.log` | `53f8d99194c34c1924139ff554fbd2daece32ab83a0fabf8b09647ac40586f7a` | all 6 stages PASS |
| Fedora Rawhide 46 x86_64 | `passed-e3r5/fedora-single-lane.log` | `48ee146ae7e52db29956600b6af9b1d3bbf17e490456c17e034621db7a5f8c9d` | all 6 stages PASS |

The pre-fix logs are from Release 1; the corrected regression runs use Release 5. They are not a same-candidate before/after comparison. The failure is confined to the audit runner's expected ID, and the corrected runner passed the full lifecycle on the current diagnostic package set. Epoch-bearing results remain diagnostic only and earn no release matrix credit.
