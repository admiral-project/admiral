# Admiral Beta - Known Limitations

Scope validado hoy:

- single-node (E2E backend probado).
- multi-node (admin + worker + portal — worker-node y portal-node validados E2E).
- Podman rootless (validado: ejecución remota en worker-node).
- systemd/Quadlet.
- `admirald`, `admiral-fleet`, `admiralctl`, `admiral-flagship`, `admiral-harbor`.
- un conjunto curado de apps validadas (e2e-whoami probado con provisioning completo).

Lo que sí está validado:

- health del control plane.
- provisioning, pause/resume, backup/restore, deprovision.
- routing público dentro del scope validado.
- storage quota notification vía email (harbor worker).
- migración de instancias entre nodos (flagship UI + admirald BFF).
- upgrade vía COPR RPM (`dnf upgrade admiral-platform`).
- rootless Podman execution remota en worker-node.
- portal-node reachable y registrado con admirald (fleet_offline es esperado para portal).
- pipeline completo provision → running verificado (instancia inst_a0d9fe7e113fc431 en worker-001).

Límites conocidos (post-beta, tracking issues):

- validación multi-node E2E automatizada.
- failure testing automatizado.
- templates oficiales empaquetados (WordPress, ERPNext, Nextcloud, Cacao, NOW LMS).
- compatibilidad universal con cualquier app no garantizada.
- script `curl ... | bash` para bootstrap.
- catálogo de ejemplos debe ser conservador.
- peers WireGuard en el hub se sobreescriben al re-ejecutar install.sh — peers previos se pierden.

Frase de estado recomendada:

> Admiral está en beta. Funcional para producción single-node con supervisión. Limitaciones conocidas documentadas.
