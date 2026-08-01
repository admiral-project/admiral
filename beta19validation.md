# Bitácora de validación beta19

Fecha de inicio: 2026-07-30  
Responsable: William Moreno Reyes <williamjmorenor@gmail.com>

Esta bitácora es viva: se actualiza al terminar cada hito de validación, al
encontrar un bloqueo y al corregir un defecto que pueda afectar el lanzamiento.

## Alcance

- RPMs locales beta19 de Admiral; no se compilan paquetes Python.
- Repositorios COPR habilitados: `admiral-project/admiral` y `@caddy/caddy`.
- Validación `--single-node` en CentOS Stream 10, Rocky Linux 10 y AlmaLinux 10.
- Validación multinodo en nube local simulada con un nodo
  `--admin-portal-node` y un nodo `--worker-node`.
- Revisión del alta SSH y del handshake entre `admiral-fleet` y `admirald`.
- Despliegue de WordPress rootless con Podman.
- Revisión y cierre fundamentado de los issues abiertos. PayPal real queda fuera
  del alcance de beta19.

## Artefactos bajo prueba

Los RPMs se usan desde `packaging/build/RPMS/`:

- `admiral-common-0.0.1beta19-35.el10.noarch.rpm`
- `admirald-0.0.1beta19-4.el10.x86_64.rpm`
- `admiral-fleet-0.0.1beta19-7.el10.x86_64.rpm`
- `admiralctl-0.0.1beta19-1.el10.x86_64.rpm`
- `admiral-flagship-0.0.1beta19-1.el10.noarch.rpm`
- `admiral-harbor-0.0.1beta19-2.el10.noarch.rpm`

## Resultados

