# Admiral Installation Guide

Guía oficial para instalar Admiral en Enterprise Linux 10.

## Alcance

Este documento cubre el flujo oficial de instalación:

1. ejecutar `admiral-install`
2. configurar HTTPS con `admiral-https-setup`
3. configurar el storage S3 de forma manual
4. respaldar `/etc/admiral/secrets` fuera del servidor

No cubre despliegues multi-node. Para eso, ver `docs/sysadmin_guide.md`.

**Nota sobre modos multi-node**: `--worker-node` y `--portal-node` son mutuamente
excluyentes por diseño. Un mismo servidor no puede ejecutar ambos roles.
Si necesita worker y portal, despliegue nodos separados.

## Plataforma soportada

- Enterprise Linux 10
- `admiral-install`
- `admiral-https-setup`
- RPMs del repositorio Admiral

## Flujo oficial

### 1. Inicializar el repositorio

```bash
cd /root/admiral
git submodule update --init --recursive
```

### 2. Instalar

En single-node:

```bash
sudo admiral-install --single-node
```

El instalador:

- instala los RPMs requeridos
- configura los servicios
- genera secretos y certificados internos
- arranca los servicios principales del modo seleccionado

En `--admin-node` y `--admin-portal-node` el instalador aplica una transacción
de paquete completa (`admiral-common`, `admirald`, `admiralctl`,
`admiral-fleet`, `admiral-harbor`, `admiral-flagship`) para mantener
playbooks y binarios en la misma versión publicada. Esta decisión es
intencional y prioriza convergencia consistente; como tradeoff, aumenta la
superficie de software instalada en el nodo admin.

La postura por defecto es:

- RHEL 10, CentOS Stream 10, Rocky Linux 10 y AlmaLinux 10 son Tier 1
- Fedora Rawhide es Tier 2 y solo se admite con `--dev-node`; sus ajustes
  inseguros de desarrollo son intencionales y están separados del perfil EL10
- `22/tcp` siempre público para administración por SSH
- `80/tcp` y `443/tcp` públicos solo en `--single-node` y `--admin-node`, servidos por Caddy
- `51820/udp` público en perfiles multi-node para WireGuard; el single-node
  seguro no ejecuta WireGuard
