# Preserved failed harness attempt 1 — independent Portal via Caddy

Candidate: `Epoch 5: 0.0.1rc6-1.el10`; three-guest CentOS Stream 10 x86_64 lab.

Observed output:

```text
routed_portal_test_email=rc6-e5-caddy-20261025T234827Z-fcf474@example.test
independent_portal_signup=pending
independent_portal_pending_login=rejected
independent_portal_customer_flow=FAIL: pending customer is absent from Harbor review queue
```

The HTTP flow had reached Harbor through the strict-CA Caddy route. DB inspection confirmed a pending customer record with the same email lowercased (`rc6-e5-caddy-20261025t234827z-fcf474@example.test`, signup status `pending`). The test helper compared the original uppercase `T/Z` email against the lowercase HTML row. This is a confirmed runner defect; it is not evidence of a product failure or a PASS. Tracked in [issue #299](https://github.com/admiral-project/admiral/issues/299). The disposable pending customer was removed before the corrected rerun.
