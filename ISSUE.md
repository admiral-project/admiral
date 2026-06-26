# Session: ERPNext provisioning — setup timeout and task expiry

## Problema

ERPNext provisioning (`admiralctl instances provision --app erpnext --tier production-s --customer cust-erp-e2e`) falló. Operation status `setup_failed`:

```
restart unit "admiral-inst_a4c8908fe1952b55-pod.service" after setup: systemd-run
[--wait --collect --working-directory=/tmp systemctl --machine=admiral-apps@ --user
restart admiral-inst_a4c8908fe1952b55-p[REDACTED]]: signal: killed
```

## Diagnóstico

1. **`systemd.Manager` timeout default 30s** — `Restart` del pod tras setup usa `systemd-run --wait`. Si reiniciar toma >30s, la transcient unit es matada con SIGKILL.

2. **`taskMaxAge = 5 min`** — `queue.go:25`. La firma del task expira a los 5 min. `bench new-site --install-app erpnext` toma 15–30 min.

3. **Setup completó en ~4 min** — demasiado rápido para un `bench new-site` exitoso. La salida no se loggea si no hay error.

## Secrets Injection — Verificado (Gitea 2026-06-25)

Instancia `inst_d0bdaabfb3717123`:

| Campo | Valor |
|---|---|
| App | gitea |
| Technical | running |
| Setup | completed |
| Health | healthy |
| Admin | usr_911e9ae607a0 / 6910eb65f28b8476c2d3cb3b |
| API | HTTP 200 en http://159.223.114.23:40010/api/v1/users/usr_911e9ae607a0 |

Flujo secreto → env confirmado:
- `buildServiceInfos` resuelve `${VAR}`
- `serviceRuntimeEnv` mezcla `svc.Env` + `svc.Secrets`
- `RunTrustedShellInPod` pasa como `--env KEY=VAL`
- Shell del setup_command accede como `$VAR`

Las secrets **sí** se inyectan correctamente.

## Próximo paso

Re-provisionar ERPNext para obtener el error real de `bench new-site` sin el enmascaramiento por expiry/timeout.
