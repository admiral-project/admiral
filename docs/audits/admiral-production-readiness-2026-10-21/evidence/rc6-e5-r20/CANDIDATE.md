# RC6 Epoch 5 Release 20 candidate

As of 2026-10-28 UTC. This is a build and packaging result, not a Gold or runtime-matrix declaration.

## Source and package builds

- Root release commit: `ba7c4396743e84baae0b4de9f89f91ff5503a33b`.
- `admirald`: `4472cd8defc2de9c649ddbc1108a0aa64c0f1859`.
- Root and RPM source references passed `python3 scripts/validate-release-refs.py`.
- Rocky Linux 10.2 x86_64 host build: six RPMs at `5:0.0.1rc6-20.el10`.
- Fedora Rawhide native x86_64 build: six Fedora-native RPMs at `5:0.0.1rc6-20.fc46`. Build ran in Fedora Linux 46 Rawhide container image digest `sha256:3375b5f7d84cb52f52575148f13425899f40ee6a80112e3df8fef3bd208f58f5`; Go was `1.27.3-X:nodwarf5`. EL10 binaries were not reused for Fedora.
- The pre-build helper exited before compiling; the successful builds are the direct native EL10 host and Fedora Rawhide container builds recorded here.

The per-distro `RPM-MANIFEST.tsv` records package name, epoch, version, release, architecture and the final SHA-256 of each signed RPM. `SHA256SUMS` records the RPM hashes. Readable build and DNF transcripts are included; trailing whitespace was trimmed in the tracked copies. Original raw build and update logs remain under `/var/lib/libvirt/images/admiral-validation/build/rc6-e5-r20/`, with their SHA-256 values in `raw-log-hashes.txt`.

## Package checks

- Both distro builds completed all six packages.
- Go `%check` suites passed for `admirald`, `admiral-fleet` and `admiralctl` on each native build.
- `admiral-flagship`: 266 tests passed on EL10 and Fedora.
- `admiral-harbor`: 352 tests passed on EL10 (391.66 s) and Fedora (485.19 s).
- R20 `admirald` complete component suite and targeted migration regressions passed separately; details are in `component-validation.txt`.

## Signatures and local repository

- All six RPMs in each distro repository passed signature and payload-digest verification against key fingerprint `8D2E8FC99FB218979157C5DBFCC63E30ED44F66E`.
- Both EL10 and Fedora `repomd.xml` signatures passed GPG verification.
- Signed local repository: `/var/lib/libvirt/images/admiral-validation/repo/rc6-e5-r20`.
- Verification record: `repo-signature-validation.txt`.

## Runtime and release status

The candidate was installed as an update on the existing Rocky admin and two worker nodes. The live R20 #255 multi-node migration passed on those existing VMs; the detailed run and resource telemetry are in `runtime/issue-255-r20-issue255-rocky-mn-20261028t002633z-2690062/RESULT.md`. An initial 512 MiB fixture was safely rejected before instance creation because it exceeded the source node's remaining RAM commit capacity; the successful issue-specific fixture used 128 MiB. No new VM was created, and the old R18 source fixture remains healthy and available.

This issue-specific migration result does not constitute a complete Single-Node or Multi-Node release-matrix cell. Because R20 changes product code, all six R19 runtime cells are invalid for R20. The R20 runtime matrix remains **0/6** pending full cells on Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide. GitHub CI passed for the selected component and root candidate SHAs; run IDs are in `ci-status.md`. This candidate is not Gold.
