# Admiral States

Este documento distingue entre estados que el producto contempla y estados que el codigo actual realmente emite.

## Customer apps

### Estados comerciales

- `active`
- `cancelled`

### Estados tecnicos

- `pending_provision`: asignado al crear la instancia.
- `initializing`: asignado al despachar `provision_app` cuando la app
  define `setup_command` en algun servicio. Indica al usuario que la
  inicializacion post-provision esta en curso.
- `running`: tras `provision_app`, `start_app`, `resume_app`,
  `reactivate_app` o `restore_backup` exitosos. Si la app tenia
  `setup_command`, tambien requiere `setup_completed = true`.
- `stopped`: tras `stop_app` o `pause_app` exitosos.
- `backup_running`: durante la ejecución de un backup.
- `deprovisioning`: durante la eliminación de la instancia.
- `deprovisioned`: tras `deprovision_app` exitoso.
- `setup_failed`: cuando una `setup_command` falla durante el
  provision. La instancia se considera irrecuperable: la suscripcion se
  cancela y se reembolsa el ultimo pago al cliente.
- `failed`: cuando una operación técnica falla (excepto backups y
  setup_command).
- `restoring`: durante la ejecución de un restore.
- `paused_for_storage`: pausada automáticamente por sobreconsumo de almacenamiento.

Campo relacionado:

- `setup_completed` (booleano, default `false`): `true` despues de que
  `setup_command` termina con exito. La fuente de verdad para que fleet
  omita re-ejecutar el setup en retries.

## Operaciones

- `queued`: operación en espera de ser procesada o despachada.
- `running`: operación en ejecución.
- `succeeded`: operación completada con éxito.
- `failed`: operación fallida.

## Nodos

- `registered`: estado inicial tras el registro.
- `active`: nodo reportando heartbeats y disponible para operaciones.
- `offline`: nodo que ha superado el tiempo de espera de heartbeat.

## Rutas publicas

Estados observados hoy:

- `pending`
- `active`
- `failed`
- `disabled`
- `deleting`
- `deleted`

## Backup records

Estados observados hoy en `backup_records`:

- `pending` — asignado al crear el registro de backup
- `succeeded` — asignado tras callback exitoso de fleet
- `deleted` — asignado tras solicitud de eliminacion

Nota: `failed` no se asigna actualmente en el codigo operativo. Si una tarea
de backup falla, la operacion pasa a `failed` pero el registro de backup
permanece `pending`.

## Storage states

Cada instancia tiene un subestado de almacenamiento:

- `ok` — uso menor a 60% del limite
- `warning` — uso entre 60% y 80%
- `critical` — uso entre 80% y 90%
- `over_quota` — uso mayor o igual al 100%. **Nota de implementación:** Aunque la constante `StorageGracePeriod` (`grace_period`) existe en el código Go, el sistema registra el estado como `over_quota` en la columna `storage_state` de la base de datos mientras dura el período de gracia activo, identificándolo porque `grace_period_ends_at` está establecido en el futuro (`grace_period_ends_at IS NOT NULL AND grace_period_ends_at > CURRENT_TIMESTAMP`).
- `suspended` — pausada por storage (via `pause_app_storage`)
- `unknown` — no se pudo medir

Campos relacionados en la instancia:

- `storage_state` — estado actual
- `storage_exceeded` — booleano (true cuando storage_state = exceeded)
- `storage_used_percent` — porcentaje de uso calculado
- `storage_used_bytes` — bytes usados segun `du -sb`
- `storage_limit_bytes` — limite configurado en el tier
- `storage_message` — mensaje descriptivo del estado
- `storage_checked_at` — timestamp de la ultima medicion

## Reglas actuales importantes

- el callback de fleet decide la transicion final de la operacion
- si una tarea falla, la operacion pasa a `failed` y la instancia pasa a `failed`
- `deprovision_app` exitoso mueve la instancia a `cancelled` / `deprovisioned`
- `setup_command` fallido mueve la instancia a `setup_failed` /
  `cancelled`, libera capacidad del nodo, falla las rutas publicas, y
  Harbor worker cancela la suscripcion de PayPal y reembolsa el ultimo
  pago
- `pause_app_storage` mueve la instancia a `stopped` por sobreconsumo de almacenamiento
- `reactivate_app` reanuda una instancia pausada por storage
- las rutas publicas de una instancia provisionada pasan de `pending` a `active` cuando fleet reporta `host_ports` y `admirald` activa el target real
