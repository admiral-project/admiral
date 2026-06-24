# Admiral App Definition v1

Este documento describe el formato YAML actualmente validado por `admirald` y reutilizado por `admiralctl apps validate`.

## Estructura base

Campos soportados en la raiz del YAML:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `name` | string | si | Identificador unico de la app (`^[a-z][a-z0-9-]*$`) |
| `display_name` | string | si | Nombre legible para mostrar en UI |
| `description` | string | no | Descripcion de la aplicacion |
| `services` | map[string]YAMLService | si | Servicios contenedores de la app |
| `shared_volumes` | map[string]YAMLSharedVolume | no | Volumenes persistentes compartidos entre varios servicios |
| `tiers` | map[string]YAMLTier | si | Planes de precio y recursos disponibles |
| `secrets` | map[string]YAMLSecret | no | Secretos globales de la aplicacion |

```yaml
name: simple-crm
display_name: Simple CRM
description: CRM ligero para pequenas empresas

services:
  web:
    image: registry.example.com/simple-crm:1.0.0
    port: 8080
    public: true
    backup:
      type: none
    command: /usr/bin/myapp --serve
    env:
      DATABASE_HOST: localhost
    secrets:
      APP_SECRET:
        generate: password
        persist: true
    registry:
      server: registry.example.com
      username: deploy-user
      password: s3cr3t-token

  db:
    image: docker.io/library/postgres:16
    volume: db_data
    backup:
      type: database
      engine: postgresql
      database_env: POSTGRES_DB
      username_env: POSTGRES_USER
      password_env: POSTGRES_PASSWORD
    env:
      POSTGRES_DB: crm
    secrets:
      POSTGRES_USER:
        generate: username
        expose: true
      POSTGRES_PASSWORD:
        generate: password
        expose: true

tiers:
  free:
    cpu: 0.5
    memory: 256M
    storage: 1G
    price_monthly: 0
    free: true

  starter:
    cpu: 1
    memory: 1G
    storage: 10G
    price_monthly: 15
    environment:
      MAX_USERS: "3"
      MAX_COMPANIES: "1"
    backups:
      enabled: true
      schedule: daily
      time: "02:00"
      timezone: "UTC"
      retention:
        count: 7
        days: 30
      manual_backups: true
      backup_database: true
      backup_volumes: false
      restore_allowed: true

```

## Servicios

Campos soportados por servicio:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `image` | string | si | Referencia completa de la imagen contenedora |
| `port` | int | no | Puerto interno del contenedor |
| `public` | bool | no | Si el servicio es accesible via internet |
| `volume` | string | no | Nombre del volumen persistente |
| `depends_on` | []string | no | Dependencias de orden de arranque entre servicios |
| `command` | string | no | Comando alternativo para el contenedor |
| `setup_command` | string | no | Comando de inicializacion ejecutado una sola vez tras el provision |
| `env` | map[string]string | no | Variables de entorno estaticas |
| `secrets` | map[string]YAMLSecret | no | Secretos generados o explicitos |
| `healthcheck` | YAMLHealthCheck | no | Healthcheck del servicio |
| `backup` | YAMLServiceBackup | si | Contrato explicito de respaldo para ese servicio |
| `registry` | YAMLRegistry | no | Credenciales para registro privado |

### `public: true`

Si un servicio tiene `public: true`, `admirald` puede crear una ruta publica
para ese servicio durante el provisionamiento. El puerto del servicio se
publica en un puerto aleatorio del host (rango 40000-49999).

Solo los servicios con `public: true` deben recibir puerto de host. Los
servicios internos (base de datos, cache, workers) no deben exponer puertos
al host.

**Solo un servicio puede ser publico por aplicacion.** Si se marcan varios,
la validacion rechaza la definicion.

### `port`

`port` representa el puerto interno del contenedor dentro del pod.

Todos los servicios que declaren `port` deben usar valores unicos dentro de la
misma app. Admiral rechaza definiciones con conflictos como dos Redis usando
`6379` en el mismo pod.

### `command`

El campo `command` permite especificar un comando distinto al entrypoint
default de la imagen. Se pasa directamente a la unidad Quadlet como
`Exec=` en la seccion `[Container]`.

