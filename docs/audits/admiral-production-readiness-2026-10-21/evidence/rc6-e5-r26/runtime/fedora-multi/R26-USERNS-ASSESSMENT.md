# R26 Fedora Multi — UserNS assessment for #307

Date: 2026-10-28 UTC  
Candidate: Epoch 5, `0.0.1rc6-26.fc46`, x86_64  
Classification: documentation/evidence only; no product change and no candidate invalidation.

## Decision

Keep the existing Ansible-managed rootless `UserNS=auto` default for `admiral-apps`, with no fixed map-size default. Podman assigns a separate subordinate UID/GID range when it creates each pod. The two-customer R26 run demonstrates an additional filesystem ownership boundary in the tested PostgreSQL workload: the same container owner (`999:999`) translated to different host IDs for A and B, and the cross-customer volume probes were denied.

This is useful defense in depth for persistent files. It does not replace rootless execution, SELinux/MCS, distinct pod networks, secret separation, or authorization. It does not prove isolation against compromise of the `admiral-apps` host account, Podman, or the kernel, and it is not a capacity or performance benchmark.

## Documentation reviewed

- [Podman rootless mode](https://docs.podman.io/en/latest/markdown/podman.1.html#rootless-mode): rootless Podman requires subordinate UID/GID ranges in `/etc/subuid` and `/etc/subgid`.
- [Podman `--userns`](https://docs.podman.io/en/latest/markdown/podman-create.1.html#--userns-mode): `auto` allocates unique UID/GID ranges from the subordinate pool. Without an explicit `size`, Podman estimates a range from the image's UID needs. An explicit `size=N` is an exact override, not a minimum that is later expanded. Unbounded `keep-id` or `nomap` can consume the subordinate ranges and prevent new `auto` allocations.
- [Podman Quadlet `[Pod] UserNS=`](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html#usernsmode): pod-level `UserNS=` maps to `podman pod create --userns` and is inherited by the pod's containers.

Admiral's current role configures rootless Podman for `admiral-apps` through its per-user containers configuration and `PODMAN_USERNS`. The default is `auto` with no size; the optional `ADMIRAL_USERNS_SIZE` override is explicitly validated and passed through. `/etc/subuid` and `/etc/subgid` are configured from the selected host range policy. This is an Ansible/runtime configuration, not a binary hardcode.

## R26 runtime evidence

The existing Fedora Multi run installed the exact native R26 Fedora RPMs and deployed two independent real Harbor customers to the same Worker:

| Tenant | UID/GID map | PostgreSQL data owner on host |
|---|---|---|
| A | `720896+1024` | `721895:721895` |
| B | `721920+1024` | `722919:722919` |

The recorded probes found the ranges non-overlapping, app and PostgreSQL containers sharing the pod map, separate pod network/PID namespaces, separate SELinux MCS labels, and separate persistent database volumes. A could not see B's volume marker, read B's volume path, or modify B's persistent files. The application image `traefik/whoami:v1.10` and PostgreSQL 16 ran successfully. PostgreSQL backup, checksum-verified restore, and Admiral deprovision succeeded on R26.

Evidence is in `security-cross-client-probes-r26.log`, `worker-security-snapshot-r26-customer-a.txt`, `worker-security-snapshot-r26-customer-b.txt`, and `R26-FEDORA-MULTI-REPORT.md`. Their hashes are recorded in `R26-FEDORA-MULTI-SHA256SUMS.txt`; the entire manifest currently verifies with `sha256sum --check`.

## Checklist disposition

The following #307 Section C claims are supported by the R26 runtime evidence and may be checked:

- Separate pod user namespaces are observed for A and B.
- The tested A/B subordinate ranges are non-overlapping.
- Filesystem isolation improved in this workload: A's reads and writes against B's persistent volume were denied.
- Persistent-volume ownership is translated to distinct host IDs, with no manual host ownership workaround required in the tested case.
- The tested isolation benefit is real for this case; `UserNS=auto` is one layer alongside SELinux/MCS and volume separation.

The configured namespace/ID capacity was also compared with the documented
planning reference of 2,000 Pods and five services per Pod:

- The R26 Worker received `599379105` subordinate UIDs and the same number of
  GIDs, with `ADMIRAL_SUBID_COUNT=max_available`.
- `user.max_user_namespaces=32768` exceeds 2,000 pod namespaces;
  `num_locks=65536` exceeds the 10,000 container reference; and the configured
  `kernel.pid_max=4194304` and per-user `TasksMax=262144` exceed a one-process
  per-service baseline.
- At the 1,024-ID map observed for A/B, 2,000 Pods would consume 2,048,000
  subordinate IDs. Even a planning allowance of 65,536 IDs per Pod would
  consume 131,072,000, below the observed subordinate pool. These are
  configuration calculations, not proof of 2,000-Pod runtime capacity; the
  solver may need larger maps for some images, and hardware/workload resources
  may become limiting first.

The Ansible role also refuses to change namespace or lock settings when an
existing rootless Podman store is present with a different or missing config.
It does not renumber IDs or rewrite volume ownership. Therefore an in-place
conversion of existing pods to `auto` is **not supported**. The safe disposition
is to preserve the existing installation and perform a separately planned
application-level backup/restore into a newly provisioned `auto` instance; the
R26 PostgreSQL backup/restore pass is useful evidence for that mechanism, but
it was not a migration test.

The following remain unchecked because this candidate's evidence does not prove them:

- MariaDB and MySQL image compatibility, and compatibility with application images requiring IDs beyond those seen in this run.
- Full lifecycle coverage of rebuild and update under `auto`; the R26 test covered provision, resize, PostgreSQL backup/restore, and deprovision.

There is no evidence in this review that justifies removing the current `auto` default or adding further hardening. Keep the issue open until its remaining checklist items have direct evidence or an explicit `NOT TESTED` disposition.
