# Modelo Rootless

Admiral adopta rootless Podman como decisión central de seguridad y operación. No es un detalle de implementación: es parte del modelo del producto.

## Decisión de arquitectura

- `admirald` mantiene el estado y valida operaciones.
- `admiral-fleet` ejecuta workloads locales como usuario rootless dedicado.
- `admiralctl` y las UIs consumen API; no acceden directo a infraestructura ni a la base de datos.
- El camino de ejecución principal usa Podman rootless, Quadlet y systemd.

## Costo operativo asumido

Levantar contenedores sin root exige preparación explícita del host. Admiral asume ese costo para ganar menos superficie de ataque y una operación más predecible.

La plataforma debe documentar y preparar:

- rangos `subuid` y `subgid` para el usuario rootless.
- `loginctl enable-linger` cuando corresponda al arranque persistente.
- directorios base con permisos de traversal mínimos.
- `chown` de los directorios de instancia al usuario rootless de ejecución.
- variables de entorno requeridas para Podman y systemd.

## Comportamiento esperado en el host

- No depender de un login interactivo para iniciar workloads.
- No ejecutar workloads con privilegios de root.
- Mantener aislamiento entre el plano de control y el plano de ejecución.
- Asegurar que los datos de cada instancia vivan en rutas dedicadas y auditables.

## Qué debe quedar explícito en el código y la documentación

- El usuario rootless de ejecución no es opcional.
- Los directorios de instancia no se pueden dejar con permisos amplios por conveniencia.
- El `chown` de instancias forma parte del aprovisionamiento normal.
- La preparación rootless del host es un requisito operativo, no un ajuste cosmético.

## Política operativa actual: `runuser` + `systemd-machined`

La ejecución rootless de Admiral no usa un único wrapper para todos los
subcomandos de Podman. La implementación actual es híbrida y eso debe quedar
documentado porque responde a fallos reales observados en host EL10.

### Regla actual

- `runuser` + `XDG_RUNTIME_DIR=/run/user/<uid>` para:
  - `podman run --rm`
  - `podman pod exists`
  - `podman container exists`
  - `podman container inspect`
  - `podman port`
  - healthchecks y helpers one-shot que usan `podman run`
- `systemd-run --machine <user>@ --user` para:
  - `podman exec`
- `systemd-run --user` sobre el bus del usuario rootless para:
  - `podman secret create`
  - `podman secret rm`

### Por qué no se unifica todo en `systemd-machined`

Porque no todos los subcomandos se comportan igual desde dentro de
`admiral-fleet.service`.

Hechos observados y validados:

- `podman exec` necesita la sesión systemd del usuario rootless para operar
  correctamente con contenedores creados por Quadlet y cgroup manager
  `systemd`.
- `podman secret create` y `podman secret rm` funcionan correctamente cuando
  se ejecutan dentro de un transient unit del usuario rootless usando
  `runuser`, `XDG_RUNTIME_DIR=/run/user/<uid>` y
  `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus`.
- `podman run --rm` lanzado por `systemd-run --machine` desde
  `admiral-fleet.service` ya mostró fallos como:
  - `Connection reset by peer`
  - `Transport endpoint is not connected`

Por eso Admiral mantiene una frontera explícita:

- operaciones ligadas a la sesión systemd del usuario rootless:
  `exec` y `secret`
- operaciones rootless simples y efímeras:
  `run`, `exists`, `inspect`, `port`

### Dependencia de host

`systemd-machined.service` debe estar instalado y corriendo para la ruta
basada en `systemd-run --machine` usada por `podman exec`.

En la validación viva de este ciclo:

- `systemd-machined.service` estaba instalado como unidad estática
- el servicio estaba `active (running)`
- `podman secret create` ejecutado dentro de un transient unit del usuario
  rootless funcionó correctamente cuando se llamó vía `runuser` +
  `systemd-run --user`

### Unitfile de `admiral-fleet`

El unitfile actual de `admiral-fleet.service` ya cubre lo necesario para la
ruta rootless validada:

- `NoNewPrivileges=false` para permitir los lanzamientos auxiliares que hace
  el agente
- `CapabilityBoundingSet=CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETUID CAP_SETGID CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW`
- `ReadWritePaths=/etc/containers/systemd/admiral /var/lib/admiral /etc/containers/systemd/users /run/user`

No hay evidencia de que falte una capability adicional para el fallo actual.
La ruptura observada en este ciclo está en la interacción entre el servicio y
el bus del usuario rootless, no en una capability Linux clásica. Si se rompe
la provisión rootless, revisar primero el transporte de systemd y el runtime
del usuario rootless antes de buscar ajustes en `CapabilityBoundingSet`.

### Implicación para troubleshooting

Si falla una provisión rootless, no asumir que "Podman rootless está roto" en
general. Primero identificar qué tipo de subcomando falló:

- si falla `exec`, revisar la ruta `systemd-machined`
- si falla `secret`, revisar la ruta del transient unit del sistema y el
  acceso al runtime rootless
- si falla `run`, `exists`, `inspect` o `port`, revisar la ruta `runuser` +
  `XDG_RUNTIME_DIR`

Esa distinción es parte del comportamiento esperado del sistema, no una
excepción accidental.
