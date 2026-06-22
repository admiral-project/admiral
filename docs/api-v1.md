# Admiral API

Este documento describe la superficie HTTP actualmente implementada por `admirald`.

Todo el trafico debe usar `HTTPS`. Las rutas de health y status requieren token administrativo.

## Autenticacion

### API v1 protegida `/api/v1/*`

Requiere uno de:

- `X-Admiral-Token: <shared-token>`
- `Authorization: Bearer <shared-token>`

### API administrativa `/api/admin/*`

Requiere sesion administrativa, excepto `POST /api/admin/auth/login`.

Headers aceptados:

- `X-Admiral-Admin-Token: <admin-session-token>`
- `Authorization: Bearer <admin-session-token>`

Reglas actuales:

- duracion maxima de sesion: 24 horas
- expiracion por inactividad: 30 minutos
- bootstrap actual de desarrollo: si no existe ningun admin, se crea `admin / secret`
- las operaciones registran `admin_user` via header `X-Admiral-Admin-User` o `X-Admiral-Operator`

## Respuesta de error

Formato comun:

```json
{
  "error": "human readable message"
}
```

## API v1

### `GET /health`

Requiere `X-Admiral-Token` o `Authorization: Bearer ...`.

Respuesta (tambien disponible en `GET /api/v1/health`):

### `GET /api/v1/status`

Respuesta extendida:

```json
{
  "status": "healthy",
  "database": "connected"
}
```

```json
{
  "status": "healthy"
}
```

### `GET /api/v1/nodes`

Lista nodos registrados.

### `GET /api/v1/nodes/{node_id}`

Devuelve un nodo concreto.

### `GET /api/v1/nodes/{node_id}/metrics`

Devuelve metricas del nodo (pods activos, pausados, fallidos; uso de disco).

### `POST /api/v1/nodes`

Registra un nodo.

Request:

```json
{
  "node_id": "node_001",
  "hostname": "worker-1",
  "ip": "10.0.0.10",
  "os": "fedora",
  "podman_version": "4.9.0"
}
```

Campos requeridos:

- `node_id`
- `hostname`
- `ip`

`os` y `podman_version` son opcionales, no se usan actualmente.

Respuesta:

```json
{
  "success": true
}
```

### `POST /api/v1/nodes/heartbeat`

Reporta liveness del nodo.

Request:

```json
{
  "node_id": "node_001",
  "status": "active",
  "hostname": "worker-1",
  "ip": "10.0.0.10",
  "podman_version": "4.9.0",
  "fleet_version": "0.1.0",
  "disk_total_bytes": 53687091200,
  "disk_used_bytes": 21474836480,
  "pods_active": 3,
  "pods_paused": 0,
  "pods_failed": 0
}
```

Campos requeridos:

- `node_id`
- `status`

`hostname`, `ip`, `podman_version`, `fleet_version` se persisten en el nodo.
`disk_total_bytes`, `disk_used_bytes`, `pods_active`, `pods_paused`, `pods_failed` se persisten como metrica del nodo pero no se usan hoy para decisiones operativas.

### `GET /api/v1/customer-apps/{instance_id}`

Devuelve una instancia de cliente concreta.

### `GET /api/v1/networking/certificate`

Devuelve informacion del certificado TLS usado por admirald.

### `GET /api/v1/apps`

Lista application definitions guardadas.

### `POST /api/v1/apps`

Aplica una application definition.

Formato aceptado:

- JSON con campo `yaml`
- body YAML/texto si el `Content-Type` contiene `yaml` o `text`

Ejemplo JSON:

```json
{
  "yaml": "name: simple-crm\n..."
}
```

Respuesta:

```json
{
  "success": true,
  "name": "simple-crm"
}
```

### `GET /api/v1/customer-apps`

Lista instancias de cliente.

Soporta filtro opcional:

`GET /api/v1/customer-apps?customer_id=hcus_123`

Esto permite a `admiral-harbor` consultar solo las instancias pertenecientes
al cliente autenticado sin exponer el listado global completo.

### `POST /api/v1/customer-apps`

Crea una instancia y encola `provision_app`.

Request:

```json
{
  "app_definition_name": "simple-crm",
  "tier_name": "starter",
  "customer_id": "cust_001"
}
```

Respuesta `202 Accepted`:

```json
{
  "operation_id": "op_123",
  "status": "queued",
  "credentials": [
    {
      "service": "db",
      "name": "POSTGRES_PASSWORD",
      "value": "generated-password"
    }
  ]
}
```

`credentials` solo aparece aqui y solo para secretos marcados con `expose: true`.

### `POST /api/v1/customer-apps/action`

Encola una accion sobre una instancia existente.

Request:

```json
{
  "instance_id": "inst_123",
  "action": "pause"
}
```

Acciones publicas soportadas hoy:

- `pause`
- `resume`
- `start`
- `stop`
- `backup`
- `deprovision`
- `reactivate`