**Importante:** Si la imagen requiere un comando especifico para operar
(por ejemplo, `server /data --console-address :9001` para MinIO), debe
declararse explicitamente en `command`. Admiral no infiere comandos;
la definicion debe ser explicita.

### `setup_command`

`setup_command` declara un comando de inicializacion que se ejecuta una
sola vez, despues de que todos los servicios estan corriendo, durante
el provisionamiento. El comando se ejecuta con `sh -c` dentro del
contenedor del servicio, por lo que puede usar expansion de variables
(`$VAR`), redireccion y comillas.

```yaml
services:
  backend:
    image: frappe/erpnext:v15
    setup_command: bench new-site site.local --db-root-password $MARIADB_ROOT_PASSWORD --install-app erpnext
```

**Cuando una app define `setup_command` en algun servicio:**

- La instancia pasa por el estado tecnico `initializing` (en lugar de
  ir directamente a `running`) para informar al usuario que la
  inicializacion esta en curso.
- `admiral-fleet` ejecuta cada `setup_command` con un timeout de 10
  minutos.
- Si **todos** los `setup_command` terminan con exito, la instancia pasa
  a `running` y se marca `setup_completed = true` en la base de datos.
- Si **algun** `setup_command` falla, la tarea completa reporta
  `Success = false` con metadatos `setup_failed = true`. Admirald marca
  la instancia como `setup_failed` y `commercial_status = cancelled`.
  Harbor, al sincronizar este estado, cancela la suscripcion de PayPal
  y reembolsa el ultimo pago al cliente.

**Idempotencia:** `setup_command` solo se ejecuta si y solo si la
columna `setup_completed` en la base de datos de admirald es `false`.
Ademas, `admiral-fleet` escribe un archivo marker local (`setup_done`)
para evitar re-ejecutar el setup si el callback se pierde y hay un
retry en el mismo nodo. La base de datos sigue siendo la fuente de
verdad; si `setup_completed` es `true`, fleet omite el setup incluso si
el marker no existe (por ejemplo, una migracion cross-node).

### Modelo de red: Pod

Los servicios de una misma aplicacion se ejecutan dentro de un pod de Podman.
Los contenedores dentro del mismo pod se comunican usando `127.0.0.1` y el
puerto interno del servicio.

No se requiere nombre de host ni alias de red para la comunicacion intra-pod.

> **Nota para aplicaciones PHP**: El driver `mysqli` de PHP interpreta
> `localhost` como conexion via Unix socket en lugar de TCP. Use `127.0.0.1`
> como host de base de datos.

### `depends_on`

`depends_on` permite declarar orden de arranque entre servicios:

```yaml
services:
  backend:
    depends_on:
      - db
      - redis-cache
```

La implementacion actual traduce estas dependencias a `Wants=` y `After=` en
las unidades Quadlet generadas por `admiral-fleet`. Eso significa:

- systemd decide el orden de activacion
- no se implementa un orquestador adicional en Fleet
- `depends_on` expresa orden de arranque, no readiness real de aplicacion

Si una app requiere esperar a que un servicio acepte conexiones, esa garantia
no la da `depends_on` por si solo en esta version.

## Shared Volumes

`shared_volumes` permite montar el mismo volumen persistente en varios
servicios de una app.

```yaml
shared_volumes:
  sites:
    mount: /home/frappe/frappe-bench/sites
    services:
      - backend
      - scheduler
      - worker-default
```

Campos:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `mount` | string | si | Ruta absoluta donde se monta el volumen en cada servicio |
| `services` | []string | si | Servicios que comparten el volumen |
| `uid` | int | no | UID deseado para uso operativo futuro |
| `gid` | int | no | GID deseado para uso operativo futuro |

Reglas:

- cada shared volume debe tener nombre unico dentro de la app
- `mount` debe ser una ruta absoluta
- `services` no puede estar vacio
- todos los servicios listados deben existir en `services`
- dos shared volumes no pueden usar el mismo `mount`
- un servicio no puede tener conflicto entre su `volume` privado y un shared
  volume en la misma ruta de montaje

Fleet crea un solo volumen Podman por shared volume y lo monta en todos los
contenedores declarados.

