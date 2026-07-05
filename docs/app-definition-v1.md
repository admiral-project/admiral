# Admiral App Definition v1

Este documento describe el formato YAML actualmente validado por `admirald` y reutilizado por `admiralctl apps validate`.

## Estructura base

Campos soportados en la raiz del YAML:

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `name` | string | si | Identificador unico de la app (`^[a-z][a-z0-9-]*$`) |
| `display_name` | string | si | Nombre legible para mostrar en UI |
| `description` | string | no | Descripcion de la aplicacion |
| `environment` | map[string]string | no | Variables de entorno globales compartidas por todos los servicios |
| `services` | map[string]YAMLService | si | Servicios contenedores de la app |
| `shared_volumes` | map[string]YAMLSharedVolume | no | Volumenes persistentes compartidos entre varios servicios |
| `tiers` | map[string]YAMLTier | si | Planes de precio y recursos disponibles |
| `secrets` | map[string]YAMLSecret | no | Secretos globales de la aplicacion |

```yaml
name: simple-crm
display_name: Simple CRM
description: CRM ligero para pequenas empresas
environment:
  APP_BASE_URL: https://crm.example.com

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
| `depends_on` | []string | no | Dependencias debiles de orden de arranque entre servicios (`Wants=` + `After=`) |
| `requires` | []string | no | Dependencias fuertes entre servicios (`Requires=` + `After=`) |
| `command` | string | no | Comando alternativo para el contenedor |
| `setup_command` | string | no | Comando de inicializacion ejecutado una sola vez tras el provision |
| `setup_timeout` | int | no | Timeout en segundos para `setup_command` (default: 600) |
| `notify_on_setup` | []YAMLSetupNotice | no | Datos informativos para mostrar al cliente tras completar setup |
| `env` | map[string]string | no | Variables de entorno estaticas o referencias `${VAR}` a env/secretos disponibles |
| `secrets` | map[string]YAMLSecret | no | Secretos generados o explicitos |
| `healthcheck` | YAMLHealthCheck | no | Healthcheck del servicio |
| `healthcheck_wait_timeout` | int | no | Tiempo maximo en segundos para esperar que el servicio alcance readiness (default: 120) |
| `backup` | YAMLServiceBackup | si | Contrato explicito de respaldo para ese servicio |
| `registry` | YAMLRegistry | no | Credenciales para registro privado |
| `user` | string | no | UID o nombre de usuario con el que ejecutar el contenedor (`--user` de podman) |

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

**Validacion de caracteres:** `admirald` rechaza `setup_command` que
contengan los siguientes caracteres y patrones inseguros:

| Patron | Motivo |
|--------|--------|
| `;` | Separacion de comandos sin control |
| `&` | Ejecucion en segundo plano (`&`) o AND condicional (`&&`) |
| `` ` `` | Subshell con backtick |
| `\|` | Pipe (`\|`) u OR condicional (`\|\|`) |
| `$(` | Subshell con `$()` |

Los comandos multi-paso deben usar un bloque YAML con literal escalar
(`\|`) para separar lineas, ya que `sh -c` interpreta saltos de linea
como separadores de comandos:

```yaml
services:
  web:
    setup_command: |
      primer-comando --arg $VAR
      segundo-comando --otro $OTRO_VAR
      tercero --final
```

> Nota: La sustitucion simple `$VAR` y `${VAR}` si esta permitida.
> Solo se bloquea `$(` (subshell) y los caracteres listados arriba.

El contenedor one-shot se ejecuta como root (UID 0) por defecto. Si la
imagen requiere un usuario no-root (por ejemplo, Gitea rechaza ejecutar
como root), se debe declarar el campo `user` con el UID o nombre de
usuario del contenedor:

```yaml
services:
  web:
    image: docker.io/gitea/gitea:1.22
    user: "1000"  # git user inside the container
    setup_command: gitea admin user list --admin | grep -F "$GITEA_ADMIN_USERNAME" || gitea admin user create --username "$GITEA_ADMIN_USERNAME" --password "$GITEA_ADMIN_PASSWORD" --email "$GITEA_ADMIN_EMAIL" --admin
```

```yaml
services:
  backend:
    image: registry.example.com/app-suite:1
    setup_command: app bootstrap --admin-password $ADMIN_PASSWORD
    notify_on_setup:
      - label: Usuario administrador
        value: Administrator
```

**Cuando una app define `setup_command` en algun servicio:**

