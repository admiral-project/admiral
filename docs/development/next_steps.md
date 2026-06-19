# Admiral: contexto vivo y próximos pasos

Este documento resume la documentación de desarrollo y la cruza con el estado actual del código.
Su objetivo es servir como contexto compacto para agentes de IA y personas, sin prometer cosas
que todavía no existen.

## Estado actual confirmado por código

- `admirald`, `admiral-fleet` y `admiralctl` están implementados como binarios Go.
- `admiral-flagship` está implementado como consola web Python/Flask con backend-for-frontend.
- `admiral-harbor` existe y está en fase temprana/pre-alpha.
- El empaquetado RPM está contemplado para los componentes principales.
- `admiral-fleet` ya usa Podman + systemd + Quadlet para ejecución rootless.
- `admirald` y `admiral-fleet` ya usan PostgreSQL como base de persistencia y cola duradera.
- El flujo oficial hoy es manual en instalación/configuración: los binarios soportan el workflow, pero requieren configuración explícita.

## Lo que la documentación antigua aún decía y ya no debe considerarse vigente

- Redis como parte obligatoria del baseline oficial.
- `admiral-flagship` como portal con lógica de negocio propia o acceso directo a datos.
- Modo de operación con promesas de automatización completas desde el primer día.
- Harbor como producto maduro; hoy no lo es.

## Resumen corto por archivo de desarrollo

### `docs/development/fase1.md`

Plantea arrancar por el control plane (`admirald`), luego el worker (`admiral-fleet`) y después la CLI (`admiralctl`).
La idea central sigue siendo válida: validar el flujo end-to-end sin introducir complejidad de orquestación innecesaria.

### `docs/development/fase2.md`

Define la dirección correcta del worker: Quadlet + systemd + Podman rootless.
Esto sí coincide con el código actual de `admiral-fleet`.

### `docs/development/fase3.md`

Describe backups, almacenamiento y autenticación administrativa en backend.
Sirve como hoja de ruta, pero no debe leerse como estado implementado completo.

### `docs/development/fase4.md`

Apunta a networking público con reverse proxy y routing.
Debe tratarse como trabajo futuro si la parte de routing público no está cerrada en código.

### `docs/development/fase5.md`

Consolida el backend administrativo y el modelo de operaciones.
Útil como contexto de diseño, pero hay que verificar cada afirmación contra `docs/api-v1.md` y el código antes de convertirla en verdad documental.

### `docs/development/fase7.md`

Describe `admiral-harbor` como portal de cliente.
Hoy debe leerse como intención de producto, no como capacidad madura.

### `docs/development/message_broker_refactor.md`

Este archivo sí marca una decisión importante ya incorporada al código: uso de PostgreSQL para la cola duradera.

### `docs/development/beta_known_limitations.md`

Sigue siendo útil, pero ahora el resumen corto y canónico es `docs/development/scope.md`.
`beta_known_limitations.md` puede quedarse como soporte detallado del scope validado.

### `docs/development/rootless.md`

Describe correctamente el modelo rootless de `admiral-fleet`.
La ejecución rootless con usuario dedicado y Quadlet es parte del estado real del worker.

## Resumen corto de AGENTS y PROYECTO

### `AGENTS.md` raíz

Fija las reglas del repositorio madre: integración de submódulos, documentación, empaquetado, pruebas end-to-end y coordinación de versiones.
El principio de fondo correcto es: simplicidad, explicitud, seguridad, auditabilidad y compatibilidad con Fedora/EL.

### `PROYECTO.md`

Es una visión de producto amplia.
Debe leerse con cuidado porque mezcla estado actual con aspiraciones antiguas.
Hoy la parte fiable es la separación de responsabilidades:

- `admirald`: control plane
- `admiral-fleet`: ejecución local
- `admiralctl`: operación por terminal
- `admiral-flagship`: consola administrativa
- `admiral-harbor`: portal de cliente en fase temprana

### `admirald/AGENTS.md`

Define correctamente que `admirald` es la fuente de verdad del sistema, valida operaciones y coordina tareas.
No debe prometer ejecución local directa.

### `admiral-fleet/AGENTS.md`

La intención de fondo es correcta, pero el texto viejo mencionaba un broker externo como transporte. Eso ya no refleja el código actual y debe considerarse obsoleto.

### `admiralctl/AGENTS.md`

Describe bien a la CLI como interfaz operativa.
La parte de ejemplos debe mantenerse alineada con el API real y con el modelo de operaciones asíncronas actual.

### `admiral-flagship/AGENTS.md`

Debe leerse como una consola administrativa delgada, no como un sistema autónomo.
No debe escribir en base de datos ni contener lógica de negocio propia.

## Próximos pasos reales

1. Reducir la documentación a una sola verdad por tema.
2. Eliminar de los textos de contexto cualquier mención a brokers externos como runtime oficial.
3. Alinear `PROYECTO.md` con el estado actual del código, no con el plan histórico.
4. Mantener `beta_known_limitations.md` como referencia operativa para el scope validado.
5. Consolidar `docs/development/scope.md` como la entrada corta para consultar el estado vigente.
6. Separar claramente:
   - implementación actual
   - decisiones ya cerradas
   - trabajo pendiente

## Pendientes que deben ir a `next_steps.md` porque aún no están cerrados en código

- Consolidar una versión única de la documentación de arquitectura.
- Revisar `PROYECTO.md` para eliminar contradicciones con el estado actual.
- Reescribir los resúmenes de `AGENTS.md` si alguna afirmación dejó de coincidir con el código.
- Verificar si `admiral-flagship` y `admiral-harbor` necesitan una página de estado operativa separada.
- Documentar formalmente la configuración manual mínima que hoy requieren los binarios.
