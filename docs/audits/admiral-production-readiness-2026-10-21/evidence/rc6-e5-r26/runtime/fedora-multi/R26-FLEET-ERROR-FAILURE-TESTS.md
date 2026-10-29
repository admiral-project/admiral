# R26 Fleet error and failed-task tests

Date: 2026-10-29 UTC  
Candidate root: `b6146a46be93f1a9c242361e27b10dbbb2164bf6`  
Admirald: `8efa1dec8e9540210d9f86d016dce4677dcc6543`  
Fleet: `edc0a0d486eb102e9aaa4f250a08f777d7441f12`

Focused tests passed against the exact R26 source pins:

```text
go test ./internal/security ./internal/executor -run 'Test(Sanitize|SanitizeArgs|SanitizedInspectJSONValueRedactsEnvironment|SystemdPodmanExecutorFailureInjection|SystemdPodmanExecutorReturnsSystemdError)$' -count=1
ok  github.com/admiral-project/admiral/admiral-fleet/internal/security  0.017s
ok  github.com/admiral-project/admiral/admiral-fleet/internal/executor  0.016s

go test ./internal/api -run 'Test(HandleFleetCallbackFailure|HandleFleetCallbackProvisionSetupFailureEnqueuesCleanup)$' -count=1
ok  github.com/admiral-project/admiral/admirald/internal/api  0.007s
```

The checks cover known password, token, API key and authorization argument redaction; environment redaction from inspect data; an executor failure returning `Success=false`; and Admirald persisting a failed callback as `failed`/`setup_failed`, including cleanup after failed setup. Fleet's `HandleTaskContext` sends the executor's result unchanged, and Admirald derives the terminal operation status from the callback's success bit.

This supports the #307 controls **“Los errores no exponen información sensible”** for the exercised Fleet command/inspect paths and **“Una tarea fallida no se informa falsamente como completada”** for the tested callback path. It is focused source/unit evidence, not a live fault-injection run. It does not establish redaction for every application log, helper payload minimization, or workload-level secret isolation.

No product file changed; the candidate and six-cell matrix are unchanged.
