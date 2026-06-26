# Session: ERPNext provisioning — setup timeout and task expiry

## Problema (original)

ERPNext provisioning falló — `systemd-run` SIGKILL por timeout de 30s en restart del pod.

## Solución implementada (2026-06-26)

### App definition: nuevo campo `setup_timeout`

El servicio `setup` ahora acepta `setup_timeout` en segundos:

```yaml
services:
  setup:
    setup_command: bench new-site ...
    setup_timeout: 3600  # timeout de 1 hora
```

Default: 600 (10 min) si no se declara.

### Fleet: timeout configurable por servicio

- `executor_provision.go`: usa `svc.SetupTimeout` en lugar de hardcode `10*time.Minute`
- `executor_helpers.go`: `podmanForSetup()` acepta timeout como parámetro
- `systemd/manager.go`: `ADMIRAL_SYSTEMD_TIMEOUT` env var (default 30s) para `systemd-run --wait`

### UX: tiempo estimado en portales

- `setup_timeout_seconds` se expone en la API de instancias
- Harbor muestra "tiempo estimado: X minutos" en dashboard, detalle y confirmación
- Flagship incluye el campo en normalize_instance

### Dev tier memory

- ERPNext dev tier: 256M → 2G (8 contenedores en el pod)

## Estado actual

- ERPNext provisiona automáticamente con `setup_command` y `setup_timeout: 3600`
- `taskMaxAge` (5 min) es tiempo máximo en cola, no límite de ejecución — no bloquea setups largos
- Setup de ERPNext probado exitosamente en `--dev-node`
