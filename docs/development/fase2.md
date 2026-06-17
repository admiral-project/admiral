# Fase 2

La dirección técnica del worker está definida por:

- Podman rootless.
- Quadlet para unidades persistentes.
- systemd como supervisor real.
- `SystemdPodmanExecutor` como camino de producción.
- `SimulatedExecutor` como camino de pruebas y desarrollo.

Modelo vigente:

- una instancia se traduce en un pod de Podman con sus contenedores y volúmenes.
- `admiral-fleet` genera Quadlet, recarga systemd y arranca o detiene las unidades.
- `admirald` mantiene el estado y la auditoría.

Configuración mínima:

- `ADMIRAL_FLEET_EXECUTOR`
- `ADMIRAL_FLEET_NODE_ID`
- `ADMIRAL_FLEET_QUADLET_DIR`
- `ADMIRAL_FLEET_DATA_DIR`
- `ADMIRAL_API_URL`
- `ADMIRAL_ADMIN_TOKEN`

Regla importante:

- no usar `podman run` como mecanismo persistente principal.
