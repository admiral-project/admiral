# Admiral Installation Guide

Guía oficial para instalar Admiral en sistemas Fedora y Enterprise Linux.
La matriz de release activa x86_64 cubre Rocky Linux 10 y CentOS Stream 10
(Tier 1), y Fedora Rawhide (Tier 2). AlmaLinux 10 y Fedora estable quedan
fuera de la matriz activa.

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

- Rocky Linux 10 y CentOS Stream 10 x86_64: Tier 1 del gate activo
- Fedora Rawhide x86_64: Tier 2 incluido en el gate activo
- AlmaLinux 10: Tier 2, fuera del gate activo mientras el chroot COPR
  `alma+epel-10-x86_64_v2` no compile los RPM Go ([#276](https://github.com/admiral-project/admiral/issues/276))
- Fedora estable queda fuera de la matriz activa
- Otros sistemas compatibles pueden usar los modos seguros, pero no cuentan
  como evidencia de la matriz activa
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

`admiral-common` es dueño de los directorios fijos de configuración y datos,
incluidos sus propietarios y modos. Esto cubre también las raíces de datos para
instancias, backups, restore, temporales, la outbox y los backups cifrados del
control plane. Por eso se puede instalar ese RPM y configurar el host
manualmente sin ejecutar Ansible para preparar directorios. Fleet valida esas
raíces y crea solo contenido dinámico debajo de ellas. Los playbooks escriben
archivos de configuración y verifican los atributos del paquete; no crean ni
cambian permisos de directorios.

La postura por defecto es:

- El gate activo x86_64 requiere Rocky Linux 10, CentOS Stream 10 y Fedora
  Rawhide, cada uno en Single-Node y Multi-Node
- AlmaLinux 10 es Tier 2 y queda fuera de la matriz activa por la limitación
  COPR indicada arriba; no debe reportarse como validado
- `--dev-node` conserva su perfil de desarrollo y no sustituye la validación
  de producción
- `22/tcp` siempre público para administración por SSH
- `80/tcp` y `443/tcp` públicos solo en `--single-node` y `--admin-node`, servidos por Caddy
- `51820/udp` público en perfiles multi-node para WireGuard; el single-node
  seguro no ejecuta WireGuard
- ningún puerto interno de `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, PostgreSQL o la Admin API de Caddy debe exponerse directamente
- Worker y Portal pueden configurarse con IPv6 público y conservar sus
  direcciones WireGuard IPv4 privadas; el E2E IPv6 público requerido por
  [#304](https://github.com/admiral-project/admiral/issues/304) sigue pendiente
  y todavía no cuenta como capacidad validada del release
- los errata de seguridad disponibles se aplican durante el playbook; quedan
  habilitados `dnf-automatic.timer` en EL10 y `dnf5-automatic.timer` en Fedora
- en los modos seguros de Fedora, LLMNR se desactiva mediante un drop-in de
  `systemd-resolved`; DNS unicast permanece habilitado
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

### Verificación por email de operadores (Flagship)

Flagship permite exigir, por operador, un código de verificación de un solo uso
cuando se inicia sesión desde un navegador desconocido. La entrega usa SMTP
(`FLAGSHIP_SMTP_HOST`, `FLAGSHIP_SMTP_FROM`, ver `admiral-flagship/README.md`).
Sin SMTP configurado, el login desde un navegador no confiable **falla cerrado**
(no abre sesión). Cada código es de un solo uso, expira en 10 minutos y está
limitado por intentos y por reenvíos por cuenta e IP. Si el operador pierde el
acceso al correo verificado, la recuperación requiere acceso administrativo al
host para limpiar `mfa_email_enabled` en PostgreSQL (ver *break-glass recovery*
en `admiral-flagship/README.md`); el correo y el código nunca se registran en
logs.

### Renovación de certificados TLS internos

La CA interna (`/etc/admiral/tls/ca.pem`) tiene vigencia de 10 años y los
certificados de servicio firmados con ella tienen vigencia de 730 días.
**No existe renovación automática todavía**; antes de que expiren, renueve
manualmente en cada nodo admin/portal:

```bash
rm -f /etc/admiral/tls/admirald-key.pem /etc/admiral/tls/admirald.csr /etc/admiral/tls/admirald.pem
sudo admiral-install --single-node   # o el modo original del nodo
```

El re-run es idempotente: conserva la clave y el certificado existentes. Tras
una renovación manual, sincroniza las copias de PostgreSQL y lo reinicia solo
si cambió el material TLS o su configuración. La CA y su clave (`ca-key.pem`,
solo en el nodo admin) no se tocan.

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