### Registro privado de contenedores

Si la imagen del servicio reside en un registro privado, se debe incluir un
bloque `registry` con las credenciales de autenticacion:

```yaml
services:
  web:
    image: registry.example.com/my-app:1.0.0
    registry:
      server: registry.example.com
      username: deploy-user
      password: s3cr3t-token
```

Campos:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `server` | string | si | Dominio del registro (ej: `registry.example.com`) |
| `username` | string | si | Nombre de usuario o token |
| `password` | string | si | Contrasena o token de acceso |

Al provisionar, `admiral-fleet` ejecuta `podman login` como el usuario
rootless antes de iniciar el pod, almacenando las credenciales en el
`auth.json` del usuario para que Podman pueda descargar la imagen.

Se pueden usar registros con certificados autofirmados configurando
`insecure = true` en `/etc/containers/registries.conf.toml` del nodo worker.

## Secretos

`env` es para valores no sensibles. `secrets` es para valores sensibles
recuperables por `admirald`.

Los secretos pueden definirse a nivel de servicio (`services.<name>.secrets`)
o a nivel de aplicacion (`secrets` en la raiz del YAML). Los secretos a nivel
de aplicacion no estan asociados a un servicio particular y se resuelven antes
del provisionamiento.

Campos de cada secreto:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `generate` | string | condicional | `username`, `password`, `random` o `ssh_key` |
| `value` | string | condicional | Valor explicito del secreto |
| `expose` | bool | no | Si `true`, el valor aparece una vez en la respuesta de provisionamiento |
| `persist` | bool | no | Si `true`, el valor se genera una sola vez y se reutiliza durante toda la vida de la instancia |

Cada secreto debe definir exactamente una fuente: `generate` o `value`, no ambas.

`persist: true` (default `false`) indica que el secreto debe generarse una
sola vez y mantenerse estable durante toda la vida de la instancia. Si el
secreto ya existe en la base de datos (por ejemplo al reprovisionar la misma
instancia), se reutiliza el valor anterior. Los secretos persistentes se
generan con 256 bits de entropia (32 bytes).

Usos recomendados de `persist`:
- `SECRET_KEY` de Ghost, Flask, Django (firman sesiones)
- Cualquier secreto que si cambia invalida datos de usuario

### Propagacion de credenciales DB

La implementacion actual propaga credenciales de base de datos desde el
servicio detectado como DB hacia secretos cliente que terminen en:

- `_DB_USER`
- `_DB_PASSWORD`
- `_DB_NAME`

Eso permite plantillas tipo WordPress/MariaDB donde ambas partes deben
compartir credenciales.

## Health checks (opcional)

Aunque el contrato YAML permite definir `healthcheck` en los servicios, actualmente `admiral-fleet` utiliza un Health Checker simplificado basado únicamente en el estado del pod de Podman.

Reglas actuales:
- Si el pod está `Running`, el estado es `healthy`.
- En cualquier otro caso, el estado es `stopped`.
- Los campos específicos de `http`, `tcp` o `command` definidos en el YAML son validados por `admirald` pero **ignorados** por el agente de ejecución en esta fase.

### Separacion de conceptos

- `status` refleja el ciclo de vida (provisioning, running, stopped, deprovisioned).
- `health` refleja el estado de salud según el checker de `admiral-fleet`.

## Tiers

Campos requeridos por tier:

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `cpu` | float | Presupuesto total de CPU del pod |
| `memory` | string | Limite de memoria (ej: `512M`, `1G`) |
| `storage` | string | Limite de almacenamiento |
| `price_monthly` | float | Precio mensual del tier |
| `free` | bool | Si `true`, el tier es gratuito (`price_monthly` debe ser 0) |

`cpu` puede ser fraccional. `memory` y `storage` usan formato: numero +
unidad opcional (`G`, `Gi`, `M`, `Mi`, `K`, `Ki`, `T`, `Ti`).

Los tiers con `free: true` no requieren checkout en harbor. El provisioning
se realiza directamente sin pasar por PayPal. Si `free: true` y ademas
`price_monthly` es distinto de 0, la validacion rechaza la definicion.

Campos opcionales:

