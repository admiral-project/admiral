# Admiral Multi Node Setup v1

## Status

Implemented for beta validation; operational details may still change before 1.0.

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

The required release-matrix topology has three distinct hosts:

* `--admin-node`: `admirald`, PostgreSQL, Caddy and Flagship;
* `--worker-node`: Fleet and rootless Podman workloads;
* `--portal-node`: Harbor customer portal, registered as a WireGuard spoke.

The Release 75 Multi-Node runs instead used `--admin-portal-node` with worker
spokes. Those runs did not test a dedicated portal and are invalid for the
Multi-Node release gate. The release gate covers Fedora Rawhide, Rocky Linux
10 and CentOS Stream 10 on x86_64, with Single-Node and Multi-Node cells for
each distribution; see master tracker
[#277](https://github.com/admiral-project/admiral/issues/277) for the
authoritative status. AlmaLinux 10 is Tier 2 and outside the active matrix
because of the COPR environment limitation tracked in
[#276](https://github.com/admiral-project/admiral/issues/276).

Example:

Internet
    |
cloud.domain.com
    |
+------------------------------------+
| admin node                         |
| admirald, PostgreSQL, Caddy,        |
| Flagship, cockpit, wg0 = 10.99.0.1 |
+------------------------------------+
          |
    ---------------------------
    |                         |
+----------------+  +----------------+
| worker node    |  | portal node    |
| Fleet, Podman  |  | Harbor         |
| cockpit-bridge |  | cockpit-bridge |
| wg0 10.99.0.2  |  | wg0 10.99.0.3  |
+----------------+  +----------------+

The worker and portal are separate spokes. A worker cannot run Harbor, and a
portal cannot run Fleet. `--admin-portal-node` is a supported combined profile
for other deployments, but it does not satisfy this release-matrix topology.

The required communication paths are:

- admin/control plane → worker and portal
- worker and portal → admin/control plane
- worker → dedicated portal on WireGuard TCP/5001 for authenticated uploaded-backup restore

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

Each hub↔spoke peer also uses a unique WireGuard `PresharedKey`. The peer
exchange playbook generates the 256-bit PSK on the admin hub, stores it only in
the root-owned `0600` peer fragments and rendered WireGuard configurations,
and keeps Ansible output hidden. Existing peer fragments preserve their PSK;
removing a peer fragment and onboarding that node again generates a new one.
The PSK is an additional defense-in-depth secret, not a replacement for the
WireGuard key pair or the firewall policy.

Every `admiral-install --worker-node` or `admiral-install --portal-node` run
automatically reconciles hub-to-spoke WireGuard peers after registration and
before the first handshake check. This generates or preserves the hub↔spoke
PSK and updates both ends before a Worker must report a healthy Fleet
heartbeat. When an independent Worker and Portal are both registered, the same
playbook also reconciles their direct peer and firewall state. The installer
builds its Ansible inventory from Admirald's active node inventory and uses the
per-node SSH delivery keys plus host-key pins verified during onboarding.
Keep those files in the root-only `/var/lib/admiral/ssh-delivery` directory
while automatic reconciliation is required. The installer fails with an
actionable error if a registered spoke lacks its key or verified host-key pin;
host-key checking is never disabled. An operator may run `wireguard-peers.yml`
manually for repair, but routine onboarding does not require that manual step.

A Portal hosted on the Admin machine uses the Admin's own WireGuard endpoint;
it is not treated as an independent spoke and does not need a second SSH
delivery identity. Direct Worker-to-Portal peer exchange applies only to
independent Worker and Portal machines.

Removing an idle Worker or Portal with `admiralctl nodes remove <node-id>`
reconciles the remaining spokes before deleting the node record. The operation
removes the departing Worker's direct peer and TCP/5001 allow rule from the
remaining Portal, or removes the departing Portal's peer from remaining
Workers. It is serialized with onboarding. If a remaining spoke cannot be
reached through its pinned SSH identity, removal fails closed with HTTP 503
and retains the node and token; restore SSH access and retry. Drain and
deprovision workloads before removing a node.

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

## 7. Spoke reconvergence

`admiral-install --worker-node` and `admiral-install --portal-node` are
re-runnable. On a previously onboarded spoke the installer:

1. verifies the supplied SSH host fingerprint;
2. tries the persisted `admiral-ssh` identity;
3. if the bootstrap key has already been revoked, uses the matching
   `/var/lib/admiral/ssh-delivery/<node-id>.ed25519` key automatically;
4. runs Ansible through that non-root account with `sudo -n`;
5. treats removal of an already absent bootstrap key as success.

The operator must keep the per-node delivery key until reconvergence is no
longer required. `--no-revoke-ssh-key` remains available for the first
onboarding run when the operator explicitly needs to preserve bootstrap access,
but is not required for normal subsequent runs.

### Worker decommission

Remove a worker through `admiralctl nodes remove` only after its workloads have
been deprovisioned. On the hub, the API revokes the worker's WireGuard address
from the live interface and persistent peer configuration before deleting the
node record and token. A local systemd socket activates a root helper with
`CAP_NET_ADMIN`; the `admirald` service itself stays unprivileged. If peer
revocation fails, node removal returns an error and the database transaction
keeps the node and token so the operator can retry. The helper serializes peer
addition and removal with the same lock used during worker bootstrap.

On an existing hub, update Admiral packages and rerun the admin installation
profile once to enable the local revocation socket before removing workers.

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

Fleet publishes only services that declare an application port, bound to the
worker WireGuard address. That publication is an intentional trust boundary:
the endpoint can receive untrusted traffic through Caddy and can also be
reached by a co-resident workload through the worker address. Published
applications MUST enforce their own authentication, authorization, rate
limits, and input validation; they MUST NOT rely on Caddy being their only
possible caller.

Each instance uses a separate rootless `pasta` network namespace. This keeps
pod localhost, unpublished ports, volumes, and secrets private to the
instance. It does not turn a host-published port into a Caddy-only endpoint.
Database and other private services MUST therefore omit the application port
declaration unless external reachability is intentional.

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
