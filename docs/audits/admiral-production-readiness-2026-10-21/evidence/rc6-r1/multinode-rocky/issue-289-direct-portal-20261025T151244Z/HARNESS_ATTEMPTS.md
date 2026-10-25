# Preserved failed harness attempts — issue #289

The first direct-origin attempt stopped at TLS setup with `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`. The probe passed the SSL context as a positional `HTTPSHandler` argument, which set `debuglevel` instead of `context`; the helper was corrected to pass `context=context`.

The next attempt reached Harbor and proved the approval POST response was HTTP 303, `Location: /admin/review-user`, `Content-Length: 0`, body length 0, and the redirect follow-up returned HTTP 200. The harness then reported a false failure because it searched the entire review page for the approved email, which remained in the flash message. The customer approval itself succeeded. That assertion was removed; the final run additionally verified customer login after approval.

These were test-helper defects, not Harbor failures. The final successful run is retained in `issue-289-direct-portal-run.log`.

The false-negative attempt created and successfully approved `rc6-issue289-20261025151230-db7439@example.test`; the final PASS run created and approved `rc6-issue289-20261025151244-7880ec@example.test`. A database read-only check is retained separately to confirm both synthetic accounts are active.
