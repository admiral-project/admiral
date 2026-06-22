# Admiral Networking v1

Status: Implemented for alpha release  
Scope: `admirald`, `admiral-fleet`, `admiralctl`, `admiral-flagship`, `admiral-harbor`  
Contract version: `networking_v1`

---

## 1. Architecture overview

Admiral soporta tanto configuraciones de nodo único (single-node) como multinodo (multi-node). La arquitectura multinodo utiliza WireGuard como red privada para toda la comunicación entre nodos y tráfico interno. Los puertos de servicios internos no se exponen a Internet.

Superficie pública soportada por defecto:

- `22/tcp` en todos los nodos para SSH
- `80/tcp` y `443/tcp` en `--single-node` y `--admin-node`, terminados por Caddy
- `51820/udp` en todos los nodos para WireGuard

Puertos internos no soportados como edge público:

- `8080/tcp` `admirald`
- `9099/tcp` `admiral-fleet`
- `5000/tcp` `admiral-flagship`
- `5001/tcp` `admiral-harbor` directo
- `5432/tcp` PostgreSQL
- `2019/tcp` Caddy Admin API

`admiral-harbor` es el único servicio HTTP orientado al cliente, pero debe publicarse detrás de Caddy. `admirald` y `admiral-flagship` tienen autenticación y controles de sesión, pero siguen siendo servicios de plano de control y no un edge público soportado.

### 1.1 Diagrama de Red (Multinodo)

```
Internet
    |
    v
DNS: *.apps.cloud.domain.com  -->  IP Pública (Control Plane)
    |
    v
+-------------------------------------------------------+
| Control Plane (wg0: 10.99.0.1)                        |
|                                                       |
| Caddy (Ingress, TLS Termination)                      |
| admirald (Control Plane API)                          |
| flagship (Admin UI)                                   |
+-------------------------------------------------------+
          |
          | Canal B: WireGuard VPN (Red de Workloads)
          |
    +-----+--------------------------+
    |                                |
+----------------------------+  +----------------------------+
| Worker 1 (wg0: 10.99.0.2)  |  | Worker 2 (wg0: 10.99.0.3)  |
|                            |  |                            |
| admiral-fleet (Agent)      |  | admiral-fleet (Agent)      |
| Podman Rootless (Workloads)|  | Podman Rootless (Workloads)|
+----------------------------+  +----------------------------+

Canal A: SSH + Ansible (Solo Administración / Bootstrap)
```

Componentes:

- `admirald` es la fuente de verdad. Posee la persistencia (`PublicRoute` en DB) y orquesta la configuración de Caddy vía su Admin API. En multinodo, se comunica con los agentes `admiral-fleet` a través de sus IPs de WireGuard.
- `Caddy` es el plano de ejecución del reverse proxy. Sirve el tráfico público y termina TLS en la entrada expuesta; los servicios internos siguen accesibles solo por la red privada.
- `admiral-fleet` reporta los endpoints internos (host_port) donde cada servicio publicado escucha.
- `admiralctl` permite inspeccionar y operar rutas desde CLI.

---

## 2. Dual-Channel Networking

Admiral utiliza una arquitectura de red de dos canales para separar las operaciones de control del tráfico de las aplicaciones.

### Canal A: Configuración y Plano de Control

- **Transporte:** SSH
- **Herramienta:** Ansible
- **Propósito:** Bootstrap de nodos, instalación de RPMs, actualizaciones, diagnósticos y administración remota.
- **Autenticación:** Preferentemente mediante llaves SSH (pública/privada).
- **Alcance:** Este canal es puramente administrativo y **no** se utiliza para el tráfico de los workloads.

### Canal B: Red de Workloads

- **Transporte:** WireGuard VPN
- **Propósito:** Tráfico del reverse proxy Caddy hacia los servicios internos, llamadas a la API de `admirald` hacia `fleet`, heartbeats, comunicación del runtime, y transferencia de backups.
- **Topología:** Star (estrella), donde el Control Plane es el hub central.
- **Privacidad:** Esta red es privada. Toda la comunicación entre componentes debe preferir las IPs de la VPN (ej. `10.99.0.x`). Los puertos de `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor` y PostgreSQL no deben exponerse al público.

