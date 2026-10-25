# Issue #271 — HTTP health probes must not follow redirects

**Disposition: targeted diagnostic acceptance passed on Rocky Linux 10.2 and Fedora Rawhide x86_64.** The issue remains open pending repeat against the final no-Epoch candidate and the complete release gate. These checks do not count as matrix cells.

## Candidate and test

- Installed packages: `Epoch 3 / 0.0.1rc6 / Release 5`; exact NEVRAs and SHA-256 are in the sibling [EL10](../rc6-epoch3-issue-260/RPM-MANIFEST-el10.tsv) and [Fedora](../rc6-epoch3-issue-260/RPM-MANIFEST-fedora.tsv) manifests.
- Fleet source: `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`, which configures both provision-time and periodic HTTP checks to return 3xx without following it.
- Guest test scripts: `scripts/rc6/issue-271-single.sh` and `scripts/rc6/issue-271-guest.sh`.
- The in-repository Go fixture returns `302` with a caller-selected `Location`; it is statically compiled, imported into the guest's rootless Podman store, and does not pull an external image.
- A local HTTP listener on port 18081 records any redirected request. Each test provisions the workload with `expected_status: 302`, then observes at least two Fleet periodic health reports.

## Results

| Guest | Redirect destination | Periodic reports | Fleet state | Listener requests |
|---|---|---:|---|---:|
| Rocky Linux 10.2 | `127.0.0.1:18081` | 2 | healthy/available, expected 302 accepted | 0 |
| Rocky Linux 10.2 | Guest address `192.168.122.153:18081` | 2 | healthy/available, expected 302 accepted | 0 |
| Fedora Rawhide | `127.0.0.1:18081` | 2 | healthy/available, expected 302 accepted | 0 |
| Fedora Rawhide | Guest address `192.168.122.154:18081` | 2 | healthy/available, expected 302 accepted | 0 |

All four instances deprovisioned, and the test confirmed no matching rootless containers remained. The final listener log was empty on both guests. The successful host logs and complete guest evidence archives are:

- Rocky log SHA-256: `37a6c21c86afeb2e5e0cf41731ba58ce4b5988b89f0ee319d04719dd0ca3cefc`.
- Rocky guest archive SHA-256: `1da494721e9a8a1e029a646ddafbc4b14286db5a6d9ad34221036a1844b5f8bf`.
- Fedora log SHA-256: `921653f201892889f8b805c8a9be67367741e4daf08b97b6ad9e8bba7fa60a2a`.
- Fedora guest archive SHA-256: `cd98da0487d914cea7c4124f6985e0e7e046c7e4c5c2bf57f9e5ebb9ea97dd29`.

Each successful run directory includes `SHA256SUMS`. Earlier attempts are retained beside the successful results and excluded from the verdict: they exposed harness setup problems (non-root `runuser`, the image-policy rejection of `localhost`, and waiting for the first fresh healthy report). The corrected test uses `sudo -u`, an allowed `docker.io` reference backed by a local image, and waits for a healthy baseline before measuring periodic checks.

## Validation scope

The four checks prove the redirect target was never contacted during provision-time or periodic Fleet health probing for this diagnostic RPM set. They are issue-specific evidence only; the active formal matrix remains **0/6** until the exact final no-Epoch candidate passes all required Single-Node and independent-Portal Multi-Node cells.
