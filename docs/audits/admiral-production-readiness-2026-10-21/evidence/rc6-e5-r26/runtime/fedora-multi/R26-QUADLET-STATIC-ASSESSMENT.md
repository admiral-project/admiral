# R26 Fedora Multi — Quadlet and Podman controls for #307

Date: 2026-10-28 UTC  
Candidate: Epoch 5, `0.0.1rc6-26.fc46`, x86_64  
Classification: source review using the exact selected Fleet SHA and R26 runtime evidence; documentation only.

## Findings

### Runtime controls observed

The R26 customer A/B snapshots show the app and PostgreSQL containers with
`NoNewPrivs=1`, seccomp mode 2, private PID namespaces, and
`privileged=false`. SELinux was Enforcing; the two pods had distinct MCS labels.
The Podman-managed infra helper showed `NoNewPrivs=0`; that exception is
recorded rather than represented as an Admiral service-container result.

The effective app capability set was
`CAP_CHOWN,CAP_DAC_OVERRIDE,CAP_FOWNER,CAP_FSETID,CAP_KILL,CAP_SETGID,
CAP_SETUID,CAP_SETPCAP,CAP_NET_BIND_SERVICE,CAP_SYS_CHROOT,CAP_SETFCAP`.
It did not include `CAP_SYS_ADMIN`, `CAP_NET_ADMIN`, `CAP_SYS_PTRACE`, or
`CAP_NET_RAW`. PostgreSQL reported `CapEff=0`. Fleet does not add capabilities;
the renderer intentionally does not drop all OCI defaults because that breaks
entrypoints which need to switch users (including MariaDB). The app set is
therefore a compatibility default, constrained by rootless user namespaces,
`NoNewPrivileges`, seccomp, and SELinux rather than a per-image minimized set.

The R26 kernel cgroup snapshot showed the pod's effective 256 MiB memory limit
and 1 CPU quota, with `pids.max=2048` for each service container. No OOM or
memory-exhaustion scenario was triggered; that test remains pending.

### Source controls reviewed

- The Pod Quadlet uses `Network=pasta` and publishes only declared service
  ports to the configured publish address. It does not request host network,
  PID, IPC, or privileged mode.
- Service Quadlets set `NoNewPrivileges=true`. The renderer mounts only declared
  named/shared volumes and Podman secrets; it does not add host paths, Podman
  sockets, or a user D-Bus socket.
- The RPM scriptlet creates
  `/etc/containers/systemd/users/<uid>/admiral` as root:root `0755`. Fleet
  writes Quadlets as root with mode `0644`; environment files are mode `0600`,
  and per-instance env/data directories are `0700`/`0750`. Quadlet writes use
  `O_NOFOLLOW`.
- Image policy is configured with the `docker.io,quay.io,registry.redhat.io`
  registry allowlist. The renderer rejects missing explicit references and
  `:latest`, and accepts explicit tags or digests. Explicit tags can still be
  retargeted by a registry; this policy is not digest-only pinning.
- Secret names are scoped to instance/service/key. R26 A/B runtime probes found
  cross-customer secret names/paths unavailable and distinct secret values.
- Quadlet value sanitization removes line breaks and NULs and replaces shell/
  Quadlet metacharacters; environment values are escaped. Existing exact-SHA CI
  covers the renderer's sanitizer, image-policy, and rendering tests.

## Section E disposition

These controls have direct source/runtime evidence and can be marked checked:

- `NoNewPrivileges=true` for Admiral app/DB service containers (with the
  Podman infra-helper exception above).
- Effective capabilities and the compatibility reason for retaining the OCI
  defaults; no broad host/network capabilities are present in the observed
  app, and PostgreSQL has none.
- Seccomp, SELinux, mount/socket boundary, effective CPU/memory/PID limits,
  Quadlet path/file handling, image-reference/registry policy, A/B volume and
  secret separation, and safe Quadlet/environment rendering.

Memory-exhaustion behavior remains unchecked. The review makes no claim that
the workload or VM survives an OOM; a future probe must be strictly cgroup
bounded and guarded against host/guest resource floors before execution.

Evidence sources: `worker-security-snapshot-r26-customer-a.txt`,
`worker-security-snapshot-r26-customer-b.txt`,
`security-cross-client-probes-r26.log`, the exact Fleet source SHA in
`../../source-pins.txt`, and CI in `../../R26-CI-STATUS.md`. The R26 Fedora
Multi SHA-256 manifest covers the runtime snapshots and probe log.
