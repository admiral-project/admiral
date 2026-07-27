# Ejecución rootless en Admiral

Este documento explica qué significa *rootless* en Admiral, qué proceso conserva
privilegios en el host, cómo se entregan las operaciones a Podman y cómo comprobar
que un workload no se está ejecutando como root del host. También documenta los
resultados obtenidos en un host EL10 real. No se debe aprobar un cambio de este
modelo únicamente porque compile o porque una unidad pase un análisis estático:
debe superar workloads reales.

## Resumen para operadores y revisores de seguridad

Admiral separa dos responsabilidades:

- `admiral-fleet` es un agente del host. Se ejecuta como root porque crea
  directorios, cambia su propietario al usuario de workloads, escribe Quadlets y
  entra en la sesión systemd de ese usuario. No ejecuta el proceso de la
  aplicación como root.
- `admiral-apps` es el usuario local sin privilegios que ejecuta Podman, los pods,
  los contenedores y sus unidades systemd de usuario.

Por tanto, encontrar `User=root` —o la ausencia de `User=`— en
`admiral-fleet.service` no demuestra que los contenedores sean rootful. Tampoco se
debe “corregir” ese hallazgo añadiendo `User=admiral-apps`: Fleet dejaría de poder
preparar el host. La comprobación válida consiste en seguir el árbol de procesos,
el user manager y el propietario del almacenamiento de Podman, como se describe
en [Cómo demostrar que el workload es rootless](#cómo-demostrar-que-el-workload-es-rootless).

El límite de confianza es deliberado: Fleet recibe tareas autenticadas de
`admirald`, valida su estructura y realiza sólo acciones implementadas. Fleet no
es una API de shell remoto y no debe construir comandos arbitrarios a partir de
entrada del cliente.

## Modelo de procesos

El flujo normal es:

```text
admirald
  │ tarea autenticada y auditable
  ▼
admiral-fleet.service                  UID 0, servicio de sistema
  │ prepara archivos y cambia identidad
  ▼
user@<uid>.service                     UID de admiral-apps, servicio de usuario
  │ administra Quadlet y transient units
  ▼
podman / conmon / pasta / crun         UID de admiral-apps
  │ user namespace rootless
  ▼
proceso dentro del contenedor          no es root del host
```

Que un proceso vea UID 0 dentro del contenedor no le entrega UID 0 en el host.
Podman rootless lo ubica en un user namespace y usa los rangos subordinados de
`/etc/subuid` y `/etc/subgid`. La identidad relevante para auditar el host es el
UID propietario de Podman, conmon, pasta, el user manager y el almacenamiento.

## Preparación requerida en el host

El RPM y el proceso de inicialización deben dejar disponibles:

1. El usuario de sistema `admiral-apps`, con home persistente en
   `/var/lib/admiral-apps`.
2. Rangos no superpuestos en `/etc/subuid` y `/etc/subgid`.
3. Linger habilitado con `loginctl enable-linger admiral-apps`, para que
   `user@<uid>.service` exista sin un login interactivo.
4. `/run/user/<uid>` y su bus D-Bus de usuario.
5. `systemd-machined.service`, utilizado para administrar las unidades Quadlet
   del usuario mediante `systemctl --machine=<usuario>@ --user`.
6. Los directorios administrados por Fleet, con propietarios y etiquetas SELinux
   correctos.

El instalador de Fleet asigna los rangos subordinados dentro de los intervalos
definidos por `SUB_UID_MIN`/`SUB_UID_MAX` y `SUB_GID_MIN`/`SUB_GID_MAX` en
`/etc/login.defs`. No presupone que `100000` esté disponible: conserva un rango
existente que sea suficiente y no se solape, selecciona un intervalo libre para
una instalación nueva y aborta ante rangos insuficientes o solapados.

Comprobaciones mínimas, sustituyendo el UID si no es 991:

```bash
id admiral-apps
getent subuid admiral-apps
getent subgid admiral-apps
loginctl show-user admiral-apps -p Linger -p State -p RuntimePath
systemctl is-active user@991.service systemd-machined.service admiral-fleet.service
test -S /run/user/991/bus
getenforce
```

No se debe hardcodear el UID 991 en código, paquetes ni unidades. El UID lo puede
asignar `systemd-sysusers` de forma diferente en otro host.

## Qué hace Fleet con privilegios

Fleet necesita privilegios de host para un conjunto pequeño y explícito de
operaciones:

- crear la estructura de instancia bajo `/var/lib/admiral`;
- escribir Quadlets bajo `/etc/containers/systemd/users/<uid>/admiral`;
- entregar directorios, archivos de entorno y datos al UID/GID rootless;
- cambiar de UID/GID mediante `runuser`;
- comunicarse con el user manager persistente del usuario;
- iniciar, detener y consultar unidades de usuario;
- leer resultados y entregar callbacks autenticados a `admirald`.

Fleet no necesita `CAP_NET_ADMIN`, `CAP_NET_RAW` ni `CAP_NET_BIND_SERVICE` para el
modelo validado. La red y los puertos publicados pertenecen a Podman rootless;
los workloads probados usan puertos altos asignados por Admiral.

## Cómo ejecuta cada clase de operación

No existe un wrapper universal fiable para todas las operaciones de Podman en
EL10. La ruta se selecciona por semántica:

| Operación | Ruta de ejecución | Motivo |
|---|---|---|
| `podman run --rm` | `runuser` + `XDG_RUNTIME_DIR` | Helper rootless efímero; no requiere transient unit |
| `podman exists`, `inspect`, `port` | `runuser` + `XDG_RUNTIME_DIR` | Consulta directa al almacenamiento del usuario |
| `podman exec` | `runuser` + bus del usuario + `systemd-run --user` | Debe conservar la sesión/cgroup systemd del usuario |
| `podman secret create/rm` | `runuser` + bus del usuario + `systemd-run --user` | El secret pertenece al almacenamiento rootless |
| `systemctl --user` para Quadlet | `systemctl --machine=<usuario>@ --user` | Administración remota del user manager persistente |

Para la ruta del bus de usuario, Fleet establece:

```text
XDG_RUNTIME_DIR=/run/user/<uid>
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus
```

### Por qué `podman exec` no usa `--machine`

En el host EL10 de validación, un backup MariaDB real ejecutado con
`systemd-run --machine admiral-apps@ --user` falló con `Connection reset by
peer` y `Transport endpoint is not connected`. La misma operación, ejecutada diez
veces mediante el bus persistente del usuario y `systemd-run --user`, completó
diez veces. Después del cambio, backups y restore reales de WordPress funcionaron.

Esto no es una preferencia estética: es una decisión basada en el comportamiento
observado del transporte de `systemd-machined` desde una unidad endurecida.

### Archivos de entorno efímeros

Los comandos de backup y restore pueden necesitar variables sensibles. Fleet
crea un env-file temporal en `/var/lib/admiral/tmp`, lo cambia al propietario
rootless, aplica modo `0600` y lo elimina al terminar.

No se usa `/tmp`: `PrivateTmp=true` da a Fleet un `/tmp` distinto del que ve el
user manager, por lo que el transient unit no podría abrir el archivo. Los
valores sensibles no deben aparecer en logs, argumentos mostrados al operador ni
mensajes de error sin redacción.

## Perfil systemd validado para Fleet

La unidad empaquetada usa:

```ini
NoNewPrivileges=false
PrivateTmp=true
ProtectHome=read-only
ProtectSystem=strict
ReadWritePaths=/etc/containers/systemd/admiral /var/lib/admiral \
  /etc/containers/systemd/users /var/lib/admiral-apps /run/user
CapabilityBoundingSet=CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETUID CAP_SETGID
PrivateDevices=true
DevicePolicy=closed
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
```

### Justificación de las excepciones

- `NoNewPrivileges=false`: Fleet debe cambiar identidad y lanzar procesos bajo
  el usuario rootless. Activarlo en el mediador impide operaciones necesarias;
  los contenedores generados sí usan `no-new-privileges`.
- `/var/lib/admiral`: estado de instancias, env-files y temporales controlados.
- `/etc/containers/systemd/users`: Quadlets de usuario generados por Fleet.
- `/var/lib/admiral-apps`: home y almacenamiento rootless de Podman.
- `/run/user`: bus y runtime cuyo UID se asigna dinámicamente. Una ruta estática
  `/run/user/991` no sería portable.
- capabilities `CHOWN`, `FOWNER` y `DAC_OVERRIDE`: preparar y corregir propiedad
  y modos de archivos administrados.
- capabilities `SETUID` y `SETGID`: entrar en la identidad de `admiral-apps`.

`ProtectSystem=strict` convierte el resto del filesystem en sólo lectura para
Fleet. `PrivateDevices=true` y `DevicePolicy=closed` evitan acceso a dispositivos
no requerido. `ProtectControlGroups=true` evita que Fleet escriba directamente
en cgroups; systemd conserva esa responsabilidad.

### Permisos probados y descartados

Se retiraron del bounding set, uno por uno, y los workloads reales continuaron
funcionando:

- `CAP_NET_BIND_SERVICE`
- `CAP_NET_ADMIN`
- `CAP_NET_RAW`

No deben reintroducirse para “arreglar Podman” sin reproducir un fallo real y
documentar qué syscall u operación las necesita.

## Cómo demostrar que el workload es rootless

Una revisión debe recoger varias evidencias; comprobar sólo `ps` dentro del
contenedor causa falsos positivos.

```bash
uid=$(id -u admiral-apps)

# El user manager persistente pertenece al usuario rootless.
systemctl status "user@${uid}.service"

# Las unidades de la aplicación son unidades de usuario, no unidades de sistema.
systemctl --machine=admiral-apps@ --user --type=service

# Podman ve los contenedores desde el almacenamiento de admiral-apps.
cd /
runuser -u admiral-apps -- env \
  HOME=/var/lib/admiral-apps \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  podman ps

# Los procesos del runtime en el host pertenecen a admiral-apps.
ps -eo user,uid,pid,ppid,cgroup,comm,args | \
  grep -E 'podman|conmon|pasta|crun'

# El almacenamiento no es /var/lib/containers/storage de root.
runuser -u admiral-apps -- env \
  HOME=/var/lib/admiral-apps \
  XDG_RUNTIME_DIR="/run/user/${uid}" \
  podman info --format '{{.Store.GraphRoot}}'
```

El resultado esperado incluye:

- unidades `admiral-inst_*.service` bajo `user@<uid>.service`;
- procesos `conmon`, `pasta` y contenedores propiedad de `admiral-apps`;
- graph root bajo `/var/lib/admiral-apps`;
- ausencia de unidades de workload equivalentes en el system manager;
- Quadlets bajo el árbol de usuarios de containers/systemd.

## SELinux

Rootless no sustituye SELinux. Las pruebas válidas se realizan con SELinux
`Enforcing`, después de instalar el RPM y aplicar las etiquetas empaquetadas:

```bash
restorecon -RF /usr/bin/admiral-fleet \
  /usr/lib/systemd/system/admiral-fleet.service \
  /etc/admiral /var/lib/admiral /var/lib/admiral-apps
getenforce
ausearch -m AVC -ts recent
```

No se considera solución ejecutar con SELinux permissive, añadir reglas amplias
sin AVC concreto ni cambiar etiquetas manualmente sin reflejarlas en packaging.

## Criterio de validación de cambios

Un cambio de permisos, transporte rootless, Quadlet, backup o packaging sólo es
válido cuando supera, como mínimo:

1. `go test ./...` y `go vet ./...` en `admiral-fleet`.
2. Construcción del RPM desde el source tree modificado.
3. Instalación/reinstalación del RPM en EL10.
4. `restorecon` y SELinux `Enforcing`.
5. Arranque de Fleet sin drop-ins que oculten el contenido del RPM.
6. Provision de una app real mediante `admirald` y Fleet.
7. Respuesta funcional de la aplicación, no sólo contenedor `running`.
8. Backup real de base de datos o volumen, según la app.
9. Pause/resume o stop/start y nueva comprobación funcional.
10. Revisión de AVC y de propietario/cgroup de los procesos.

Para cambios sensibles se usa WordPress/MariaDB y el golden test de ERPNext. Una
app mínima resulta útil para diagnóstico, pero por sí sola no valida setup,
persistencia, varios servicios, dependencias y backups.

## Validación viva del 14 de julio de 2026

Entorno:

- CentOS Stream 10, kernel 6.12;
- systemd 257;
- Podman 6.0;
- SELinux `Enforcing`;
- usuario `admiral-apps` con UID 991 en este host;
- RPM `admiral-fleet-0.0.1beta16-1.el10.x86_64` reinstalado con reemplazo
  forzado;
- unidad empaquetada, sin drop-in experimental.

Resultados confirmados hasta este punto:

| Workload | Prueba funcional | Persistencia/backup | Lifecycle | Resultado |
|---|---|---|---|---|
| WordPress + MariaDB | instalación real de WordPress | backup MariaDB y restore de una opción modificada | pause/resume, stop/start | correcto |
| E2E Whoami + PostgreSQL | HTTP 200 con identidad del contenedor | backup PostgreSQL real | pause/resume y HTTP posterior | correcto |
| Uptime Kuma | frontend HTTP 302 esperado | backup del volumen `kuma_data` | pause/resume y HTTP posterior | correcto |
| ERPNext 15 + MariaDB + 3 Redis + 6 servicios Frappe | `bench new-site`, instalación de Frappe/ERPNext, Login HTTP 200 y `bench list-apps` | backup MariaDB y backup de volúmenes compartidos | pause/resume y Login HTTP 200 posterior | correcto |

WordPress se ejecutó tres veces: perfil anterior, perfil endurecido intermedio y
perfil final `strict`. El perfil final conservó Quadlet, secrets, healthchecks,
setup, backup y lifecycle. No se observaron AVC durante esos ciclos.

El golden test ERPNext usó el tier `dev` de 2 GiB. Creó un pod con MariaDB, tres
Redis y los servicios frontend, backend, setup, websocket, scheduler y worker.
El provision tardó aproximadamente siete minutos, incluyendo descarga de imagen,
`bench new-site`, instalación de Frappe y ERPNext y reinicio del pod posterior al
setup. La verificación funcional obtuvo:

- operación de provision `succeeded` y `setup_completed=true`;
- página Login con HTTP 200 y 345503 bytes;
- `bench --site frontend list-apps` devolvió `frappe` y `erpnext`;
- backup de base de datos MariaDB `succeeded`;
- backup de volúmenes compartidos `succeeded`;
- pause y resume `succeeded`;
- la misma página Login volvió a responder HTTP 200 después del resume.

El resultado se registró sólo después de esas comprobaciones, no cuando los
contenedores pasaron a estado `running`.

## Diagnóstico por tipo de fallo

- Fallan `podman exec` o secrets: comprobar `/run/user/<uid>/bus`, linger,
  `user@<uid>.service`, propietario del env-file y transient units.
- Falla `systemctl --user`: comprobar `systemd-machined.service`, el user manager
  y la ubicación/generación del Quadlet.
- Fallan `run`, `exists`, `inspect` o `port`: comprobar `runuser`, el UID resuelto,
  `XDG_RUNTIME_DIR`, home y almacenamiento de Podman.
- El contenedor arranca pero la app no responde: revisar healthcheck, dependencias,
  setup y logs del servicio; `active (running)` no basta.
- Falla con `ProtectSystem=strict`: identificar la ruta exacta que necesita
  escritura. No ampliar `ReadWritePaths` a `/etc`, `/var` o `/run` completos sin
  evidencia.
- Aparece un AVC: conservar el evento, reproducirlo y corregir etiqueta o acceso
  mínimo. No deshabilitar SELinux.

## Errores de interpretación que deben evitarse

- “Fleet corre como root, entonces los workloads son rootful”: falso; auditar el
  user manager, cgroup, propietario y graph root.
- “UID 0 dentro del contenedor es root del host”: falso en un user namespace
  rootless.
- “`NoNewPrivileges=false` en Fleet se hereda como privilegio del workload”:
  falso; el Quadlet aplica `no-new-privileges` al contenedor.
- “La unidad obtiene una buena puntuación de hardening, entonces funciona”:
  incompleto; debe pasar los workloads y backups descritos.
- “El contenedor está `running`, entonces el provision funciona”: incompleto;
  setup, HTTP y persistencia pueden seguir fallando.
- “Una capability podría ser útil en el futuro”: no es justificación para
  mantenerla. La lista debe corresponder a operaciones actuales y comprobadas.
