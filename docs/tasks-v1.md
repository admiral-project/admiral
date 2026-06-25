# Admiral Fleet Tasks

Este documento describe el contrato de tareas actualmente implementado entre `admirald` y `admiral-fleet`.

## Transporte

- cola PostgreSQL: `fleet_commands`
- formato: JSON
- transporte requerido: `amqps://`

Reglas actuales:

- la cola debe ser durable
- los mensajes deben ser persistentes
- el worker debe validar `node_id`
- el worker no debe loggear payloads completos ni secretos

## Almacenamiento

`tier.storage` se usa como limite de referencia para monitoreo operacional. `admiral-fleet` ejecuta un storage checker periodico que mide el uso real de cada volumen, clasifica el estado segun umbrales (60% warning, 80% critical, 90% exceeded) y reporta a `admirald` via `POST /api/v1/fleet/storage`.

Ver `docs/app-definition-v1.md` para formato aceptado y `docs/configuration-v1.md` para opciones de configuracion del checker.

## `FleetTask`

```json
{
  "task_id": "task_123",
  "operation_id": "op_456",
  "node_id": "node_001",
  "action": "provision_app",
  "instance_id": "inst_789",
  "app": {
    "name": "simple-crm",
    "version": "latest"
  },
  "tier": {
    "name": "starter",
    "cpu": 1,
    "memory": "1G",
    "storage": "10G",
    "environment": {
      "MAX_USERS": "10"
    }
  },
  "services": [
    {
      "name": "web",
      "image": "registry.example.com/simple-crm:1.0.0",
      "port": 8080,
      "volume": "web_data",
      "depends_on": ["db"],
      "requires": ["db"],
      "command": "/usr/bin/myapp --serve",
      "setup_command": "init-db --apply-migrations",
      "notify_on_setup": [
        {
          "label": "Usuario administrador",
          "value": "Administrator"
        }
      ],
      "env": {
        "DATABASE_HOST": "db"
      },
      "secrets": {
        "APP_SECRET": "decrypted-value"
      },
      "healthcheck": {
        "type": "tcp",
        "port": 8080
      },
      "healthcheck_wait_timeout": 180,
      "registry": {
        "server": "registry.example.com",
        "username": "deploy",
        "password": "token"
      },
      "user": "1000"
    }
  ],
  "shared_volumes": [
    {
      "name": "sites",
      "mount": "/home/frappe/frappe-bench/sites",
      "services": ["web", "setup"]
    }
  ],
  "setup_completed": false,
  "backup": {
    "type": "database",
    "engine": "postgresql",
    "service": "db",
    "database_env": "POSTGRES_DB",
    "username_env": "POSTGRES_USER",
    "password_env": "POSTGRES_PASSWORD"
  },
  "storage": {
    "backend": "local",
    "key": "/var/lib/admiral/backups/inst_789/op_456",
    "backup_id": "bk_123"
  }
}
```

## Campos principales

Requeridos siempre:

- `task_id`
- `operation_id`
- `node_id`
- `action`
- `instance_id`

`backup`, `restore` y `storage` son opcionales (solo se incluyen segun la accion).
`app`, `tier` y `services` siempre se serializan (pueden aparecer como valores
vacios si la accion no los requiere).

### Campos de servicio

Cada item de `services` incluye:

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `name` | string | Nombre del servicio |
| `image` | string | Referencia completa de la imagen |
| `port` | int | Puerto interno del contenedor |
| `volume` | string | Nombre del volumen persistente (opcional) |
| `depends_on` | []string | Orden debil de arranque entre servicios |
| `requires` | []string | Dependencias fuertes entre servicios |
| `command` | string | Comando alternativo al entrypoint (opcional) |
| `setup_command` | string | Comando de inicializacion ejecutado una sola vez post-provision (opcional) |
| `notify_on_setup` | []YAMLSetupNotice | Datos informativos para el cliente tras setup |
| `env` | map | Variables de entorno materializadas |
| `secrets` | map | Secretos desencriptados |
| `healthcheck` | YAMLHealthCheck | Healthcheck del servicio |
| `healthcheck_wait_timeout` | int | Tiempo maximo para esperar readiness |
| `registry` | RegistryConfig | Credenciales para registro privado (opcional) |
| `user` | string | UID o usuario usado por contenedores one-shot de setup/healthcheck |

### Campos de tier

Cada item de `tier` incluye:

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `name` | string | Nombre del tier |
| `cpu` | float | Presupuesto de CPU del pod |
| `memory` | string | Limite de memoria |
| `storage` | string | Limite de almacenamiento |
| `environment` | map | Variables de entorno del tier (opcional) |

## Acciones del contrato actual

Acciones aceptadas por el contrato compartido:

- `provision_app`
- `start_app`
- `stop_app`
- `pause_app`
- `resume_app`
- `resize_app`
- `deprovision_app`
- `backup_database`
- `backup_volumes`
- `inspect_app`
- `delete_backup`
- `test_backup_storage`
- `restore_backup`
- `pause_app_storage`
- `reactivate_app`

Estado por executor:

- `simulated`: acepta todas las acciones listadas arriba
- `systemd-podman`: implementa todas excepto `resize_app`

## Uso de secretos por accion

### Secretos permitidos

- `provision_app`
- `backup_database`
- `restore_backup`

### Secretos incluidos

- `provision_app` — todos los secretos de la instancia
- `start_app` — todos los secretos de la instancia
- `resume_app` — todos los secretos de la instancia
- `reactivate_app` — todos los secretos de la instancia
- `backup_database` — solo secretos del servicio/bloque `backup`
- `restore_backup` — todos los secretos de la instancia

