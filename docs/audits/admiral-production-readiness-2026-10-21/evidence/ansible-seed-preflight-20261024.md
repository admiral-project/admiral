# Ansible seed preflight — 2026-10-24

This preflight prepares the disposable x86_64 guests for fast execution of the
release validation playbooks. It does not count as a runtime cell result.

## Seed images

Each image was refreshed from its native distribution repositories on
2026-10-24. The SHA-256 values below identify the exact images retained in the
lab:

| OS | Seed image | SHA-256 |
|---|---|---|
| Rocky Linux 10.2 | `Rocky-10.2-seed-20261024-r73-updated.x86_64.qcow2` | `fd2456f930929c1ba9ae05b5a86548a0e9e436957fbcaf08d4583795915dc930` |
| CentOS Stream 10 | `CentOS-Stream-10-seed-20261024-r73-updated.x86_64.qcow2` | `2b046acf36e4b775bac179ad2dd5c93cadc051ea7b6991842d0d0274a466b195` |
| Fedora Rawhide | `Fedora-Rawhide-seed-20261024-r73-updated.x86_64.qcow2` | `3199f6fd067a97e11bd29fb466c31edbf3727c95cb6e2c16ac1ed2434c4bb7ef` |

Fresh clones for the three target OSes were checked with
`dnf --refresh check-update` on 2026-10-24. All reported **zero OS package
updates**. DNF returned 100 because the Admiral COPR offered newer RPM release
numbers for the same pinned upstream Python library versions: eight packages
on EL10 and five on Fedora Rawhide.
The installed Python baseline was recorded and left unchanged. No Admiral RPM
was installed in the checked guests.

Enabled repositories were the native OS repositories and Admiral COPR; EPEL
and CRB were enabled on EL10. A local validation repository was not baked into
the seeds and must be configured in each lab when needed.

## Playbook preparation

`ansible/site.yml` and `ansible/wireguard-peers.yml` both pass
`ansible-playbook --syntax-check` with inventory groups for `admin`, `workers`,
and `portal`. This is static validation only. The actual installer invokes
`site.yml` on one target per `admiral-install` run, so increasing Ansible
`forks` does not accelerate a Single-Node run. The time savings come from
cloning the prepared images and running independent Single-Node cells in
parallel; Multi-Node remains one three-guest cell at a time on this 8-GiB host.

The audit helper configures the candidate repository per guest and installs
the exact native RPM set through DNF. It does not run a full OS update during
the playbook run.

No release-candidate installation playbook was run during this preflight:
the next candidate remains gated on issue triage, fixes, and green CI.

The local regression suites run after updating the audit-repository tests:

| Command / suite | Result |
|---|---|
| `python3 -m pytest -q scripts/test_*.py` | PASS — 150 passed |
| `make test-admiralctl-local` | PASS |
| `go test ./...` and `go vet ./...` in `admirald`, `admiral-fleet`, and `admiralctl` | PASS |
| `python3 -m pytest tests/ -q` in `admiral-flagship` | PASS — 266 passed |
| Harbor pytest with CI deprecation-warning filters | PASS — 350 passed |
| Ansible syntax checks for `site.yml` and `wireguard-peers.yml` | PASS |

The initial full root suite exposed four stale assertions expecting Python
helper RPMs inside the local candidate repo. The tests now assert the current
six-Admiral-RPM repository contract and still reject stale/mixed repo contents.
The full root suite passed after that correction.

## Disk cleanup

Before removing images, the lab checked QCOW2 backing chains and all libvirt
domain disks. Seven old, unreferenced seed generations were removed; current
updated seeds, active VM disks, and failure evidence were retained. This freed
`18,247,122,944` bytes. The lab then had 62 GiB available (61% filesystem
usage). The host-side removal manifest is
`/var/lib/libvirt/images/admiral-validation/validation/obsolete-vm-cleanup-20261024/disk-cleanup-20261024.txt`.

## Reproduction commands

```bash
ansible-playbook --syntax-check -i /tmp/admiral-audit-syntax-inventory.ini ansible/site.yml
ansible-playbook --syntax-check -i /tmp/admiral-audit-syntax-inventory.ini ansible/wireguard-peers.yml
```

For seed freshness, run `dnf --refresh check-update` on a disposable clone of
each listed image and distinguish OS updates from new RPM releases of the
same pinned Python upstream versions. Do not run `dnf update` as part of a
release-cell execution.
