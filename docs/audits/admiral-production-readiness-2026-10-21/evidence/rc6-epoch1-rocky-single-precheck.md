# RC6 local Epoch precheck — Rocky Linux 10 Single-Node

Date: 2026-10-25 UTC
Result: **PASS for local iteration; NOT a release-matrix cell**

## Candidate and environment

- Candidate payload: Admiral `0.0.1rc6-1.el10`, built with temporary RPM Epoch 1.
- Purpose: exercise the current fixes locally while keeping package ordering above
  earlier local RPMs. These RPMs are not publishable and do not count toward RC6.
- OS: Rocky Linux 10.2 x86_64, clone `rc6-epoch1-rocky-sn-439` from the updated
  Rocky validation seed.
- VM address: `192.168.122.125`.
- Root audit commit used by the runner: `4392031e8c1440bd128becf06dde63909c0822fc`
  (CI run [40162892881](https://github.com/admiral-project/admiral/actions/runs/40162892881), green).
- Component refs: admirald `51e2a5b6f1da7e2cb568e94b6d1836eba058e422`, Fleet
  `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`, admiralctl
  `fa2a65e866310bd82bea78859804b6c3aea7989a`, Flagship
  `b7325bbc71fc474a521496e593b2967e4d555ac1`, Harbor
  `034924d23016a1fda48716c29528076378cf934e`.
- All six RPM `%check` phases passed in the local native Rocky build. The NEVRA,
  SHA-256 values and source pins are recorded in the ignored local artifact
  directory `packaging/build/local-epoch1-rc6-el10-x86_64/`.

## Installation evidence

The clean guest installation completed at `2026-10-25T04:51:01Z` in 288 seconds.
Ansible reported 231 tasks, 94 changed, 0 unreachable and 0 failed. The local
repository was copied to the guest before firewall hardening and used via
`file://`; the Python helper RPM baseline was unchanged. The six installed
Admiral RPMs all reported Epoch 1, version `0.0.1rc6`, release `1.el10`.

The first install attempt using an HTTP repository on host port 8787 failed
because the secure guest's egress policy prevented DNF from refreshing that
repository after firewall setup. That failure is retained in the restricted
lab evidence. The harness now stages the repository before hardening; this
retry used a fresh guest and completed successfully.

## Executed functional stages

All six stages completed on the same guest between `04:51:07Z` and `04:55:29Z`:

| Stage | Result | Evidence observed |
| --- | --- | --- |
| Workload create, idempotent replay, deprovision | PASS | Replay returned the same operation and instance IDs; deprovision left no matching containers, pods, volumes, Quadlet units or files. |
| Resize and data continuity | PASS | Small → medium → small; health/HTTP stayed successful and the SQL marker persisted. |
| Backup, restore and negative state | PASS | Restore while running returned HTTP 409; paused restore succeeded, restored the original SQL marker, and deleted backup artifact was absent while its tombstone remained. |
| Instance and control-plane lifecycle | PASS | Pause, resume, stop, start, restart and Admirald stop/start checks completed; CLI failed while the service was stopped and recovered afterward. |
| Host reboot persistence | PASS | Boot ID changed; the workload recovered healthy/available and its SQL marker persisted after reboot. |
| Final services, resources and RPMs | PASS | No failed systemd units; six exact Epoch/version/release checks passed; no remaining rootless containers, pods or volumes. |

Runner result: `single_node_lane=os:rocky result:PASS failed_stages:0`.

## Reproduction and raw evidence

The source harness is `scripts/rc6/run-single-lane.sh`, with its invoked scripts
in the same directory. Reproduction command:

```bash
RC6_EXPECTED_EPOCH=1 \
RC6_RUNTIME_ROOT=/var/lib/libvirt/images/admiral-validation/evidence/rc6-epoch1-439 \
RC6_SSH_KEY=/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519 \
RC6_KNOWN_HOSTS_DIR=/var/lib/libvirt/images/admiral-validation/cloud-init \
bash docs/audits/admiral-production-readiness-2026-10-21/scripts/rc6/run-single-lane.sh \
  rocky 192.168.122.125 rc6-epoch1-rocky-sn-439
```

Restricted raw lab logs (not copied into this repository) are stored at:

- `/var/lib/libvirt/images/admiral-validation/evidence/rc6-epoch1/rocky/install-single-node-retry.log`
- `/var/lib/libvirt/images/admiral-validation/evidence/rc6-epoch1/rocky/install-single-node-439.log`
- `/var/lib/libvirt/images/admiral-validation/evidence/rc6-epoch1-439/functional/rocky-single/lane.log`
- RPM metadata and SHA-256 manifest: `packaging/build/local-epoch1-rc6-el10-x86_64/repo/RPM-MANIFEST.tsv`

## Limitations

This is one functional precheck against an Epoch-tagged local build. It does not
validate the final no-Epoch RPM set, another OS, independent portal behavior,
Multi-Node behavior, security isolation, stress limits, or failure injection.
The formal active matrix remains **0/6** until every cell passes on the same
final unmodified-spec RC6 candidate and every linked actionable issue has its
required evidence.
