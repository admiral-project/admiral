# R26 customer ownership handler tests

Date: 2026-10-29 UTC  
Candidate root: `b6146a46be93f1a9c242361e27b10dbbb2164bf6`  
Admirald source: `8efa1dec8e9540210d9f86d016dce4677dcc6543`

The following focused tests passed against the exact R26 Admirald source:

```text
go test ./internal/api -run 'Test(HandleCustomerAppActionRejectsOtherCustomer|CustomerOperationStatusEnforcesOwnership|HandleCustomerAppsRejectsOtherCustomerProvision|CustomerBackupListAndReadAreInstanceScoped|CustomerRestoreRejectsBackupOwnedByAnotherCustomer)$' -count=1
ok  github.com/admiral-project/admiral/admirald/internal/api  0.009s
```

They exercise the customer HTTP handlers and Harbor authentication middleware with foreign customer or instance identifiers:

- A stop request for another customer's instance returns HTTP 403 before task dispatch.
- A foreign customer's operation lookup returns 403; an operation belonging to a different instance returns 404.
- Provisioning while claiming another customer ID returns 403.
- A foreign customer's backup list returns 403; reading a backup record belonging to a different instance returns 404.
- Restore using another customer's backup ID returns 404.

This supports the #307 control **“No se puede manipular una instancia ajena mediante IDs falsificados”** for the tested customer-facing handler paths. It is handler-level evidence, not a live cross-customer attack against a running cluster. Workload-to-workload access, host systemd user-manager boundaries, and the remaining backup and node-scope probes remain separate controls.

No product file changed; the candidate and six-cell matrix are unchanged.