---

## 3. PublicRoute entity

### 2.1 Fields

Campo | Tipo | Descripción
---|---|---
`id` | `string` | ID único, formato `route_<8_random_digits>`
`hostname` | `string` | Hostname público (FQDN)
`public_id` | `string` | ID de publicación (tipo: `instance_id` para app_instance, `route_kind` para estáticas)
`app_instance_id` | `string` | ID de la instancia de app asociada (vacío para rutas estáticas)
`app_template_code` | `string` | Código de la definición de app (`app_code`)
`node_id` | `string` | ID del nodo worker donde corre el pod (nullable para rutas estáticas)
`service_name` | `string` | Nombre del servicio publicado (e.g. `web`)
`target_scheme` | `string` | Esquema del target interno (`http`, `respond`)
`target_host` | `string` | IP interna del nodo (ej. IP de WireGuard `10.99.0.x`) o `127.0.0.1` para single-node.
`target_port` | `int` | Puerto interno del servicio
`target_url` | `string` | URL completa del target (`http://<host>:<port>` o URL de redirect para estáticas)
`route_kind` | `string` | Tipo de ruta (ver 2.2)
`tls_mode` | `string` | Modo TLS (`auto`)
`status` | `string` | Estado de la ruta (ver 2.3)
`last_error` | `string` | Último error registrado
`last_health_status` | `string` | Estado del health check (`healthy`, `unhealthy`, `disabled`, `unavailable`)
`last_health_checked_at` | `datetime` | Timestamp del último health check
`created_at` | `datetime` | Fecha de creación
`updated_at` | `datetime` | Fecha de última actualización

### 2.2 Route kinds

| Kind | Valor constante | Descripción |
|---|---|---|
| `admin` | `RouteKindAdmin` | Ruta para el panel administrativo (admiral-flagship) |
| `portal` | `RouteKindPortal` | Ruta para el portal del cliente (admiral-harbor) |
| `apps_root` | `RouteKindAppsRoot` | Ruta raíz para el dominio de apps (redirect) |
| `app_instance` | `RouteKindInstance` | Ruta para una instancia de aplicación publicada |
| `flagship` | `RouteKindFlagship` | Ruta para admiral-flagship (independiente de admin) |
| `cockpit` | `RouteKindCockpit` | Ruta para Cockpit web console |

### 2.3 Route statuses

| Status | Valor constante | Descripción |
|---|---|---|
| `pending` | `RouteStatusPending` | Ruta creada pero aún no health-checkeada |
| `active` | `RouteStatusActive` | Ruta publicada y健康 |
| `failed` | `RouteStatusFailed` | Ruta que falló health check o validación |
| `disabled` | `RouteStatusDisabled` | Ruta deshabilitada (Caddy responde 503) |
| `deleting` | `RouteStatusDeleting` | Ruta marcada para eliminación (transición) |
| `deleted` | `RouteStatusDeleted` | Ruta eliminada (registro histórico) |

### 2.4 State machine

```
pending --> active (tras health check exitoso)
pending --> failed (tras health check fallido)
active  --> disabled
active  --> deleting
active  --> failed (por error recurrente)
disabled --> active (rehabilitación)
failed  --> active (reintento exitoso)
failed  --> pending (reintento)
deleting --> deleted (tras sync y removal)
```

---

## 3. Configuration contract

Sección de networking en `/etc/admirald.ini`:

```ini
networking_base_domain=cloud.example.com
networking_admin_host=admin.cloud.example.com
networking_admin_target=https://127.0.0.1:5000
networking_portal_host=portal.cloud.example.com
networking_portal_target=
networking_apps_domain=apps.cloud.example.com
networking_apps_redirect=portal.cloud.example.com
networking_flagship_host=flagship.cloud.example.com
networking_flagship_target=https://127.0.0.1:5000
networking_cockpit_host=cockpit.cloud.example.com
networking_cockpit_target=http://127.0.0.1:9090
networking_tls_provider=letsencrypt
networking_tls_email=ops@example.com
networking_tls_cert_file=/etc/admiral/tls/wildcard.pem
networking_tls_key_file=/etc/admiral/tls/wildcard-key.pem
caddy_admin_url=http://127.0.0.1:2019
```

