# Admiral Installation Guide — Single Node

Guía consolidada para desplegar Admiral en modo single-node sobre Enterprise Linux 10
(CentOS Stream 10 / Rocky Linux 10 / AlmaLinux 10).

Soporta dos modos de operación:

- **QA** — Sin DNS público, TLS interno autofirmado, componentes bound a `0.0.0.0:<port>`.
- **Producción** — DNS público configurado, wildcard Let's Encrypt vía DNS-01, Caddy como TLS terminator.

---

## Entorno de referencia

| Recurso  | Mínimo |
|----------|--------|
| OS       | EL 10 (CentOS Stream 10 / Rocky Linux 10 / AlmaLinux 10) |
| Podman   | 5.8.2+ (Quadlet `.pod` soportado) |
| Go       | 1.22+ (solo para build de RPMs) |
| PostgreSQL | 16 |
| Caddy    | 2.x (COPR) |
| RAM      | 4 GB |
| vCPUs    | 2 |
| SELinux  | enforcing |

## Arquitectura single-node

| Componente | Puerto | Protocolo | Binding QA | Binding Producción |
|---|---|---|---|---|
| `admirald` | 8080 | HTTPS | 127.0.0.1 | 127.0.0.1 |
| `admiral-fleet` | 9099 | HTTP | 127.0.0.1 | 127.0.0.1 |
| `admiral-flagship` | 5000 | HTTPS | **0.0.0.0** | **0.0.0.0** |
| `admiral-harbor` | 5001 | HTTPS | **0.0.0.0** | **0.0.0.0** |
| PostgreSQL | 5432 | TCP | 127.0.0.1 | 127.0.0.1 |
| Caddy admin | 2019 | HTTP | 127.0.0.1 | 127.0.0.1 |
| Apps | 40000-49999 | Variable | 0.0.0.0 | 0.0.0.0 |

---

## 1. Inicializar submódulos

```bash
cd /root/admiral
git submodule update --init --recursive
```

## 2. Habilitar repositorios e instalar dependencias

El método oficial de distribución es el repositorio COPR `admiral-project/admiral`.
Todos los componentes se instalan como RPMs.

```bash
dnf install -y 'dnf-command(copr)' epel-release
dnf copr enable -y @caddy/caddy
dnf copr enable -y admiral-project/admiral
dnf install -y golang podman postgresql-server postgresql-contrib python3-pip caddy
```

Las dependencias Python (`flask`, `flask-login`, `gunicorn`, `argon2-cffi`,
`flask-sqlalchemy`, `flask-alembic`, etc.) están empaquetadas como RPMs dentro
del COPR de Admiral y se instalan automáticamente como dependencias de
`admiral-flagship` y `admiral-harbor`.

> **Nota:** `golang` solo es necesario si vas a recompilar RPMs localmente
> (ver Paso 4). Para instalación estándar desde COPR no hace falta.

> **Nota:** `postgresql-server` se instala desde el playbook de Ansible antes
> de ejecutar `postgresql-setup`, porque algunas variantes de EL 10 no
> exponen ese comando hasta que el paquete está presente.

## 3. Usuario rootless para workloads

El usuario `admiral-apps` lo crea automáticamente el RPM `admiral-common`
via `%pre`. No requiere intervención manual. Verificar después de instalar:

```bash
id admiral-apps
```

## 4. Compilar RPMs localmente (solo si hay cambios locales no publicados)

Normalmente los RPMs se instalan directamente desde el COPR oficial
(`admiral-project/admiral`). Este paso solo es necesario si tienes cambios
locales en el código que aún no se han publicado.

