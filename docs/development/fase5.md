# Fase 5

Documento de transición para la capa administrativa.

Idea central:

- `admirald` sigue siendo la fuente de verdad.
- `admiral-flagship` solo consume API y muestra estado.
- `admiralctl` conserva las operaciones técnicas más completas.

Regla práctica:

- no duplicar lógica de negocio en la UI.
- no acceder directo a base de datos.
- no ejecutar acciones de infraestructura desde el frontend.