### 3.1 Single Node vs Multi Node

Admiral detecta automáticamente la topología basándose en la configuración de los nodos.

- **Single Node Setup:** `target_host` será típicamente `127.0.0.1`. Toda la comunicación ocurre localmente dentro del mismo host.
- **Multi Node Setup:** `target_host` utilizará la IP asignada en la red WireGuard (ej. `10.99.0.2`). Caddy en el Control Plane enrutará el tráfico a través de la interfaz `wg0`.

### 3.2 Derivation rules

Si `networking_admin_host`, `networking_portal_host`, `networking_apps_domain`, `networking_flagship_host` o `networking_cockpit_host` no están definidos, se derivan automáticamente desde `networking_base_domain`:

- `admin.<base_domain>` (opcional; no se publica por defecto en single-node)
- `portal.<base_domain>`
- `apps.<base_domain>`
- `flagship.<base_domain>`
- `cockpit.<base_domain>`

### 3.3 Target rules

- `networking_admin_target`: si está vacío, Caddy responde con placeholder estático. Si se define, hace reverse proxy hacia esa URL.
- `networking_portal_target`: default `https://127.0.0.1:5001` (admiral-harbor, ver `packaging/systemd/admiral-harbor.service`). Ese puerto es interno; no se publica directamente a Internet.
- `networking_flagship_target`: default `https://127.0.0.1:5000` (admiral-flagship, ver `packaging/systemd/admiral-flagship.service`). Ese puerto es interno; no se publica directamente a Internet.
- `networking_cockpit_target`: default `https://127.0.0.1:9090`. Ese puerto es interno; no se publica directamente a Internet.
- `networking_apps_redirect`: define la URL destino del redirect 308 desde `apps.<domain>`.

### 3.4 TLS — Wildcard certificate (MANDATORIO)

Let's Encrypt tiene un rate limit de **50 certificados por dominio por semana**.
Como cada instancia de app es un subdominio distinto de `*.apps.<domain>`,
usar certificados individuales por ruta es inviable en producción.

La solución obligatoria es un **certificado wildcard `*.apps.<domain>`**
obtenido vía **DNS-01 challenge**.

#### Flujo de instalación

```
1. Instalar backend Admiral (admirald, admiral-fleet, Caddy, etc.)
2. Ejecutar certbot DNS-01 manual:
     certbot certonly --manual --preferred-challenges dns \
       -d "*.apps.<DOMAIN>" -d "apps.<DOMAIN>"
3. Agregar registro TXT en el DNS:
     _acme-challenge.apps.<DOMAIN>  TXT  "<valor_mostrado_por_certbot>"
4. Esperar propagación, confirmar en certbot
5. Configurar en admirald:
     ADMIRAL_NETWORKING_TLS_CERT_FILE=/etc/letsencrypt/live/apps.<DOMAIN>/fullchain.pem
     ADMIRAL_NETWORKING_TLS_KEY_FILE=/etc/letsencrypt/live/apps.<DOMAIN>/privkey.pem
6. Caddy carga el wildcard desde archivo; todas las rutas
   *.apps.<domain> usan ese mismo certificado
7. Los hosts fijos `portal`, `flagship` y `cockpit` usan ACME automático
   gestionado por Caddy y no requieren wildcard manual
```

#### Reglas

- `networking_tls_provider`: default `letsencrypt`. Esquema para dev/QA. En producción el wildcard se carga desde archivo.
- `networking_tls_cert_file` / `networking_tls_key_file`: **obligatorios en producción**. Apuntan al wildcard de Let's Encrypt.
- `networking_tls_email`: requerido por ACME.
- Caddy configura ACME automation como fallback para dev. En producción, si `cert_file` y `key_file` están definidos, Caddy los carga estáticamente para `*.apps.<domain>` y sigue usando ACME automático para hosts fijos como `portal`, `flagship` y `cockpit`.
- `networking_tls_provider=internal` para QA interno con wildcard autofirmado (ver `docs/admiral-installation-guide.md`).

