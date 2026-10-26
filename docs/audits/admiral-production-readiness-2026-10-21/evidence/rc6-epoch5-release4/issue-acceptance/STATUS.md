# Issue acceptance status for `rc6-e5-r4`

Updated 2026-10-26 after closing #296, #297, and #298. Candidate identity remains `5:0.0.1rc6-4`; no product artifact changed during this validation work. The six-cell x86_64 matrix and the six-repository CI record remain the evidence in `../CANDIDATE.md`. This report does not declare the candidate Gold.

## Closed after exact-candidate runtime evidence

| #296/#297/#298 | CentOS Stream 10 Single-Node, all six native `0.0.1rc6-4.el10` RPMs: dev install completed; Fleet localhost reached healthy/available; Fail2ban was absent in dev and secure reconvergence passed; both Harbor background one-shots succeeded with `ENV=development`, then secure reconvergence restored `ENV=production` and removed dev drop-ins. | `centos-single/dev-node-install-retry.log`; `centos-single/dev-node-runtime.log`; `centos-single/issue-213/dev-to-single-rc6e5r4a.log`; see hashes in `SHA256SUMS`. Git commit `9a59c434043b4f4c94e3577af87ce28bb1e4064c`. |

| Issue | Result | Evidence |
|---|---|---|
| #202 | Rocky 10.2 Single-Node: backup mode 0600, directory 0700, checksum and size match; restore recovers marker; symlink write-through rejected; deprovision succeeds. | `rocky-single/issue-202/volume-backup-rc6e5r4a.log` |
| #300 | Rocky 10.2 and Fedora Rawhide Single-Node: first deprovision succeeds; repeated request gets HTTP 409; operation and task inventories do not grow. | `rocky-single/issue-300-repeat.log`; `fedora-single/issue-300-repeat-retry.log` |
| #205 | Rocky 10.2 and Fedora Rawhide Single-Node: after provision/deprovision and second secure reconciliation, `rpm -V admiral-common` is clean and common-owned roots retain expected modes/owners. | `rocky-single/issue-191-205-final.log`; `fedora-single/issue-191-205-final.log` |

## Additional final-candidate probes (not yet sufficient to close)

| Issue | Result so far | Remaining gate |
|---|---|---|
| #259 | Four user-manager restart/recovery cycles passed in Rocky, CentOS, and Fedora Single-Node; zero false healthy/available samples, SQL marker preserved, cleanup succeeded. | Multi-Node coverage requested in the issue comments. |
| #260 | Declared PostgreSQL service outage passed on all three Single-Node OS cells: 61 samples over 60 seconds, unavailable within about 3 seconds, zero stale healthy/available samples after 5 seconds, marker survived recovery. | Multi-Node coverage requested in the issue comments. |
| #271 | Both redirect targets (loopback and node address) received zero requests across periodic health reports in Rocky, CentOS, and Fedora Single-Node. | Multi-Node coverage requested in the issue comments. |
| #296/#297/#298 | Clean CentOS Single-Node installed directly as `--dev-node` from exact RPMs. Fleet localhost registered healthy; Fail2ban was absent and not installed; both Harbor one-shots succeeded with `ENV=development`; secure reconvergence removed dev overrides and set `ENV=production`. | Evidence is staged for publication; no known issue-specific runtime gate remains. |
| #213 | CentOS exact-candidate dev-to-secure reconvergence rejected an untrusted self-signed leaf, reissued a CA-signed leaf with loopback and node-IP SAN, verified both, kept Harbor/Flagship TLS healthy, restored Fleet healthy, and removed dev overrides. | Fedora repeat requested by the latest issue comment. The general runner also flagged unrelated base `kdump.service`; Admiral units were healthy. |

Candidate component/root CI is green on the exact recorded source SHAs: root run `40268230411`, `admirald` `40263188438`, `admiral-fleet` `40069777965`, `admiralctl` `40030034925`, `admiral-flagship` `39795263415`, and `admiral-harbor` `40171847383`.

## Still open

These issues remain open and must retain their issue-specific acceptance criteria:

`#295 #294 #291 #289 #288 #287 #286 #278 #271 #260 #259 #257 #255 #240 #229 #228 #216 #213 #201 #191 #190 #182 #181 #106`.

#191 has final-candidate Single-Node evidence on Rocky and Fedora, including clean `rpm -V admiral-common`, Harbor directory ownership/mode, and no directory discrepancy in `rpm -V admiral-harbor`. Its requested hub Multi-Node check remains outstanding.

#106 requires a real PayPal Sandbox checkout and verified webhook/transaction flow. No PayPal Sandbox credentials are available in this runner; this issue cannot be truthfully closed without that evidence.

## Resource and platform record

Four issue-validation VMs remain: Rocky and Fedora are shut down; CentOS secure single-node and dev-to-secure guests are running. Host status: 55 GiB disk available, 2.9 GiB memory available, 1.0 GiB swap used. Preserve updated seeds and clean disposable guests only through `scripts/cleanup-audit-vm.sh` when their evidence is complete. No AlmaLinux result is counted in the active matrix.
