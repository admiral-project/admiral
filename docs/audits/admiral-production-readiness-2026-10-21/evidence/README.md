# Evidence directory

## Current candidate

RC5 Release 74 is the active candidate, with root package-preparation commit `d6e5cacb7c35807417f19b7f970c1d1f6a2d387c` and five exact component pins. All six RPMs were installed from native EL10 and Fedora repositories. Three Single-Node cells (Rocky Linux 10, CentOS Stream 10, Fedora Rawhide) passed in one concurrent run; all three Multi-Node cells remain NOT TESTED. Candidate refs, CI, package NEVRAs and hashes, seeds, run logs, corrected harness retries and limitations are in [`release74-single-node.md`](release74-single-node.md). Historical Release 67 and earlier artifacts remain candidate-specific and do not transfer.

This directory contains sanitized, non-secret audit artifacts. Source/RPM identity, lab preflight, guest snapshots, seed update results, lifecycle probes, Multi-Node placement and recovery, isolation probes, backups/restores, failure injection, concurrency probes, repository test results, and dependency screening are retained as candidate-specific history. Raw per-guest R74 logs remain in the ignored lab directory, mode 0600; their hashes are published without copying configuration-bearing logs into Git.

The Release 43 package manifest and its scoped guest observations are retained as historical evidence in `release43-candidate.md`. They do not validate Release 46.

The prepared seeds were sourced from official GenericCloud images, checked against official SHA-256 manifests, updated with `dnf -y update`, booted once with the updated kernel, and shut down cleanly. Source image SHA-256 values recorded during this preparation:

* AlmaLinux 10.2 `AlmaLinux-10-GenericCloud-10.2-20261012.0.x86_64.qcow2`: `cbee4726fc0f5a60694bb4f289003cc221e715dfbacebcce76b54daf386d8eca`.
* CentOS Stream 10 `CentOS-Stream-GenericCloud-10-20261019.0.x86_64.qcow2`: `61a925943be6f1352c5841d6d79e87f9864d265bb062495034408a83ea544b30`.

Official references: [AlmaLinux downloads](https://almalinux.org/get-almalinux/) and [CentOS Stream 10 cloud images](https://cloud.centos.org/centos/10-stream/x86_64/images/).
