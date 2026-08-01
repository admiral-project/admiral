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
- Fleet delega todas las operaciones Podman a helpers especializados que se
  ejecutan como `admiral-apps`:
  - `admiral-fleet-lifecycle` para existencia, inspección, puertos y eliminación
    de pods, contenedores y volúmenes;
  - `admiral-fleet-setup` para `exec`, `cp`, `run --rm`, login y secrets;
  - `admiral-fleet-backup` para backup, restore y artefactos de almacenamiento.
- Los helpers reciben tareas por stdin y comparten el mismo runtime rootless.
  Ninguno tiene privilegios de host ni constituye una API de shell remoto.

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

## Arquitectura y modelo de procesos

### Enfoque final: binarios especializados y una sola ruta rootless

La migración no introduce un binario monolítico. El contrato de ejecución se
divide por responsabilidad:

| Binario | Responsabilidad | Puede ejecutar |
|---|---|---|
| `admiral-fleet-lifecycle` | Estado y ciclo de vida | `version`, `port`, `pod`, `ps`, `container`, `volume`, `rm` |
| `admiral-fleet-setup` | Provisionado y operaciones efímeras | `exec`, `cp`, `run`, `login`, `secret` |
| `admiral-fleet-backup` | Plan de datos | dump, restore, checksum y S3 |

Los tres son ejecutables independientes, instalados por RPM con permisos
normales de usuario y lanzados directamente como `admiral-apps`. Comparten sólo
el protocolo pequeño, la validación del dominio y el transporte rootless; no
comparten un ejecutable grande ni una API de shell.

La ruta única de producción es:

```text
Fleet (root; host/systemd/storage)
  └─ runuser -u admiral-apps
       └─ helper especializado
            └─ systemd-run --user --wait --collect --pipe
                 └─ podman rootless
```

Fleet no invoca `podman` directamente para lifecycle, setup, healthchecks,
secrets, backup o restore. La compatibilidad de bajo nivel que permanece en el
paquete Podman sólo sirve a dobles de prueba y a constructores explícitos; no
es una ruta seleccionable por el servicio Fleet en producción. Así se evita
que una operación cambie silenciosamente entre dos contextos de permisos.

Cada solicitud contiene versión, operación, argumentos estructurados y, cuando
corresponde, stdin binario. Los secretos viajan por stdin o por el entorno
controlado del helper, nunca como argumentos visibles en `ps`. El helper sólo
acepta operaciones de su tabla y rechaza cualquier primera operación fuera de
su dominio.

El flujo normal es:

```text
admirald
  │ tarea autenticada y auditable
  ▼
admiral-fleet.service                  UID 0, servicio de sistema
  │ prepara archivos, escribe Quadlets y administra systemd
  ├─ orquestación de contenedores ──► systemctl --machine=<usuario>@ --user
  └─ operaciones Podman ───────────► runuser -u admiral-apps, tarea por stdin
                                      │
                                      ├─ admiral-fleet-lifecycle
                                      ├─ admiral-fleet-setup
                                      └─ admiral-fleet-backup
                                              │ runtime rootless común
                                              │ systemd-run --user --wait --collect --pipe
                                              ▼
                                      user@<uid>.service
                                              │ transient unit
                                              ▼
                                      podman / conmon / pasta / crun
                                                                UID de admiral-apps
                                              │ user namespace rootless
                                              ▼
                                      proceso dentro del contenedor
                                                                no es root del host
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

Fleet no ejecuta Podman directamente. La única ruta permitida para operaciones
Podman es:

```text
admiral-fleet (root)
  └─ runuser -u admiral-apps
       └─ helper especializado
            └─ runtime rootless común
                 └─ systemd-run --user --wait --collect --pipe
                      └─ podman
```

| Operación | Helper | Responsabilidad de Fleet |
|---|---|---|
| existencia, inspect, port y eliminación | `admiral-fleet-lifecycle` | Validar tarea y reportar resultado |
| `exec`, `cp`, `run --rm`, login y secrets | `admiral-fleet-setup` | Preparar archivos y coordinar systemd |
| backup y restore de base/volúmenes | `admiral-fleet-backup` | Preparar storage, pause/resume y coordinar systemd |
| Quadlet, daemon-reload, start, stop y restart | `systemctl --machine=<usuario>@ --user` | Ejecutar la orquestación de unidades |

Los tres helpers utilizan el mismo runtime para configurar `HOME`,
`XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, timeouts, stdin/stdout, errores y
sanitización. No existe una segunda implementación `runuser + podman` dentro de
Fleet ni fallback a Podman root si un helper no está instalado.

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

## Helpers rootless especializados

Cada helper es un binario pequeño con un dominio limitado. La lógica común de
transporte y seguridad vive en un paquete interno compartido; no se duplica en
los binarios.

- `admiral-fleet-lifecycle` ejecuta consultas y operaciones Podman de lifecycle.
- `admiral-fleet-setup` ejecuta operaciones interactivas, setup, secrets y
  contenedores efímeros.
- `admiral-fleet-backup` ejecuta dumps, restores, checksum y almacenamiento S3.

Fleet conserva la orquestación de unidades: renderiza Quadlets, solicita
`daemon-reload`, inicia o detiene unidades y coordina pause/resume. El helper
especializado ejecuta solamente la operación Podman asignada.

### Transporte

```text
admiral-fleet (root)
  └─ runuser -u admiral-apps -- env \
       XDG_RUNTIME_DIR=/run/user/<uid> \
       DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus \
       ADMIRAL_FLEET_DATA_DIR=/var/lib/admiral \
       ADMIRAL_FLEET_ROOTLESS_USER=admiral-apps \
       /usr/bin/admiral-fleet-backup <backup|restore>
         ← tarea JSON por stdin
```