Respuesta `202 Accepted`:

```json
{
  "operation_id": "op_123",
  "status": "queued"
}
```

### `GET /api/v1/operations`

Lista operaciones.

### `GET /api/v1/operations?id=op_123`

Devuelve una operacion concreta.

### `POST /api/v1/fleet/callback`

Recibe el resultado de una tarea ejecutada por `admiral-fleet`.

Request:

```json
{
  "task_id": "task_123",
  "operation_id": "op_123",
  "node_id": "node_001",
  "success": true,
  "error": "optional error message",
  "logs": "provisioned instance inst_123",
  "metadata": "{\"executor\":\"systemd-podman\"}"
}
```

Campos requeridos:

- `task_id`
- `operation_id`
- `node_id`
- `success`

Reglas:

- callbacks desconocidos para `operation_id` se rechazan con `404`
- `logs` y `metadata` no deben incluir secretos
- `metadata` es JSON opaco serializado como string

### `POST /api/v1/fleet/health`

Recibe reportes de salud de pods desde `admiral-fleet`.

Request:
```json
{
  "instance_id": "inst_789",
  "node_id": "node_001",
  "health_status": "healthy",
  "message": "",
  "checked_at": "2026-05-29T00:00:00Z"
}
```

### `POST /api/v1/fleet/storage`

Recibe reportes de uso de almacenamiento desde `admiral-fleet`.

Request:
```json
{
  "instance_id": "inst_789",
  "node_id": "node_001",
  "storage_limit_bytes": 10737418240,
  "storage_used_bytes": 6442450944,
  "storage_used_percent": 60.0,
  "storage_state": "warning",
  "storage_message": "storage usage at 60.0% (warning threshold)",
  "checked_at": "2026-05-29T00:00:00Z"
}
```

Estados posibles: `ok`, `warning`, `critical`, `over_quota`, `grace_period`, `suspended`, `unknown`.

### `GET /api/v1/routes`

Lista rutas publicas persistidas.

### `POST /api/v1/routes`

Fuerza reconciliacion/sync con Caddy.

### `GET /api/v1/routes/{hostname}`

Devuelve una ruta concreta.

### `POST /api/v1/routes/{hostname}/enable`

Habilita una ruta.

### `POST /api/v1/routes/{hostname}/disable`

Deshabilita una ruta.

### `POST /api/v1/routes/{hostname}/sync`

Fuerza sync de una ruta por hostname.

### `POST /api/v1/routes/{hostname}/delete`

Marca la ruta para eliminacion y la remueve.

Tambien acepta `DELETE`.

### `GET /api/v1/instances`

Lista instancias de cliente (similar a `GET /api/v1/customer-apps`).

### `GET /api/v1/instances/{instance_id}`

Devuelve una instancia concreta.

### `POST /api/v1/instances/{instance_id}/{action}`

Encola una accion sobre una instancia existente.

Acciones soportadas:
- `pause`
- `resume`
- `start`
- `stop`
- `backup`
- `deprovision`
- `inspect`
- `reactivate`

### `GET /api/v1/backups`

Lista `backup_records`.

### `GET /api/v1/backups/{backup_id}`

Devuelve un backup concreto.

### `DELETE /api/v1/backups/{backup_id}`

Encola `delete_backup`.

### `POST /api/v1/backups/restore`

Encola `restore_backup`. Mismo comportamiento que `POST /api/admin/backups/restore`.

## API administrativa

### Autenticacion

#### `POST /api/admin/auth/login`

Request:

```json
{
  "username": "admin",
  "password": "secret"
}
```

Respuesta (login exitoso):

```json
{
  "token": "adm_tok_123",
  "expires_at": "2026-05-29T12:00:00Z",
  "role": "superadmin",
  "username": "admin"
}
```

Respuesta (password change requerido — primer login con credenciales de bootstrap):

```json
{
  "password_change_required": true,
  "username": "admin",
  "role": "superadmin"
}
```

#### `POST /api/admin/auth/logout`

Invalida la sesion actual. Requiere `X-Admiral-Admin-Token` o `Authorization: Bearer ...`.

#### `GET /api/admin/auth/me`

Devuelve usuario autenticado.

### Apps administrativas

#### `GET /api/admin/apps`

Lista apps.

#### `GET /api/admin/apps/{app_id}`

Devuelve una app.

#### `GET /api/admin/apps/{app_id}/yaml`

Devuelve el YAML guardado.

#### `GET /api/admin/apps/{app_id}/versions`

Hoy devuelve `["latest"]`.

#### `GET /api/admin/apps/{app_id}/tiers`

Lista tiers.

#### `GET /api/admin/apps/{app_id}/tiers/{tier_id}`

Devuelve un tier.

#### `POST|PUT /api/admin/apps`

Reutiliza el flujo de aplicar app definition.

#### `POST|PUT /api/admin/apps/{app_id}/tiers`

Crea o reemplaza un tier.

### Instancias administrativas

