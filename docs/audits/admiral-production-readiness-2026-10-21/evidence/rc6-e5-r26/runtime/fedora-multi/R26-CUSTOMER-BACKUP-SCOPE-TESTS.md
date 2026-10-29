# R26 customer lifecycle and backup authorization tests

Date: 2026-10-29 UTC  
Candidate root: `b6146a46be93f1a9c242361e27b10dbbb2164bf6`  
Admirald source: `8efa1dec8e9540210d9f86d016dce4677dcc6543`

The following focused tests passed against the exact R26 Admirald source:

```text
go test ./internal/api -run 'Test(HandleCustomerAppActionRejectsOtherCustomer|CustomerBackupListAndReadAreInstanceScoped|CustomerRestoreRejectsBackupOwnedByAnotherCustomer|CustomerRestorePOSTDispatchesAndQueuesS3Restore|CustomerBackupPolicyBlocksDisabledRestoreAndManualBackup)$' -count=1
ok  github.com/admiral-project/admiral/admirald/internal/api  0.009s
```

Evidence and scope:

- A stop request using another customer's instance ID returns 403 before any task is queued.
- Backup list/read are scoped to the route instance: foreign customer list access returns 403 and a record from another instance returns 404.
- Restore rejects a backup owned by another customer. A valid restore is accepted only for the authenticated route instance, authorized tier policy, and selected service; the queued task uses that instance's node.
- The Harbor-facing customer backup handler exposes list/read and restore only; it does not implement customer delete/download methods.

This supports the #307 controls for cross-customer lifecycle, backup ownership, restore identity/authorization/destination, and customer access to another customer's backups. It is API handler/middleware evidence, not a live cluster attack or external-object-store test. External backup object tampering and workload-to-workload secret isolation remain separate controls.

No product file changed; the candidate and six-cell matrix are unchanged.
