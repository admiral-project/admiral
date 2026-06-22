# Admiral Installation Guide

Guía oficial para instalar Admiral en Enterprise Linux 10.

## Alcance

Este documento cubre el flujo oficial de instalación:

1. ejecutar `admiral_install`
2. configurar HTTPS con `admiral_https_setup`
3. configurar el storage S3 de forma manual
4. respaldar `/etc/admiral/secrets` fuera del servidor

No cubre despliegues multi-node. Para eso, ver `docs/sysadmin_guide.md`.

**Nota sobre modos multi-node**: `--worker-node` y `--portal-node` son mutuamente
excluyentes por diseño. Un mismo servidor no puede ejecutar ambos roles.
Si necesita worker y portal, despliegue nodos separados.

## Plataforma soportada

- Enterprise Linux 10
- `admiral_install`
- `admiral_https_setup`
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
sudo admiral_install --single-node
```

El instalador:

- instala los RPMs requeridos
- configura los servicios
- genera secretos y certificados internos
- arranca los servicios principales del modo seleccionado

La postura por defecto es:

- `22/tcp` siempre público para administración por SSH
- `80/tcp` y `443/tcp` públicos solo en `--single-node` y `--admin-node`, servidos por Caddy
- `51820/udp` público siempre para WireGuard
- ningún puerto interno de `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, PostgreSQL o la Admin API de Caddy debe exponerse directamente

### 3. Configurar HTTPS público

`admiral_install` no configura el wildcard público ni maneja DNS.
Eso se hace manualmente después de la instalación con:

```bash
sudo admiral_https_setup --domain cloud.example.com
```

`admiral_https_setup` usa DNS-01. El operador debe publicar el TXT record que certbot solicite.

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
