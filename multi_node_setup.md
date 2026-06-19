# Sesión Multi-Nodo — 2026-06-19

## Resumen

Instalación y configuración de Admiral en modo multi-nodo con 3 VPS:
- **Admin**: (CentOS Stream)
- **Worker**: (CentOS Stream 10)
- **Portal**: (CentOS Stream 10, parcial)

## Commits realizados

```
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
- Worker (CentOS Stream 10)
- Portal (CentOS Stream 10)

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
- El playbook sobreescribe `wg-admiral.conf` sin peers
- **Fix pendiente**: peers se agregan con `wg-quick save` manualmente

#### 4. Portal: node ID en harbor.env
- install.sh buscaba `ADMIRAL_FLEET_NODE_ID` en `fleet.env`
- Portal usa `harbor.env` que no tiene esa variable
- **Fix**: `grep -E 'ADMIRAL_FLEET_NODE_ID|HARBOR_NODE_ID' /etc/admiral/*.env`

#### 5. Portal: auto-generate node-id
- No se pasaba `--node-id` al ejecutar `--portal-node`
- **Fix**: auto-genera `portal-001` / `worker-001` si no se especifica

### Limpieza y rebuild de specs

Todos los specs actualizados a 0.0.1beta4, Release 2.

RPMs construidos (0.0.1beta4-2):
- admiral-common, admirald, admiral-fleet, admiralctl, admiral-flagship, admiral-harbor

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

### Admin VPS
- admirald — active (v0.0.1beta4-2, systemd unit corregido)
- WireGuard hub — corriendo con peer del worker
- worker-001 — active/healthy/available

### Worker VPS
- admiral-fleet — active/running (v0.0.1beta4-2)
- e2e-whoami instance — corriendo rootless

### Portal VPS
- admiral-harbor — installed but malfunctioning
- Nodo registrado como "target" en lugar de "portal-001"
- Peer WireGuard no agregado
- **Pendiente de arreglar**: task de Ansible usa `inventory_hostname` en lugar de `fleet_node_id`

## Pendientes
- [ ] Fix task de Ansible para usar `fleet_node_id` en registro de portal
- [ ] Persistencia de peers WireGuard en hub
- [ ] Instalar portal correctamente
- [ ] Deploy WordPress
- [ ] Regression test `--single-node`
