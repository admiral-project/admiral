# R26 Fedora Multi — SELinux and systemd user manager for #307 D/F

Candidate: Epoch 5, `0.0.1rc6-26.fc46`, x86_64  
Classification: R26 Fedora Multi snapshots and installation evidence plus source review; no product changes or new runtime test.

## D. SELinux and storage

The R26 installer uses `admiral_selinux` to enable enforcing mode, persist
`SELINUX=enforcing` in `/etc/selinux/config`, and assert the live mode and boot
setting. The R26 Fedora Multi Admin, Worker and Portal installation logs show
that task completing successfully. The R26 Fedora Single report records a real
VM reboot and Fedora remaining SELinux Enforcing.

During the existing R26 A/B run, both app and PostgreSQL processes had
`system_u:system_r:container_t` labels with separate MCS categories for A and
B. Their Podman mount labels carried those corresponding categories. SELinux
was Enforcing during both snapshots and the cross-customer file probes. The
renderer and generated Quadlets do not set `label=disable`; the Podman snapshots
show active per-pod MCS labels.

The R26 source review of host paths found the package-managed Quadlet directory
root-owned and non-writable by workloads, Quadlet files mode `0644`, environment
files `0600`, and per-instance environment/data directories `0700`/`0750`.
Generated writes use `O_NOFOLLOW`. The A-to-B probes failed to find/read B's
volume marker and failed to write to B's persistent volume; their results are
recorded in `security-cross-client-probes-r26.log`.

Not established by this evidence: the filesystem SELinux label on the backing
volume directory was not separately read with `ls -Z`/`stat`; shared-volume
cross-customer semantics were not exercised; no AVC journal review was captured.
Those D checks remain open.

## F. systemd user manager

R26 snapshots show that both workloads run below the same `admiral-apps`
`systemd --user` manager, with delegation of the CPU, memory and PID controllers.
The per-customer Quadlet and generated unit names are distinct. The containers
do not mount the user D-Bus socket or the rootless Podman control socket; the
R26 probe in the database containers found neither interface, and the app/DB
snapshots contain only the declared per-instance database volume, not a host
control-socket mount.

The kernel cgroup files under each pod show `memory.max=268435456` (256 MiB)
and `cpu.max=100000 100000` (one CPU); the service container scopes show
`pids.max=2048`. These are Podman cgroup controls, not `systemd --user` unit
`MemoryMax` or `CPUQuota`: the generated pod unit reports those systemd
properties as unlimited, while its `TasksMax` is bounded. Similarly, the pod
unit has `NoNewPrivileges=no`, while the app and database processes have the
container-level `NoNewPrivs=1`. This distinction is why the observed runtime
settings are attributed to the container boundary rather than overclaimed as
systemd user-unit hardening.

The review therefore finds no separate per-instance user manager: all customer
units share the `admiral-apps` manager, but the tested containers had no mounted
path to control it. No additional systemd-user directive is recommended from
this evidence; no product hardening change is justified without a demonstrated
reachable control path. A direct attempt from an app container to query/stop a
peer unit, and a failure-injection check for impact on another instance, were
not run and remain open.

## Evidence and limits

Primary runtime sources are `worker-security-snapshot-r26-customer-a.txt`,
`worker-security-snapshot-r26-customer-b.txt`, and
`security-cross-client-probes-r26.log`. Installer evidence is in the exact
Fedora Multi Ansible logs; reboot evidence is in
`runtime/fedora-single/R26-FEDORA-SINGLE-REPORT.md`. The R26 Fedora Multi
manifest covers these existing artifacts. This static assessment does not
restart or complete the Fedora Multi cell and does not claim a global SELinux
or systemd audit across all release OSes.