```bash
dnf install -y golang rpm-build python3-pip

mkdir -p /root/admiral/packaging/build/{SOURCES,RPMS/{noarch,x86_64},SRPMS,SPECS,BUILD,tmp}

# Crear tarball fuente
tar --exclude=.git --exclude=packaging/build \
  -czf /root/admiral/packaging/build/SOURCES/admiral-0.0.1.alpha1.tar.gz \
  -C /root/admiral \
  --transform='s,^\./,admiral-v0.0.1.alpha1/,' \
  --transform='s,^\.$,admiral-v0.0.1.alpha1,' \
  .

# Copiar archivos de soporte
for f in admirald.service admiral-fleet.service admiral-flagship.service admiral-harbor.service \
         admirald.ini fleet.env admiralctl.yaml flagship.env harbor.env \
         admiral-harbor-worker.service admiral-harbor-worker.timer \
         admiral-harbor-catalog-sync.service admiral-harbor-catalog-sync.timer; do
  cp "/root/admiral/packaging/systemd/$f" /root/admiral/packaging/build/SOURCES/ 2>/dev/null || \
  cp "/root/admiral/packaging/config/$f" /root/admiral/packaging/build/SOURCES/ 2>/dev/null || true
done

cp /root/admiral/packaging/bin/* /root/admiral/packaging/build/SOURCES/ 2>/dev/null || true

RPMDEFS='--define _topdir /root/admiral/packaging/build
         --define _sourcedir /root/admiral/packaging/build/SOURCES
         --define _specdir /root/admiral/packaging/build/SPECS
         --define _builddir /root/admiral/packaging/build/BUILD
         --define _rpmdir /root/admiral/packaging/build/RPMS
         --define _srcrpmdir /root/admiral/packaging/build/SRPMS
         --define _tmppath /root/admiral/packaging/build/tmp'

# Python dependencies (solo si los wheels no están en SOURCES)
for wheel_spec in python-alembic python-flask-alembic python-flask-login python-flask-sqlalchemy; do
  cp "/root/admiral/packaging/rpm/$wheel_spec.spec" /root/admiral/packaging/build/SPECS/
  rpmbuild -ba $RPMDEFS /root/admiral/packaging/build/SPECS/$wheel_spec.spec
done

# Componentes Admiral
for spec in admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor; do
  cp "/root/admiral/packaging/rpm/$spec.spec" /root/admiral/packaging/build/SPECS/
  rpmbuild -ba $RPMDEFS /root/admiral/packaging/build/SPECS/$spec.spec
done
```

## 5. Generar certificados TLS internos

```bash
mkdir -p /etc/admiral/tls && cd /etc/admiral/tls

# CA
openssl genrsa -out ca-key.pem 4096
openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 365 \
  -subj "/C=US/ST=NY/O=Admiral/CN=Admiral CA" -out ca.pem

# admirald
openssl genrsa -out admirald-key.pem 2048
openssl req -new -key admirald-key.pem -out admirald.csr \
  -subj "/C=US/ST=NY/O=Admiral/CN=admirald"
openssl x509 -req -in admirald.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out admirald.pem -days 365 \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1")

# fleet
openssl genrsa -out fleet-key.pem 2048
openssl req -new -key fleet-key.pem -out fleet.csr \
  -subj "/C=US/ST=NY/O=Admiral/CN=fleet"
openssl x509 -req -in fleet.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out fleet.pem -days 365 \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1")

# flagship (usa mismo cert que admirald o uno propio)
cp admirald.pem flagship.pem
cp admirald-key.pem flagship-key.pem

# Wildcard local para Caddy (modo Producción)
openssl genrsa -out caddy-local-key.pem 2048
openssl req -new -key caddy-local-key.pem \
  -out caddy-local.csr \
  -subj "/C=US/ST=Test/O=Admiral/CN=*.apps.qa.admiral.test"
openssl x509 -req -in caddy-local.csr \
  -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out caddy-local.pem -days 365 \
  -extfile <(printf "subjectAltName=DNS:*.apps.qa.admiral.test,DNS:apps.qa.admiral.test")

chmod 644 /etc/admiral/tls/*.pem
openssl verify -CAfile ca.pem admirald.pem fleet.pem flagship.pem
```

## 6. Configurar PostgreSQL

Admiral usa tres bases de datos: `admiral` (estado global de admirald),
`admiral_queue` (cola de tareas de fleet) y `admiral_harbor` (portal de clientes).