| Campo | Tipo | Descripcion |
|-------|------|-------------|
| `free` | bool | Marca el tier como gratuito. No requiere checkout ni pago |
| `environment` | map | Variables de entorno del tier |
| `backups` | BackupPolicy | Politica de backups del tier |

### Politica de backups por tier

Campos de `tiers.<name>.backups`:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `enabled` | bool | si | Activa backups programados para este tier |
| `schedule` | string | condicional | `disabled`, `daily` o `weekly` (validado solo si `enabled=true`) |
| `weekday` | string | no | Reservado para uso futuro (no implementado) |
| `time` | string | no | Reservado para uso futuro (no implementado) |
| `timezone` | string | no | Reservado para uso futuro (no implementado) |
| `retention.count` | int | condicional | Numero maximo de backups a conservar (validado si `enabled=true`) |
| `retention.days` | int | condicional | Dias maximos de retencion (validado si `enabled=true`) |
| `manual_backups` | bool | no | Permite backups manuales (default `false`) |
| `backup_database` | bool | no | Activa backup de base de datos en este tier (default `false`) |
| `backup_volumes` | bool | no | Activa backup de volumenes en este tier (default `false`) |
| `restore_allowed` | bool | no | Permite restaurar desde backup en este tier (default `false`) |

```yaml
tiers:
  starter:
    backups:
      enabled: true
      schedule: daily       # disabled | daily | weekly
      weekday: sunday       # solo si schedule=weekly
      time: "02:00"
      timezone: "UTC"
      retention:
        count: 7
        days: 30
      manual_backups: true
      backup_database: true
      backup_volumes: false
      restore_allowed: true
```

### Variables de entorno por tier

`environment` permite definir pares `KEY: VALUE` que se inyectan en las
instancias. Reglas:

- la clave debe usar solo `A-Z`, `0-9` y `_`
- la clave debe empezar con una letra o `_`
- la clave no puede usar el prefijo reservado `ADMIRAL_`
- el valor siempre se trata como texto

Precedencia del entorno al provisionar:

1. `tiers.<name>.environment` — mayor prioridad, permite al operador
   sobreescribir valores por plan
2. `services.<name>.env`
3. Variables internas de Admiral (`ADMIRAL_APP_CODE`, `ADMIRAL_TIER_CODE`,
   `ADMIRAL_INSTANCE_ID`, `ADMIRAL_TENANT_ID`, `ADMIRAL_ENVIRONMENT`)

Las variables con prefijo `ADMIRAL_` son protegidas por el sistema.
No pueden ser sobreescritas desde `env` de servicio ni desde `environment`
del tier.

## `services.<name>.backup`

Describe como construir tareas de backup para un servicio individual.

| Campo | Requerido | Descripcion |
|-------|-----------|-------------|
| `type` | si | `database`, `volume` o `none` |
| `engine` | condicional | `postgresql`, `mysql`, `mariadb` (requerido si type=database) |
| `database_env` | condicional | Env var con nombre de DB (requerido si type=database) |
| `username_env` | condicional | Env var con usuario DB (requerido si type=database) |
| `password_env` | condicional | Env var con contrasena DB (requerido si type=database) |

Reglas:

- Cada servicio debe declarar `backup`.
- `type: none` indica explicitamente que el servicio no requiere respaldo.
- `type: volume` requiere que el servicio declare `volume` o participe en al
  menos un `shared_volumes`.
- `type: database` requiere `engine`, `database_env`, `username_env` y `password_env`.

### `type: database`

Respaldo logico via dump de base de datos. Admirald envia la accion
`backup_database` y fleet ejecuta el comando apropiado segun el engine:

- `postgresql` → `pg_dump`
- `mysql` → `mysqldump`
- `mariadb` → `mariadb-dump`

### `type: volume`

Respaldo del contenido persistente del servicio. Admirald envia la accion
`backup_volumes` y fleet comprime en un tarball:

- el volumen privado del servicio si existe
- los shared volumes asociados a ese servicio si existen

Los backups de volumen tambien se activan independientemente via
`tier.<name>.backups.backup_volumes: true`.

### `type: none`

Servicio sin estado respaldable. Admiral no debe intentar respaldarlo.

### Patron recomendado (WordPress)

