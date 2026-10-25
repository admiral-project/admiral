# Issue #295 — RC6 Release 4 Fedora Rawhide installed-worker check

Date: 2026-10-25 UTC
Environment: Fedora Rawhide 46 x86_64 KVM guest `rc6r4-fedora-single`, fresh updated Fedora seed.
Candidate: all six native Fedora RPMs, Epoch 0, `0.0.1rc6-4.fc46`.
Scope: Harbor-created customer and Harbor's packaged API client/worker. No PayPal endpoint or sandbox was used.

The exact package build/source pins and artifact SHA-256 values are in [`RC6 Release 4 build evidence`](../../rc6-release4-build/CANDIDATE.md) and its Fedora NEVRA/hash manifests.

## Result

**PASS for the corrected customer flow on this exact candidate.** The issue's original 403 was not reproduced. The installed Harbor registration route generated the customer ID; the packaged Harbor client provisioned and read the instance; before the prepaid date the worker did not deprovision it; after the test dates were expired it queued exactly one deprovision operation. The operation succeeded, the instance became `deprovisioned`, and a second worker run created no duplicate. The final rootless Podman container, pod, and volume inventories were empty and the Harbor fixture was removed.

Customer `hcus_7604b72769814f80` had no PayPal subscription ID. Instance `inst_78f42f35f070dd19` was deprovisioned by operation `op_9de4b98295688cee` with status `succeeded`.

## Reproduction

1. Apply `fixtures/e2e-whoami.yaml` using the guest's configured operator CLI.
2. Run `scripts/rc6/issue-295-harbor-flow.py` under the `admiral` account with `/etc/admiral/harbor.env`, working directory `/usr/lib/admiral/harbor`, and `PYTHONPATH=/usr/lib/admiral/harbor`. This registers the customer through Harbor and provisions through Harbor's installed client.
3. Run the installed `admiral-harbor-worker.service` before expiry; inspect the customer and verify zero deprovision operations.
4. Run helper action `expire CUSTOMER_ID`, start the installed worker, and verify exactly one customer-scoped deprovision operation.
5. Poll that operation using the installed Harbor client until terminal; require `succeeded`.
6. Run the worker again; require one deprovision operation total, inspect `deprovisioned`, verify empty rootless runtime inventories, then clean the fixture.

The repeatable customer-scoped operation poller is [`issue-295-poll-operation.py`](../../../scripts/rc6/issue-295-poll-operation.py).

## Evidence

All raw logs were retained. The first pre-expiry harness run reached the worker and showed the customer remained running, but its embedded Python heredoc consumed the JSON pipeline; it is not counted. The corrected pre-expiry rerun passed. The first operation poll lacked a Flask app context; the corrected poller then returned `succeeded`. The first cleanup wrapper used the validator's inaccessible current directory for the rootless account; a corrected wrapper changed to `/` and confirmed empty inventories before fixture cleanup. Those harness failures did not represent Admiral failures and are retained below.

| Capture | SHA-256 | Interpretation |
|---|---|---|
| `issue-295-fedora-r4-setup.log` | `e94ecca09caea207602777320614e570d30cf6fcca1b67052fde74031fd76fb7` | Harbor registration and provision succeeded; Harbor-generated customer ID, `paypal_subscription_id_present=false`. |
| `issue-295-fedora-r4-preexpiry.log` | `e5e2f8f75fe3fdefeb7ea1f743f439631dbfe86dc7bf3e091b68da57b9e9a13d` | Initial harness parser error after worker run; not counted. |
| `issue-295-fedora-r4-preexpiry-rerun.log` | `e79dfbd65a12f47e06987ecaa00482c48843b667e0b452bcbc4c338053c5d9ea` | Customer remained running; zero deprovision operations before prepaid expiry. |
| `issue-295-fedora-r4-expiry-worker.log` | `b53c6823fbf086134601c8c30ab22fec1f208dd5df3c9f07dc6d5aeea46c2ad8` | Expiry advanced locally; installed worker queued one operation, `Errors: 0`. |
| `issue-295-fedora-r4-operation.log` | `6ba53ec43915769bc883d096be403cc7ed59e049f3524a473b3bfc89d8bc74a5` | Initial poller missing app context; not counted. |
| `issue-295-fedora-r4-operation-rerun.log` | `040904a4c644d4f19bc89c8cd7b7aeaa955a171b77fbfa28fb95385c4b785a0c` | Corrected customer-scoped poll returned operation `succeeded`. |
| `issue-295-fedora-r4-rerun-cleanup.log` | `ece7a69b8ca162583564d48e19c52e007ff7a2356738acb285f7ae7061ff28bf` | Second worker run left exactly one successful deprovision; instance was `deprovisioned`. The Podman command failed before inventory output because `sudo` inherited the validator's inaccessible working directory; not counted for cleanup. |
| `issue-295-fedora-r4-cleanup-rerun.log` | `a2afb5dcd9e600c5bdfd641ea9414456090c602c7553c3e9d73408a8ecf0b509` | Corrected cleanup verified no containers, pods, or volumes and removed the Harbor fixture. |

The issue remains open and labeled `posible-false-positive`: this exact-candidate run supports the corrected flow but does not establish why the earlier synthetic fixture returned 403. This issue-specific result gives no Fedora Single-Node matrix-cell credit by itself.