- La instancia pasa por el estado tecnico `initializing` (en lugar de
  ir directamente a `running`) para informar al usuario que la
  inicializacion esta en curso. El tiempo estimado se calcula del
  campo `setup_timeout` y se muestra en los portales.
- `admiral-fleet` ejecuta cada `setup_command` con un timeout de
  `setup_timeout` segundos (default: 600, i.e. 10 minutos).
  Valores comunes: 120 (2 min) para WP-CLI, 3600 (1 hora) para
  `bench new-site --install-app erpnext`.
- Antes de ejecutar `setup_command`, `admiral-fleet` espera a que el
  servicio objetivo y sus dependencias declaradas en `requires` y
  `depends_on`
  alcancen readiness. Si un servicio define `healthcheck`, ese contrato
  se usa como criterio de readiness; si no lo define, se exige al menos
  que el contenedor exista y este en estado `running`.
- Después de un `setup_command` exitoso, `admiral-fleet` reinicia el pod
  afectado para que el servicio largo lea la configuracion persistida por
  el setup antes de declararlo listo para el primer uso.
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

### `notify_on_setup`

`notify_on_setup` permite declarar pares `label/value` para mostrarlos al
cliente junto con las credenciales expuestas cuando el provisionamiento
responde o cuando Harbor consulta `/credentials`.

Uso recomendado:

- nombres de usuario predefinidos por la aplicacion
- URLs internas relevantes para onboarding
- identificadores operativos que no sean secretos

No debe usarse para contrasenas, tokens o material secreto; para eso se
deben usar `secrets` con `expose: true`.

### Modelo de red: Pod

Los servicios de una misma aplicacion se ejecutan dentro de un pod de Podman.
Los contenedores dentro del mismo pod se comunican usando `127.0.0.1` y el
puerto interno del servicio.

No se requiere nombre de host ni alias de red para la comunicacion intra-pod.

> **Nota para aplicaciones PHP**: El driver `mysqli` de PHP interpreta
> `localhost` como conexion via Unix socket en lugar de TCP. Use `127.0.0.1`
> como host de base de datos.

### `depends_on`

`depends_on` permite declarar orden de arranque entre servicios con
dependencia debil:

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
- si el servicio dependido falla, este servicio igualmente arranca
- no se implementa un orquestador adicional en Fleet
- `depends_on` expresa orden de arranque y, si el servicio dependido tiene
  `healthcheck`, tambien condiciona el inicio de `setup_command` a ese
  readiness declarado

### `requires`

`requires` permite declarar dependencias fuertes entre servicios:

```yaml
services:
  web:
    requires:
      - db
```

La implementacion traduce estas dependencias a `Requires=` y `After=` en
las unidades Quadlet generadas por `admiral-fleet`. A diferencia de `depends_on`:

- si el servicio requerido falla, systemd detiene o no arranca este servicio
- util para servicios que no pueden operar sin su dependencia
- `requires` y `depends_on` pueden coexistir en el mismo servicio

### `healthcheck_wait_timeout`

Controla el tiempo maximo total (en segundos) que `admiral-fleet` espera
a que el servicio alcance readiness durante el provisionamiento.

```yaml
services:
  db:
    healthcheck:
      type: tcp
      port: 3306
    healthcheck_wait_timeout: 180
```

- el valor default es 120 segundos (60 intentos × 2s de intervalo)
- el intervalo entre intentos se configura via `healthcheck.interval_seconds`
- si se configura `healthcheck_wait_timeout`, el numero de reintentos se
  recalcula como `timeout / interval_seconds`

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

### Restriccion de nombres sensibles en `env`

`admiral-fleet` rechaza nombres de variables en `env` que contengan
(`sin importar mayusculas/minusculas`):

- `SECRET`
- `PASSWORD`
- `TOKEN`
- `KEY`
- `CREDENTIAL`

Si una variable de entorno tiene un nombre sensible (ej.
`MARIADB_ROOT_PASSWORD`, `POSTGRES_PASSWORD`, `DB_PASSWORD`, `API_KEY`,
`AUTH_TOKEN`), debe declararse en `secrets:` del servicio, no en `env:`.

Las variables en `secrets:` se inyectan via `Secret=` de Quadlet
(almacen secreto cifrado de Podman), no en el archivo de entorno plano:

