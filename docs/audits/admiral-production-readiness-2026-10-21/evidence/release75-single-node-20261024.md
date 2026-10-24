# Release 75 Single-Node parallel validation

**Run:** `single-pass-20261024T220905Z`  
**Window:** 2026-10-24 22:09:05–22:27:10 UTC  
**Result:** **3/3 Single-Node cells PASS** for the Release 75 functional gate.  
**Overall active functional matrix:** **3/6 PASS**. No Release 75 Multi-Node cell was run.

This is candidate-specific end-to-end evidence. It is not a full production-readiness, security, resilience, or performance certification. A result from an earlier release does not transfer to Release 75.

## Candidate and environment

The six Admiral RPMs are Release 75. They were prepared at root commit `b88370d90aa2a2de0f73ce5ce3cbbff39f0ed953`. The validation scripts and harness corrections were at root commit `9104ca0b111c0e6cc9c32280529fc8456408d727`; these commits changed the test harness after packaging, not the component RPM sources. Root CI for the harness commit passed: [run 40137247001](https://github.com/admiral-project/admiral/actions/runs/40137247001).

| Component source | Exact commit packaged |
|---|---|
| `admiral-common` | `3faa349a5ba96b051104f1af5d043cb14bc8259d` |
| `admirald` | `65afd58947c56edaef041737d7f775e7b4038182` |
| `admiral-fleet` | `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686` |
| `admiralctl` | `fa2a65e866310bd82bea78859804b6c3aea7989a` |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` |
| `admiral-harbor` | `dd39e9a74bf658ecf6fd6e9f8bd30b2ddf82d7db` |

CI was green for the root package-preparation commit and all five component submodule commits used by the RPMs:

| Repository | CI run |
|---|---|
| Root project/package preparation (`b88370d`) | [40134458726](https://github.com/admiral-project/admiral/actions/runs/40134458726) |
| `admirald` | [40134043032](https://github.com/admiral-project/admirald/actions/runs/40134043032) |
| `admiral-fleet` | [40069777965](https://github.com/admiral-project/admiral-fleet/actions/runs/40069777965) |
| `admiralctl` | [40030034925](https://github.com/admiral-project/admiralctl/actions/runs/40030034925) |
| `admiral-flagship` | [39795263415](https://github.com/admiral-project/admiral-flagship/actions/runs/39795263415) |
| `admiral-harbor` | [39795262318](https://github.com/admiral-project/admiral-harbor/actions/runs/39795262318) |

The R75 harness correction commit `9104ca0` passed root CI [40137247001](https://github.com/admiral-project/admiral/actions/runs/40137247001). The documentation commit recording this evidence also passed root CI [40138894596](https://github.com/admiral-project/admiral/actions/runs/40138894596).

EL10 RPMs were built in an EL10 environment and installed only on Rocky Linux and CentOS Stream. Fedora Rawhide received its native `.fc46` RPMs built in the Fedora builder. No cross-distro or `--nodeps` installation was used.

The lab host is Rocky Linux 10 x86_64 with 8 GiB RAM and 4 GiB swap. Three isolated KVM guests ran in parallel, each with 2 vCPU and 2 GiB RAM:

| Cell | Guest and address | Guest OS | Seed image SHA-256 | Candidate RPM suffix |
|---|---|---|---|---|
| Rocky Single-Node | `adm-r75-rocky-single` / `192.168.122.173` | Rocky Linux 10.2 x86_64 | `fd2456f930929c1ba9ae05b5a86548a0e9e436957fbcaf08d4583795915dc930` | `.el10` |
| CentOS Single-Node | `adm-r75-centos-single` / `192.168.122.174` | CentOS Stream 10 x86_64 | `2b046acf36e4b775bac179ad2dd5c93cadc051ea7b6991842d0d0274a466b195` | `.el10` |
| Fedora Single-Node | `adm-r75-fedora-single` / `192.168.122.175` | Fedora Rawhide 46 x86_64 | `3199f6fd067a97e11bd29fb466c31edbf3727c95cb6e2c16ac1ed2434c4bb7ef` | `.fc46` |

The seed preflight confirmed the listed OS versions, SELinux Enforcing, enabled Admiral COPR on all three guests, and EPEL plus CRB on the two EL10 guests. Required Python dependency packages were already installed in the seeds. The test run did not execute a full OS update or dependency installation.

## Procedure and result

The coordinated runner was `docs/audits/admiral-production-readiness-2026-10-21/scripts/r75/run-single-release-pass.sh`, using the three guest addresses above and the lab's private SSH key via `R75_SSH_KEY`. It performed seed preflight, the secure Ansible installer, post-install checks, and one functional lane per guest concurrently.

The seed preflight, package installation, and post-install checks passed on all three guests. The secure installer recaps were:

| Guest | Ansible recap | Result |
|---|---:|---|
| Rocky Linux 10.2 | `ok=231 changed=94 failed=0 unreachable=0` | PASS |
| CentOS Stream 10 | `ok=230 changed=97 failed=0 unreachable=0` | PASS |
| Fedora Rawhide 46 | `ok=237 changed=99 failed=0 unreachable=0` | PASS |

Each functional lane executed these checks against the installed Release 75 packages:

| Test ID | Procedure and expected evidence | Rocky | CentOS Stream | Fedora |
|---|---|---:|---:|---:|
| `R75-SN-SEED-INSTALL-01` | Seed and enabled-repository preflight; install exact native six-RPM set; secure setup completes without Ansible failure; API, node, and rootless Podman checks succeed | PASS | PASS | PASS |
| `R75-SN-LIFECYCLE-IDEMPOTENCY-01` | Create workload; repeat the same idempotency key and confirm same operation/instance; verify app and SQL; deprovision and check runtime cleanup | PASS | PASS | PASS |
| `R75-SN-RESIZE-PERSISTENCE-01` | Resize small → medium → small; confirm persisted SQL marker and workload availability | PASS | PASS | PASS |
| `R75-SN-BACKUP-RESTORE-01` | Create/checksum backup; reject restore in invalid state with HTTP 409; restore original SQL marker; delete backup and workload; confirm tombstone/history behavior | PASS | PASS | PASS |
| `R75-SN-SERVICE-LIFECYCLE-01` | Pause/resume/stop/start/restart workload; restart/stop/start `admirald`; confirm unavailable behavior while stopped and API recovery | PASS | PASS | PASS |
| `R75-SN-HOST-REBOOT-01` | Reboot guest; confirm changed boot ID; wait for three containers, PostgreSQL readiness, `running/healthy/available`, HTTP 200, and preserved SQL marker; deprovision | PASS | PASS | PASS |
| `R75-SN-TERMINAL-CLEANUP-01` | Audit five test instances and 23 operation records; require all operations successful, terminal workload state, exact candidate NEVRAs, healthy services, and no residual test resources | PASS | PASS | PASS |

All three host-reboot tests observed a changed boot ID. Rocky converged by post-reboot poll 3; CentOS Stream by poll 3; Fedora by poll 3. Each returned HTTP 200 after reboot and read back `r75-reboot-persisted` from PostgreSQL. The final audit on each guest found five test instances in deprovisioned/cancelled state, 23/23 selected operations succeeded, and no test containers, pods, volumes, units, or files remained.

There were transient startup states during the real restart windows, including `stopped/unavailable` while the runtime came up. The runner waited for the required healthy/available state and checked that Admiral did not claim healthy/available while required containers or PostgreSQL were unready. These converged within the test timeout and did not fail the checks.

## RPM identity and hashes

All six packages per native platform were installed and their NEVRAs checked on the guests. The SHA-256 values below are for the exact RPM payloads in the isolated local validation repositories.

| Package | EL10 NEVRA | EL10 SHA-256 | Fedora NEVRA | Fedora SHA-256 |
|---|---|---|---|---|
| `admiral-common` | `admiral-common-0.0.1rc5-75.el10.noarch` | `c992fa847d6004226396914535de01e94b4afcebd0c9173d0a180ed832988153` | `admiral-common-0.0.1rc5-75.fc46.noarch` | `57e745b268ca8fbdcc7077d03b8ee572c1ce13521ba7d541f246ecf16fdb9034` |
| `admirald` | `admirald-0.0.1rc5-75.el10.x86_64` | `aac135efbf4509c07bb9220ea846931964e6aae26a2b0094ed7c33370dd03f2c` | `admirald-0.0.1rc5-75.fc46.x86_64` | `c231bc0739043fa2b820bc86378e8df39aa099512abf1c37a088a83bc5f505bd` |
| `admiral-fleet` | `admiral-fleet-0.0.1rc5-75.el10.x86_64` | `ee1822feededecfbe783abe712070124dd115a8822a0db3f9356bfdd130f857d` | `admiral-fleet-0.0.1rc5-75.fc46.x86_64` | `d2553035cbc04db7963a563d95fd992864f558df2b2aeca6393f196bd56310bf` |
| `admiralctl` | `admiralctl-0.0.1rc5-75.el10.x86_64` | `16b9c4ad72b1fdb5857c35e47e8057909031b0c88d76fc2b366a79bcf70ce21b` | `admiralctl-0.0.1rc5-75.fc46.x86_64` | `71978438001aa24e72230012e9bee0a3a46d4f6aefb4038fa415041a2d713a39` |
| `admiral-flagship` | `admiral-flagship-0.0.1rc5-75.el10.noarch` | `6723cede0125f7e98f9198a20e9ff2b64e5bb33cbc626652900658dc63f589e8` | `admiral-flagship-0.0.1rc5-75.fc46.noarch` | `a581f18689882af8d8841a36a02149c5b515ad82104b70159c848630bbf7531c` |
| `admiral-harbor` | `admiral-harbor-0.0.1rc5-75.el10.noarch` | `a26baf08d290040162440ae6f818fbc923da189bbb4ebc95f27938cc0575a178` | `admiral-harbor-0.0.1rc5-75.fc46.noarch` | `42738f483da264c6ac43ca9d30d8e85b5ed77929ede7c579c5fda8a72ef4913f` |

The RPM build logs have SHA-256 `b016e5efacc49de6e77cb6d67207cd6016334aa7496ea21ed2f5cdc0b8ea4820` (EL10) and `d6216320c0fad34995b730f463f3fef0d5229b5387ea156ae36db57e83fc2139` (Fedora). The private runtime log checksum manifest SHA-256 is `fc7b8b88b4a74e103907bc9ddb5ab87a9ac9d7baf25d795a268bf463c69b5f66`; raw logs remain in the ignored lab directory with mode `0600` and were verified against the manifest after the run.

## Limits and reproduction

This pass validates the named functional procedures above only. It did not run the Multi-Node topology, exhaustive authorization or workload-isolation negatives, stress/concurrency campaigns, resource exhaustion, broad failure injection, external-storage backup, or controlled performance percentiles. Those scenarios remain NOT TESTED and block any broader production-readiness claim.

To reproduce on equivalent disposable VMs, prepare the exact candidate repo and updated seeds, provide a private key through `R75_SSH_KEY`, then run:

```bash
R75_SSH_KEY=/path/to/private/validator_ed25519 \
  docs/audits/admiral-production-readiness-2026-10-21/scripts/r75/run-single-release-pass.sh \
  192.168.122.173 192.168.122.174 192.168.122.175
```

This recorded run's raw logs are under the ignored local path `packaging/build/validation/rc5-r75/runtime/single-pass-20261024T220905Z/`. The original, invalidated R75 harness attempt is retained separately at `single-pass-20261024T214533Z/`; it is not included in the PASS result.
