# Admiral Configuration

Este documento describe la configuracion actualmente soportada por el codigo.

## `admirald`

Orden de carga:

1. defaults embebidos
2. `/etc/admirald.ini`
3. variables de entorno

### Campos soportados

Archivo `/etc/admirald.ini`:

```ini
port=8080
database_url=postgres://admiral_core_user:postgres@localhost:5432/admiral_core?sslmode=require
queue_database_url=postgres://admiral_queue_user:postgres@localhost:5432/admiral_queue?sslmode=require
admin_token=replace-with-internal-token
token_pepper=replace-with-long-random-pepper
secrets_key=replace-with-long-random-production-secret
flagship_admin_user=admin
flagship_admin_pswd=replace-with-long-random-admin-password
tls_cert_file=/etc/admiral/tls/admirald.pem
tls_key_file=/etc/admiral/tls/admirald-key.pem
networking_base_domain=cloud.example.com
networking_admin_host=admin.cloud.example.com
networking_admin_target=
networking_flagship_target=https://127.0.0.1:5000
networking_portal_host=portal.cloud.example.com
networking_apps_domain=apps.cloud.example.com
networking_apps_redirect=portal.cloud.example.com
networking_tls_provider=letsencrypt
networking_tls_email=ops@example.com
caddy_admin_url=http://127.0.0.1:2019
```

Variables de entorno equivalentes:

- `ADMIRAL_PORT`
- `ADMIRAL_ENV` — define entorno (`development` o produccion)
- `ADMIRAL_DATABASE_URL`
- `ADMIRAL_QUEUE_DATABASE_URL`
- `ADMIRAL_ADMIN_TOKEN`
- `ADMIRAL_TOKEN_PEPPER`
- `ADMIRAL_SECRETS_KEY`
- `ADMIRAL_FLAGSHIP_ADMIN_USER`
- `ADMIRAL_FLAGSHIP_ADMIN_PSWD`
- `ADMIRAL_TLS_CERT_FILE`
- `ADMIRAL_TLS_KEY_FILE`
- `ADMIRAL_NETWORKING_BASE_DOMAIN` — dominio base, usado para auto-derivar los demas hosts si no se definen explicitamente
- `ADMIRAL_NETWORKING_ADMIN_HOSTNAME`
- `ADMIRAL_NETWORKING_ADMIN_TARGET` — default vacio (placeholder); si se define, Caddy hace proxy reverso
- `ADMIRAL_NETWORKING_PORTAL_HOSTNAME`
- `ADMIRAL_NETWORKING_PORTAL_TARGET` — target para portal
- `ADMIRAL_NETWORKING_APPS_DOMAIN`
- `ADMIRAL_NETWORKING_APPS_REDIRECT_TO`
- `ADMIRAL_NETWORKING_TLS_PROVIDER`
- `ADMIRAL_NETWORKING_TLS_EMAIL`
- `ADMIRAL_NETWORKING_TLS_CERT_FILE` — certificado wildcard publico (Let's Encrypt)
- `ADMIRAL_NETWORKING_TLS_KEY_FILE` — clave privada del certificado wildcard
- `ADMIRAL_NETWORKING_FLAGSHIP_HOST` — default `flagship.<base_domain>`
- `ADMIRAL_NETWORKING_FLAGSHIP_TARGET` — default `https://127.0.0.1:5000`
- `ADMIRAL_NETWORKING_COCKPIT_HOST` — default `cockpit.<base_domain>`
- `ADMIRAL_NETWORKING_COCKPIT_TARGET` — default `https://127.0.0.1:9090`
- `ADMIRAL_CADDY_ADMIN_URL`

### Reglas actuales

- `admin_token` y `token_pepper` son obligatorios
- `queue_database_url` es obligatorio
- `flagship_admin_user` y `flagship_admin_pswd` se usan solo para bootstrap inicial
- `tls_cert_file` es obligatorio
- `tls_key_file` es obligatorio
- `database_url` y `queue_database_url` deben apuntar a bases logicas distintas
- `caddy_admin_url` usa por defecto `http://127.0.0.1:2019`
- `networking_admin_target` si se define, Caddy hará reverse proxy hacia esa URL en lugar de responder con placeholder estático. Vacío por defecto (solo placeholder).
- `networking_portal_target` default `https://127.0.0.1:5001` para admiral-harbor
- `networking_flagship_target` default `https://127.0.0.1:5000` para admiral-flagship. `networking_admin_target` y `networking_flagship_target` son independientes: el primero controla la ruta admin, el segundo la ruta flagship.
- `networking_cockpit_target` default `https://127.0.0.1:9090` para Cockpit
- la contraseña administrativa se guarda como hash Argon2id antes de persistirse en `admin_users`
- si ya existe al menos un administrador, `flagship_admin_user` y `flagship_admin_pswd` se ignoran al arrancar
- si no existe ningún administrador y faltan esas credenciales, el arranque falla con un error de bootstrap explícito
- la contraseña inicial debe tener al menos 12 caracteres, no puede tener espacios al inicio o al final y no debe ser `secret`, `admin` ni igual al usuario

### Base de datos

Backends soportados hoy:

- PostgreSQL (SQLite no está soportado en `admirald` y requiere PostgreSQL tanto para la base de datos principal como para la cola duradera).

Ejemplo:

```ini
database_url=postgres://admiral_core_user:postgres@localhost:5432/admiral_core?sslmode=require
queue_database_url=postgres://admiral_queue_user:postgres@localhost:5432/admiral_queue?sslmode=require
```

### `secrets_key`

Comportamiento actual:

- En **produccion** (ADMIRAL_ENV no definido o distinto de `development`):
  `ADMIRAL_SECRETS_KEY` es obligatorio. Si falta, admirald falla al arrancar.
- En **desarrollo** (`ADMIRAL_ENV=development`): si no se define, se usa una
  clave efimera `dev-ephemeral-key-change-me`.

No hay fallback a `admin_token`. Producion debe siempre definir
`ADMIRAL_SECRETS_KEY` explicita y estable.

### Rotacion de `ADMIRAL_SECRETS_KEY`

Para rotar la clave sin perder secretos existentes, configure la nueva clave
en `ADMIRAL_SECRETS_KEY` y la anterior en `ADMIRAL_SECRETS_KEY_PREVIOUS`
(separadas por comas si hay más de una). Los nuevos valores se cifran con la
clave actual; los valores existentes siguen siendo descifrables durante la
ventana de migración. Después de re-cifrar o reemplazar los secretos
existentes, retire las claves anteriores y reinicie `admirald`.

## `admiral-fleet`

Variables soportadas:

- `ADMIRAL_FLEET_NODE_ID`
- `ADMIRAL_API_URL`
- `ADMIRAL_API_CA_FILE`
- `ADMIRAL_FLEET_TOKEN`
- `ADMIRAL_FLEET_EXECUTOR`
- `ADMIRAL_FLEET_QUADLET_DIR`
- `ADMIRAL_FLEET_DATA_DIR`
- `ADMIRAL_FLEET_CALLBACK_OUTBOX`
- `ADMIRAL_FLEET_HTTP_ADDR`
- `ADMIRAL_FLEET_PUBLIC_HOST`
- `ADMIRAL_FLEET_PUBLIC_PORT`
- `ADMIRAL_FLEET_STORAGE_CHECK_INTERVAL`
- `ADMIRAL_FLEET_STORAGE_EXCEEDED_ACTION`
- `ADMIRAL_FLEET_ROOTLESS_USER` — **obligatorio**. Define el usuario Unix para ejecutar pods rootless. Sin esta variable, fleet falla al iniciar.

Defaults actuales:

- `ADMIRAL_API_URL=https://127.0.0.1:8080`
- `ADMIRAL_FLEET_EXECUTOR=simulated`
- `ADMIRAL_FLEET_QUADLET_DIR=/etc/containers/systemd/admiral`
- `ADMIRAL_FLEET_DATA_DIR=/var/lib/admiral`
- `ADMIRAL_FLEET_CALLBACK_OUTBOX=/var/lib/admiral/outbox`
- `ADMIRAL_FLEET_HTTP_ADDR=127.0.0.1:9099`
- `ADMIRAL_FLEET_STORAGE_CHECK_INTERVAL=60s`
- `ADMIRAL_FLEET_STORAGE_EXCEEDED_ACTION=report_only`

Reglas:

- `ADMIRAL_FLEET_NODE_ID` es obligatorio
- `ADMIRAL_FLEET_TOKEN` es obligatorio
- `ADMIRAL_API_URL` debe usar `https://`
- executors validos:
  - `simulated`
  - `systemd-podman`
- `ADMIRAL_FLEET_STORAGE_CHECK_INTERVAL` acepta duraciones Go (`60s`, `5m`, `120s`)
- `ADMIRAL_FLEET_STORAGE_EXCEEDED_ACTION` valores:
  - `report_only` (default) — solo reporta, no toma acciones destructivas
  - `pause_instance` — experimental: pausa la instancia al exceder storage
  - `stop_pod` — experimental: detiene el pod al exceder storage

`admiral-fleet` no debe recibir `ADMIRAL_SECRETS_KEY`.
Fleet no requiere acceso directo a la base de datos de cola. Las tareas se reciben via API HTTP desde `admirald`.

## `admiralctl`

Archivo de configuracion:

- `~/.config/admiralctl/config.yaml`

Campos soportados:

```yaml
server_url: https://localhost:8080
token: dev-token
ca_cert_file: /etc/admiral/tls/ca.pem
```

Overrides por entorno:

- `ADMIRAL_SERVER_URL`
- `ADMIRAL_ADMIN_TOKEN`
- `ADMIRAL_TLS_CA_FILE`

Reglas:

- `ADMIRAL_SERVER_URL` debe usar `https://`
- la CLI publica usa `admin_token`
- la CLI todavia no tiene configuracion separada para sesion admin

## Seguridad operativa

- `ADMIRAL_SECRETS_KEY` solo debe vivir en el nodo de `admirald`
- `ADMIRAL_QUEUE_DATABASE_URL` solo debe configurarse en `admirald`, nunca en `admiral-fleet`
- `ADMIRAL_FLAGSHIP_ADMIN_USER` solo debe vivir en el nodo de `admirald`
- `ADMIRAL_FLAGSHIP_ADMIN_PSWD` solo debe vivir en el nodo de `admirald`
- no exponer `caddy_admin_url` publicamente
- no usar brokers externos ni Redis como dependencias runtime del baseline oficial