#### Renovación

- Certificados Let's Encrypt: 90 días.
- Admirald logea warning cuando el certificado tiene >= 85 días (faltan <= 5).
- La renovación requiere repetir el DNS-01 challenge.
- Para renovación automática sin intervención manual: instalar plugin DNS automatizado para el proveedor.

#### Rate limit

Si se usa ACME HTTP-01 por ruta (sin wildcard), al llegar a 50 certificados:

```
too many certificates (50) already issued for "example.com"
```

La única forma de evitarlo: wildcard (cuenta como 1 certificado para todas las apps).

---

## 4. Hostname generation contract

### 4.1 Format

```
<app_code><random_6_digits>.<apps_domain>
```

Ejemplos válidos:

```
wiki437198.apps.cloud.example.com
crm550219.apps.cloud.example.com
erp114927.apps.cloud.example.com
```

### 4.2 Rules

- `app_code`: debe coincidir con `^[a-z][a-z0-9-]*$`, proviene del manifiesto (`app_definition.name`).
- `random_6_digits`: exactamente 6 dígitos generados con `crypto/rand` (RNG criptográficamente seguro), no incremental, no secuencial.
- Colisiones: se reintenta hasta 20 veces. Si todas colisionan, la generación falla con error.
- El hostname generado **no debe cambiar** durante el ciclo de vida de la instancia, incluso si la app migra de nodo, cambia de tier, es pausada, restaurada o cambia de IP.

### 4.3 No permitido

```
wordpress.apps.cloud.example.com
cliente1.apps.cloud.example.com
node2wiki.apps.cloud.example.com
wiki000001.apps.cloud.example.com
```

---

## 5. CaddyAdminClient contract

### 5.1 Transport

- URL base: `http://127.0.0.1:2019` (nunca expuesta públicamente).
- Timeout HTTP: 10 segundos.
- Formato: JSON.

### 5.2 Methods

| Method | Signature | Description |
|---|---|---|
| `GetConfig` | `() -> (map, error)` | Obtiene configuración actual de Caddy (`GET /config/`) |
| `ValidateConfig` | `(cfg) -> error` | Valida configuración sin aplicarla (`POST /load`) |
| `SyncRoutes` | `(routes, cfg) -> error` | Reconcilia todas las rutas en Caddy: fusiona bootstrap, construye server config con todas las rutas, agrega servidor HTTP→HTTPS redirect, aplica vía `POST /load` |
| `ApplyRoute` | `(route, cfg) -> error` | Conveniencia: llama `SyncRoutes` con una sola ruta |
| `RemoveRoute` | `(hostname, cfg) -> error` | Elimina una ruta del siguiente sync |
| `EnableRoute` | `(route, cfg) -> error` | Cambia status a `active` y sincroniza |
| `DisableRoute` | `(route, cfg) -> error` | Cambia status a `disabled` y sincroniza |
| `Healthcheck` | `() -> error` | Verifica que Caddy Admin API responda |
| `Bootstrap` | `(cfg, email) -> error` | Inicializa Caddy con configuración mínima si está vacío: configura Admin API en `127.0.0.1:2019`, ACME automation con email, certificados TLS estáticos si existen |

### 5.3 Requirements

- **Idempotente**: `SyncRoutes` puede llamarse múltiples veces sin efectos secundarios.
- **Tolerante a fallos**: si Caddy no responde, se marca error en las rutas pero no se pierde estado.
- **No destructivo**: no debe eliminar rutas no administradas por Admiral (se fusiona con la configuración existente de Caddy).
- **Bootstrap seguro**: solo se ejecuta si la configuración actual de Caddy está vacía.

### 5.4 Caddy route structure

Para cada `PublicRoute`, se genera una ruta Caddy con:

- **Match**: `{"host": ["<hostname>"]}`
- **Handle** (según tipo):
  - `disabled` → `static_response` con HTTP 503
  - `admin`, `portal`, `flagship`, `cockpit` sin target → `static_response` con placeholder
  - `admin`, `portal`, `flagship`, `cockpit` con target → `reverse_proxy` al target
  - `apps_root` → `static_response` con HTTP 308 redirect
  - `app_instance` (default) → `reverse_proxy` al target

