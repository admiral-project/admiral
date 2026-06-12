# Admiral States

Este documento distingue entre estados que el producto contempla y estados que el codigo actual realmente emite.

## Customer apps

### Estados comerciales observados hoy

- `active`
- `cancelled`

El modelo de producto contempla otros estados, pero los handlers actuales no los emiten todavia.

### Estados tecnicos observados hoy

- `pending_provision`
- `running`
- `stopped`
- `backup_running`
- `deprovisioning`
- `deprovisioned`
- `failed`
- `restoring`

Notas:

- `pending_provision` se asigna al crear la instancia
- `running` se asigna tras `provision_app`, `start_app`, `resume_app` y `restore_backup` exitosos
- `stopped` se asigna tras `stop_app` y `pause_app`
- `backup_running` se asigna al encolar backups
- `restoring` se asigna al encolar restore
- `provisioning` se asigna durante el provisionamiento
- `paused` se asigna via `pause_app_storage` (por sobreconsumo de almacenamiento)

## Operaciones

Estados observados hoy:

- `queued`
- `running`
- `succeeded`
- `failed`

No hay emision real de `cancelled` en los handlers actuales.

## Nodos

Estados observados hoy:

- `registered`
- `active`

Notas:

- `registered` se usa en el primer `POST /api/v1/nodes`
- `active` se asigna por update de nodo y por heartbeat

Estados como `draining`, `inactive`, `unreachable` o `maintenance` no los emite hoy el codigo operativo.

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
- `over_quota` — uso mayor o igual al 100%
- `grace_period` — en periodo de gracia tras exceder cuota
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
- `pause_app_storage` mueve la instancia a `stopped` por sobreconsumo de almacenamiento
- `reactivate_app` reanuda una instancia pausada por storage
- las rutas publicas de una instancia provisionada pasan de `pending` a `active` cuando fleet reporta `host_ports` y `admirald` activa el target real
