# ERPNext image snapshot

Checked: 2026-10-28 UTC, before R21 E2E.

The example previously used `docker.io/frappe/erpnext:v15.10.0` (Docker Hub last updated 2024-01-10). Docker Hub's official `frappe/erpnext` tag API lists `v15.124.1` as the latest version-15 release, last updated 2026-10-27 13:33:16 UTC. The multi-platform tag digest is `sha256:77939536a7764c26bcb59c449f4a60283ceca8df01a6b0e45ade704eb05f9742`; this x86_64 example pins its `linux/amd64` manifest digest `sha256:7229b744703f057bf9fc3af7c863f7cdb404ff42a546cfa5dd2ca198157654e4`.

All six ERPNext service image references in `examples/apps/erpnext.yaml` now use `docker.io/frappe/erpnext:v15.124.1@sha256:7229b744703f057bf9fc3af7c863f7cdb404ff42a546cfa5dd2ca198157654e4`. This is an example definition update, not packaged Admiral product code; it does not require an RPM rebuild or invalidate the six RPM runtime matrix cells.

Sources:

- Docker Hub tags: https://hub.docker.com/r/frappe/erpnext/tags
- ERPNext v15.124.1 release: https://github.com/frappe/erpnext/releases/tag/v15.124.1
