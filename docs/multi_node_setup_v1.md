multi_node_networking_v1.md

Admiral Multi Node Networking Contract v1

Status

Proposed — Phase 6

Purpose

This document defines the official networking contract for distributed workloads in Admiral.

The objective is to support a simple, secure and operational multi-node architecture without introducing Kubernetes-style complexity.

The networking model intentionally separates:

- setup/control operations
- workload traffic

into distinct channels.

Design Principles

The networking architecture MUST preserve Admiral's core principles:

- simple
- secure by default
- rootless-first
- Enterprise Linux friendly
- inexpensive to operate
- minimal moving parts
- operationally understandable

Admiral multi-node networking is intentionally not a service mesh, cluster overlay or distributed control fabric.

The model is:

«Central control plane + remote workers + private workload network.»

---

1. Networking model

Admiral uses a dual-channel networking architecture.

Channel A — Setup and Control Plane

Transport:

«SSH»

Purpose:

- node bootstrap
- installation
- upgrades
- diagnostics
- troubleshooting
- remote administration
- automation execution (Ansible)

Authentication:

Preferred:

«SSH public/private key»

Password-based SSH MAY exist but MUST NOT be the recommended deployment path.

Control plane traffic includes:

- bootstrap execution
- Ansible deployment
- RPM installation
- configuration rendering
- service lifecycle
- diagnostics
- node recovery

This channel is administrative.

It is NOT used for workload traffic.

---

Channel B — Workload Network

Transport:

«WireGuard VPN»

Purpose:

- Caddy reverse proxy traffic
- Admirald API calls to fleet
- fleet heartbeat
- worker runtime communication
- backup/restore transfer
- workload routing

This network is private.

No workload communication should depend on public Internet interfaces.

This channel forms the internal private network of Admiral.

---

2. Official topology

The supported topology for v1 is:

«star topology»

Example:

Internet
    |
cloud.domain.com
    |
+------------------------------------+
| control plane (admin-node)         |
| admirald                           |
| caddy                              |
| cockpit                            |
| PostgreSQL                         |
| wg0 = 10.99.0.1                    |
+------------------------------------+
          |
    ---------------------------
    |             |           |
+----------------+  +----------------+  +----------------+
| worker node1   |  | worker node2   |  | portal node    |
| fleet          |  | fleet          |  | admiral-harbor |
| podman         |  | podman         |  | PostgreSQL     |
| cockpit-bridge |  | cockpit-bridge |  | cockpit-bridge |
| wg0 10.99.0.2  |  | wg0 10.99.0.3  |  | wg0 10.99.0.100|
+----------------+  +----------------+  +----------------+

Only these communication paths are required:

- control plane → worker
- worker → control plane

Worker-to-worker communication is out of scope.

Mesh networking is out of scope.

---

3. Routing contract

Public traffic enters Admiral through a centralized ingress.

Ingress:

«Caddy running on control plane»

Workers MUST NOT expose public ingress directly.

The routing contract is:

public fqdn
→ caddy
→ worker wireguard ip
→ workload port

Example:

blog.customer.com
→ caddy
→ 10.99.0.2:49123

Workers are addressed via WireGuard private IP.

Public worker IPs MUST NOT be required for runtime routing.

---

4. API communication contract

Admirald ↔ Fleet communication MUST prefer WireGuard transport.

Example:

https://10.99.0.2:8443

instead of:

https://203.0.113.10:8443

Fleet API SHOULD NOT require public exposure.

Firewall posture:

Preferred:

WG UDP port only
SSH port only

Example:

- 22/tcp
- 51820/udp

All other administrative interfaces SHOULD remain private.

---

5. SSH contract

SSH is the official setup transport.

SSH responsibilities:

- bootstrap worker
- install RPMs
- configure rootless Podman
- configure WireGuard
- install fleet
- rotate configs
- upgrade node
- run diagnostics

SSH is not a workload transport.

SSH tunnels are explicitly out of scope.

Admiral does not rely on SSH tunnels for runtime routing.

---

6. Ansible contract

Ansible is the official deployment mechanism for distributed nodes.

The installer MUST support:

admiralctl node bootstrap

or equivalent wrapper around Ansible.

The workflow:

1. SSH to target node
2. Prepare host
3. Configure rootless runtime
4. Install WireGuard
5. Configure peer
6. Validate WG connectivity
7. Install admiral-fleet
8. Configure fleet
9. Start services
10. Register node in admirald
11. Validate heartbeat

Success criteria:

The node becomes:

healthy
connected
schedulable

without manual intervention.

---

7. Node registration contract

A registered node MUST expose:

- node_id
- node_name
- wireguard_ip
- administrative_ip
- fleet_version
- runtime_capabilities
- rootless_user
- health_state

Admirald MUST prefer:

wireguard_ip

for workload communication.

---

8. Security model

Official security posture:

Setup plane:

SSH + public/private key

Workload plane:

WireGuard private network

Runtime services SHOULD remain private.

Public ingress MUST terminate in Caddy.

Workers SHOULD NOT expose arbitrary public workload ports.

Recommended exposure:

22/tcp
51820/udp

Only.

---

9. Supported scope (v1)

Supported:

- single control plane
- multiple workers
- centralized ingress
- rootless Podman
- EL10 family
- WireGuard private networking
- SSH bootstrap
- Ansible automation

Not supported:

- worker mesh
- multi-control-plane HA
- service mesh
- overlay SDN
- Kubernetes networking
- dynamic east-west routing
- worker-to-worker workloads
- automatic workload migration
- public ingress on workers

---

10. Operational claim

The official v1 networking claim is:

«Admiral distributed workloads run through a simple private WireGuard network, while setup and lifecycle automation are performed over SSH using Ansible.»

This separation intentionally minimizes complexity while preserving secure multi-node operation.