Además se agrega un servidor en puerto 80 que hace redirect 308 a HTTPS.

---

## 6. Reconciler contract

### 6.1 Trigger

El reconciler se ejecuta:

1. En cada `Sync()` del Manager (llamado tras crear/actualizar/eliminar rutas).
2. Periódicamente (según scheduler de admirald).

### 6.2 Logic

```
desired_state = PublicRoutes desde DB (todas excepto deleted)
actual_state = rutas en Caddy

for each desired_route:
    if not in actual_state:
        crear en Caddy
    else if modified:
        actualizar en Caddy

for each actual_route (no administrada por Admiral):
    NO eliminar (se respetan rutas externas)

routes en DB con status=deleting:
    eliminar de Caddy, luego eliminar de DB (status=deleted)

routes en DB con status=disabled:
    asegurar que Caddy responda 503

healthcheck post-sync:
    para cada ruta active/pending:
        GET https://<hostname>/
        2xx/3xx -> healthy
        otro -> unhealthy
        actualizar last_health_status, last_health_checked_at, last_error
        si pending y healthy -> active
```

---

## 7. Provisioning flow

```
1.  Validar manifest YAML (app_definition)
2.  Crear pod en nodo (vía task a admiral-fleet)
3.  admiral-fleet reporta host_ports (endpoint interno)
4.  Manager.ActivateInstanceRoutes() actualiza target_host/target_port
5.  Admirald genera hostname único (app_code + 6 random digits)
6.  Crea PublicRoute en DB con status=pending
7.  SeedStaticRoutes (si aplica) para admin/portal/apps_root
8.  Manager.Sync() reconcilia Caddy
9.  Healthcheck POST-sync:
      healthy  -> status=active
      unhealthy -> status=failed
```

### 7.1 Deprovisioning flow

```
1.  status=deleting en DB
2.  Manager.Sync() elimina ruta de Caddy
3.  Task a fleet para eliminar pod
4.  Manager.DeleteRoute() -> status=deleted en DB (o DeleteInstanceRoutes)
```

### 7.2 Node migration flow

```
1.  admiral-fleet reporta nuevo endpoint (health report con host_ports)
2.  Manager.ActivateInstanceRoutes() actualiza target_host/target_port
3.  Manager.Sync() -> Caddy actualizado
4.  Healthcheck
5.  hostname permanece igual
```

---

## 8. Health checks

### 8.1 Protocol

- Método: `GET /`
- Ruta: a través de Caddy proxy (`https://<hostname>/`)
- Transporte: dial a `127.0.0.1:443` con `ServerName` del hostname y `InsecureSkipVerify: true`
- Timeout: 10 segundos
- No sigue redirects (`ErrUseLastResponse`)

### 8.2 Resultados

| Código HTTP | Health status |
|---|---|
| 2xx o 3xx | `healthy` |
| Otro o error | `unhealthy` |

### 8.3 Rutas estáticas

Las rutas de tipo `admin`, `portal`, `apps_root`, `flagship` y `cockpit` siempre reportan `healthy` sin hacer HTTP request real, pues son placeholders controlados por admirald.

### 8.4 Registro

Por cada health check se actualizan:

- `last_health_status`
- `last_health_checked_at`
- `last_error` (si aplica)

---

## 9. API contract (admirald → consumidores)

### 9.1 Route kinds expuestos

- `admin` — panel administrativo
- `portal` — portal del cliente
- `apps_root` — dominio raíz de apps (redirect)
- `app_instance` — instancias de aplicación publicadas
- `flagship` — admiral-flagship
- `cockpit` — Cockpit web console

### 9.2 Endpoints

Rutas de administración (protegidas por `admin_token`):

