# RC6 x86_64 OS seed images — 2026-10-25

These immutable lab seeds were freshly produced with `scripts/create_seed_os.sh` from the distribution cloud images. They are intended to avoid repeating the full OS update and dependency installation in each validation run.

| OS | Seed image | Runtime packages installed | `dnf check-update` | Admiral packages installed | Admiral services enabled | Local validation repo baked in | Image SHA-256 |
|---|---|---:|---:|---:|---:|---:|---|
| Rocky Linux 10.2 x86_64 | `Rocky-10.2-seed-20261025-rc6-updated.x86_64.qcow2` | yes | 0 (no updates pending) | no | no | no | `7ea75d0ec238ee8d813b42cfa7b42e73c9f3eb1aaff9b30634b73eba04a968b6` |
| CentOS Stream 10 x86_64 | `CentOS-Stream-10-seed-20261025-rc6-updated.x86_64.qcow2` | yes | 0 (no updates pending) | no | no | no | `8c30081d6d1542ccf74223d7b5a81a55d8ab8178124a47f9919b97bfb2db43c7` |
| Fedora Rawhide x86_64 | `Fedora-Rawhide-seed-20261025-rc6-updated.x86_64.qcow2` | yes | 0 (no updates pending) | no | no | no | `01f5a6772943027a35b429e3a40d28de6ed22cb92f3d00e3858517269a992b1e` |

The per-OS directories contain the seed-creation log, DNF update/dependency setup log, final verification output and their SHA-256 manifest. Each verification records the OS identity/architecture, enabled repositories, required runtime package inventory, service states and the zero-update result. The setup used the distro's matching repository family (Fedora Rawhide/COPR; EL10 BaseOS/AppStream/CRB/EPEL/COPR) and did not store the Admiral local repository in the image; local repository setup remains a per-lab action.

The three seed files were independently checked with `qemu-img check` after creation; all reported no image errors. Their creation records are associated with the Release 75 seed-maintenance helper and contain no Admiral runtime packages; the RPM set used to supply/check dependency metadata did not get installed in the seed.
