# R26 Fedora Multi — Fleet source review for #307 Section G

Candidate: Epoch 5, `0.0.1rc6-26.fc46`, x86_64  
Fleet source: `edc0a0d486eb102e9aaa4f250a08f777d7441f12`  
Classification: static review of the selected R26 source; no product changes or runtime tests.

## Findings supported by source

### Task origin and node scope

Production Fleet is configured with a rootless `RemoteRunner`. It rejects executables
other than `podman`, routes operations only to the lifecycle or setup helper, and
launches those helpers through `runuser -u admiral-apps` with the user's HOME,
runtime directory and D-Bus address. The production Fleet entry point sets
`RemotePodman=true`; the separate backup executable runs as the already-rootless
workload user. I found no production fallback from these paths to rootful Podman.

The claim endpoint requires the authenticated node ID to match the request and the
queue selects commands only for that node. Fleet rejects unsigned tasks, verifies
the Ed25519 signature and a 15-minute timestamp window, and rejects replayed task
IDs within that window. This is evidence for node-scoped task origin; it does not
replace customer/instance authorization in Admirald.

### Paths, cleanup and failure reporting

Fleet validates instance IDs against path separators, `..` and NUL. Generated
Podman names use `SafeName`; the control plane also validates application service
names before it creates signed tasks. File writers use `O_NOFOLLOW`, and
package-managed directories are checked before sensitive writes. Deprovision
derives pod, container, volume and secret names from the signed task. It retains
Quadlet and instance metadata and returns failure when managed runtime cleanup
fails; it reports success only after cleanup, Quadlet removal, reload and data
directory removal complete.

## Section G dispositions

The following four Section G checks are supported by this source review:

- No production rootful Podman fallback in the Fleet execution path.
- Instance and resource names are validated/normalized across the trusted task
  path and generated resource names.
- Generated file writes guard against following a final-component symlink.
- Cleanup is limited to names derived from a signed task for the authenticated
  node, and cleanup failures are not reported as success.

The following checks remain open rather than being inferred from static evidence:

- Least privilege has not been proven necessary/minimal by a capability-level
  experiment. The system service runs as root with a bounded capability set
  (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`); `NoNewPrivileges=false`
  is documented as required by its rootless-user management path.
- The setup helper intentionally supports `podman exec` and `podman run`; app
  `setup_command` is executed with `sh -c` inside the target workload container.
  The Harbor customer UI accepts a catalog slug/tier and fixed actions, not app
  YAML or a host command; customer API handlers check ownership before queuing
  lifecycle and backup effects. This supports the Section A customer-command
  boundary, but does not make setup shell safe against a compromised trusted
  principal.
- The authenticated Harbor service principal can write app definitions through
  the v1 apps route, which dispatches POST to `SaveAppDefinition`. This is a
  pre-existing service-principal boundary, not a customer-facing route or an
  R25→R26 change. It remains a residual risk to evaluate under the existing
  issue scope; no hardening change was made during this regression review.
- Fleet verifies that tasks come from Admirald and target its node, but does not
  independently authorize a customer against an instance ID. That control must
  be evidenced at the control-plane/API boundary and in the tenant authorization
  section.
- The helpers receive task data needed to provision secrets and operate backup/
  restore. Field-by-field secret minimization was not established in this pass.
- Command runners sanitize common credential patterns from arguments and
  stderr, but this review did not demonstrate that every task error and metadata
  path excludes sensitive values.

No commands or tests were run. The R26 candidate and its six RPMs are unchanged.
The final R26 runtime matrix is 6/6 PASS. This static review leaves the
explicitly listed Section G controls without direct evidence open in #307; it
does not claim that the security checklist is complete.
