# NOW-LMS image availability snapshot

Checked: 2026-10-28 UTC

The current Quay tag API for `bmosoluciones/now_lms` lists only:

| Tag | Digest | Quay last modified |
|---|---|---|
| `v1.3.4` | `sha256:6c365c80654e8306276958da2e205bd7768d6e148591666d483bd8aa3c41318d` | 2026-08-01 15:55:09 UTC |
| `latest` | `sha256:8782a027547a5d1e923a9b213a45c8a0ceac78b0ddf59ebe89319e970115e91b` | 2026-07-31 17:08:55 UTC |

The `v1.3.4` manifest digest matches the image used by `examples/apps/now-lms.yaml` and the R20 execution. The `latest` tag was modified earlier and is not a newer published candidate by tag timestamp. The current GitHub release is v2.0.4 (published 2026-08-07), but Quay has no v2.0.4 tag or image in the public tag listing. Building an image from source locally would not validate the published image used by the example, so no substitute image was built or run.

R20 execution evidence for the Quay v1.3.4 digest records the upstream migration failure `relation "curso" does not exist` before backend readiness. No Admiral product error was observed. Re-test NOW-LMS when a newer Quay image is published; until then #305 remains open on this example.

Sources:

- Quay tags API: https://quay.io/api/v1/repository/bmosoluciones/now_lms/tag/?limit=100&onlyActiveTags=true
- Quay tags page: https://quay.io/repository/bmosoluciones/now_lms?tab=tags
- NOW-LMS v2.0.4 release: https://github.com/bmosoluciones/now-lms/releases/tag/v2.0.4
- Prior execution: `docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r20/runtime/issue-305-executed-20261028/now-lms-diagnostic-r20-20261028/`
