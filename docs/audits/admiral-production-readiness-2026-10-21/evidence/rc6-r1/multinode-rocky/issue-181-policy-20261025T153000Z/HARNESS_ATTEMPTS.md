# Issue #181 harness attempt record

- **Environment-file launcher attempt:** sourcing `/etc/admiral/harbor.env` as a shell script failed because the systemd environment file contains an unquoted display-name value with spaces. The test flow did not start and no customer or instance was created. The final runner uses `systemd-run`'s `EnvironmentFile=` parser.
- **Wrong customer identifier attempt:** the probe used Harbor's integer user ID as `X-Admiral-Customer-ID`; the API returned `403 {"error":"access denied"}` at the ownership check. This is not a tier-policy result and is excluded from PASS evidence. The created synthetic instance was deprovisioned successfully.
- **Successful run:** the runner obtained Harbor's `public_id` (`hcus_...`) using a read-only query and passed that value to the customer-scoped API. The run and result are in `issue-181-run.log`.
- **Prior paused test instance cleanup:** a paused synthetic `e2e-backup-policy` instance from a prior probe was identified from its operation history, deprovisioned, and followed by an empty Worker runtime inventory. It was not counted as evidence for the final successful run.

No credentials or password values are recorded here.