```yaml
services:
  web:
    image: docker.io/library/wordpress:6
    volume: wp_content
    backup:
      type: volume

  db:
    image: docker.io/library/mariadb:10
    volume: db_data
    backup:
      type: database
      engine: mariadb
      database_env: MARIADB_DATABASE
      username_env: MARIADB_USER
      password_env: MARIADB_PASSWORD
    env:
      MARIADB_DATABASE: wordpress
    secrets:
      MARIADB_ROOT_PASSWORD:
        generate: password
      MARIADB_USER:
        generate: username
        expose: true
      MARIADB_PASSWORD:
        generate: password
        expose: true
tiers:
  small:
    backups:
      enabled: true
      schedule: daily
      backup_database: true
      backup_volumes: true
```

Esto asegura que tanto la base de datos como `wp-content` (plugins, themes,
uploads) sean respaldados.

## Volumen persistente

Los servicios con `volume` declarado reciben un volumen persistente de Podman
que sobrevive a reinicios del contenedor.

Los volumenes se montan en un directorio default segun la imagen o nombre:

| Deteccion | Mount target |
|---|---|
| imagen contiene `postgres` | `/var/lib/postgresql/data` |
| imagen contiene `mariadb` o `mysql` | `/var/lib/mysql` |
| imagen contiene `wordpress` | `/var/www/html/wp-content` |
| servicio se llama `db` | `/var/lib/postgresql/data` |
| cualquier otra | `/data` |

Los `shared_volumes` no usan autodeteccion de mount target: la ruta se toma
directamente de `shared_volumes.<name>.mount`.

## Validacion actual

Reglas activas en `admirald/pkg/admiral/validation.go`:

- `name` requerido, formato `^[a-z][a-z0-9-]*$`
- `display_name` requerido
- al menos un servicio
- cada servicio debe tener `image`
- si un servicio declara `port > 0`, ese puerto debe ser unico dentro de la app
- solo un servicio puede ser `public: true`
- servicio publico requiere `port > 0`
- `depends_on`: cada dependencia debe existir y no se permiten ciclos
- `shared_volumes`: nombre valido, `mount` absoluto, servicios existentes,
  lista no vacia y sin mounts duplicados
- al menos un tier
- cada tier debe tener `cpu > 0`, `memory`, `storage`, `price_monthly >= 0`
- si `free: true`, `price_monthly` debe ser 0
- cada secreto debe definir exactamente una fuente (`generate`, `value`)
- `generate` debe ser `username`, `password`, `random` o `ssh_key`
- si existe `backup`:
  - `type` requerido (`database`, `volume` o `none`)
  - si `type=database`: `engine` requerido (`postgresql`, `mysql`, `mariadb`)
  - si `type=database`: `database_env`, `username_env`, `password_env` requeridos
  - si `type=volume`: el servicio debe declarar `volume` o usar `shared_volumes`
- `healthcheck`: validación sintáctica de `type` (`http`, `tcp`, `command`) y sus campos asociados.
- `environment` del tier: formato `^[A-Z_][A-Z0-9_]*$`, sin prefijo `ADMIRAL_`
- `memory` y `storage`: formato numero + unidad (`k/kb/kib/m/mb/mib/g/gb/gib/t/tb/tib`)
- `backup.schedule`: `disabled`, `daily` o `weekly`

## Notas

- Los servicios dentro de una misma app se ejecutan en un pod de Podman y se
  comunican via `localhost`.
- El orden de arranque entre servicios lo resuelve systemd a partir de
  `depends_on` traducido a Quadlet (`Wants=` y `After=`).
- Cuando el tier define CPU o memoria, `admiral-fleet` aplica limites al pod
  completo con Quadlet/Podman.
- Las variables de entorno que referencien otros servicios deben usar
  `localhost` como host, no el nombre del servicio.
- El contrato no embebe detalles de Podman ni systemd.
- `admiral-fleet` recibe `env` y `secrets` ya materializados por tarea cuando
  la accion lo requiere.
- `ADMIRAL_SECRETS_KEY` nunca sale de `admirald`.
- `podman-restart.service` debe estar habilitado en el nodo para asegurar
  persistencia de contenedores root y estado operativo tras reinicio.
