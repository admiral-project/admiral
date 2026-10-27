# RC6 Epoch 5 Release 16 candidate

**Status: invalidated by two #291 re-onboarding failures. Not Gold.**

Release 15 failed the supported Worker re-onboarding path in #291. The
installer/Ansible correction is root source commit
`de88e350a90d81d329fa7fe7aea32bf9e790d203`: spoke peer reconciliation now runs
before the first handshake, and the Worker health gate runs after reconciliation.
This is a product change, so R15 cannot close #291 or serve as the new release
candidate. The failure analysis is recorded in the R15 evidence directory.

Release 16 was built as six signed native EL10 RPMs and six signed native
Fedora `.fc46` RPMs from the same component pins. The source pins, fetched
`origin/main` comparisons, NEVRAs, and SHA-256 values are recorded in this
directory. Root RPM reference validation and all component CIs passed.

The root regression CI passed both jobs on packaging commit `23f37e7` in run
[40491323973](https://github.com/admiral-project/admiral/actions/runs/40491323973).
Its Scripts regression suite and local `admiralctl` source-layout checks are
green. All five selected component CIs are green as recorded in
[source-pins.txt](source-pins.txt). The exact root product payload remains
`de88e350a90d81d329fa7fe7aea32bf9e790d203`.

## Release gates

- The R16 Rocky Multi-Node #291 sequence passed remove/revocation/denial and
  the first rejoin, then failed the required remove-and-rejoin repetition:
  after node registration, peer reconciliation waited for `active`, although
  the heartbeat needed the peer to be installed first. See
  [the R16 issue evidence](runtime/issue-291/rejoin-worker-r16.log).
- The root product fix for R17 is `ba59c45d647bd354c878d7e61497896746a88c2b`;
  it admits only the exact currently registering node while building the
  pre-heartbeat peer inventory. R17 builds and validation are tracked in
  [the R17 candidate](../rc6-e5-r17/CANDIDATE.md).
- Required runtime matrix: **0/6**. R16 does not receive matrix credit.
- GitHub root issues: 7 open; 283 closed. No Gold declaration while an issue
  remains open or any matrix cell is incomplete.
