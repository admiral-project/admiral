# Fedora Rawhide Single-Node — RC6 E5 R26

Date: 2026-10-28 UTC  
Result: **PASS**  
Candidate: Epoch 5, `0.0.1rc6-26.fc46`, x86_64  
Guest: existing Fedora 46 Rawhide VM `rc6e5r18-ipv6-worker`; no VM was created.

## Exact candidate installation

The original clean-seed installation used the packaged `admiral-install --single-node` path and local Fedora-native R26 RPM repository. It completed at 2026-10-28 21:48 UTC with Ansible recap `ok=268 changed=110 unreachable=0 failed=0`. Fedora Rawhide remained SELinux Enforcing; the firewall roles verified the effective public-service/port rules; rootless Podman was configured for `admiral-apps` with `userns=auto`. PostgreSQL, Admirald, Fleet, Caddy, Harbor and Flagship were active, with no failed Admiral-related units.

The full final gate printed all six installed EVR/NEVRA values at the end and verified the expected R26 release. RPM SHA-256 values are in `../../fedora/SHA256SUMS` and `../../fedora/RPM-MANIFEST.tsv`; the source pins are in `../../source-pins.txt`. The RPM files are Fedora-native `.fc46` builds, not EL10 artifacts.

## Functional checklist

All six Single-Node lane stages passed on the same installed R26 packages, run `r26feds2`, 2026-10-28 22:01:45–22:09:15 UTC:

1. **Workload / idempotency / deprovision:** the local Worker was registered, active, healthy and available; `e2e-whoami` was applied and provisioned with the same idempotency key twice. Both calls returned the same operation and instance. The rootless workload reached running/healthy/available, PostgreSQL stored a marker, the loopback endpoint returned HTTP 200, and deprovision removed the matching containers, pod, volume, user units and files.
2. **Resize and data continuity:** a real `small → medium → small` resize succeeded. Health, HTTP 200 and the PostgreSQL marker were verified after each resize.
3. **Backup / restore:** a PostgreSQL backup completed with SHA-256 `5dec090f8f55338cc755a2ba420cac8a98d749f3627164e8db1bd6da6ac5fb7d`. Restore while running was rejected with HTTP 409. After pausing, checksum-verified restore succeeded; the original marker returned, the workload returned to HTTP 200, the backup tombstone remained `deleted`, and its artifact was absent after deletion. The instance was deprovisioned without residual resources.
4. **Control-plane / workload lifecycle:** pause/resume, stop/start, restart, and an Admirald restart succeeded; the workload returned to HTTP 200 after each supported recovery. The CLI check while Admirald was stopped failed as expected.
5. **Real reboot / persistence:** boot ID changed from `7bf6a3e1-c57d-4125-bb0a-44f6439361eb` to `e43fbefe-90d4-4864-85bb-a5683d5fb0a3`. Admiral, Fleet, PostgreSQL and the workload recovered; the persisted marker `r26-reboot-persisted` was readable and the endpoint returned HTTP 200. The reboot test instance was deprovisioned successfully.
6. **Final checks:** no failed Admiral-related units; the six installed RPMs still matched R26; rootless containers, pods and volumes were empty; the final boot ID matched the post-reboot ID.

The raw lane log contains operation IDs, poll outcomes, markers, HTTP statuses and final NEVRAs. Its SHA-256 is recorded in `R26-FEDORA-SINGLE-SHA256SUMS.txt`.

## Resource guard

The single-guest monitor used a corrected dynamic alert label and a 2.5 GiB host RAM floor, 32 GiB host disk floor, 512 MiB guest RAM floor and 2 GiB guest disk floor. Across 63 samples there were zero threshold alerts. Minimums were host RAM 2,819 MiB, host disk 34.07 GiB, guest RAM 1,156 MiB and guest disk 3.09 GiB. The VM was shut down cleanly after the cell; host availability returned to 5.2 GiB RAM with 35 GiB disk free. The earlier partial attempt stopped at its stricter 3 GiB floor and is historical only; it did not change the candidate.

That interrupted attempt left one stale operations-table row whose Fleet command was later marked `cancelled` (`instance is already deprovisioned`). It left no runtime resources and was not created by the successful `r26feds2` lane. The successful lane's own deprovision operations all reached `succeeded` and its postchecks found no resource residue.

## Candidate and release status

No product files changed during this cell. `PRODUCT_CHANGED=NO`; `CANDIDATE_INVALIDATED=NO`; R26 remains Epoch 5 Release 26. At the time this report was first written, Fedora Single was the only PASS cell and the other five cells were pending. This is a historical snapshot; see the final matrix update below.

## Final matrix update — 2026-10-29

The pending cells listed above were pending when this single-node run was recorded. Subsequent R26 runtime reports completed Rocky Linux 10 Single-Node and Multi-Node, CentOS Stream 10 Single-Node and Multi-Node, and Fedora Rawhide Multi-Node. The final candidate matrix is **6/6 PASS**. See the corresponding R26 reports under runtime/; no product or RPM change occurred between these cells.