```bash
postgresql-setup --initdb
systemctl enable --now postgresql

su - postgres -c "psql -c \"CREATE USER admiral WITH PASSWORD 'changeme';\""
for db in admiral admiral_queue admiral_harbor; do
  su - postgres -c "psql -c \"CREATE DATABASE $db OWNER admiral;\""
  su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $db TO admiral;\""
done

sed -i 's/^host    all             all             127.0.0.1\/32            ident$/host    all             all             127.0.0.1\/32            scram-sha-256/' /var/lib/pgsql/data/pg_hba.conf
systemctl restart postgresql

for db in admiral admiral_queue admiral_harbor; do
  PGPASSWORD=changeme psql -h 127.0.0.1 -U admiral -d "$db" -c "SELECT 1 AS ok"
done
```

## 7. Configurar Caddy (solo producción)

En modo QA no se necesita Caddy — los componentes flagship y harbor exponen HTTPS
directo. En producción Caddy actúa como reverse proxy TLS.

```bash
cat > /etc/caddy/Caddyfile << 'EOF'
{
	admin 127.0.0.1:2019
}
EOF

systemctl enable --now caddy
sleep 2
curl -s http://127.0.0.1:2019/config/ | python3 -m json.tool | head -5
```

## 8. Instalar los RPMs

### 8.1 Instalación estándar (desde COPR)

```bash
dnf install -y admiral-common admirald admiral-fleet admiralctl \
  admiral-flagship admiral-harbor

rpm -q admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor
```

### 8.2 Instalación local (solo si compilaste RPMs en el Paso 4)

```bash
dnf install -y /root/admiral/packaging/build/RPMS/noarch/python3-*-*.rpm 2>/dev/null || true
dnf install -y \
  /root/admiral/packaging/build/RPMS/noarch/admiral-common-*.rpm \
  /root/admiral/packaging/build/RPMS/x86_64/admirald-*.rpm \
  /root/admiral/packaging/build/RPMS/x86_64/admiral-fleet-*.rpm \
  /root/admiral/packaging/build/RPMS/x86_64/admiralctl-*.rpm \
  /root/admiral/packaging/build/RPMS/noarch/admiral-flagship-*.rpm \
  /root/admiral/packaging/build/RPMS/noarch/admiral-harbor-*.rpm

rpm -q admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor
```



## 9. Configurar admirald

### Modo QA (sin DNS, TLS interno)

```bash
cat > /etc/admirald.ini << 'EOF'
port=8080
listen_address=127.0.0.1
database_url=postgres://admiral:changeme@127.0.0.1:5432/admiral?sslmode=disable
queue_database_url=postgres://admiral:changeme@127.0.0.1:5432/admiral_queue?sslmode=disable
shared_token=changeme-shared-token
secrets_key=changeme-secrets-key
flagship_admin_user=admin
flagship_admin_pswd=changeme-admin-password

tls_cert_file=/etc/admiral/tls/admirald.pem
tls_key_file=/etc/admiral/tls/admirald-key.pem

networking_base_domain=qa.admiral.test
networking_tls_provider=internal
networking_tls_cert_file=/etc/admiral/tls/caddy-local.pem
networking_tls_key_file=/etc/admiral/tls/caddy-local-key.pem
caddy_admin_url=http://127.0.0.1:2019
EOF
```

### Modo Producción (DNS público, Let's Encrypt)

```bash
# Obtener wildcard DNS-01
dnf install -y certbot
certbot certonly --manual --preferred-challenges dns \
  -d "*.apps.<DOMAIN>" -d "apps.<DOMAIN>"

# Permitir a Caddy leer el certificado
chgrp caddy /etc/letsencrypt/live/apps.<DOMAIN>/fullchain.pem \
  /etc/letsencrypt/live/apps.<DOMAIN>/privkey.pem
chmod 640 /etc/letsencrypt/live/apps.<DOMAIN>/fullchain.pem \
  /etc/letsencrypt/live/apps.<DOMAIN>/privkey.pem

cat > /etc/admirald.ini << 'EOF'
port=8080
listen_address=127.0.0.1
database_url=postgres://admiral:changeme@127.0.0.1:5432/admiral?sslmode=disable
queue_database_url=postgres://admiral:changeme@127.0.0.1:5432/admiral_queue?sslmode=disable
shared_token=changeme-shared-token
secrets_key=changeme-secrets-key
flagship_admin_user=admin
flagship_admin_pswd=changeme-admin-password

tls_cert_file=/etc/admiral/tls/admirald.pem
tls_key_file=/etc/admiral/tls/admirald-key.pem

networking_base_domain=<DOMAIN>
networking_tls_provider=letsencrypt
networking_tls_email=ops@<DOMAIN>
networking_tls_cert_file=/etc/letsencrypt/live/apps.<DOMAIN>/fullchain.pem
networking_tls_key_file=/etc/letsencrypt/live/apps.<DOMAIN>/privkey.pem
caddy_admin_url=http://127.0.0.1:2019
EOF
```

