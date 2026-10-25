# RC6 Release 1 Rocky Multi-Node — issue #278

**Result: PASS for the issue-specific runtime acceptance check. This is not a Multi-Node matrix-cell pass.**

## Candidate and environment

- Admiral candidate: `0.0.1rc6-1.el10`, RPM Epoch `0` (not explicitly set).
- Root source: `267da7ebd739a0703c276ec8d4770ffa31a45f25`; root CI run [40194076634](https://github.com/admiral-project/admiral/actions/runs/40194076634) succeeded.
- Platform: Rocky Linux 10.2 x86_64.
- Topology: separate Admin, Worker, and independent Portal guests. The test exercised Admin and Worker; Portal remained separate and was later reconciled with the Worker.
- Worker node ID: `rc6r1-worker`; guest: `rc6r1rocky-worker-r2`.
- All six EL10 RPM NEVRAs and SHA-256 values are recorded in `candidate-rpm-manifest-el10.tsv`. The installed Admin and Worker candidate identities are in `candidate-hub.txt` and `candidate-worker.txt`.
- Reproduction script: [`multinode-node-removal-history.sh`](../../../../scripts/rc6/multinode-node-removal-history.sh), SHA-256 `4dd5ed649f8f2dbf622448616aceba2b64b172809c256760845aad16ee515071`.

## Procedure and observed result

The script installed the `e2e-whoami` fixture and provisioned `inst_c1415ca7c9a5405b` on the Worker.

1. Before removal, the instance returned HTTP 200 from its Worker endpoint (`metadata.txt`).
2. Removing the Worker while the test instance was active was rejected. The instance remained `running/healthy/available`, the node remained registered, and its endpoint still returned HTTP 200 (`remove-active-instance.log`, `instance-after-rejected-removal.json`).
3. The test instance was deprovisioned successfully and the Worker runtime inventory was empty (`deprovision.json`, `worker-clean-before-node-removal.txt`).
4. Before idle-node removal, PostgreSQL contained the terminal customer instance plus two successful operations: provision and deprovision.
5. After idle-node removal, the instance row remained with its terminal status and detached `node_id`; both operation rows and their IDs, actions, and states were unchanged. The removed node was absent from inventory and `nodes show` returned not found (`customer-app-*-node-removal.json`, `operations-*-node-removal.json`, `nodes-after-removal.json`, `node-show-after-removal.log`).

The pre-existing synthetic Harbor restore instance had still been counted as commercially active despite being stopped, so the first harness attempt correctly failed its one-active-instance assertion and cleaned up only its own workload. That attempt is retained in the sibling `issue-278-node-removal-20261025T145303Z/` directory. Its 743-byte test backup was preserved and checksum-verified before the synthetic instance was deprovisioned; the instance and its operation history were then also preserved through node removal. The observed status change to cancelled/deprovisioned was the requested lab cleanup, not an Admiral node-removal side effect.

## Lab recovery after the destructive scenario

The Worker was re-enrolled with the packaged `admiral-install --worker-node` helper. An initial invocation using explicit SSH-user/key flags completed Ansible registration and produced a fresh heartbeat, but returned nonzero in its final SSH lockdown check. The subsequent WireGuard reconciliation playbook completed for all three guests with zero failed/unreachable tasks. Final runtime checks showed:

- Worker RPMs remained `0:admiral-common-0.0.1rc6-1.el10` and `0:admiral-fleet-0.0.1rc6-1.el10`.
- Worker and Portal systemd services were active; Admin reported the Worker healthy and available.
- Worker-to-Portal `/ready` returned HTTP 200 with TLS verification result 0.
- Portal self-check `/ready` returned HTTP 200 with TLS verification result 0, and `harborctl ping` reached Admirald.

The installer postflight return code is preserved in `worker-reenroll.log`; it is not hidden or counted as a product PASS. Re-enrollment and service-level recovery were independently checked afterward.

## Evidence inventory

`metadata.txt`, `candidate-hub.txt`, `candidate-worker.txt`, `provision.json`, `instance-before-removal.json`, `remove-active-instance.log`, `instance-after-rejected-removal.json`, `deprovision.json`, `worker-clean-before-node-removal.txt`, before/after customer and operation snapshots, `remove-idle-node.log`, `nodes-after-removal.json`, `node-show-after-removal.log`, the re-enrollment and WireGuard reconciliation logs, `nodes-after-worker-reenrollment.json`, `worker-after-reenrollment-runtime.txt`, `worker-to-portal-ready-after-reconcile.txt`, `portal-self-check-after-reconcile.txt`, and `SHA256SUMS`.

The issue-specific check passes on the exact no-Epoch Release 1 RPM candidate. The six-cell release matrix remains **0/6** until every required scenario passes on the same candidate in each OS/mode cell.
