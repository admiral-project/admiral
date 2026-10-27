# RC6 Epoch 5 Release 17 candidate

**Status: product fix prepared; CI, RPM builds and runtime validation pending. Not Gold.**

Release 16 was invalidated by the second supported remove-and-rejoin attempt in
#291. The spoke registered successfully, but the pre-heartbeat peer inventory
waited for the node to become `active`; the node could not become active until
WireGuard had been reconciled. Root product commit
`ba59c45d647bd354c878d7e61497896746a88c2b` allows only the exact currently
registering node into that peer inventory. Other inventory and removal paths
remain active-only.

Release 17 increments all six Admiral RPM Release fields, including packages
whose product sources did not change. The common RPM source pin is the exact
product commit above. The refreshed component comparisons and required pin
exceptions are in [source-pins.txt](source-pins.txt). Fedora must use six
native `.fc46` RPMs built from these same pins; EL10 RPMs are never installed
on Fedora.

Local root regression validation passed 189 tests and the release-reference
validator passed on this exact R17 metadata. Root GitHub CI, native RPM builds,
repository signatures, package SHA-256 manifests, and exact-package runtime
validation are pending. No issue has been closed from R17 evidence yet.

## Gates

- Open root issues: 7 — #106, #182, #228, #255, #271, #291, #294.
- Required x86_64 runtime matrix: **0/6**. Issue-specific validation does not
  count as a matrix cell.
- Gold: **not eligible** while any root issue is open or any matrix cell is
  incomplete.
- Host guardrail at preparation: 2.6 GiB available RAM, 48 GiB free disk;
  the three existing Rocky guests remain running. Builds and validation must
  be serial and resource-capped.
