# Admiral RC6 Epoch 5 Release 18 candidate

**Package build and signing:** PASS for all six EL10 RPMs and all six native
Fedora Rawhide RPMs. **Runtime release matrix:** 0/6. **Gold:** NO.

Release 17 is historical and invalidated by product changes for #255 and #304.
Release 18 packages the selected source pins listed in
[`source-pins.txt`](source-pins.txt). The RPM build checkout was `793a512`;
the latest root-only harness updates are documentation and test changes, do not
alter the RPM source pins, and do not invalidate these packages.

## Build and package checks

- Native Rocky Linux 10.2 x86_64 build produced six `.el10` RPMs. Go package
  tests and architecture checks passed; Flagship passed 266/266 and Harbor
  passed 352/352. See [`el10/build.log`](el10/build.log) and
  [`el10/build-environment.txt`](el10/build-environment.txt).
- Fedora Linux 46 Rawhide x86_64 container build produced six native `.fc46`
  RPMs from the same source pins. No EL10 RPM was relabeled or installed on
  Fedora. Go package tests and architecture checks passed; Flagship passed
  266/266 and Harbor passed 352/352. See [`fedora/build.log`](fedora/build.log)
  and [`fedora/build-environment.txt`](fedora/build-environment.txt).
- Release defaults in the audit harness were corrected to Epoch 5, Release 18
  and the `rc6-e5-r18` candidate path. The focused regression test passed
  12/12. `scripts/validate-release-refs.py` passed in the RPM build.
- Root CI is green on the latest harness commit `1ec505b` (run
  `40541072575`). CI is green on all selected component commits; exact SHAs and
  run IDs are recorded in [`source-pins.txt`](source-pins.txt).

## Signed local repositories

The signed local repositories are staged at
`/var/lib/libvirt/images/admiral-validation/repo/rc6-e5-r18/{el10,fedora}/x86_64`.
Both repositories contain exactly six packages for their native distro tag.
All 12 RPM signatures and both `repomd.xml` signatures verified with the lab
validation key fingerprint `8D2E8FC99FB218979157C5DBFCC63E30ED44F66E`.

| Distro | Manifest | Repo config |
| --- | --- | --- |
| EL10 | [`el10/RPM-MANIFEST.tsv`](el10/RPM-MANIFEST.tsv) | [`admiral-local-el10.repo`](admiral-local-el10.repo) |
| Fedora Rawhide | [`fedora/RPM-MANIFEST.tsv`](fedora/RPM-MANIFEST.tsv) | [`admiral-local-fedora.repo`](admiral-local-fedora.repo) |

The manifests identify the signed RPM NEVRA and SHA-256 values. Signature
verification details are in [`repo-signature.log`](repo-signature.log).

## Release gates

- Open root issues: **6** — #106, #255, #271, #304, #305, and #307. Current
  dispositions are in [`ISSUE-TRIAGE.md`](ISSUE-TRIAGE.md).
- Required runtime matrix: Rocky Linux 10, CentOS Stream 10, and Fedora
  Rawhide x86_64, each Single-Node and Multi-Node: **0/6**.
- #307 is **open**. Its expected security review covers checklist sections
  A–L, including two real customers sharing a Worker and effective runtime
  isolation. The current partial review is
  [`SECURITY-REGRESSION-REPORT.md`](../issue-307-20261027/SECURITY-REGRESSION-REPORT.md);
  it does not pass or close #307.
- Gold is ineligible while issues remain open or any matrix cell is incomplete.

## Lab capacity

After both builds, host capacity was 5.2 GiB available RAM and 48 GiB free
disk; no validation VMs were running. The updated OS seed images remain
preserved. The current lab cannot safely run the three-node, two-customer
security validation or the 7 GiB guest required by #305. It also has no routed
public IPv6 path for #304. These are outstanding validation constraints, not
PASS results.
