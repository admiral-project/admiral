# CentOS Stream Worker re-registration evidence

This guest was deliberately removed from Admirald during the #278 node-removal probe. Before re-registration, the Admin node inventory contained only the independent Portal. Re-running the packaged `admiral-install --worker-node --validation-seed --yes` workflow against the same `5:0.0.1rc6-2.el10` RPM set restored `rc6e5cs-worker` as role `worker`, `active/healthy`, WireGuard `10.99.0.2`. The separate Portal remained role `portal`, `active/healthy`, WireGuard `10.99.0.3`.

The installer completed in 261 seconds: Ansible `ok=146 changed=15 unreachable=0 failed=0`; the control-plane handshake succeeded on the first attempt, the temporary bootstrap key was rejected after completion, and the pinned operator key remained valid. RPM NEVRAs did not change on Admin or Worker. This is manual re-registration/recovery evidence after intentional node removal; it does not claim automatic failover.

The complete mode-0600 installer transcript is retained on the lab host at `/var/lib/libvirt/images/admiral-validation/evidence/rc6-r2-epoch5/multinode-centos/worker-reregister.log`, SHA-256 `151a87ea30153be1d2af15e136f3684ec612076941e04aad4661622d80a17231`. It is not copied into Git because it contains provisioning details. Sanitized node inventories are adjacent to this report.
