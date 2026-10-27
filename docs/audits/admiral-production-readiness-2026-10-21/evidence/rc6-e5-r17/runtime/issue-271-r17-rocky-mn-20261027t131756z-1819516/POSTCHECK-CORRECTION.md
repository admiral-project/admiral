# #271 final inventory assertion correction

Both redirect variants completed their two periodic health reports with the
declared HTTP 302 accepted, `healthy/available` state, and zero requests to the
reachable listener. Each deprovision operation succeeded.

The first harness version used `podman pod ps -a`; the installed Podman does
not accept `-a` for that subcommand. That command's error was not fatal in the
first compound inventory shell, so that initial inventory conclusion is not
counted. The corrected read-only postcheck used `podman ps -a`, `podman pod
ps`, and `podman volume ls` separately with fail-fast behavior. It confirmed
both instances are `deprovisioned`, no matching containers, pods, or volumes
remain, the test image is absent, the listener is stopped, and the temporary
app definition is inactive. See `postcheck.log`,
`podman-inventory-postcheck.log`, and `postcheck-assertions.log`.

Classification: `HARNESS_DEFECT`. No Admiral product artifact changed; R17
remains the tested candidate.
