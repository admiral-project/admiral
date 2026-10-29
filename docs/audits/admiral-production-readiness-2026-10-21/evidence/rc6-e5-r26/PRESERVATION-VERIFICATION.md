# RC6 E5 R26 — Preservation Verification

Date: 2026-10-29 UTC

The source-and-documentation preservation set was pushed to GitHub `origin/main` in commit `21f0130b3cc18fec9c217fb622a937af4f037b97`. I fetched it into a fresh shallow clone from `https://github.com/admiral-project/admiral.git` and ran the published `PRESERVATION-SHA256SUMS` there. **80/80 entries passed**. The checked set includes the reports, manifests, source pins, selected audit scripts and the already-tracked RPM spec sources.

This verifies the external GitHub copy of source and documentation. It does not claim that raw runtime logs or the exact native E2E RPM files were copied. Those were omitted from this publication under the source-and-documentation scope; the original log checksums remain records, not copies. Copr independently holds the six exact EL10 source RPM inputs and successful EL10/Fedora Rawhide build results, as documented in [#308](https://github.com/admiral-project/admiral/issues/308#issuecomment-6499787588).

No product code, RPM, test result, source pin, VM or issue state changed for this preservation.
