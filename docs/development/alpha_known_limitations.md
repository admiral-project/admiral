# Admiral Beta - Known Limitations

Scope validado hoy:

- single-node (E2E backend probado).
- multi-node (revisión teórica de playbooks Ansible — site.yml, wireguard-peers.yml, roles por modo).
- Podman rootless.
- systemd/Quadlet.
- `admirald`, `admiral-fleet`, `admiralctl`, `admiral-flagship`, `admiral-harbor`.
- un conjunto curado de apps validadas.

Lo que sí está validado:

- health del control plane.
- provisioning, pause/resume, backup/restore, deprovision.
- routing público dentro del scope validado.
- storage quota notification vía email (harbor worker).
- migración de instancias entre nodos (flagship UI + admirald BFF).
- upgrade vía COPR RPM (`dnf upgrade admiral-platform`).

Límites conocidos (post-beta, tracking issues):

- validación multi-node E2E automatizada.
- failure testing automatizado.
- templates oficiales empaquetados (WordPress, ERPNext, Nextcloud, Cacao, NOW LMS).
- compatibilidad universal con cualquier app no garantizada.
- script `curl ... | bash` para bootstrap.
- catálogo de ejemplos debe ser conservador.

Frase de estado recomendada:

> Admiral está en beta. Funcional para producción single-node con supervisión. Limitaciones conocidas documentadas.
