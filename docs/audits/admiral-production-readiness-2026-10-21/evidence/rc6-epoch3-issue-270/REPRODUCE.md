# Reproducing issue #270

The raw guest logs and eight signed helper RPM inputs are included alongside this file. The guest helper under test is `../../scripts/prepare-audit-seed-guest.sh`.

## Positive run

1. Create a disposable Fedora Rawhide x86_64 VM from a freshly updated Fedora seed using `scripts/create-audit-vm.sh` and a seed-backed qcow2 overlay.
2. Copy `inputs/staged-rpms/*.rpm` to `/var/tmp/admiral-candidate-python-rpms/` in the guest, and copy `inputs/RPM-GPG-KEY-admiral-validation` to `/var/tmp/admiral-validation.pub`.
3. Copy `scripts/prepare-audit-seed-guest.sh` to `/var/tmp/prepare-audit-seed-guest.sh`.
4. Run from `/` in the guest:

   ```bash
   sudo env ADMIRAL_AUDIT_RPM_GPG_KEY_FILE=/var/tmp/admiral-validation.pub \
     bash /var/tmp/prepare-audit-seed-guest.sh
   ```

5. Require eight `rpmkeys --checksig` signature `OK` results, no `NOKEY`, successful DNF local-package installation, seed completion, and `dnf check-update` output limited to newer RPM releases of the same pinned upstream Python versions.

## Negative runs

Use a new seed-backed guest overlay for each run and stage the same eight inputs.

- **Missing key:** run the helper without `ADMIRAL_AUDIT_RPM_GPG_KEY_FILE`; require failure with the missing-key message.
- **Wrong key:** use `inputs/wrong-public-key.gpg`; require fingerprint rejection.
- **Altered RPM:** append one byte to a copy of `python3-alembic-1.20.1-4.fc46.noarch.rpm`, use the correct public key, and require signature rejection.

For each negative run, capture the package NEVRAs before and after. They must be identical so no staged candidate RPM was installed. Use `scripts/cleanup-audit-vm.sh` only after the test guest is shut off; preserve its logs first.

`RPM-MANIFEST.tsv` records the tested package identities and hashes. `SHA256SUMS` records all committed evidence artifacts, including the original `NOKEY` log and test outputs.