- La tarea viaja por **stdin**, nunca en argv: las credenciales de almacenamiento
  no quedan visibles en `ps`.
- El helper responde un `TaskResult` por stdout. Ante un fallo escribe el error en
  stderr, sale con código no-cero y Fleet conserva el error estructurado del
  helper en vez de sustituirlo por el error genérico de lanzamiento.
- Dentro del helper, Podman se invoca con `systemd-run --user --wait --collect
  --pipe`, la misma ruta validada para `podman exec`. Las credenciales S3 se
  heredan del environ de Fleet a través de `runuser`.
- `ADMIRAL_FLEET_DATA_DIR` y `ADMIRAL_FLEET_ROOTLESS_USER` se pasan por entorno
  para que el helper localice los árboles y al usuario sin argumentos
  adicionales.

El mismo transporte se usa para `admiral-fleet-lifecycle` y
`admiral-fleet-setup`; cada helper acepta únicamente las acciones de su propio
dominio.

### Entrega de árboles de almacenamiento

El usuario rootless debe poder crear y borrar artefactos y staging sin root. Por
eso Fleet entrega los árboles `backups/`, `restore/` y `tmp/` bajo
`/var/lib/admiral` al UID/GID de `admiral-apps`:

- crea cada raíz con modo `0751` y la hace propiedad del usuario rootless;
- los artefactos preexistentes creados por versiones anteriores de Fleet (que
  corrían como root) se migran recursivamente al usuario rootless.

La migración usa **`lchown` y salta los symlinks**: una vez que el árbol queda
modificable por el usuario rootless, un symlink plantado dentro de él nunca debe
ser dereferenciado por `os.Chown` (eso permitiría que el usuario rootless
redirija a root a cambiar el propietario de un archivo arbitrario del host).
`lchown` además es inmune a una carrera TOCTOU de swap directorio→symlink porque
no dereferencia: como máximo cambia el propietario del propio enlace.

### Garantías y límites de los helpers

- Cada helper ejecuta exactamente las acciones autorizadas de su dominio; no son
  una API de shell remoto y no construyen comandos arbitrarios desde la tarea.
- Los helpers escriben únicamente en los árboles que Fleet les entrega como
  propietario y no tienen privilegios de host.
- No toma decisiones de negocio: si un backup o restore procede lo decide
  `admirald`, no los helpers.
- Los tres helpers se empaquetan en el RPM de Fleet y `restorecon` los etiqueta
  en `%post` para SELinux.

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
  /usr/bin/admiral-fleet-backup \
  /usr/bin/admiral-fleet-lifecycle \
  /usr/bin/admiral-fleet-setup \
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
11. Comprobar que los tres helpers se ejecutan como `admiral-apps`, reciben la
    tarea por stdin y no exponen secretos en argv.
12. Comprobar por separado `run`, `inspect`, `exec`, `cp`, secrets, backup y
    restore; todas deben usar el runtime rootless común.

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
- RPM `admiral-fleet-0.0.1beta19-6.el10.x86_64` reinstalado con reemplazo
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

## Validación viva del 1 de agosto de 2026: migración al helper rootless

Entorno: CentOS Stream 10, `admiral-fleet-0.0.1beta19-9.el10.x86_64` instalado
desde el RPM local, SELinux `Enforcing`, `admiral-apps` con UID 991.

Ciclo E2E con WordPress/MariaDB sobre el plano de datos delegado:

| Comprobación | Evidencia |
|---|---|
| Backup manual delegado | Operación `op_8f43a9e89de06c99` `succeeded`; backup `bk_7c69fe302c83c465` (`s3`, checksum sha256 `d0bb538b28a355fc17086c8c727bcb9736764f52ed4f890c1ef003237979f56f`). |
| Propiedad de los artefactos | El tar.gz resultante pertenece a `admiral-apps` y se creó bajo `backups/`, no por un chown posterior de root. |
| Restore delegado desde S3 | Pause `op_d57bce9a26b3173e`, restore `op_c99924894e0a9e7f` y start `op_23c7693e30475c28`, todos `succeeded`; el restore verificó checksum. |
| Estado final | Inspección `op_6cb1de70ddb621be` confirmó `technical_status=running` y `health_status=healthy`; WordPress respondió HTTP 301. |
| Entrega de árboles antiguos | Migración recursiva de `backups/`, `restore/` y `tmp/` al usuario rootless con `lchown` y sin seguir symlinks. |
| TLS | El flujo S3 mantiene `ADMIRAL_INSECURE_SKIP_VERIFY=0`. |

El ciclo E2E final sólo se considera válido cuando lifecycle, inspect, setup,
secrets, backup y restore utilizan los helpers especializados y el mismo runtime
rootless, sin fallback a la ruta Podman ejecutada por Fleet como root.

La corrección de ownership de los archivos temporales de entorno queda incluida
en `admiral-fleet-0.0.1beta19-9`: Fleet conserva el archivo bajo el UID rootless
antes de entregarlo al helper, de modo que `podman run --env-file` puede abrirlo
desde el transient unit de usuario.

Fallos corregidos durante esta migración (ya resueltos en el RPM instalado):

- el helper usaba `systemctl --user` con opciones que sólo acepta
  `systemd-run`; corregido a `systemd-run --user --wait --collect --pipe`;
- los árboles de almacenamiento creados por versiones anteriores de Fleet
  pertenecían a root y el helper fallaba con `permission denied`; corregido con
  la migración de propiedad descrita arriba.

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