- ningún puerto interno de `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, PostgreSQL o la Admin API de Caddy debe exponerse directamente
- los errata de seguridad disponibles se aplican durante el playbook y
  `dnf-automatic.timer` queda habilitado para actualizaciones posteriores
- Fail2ban usa nftables nativo y la instalación comprueba que un baneo de
  prueba crea una regla efectiva

### 3. Configurar HTTPS público

`admiral-install` no configura el wildcard público ni maneja DNS.
Eso se hace manualmente después de la instalación con:

```bash
sudo admiral-https-setup --domain cloud.example.com
```

`admiral-https-setup` usa DNS-01. El operador debe publicar el TXT record que certbot solicite.

El certificado público `ca.pem` puede distribuirse para validación TLS donde sea necesario.
La clave privada `ca-key.pem` no debe salir del nodo admin.

### 4. Configurar backup storage S3

La instalación base no configura backup storage.

Después de levantar el sistema:

- configurar el backend de backup storage con `admiralctl`
- cargar las credenciales de AWS en `/etc/admiral/fleet.env` en cada nodo que ejecute `admiral-fleet`
- reiniciar `admiral-fleet` en cada nodo afectado

La configuración de storage y las credenciales no forman parte del bootstrap automático.

### 5. Respaldar secretos

`/etc/admiral/secrets` debe copiarse fuera del servidor inmediatamente.

Ese archivo contiene:

- secretos de bootstrap
- `ADMIRAL_SECRETS_KEY`
- `HARBOR_ENCRYPTION_KEY`

Si se pierde, no se pueden recuperar los datos cifrados ni los secretos necesarios para reinstalar la plataforma.

## Seguridad operativa

Esta sección documenta los riesgos aceptados por diseño y los procedimientos
de mantenimiento de seguridad que el operador debe conocer.

### Usuario SSH de operación (`opsa_*`)

El instalador crea un usuario SSH no-root (`opsa_<sufijo aleatorio>`, registrado
en `/etc/admiral/secrets` como `ADMIRAL_SSH_USER`) con `sudo NOPASSWD: ALL`.
Existe para el aprovisionamiento desatendido con Ansible (admin → spokes) y
como vía de recuperación del operador.

**Esto equivale a acceso root completo sin contraseña.** La llave SSH que da
acceso a esta cuenta debe protegerse como si fuera la clave root.

- En nodos spoke (`--worker-node`, `--portal-node`) es indispensable: root
  queda bloqueado (`PermitRootLogin no`) tras verificar el acceso no-root.
- En `--single-node` puede prescindirse de él una vez instalado, porque el
  aprovisionamiento es local. Para eliminarlo:

```bash
userdel -r "$(grep ^ADMIRAL_SSH_USER= /etc/admiral/secrets | cut -d= -f2-)"
rm -f /etc/sudoers.d/opsa_*
```

Si se elimina, la recuperación del host dependerá del acceso root por llave
(`PermitRootLogin prohibit-password`).

### Token de administración en Flagship

`/etc/admiral/flagship.env` contiene `ADMIRAL_ADMIN_TOKEN`, el token con
privilegios administrativos totales sobre la API de `admirald`. Flagship lo
necesita para operar como consola administrativa. Comprometer el proceso
Flagship equivale a comprometer la plataforma completa. El archivo se instala
con permisos `0600 root:admiral` y solo es legible por el servicio.

### Renovación de certificados TLS internos

La CA interna (`/etc/admiral/tls/ca.pem`) tiene vigencia de 10 años y los
certificados de servicio firmados con ella tienen vigencia de 730 días.
**No existe renovación automática todavía**; antes de que expiren, renueve
manualmente en cada nodo admin/portal:

```bash
rm -f /etc/admiral/tls/admirald-key.pem /etc/admiral/tls/admirald.csr /etc/admiral/tls/admirald.pem
sudo admiral-install --single-node   # o el modo original del nodo
```

El re-run es idempotente: regenera la clave y el certificado firmados por la
CA existente, sincroniza las copias de PostgreSQL y reinicia los servicios
afectados. La CA y su clave (`ca-key.pem`, solo en el nodo admin) no se tocan.

En perfiles seguros, SSH acepta únicamente claves, limita los intentos y
desactiva autenticación interactiva, contraseñas vacías, X11 y reenvío de
agente. El reenvío TCP permanece disponible para el túnel opcional documentado.

### Política de egreso por puertos

La política nftables de egreso (`admiral_egress`) filtra por puerto destino
(22, 53, 80, 123, 443, 587, 51820 según perfil), no por dirección destino,
porque los registros OCI y las APIs de PayPal usan CDNs con IPs rotativas.
NTP (UDP/123) mantiene una hora fiable y la instalación de producción exige
que `chronyd` alcance sincronización antes de completarse; esto protege la
validación TLS, la caducidad de tokens y las marcas de auditoría. Un workload
comprometido podría exfiltrar por 443; es una decisión consciente, equivalente
al modelo de Kubernetes. El operador puede añadir control por destino encima
si lo requiere.

### UIDs de contenedores rootless

El usuario `admiral-apps` recibe el rango fijo `100000:131072` en
`/etc/subuid` y `/etc/subgid`. En hosts con asignaciones previas en ese rango,
verifique colisiones antes de instalar (`grep 100000 /etc/subuid /etc/subgid`).

### Superficie de red interna

Los servicios internos (`admirald`, Fleet, Flagship, Harbor, PostgreSQL, la
Admin API de Caddy) escuchan en loopback o en la IP WireGuard del nodo.
El checklist del instalador no los considera superficie pública: la subred
`10.99.0.0/24` solo es alcanzable por pares WireGuard autenticados, y las
reglas de la zona `admiral` de firewalld solo admiten tráfico del hub.

### Tradeoff de paquete completo en nodos admin

Los perfiles `--admin-node` y `--admin-portal-node` instalan todos los
componentes Admiral aunque algunos servicios no se habiliten en ese host.
Esto evita divergencia de versiones entre playbooks y ejecutables durante
reconvergencias y upgrades, pero implica más binarios presentes en disco.

Mitigaciones recomendadas:

- mantener SELinux en enforcing
- aplicar errata de seguridad sin demoras (`dnf-automatic` activo)
- restringir acceso SSH administrativo a llaves gestionadas
- auditar servicios activos con `systemctl list-unit-files 'admiral*'`

## Archivos de configuración

| Componente | Archivo |
|-----------|---------|
| `admirald` | `/etc/admirald.ini` |
| `admiral-fleet` | `/etc/admiral/fleet.env` |
| `admiral-flagship` | `/etc/admiral/flagship.env` |
| `admiral-harbor` | `/etc/admiral/harbor.env` |
| `admiral-harbor` SMTP opcional | `/etc/admiral/harbor.smtp.env` |
| `admiralctl` | `~/.config/admiralctl/config.yaml` |

Los valores instalados en `/etc/admiralctl/config.yaml` son solo defaults del paquete.

## Verificación

```bash
systemctl status admirald admiral-fleet admiral-flagship admiral-harbor
admiralctl status
admiralctl nodes list
admiralctl instances list
admiralctl backups list
admiralctl routes list
admiralctl operations list
```

## Referencias

- `docs/sysadmin_guide.md`
- `docs/networking_v1.md`
- `admiralctl/docs/man.md`