#### `GET /api/admin/instances`

Lista instancias.

#### `GET /api/admin/instances/{instance_id}`

Devuelve una instancia.

#### `POST /api/admin/instances/{instance_id}/{action}`

Acciones soportadas hoy:

- `pause`
- `resume`
- `start`
- `stop`
- `backup` (referencia a HandleTriggerBackup para bases de datos o volumenes)
- `deprovision`
- `inspect` (crea operacion `inspect_app`)
- `reactivate`

### Backups administrativos

#### `GET /api/admin/backups`

Lista `backup_records`.

Query opcional:

- `instance_id`

#### `GET /api/admin/backups/{backup_id}`

Devuelve un backup.

#### `DELETE /api/admin/backups/{backup_id}`

Encola `delete_backup`.

#### `POST /api/admin/backups/prune`

Aplica pruning simple sobre backups `succeeded`.

#### `POST /api/admin/instances/{instance_id}/backups/database`

Encola `backup_database`.

#### `POST /api/admin/instances/{instance_id}/backups/volumes`

Encola `backup_volumes`.

#### `POST /api/admin/backups/restore`

Encola `restore_backup`.

Request:

```json
{
  "backup_id": "bk_123",
  "target_app_id": "inst_123",
  "target_node_id": "node_001",
  "restore_mode": "replace",
  "verify_checksum": true,
  "source": {
    "type": "local_path",
    "uri": "/var/lib/admiral/backups/inst_123/file.tgz"
  }
}
```

Reglas actuales:

- la instancia destino debe estar `paused` o `stopped` (codigo acepta ambos)
- la app debe tener bloque `backup` declarado
- `target_node_id` debe coincidir con el nodo actual de la instancia si se especifica

#### `POST /api/admin/instances/{instance_id}/migrate`

Inicia una migracion offline de una instancia hacia otro worker.

Request:

```json
{
  "target_node_id": "node_002"
}
```

Respuesta:

```json
{
  "operation_id": "op_123",
  "instance_id": "inst_123",
  "logical_instance_id": "li_123",
  "status": "running"
}
```

Garantias actuales:

- preserva `logical_instance_id`
- mantiene `node_id` en origen hasta el cutover
- intenta rollback pre-cutover si falla provision, restore, start o validation
- conserva rutas publicas durante cutover exitoso

### Settings de backup storage

#### `GET /api/admin/settings/backup-storage`

Devuelve configuracion actual. Los campos de secretos se enmascaran.

#### `PUT /api/admin/settings/backup-storage`

Guarda configuracion global.

Backends soportados hoy:

- `local`
- `s3`

#### `POST /api/admin/settings/backup-storage/test`

Encola `test_backup_storage` si existe al menos un nodo activo.

### Nodos y tareas administrativas

#### `GET /api/admin/nodes`

Lista nodos.

#### `GET /api/admin/nodes/{node_id}`

Devuelve un nodo.

#### `GET /api/admin/nodes/{node_id}/metrics`

Devuelve metricas del nodo (discos, pods activos, pausados, fallidos).

No existe un endpoint `/api/admin/nodes/{node_id}/status`. Usar
`GET /api/admin/nodes/{node_id}` para obtener datos del nodo.

#### `GET /api/admin/tasks`

Hoy devuelve lista de operaciones (`operations`).

#### `GET /api/admin/tasks/{task_id}`

Hace lookup por ID usando operaciones como aproximacion.

### Gestion de usuarios administrativos

#### `GET /api/admin/users`

Lista usuarios administrativos.

Requiere sesion administrativa.

Respuesta:

```json
[
  {
    "username": "admin",
    "role": "superadmin",
    "created_at": "2026-06-01T00:00:00Z"
  }
]
```

#### `GET /api/admin/users/{username}`

Devuelve un usuario concreto.

#### `POST /api/admin/users`

Crea un nuevo usuario administrativo.

Request:

```json
{
  "username": "operator",
  "password": "secure-password",
  "role": "support"
}
```

Roles disponibles:

- `superadmin`
- `admin`
- `platform`
- `support`
- `audit`

Requiere sesion administrativa con token compartido o token de admin existente (`X-Admiral-Token` o `X-Admiral-Admin-Token`).

Respuesta `201 Created`:

```json
{
  "username": "operator",
  "role": "support"
}
```

#### `POST /api/admin/users/{username}/set-password`

Cambia la contraseña de un usuario.

Request:

```json
{
  "new_password": "new-secure-password"
}
```

Respuesta `200 OK`.

#### `POST /api/admin/users/{username}/set-role`

Cambia el rol de un usuario.

Request:

```json
{
  "role": "admin"
}
```

Respuesta `200 OK`.

### Health y Callbacks Administrativos

La ruta `POST /api/v1/fleet/health` (documentada arriba) recibe los reportes de
salud de instancias desde `admiral-fleet`. No existe un endpoint separado bajo
`/api/admin/health/callback`.
