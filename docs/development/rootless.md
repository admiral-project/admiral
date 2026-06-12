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
