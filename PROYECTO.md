# Proyecto Admiral

Admiral es una PaaS simple para agencias que quieren operar SaaS sobre Linux con Podman, systemd y PostgreSQL.

## Estado del producto

- `admirald`: control plane y fuente de verdad.
- `admiral-fleet`: ejecución local en nodos workloads.
- `admiralctl`: operación técnica por terminal.
- `admiral-flagship`: consola administrativa web, funcional e incluida en el flujo normal de instalación single-node.
- `admiral-harbor`: portal de cliente, en pre-alpha.

## Decisiones de arquitectura vigentes

- Go para `admirald`, `admiral-fleet` y `admiralctl`.
- Python/Flask para `admiral-flagship` y `admiral-harbor`.
- Podman rootless para workloads.
- systemd y Quadlet para persistencia de servicios.
- PostgreSQL para estado y cola duradera.
- RPM como formato de distribución.

## Principios

1. Simplicidad.
2. Comportamiento explícito.
3. Seguridad por defecto.
4. Auditabilidad.
5. Operación predecible.
6. Errores claros.
7. Compatibilidad con Fedora y Enterprise Linux.

## Qué debe recordar un agente

- `admirald` no ejecuta contenedores remotos.
- `admiral-fleet` no toma decisiones comerciales.
- `admiralctl` no escribe directo en la base.
- `admiral-flagship` es una UI delgada sobre la API.
- `admiral-harbor` es portal de cliente y no administra infraestructura.
