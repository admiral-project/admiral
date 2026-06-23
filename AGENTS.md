# Proyecto Admiral

Admiral es una PaaS simple orientado a facturación para agencias que quieren operar SaaS
sobre Linux con Podman, systemd y PostgreSQL, escalable de 1 a N nodos.

## Componentes

- `admirald`: control plane y fuente de verdad — estable.
- `admiral-fleet`: ejecución local en nodos workloads — estable.
- `admiralctl`: operación técnica por terminal — estable.
- `admiral-flagship`: consola administrativa web — estable.
- `admiral-harbor`: portal de cliente - verificar flujo real con paypal.

El desarrollo se da en el repositorio `admiral` donde se coordina el desarrollo de todo el conjunto
como un solo proyecto.

## Decisiones de arquitectura vigentes

- Go para `admirald`, `admiral-fleet` y `admiralctl`.
- Python/Flask para `admiral-flagship` y `admiral-harbor`.
- Podman rootless para workloads.
- systemd y Quadlet para persistencia de servicios.
- PostgreSQL para estado y cola duradera.
- RPM como formato de distribución (EL10 y Fedora Soportados).
- VPN con WireGuard.

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
- `admiral-harbor` es portal de cliente y no administra ni conoce infraestructura.

La etapa actual del proyecto es:

- **Beta** (2026-06-23). Todos los componentes funcionales.
- Single-node E2E validado.
- Multi-node E2E validado (un nodo admin con admirald + harbor / N node workers).
- RPM disponible en https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/.
- Storage quota notification por email (harbor worker async).
- Pendiente para 1.0: pago verificado con PayPal real.

## Project Context

Admiral is intentionally simple. It is not Kubernetes, does not try to replace Kubernetes, and must avoid unnecessary orchestration complexity.

The platform is built around existing Linux technologies:

- Go for core services and CLI tools.
- Python for web apps.
- Podman for rootless containers and pods.
- systemd for service supervision.
- PostgreSQL for persistent state.
- RPM packaging for Fedora and Enterprise Linux.
- Fedora and Enterprise Linux compatible systems as the target runtime.

## Product Principles

When contributing to this repository, prioritize:

1. Simplicity over cleverness.
2. Explicit behavior over hidden magic.
3. Safe defaults.
4. Auditability.
5. Predictable operations.
6. Clear errors.
7. Idempotent task execution where possible.
8. Compatibility with Fedora and Enterprise Linux.
9. Integration with Podman and systemd instead of reinventing them.
10. Billing-aware platform behavior without embedding payment-provider logic into low-level components.
11. Secure by default.


## Distribution Support Tiers

| Tier | Distribution | Role |
|------|-------------|------|
| **Tier 1** | EL10 (RHEL 10 / CentOS Stream 10) | Target primario. Mandatorio. |
| **Tier 2** | Fedora (44, rawhide) | Development. Upstream para EL11. Soportado, no recomendado para producción. |
| **Tier 3** | Amazon Linux 2023 | Best effort. **No instalable**: AL2023 no incluye Podman (solo Docker/containerd). Admiral requiere Podman para contenedores rootless. |

Policy:
- Bugs exclusivos de Tier 2 o Tier 3 tienen menor prioridad que los de Tier 1.
- Los spec files y parches no deben sacrificar claridad en EL10 por compatibilidad con tiers inferiores.
- Fedora es upstream para desarrollo e integración continua.
- Todos los RPM deben compilarse para **aarch64** y **x86_64**.

## Repository Role

Each Go repository has a clear product responsibility.

### admirald

`admirald` is the control plane.

It owns platform state, validates operations, exposes APIs, coordinates provisioning, dispatches tasks, receives task results, and maintains auditability.

`admirald` should not directly execute Podman commands on remote nodes. Execution belongs to `admiral-fleet`.

### admiral-fleet

`admiral-fleet` is the worker agent.

It runs on workload nodes and executes authorized tasks received from `admirald`. It interacts locally with Podman, systemd, volumes, backups, and node-level resources.

`admiral-fleet` should not make business decisions. It should not decide whether a customer has paid, whether a subscription is valid, or whether an app should be suspended for commercial reasons. Those decisions belong to `admirald`.

### admiralctl

`admiralctl` is the CLI.

It communicates with `admirald` and provides commands for initialization, diagnostics, configuration, app management, node management, instance management, backup operations, and troubleshooting.

`admiralctl` should not bypass `admirald` by writing directly to the database or manipulating remote worker state directly.

## Architecture Rules

Follow these boundaries:

- Global state lives in `admirald`.
- Local execution lives in `admiral-fleet`.
- Terminal operations go through `admiralctl`.
- Long-running or destructive operations must be represented as operations/tasks.
- State transitions must be explicit.
- Operational actions must be auditable.
- Components must fail safely.
- Services must be manageable through systemd.
- Runtime behavior must be compatible with RPM-based installation.

Avoid hidden coupling between repositories. Public contracts between components should be documented and versioned.

## Technology Requirements

Use Go for all code in admirald, admiral-fleet and admiralctl submodules.

Prefer the Go standard library unless an external dependency provides clear value.

When adding dependencies:

- Choose maintained libraries.
- Avoid large frameworks unless justified.
- Avoid dependencies that make RPM packaging difficult.
- Avoid dependencies that require nonstandard runtime services.
- Keep transitive dependency count low.

Target Linux as the only runtime.

## Code Style

Use idiomatic Go.

All code must be formatted with:

