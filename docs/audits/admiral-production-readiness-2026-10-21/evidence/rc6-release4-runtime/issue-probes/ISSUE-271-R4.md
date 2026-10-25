# Issue #271 — HTTP health checks must not follow redirects

Date: 2026-10-25 UTC
Candidate: RC6 Release 4, Epoch 0 (`0.0.1rc6-4`)
Scope: installed Admiral on Rocky Linux 10.2 and Fedora Rawhide 46, x86_64, Single-Node diagnostic guests. This issue probe is not a complete matrix cell.

## Result

**PASS on both tested guests.** For each guest, a disposable workload declared HTTP health status `302` and redirected to a listener outside the workload. Fleet continued to record the workload as `healthy` / `available` over at least two subsequent health-report updates. The redirect listener received zero requests for both loopback and guest-address redirect targets. Both workloads were deprovisioned and their matching Podman containers were absent afterward.

This demonstrates the redirect-following regression check on this candidate and these two single-node environments. It does not establish behavior for other response codes, multi-node routing, or all health-check failure paths.

## Environment and reproduction

| OS | Guest | Candidate RPM | Result |
|---|---|---|---|
| Rocky Linux 10.2 x86_64 | `rc6r4-rocky-single` (`192.168.122.70`) | Native EL10 `0:0.0.1rc6-4.el10` | PASS |
| Fedora Rawhide 46 x86_64 | `rc6r4-fedora-single` (`192.168.122.71`) | Native Fedora `0:0.0.1rc6-4.fc46` | PASS |

Reproduction uses the tracked `scripts/rc6/issue-271-single.sh` and `scripts/rc6/issue-271-guest.sh`. Run the host script once per guest with OS, SSH destination, guest address, SSH key, known-hosts file, and output directory. The script builds a temporary redirect-target server on the host, imports it into the guest's rootless Podman store, applies a disposable app with the redirect health endpoint, and checks two successive `last_health_checked_at` changes for each redirect target. It then deprovisions and checks for a matching residual container. No production systems were touched.

## Evidence

| OS | Capture | SHA-256 |
|---|---|---|
| Rocky | `issue-271-rocky/redirect-health.log` | `fe8fff7b957a8be82d242d4e014b8f928e7bfba1a516866be10d2cb36aab744d` |
| Rocky | `issue-271-rocky/guest-evidence.tar.gz` | `ccf02aa1d5a895f3dbefa3530051e4ff32a837bc68a6b729af13f0340f5535a9` |
| Fedora | `issue-271-fedora/redirect-health.log` | `7da8987a3b627b73efd4f1470d2583d767dda7c57ab27d3dd8c7cc257edfafca` |
| Fedora | `issue-271-fedora/guest-evidence.tar.gz` | `676e862acc7c147bc63562028cff833c81c979e82b7236ffed527b44ee7abeb7` |

The guest archives contain the disposable app definition, import/provision/deprovision outputs, redirect-listener logs, and per-capture checksums. The raw logs show zero redirect-target hits and `issue_271_redirect_health_checks=PASS` for each OS.
