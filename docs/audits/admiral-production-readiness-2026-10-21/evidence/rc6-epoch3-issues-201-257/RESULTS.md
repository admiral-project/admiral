# Issue gates #201 and #257 — diagnostic candidate E3/R5

Date: 2026-10-25 UTC
Candidate: Admiral `0.0.1rc6-5`, RPM Epoch 3
Source checkout used by the installer harness: root commit `20e5e5febd4a2d3d64d9ba69412236d9f14fb324`.
This is targeted issue evidence only. Epoch 3 is a diagnostic candidate and earns **no formal release-matrix cell credit**.

## Result

| Issue | Rocky Linux 10.2 x86_64 | Fedora Rawhide 46 x86_64 | Gate |
|---|---|---|---|
| #201 — patched Flask dependency | PASS: installed Flask `1:3.1.3-4.el10` from Admiral COPR | PASS: installed Flask `1:3.1.3-6.fc45` from Rawhide; COPR also exposes `1:3.1.3-4.fc46` | Passes the issue's clean-install and Flask security-floor check. Fedora's actual selected provider is Rawhide, not COPR. |
| #257 — Mistune dependency | PASS: installed Mistune `3.4.0-2.el10` from Admiral COPR | PASS: installed Mistune `3.4.0-2.fc46` from Admiral COPR | Passes repository availability, clean dependency resolution and runtime check. |

Both guests started from updated OS seeds. Before the transaction, Admiral packages were absent and the target Flask/Mistune dependency stack was removed. Enabled repositories were the distribution repositories and Admiral COPR; Rocky also had EPEL and CRB. No `admiral-local` repository was present. The six candidate Admiral RPM files were passed directly to DNF as local package arguments; DNF performed ordinary dependency resolution and GPG checking. No `--nodeps`, repository bypass, cross-distribution RPM, or locally built Python helper RPM was used.

The six candidate RPM signatures were verified before installation. DNF transactions succeeded on both guests. The installer completed with zero failed/unreachable Ansible tasks, Harbor's systemd unit was active, and `/health` and `/ready` returned HTTP 200 (`database=ok`, `admirald=ok`). Exact NEVRAs, RPM SHA-256 values, repository queries, transaction logs, and runtime checks are retained in the adjacent OS directories. RPM manifests are copied from the previously committed E3/R5 candidate evidence and identify all six exact package files.

## Harness retry accounting

The first attempt under `failed-harness-attempts/` selected only four Admiral RPM files due to an incomplete file glob (it omitted `admirald` and `admiralctl`). It is retained for traceability and marked **NOT COUNTED**; it is a harness defect, not a product failure. The subsequent `rocky/` and `fedora/` runs selected and signature-checked all six packages and are the runs counted above.

Raw Ansible installer logs were intentionally excluded because they may contain generated credentials. `installer-summary.txt` retains only exit status and safe PLAY RECAP counters.

## Formal matrix impact

None. These runs use Epoch 3 and Release 5 diagnostic RPMs, not the final no-Epoch `0.0.1rc6 Release 1` candidate. They also exercise dependency installation and Harbor health only, not the full Single-Node or Multi-Node validation procedures. The formal matrix remains **0/6**.
