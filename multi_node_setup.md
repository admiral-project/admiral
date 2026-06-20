# Sesión Multi-Nodo — 2026-06-19

## Resumen

Instalación y configuración de Admiral en modo multi-nodo con 3 VPS:
- **Admin**: (CentOS Stream, AlmaLinux 9)
- **Worker**: (AlmaLinux 9)
- **Portal**: (AlmaLinux 9)

## Commits realizados

```
56dfe8e fix(ansible): generate unique random token per node on registration
e2fafc7 docs: update session log with node_tokens table analysis and fixes
f5fbaaa fix(inventory): fleet uses bare hostname as node_id in single-node
5cd0374 fix(inventory): use hostname-portal node_id for harbor in single-node
6e6b5b0 fix(inventory): register harbor before fleet in single-node
28631e1 docs: update session log with harbor-before-fleet fix and node cleanup
4885aa3 fix(ansible): pass fleet token when registering portal node in single-node
```

**Submodule admirald** (`89cceb4`):
```
89cceb4 feat(db): add node_tokens table with composite key (node_id, token_type)
```
65891a1 fix(ansible): reload systemd daemon after installing firewalld package
deca742 fix: use ansible_hostname for harbor node_id and set /var/lib/admiral ownership to admiral
d31205f build: update submodule commit macros in SPEC files to match HEAD
4c774a7 fix(db): filter cancelled instances when counting active instances per node
eb2fdb9 docs: update known limitations with multi-node validation scope
54d2020 docs: update multi-node session log with portal installation and instance validation
28844d1 fix(ansible): skip WireGuard config deploy if already exists
a09831b docs: rename alpha_known_limitations to beta_known_limitations
067b517 fix(install): auto-generate node-id for worker and portal spoke nodes
f2330d2 fix(install): read node ID from harbor.env for portal nodes
9c5f85c build(makefile): bump VERSION to 0.0.1beta4
0d4bf0e build(packaging): bump all specs to 0.0.1beta4, release 2
9432f9b fix(install): pass admiral_wireguard_ip for admin/single node installs
a71b17b build(packaging): bump admirald to release 2 with fixed systemd unit
5adf739 fix(packaging): remove hardcoded ADMIRAL_LISTEN_ADDRESS from systemd unit
a4680ee fix(ansible): use sudo -u postgres for all psql tasks
```

## Bitácora

### Drops anteriores eliminados
- worker-001 (68.183.139.102) — destruido
- portal-002 (157.230.9.254) — destruido

### Nuevos droplets
- Worker (AlmaLinux 9)
- Portal (AlmaLinux 9)

### Admin VPS — install.sh --admin-node
- `dnf update` desde COPR
- WireGuard y know_host limpiados
- `install.sh --admin-node` completado exitosamente

### Worker node — install.sh --worker-node
- Worker registrado exitosamente
- Nodo `worker-001` — active/healthy/available

### Problemas encontrados y resueltos

#### 1. `ADMIRAL_LISTEN_ADDRESS=127.0.0.1` en systemd unit
- El systemd unit hardcodeaba `Environment=ADMIRAL_LISTEN_ADDRESS=127.0.0.1`
- La variable de entorno sobreescribía el INI config
- **Fix**: eliminado del unit en `packaging/systemd/admirald.service`
- **Verificado**: RPM rebuilt e instalado, admirald escuchando en `*:8080`

#### 2. Certificado TLS sin SAN para WireGuard IP
- **Fix**: `install.sh` ahora pasa `admiral_wireguard_ip=10.99.0.1` para admin/single mode

#### 3. Persistencia de peers WireGuard
- El playbook sobreescribe `wg-admiral.conf` al re-ejecutar install.sh
- Peers previos se perdían
- **Fix**: task ahora es conditional — solo deploya si el archivo no existe
- **Verificado**: WireGuard peers persisten al re-ejecutar install.sh

#### 4. Portal: node ID en harbor.env
- install.sh buscaba `ADMIRAL_FLEET_NODE_ID` en `fleet.env`
- Portal usa `harbor.env` que no tiene esa variable
- **Fix**: `grep -E 'ADMIRAL_FLEET_NODE_ID|HARBOR_NODE_ID' /etc/admiral/*.env`
- **Verificado**: portal-001 registrado correctamente

#### 5. Portal: auto-generate node-id
- No se pasaba `--node-id` al ejecutar `--portal-node`
- **Fix**: auto-genera `portal-001` / `worker-001` si no se especifica
- **Verificado**: portal-001 y worker-001 generados y usados correctamente

#### 6. Firewalld daemon reload en fresh installs
- En droplets frescos de DigitalOcean, firewalld no viene instalado
- Cuando package lo instala, systemd no había recargado sus unidades
- `firewall-cmd --set-default-zone=public` fallaba con "FirewallD is not running"
- **Fix**: `daemon_reload: true` en la task de servicio de firewalld
- **Verificado**: install.sh --single-node completa sin errores

#### 7. /var/lib/admiral permissions
- El directorio era owned por root:admiral con permisos 0751
- admirald necesita escribir `know_host.yaml` — fallaba con "permission denied"
- **Fix**: SPEC ahora declara `/var/lib/admiral` como `admiral:admiral 0751`
- **Verificado**: RPM rebuild e instalado, admirald escribe sin errores

#### 8. Harbor node_id usaba inventory_hostname
- En single-node (delegate_to: localhost), inventory_hostname = "localhost"
- Fleet usa `ansible_hostname` — daba hostname real
- Resultado: doble registro con node_ids distintos
- **Fix**: harbor ahora usa `ansible_hostname` como fallback (igual que fleet)
- **Nota**: doble registro en single-node (worker + portal) es comportamiento correcto

#### 9. Harbor sin --token causaba HTTP 401 en fleet heartbeat
- En single-node, harbor registra sin `--token` — admirald genera nuevo token
- Este nuevo token sobreescribe el de fleet en la DB
- Fleet hace heartbeat con su token guardado → no coincide → 401
- **Fix**: harbor ahora pasa `--token {{ admiral_fleet_token_value }}`
- **Pendiente**: re-testar en 159.223.165.61 después del fix

### Limpieza y rebuild de specs

Todos los specs actualizados a 0.0.1beta4, Release 2.
admiral-common rebuild a Release 4 con fix de permisos.

RPMs construidos (0.0.1beta4-2):
- admirald, admiral-fleet, admiralctl, admiral-flagship, admiral-harbor

RPMs construidos (0.0.1beta4-4):
- admiral-common

## Validación Single-Node (67.205.167.193)

**Test**: `install.sh --single-node` en droplet limpio CentOS Stream 10
**Swap**: 8GB swap creado para evitar OOM
**Resultado**: ✓ ÉXITO — instalación completa

- Todos los servicios activos: admirald, admiral-fleet, admiral-flagship, admiral-harbor, caddy, postgresql
- WireGuard hub corriendo en puerto 51820
- Nodo worker y portal registrados (comportamiento correcto en single-node)
- Permisos de /var/lib/admiral corregidos

**Issues encontrados y resueltos durante instalación**:
- firewalld no estaba corriendo — fix en Ansible
- permisos de /var/lib/admiral — fix en SPEC

## Validación Single-Node (159.223.165.61 — Rocky Linux 9)

**Test**: `install.sh --single-node` en droplet limpio Rocky Linux 9
**Swap**: 8GB swap creado para evitar OOM
**admiral-common**: release 4 con fixes de permisos
**Resultado**: ✓ Instalación completa — 0 failed

- Todos los servicios activos
- Nodo único registrado con hostname real (fix de inventory_hostname funcionó)
- **Issue descubierto**: fleet heartbeat falla con HTTP 401
  - Causa: harbor registra sin `--token`, admirald genera nuevo token que sobreescribe el de fleet
  - **Fix**: pasar `--token {{ admiral_fleet_token_value }}` en harbor (commit 4885aa3)

## Validación Rootless Remote

**Test**: Provisionar app e2e-whoami en worker remoto
**Resultado**: ✓ ÉXITO

- Task llegó del admin al fleet agent en worker
- Fleet ejecutó como `admiral-apps` (uid=1001, no root)
- Containers corriendo rootless sin privilegios
- Podman rootless funciona en ejecución remota

```
$ su - admiral-apps -c "podman ps"
CONTAINER ID  IMAGE                       STATUS      PORTS
72858efd3578  admiral-inst_..._infra    Up 1 min    0.0.0.0:40000->80/tcp
a964b66df312  docker.io/traefik/whoami  Up 1 min    0.0.0.0:40000->80/tcp
```

## Estado actual

### Admin VPS (165.22.178.97)
- admirald — active (v0.0.1beta4-3)
- WireGuard hub — corriendo con peers de worker y portal
- worker-001 — active/healthy/available

### Worker VPS (142.93.251.187)
- admiral-fleet — active/running (v0.0.1beta4-2)
- e2e-whoami instance `inst_a0d9fe7e113fc431` — running rootless

### Portal VPS (134.122.17.193)
- admiral-harbor — active/running (v0.0.1beta4-2)
- Nodo registrado como `portal-001` — reachable
- Health status: `unhealthy` con razón `fleet_offline` (esperado — portal no corre fleet agent)

### Single-Node VPS (67.205.167.193)
- admirald, admiral-fleet, admiral-flagship, admiral-harbor — todos active
- WireGuard hub — active
- Nodo worker y portal registrados (correcto en single-node)
- Permisos de /var/lib/admiral — corregidos

## Sesión 2026-06-19 (continuación)

### Fix de token en single-node — solución de tabla separada

**Problema root cause**: En single-node, harbor y fleet corren en el mismo host físico y comparten el mismo `node_id` (hostname). Ambos usan `UpsertNodeToken` que writea en la misma row de `nodes`. La última escritura gana — siempre sobreescribía el token anterior.

El `TokenType` importa: `NodeAuthMiddleware` exige `token_type == "worker"` para heartbeat. Si harbor writea último con `token_type=portal`, fleet recibe 401.

**Intentos previos**:
1. Pass `--token` en harbor para que use el fleet token — no funciona porque `UpsertNodeToken` sobreescribe todos los campos incluyendo `token_type`
2. Invertir orden de registro (harbor → fleet) — no funciona porque ambos usan el mismo `node_id` y hay solo una row

**Solución definitiva**: tabla `node_tokens` separada con clave compuesta `(node_id, token_type)`.

```
Commit: 89cceb4 feat(db): add node_tokens table with composite key (node_id, token_type)
```

**Cambios en admirald**:
- Migration 11: crea tabla `node_tokens (node_id, token_type, token_identifier, token_hash, token_status, token_value_encrypted, token_expires_at, claim_id)` con PK compuesta
- `UpsertNodeToken`: ahora writea en `node_tokens` con `ON CONFLICT (node_id, token_type) DO UPDATE`
- `GetNodeTokenByIdentifier`: JOIN entre `nodes` y `node_tokens` para auth — retorna el `token_type` del token row, no del node
- `NodeAuthMiddleware`: usa `nodeToken.TokenType` del token row para verificar `expectedTokenType`
- `ReapExpiredNodeTokens`: DELETE de `node_tokens` en vez de `nodes`
- `RemoveNode`: DELETE de `node_tokens` antes de `nodes`

**Por qué funciona**: fleet y harbor escriben en la misma tabla `node_tokens` pero con `token_type` diferente. Cada uno tiene su propia row con PK `(node_id, token_type)`. No hay colisión.

### Fix de orden de roles en site.yml

Complementario al fix de DB, se invierte el orden de roles en `ansible/site.yml`:

```
Commit: 6e6b5b0 fix(inventory): register harbor before fleet in single-node
Commit: 5cd0374 fix(inventory): use hostname-portal node_id for harbor in single-node
Commit: f5fbaaa fix(inventory): fleet uses bare hostname as node_id in single-node
```

- Antes: fleet → flagship → harbor
- Después: harbor → flagship → fleet
- Harbor usa `{hostname}-portal` como node_id en single-node
- Fleet usa `{hostname}` (bare) como node_id en single-node

### Limpieza del nodo admin para re-test single-node

Este nodo (165.22.178.97) tenía una instalación multi-nodo anterior con worker-001 y una instancia e2e-whoami. Para probar single-node limpio:

- Instancia `inst_a0d9fe7e113fc431` puesta en deprovisioning (nodo offline, no completaba)
- Paquetes Admiral removidos: `admiralctl`, `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, `admiral-common`
- Directorios eliminados: `/etc/admiral`, `/var/lib/admiral`, `/var/log/admiral`
- PostgreSQL data removido: `/var/lib/pgsql/data`
- Firewalld: puertos 51820/udp y 9999/tcp removidos
- Sistema limpio para re-instalación single-node

## Validación 2026-06-19 (confirmada)

**Host**: 165.22.178.97 (CentOS Stream 10) — mismo nodo admin convertido a single-node

### Procedimiento
1. Limpieza completa: paquetes removidos, datos borrados, firewall limpio
2. Instalación `--single-node` con playbook actual (sin los fixes de orden)
3. Rebuild de admirald RPM con commit `89cceb4` (node_tokens table)
4. Re-install RPM sobre instalación existente
5. Restart admirald — migration 11 creó `node_tokens` y migró token de portal
6. Re-registro manual de fleet para crear token worker en `node_tokens`

### Resultado
- **confirmado**: fleet authenticates with `token_type=worker` from `node_tokens` — no more HTTP 401
- **confirmado**: node `centos-s-2vcpu-2gb-90gb-intel-nyc1` status=active, health=healthy, available=true
- **confirmado**: `node_tokens` tiene 2 rows — `portal` (available) y `worker` (active)
- **confirmado**: admiral-fleet service running, fetched task encryption key successfully
- **confirmado**: admiral-harbor service running (desde instalación anterior)

### Arquitectura de tokens (validada)
```
nodes:
  id=centos-s-2vcpu-2gb-90gb-intel-nyc1 (bare hostname — único para el host)
  node_role=worker (último en registrarse)

node_tokens:
  (centos-s-2vcpu-2gb-90gb-intel-nyc1, portal)   → token de harbor
  (centos-s-2vcpu-2gb-90gb-intel-nyc1, worker)   → token de fleet
```

### Nota sobre re-registro manual
El playbook actual (sin re-run) usa el mismo node_id para fleet y harbor en single-node. El fix de DB permite que ambos convivan con tokens separados en `node_tokens`. No fue necesario re-run del playbook para validar el fix — el re-registro manual de fleet fue suficiente.

En un deploy limpio con el playbook actualizado (orden + hostname-portal suffix), harbor tendría su propio node_id `{hostname}-portal` y no compartiría el nodo.

## Fix de token único por nodo — multi-node

**Problema**: Worker nodes en multi-node fallaban con:
```
pq: duplicate key value violates unique constraint "node_tokens_token_identifier_key"
```

**Root cause**: Todos los workers usaban `admiral_fleet_token_value` (el token compartido del inventario). Cada worker generaba el mismo `token_identifier = SHA256(raw_token + pepper)` → violaba el UNIQUE constraint en `node_tokens.token_identifier`.

**Solución**: Cada nodo genera un token aleatorio único en tiempo de registro:
```bash
openssl rand -hex 32
```

**Cambios en ansible** (solo, sin cambios en admirald):

`ansible/roles/admiral_fleet/tasks/main.yml`:
- Nueva task: `Generate random fleet node token` — `set_fact: fleet_node_token_value`
- `fleet.env` usa `{{ fleet_node_token_value }}` en vez de `{{ admiral_fleet_token_value }}`
- `--token` en registro usa `{{ fleet_node_token_value }}`

`ansible/roles/admiral_harbor/tasks/main.yml`:
- Nueva task: `Generate random harbor node token` — `set_fact: harbor_node_token_value`
- `--token` en registro usa `{{ harbor_node_token_value }}`

**Por qué funciona**: Cada nodo tiene un token raw diferente → SHA256 diferente → `token_identifier` único → UNIQUE constraint satisfecha.

**Pendiente**: Re-test de instalación multi-node en workers 137.184.142.125 y 134.209.219.244 con el playbook actualizado.

## Pendientes
- [ ] Re-test multi-node worker installation en 137.184.142.125 y 134.209.219.244
- [ ] Validar acceso a Harbor UI desde browser
- [ ] Deploy WordPress u otra app oficial en single-node
- [ ] Failure testing automatizado
- [ ] Validación multi-node E2E automatizada
