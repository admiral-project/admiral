# Admiral

Plataforma PaaS ligera para agencias de software que quieren vender y operar aplicaciones SaaS usando Podman, systemd, PostgreSQL y Linux empresarial, sin la complejidad de Kubernetes.

## Estructura del proyecto

- `admirald/` — Control plane central (Go). API REST, orquestación, billing, backups, routing Caddy.
- `admiral-fleet/` — Worker agent (Go). Ejecuta pods con Podman Quadlets y systemd en nodos.
- `admiralctl/` — CLI administrativa (Go). Gestión de nodos, apps, instancias, backups y rutas.
- `admiral-harbor/` — Portal de clientes (Python/Flask/PatternFly). En desarrollo.
- `admiral-flagship/` — Consola admin (Python/Flask/PatternFly). Funcional e incluida en el flujo normal de instalación single-node.
- `PROYECTO.md` — Definición de producto, arquitectura y roadmap.
- `alpha_checks.md` — Matriz de validación alfa backend (46 casos).
- `REPLIT_REVIEW.md` — Análisis estático pre-alpha del backend contra el checklist.

## User preferences

- El usuario está muy satisfecho con análisis detallados y estructurados: tabla por componente, mapeo explícito de cada caso del checklist, identificación de riesgos con impacto y evidencia de código, y resumen ejecutivo claro al final. Mantener este nivel de profundidad y formato en futuros análisis de código.