| Área | Entorno | Estado | Evidencia |
|---|---|---|---|
| Pruebas de instalador | Host de validación | Aprobado | `python3 -m unittest discover -s scripts -p 'test_*.py'`: 48 pruebas correctas. |
| Pruebas Go | Host de validación | Aprobado | `go test ./admirald/... ./admiral-fleet/... ./admiralctl/...` correcto. |
| Single node | Rocky Linux 10 | Aprobado | `admiral-install --single-node` terminó con `ok=214`, `changed=104`, `failed=0`; servicios activos. |
| WordPress | Rocky Linux 10 | Aprobado | Operación `op_45a77d013a8fdd86` correcta; instancia `inst_e8c7b3742bb647a5` sana y en ejecución. El HTTP local respondió 301 y los contenedores se ejecutaron como `admiral-apps` con Podman rootless. |
| Single node | AlmaLinux 10 | Aprobado | Reinstalados los RPM locales actuales y convergencia `admiral-install --single-node` correcta. Caddy responde `200` en `127.0.0.1:2019`, los cinco servicios están activos, `harborctl ping` y ambos nodos informan estado saludable. No hubo errores de reconciliación de rutas posteriores al reinicio de Admirald. |
| Single node | CentOS Stream 10 | Aprobado | VM limpia con los RPM locales actuales. La convergencia `admiral-install --single-node` dejó los cinco servicios activos, Caddy respondió `200` en `127.0.0.1:2019`, Harbor respondió correctamente y los nodos portal/worker quedaron `active` y `healthy`. |
| WordPress | CentOS Stream 10 | Aprobado | Operación `op_6fa5f77057b0536a` correcta; instancia `inst_60611fa4ffdfa938` con estado técnico `running`. `podman ps` bajo `admiral-apps` mostró los servicios rootless y `curl http://127.0.0.1:40000/` respondió `301`. |
| WordPress | AlmaLinux 10 | Aprobado | Operación `op_e29c08a4012626d8` correcta; instancia `inst_c8bda6f60fb27eba` con estado técnico `running`. Los cuatro contenedores rootless se ejecutaron como `admiral-apps` y `curl http://127.0.0.1:40000/` respondió `301`. |
| Multinodo | Rocky Linux 10 admin + CentOS Stream 10 worker en red local aislada | Aprobado | `--admin-portal-node` en `192.168.100.93` y `--worker-node` en `192.168.100.94`; reconciliación Ansible final `failed=0`; RPMs beta19 locales instalados en ambos nodos. |
| SSH y handshake | Multinodo | Aprobado | WireGuard `10.99.0.1`--`10.99.0.2` con handshake activo; `worker-beta19` registró `fleet_version=0.0.1beta19`, `health_status=healthy` y `available_for_provisioning=true`. La llave bootstrap se conservó intencionalmente con `--no-revoke-ssh-key` para recuperación del laboratorio. |
| WordPress | Multinodo | Aprobado | Provision `op_d269c72819eaf2b9`, instancia `inst_c4e0a2cb67a47ab2` sana, `setup_completed=true`, técnica `running`; HTTP sobre VPN respondió `301`; los cuatro contenedores permanecieron rootless bajo `admiral-apps`. |
| Backup y ciclo de vida | Multinodo | Aprobado | Backup DB `op_b58ab1d6fc02e8c2` correcto; pausa `op_0932f222007181ad` y resume `op_c1e80121a6f3fd0b` correctos; la instancia quedó saludable tras reanudar. |
| Backup y restore de datos como `admiral-apps` | Single node (CentOS Stream 10) | Aprobado | El plan de datos (dump de base y artefactos de restauración) se ejecuta con el helper `admiral-fleet-backup` bajo `admiral-apps` (uid 991), de modo que los archivos quedan propiedad de ese usuario y no de root. Backup manual `op_c981ae9901386cad` correcto → `bk_a9026335dfedcafb` (mariadb, `size_bytes 20601`, `checksum_sha256 470b391335e4e761f4709060b9bdf61d67512274c9bfdea630b38a735bb4191f`, `storage_backend s3`, `triggered_by manual`). Restore `op_340723750a8dbcff` correcto desde S3 con verificación de checksum: tras reanudar, un cambio a `wp_options.blogname` realizado después del backup quedó revertido, evidencia de que el dump se aplicó sobre los datos en ejecución. La instancia quedó `technical_status=running` y `health_status=healthy`. |
| Entrega de árboles sin seguir symlinks | Single node (CentOS Stream 10) | Aprobado | Se plantó un symlink `planted-link → /etc/hostname` dentro del árbol `backups/` y se ejecutó un backup real con `admiral-fleet-0.0.1beta19-7`: la operación `op_bbad52b90bd513fa` terminó `succeeded`, el symlink quedó intacto y sin tocar, y `/etc/hostname` conservó el propietario `root:root`. La migración de propiedad se realiza con `lchown` y salta los symlinks, por lo que un árbol modificable por el usuario rootless no puede redirigir a root a cambiar el propietario de un archivo arbitrario del host. |
| Issues de GitHub | `admiral-project/admiral` | En curso | #3, #4 y #12 están cerrados. Permanecen abiertos #5, #6, #10, #14, #16 y #17; no se modifican desde esta validación y requieren resolución o decisión explícita de release. |

## Hallazgos corregidos antes de continuar

1. La precondición del instalador shell trataba una instalación RPM nueva como
   una configuración heredada. Corregido en
   `fix(installer): allow fresh RPM baseline configuration`.
2. La misma condición existía en el playbook Ansible. Corregido en
   `fix(installer): accept clean RPM baseline in playbook`.
3. Los comandos instalados tenían guion bajo cuando la interfaz documentada usa
   guiones. Corregido en `fix(cli): standardize installed command names`.
4. Al delegar el backup/restore del plan de datos al helper
   `admiral-fleet-backup`, el primer intento falló porque el helper usaba
   `systemctl --user` con opciones que solo acepta `systemd-run`
   (`--collect`). Corregido en `fix(backup): run helper podman via systemd-run
   and keep task errors`.
