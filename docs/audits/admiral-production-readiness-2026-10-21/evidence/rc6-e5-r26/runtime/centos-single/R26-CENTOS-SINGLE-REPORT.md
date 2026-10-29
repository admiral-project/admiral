# R26 CentOS Stream 10 Single-Node Runtime Cell

Date: 2026-10-28 UTC  
Result: **PASS**  
Candidate: Epoch 5, 0.0.1rc6-26.el10, x86_64  
Guest: CentOS Stream 10, existing libvirt domain rc6e5r18-ipv6-worker; no VM domain was created.

## Exact candidate installation

The installation used the recently updated CentOS Stream 10 seed and the six local EL10 R26 RPMs. Their SHA-256 values matched ../../el10-SHA256SUMS; NEVRA and checksums are in ../../el10-RPM-MANIFEST.tsv. Component and root pins are in ../../source-pins.txt.

The secure admiral-install --single-node --validation-seed path completed at 2026-10-28 23:09:43 UTC. Ansible recap: ok=261 changed=108 unreachable=0 failed=0 skipped=159. CentOS Stream remained SELinux Enforcing. The final gate verified all six expected 5:0.0.1rc6-26.el10 package versions, active Admiral-related services, and no failed Admiral-related units.

The Fleet role reported userns=auto, max_user_namespaces=32768, and kernel.pid_max=4194304. It allocated non-overlapping subordinate UID and GID ranges with 599,379,105 IDs each. The candidate workload completed the full Single-Node lifecycle.

## Functional checklist

All six stages passed on the installed R26 packages, run r26cs10s1, from 2026-10-28 23:09:57 through 23:16:47 UTC:

1. **Workload, idempotency, and deprovision:** the same idempotency key returned the same operation and instance. The application became healthy and returned HTTP 200. Deprovision removed its containers, pod, volume, units, and files.
2. **Resize and data continuity:** a real small → medium → small resize succeeded; health, HTTP 200, and the PostgreSQL marker remained intact after both changes.
3. **Backup and restore:** PostgreSQL backup succeeded. Restore while running was correctly rejected with HTTP 409. After pause, checksum-verified restore returned the original marker and HTTP 200. The backup tombstone remained deleted, its artifact was removed, and workload resources were cleaned up.
4. **Instance and control-plane lifecycle:** pause/resume, stop/start, restart, and Admirald restart succeeded. The workload returned to HTTP 200; the CLI failed as expected while Admirald was stopped.
5. **Real reboot and persistence:** the guest boot ID changed. Admiral, Fleet, PostgreSQL, and the workload recovered; the PostgreSQL marker remained; deprovision succeeded.
6. **Final state:** all six R26 RPMs had the expected EL10 NEVRA, required services were active, there were no failed Admiral-related units, and no rootless containers, pods, or volumes remained.

The stage summary is R26-CENTOS-SINGLE-STAGES.txt. Resource samples are in R26-CENTOS-SINGLE-RESOURCES.jsonl.

## Resource guard and cleanup

A 10-second monitor ran for 112 samples. It recorded **zero threshold alerts**. Configured graceful-stop floors were host RAM 2.5 GiB, host disk 32 GiB, guest RAM 512 MiB, and guest disk 2 GiB. Observed minima were host RAM 3.538 GiB, host disk 46.627 GiB, guest RAM 0.685 GiB, and guest disk 6.389 GiB. Final host availability after the guest was shut down was 5.5 GiB RAM and 48 GiB disk.

At cell completion, the CentOS guest was shut down cleanly, the existing domain was restored to its original Fedora disk, and the temporary CentOS overlay was deleted. All three existing domains are shut off. The 17 obsolete R21/R23/R24/R25 overlays previously removed are recorded in ../rocky-single/R26-HOST-OBSOLETE-OVERLAYS-REMOVED.tsv.

Private raw installer and lane logs remain on the validation host because installer output can include generated credentials. Their SHA-256 values are recorded in R26-CENTOS-SINGLE-PRIVATE-LOG-SHA256.txt; generated report and non-secret resource evidence are published alongside this file.

## Candidate and release status

At the time this report was first written, CentOS Stream 10 Single-Node was the third PASS cell and the matrix stood at **3/6 PASS**. Rocky Multi, CentOS Stream 10 Multi, and Fedora Multi were then pending. This is a historical snapshot; see the final matrix update below.

No product source or RPM changed in this cell. Candidate R26 remains valid; this runtime result does not close #307 or release tracker #308.

## Final matrix update — 2026-10-29

The pending cells listed above were pending when this single-node run was recorded. Subsequent R26 runtime reports completed Rocky Linux 10 Multi-Node, Rocky Linux 10 Single-Node, and Fedora Rawhide Multi-Node. The final candidate matrix is **6/6 PASS**. See the corresponding R26 reports under runtime/; no product or RPM change occurred between these cells.
