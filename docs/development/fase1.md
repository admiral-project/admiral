# Fase 1

Objetivo: validar el flujo mínimo de Admiral sin complejidad extra.

Orden recomendado:

1. `admirald` como control plane.
2. `admiral-fleet` como ejecución local.
3. `admiralctl` como interfaz operativa.

Principios:

- API y contratos primero.
- Seguridad por defecto.
- Podman y systemd como base de ejecución.
- PostgreSQL como persistencia y cola duradera.
- Sin brokers externos como dependencia runtime oficial.

La meta práctica sigue siendo simple:

`admiralctl` -> `admirald` -> `admiral-fleet` -> `podman` + `systemd`