```bash
gofmt
```

Recommended checks:

go test ./...
go vet ./...
golangci-lint run ./...

Use clear package names.

Avoid overly generic package names such as:

common
utils
helpers
misc

Prefer names that describe domain responsibility, for example:

config
api
auth
nodes
apps
tasks
operations
fleet
podman
systemd
backups

- Keep functions small and focused.
- Avoid clever abstractions before there are at least two real use cases.
- Error Handling
    - Errors must be explicit and actionable.
    - Prefer wrapping errors with context:
    - return fmt.Errorf("create pod %q: %w", podName, err)
    - Do not silently ignore errors.
    - Do not log and return the same error unless there is a clear reason.
    - CLI errors should be understandable to an operator.
    - API errors should be structured and should not leak secrets or sensitive internal details.
    - Worker errors should include enough context for troubleshooting task failures.
- Logging
    - Use structured logging where practical.
    - Logs should include relevant identifiers when available:
        - request_id
        - operation_id
        - task_id
        - node_id
        - instance_id
        - app_id
        - customer_id, only where appropriate and not sensitive
        - pod_name
        - service_name
    - Do not log secrets, tokens, passwords, private keys, payment credentials, or database credentials.
- Configuration should support:
    - Config files.
    - Environment variables.
    - Reasonable defaults for local development.
    - Explicit production configuration.
    - Do not hardcode production paths, credentials, domains, node IDs, queue names, or database URLs.
    - Configuration loading should fail clearly when required values are missing.
- Security is a core requirement.
    - Do not introduce code that:
        - Executes arbitrary shell commands from user input.
        - Accepts unauthenticated task execution.
        - Trusts remote input without validation.
        - Logs secrets.
        - Stores plaintext credentials unnecessarily.
        - Bypasses authorization checks.
        - Allows path traversal.
        - Pulls arbitrary images without policy checks where image policy applies.
        - Changes billing-sensitive state without auditability.
- Use least privilege where possible.
- Any component-to-component communication must be authenticated.
- Destructive operations must be explicit and auditable.

Database Rules

For repositories that use PostgreSQL:

Use migrations.
Do not modify schema implicitly at runtime.
Keep schema changes small and reviewable.
Use transactions for multi-step state changes.
Avoid business-critical state changes without audit records.
Use explicit timestamps.
Prefer stable internal IDs.

Do not allow admiralctl or admiral-fleet to write directly to the central Admiral database unless a documented architectural decision explicitly allows it.

Compatibility

The target deployment environment is:

Fedora.
Enterprise Linux compatible distributions.
Podman-based container runtime.
systemd-based service management.
RPM-based package installation.

Avoid assumptions specific to Docker.

Avoid assumptions specific to Debian/Ubuntu production environments.

Local development may support additional environments, but production behavior should target Fedora and Enterprise Linux first.

Packaging

The final software must be suitable for RPM packaging.

When adding files, consider:

systemd unit files.
default configuration files.
log paths.
data paths.
backup paths.
user/group ownership.
SELinux compatibility where applicable.

Do not assume the binary will always be run from the source tree.

Documentation

Update documentation when changing:

CLI commands.
API contracts.
configuration keys.
task payloads.
database schema.
operational behavior.
installation behavior.
security-sensitive behavior.

Documentation should be clear enough for a small software agency operator, not only for the original developer.

Backward Compatibility

During early development, breaking changes are acceptable, but they must be intentional.

When APIs, task payloads, config files, or database schemas change, update related documentation and tests.

Once a public release exists, compatibility should be managed through versioning and migrations.

Development Commands

Common commands:

go mod tidy
gofmt -w .
go test ./...
go vet ./...
go build ./...

Before committing, run:

gofmt -w .
go mod tidy
go test ./...

If the repository includes a Makefile, prefer:

- make fmt
- make test
- make build

Commit Guidelines

All commits MUST use semantic commit messages in English and MUST include a Signed-off-by trailer.

Semantic commit format:

type(scope): short description in imperative mood

Types:

- feat: a new feature
- fix: a bug fix
- docs: documentation only changes
- style: formatting, missing semicolons, etc; no production code change
- refactor: code change that neither fixes a bug nor adds a feature
- perf: performance improvement
- test: adding or correcting tests
- chore: changes to the build process, dependencies, or tooling
- ci: CI/CD configuration changes
- build: changes affecting the build system or external dependencies

Scope is optional but encouraged (e.g., `api`, `cli`, `fleet`, `db`, `auth`).

Good examples:

feat(api): add node registration endpoint
fix(fleet): handle heartbeat timeout gracefully
docs(cli): document JSON output flag
refactor(api): extract auth middleware into separate package

Avoid vague commits:

fix stuff
updates
work in progress
misc changes
Non-Goals

Do not add features that push Admiral toward unnecessary platform complexity without a clear requirement.

Non-goals for the early product:

- Kubernetes compatibility layer.
- Complex autoscaling.
- Multi-region orchestration.
- Service mesh.
- Custom container runtime.
- Full monitoring platform.
- Full CI/CD system.
- Arbitrary workflow engine.
- Cloud-provider-specific abstraction layer.

Admiral should remain focused on helping agencies sell and run SaaS applications using simple Linux infrastructure.

Decision Rule

When in doubt, choose the option that makes Admiral:

- Easier to install.
- Easier to operate.
- Easier to debug.
- Easier to package.
- Easier to secure.
- Less surprising.

The platform should feel boring, reliable, and practical.
