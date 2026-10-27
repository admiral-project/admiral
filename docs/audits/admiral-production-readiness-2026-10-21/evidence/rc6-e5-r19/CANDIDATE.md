# Admiral RC6 Epoch 5 Release 19 candidate

**Candidate:** `0.0.1rc6`, Epoch 5, Release 19, x86_64.

**Package build/signing:** PASS for six native EL10 RPMs and six native Fedora Rawhide RPMs.

**Runtime matrix:** 0/6 for this candidate. **Gold:** NO.

Release 18 is invalidated because Release 19 changes installed `admirald`
behavior for migration and ships updated `admiralctl` migration documentation.
All six required cells must be repeated on the signed Release 19 packages.
Evidence from earlier releases is retained but does not count toward the R19
matrix.

## Package builds

- Rocky Linux 10.2 x86_64 built the six `.el10` RPMs natively. Build and
  packaged tests passed; see [`el10/build.log`](el10/build.log) and
  [`el10/build-environment.txt`](el10/build-environment.txt).
- Fedora Rawhide x86_64 built six `.fc46` RPMs in the official Fedora Rawhide
  environment. Build and packaged tests passed; see
  [`fedora/build.log`](fedora/build.log) and
  [`fedora/build-environment.txt`](fedora/build-environment.txt). No EL10 RPM
  was used to build or install on Fedora.
- `scripts/validate-release-refs.py` passed in both environments. The six
  Admiral specs all use Release 19. Manifests list exact NEVRA and SHA-256;
  all 12 RPM signatures and both repository metadata signatures verify with
  validation key fingerprint
  `8D2E8FC99FB218979157C5DBFCC63E30ED44F66E`. See
  [`source-pins.txt`](source-pins.txt), both distro manifests, and
  [`repo-signature.log`](repo-signature.log).

## Release gates

- The required matrix is Rocky Linux 10, CentOS Stream 10, and Fedora Rawhide
  x86_64, Single-Node and Multi-Node: **0/6** on R19. No R18 cell is counted
  after the product change.
- GitHub currently has four actionable open issues: #255, #271, #305, and
  #307. #106 is the excluded PayPal gate; #304 is closed. No issue is closed
  by this build record.
- #255's deterministic PostgreSQL regression, repeated `-race` regression,
  and component CI pass locally/on GitHub. Its required real Multi-Node
  migration, restore, cutover, preserved logical instance ID, and state
  timeline have not yet been captured on R19.
- The component CI runs for the selected five component SHAs are green. Root
  repository CI for the R19 pin/spec update is pending.
- Gold remains ineligible while any actionable issue is open or any matrix
  cell is incomplete.

## Resource snapshot

After the RPM builds and signing, the host had 3.9 GiB available RAM, 699 MiB
swap in use, and 56 GiB free disk. The EL10 build was capped at 2.5 GiB and the
Fedora Rawhide build container at 1.5 GiB with two CPUs. The Fedora builder
used Fedora-native `.fc46` helper packages only.
