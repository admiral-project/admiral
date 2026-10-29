# R26 restore precondition

The first request to restore `bk_7a9b01a69e1fd350` while the synthetic application was running returned HTTP 409:

`Restore is only allowed when the app is paused`

Admiral did not create a restore operation for that request and no database data was changed. The instance was paused through the supported Admiral operation (`op_f1b84d849a59099f`), after which restore with checksum verification succeeded (`op_83744265d741d554`). The instance was resumed successfully (`op_c169e150fdc9020a`), returned to healthy/available, and its strict-TLS workload route returned HTTP 200.

This is the expected restore precondition, not a product failure.
