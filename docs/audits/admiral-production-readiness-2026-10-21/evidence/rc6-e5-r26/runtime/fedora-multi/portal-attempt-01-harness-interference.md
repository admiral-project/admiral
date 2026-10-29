# Fedora Multi Portal attempt 01: harness interference

The initial clean Portal install did not complete. This attempt is retained as diagnostic evidence, not counted as a passed cell.

- Candidate: `0.0.1rc6-26`, Epoch 5, Fedora Rawhide 46, x86_64.
- Installer: `portal-install.log`, started `2026-10-28T20:16:30Z`, ended `2026-10-28T20:23:18Z`, SSH exit 1.
- Ansible recap: `ok=127 changed=55 unreachable=1 failed=0`.
- Failure: `admiral_fail2ban : Wait for the Fail2ban SSH jail to become ready`; Ansible timed out after 12 seconds waiting for privilege escalation.
- Before fail2ban started, the old resource monitor attempted `admiral-ssh@192.168.122.22` before Admin had delivered the Portal SSH key. Portal sshd recorded five `Invalid user admiral-ssh` failures from Admin (`192.168.122.20`) between 20:16 and 20:17 UTC.
- Fail2ban started at 20:22:16 UTC, replayed those journal entries and banned the Admin address. The monitor had been replaced with a key-readiness check at 20:18; its later samples did not make authentication attempts before key delivery.
- The Admin address was unbanned after recording the event. The installation had already timed out and was not counted as a pass.

Classification: validation-harness interference. The pre-enrollment SSH probes from the old monitor caused the failures; no Admiral package, source, RPM, or installer configuration was changed. The monitor now checks the Admin-delivered key and known-host files before probing a spoke. The existing Portal domain will be reimaged from the same Fedora seed and the clean setup repeated with the corrected monitor. The first overlay and log are retained for audit.

Retained failed Portal overlay: `/var/lib/libvirt/images/admiral-validation/overlays/rc6-e5-r26-fedora-portal.attempt-01.qcow2`.
SHA-256 before reimage: `d32712e70a41432576275a490c56452da67b29c7c14339a2bd2a4988930ec78a`.
The failed overlay was 426 MiB on disk, had a 5 GiB virtual size, and used the same Fedora Rawhide 46 seed as the clean retry. The portal VM was shut down gracefully before reimaging. At shutdown, host RAM available was 3.7 GiB and disk available was 36 GiB.

Clean retry preparation: the failed overlay was retained as `portal.attempt-01.qcow2`; a new 193 KiB copy-on-write overlay was created at the domain's original disk path from the same Fedora seed. The existing libvirt domain was restarted (domain ID changed from 10 to 11); no domain was added. The stale `portal-001` SSH delivery key and known-host entry were removed from Admin so the corrected monitor reports enrollment pending instead of probing the fresh guest.
