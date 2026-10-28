# RC6 E5 R20 — Issue #255 512 MiB admission attempt

**Result: NOT RUN — safely rejected before an instance was created.**

The initial disposable migration fixture requested the inherited 512 MiB tier on source worker `rc6e5r18-ipv6-worker`. Admiral returned `no_node_available_for_requested_tier` with `insufficient_ram_commit_capacity`. At that point the worker commit limit was 800,597,606 bytes and committed RAM was 536,870,912 bytes, leaving 263,726,694 bytes, less than the requested 536,870,912 bytes.

The provision operation was `op_bb2712a4600983e9` and remained failed with an empty instance ID. No workload or migration was created. The temporary app definition was deactivated and removed. No VM, existing fixture, or database was changed. The successful R20 run uses a 128 MiB disposable tier and is documented in the adjacent `issue-255-r20-...002633z...` directory.
