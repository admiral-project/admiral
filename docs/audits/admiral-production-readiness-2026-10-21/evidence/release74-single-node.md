# Release 74 Single-Node pass — 2026-10-24

## Result

**Three of six Release 74 functional cells PASS in one coordinated pass.** The Rocky Linux 10 x86_64, CentOS Stream 10 x86_64 and Fedora Rawhide x86_64 Single-Node cells ran concurrently against fresh guest clones. Each passed the Release 74 Single-Node checklist in master issue [#277](https://github.com/admiral-project/admiral/issues/277) after correcting the noted local harness checks. The other three cells (Multi-Node on each OS) are **NOT TESTED**. No new product defect was identified. This does not mean the complete security/resilience/performance audit or production readiness passed.

A second full fresh-VM pass on the same exact Release 74 RPM candidate also passed all three Single-Node cells together after fixing the launcher script's executable bit. Its source/tooling identity, six stage results per OS, updated boot IDs and raw-log hashes are in [`release74-single-node-rerun-20261024.md`](release74-single-node-rerun-20261024.md). The rerun preserves the initial launcher and early-boot preflight failures separately; neither entered a product test. Current matrix remains 3/6 because Multi-Node is NOT TESTED.

This report distinguishes the final check result from the first harness result: Rocky and Fedora's first final cleanup probe failed to change directory from `/home/validator`, which has mode 0700. That probe did not inspect runtime state. The command was rerun from `/tmp` and passed. Fedora's functional log also contains `_reboot: command not found`, caused by the local lane script being edited while that already-running shell was reading it; the reboot test had already passed. Both raw errors are preserved. These were test harness errors, not suppressed product failures.

## Candidate and CI identity

- Root package-preparation commit: `d6e5cacb7c35807417f19b7f970c1d1f6a2d387c` (`build(rpm): prepare coordinated Release 74 set`).
- Component source pins:

| Component | Exact source SHA | CI |
|---|---|---|
| `admirald` | `83b4dd4db8963ac40a51c00fb9e52a9f2081df5c` | [success](https://github.com/admiral-project/admirald/actions/runs/40080443575) |
| `admiral-fleet` | `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` | [success](https://github.com/admiral-project/admiral-fleet/actions/runs/40069777965) |
| `admiralctl` | `fa2a65e866310bd82bea78859804b6c3aea7989a` | [success](https://github.com/admiral-project/admiralctl/actions/runs/40030034925) |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | [success](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415) |
| `admiral-harbor` | `dd39e9a74bf658ecf6fd6e9f8bd30b2ddf82d7db` | [success](https://github.com/admiral-project/admiral-harbor/actions/runs/39795262318) |

The root CI for that candidate commit passed: [Main Regression Tests](https://github.com/admiral-project/admiral/actions/runs/40120683532). `python3 scripts/validate-release-refs.py` passed against the same pins. These CI runs identify the tested source candidate; the later audit-document-only commit has its own root CI result in the GitHub tracker comment.

Six coordinated RPMs were installed per guest via the guest's native, signed local DNF repository with normal dependency resolution and GPG checking. No `--nodeps`, force, or cross-distribution RPM installation was used. Exact NEVRAs and SHA-256 values are in [`release74-el10-RPM-MANIFEST.tsv`](release74-el10-RPM-MANIFEST.tsv), [`release74-fedora-RPM-MANIFEST.tsv`](release74-fedora-RPM-MANIFEST.tsv), and their [`EL10 checksums`](release74-el10-SHA256SUMS) / [`Fedora checksums`](release74-fedora-SHA256SUMS). EL guests used `0.0.1rc5-74.el10`; Fedora used `0.0.1rc5-74.fc46`.

## Seeds and guests

The three updated seed images had zero available OS updates on the preflight clones. Their exact seed hashes are recorded in [`ansible-seed-preflight-20261024.md`](ansible-seed-preflight-20261024.md). The candidate repository was configured in each disposable guest, not baked into the seed. EPEL and CRB were enabled on EL guests; the Admiral COPR was configured; no full OS update was repeated as part of this test.

Each guest was a fresh 2-vCPU, 2-GiB x86_64 clone. Strict SSH host-key checking was enabled. Preflight confirmed no Admiral RPMs and an empty rootless Podman inventory.

| OS / VM | Address / MAC | Kernel | Boot ID before → after actual reboot | Ansible recap |
|---|---|---|---|---|
| Rocky Linux 10.2 / `adm-r74-rocky-single` | `192.168.122.150` / `52:54:00:74:20:01` | `6.12.0-211.68.1.el10_2.x86_64` | `29291a13-35c3-4fbb-9119-69f85a094d5b` → `c110bb19-9a9c-4aed-b42a-c94ae587a0ee` | `ok=231 changed=94 unreachable=0 failed=0 skipped=148` |
| CentOS Stream 10 / `adm-r74-centos-single` | `192.168.122.151` / `52:54:00:74:20:02` | `6.12.0-278.el10.x86_64` | `2ffdc670-e21f-452f-b393-0b72d2224959` → `6c2d606c-97ce-4f41-a49d-bf9dcc50d441` | `ok=230 changed=97 unreachable=0 failed=0 skipped=149` |
| Fedora Rawhide 46 / `adm-r74-fedora-single` | `192.168.122.152` / `52:54:00:74:20:03` | `7.4.0-0.rc0.261023g734bef548a96.6.fc46.x86_64` | `a7fbe7e8-9ddc-44f5-9ea2-d7f36612b260` → `9820570b-805f-4cbc-bc3c-da510213cae6` | `ok=237 changed=99 unreachable=0 failed=0 skipped=142` |

The secure installer completed with exit code 0 on every guest. Each post-install audit found SELinux enforcing, all six expected RPMs at the exact R74 NEVRA, all six services active, no failed units, TLS health endpoints HTTP 200, healthy worker/portal registrations, rootless Podman, and no initial workload resources.

## Per-cell checks

All statuses below are E2E/integration checks executed against the exact R74 RPMs. `PASS` applies to the named test only.

| Check | Procedure and pass condition | Rocky | CentOS Stream | Fedora Rawhide |
|---|---|---:|---:|---:|
| `R74-SN-BASELINE` | Fresh guest; empty package/runtime baseline; exact native RPM install; secure installer recap; SELinux, services, TLS/API/portal health and registration postcheck | PASS | PASS | PASS |
| `R74-SN-WORKLOAD` | Create real app + PostgreSQL; HTTP 200 and SQL marker; same idempotency key returns same work; deprovision | PASS | PASS | PASS |
| `R74-SN-RESIZE` | Resize `small → medium → small`; require healthy/available and HTTP 200 at each tier; SQL marker survives | PASS | PASS | PASS |
| `R74-SN-BACKUP` | Backup; reject restore while running with HTTP 409; pause and restore; verify checksum and original SQL marker; remove backup and workload | PASS | PASS | PASS |
| `R74-SN-LIFECYCLE` | Workload pause/resume/stop/start/restart; admirald systemd stop/start/restart; confirm expected API outage and recovery | PASS | PASS | PASS |
| `R74-SN-REBOOT` | Write SQL marker; reboot actual VM; require changed boot ID, services/workload recovery, HTTP 200 and marker persistence; deprovision | PASS | PASS | PASS |
| `R74-SN-CLEANUP` | Review all test operations and instances; require terminal success/deprovision status and no test containers, pods, volumes, units, Quadlets, instance directories or backup artifacts | PASS | PASS | PASS* |

`*` Fedora's final cleanup retry passed after the working-directory harness failure. Rocky had the same correction. The CentOS initial final cleanup check passed.

Across each OS, the terminal-state audit found 15 test instances with `technical_status=deprovisioned` and `commercial_status=cancelled`, and 23/23 test operations terminal and succeeded. Retained database history is expected audit state; it was not treated as an orphan. Runtime inventory was empty. All expected Admiral services remained active and exact R74 RPMs remained installed.

## Execution timing and observations

- The three lanes began from fresh updated guests at about `2026-10-24T18:43:50Z` and completed their final cleanup checks by `19:09:23Z`, executing concurrently.
- Secure install elapsed: Rocky 555 s; CentOS Stream 614 s; Fedora Rawhide 624 s.
- Cold first workload provision: approximately 242.5 s Rocky, 247.9 s CentOS Stream and 241.5 s Fedora. The VMs were concurrently pulling/extracting PostgreSQL, so these are shared-host cold-start observations, not controlled performance measurements. Early health samples briefly showed the DB not ready; after image startup the service became healthy/available and the provision completed. No false healthy state was reported while DB readiness was false. This behavior is already tracked in [#236](https://github.com/admiral-project/admiral/issues/236); the R74 sample is appended there, with no duplicate issue.
- No stress test or p50/p95/p99 campaign was run.

## Evidence retention and hashes

Raw logs and guest log archives remain on the lab host under `packaging/build/validation/rc5-r74/runtime/single/<os>/`, directories mode 0700 and files mode 0600. They are not checked in because they contain detailed machine configuration and operational records. Hashes allow an operator with access to that host to verify each artifact. Archives were checked for readable contents; they were not published as raw logs.

| OS | Preinstall | Install | Postinstall | Functional (includes initial harness errors and corrected retry) | Diagnostics | Terminal audit | Guest log archive |
|---|---|---|---|---|---|---|---|
| Rocky | `f2f0c440d172fa153c3e53d987ce171577265ec5bcc138c16aecd03394f15365` | `314279ade2c1a2b2cee720cb90912b84c90cb00dccbb2bb8b000bb50e34b3de1` | `439f75517a41ad77def7ad04a16df44152140696dce2c4b941e166bb89929955` | `7219368ecee92d9ff6b922ac2ab356dd89d8a4fec7d6f4cd486eab2905988c4b` | `232281ca70820156b57dc195211dc69c277bbce28500f2084ba9dedc9c35c39c` | `7e08b66cacfbc66ae26cfaffbbf3b32da8b6c88b3354ffd47a00d0414cdb446d` | `4fc319b50e09f0b0b277c4d425d40b2ee62b86a8c793de1314162052f0be8a81` |
| CentOS | `e076d482eb357dee83d9cde3a3fdc73578fd3c2440624ef8d8f5588f35949216` | `54a969addea0420d51a8f20c277bba3519e40f2a096903d60215e6813778ffb8` | `8a765a96e5ef385de58a14fc2ba8f3ae793d4fcd4877fad89339222d46ad0a20` | `c2e62a92200872932a7258a571b914611370ae5c77dfc8b8584cc95dc048ba6d` | `165b7cc6bad02c71e4e89ac2110f122e60ce4f8b35e01e9a4bc7e0ca39f996a8` | `866445288efa451a7f39810311c24121f197e2fe32ab71f6b51b86f7969e9ac3` | `29c576af4c7053178036ddc9022832b0001fa881a81f99bad2645a8b83c91eb5` |
| Fedora | `f3a2c545295d84dbff9871246310bf1ba2427bf96538464d3cac488f513dff3e` | `8d0a489996c7aaa80303e5893e76ecf87f4b8f4ea0926e42ef29c27eece50c67` | `f8d1510fc43697c8edefd5b4370d876024a35265f6ec15c9b2b653130b903bef` | `98d01400ab77d63dcd000e540c06fe00a823ee1fab1ef8cf1001772e2aac5239` | `3437ac552f1d418a58ae3bf74c498d338321fe475c046af012849ea597c82a7e` | `8d36c175fcdf16c0456b4bb7c437b77063bd71fae0cb26ae33c89a6d8b009bd3` | `27fb56928176a8516d71a8843611feef70d9f2e9757e6eb33d2e62757d13956b` |

The tested VMs were shut down after capture. At final check, all three R74 libvirt domains were `shut off`; host filesystem showed 57 GiB available. No disks or evidence were deleted for this run.

## Reproduction

The scripts in [`../scripts/r74/`](../scripts/r74/) include the per-lane workflow and a parallel launcher. They intentionally do not include SSH private keys or host pins. Clone fresh R74 guests from the listed seeds, configure the candidate repository in each guest, then set `R74_SSH_KEY` to the protected lab key and `R74_KNOWN_HOSTS_DIR` to the protected directory containing `adm-r74-{rocky,centos,fedora}-single/known_hosts`. Run the launcher from the repository root with the three guest addresses:

```bash
R74_SSH_KEY=/path/to/protected/lab-key \
R74_KNOWN_HOSTS_DIR=/path/to/protected/known-hosts \
  docs/audits/admiral-production-readiness-2026-10-21/scripts/r74/run-single-pass.sh \
  ROCKY_IP CENTOS_IP FEDORA_IP
```

The launcher runs the three independent lanes concurrently and preserves lane output under the ignored validation directory. It must target fresh disposable clones and the exact R74 RPM manifests above. Do not run it against production or reused test state.
