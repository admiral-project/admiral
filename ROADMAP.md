# Roadmap — Admiral

> Estado actual verificado contra código fuente el 2026-06-17.
> Actualización parcial: refactor harbor role-separation (15 commits, +4 test files, +27 tests, customer.py eliminado). Pendiente: exports CSV, migraciones versionadas.

---

## Fase 1 — Production Readiness (obligatoria)

**Objetivo:** Que una agencia pueda instalar Admiral y operar clientes reales sin miedo.

### 1. Harbor E2E completo

- [x] Registro de cliente
- [x] Login de cliente
- [x] Compra / checkout con PayPal
- [x] Aprovisionamiento de instancia
- [x] Upgrade de tier
- [x] Downgrade de tier
- [x] Pausa de instancia
- [x] Resume de instancia
- [x] Backup (base de datos y volúmenes)
- [x] Restore desde backup
- [x] Cancelación / deprovision

**Resultado:** Suite E2E automatizada — backend validado en single-node.

### 2. Instalador oficial

- [x] Instalación via RPM (`dnf install admiral-platform`)
- [ ] Script `curl ... | bash` para bootstrap sin clonar repositorio

**Validado en:** Fedora, AlmaLinux, Rocky Linux, RHEL (vía RPM).

### 3. Seguridad por defecto

- [ ] WireGuard obligatorio entre nodos (implementado el modelo de red, falta enforce automático)
- [ ] Firewall automático (pendiente)
- [x] Certificados automáticos (certbot DNS-01 + Caddy ACME automation)
- [ ] Rotación de credenciales iniciales (pendiente)
- [x] Secrets fuera de archivos planos (AES-256-GCM en DB, `/etc/admiral/secrets` protegido)

**Resultado:** Escaneo externo no debe descubrir PostgreSQL, Redis, RabbitMQ, Fleet.

### 4. Multinodo

- [x] Topología documentada y soportada en código (WireGuard, migración offline)
- [ ] Validación E2E automatizada multi-nodo

**Topología objetivo:**
- **Principal:** admirald, admiralctl, flagship
- **Comercial:** harbor
- **Workers:** fleet

### 5. Backups reales

- [x] Crear backup (database + volumes, local y S3)
- [x] Descargar backup
- [x] Restaurar backup exitoso en entorno limpio

**Resultado:** Restore validado con verificación de checksum.

---

## Fase 2 — Operabilidad

**Objetivo:** Poder administrar decenas de clientes.

### 6. Observabilidad mínima

- [x] Health checks de pods (fleet → admirald cada 30s)
- [x] Heartbeat de nodos (fleet → admirald cada 30s)
- [x] Métricas de nodo (disco, RAM, pods activos/pausados/fallidos)
- [x] Estado visible desde Flagship (dashboard con capacidad, alerts, jobs recientes)

**Basta:** Node status, worker status, pod status, last backup, disk usage, CPU usage, RAM usage visible desde Flagship.

### 7. Auditoría

- [x] Registro de quién, cuándo, qué en tabla `audit_logs`
- [x] Para: deploys, upgrades, backups, restores, cambios de tier, pausas
- [x] Visible desde Harbor (admin audit log)
- [x] `X-Admiral-Admin-User` / `X-Admiral-Operator` en requests

### 8. Recuperación ante fallos

- [ ] Suite de failure testing automatizada
- [x] Caída de Harbor: clientes siguen funcionando (desacoplado)
- [x] Caída de Admirald: fleet bufferiza en outbox local
- [x] Caída de Worker: solo pods en ese nodo se ven afectados
- [x] Vuelve Worker: reconcile al arranque (fleet reconcilia estado local)

### 9. Idempotencia

- [x] Toda operación puede ejecutarse dos veces sin romper nada
- [x] Especialmente: deploy, backup, restore, pause, resume, upgrade
- [x] Basado en cola durable PostgreSQL con deduplicación por `task_id`
- [x] Callbacks con outbox local para reintento

---

## Fase 3 — Escalamiento comercial

**Objetivo:** Que una agencia pueda vender SaaS encima de Admiral.

### 10. Marketplace de aplicaciones

- [x] App definition YAML como contrato oficial con `name`, `version`, `tiers`, `volumes`, `environment`
- [x] Catálogo sincronizado desde admirald a harbor
- [x] UI de administración de apps en Flagship y Harbor

### 11. Catálogo de templates

- [ ] WordPress (implementado como ejemplo en docs, falta template oficial empaquetado)
- [ ] ERPNext
- [ ] Nextcloud
- [ ] Cacao Accounting
- [ ] NOW LMS

### 12. Billing sólido

- [x] Pago inicial (PayPal Subscriptions API)
- [x] Renovación (worker genera invoices mensuales)
- [x] Cancelación (desde portal cliente y admin)
- [x] Suspensión por impago (overdue policy configurable)
- [x] Reactivación tras pago
- [x] Webhooks PayPal verificados con firma
- [x] Métricas de MRR, churn, revenue en admin

---

## Fase 4 — Release 1.0

**Objetivo:** Declarar Admiral estable.

### Arquitectura

- [x] Single node validado (backend E2E probado)
- [ ] Multinodo validado (implementado en código, pendiente validación E2E)
- [ ] VPN validada (WireGuard modelado, pendiente validación)

### Operación

- [x] Backup validado (local + S3, database + volumes)
- [x] Restore validado (con verificación de checksum)
- [ ] Upgrade validado (pendiente script de actualización entre versiones)

### Seguridad

- [ ] Firewall validado (pendiente implementación automática)
- [x] Certificados validados (wildcard Let's Encrypt DNS-01 funcional)
- [x] Secrets gestionados (AES-256-GCM en reposo, rotation key protegida)

### Testing

- [~] Unitarios — 31 archivos de test ~147 tests (77 en harbor post-refactor)
- [ ] Integración — pendiente
- [x] E2E — backend single-node validado
- [ ] Failure testing — pendiente

### Comercial

- [x] Harbor completo — funcional con registro, catálogo, billing, soporte, LMS y separación estricta de roles admin/cliente
- [x] Billing completo — PayPal Subscriptions, invoices, overdue policy, métricas
- [ ] Catálogo completo — faltan templates empaquetados oficiales

---

## Resumen por proyecto (verificado contra código)

| Proyecto | Estado | Tests | Gaps detectados |
|---|---|---|---|
| `admirald` | ✅ Estable | 11 files | Ninguno |
| `admiral-fleet` | ✅ Estable | 8 files | Sin tests en `agent/` ni `storage/s3.go`; `StorageExceededAction` configurado pero no ejecutado |
| `admiralctl` | ✅ Funcional | 3 files | Faltan `instances show` e `instances inspect` (documentados pero no implementados) |
| `admiral-flagship` | ✅ Alpha sólido | 61 py + 51 js | Backup settings UI read-only; sin botón de migración en UI |
| `admiral-harbor` | ✅ Alpha sólido | 13 files | exports CSV rotos; migraciones sin versionar |
