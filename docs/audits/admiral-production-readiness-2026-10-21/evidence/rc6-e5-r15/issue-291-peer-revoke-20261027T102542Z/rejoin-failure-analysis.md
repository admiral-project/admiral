# R15 #291 re-onboarding failure analysis

## Reproduction

After `admiralctl nodes remove rc6e5r15-rocky-worker` removed the Worker's peer,
the supported `admiral-install --worker-node` flow registered the same Worker
again and added its public key to the Admin. Installation then timed out at the
Fleet healthy-heartbeat gate after 120 seconds. The Fleet service was running,
but its HTTPS request to the Admin over WireGuard timed out.

## Cause

The removed Worker retained its previous hub preshared key in its local
`/etc/wireguard/wg-admiral.conf`. Removal correctly deleted the Worker's
durable peer fragment on the Admin. During re-onboarding, the Fleet Ansible role
re-added the hub peer without a preshared key and waited for a healthy heartbeat
before the installer's later `wireguard-peers.yml` reconciliation could restore
matching hub and spoke configuration. The live Admin peer therefore had no
preshared key while the Worker still used its old one. Neither side completed a
WireGuard handshake.

The diagnostic compared persisted and live key state without recording key
material: the Admin fragment and live peer had no PSK; the Worker's persisted
and live hub peer had a PSK and matched each other. Public keys and AllowedIPs
were correct. The Admin WireGuard service, interface, and TCP/8080 listener were
active, so this was not a host resource or service outage.

## Classification and corrective direction

This is a product defect in the spoke installer/Ansible ordering. R15 does not
pass #291 re-onboarding. Run the existing spoke peer reconciliation before the
Fleet heartbeat gate, then require a fresh healthy heartbeat after hub/spoke
WireGuard state has converged. Any product change here invalidates R15 and
requires a new six-RPM candidate and full six-cell validation.

The Worker was re-registered but did not report a healthy heartbeat at the end
of this reproduction. Do not count this run as a successful re-onboarding.
