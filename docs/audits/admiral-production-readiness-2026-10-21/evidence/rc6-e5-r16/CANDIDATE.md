# RC6 Epoch 5 Release 16 candidate

**Status: packaging metadata prepared; native builds, CI and runtime validation pending. Not Gold.**

Release 15 failed the supported Worker re-onboarding path in #291. The
installer/Ansible correction is root source commit
`de88e350a90d81d329fa7fe7aea32bf9e790d203`: spoke peer reconciliation now runs
before the first handshake, and the Worker health gate runs after reconciliation.
This is a product change, so R15 cannot close #291 or serve as the new release
candidate. The failure analysis is recorded in the R15 evidence directory.

All six Admiral RPM specs increment to Release 16. The source pins and fetched
`origin/main` comparisons are recorded in [source-pins.txt](source-pins.txt).
`python3 scripts/validate-release-refs.py` passed after the Release 16 pin and
spec edits. CI and native build results will be added here before installing
the candidate.

## Release gates

- Native EL10 and Fedora Rawhide builds: pending. Fedora must produce native
  `.fc46` RPMs from the same component sources; do not install `.el10` RPMs on
  Fedora.
- Required runtime matrix: **0/6** before Release 16 validation begins.
- GitHub root issues: 7 open; 283 closed. No Gold declaration while an issue
  remains open or any matrix cell is incomplete.
