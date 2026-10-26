# Issue #278 — RC6 Epoch 5 / Release 2 node removal history

Date: 2026-10-26 UTC. Result: **PASS** on CentOS Stream 10 x86_64 using three real KVM guests: Admin `rc6e5cs-admin`, Worker `rc6e5cs-worker`, and independent Harbor Portal `rc6e5cs-portal`. The exact local candidate was Epoch 5 / Release 2; package NEVRAs and hashes are in `../../x86_64/RPM-MANIFEST.tsv`. Source root: `e710237fd908feabf17b12fb61d08429deb21e52`.

## Procedure and result

Reproduction: run the tracked `scripts/rc6/multinode-node-removal-history.sh` with the validator key, pinned Admin/Worker known-hosts, Admin/Worker IPs, Worker node ID, `el10`, Epoch `5`, and package Release `2`.

Test ID `RC6-MN-NODE-REMOVE-HISTORY-01`, started `2026-10-26T01:32:13Z` and completed `01:32:35Z`, test instance `inst_5ee1b5a8b486aa5c`:

1. Verified all six exact candidate packages on Admin and common/Fleet packages on Worker.
2. Provisioned the workload specifically onto the Worker; it reached HTTP 200 over its Worker endpoint.
3. Tried to remove the Worker while the instance was active. The CLI refused with exit 1 and explicit `1 active instance` guidance; the instance remained running/healthy and HTTP stayed 200.
4. Deprovisioned the test instance. Verified the Worker had no matching containers, pods, volumes, or files.
5. Captured the terminal customer-app row and its successful provision/deprovision operation history from PostgreSQL. Removed the now-idle Worker.
6. Re-read PostgreSQL and verified the customer-app row fields and both operation records were unchanged; the Worker was absent from the node inventory and `nodes show` returned not found.

Result markers are in `centos/clean/metadata.txt`, `customer_instance_preserved=True`, `operation_history_preserved=True rows=2`, and `node_count=1 removed_node_absent=yes`. All raw outputs are covered by `centos/clean/SHA256SUMS`.

## Preserved precondition failure and cleanup

The first attempt is retained at `centos/` with `exit_code=1`: it correctly refused Worker removal because an earlier disposable `e2e-portal-free` test instance was still active, so the observed active count was 2 (the existing fixture plus the new test). Its EXIT handler deprovisioned the newly created instance successfully. We inspected the pre-existing item and confirmed it was a synthetic e2e test app/customer in this isolated lab, then deprovisioned it explicitly. Before/after API state, successful operation, empty runtime inventory, and checksums are retained in `centos/preexisting-test-instance-cleanup/`. We reran the complete scenario after removing that precondition, and only the clean rerun is counted as PASS.

This is issue-specific Multi-Node evidence on CentOS Stream 10. It is not a complete Multi-Node matrix-cell PASS and gives no Rocky or Fedora Multi-Node credit. No source changes were needed; the fix is in the installed candidate.