### Acciones sin secretos

- `stop_app`
- `pause_app`
- `resize_app`
- `deprovision_app`
- `backup_volumes`
- `inspect_app`
- `delete_backup`
- `test_backup_storage`

`admirald` aplica scoping antes de publicar:

- `provision_app`, `start_app`, `resume_app`, `restore_backup`: reciben el mapa completo de secretos de la instancia
- `backup_database`: recibe solo los secretos del servicio/variables referenciados por `services.<name>.backup`

## `services.<name>.backup`

`backup` describe la fuente logica del backup del servicio:

- `type`
- `engine`
- `database_type`
- `database_env`
- `username_env`
- `password_env`

Para tareas `backup_volumes`, Admiral selecciona el servicio cuyo `backup.type` es `volume`. El worker respalda solo ese volumen y organiza los archivos bajo el prefijo `<service_name>/`.

Ejemplo: un backup del servicio `web` de WordPress produce un archive con:

```
web/wp-content/plugins/...
web/wp-content/themes/...
web/wp-content/uploads/...
```

En restore, el worker extrae cada seccion al volumen correspondiente del servicio.

## Bloque `storage`

`storage` describe donde leer o escribir el artefacto:

- `backend`
- `key`
- `backup_id`
- `endpoint`
- `region`
- `bucket`
- `prefix`
- `force_path_style`
- `access_key_env`
- `secret_key_env`
- `session_token_env`

## Bloque `restore`

Campos actualmente usados:

- `backup_id`
- `storage_backend`
- `storage_key`
- `backup_type`
- `database_type`
- `service` (requerido para `database`, opcional para `volume`)
- `checksum_sha256`
- `verify_checksum`

Para restores de tipo `volume`, si `service` no se especifica, el worker restaura todos los servicios que declaran `volume`.

## `TaskResult`

Callback a `POST /api/v1/fleet/callback`:

```json
{
  "task_id": "task_123",
  "operation_id": "op_456",
  "node_id": "node_001",
  "success": true,
  "logs": "provisioned instance inst_789",
  "metadata": "{\"executor\":\"systemd-podman\"}"
}
```

Campos requeridos:

- `task_id`
- `operation_id`
- `node_id`
- `success`

Campos opcionales:

- `error`
- `logs`
- `metadata`

## Metadata usada hoy

Ejemplos reales:

- provision (sin setup_command):
  - `{"executor":"systemd-podman","action":"provision_app","host_ports":{"web":40000}}`
- provision (con setup_command correcto):
  - `{"executor":"systemd-podman","action":"provision_app","host_ports":{"web":40000},"has_setup":true}`
- provision (setup_command fallido):
  - `{"executor":"systemd-podman","action":"provision_app","host_ports":{"web":40000},"has_setup":true,"setup_failed":true,"setup_error":"bench new-site failed: ..."}`
- backup database:
  - `{"executor":"systemd-podman","backup":{...}}`
- delete backup:
  - `{"executor":"systemd-podman","action":"delete_backup","backup_id":"bk_123"}`
- restore:
  - `{"executor":"systemd-podman","restore":{"backup_id":"bk_123","artifact":"/path/file"}}`

`metadata` sigue siendo opaco para el contrato, pero `admirald` ya parsea algunos campos concretos:

- `host_ports` tras `provision_app`
- `has_setup` y `setup_failed` + `setup_error` tras `provision_app`
- `backup.*` tras backups

### Idempotencia de setup_command

`FleetTask.setup_completed` (booleano, default false) es la fuente de
verdad para que fleet omita el setup en retries. Admirald lo popula
desde la columna `customer_apps.setup_completed` en la base de datos.
Si es `true`, `admiral-fleet` nunca ejecuta `setup_command` aunque el
pod ya exista o el worker sea reiniciado.

Ademas, `admiral-fleet` escribe un archivo marker local
(`<data_dir>/instances/<id>/setup_done`) tras una ejecucion exitosa de
setup. Esto protege contra el escenario de "callback perdido":
admirald nunca recibio el callback de exito, re-despacha la tarea con
`setup_completed=false`, y el worker no puede distinguir si ya corrio
el setup. El marker previene la re-ejecucion en el mismo nodo. La DB
sigue ganando: si `setup_completed=true` el worker omite el setup
incluso si el marker no existe (caso de migracion cross-node).

### Comportamiento del callback en setup_command fallido

Cuando un `setup_command` falla, la tarea reporta `success = false` con
metadatos `setup_failed = true`. Admirald distingue provision fallido
de setup fallido usando este flag:

- provision fallido (sin `setup_failed`): la instancia pasa a `failed`,
  `commercial_status` se mantiene.
- setup fallido (`setup_failed = true`): la instancia pasa a
  `setup_failed` y `commercial_status = cancelled`. Harbor, al
  sincronizar, cancela la suscripcion de PayPal y reembolsa el ultimo
  pago del cliente. Se considera estado irrecuperable.

## Reglas del worker

`admiral-fleet` debe:

- rechazar tareas con `node_id` distinto al nodo local
- rechazar acciones desconocidas
- responder siempre con callback si acepto la tarea
- evitar decisiones comerciales
- usar argumentos separados y timeouts al invocar systemd/Podman

## Estado actual del executor real

El executor `systemd-podman` ya implementa acciones reales.

La representacion de runtime usada hoy es:

- `.pod` — agrupa servicios en un pod de Podman
- `.container` — servicios individuales dentro del pod
- `.volume` — volumenes persistentes
