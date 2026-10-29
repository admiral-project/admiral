# RC6 E5 R26 — Preservation Index

Date: 2026-10-29 UTC
Scope: source code and documentation only, per release-owner direction. Product code, candidate identity, RPMs, and original test files were not modified. This is a preservation index, not a new release or a Gold declaration.

## Preserved in GitHub

This documentation set is being added to `origin/main` without changing the six R26 source pins. It contains the final candidate/release/security reports, all six cell reports, source/build manifests and pins, the R26 audit scripts selected for publication, and their checksums. The per-file inventory is [`PRESERVATION-INVENTORY.tsv`](PRESERVATION-INVENTORY.tsv). `PRESERVATION-SHA256SUMS` covers the published source/document files; its own checksum is represented by the containing Git commit.

The original evidence directory contained 165 files (1135666 bytes). The source-and-documentation selection contains 71 files (248233 bytes), before this index, inventory, and checksum file. The standalone resource guard is also preserved at `docs/audits/admiral-production-readiness-2026-10-21/scripts/r26-multinode-resource-guard.py`.

## R26 source and candidate references

The source is already available in the project's upstream repositories. I checked the live `origin/main` refs on 2026-10-29:

| Repository | R26 source SHA | `origin/main` |
|---|---|---|
| `admiral` product payload | `b6146a46be93f1a9c242361e27b10dbbb2164bf6` | ancestor of root `7822613725d36bef17845fe06f387c9ae9539b58` |
| `admirald` | `8efa1dec8e9540210d9f86d016dce4677dcc6543` | exact match |
| `admiral-fleet` | `edc0a0d486eb102e9aaa4f250a08f777d7441f12` | exact match |
| `admiralctl` | `d0e98414115c9628e59b33678cfcbd9bc0e342d5` | exact match |
| `admiral-flagship` | `b7325bbc71fc474a521496e593b2967e4d555ac1` | exact match |
| `admiral-harbor` | `dd4818b6e2bc53eea4495fc5e374a4893cfcb107` | exact match |

The root RPM specs under `packaging/rpm/` are already tracked in source and byte-identical to the six EL10 and six Fedora build spec snapshots. The root code pin is retained as an ancestor; this preservation adds documentation and audit scripts only.

## External build and tracker records

The six EL10 R26 source RPMs at `/srv/admiral-copr-r26-srpms/` total 83421504 bytes. Each Copr-stored source RPM was downloaded and SHA-256 compared byte-for-byte with its local original. All six Copr builds succeeded in both `epel-10-x86_64` and `fedora-rawhide-x86_64`. The build IDs, source SHA-256 values and result links are recorded in [the #308 comment](https://github.com/admiral-project/admiral/issues/308#issuecomment-6499787588). The Fedora Rawhide chroot produced `.fc46` packages; no EL10 binary was used as a Fedora binary.

The public issue records are [#307](https://github.com/admiral-project/admiral/issues/307) and [#308](https://github.com/admiral-project/admiral/issues/308), both closed. They contain the security disposition and the 6/6 runtime matrix results.

## Inventory outside the evidence directory

| Location | Observed contents | Size / date | Relation and classification | External copy |
|---|---|---|---|---|
| `packaging/build/validation/rc6-e5-r26/` | 8896 files: 12 native RPMs, 12 source RPMs, six specs per target, build roots, extracted sources, and temporary Go caches | 1153183701 bytes; generated 2026-10-28 | Package outputs and build intermediates. RPM/source RPM files were not copied under the current source-and-documentation scope. | The six EL10 source inputs and Copr build outputs are on Copr. The exact native tested RPMs are represented by public manifests/hashes, not by a claim of a byte-identical external copy. |
| `/srv/admiral-copr-r26-srpms/` | Six EL10 source RPMs plus `SHA256SUMS` | 83421504 bytes of source packages; 2026-10-29 | Exact Copr build inputs. | Byte-identical Copr copies verified for all six. |
| `/tmp/` R26-named scratch files | 36 files, 172978 bytes, including drafts/copies of issue comments and checksum work; temporary test dirs are empty, and two temporary VM XML directories identify RC6 R18 rather than R26 | 2026-10-28–29 | Noncanonical scratch. Published comment copies are available from GitHub; a host-identifying fingerprint file is withheld from publication. | No separate copy; not needed to reproduce final reports. |
| `docs/audits/.../scripts/r26-multinode-resource-guard.py` | One audit source script | 7,671 bytes; 2026-10-28 | Reproducibility source for recorded resource guards. | Included in the documentation/source push. |

## Explicit limits of this preservation

- Runtime `.log`, `.json`, `.jsonl`, raw snapshots and private-log contents were not copied because the requested preservation scope is source code and documentation. Their checksums remain in the published manifests where available; those hashes are not represented as copies of the files.
- The helper `runtime/fedora-multi/caddy-customer-flow.sh` was not published because it reads and prints the installed Harbor bootstrap credential. Its result remains described in the final report and closed issue records.
- The 12 native RPM files were not uploaded by this documentation-only preservation. Copr has successful builds from the same source inputs, but this index does not claim Copr's resulting binaries are byte-identical to the native RPMs used in the E2E cells.
- Build caches and extracted intermediate files remain untouched on the host; the Go caches alone occupy roughly 810 MB and are not needed as source or documentation.

No VMs were created, stopped or destroyed for this preservation. No RPMs were rebuilt, no E2E/security tests were rerun, and issues #307/#308 were not reopened.