## 10. Configurar fleet

```bash
cat > /etc/admiral/fleet.env << 'EOF'
ADMIRAL_FLEET_NODE_ID=node_001
ADMIRAL_SHARED_TOKEN=changeme-shared-token
ADMIRAL_API_URL=https://127.0.0.1:8080
ADMIRAL_API_CA_FILE=/etc/admiral/tls/ca.pem
ADMIRAL_QUEUE_DATABASE_URL=postgres://admiral:changeme@127.0.0.1:5432/admiral_queue?sslmode=disable
ADMIRAL_FLEET_EXECUTOR=systemd-podman
ADMIRAL_FLEET_DATA_DIR=/var/lib/admiral
ADMIRAL_FLEET_CALLBACK_OUTBOX=/var/lib/admiral/outbox
ADMIRAL_FLEET_HTTP_ADDR=127.0.0.1:9099
ADMIRAL_FLEET_ROOTLESS_USER=admiral-apps
EOF
```

## 11. Configurar admiralctl

Fuente: `admiralctl/internal/config/config.go`

```bash
mkdir -p ~/.config/admiralctl
cat > ~/.config/admiralctl/config.yaml << 'EOF'
server_url: https://127.0.0.1:8080
token: changeme-shared-token
ca_cert_file: /etc/admiral/tls/ca.pem
operator: admin
EOF
```

Los valores también pueden definirse via variables de entorno:
`ADMIRAL_SERVER_URL`, `ADMIRAL_SHARED_TOKEN`, `ADMIRAL_TLS_CA_FILE`, `ADMIRAL_OPERATOR`.

### 11.1 Gestión de usuarios con admiralctl

`admiralctl user` permite gestionar los usuarios administradores de admirald
(no confundir con los clientes de harbor):

```bash
# Login para obtener token de sesión (necesario para user)
admiralctl user login --username admin --password changeme-admin-password

# Listar usuarios
admiralctl user list

# Crear nuevo admin
admiralctl user create --username operator --password s3cr3t

# Cambiar contraseña
admiralctl user set-password admin
```

El primer admin se crea automáticamente al arrancar admirald con los valores
`flagship_admin_user` y `flagship_admin_pswd` de `/etc/admirald.ini`.

## 12. Configurar flagship

Las variables de entorno que `admiral-flagship` realmente lee están definidas en
`app/config.py`:

| Variable | Propósito |
|---|---|
| `ADMIRAL_API_URL` | URL base de admirald (default: `https://127.0.0.1:8080`) |
| `ADMIRAL_SHARED_TOKEN` | Token compartido con admirald (requerido en producción) |
| `ADMIRAL_CA_FILE` | Ruta al CA PEM para verificar TLS de admirald |
| `FLAGSHIP_SECRET_KEY` | Secret key de Flask (requerido en producción) |
| `FLAGSHIP_SESSION_COOKIE_SECURE` | Cookie HTTPS-only (default: `true`) |
| `FLAGSHIP_SESSION_TIMEOUT_MINUTES` | Timeout de sesión (default: `30`) |

```bash
cat > /etc/admiral/flagship.env << 'EOF'
FLAGSHIP_SECRET_KEY=changeme-flagship-secret
ADMIRAL_API_URL=https://127.0.0.1:8080
ADMIRAL_SHARED_TOKEN=changeme-shared-token
ADMIRAL_CA_FILE=/etc/admiral/tls/ca.pem
EOF
```

> El paquete RPM instala `/etc/admiral/flagship.env` con valores por defecto
> seguros para desarrollo y QA. Antes de poner el sistema en producción,
> sustituye `FLAGSHIP_SECRET_KEY` y `ADMIRAL_SHARED_TOKEN` por valores reales
> generados para tu instalación. El arranque también emite un warning claro si
> detecta los defaults de desarrollo.

