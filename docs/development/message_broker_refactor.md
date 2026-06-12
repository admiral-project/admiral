# Message Broker Refactor

Decisión vigente:

- un broker externo dejó de ser la cola runtime oficial.
- la cola duradera de tareas usa PostgreSQL.
- la base de la cola es separada de la base núcleo de `admirald`.

Bases lógicas:

- `admiral_core`
- `admiral_queue`

Regla de acceso:

- `admirald` puede acceder a ambas.
- `admiral-fleet` solo a `admiral_queue`.

La lógica de pickup usa `FOR UPDATE SKIP LOCKED`.

Variables heredadas del broker externo deben considerarse obsoletas.