```yaml
services:
  db:
    image: docker.io/library/mariadb:10
    env:
      MARIADB_DATABASE: wordpress        # bien: no contiene palabra sensible
    secrets:
      MARIADB_ROOT_PASSWORD:             # bien: va en secrets, no en env
        generate: password
      MARIADB_USER:
        generate: username
      MARIADB_PASSWORD:
        generate: password
```

### Propagacion entre servicios

Cuando un servicio de base de datos (PostgreSQL, MariaDB, MySQL)
define secretos con nombres como `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`MARIADB_USER`, `MARIADB_PASSWORD`, `admiral` los propaga automaticamente
a servicios cliente que tengan secretos con nombres que terminen en:

- `_DB_USER`
- `_DB_PASSWORD`
- `_DB_NAME`

O que coincidan exactamente con el nombre del secreto de la DB.

Esto permite que WordPress reciba `WORDPRESS_DB_USER` con el mismo valor
que `MARIADB_USER`, sin tener que declarar valores explicitos ni
generar secretos independientes.

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

Aunque el contrato YAML permite definir `healthcheck` en los servicios, la
implementacion actual distingue dos usos:

- durante el provisionamiento, `admiral-fleet` si usa `healthcheck`
  como criterio de readiness antes de ejecutar `setup_command`
- fuera de ese flujo, el health checker operativo sigue siendo simplificado
  y se basa principalmente en el estado del pod/contenedor

Reglas actuales durante provisionamiento:
- si el contenedor no esta `running`, el servicio no esta listo
- `type: command` ejecuta el comando dentro del servicio
- `type: tcp` intenta conectar al puerto publicado del servicio
- `type: http` hace un GET al puerto publicado y valida el status esperado
- si no hay `healthcheck`, el readiness minimo es que el contenedor exista y
  este en estado `running`

Reglas actuales para salud operativa simplificada:
- si el pod/servicio esta `Running`, el estado es `healthy`
- en cualquier otro caso, el estado es `stopped`

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
3. `environment` global de la app
4. Variables internas de Admiral (`ADMIRAL_APP_CODE`, `ADMIRAL_TIER_CODE`,
   `ADMIRAL_INSTANCE_ID`, `ADMIRAL_TENANT_ID`, `ADMIRAL_ENVIRONMENT`,
   `ADMIRAL_PUBLIC_URL`, `ADMIRAL_PUBLIC_HOSTNAME`)

Las variables con prefijo `ADMIRAL_` son protegidas por el sistema.
No pueden ser sobreescritas desde `env` de servicio ni desde `environment`
del tier.

`admirald` es la fuente de verdad de las variables internas `ADMIRAL_*`.
Estas variables son reservadas globales del runtime: se inyectan en todos los
servicios de la instancia y no deben declararse en la definicion de app, en
`services.<name>.env`, en `environment` global ni en `tiers.<name>.environment`.

Cuando la instancia tiene una ruta publica, `admirald` tambien inyecta como
variables reservadas globales:

- `ADMIRAL_PUBLIC_URL`: URL publica completa con esquema y `/` final, por
  ejemplo `https://wp189654.apps.example.com/`.
- `ADMIRAL_PUBLIC_HOSTNAME`: hostname publico sin esquema, por ejemplo
  `wp189654.apps.example.com`.

Las apps que necesitan fijar su URL canonical durante `setup_command` deben
usar `ADMIRAL_PUBLIC_URL`. Si la app tambien soporta ejecuciones sin ruta
publica, puede definir un fallback explicito:

```yaml
setup_command: app setup --url=${ADMIRAL_PUBLIC_URL:-https://$ADMIRAL_INSTANCE_ID.local}
```

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
- `requires`: cada dependencia debe existir y no se permiten ciclos
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
- `environment` global de la app: formato `^[A-Z_][A-Z0-9_]*$`, sin prefijo `ADMIRAL_`
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
- Las referencias `${VAR}` en `env` se resuelven en este orden:
  secretos del servicio, secretos globales, entorno final mergeado.
- La precedencia del merge de entorno es:
  variables internas Admiral, `environment` global, `service.env`, `tier.environment`.
- El contrato no embebe detalles de Podman ni systemd.
- `admiral-fleet` recibe `env` y `secrets` ya materializados por tarea cuando
  la accion lo requiere.
- `ADMIRAL_SECRETS_KEY` nunca sale de `admirald`.
- `podman-restart.service` debe estar habilitado en el nodo para asegurar
  persistencia de contenedores root y estado operativo tras reinicio.
