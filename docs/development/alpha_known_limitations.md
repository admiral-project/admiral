# Admiral Alpha - Known Limitations

Scope validado hoy:

- single-node.
- Podman rootless.
- systemd/Quadlet.
- `admirald`, `admiral-fleet`, `admiralctl`.
- un conjunto curado de apps validadas.

Lo que sí está validado:

- health del control plane.
- provisioning.
- pause/resume.
- backup/restore.
- deprovision.
- routing público dentro del scope validado.

Límites conocidos:

- validación multi-node incompleta.
- compatibilidad universal con cualquier app no garantizada.
- backup por servicio, no por app.
- catálogo de ejemplos debe ser conservador.

Frase de estado recomendada:

> Admiral está listo para alpha en single-node con limitaciones conocidas.
