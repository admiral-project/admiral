# RC6 Epoch 5 Release 15 candidate

**Status: six RPMs built and signed in each native environment; runtime matrix 0/6; eight issues open; not Gold.** Release 14 was rejected after the Rocky Multi-Node #291 preflight failed to recognize an independent Portal that was already active and healthy. The product fix changes `admirald`, so all six cells restart on Release 15.

## Product change and evidence

`admirald` commit `313a96c9c2234711685fce2b878705733f766b5b` synchronizes generated peer inventory after a successful Portal health check. It includes a regression test for a Portal changing from registered to active in `know_host.yaml`. Targeted test, `go test ./...`, and `go vet ./...` passed locally. Component PR [#63](https://github.com/admiral-project/admirald/pull/63) is open and its selected-head CI run [40472619846](https://github.com/admiral-project/admirald/actions/runs/40472619846) passed.

The release pins and freshly fetched `origin/main` comparisons are recorded in [source-pins.txt](source-pins.txt). The selected `admirald` and `admiralctl` commits are retained release-validation pins because they contain the fixes required for #228/#291. `python3 scripts/validate-release-refs.py` passed before the builds.

## Native builds

All six RPM specs increment to Release 15, and all six passed their package `%check` suites in both native environments. EL10 was built on Rocky Linux 10.2 with Go 1.26.10/RPM 4.19.1.1. Fedora Rawhide used the Fedora 46 build image with Go 1.27.3/RPM 6.1.0 and produced `.fc46` packages from the same component sources. No EL10 RPM was installed on Fedora.

| RPM | EL10 NEVRA | Fedora Rawhide NEVRA |
|---|---|---|
| `admiral-common` | `5:admiral-common-0.0.1rc6-15.el10.noarch` | `5:admiral-common-0.0.1rc6-15.fc46.noarch` |
| `admirald` | `5:admirald-0.0.1rc6-15.el10.x86_64` | `5:admirald-0.0.1rc6-15.fc46.x86_64` |
| `admiral-fleet` | `5:admiral-fleet-0.0.1rc6-15.el10.x86_64` | `5:admiral-fleet-0.0.1rc6-15.fc46.x86_64` |
| `admiralctl` | `5:admiralctl-0.0.1rc6-15.el10.x86_64` | `5:admiralctl-0.0.1rc6-15.fc46.x86_64` |
| `admiral-flagship` | `5:admiral-flagship-0.0.1rc6-15.el10.noarch` | `5:admiral-flagship-0.0.1rc6-15.fc46.noarch` |
| `admiral-harbor` | `5:admiral-harbor-0.0.1rc6-15.el10.noarch` | `5:admiral-harbor-0.0.1rc6-15.fc46.noarch` |

Harbor passed 352 tests on each platform; Flagship passed 266 tests on each. The build logs and toolchain records are [EL10](el10/build.log) and [Fedora Rawhide](fedora/build.log). The signed RPM SHA-256 manifests are [EL10](el10/RPM-MANIFEST.tsv) and [Fedora Rawhide](fedora/RPM-MANIFEST.tsv). Both local repositories and their `repomd.xml` signatures verify with key fingerprint `8D2E8FC99FB218979157C5DBFCC63E30ED44F66E`; all five public repository endpoints returned HTTP 200. See [repository signature log](repo-signature.log) and the [EL10](admiral-local-el10.repo) / [Fedora](admiral-local-fedora.repo) DNF configs.

## Runtime release gate

| Operating system | Single-Node | Multi-Node |
|---|---:|---:|
| Rocky Linux 10 x86_64 | Pending R15 | Pending R15 |
| CentOS Stream 10 x86_64 | Pending R15 | Pending R15 |
| Fedora Rawhide x86_64, native `.fc46` | Pending R15 | Pending R15 |

**Release 15 matrix: 0/6.** The live GitHub issue list has eight open issues: #106, #182, #228, #255, #271, #289, #291, and #294. AlmaLinux remains outside the active matrix while the COPR limitation in #276 stands. No issue has been closed based on R14 build or runtime evidence.

## R15 issue-specific follow-up — 2026-10-27

Rocky Multi-Node R15 issue #289 acceptance passed with two complete customer flows through Admin Caddy and two through the direct Portal WireGuard origin. Each deployment reached `running/healthy/available`; strict TLS route checks returned HTTP 200; all four instances were deprovisioned and final app-route and rootless Podman inventories were empty. The detailed report and hashed raw evidence are in [`ISSUE-289-REPORT.md`](ISSUE-289-REPORT.md) and [`ISSUE-289-EVIDENCE-SHA256SUMS`](ISSUE-289-EVIDENCE-SHA256SUMS). This is not a matrix-cell pass.

The same fresh Rocky Multi-Node R15 installation completed the #182 uploaded-backup restore on the Worker after the packaged installer automatically configured Worker-to-Portal networking. The SQL marker was restored, the resumed workload returned HTTP 200, unregistered Worker and metadata sources were rejected without new restore operations, and the synthetic instance was deprovisioned. Issue #291 still needs its R15 peer/firewall revocation check. These issue-specific results do not change the formal matrix result of 0/6.

Root commit `cdeb30d` records the exact Makefile source pins, submodule pointer, and six Release 15 RPM specs that were used for this build; no product content changed after the R15 package build.