5. Tras corregir lo anterior, el segundo intento falló con "permission denied"
   al escribir el artefacto porque los árboles `backups/restore/tmp` creados
   antes por root no eran propiedad del usuario rootless. Corregido en
   `fix(backup): hand pre-existing storage trees to the rootless user`.
6. La migración de propiedad de los árboles de almacenamiento usaba `os.Chown`
   dentro de un `Walk`, que sigue symlinks. Una vez que el árbol queda
   modificable por el usuario rootless, un symlink plantado podía redirigir a
   root (Fleet) a cambiar el propietario de un archivo arbitrario del host, y
   además con una ventana TOCTOU de swap directorio→symlink. Corregido usando
   `lchown` y saltando las entradas symlink, incluido el chown de la raíz, en
   `fix(executor): hand storage trees to rootless without following symlinks`
   (commit `92650d6`, RPM `admiral-fleet-0.0.1beta19-7`).

## Hallazgos en curso

4. En EL10, una instalación nueva necesita el repositorio CRB además de EPEL
   para resolver dependencias de instalación. Rocky y Alma se prepararon con
   CRB explícitamente para continuar la matriz. El bootstrap shell y el rol
   Ansible ahora habilitan CRB de forma explícita antes de instalar paquetes de
   Admiral; la prueba de regresión pasó (46 pruebas). Falta reconstruir el RPM
   `admiral-common` y repetir la validación en una instalación EL10 limpia.

Actualización: el RPM local `admiral-common-0.0.1beta19-34.el10.noarch.rpm`
fue reconstruido correctamente con la corrección de CRB y sus referencias de
fuente fueron validadas. Se utilizará para las instalaciones restantes.

5. En Alma, la primera convergencia dejó una máscara ACL vacía en el socket
   administrativo de Caddy, con lo cual Admirald no podía reconciliar rutas.
   El token de Fleet sí quedó correcto tras el registro del nodo; los `401`
   iniciales fueron previos a ese registro. Los intentos de reparar el socket
   con un watcher y con `ExecStartPost` no son robustos: Caddy recrea el socket
   al recibir `/load` y vuelve a perder los ACL aplicados.

Actualización: se descarta el socket Unix como transporte de la Admin API.
`admirald` y Caddy se ejecutan en el mismo host; la API queda ligada únicamente
a `127.0.0.1:2019`, no se publica en el firewall y el VPS se administra por
SSH. En esta topología el socket Unix no añade una capa de protección material
frente a loopback, pero sí añade complejidad operativa y riesgo de regresión
durante las recargas de Caddy. El playbook elimina los overrides y ACL
anteriores, y configura explícitamente el puerto loopback. Falta reconstruir
los RPM locales afectados y repetir Alma.

## Criterio de salida

beta19 queda validado únicamente cuando las tres instalaciones single-node y el
flujo multinodo terminen sin fallos, se compruebe el handshake Fleet--Admirald,
WordPress rootless permanezca sano y cada issue abierto tenga una resolución con
evidencia o una justificación explícita de fuera de alcance.

## Hito cerrado: matriz single-node

La matriz single-node queda cerrada el 2026-07-30. Rocky Linux 10, AlmaLinux
10 y CentOS Stream 10 completaron la instalación con los RPM locales beta19;
en los tres se verificó Caddy por `127.0.0.1:2019` y un despliegue real
WordPress/MariaDB rootless.

## Hito cerrado: multinodo beta19

El escenario multinodo queda validado el 2026-07-30 con los RPMs locales beta19.
El worker ejecutó Podman con `rootless=true`, almacenamiento en
`/var/lib/admiral-apps/.local/share/containers/storage`, cgroup `systemd` y
`Linger=yes`. La instancia WordPress fue creada en el worker, respaldada,
pausada y reanudada sin fallos persistentes. El primer intento de bootstrap no
se contabiliza porque mezcló RPMs beta18 del COPR; se corrigió instalando el
conjunto local beta19 completo antes de repetir la prueba.