| Método | Path | Handler | Descripción |
|---|---|---|---|
| `GET` | `/api/v1/routes` | `ListRoutes` | Lista todas las rutas públicas |
| `GET` | `/api/v1/routes/{hostname}` | `GetRoute` | Detalle de una ruta por hostname |
| `POST` | `/api/v1/routes/{hostname}/enable` | `EnableRoute` | Habilita una ruta |
| `POST` | `/api/v1/routes/{hostname}/disable` | `DisableRoute` | Deshabilita una ruta |
| `DELETE` | `/api/v1/routes/{hostname}` | `DeleteRoute` | Elimina una ruta |
| `POST` | `/api/v1/routes/sync` | `SyncRoutes` | Fuerza reconciliación con Caddy |
| `GET` | `/api/v1/routes/certificate` | `CertificateInfo` | Información del certificado TLS |

### 9.3 admiralctl commands

```bash
admiralctl routes list
admiralctl routes show <hostname>
admiralctl routes sync
admiralctl routes enable <hostname>
admiralctl routes disable <hostname>
```

---

## 10. Validation rules

Antes de publicar una ruta se valida:

- [ ] `hostname` único en DB
- [ ] `service_name` existe en la definición de la app
- [ ] `service.public == true`
- [ ] `node_id` existe y está activo
- [ ] endpoint interno disponible (host:port reachable)
- [ ] Caddy Admin API reachable
- [ ] `networking_apps_domain` configurado (si es app_instance)

---

## 11. Component responsibilities

### 11.1 admirald

- Persistencia de `PublicRoute` en DB (CRUD + queries por kind/hostname/instance)
- Generación de hostnames con detección de colisiones
- Cliente `CaddyAdminClient` para comunicación con Caddy Admin API
- `Manager` como orquestador: `SeedStaticRoutes`, `CreateInstanceRoutes`, `ActivateInstanceRoutes`, `Sync`, `DisableRoute`, `EnableRoute`, `DeleteRoute`, `DeleteInstanceRoutes`
- Health checks periódicos sobre rutas publicadas a través de la red WireGuard.
- API REST de rutas (`/api/v1/routes/*`)
- `CertificateInfo` y `WarnExpiringCert` para monitoreo de certificados
- Reconciler que compara DB vs Caddy y corrige diferencias

### 11.2 admiral-fleet

- Ejecutar pods con servicios publicados.
- Escuchar tareas de `admirald` a través de la red privada WireGuard.
- Reportar `host_ports` vía health report (`map[service_name]host_port`) usando la IP de la VPN.
- No exponer servicios privados (`public=false`) a redes públicas.
- Proveer health endpoint interno.

### 11.3 Ansible (Administración)

- **Official mechanism for bootstrap:** Es la herramienta oficial para la preparación de nuevos nodos.
- Tareas administrativas: Instalación de dependencias (`podman`, `wireguard-tools`), configuración de usuarios rootless, configuración de `wg0`, e instalación/actualización de `admiral-fleet`.
- Delegación de tareas: Las tareas de mantenimiento del host se delegan a Ansible vía SSH, evitando sobrecargar los agentes con lógica de nivel de sistema operativo.
- Ansible no crea ni valida los registros DNS del wildcard `*.apps.<domain>`.
- La obtención del wildcard se hace con `scripts/admiral_https_setup.py`, porque el DNS-01 challenge requiere intervención manual del operador.

### 11.3.1 `scripts/admiral_https_setup.py`

- Ejecuta el flujo interactivo de DNS-01 para obtener el wildcard de Let's Encrypt.
- Solicita al operador publicar el TXT record requerido por certbot.
- Corrige permisos de `/etc/letsencrypt` para que Caddy pueda leer el wildcard.
- Escribe el drop-in `10-https.conf` para `admirald` después de completar el challenge.
- Reinicia `cockpit.socket`, `caddy` y `admirald` para aplicar la nueva configuración.

### 11.4 admiralctl

- `routes list`: listar rutas públicas
- `routes show <hostname>`: detalle de ruta
- `routes sync`: forzar reconciliación
- `routes enable <hostname>`: habilitar ruta
- `routes disable <hostname>`: deshabilitar ruta

### 11.5 admiral-flagship

- Implementado como aplicación Python en `admiral-flagship/`.
- Corre en puerto 5000 por defecto.
- Ruta pública canónica: `flagship` con target `https://127.0.0.1:5000` por defecto.
- `admin` es opcional y no se publica por defecto en single-node.
- Se configura via `networking_flagship_target` y opcionalmente `networking_admin_target`.