## 13. Configurar admiral-harbor

Las variables de entorno que `admiral-harbor` realmente lee están definidas en
`app/config.py`.

### 13.1 Conexión con admirald

`admiral-harbor` se comunica con `admirald` mediante su API REST. Necesita:

| Variable | Propósito | Default |
|---|---|---|
| `ADMIRAL_API_URL` | URL base del API de admirald | `https://127.0.0.1:8443` |
| `ADMIRAL_SHARED_TOKEN` | Token compartido para autenticación | `dev-token` |
| `ADMIRAL_CA_FILE` | Ruta al CA bundle para verificar el certificado TLS de admirald | _(vacío, usa system CA)_ |
| `ADMIRAL_INSECURE_SKIP_VERIFY` | Omitir verificación TLS (solo QA) | `0` |

En **QA** (certificado autofirmado), usar `ADMIRAL_INSECURE_SKIP_VERIFY=1`.
En **producción**, configurar `ADMIRAL_CA_FILE` apuntando al CA que firmó el certificado de admirald.
Cuando alguno de los secretos o tokens siga con el valor por defecto, Harbor
lo registra como warning al arrancar. Eso no sustituye la revisión manual: en
producción deben reemplazarse `HARBOR_SECRET_KEY`, `HARBOR_ENCRYPTION_KEY` y
`ADMIRAL_SHARED_TOKEN`.

### 13.2 Archivo de entorno compartido

El paquete RPM instala `/etc/admiral/harbor.env` y tanto `admiral-harbor.service`
como `harborctl` lo leen automáticamente. Ese archivo trae valores de ejemplo
para desarrollo y QA; en producción debes editarlo antes de arrancar el servicio.

```bash
sed -n '1,200p' /etc/admiral/harbor.env
chmod 640 /etc/admiral/harbor.env
chown root:admiral /etc/admiral/harbor.env
```

Valores que debes revisar antes de producción:

| Variable | Propósito |
|---|---|
| `HARBOR_DATABASE_URL` | Base de datos de Harbor |
| `HARBOR_SECRET_KEY` | Secret key de Flask |
| `HARBOR_ENCRYPTION_KEY` | Clave de cifrado de datos sensibles |
| `ADMIRAL_SHARED_TOKEN` | Token compartido con admirald |
| `ADMIRAL_CA_FILE` | CA para verificar TLS de admirald |
| `ADMIRAL_INSECURE_SKIP_VERIFY` | Solo para QA; dejar en `0` en producción |

> Nota operativa: el branding white-label del portal y las tasas fiscales ya no
> se configuran por variables de entorno. Se administran desde la base de datos
> a través del panel de Harbor, donde el administrador puede subir logo y
> favicon, y editar el nombre, la descripción y los tax rates del portal.

### 13.3 harborctl

El CLI `harborctl` carga automáticamente `/etc/admiral/harbor.env` al iniciar,
por lo que usa la misma configuración que el servicio systemd. Ejemplo:

```bash
harborctl user list
harborctl user create --type customer --display-name "Cliente" --country NI cliente@example.com
```

Si se requiere una contraseña no interactiva, usar la variable de entorno
`ADMIRAL_HARBOR_SET_PASSWORD`.

Ejemplo completo de setup de usuarios:

```bash
# Crear admin de harbor
ADMIRAL_HARBOR_SET_PASSWORD=admin123 harborctl user create \
  --type admin --display-name "Admin User" admin

# Crear cliente de prueba
ADMIRAL_HARBOR_SET_PASSWORD=customer123 harborctl user create \
  --type customer --display-name "Cliente Demo" --country US demo@example.com

# Listar todos los usuarios
harborctl user list
```

> Por defecto, harbor crea automáticamente el admin `admin`/`secret` en el
> primer arranque si no existe ningún administrador en la base de datos.

> Nota: tanto `admiral-flagship` como `admiral-harbor` usan gunicorn con
> `--bind 0.0.0.0:5000` y `--bind 0.0.0.0:5001` respectivamente, sirviendo
> directamente HTTPS con el certificado `/etc/admiral/tls/admirald.pem`.
> No necesitan override en modo QA. En producción, se recomienda que Caddy
> reverse-proxée en lugar de exponer gunicorn directamente.

