# Issue #270 — staged seed RPM signature verification

**Result: PASS for the issue-specific helper gate.** Issue #270 remains open; no release matrix cell is credited by this result.

## Tested candidate and environment

- Root source commit: `ee65cdb3613cd02b8cb41431c2d06e0cc3caf656`.
- Helper source: `scripts/prepare-audit-seed-guest.sh`, blob `9f9259c68f5ee8327a61d0e4c0a6afa22127f7bb`.
- Guest: fresh overlay from Fedora Rawhide 46 x86_64 seed, SHA-256 `01f5a6772943027a35b429e3a40d28de6ed22cb92f3d00e3858517269a992b1e`.
- Each scenario used a separate disposable VM overlay. All were removed after their logs and package state were collected.
- Eight Fedora `.fc46` helper RPMs were staged. NEVRA, Epoch and SHA-256 are in `RPM-MANIFEST.tsv`.
- Expected public-key fingerprint: `7103D33100F674D0B3DFAD17B943D0C834ED6667`.

## Results

| Scenario | Expected | Observed | Evidence |
|---|---|---|---|
| Correct key | Import exact key; all eight RPM signatures pass; local DNF install succeeds without `NOKEY`; normalized update check allows only newer RPM releases of the same upstream Python versions | PASS: eight signature `OK` results, zero `NOKEY` matches, helper produced the seed, and all eight check-update results were same-upstream-version RPM release bumps | `cases/correct-key/guest-run.log` |
| Missing key | Fail before any staged RPM installation | PASS: exit 1 with the required-key error; installed helper-package NEVRAs were unchanged | `cases/missing-key/` |
| Wrong key | Reject fingerprint before any staged RPM installation | PASS: exit 1; supplied fingerprint was `C1FDE9BC160A326249ED4A2CB04878BC37D63DCC`; installed helper-package NEVRAs were unchanged | `cases/wrong-key/` |
| Altered RPM | Reject modified signature before any staged RPM installation | PASS: one appended byte to the staged Alembic RPM caused signature verification failure; installed helper-package NEVRAs were unchanged | `cases/tampered-rpm/` |

The original Release 71 run showing DNF `NOKEY` warnings is retained at `cases/original-r71-nokey.log`. The corrected successful run is retained beside it under `cases/correct-key/`.

## Harness observations

- The initial missing-key VM creation encountered a stale DHCP lease: the requested `.155` address was leased to a prior disposable guest, so the new guest received `.227`. The guest was reached only after reading its actual libvirt lease and validating its generated SSH host key with `HostKeyAlias`; the test then passed. The mismatch and cleanup are recorded in `cases/missing-key/vm-create.log`.
- The first tampered-RPM SSH attempt ran before cloud-init had enabled SSH and was refused. No helper was invoked on that attempt. The same VM was retried after strict-host-key SSH became available and the test passed; this setup failure is retained in `cases/tampered-rpm/RESULT.txt`.
- No product RPMs or source were changed for this check. Fedora helper RPMs are not Admiral RPMs, and this targeted test does not validate an RC6 runtime cell.

## Verdict

The implementation fix already present in root `main` meets the #270 issue-specific acceptance criteria on a fresh Fedora Rawhide seed. Keep #270 open as required by the release tracker; require the exact no-Epoch candidate gate separately before release validation.