### 11.6 admiral-harbor

- Implementado y funcional desde alpha.
- Portal comercial de clientes: catálogo de apps, autenticación, suscripciones, facturación, tickets de soporte, backups.
- Corre en puerto 5001 con TLS.
- Ruta `portal` servida por Caddy con target `https://127.0.0.1:5001` (configurable via `networking_portal_target`).
- Toda la configuración comercial se gestiona desde el admin UI en base de datos (sin shell).

---

## 12. Entry points

```
portal.cloud.domain.com     -> admiral-harbor (Python, puerto 5001, TLS)
apps.cloud.domain.com       -> redirect configurable (default a portal)
*.apps.cloud.domain.com     -> aplicaciones provisionadas
flagship.cloud.domain.com   -> admiral-flagship (target default :5000)
cockpit.cloud.domain.com    -> Cockpit web console (target default :9090)
```

---

## 13. DNS contract

Deben existir registros DNS:

```
A admin.cloud.domain.com       -> IP pública nodo administrativo
A portal.cloud.domain.com      -> IP pública nodo administrativo
A apps.cloud.domain.com        -> IP pública nodo administrativo
A *.apps.cloud.domain.com      -> IP pública nodo administrativo
```

Se permite `CNAME` como alternativa.

---

## 14. DNS setup example

Escenario: dominio `cloud.example.com`, VPS con IP `203.0.113.42`.

### 14.1 Registrar dominio

El dominio `cloud.example.com` debe estar registrado y sus DNS authoritative administrados (Cloudflare, AWS Route53,Namecheap, etc.).

### 14.2 Crear registros A

| Tipo | Nombre | Valor |
|------|--------|-------|
| A | `admin.cloud.example.com` | `203.0.113.42` |
| A | `portal.cloud.example.com` | `203.0.113.42` |
| A | `apps.cloud.example.com` | `203.0.113.42` |
| A | `*.apps.cloud.example.com` | `203.0.113.42` |

Se permite `CNAME`:

| Tipo | Nombre | Valor |
|------|--------|-------|
| CNAME | `admin.cloud.example.com` | `cloud.example.com` |
| CNAME | `portal.cloud.example.com` | `cloud.example.com` |
| CNAME | `apps.cloud.example.com` | `cloud.example.com` |
| CNAME | `*.apps.cloud.example.com` | `cloud.example.com` |

### 14.3 Verificar propagación

```bash
dig +short admin.cloud.example.com
dig +short portal.cloud.example.com
dig +short apps.cloud.example.com
dig +short "*.apps.cloud.example.com"
```

Todos deben resolver a `203.0.113.42`.

### 14.4 Wildcard TLS (post-instalación)

Una vez instalado Admiral y confirmados los DNS, ejecutar:

```bash
sudo admiral_https_setup --domain cloud.example.com
```

O manualmente:

```bash
certbot certonly --manual --preferred-challenges dns \
  -d "*.apps.cloud.example.com" -d "apps.cloud.example.com"
```

Agregar el registro TXT que certbot muestre:

| Tipo | Nombre | Valor |
|------|--------|-------|
| TXT | `_acme-challenge.apps.cloud.example.com` | `<valor_mostrado_por_certbot>` |

Verificar propagación antes de confirmar:

```bash
dig +short TXT _acme-challenge.apps.cloud.example.com
```

### 14.5 Renovación

Los certificados Let's Encrypt expiran a los 90 días. Admirald advierte en logs cuando faltan ≤5 días.

Renovación manual:

```bash
certbot renew --deploy-hook 'systemctl restart cockpit.socket caddy admirald'
```

Para renovación automática sin intervención: instalar plugin DNS del proveedor (e.g. `certbot-dns-cloudflare`, `certbot-dns-route53`).

### 14.6 Referencias

- `docs/development/fase4.md` — especificación original de la fase 4
- `docs/configuration-v1.md` — configuración completa de admirald
- `docs/admiral-installation-guide.md` — guía de instalación completa
- `scripts/admiral_https_setup.py` — script automatizado de post-instalación
