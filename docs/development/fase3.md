# Fase 3

Backend para operación y backups.

Lo que define esta fase:

- backups de bases de datos y volúmenes.
- retención y scheduler de backups.
- autenticación administrativa en `admirald`.
- metadata de backup trazable por instancia y tier.
- resiliencia cuando `admirald` no está disponible temporalmente.

Reglas clave:

- el tier pertenece a la app.
- cada backup conserva el `tier_snapshot`.
- no guardar secretos en claro.
- si no hay storage remoto configurado, usar fallback local.

Esta fase sigue siendo backend. No incluye UI web.