> Importante: el empaquetado es genérico. Los valores por defecto son solo
> placeholders de instalación. Cada sysadmin debe sustituirlos por secretos,
> URLs y credenciales apropiadas para su entorno antes de habilitar producción.

## 14. Arrancar servicios

```bash
# Restaurar contextos SELinux
restorecon -F /usr/bin/admirald /usr/bin/admiral-fleet /usr/bin/admiralctl 2>/dev/null || :
restorecon -R /etc/admiral 2>/dev/null || :

# Arrancar en orden
systemctl enable --now admirald
sleep 3
systemctl enable --now admiral-fleet
sleep 3
systemctl enable --now admiral-flagship
sleep 3
systemctl enable --now admiral-harbor
sleep 3

# Verificar estado
systemctl status admirald admiral-fleet admiral-flagship admiral-harbor --no-pager
```

## 15. Registrar nodo y verificar salud

```bash
TOKEN=changeme-shared-token

# Registrar nodo
curl -sk -X POST -H "X-Admiral-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"node_id":"node_001","hostname":"'$(hostname)'","ip":"127.0.0.1","os":"CentOS Stream 10","podman_v":"5.8"}' \
  https://127.0.0.1:8080/api/v1/nodes

# Esperar heartbeat
sleep 15

# Verificar
curl -sk -H "X-Admiral-Token: $TOKEN" \
  https://127.0.0.1:8080/api/v1/nodes | python3 -m json.tool
```

### Salud esperada

```bash
curl -sk https://127.0.0.1:8080/api/v1/health
# {"status":"healthy"}

curl -s http://127.0.0.1:9099/health
# {"node_id":"node_001","status":"healthy",...}

admiralctl status
admiralctl nodes list
```

## 16. Verificar consolas web

Cada componente sirve directamente HTTPS en `0.0.0.0`:

| Servicio | Puerto | URL (QA) |
|---|---|---|
| admirald (API) | 8080 | `https://127.0.0.1:8080/` (solo loopback) |
| admirald (API health) | 8080 | `https://127.0.0.1:8080/api/v1/health` |
| admiral-flagship (admin UI) | 5000 | `https://<IP_PUBLICA>:5000/` |
| admiral-harbor (customer portal) | 5001 | `https://<IP_PUBLICA>:5001/` |
| admiral-fleet (health) | 9099 | `http://127.0.0.1:9099/health` (solo loopback) |
| Caddy (admin API) | 2019 | `http://127.0.0.1:2019/config/` |

```bash
# Flagship (admin console)
curl -sk https://0.0.0.0:5000/ | head -5

# Harbor (customer portal)
curl -sk https://0.0.0.0:5001/ | head -5
```

## Diagnóstico rápido

| Componente | Comando de verificación |
|---|---|
| PostgreSQL | `systemctl status postgresql` |
| Caddy | `curl -s http://127.0.0.1:2019/config/` |
| admirald | `curl -sk https://127.0.0.1:8080/api/v1/health` |
| admiral-fleet | `curl -s http://127.0.0.1:9099/health` |
| admiral-flagship | `curl -sk https://127.0.0.1:5000/` |
| admiralctl | `admiralctl status` |
| admiralctl users | `admiralctl user login --username admin --password ...` |
| harborctl | `harborctl user list` |
| admiral-harbor | `curl -sk https://127.0.0.1:5001/ \| head -5` |
| Logs admirald | `journalctl -u admirald --no-pager -n 50` |
| Logs fleet | `journalctl -u admiral-fleet --no-pager -n 50` |
| Logs flagship | `journalctl -u admiral-flagship --no-pager -n 50` |
| Logs harbor | `journalctl -u admiral-harbor --no-pager -n 50` |

---

## Siguientes pasos

Una vez verificado el setup base, continuar con el ciclo de vida de apps:

1. Cargar app definitions desde `examples/apps/`
2. Provisionar instancias
3. Probar pause/resume/backup/restore/deprovision

Ver `docs/rpm_e2e_validation_guide.md` para la validación E2E completa.
