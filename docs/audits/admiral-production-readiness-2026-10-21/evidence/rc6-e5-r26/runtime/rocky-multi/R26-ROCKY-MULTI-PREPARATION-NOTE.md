# R26 Rocky Multi-Node preparation note

Classification: harness-only issue; no product change and no candidate invalidation.

The first disposable overlay-preparation helper attempted to hash the 2.3 GiB Rocky seed with `Path.read_bytes()`, briefly raising the helper RSS to about 1 GiB. Resource inspection caught this before any guest started. The helper was stopped; all three existing domains were restored to their original Fedora disks, all temporary Rocky overlays from that attempt were removed, and host RAM availability returned to 5.4 GiB.

The setup was then prepared again using a streaming SHA-256 calculation. A resource guard is in place for the runtime run. It requests only graceful `virsh shutdown` when the host drops below 2,560 MiB available RAM or 32 GiB free disk, or a guest drops below 256 MiB available RAM or 2 GiB free disk. It never destroys a VM or kills a process.

No VM was started during either preparation attempt. The R26 RPM files and product source remain unchanged.
