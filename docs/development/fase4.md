# Fase 4

Networking público de Admiral.

Objetivo:

- exponer apps por HTTPS.
- usar Caddy como reverse proxy.
- administrar rutas desde `admirald`.
- resolver hostnames automáticos por instancia.

Reglas:

- Caddy Admin API solo local.
- TLS automático por defecto.
- solo servicios marcados como `public: true` se publican.
- no introducir complexity tipo service mesh.

Estado del documento:

- esta fase describe dirección de producto; no debe interpretarse como totalmente cerrada en código si la implementación aún no coincide.
