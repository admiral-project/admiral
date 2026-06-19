# Admiral Beta - Known Limitations

Scope validado hoy:

- single-node (E2E backend probado).
- multi-node (worker-node validado E2E con rootless Podman remoto).
- Podman rootless (validado: ejecución remota en worker-node).
- systemd/Quadlet.
- `admirald`, `admiral-fleet`, `admiralctl`, `admiral-flagship`, `admiral-harbor`.
- un conjunto curado de apps validadas (e2e-whoami probado).

Lo que sí está validado:

- health del control plane.
- provisioning, pause/resume, backup/restore, deprovision.
- routing público dentro del scope validado.
- storage quota notification vía email (harbor worker).
- migración de instancias entre nodos (flagship UI + admirald BFF).
- upgrade vía COPR RPM (`dnf upgrade admiral-platform`).
- **NUEVO** rootless Podman execution remota en worker-node.

Límites conocidos (post-beta, tracking issues):

- validación multi-node E2E automatizada.
- failure testing automatizado.
- templates oficiales empaquetados (WordPress, ERPNext, Nextcloud, Cacao, NOW LMS).
- compatibilidad universal con cualquier app no garantizada.
- script `curl ... | bash` para bootstrap.
- catálogo de ejemplos debe ser conservador.
- portal-node: task de Ansible usa `inventory_hostname` en lugar de `fleet_node_id` para registro.
- peers WireGuard no persisten al re-ejecutar playbook del hub.

Frase de estado recomendada:

> Admiral está en beta. Funcional para producción single-node con supervisión. Limitaciones conocidas documentadas.
