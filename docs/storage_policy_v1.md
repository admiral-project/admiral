# Storage Policy v1 — Grace Period & Emergency Quota

## Decisión de Arquitectura

El manejo de almacenamiento en Admiral sigue un modelo de **soft fail con período de gracia**, evitando un hard fail inmediato cuando una aplicación supera el límite de almacenamiento incluido en su tier.

La separación de responsabilidades sigue los principios del producto:

- **admiral-fleet**: mide, notifica y ejecuta órdenes técnicas.
- **admirald**: mantiene la máquina de estados, aplica política y audita.
- **admiral-harbor**: experiencia comercial, billing y notificaciones al usuario (fase posterior).

---

## Umbrales por Aplicación

| Uso del límite del tier | Estado | Acción |
|--------------------------|--------|--------|
| < 60% | `storage_ok` | Sin alerta |
| >= 60% | `storage_warning` | Aviso preventivo |
| >= 80% | `storage_critical` | Advertencia destacada |
| >= 90% | `storage_critical` | Advertencia urgente |
| >= 100% (soft quota) | `storage_over_quota` | Iniciar período de gracia |
| Fin del período de gracia | `storage_suspended` | Pausar la app |
| >= emergency quota | `storage_suspended` | Pausar la app inmediatamente |

## Emergency Quota

El crecimiento no puede ser ilimitado durante los 5 días de gracia. Se define un **emergency quota**:

```
emergency_quota = min(soft_quota × 1.20, soft_quota + 2GB)
```

Ejemplo:

- Tier 10 GB → soft quota 10 GB → emergency quota 12 GB
- Tier 50 GB → soft quota 50 GB → emergency quota 60 GB

Si la app alcanza el emergency quota antes de que terminen los 5 días, se pausa inmediatamente.

## Período de Gracia

- Comienza cuando la app supera el 100% del almacenamiento incluido.
- Duración: **5 días corridos**.
- Durante el período:
  - La app sigue funcionando (a menos que alcance el emergency quota).
  - El usuario puede liberar espacio o subir de tier.
- Al vencimiento: la app se pausa automáticamente.
- Los volúmenes, backups y datos permanecen intactos.
- La reactivación requiere liberar espacio o cambiar de tier.

## Umbrales Globales por Nodo

Además del límite individual por app, fleet monitorea el disco global del worker:

| Uso global del nodo | Acción |
|---------------------|--------|
| >= 70% | Registrar advertencia operativa |
| >= 80% | Notificar a administradores |
| >= 90% | Nodo degradado: no aprovisionar nuevas apps |
| >= 95% | Medidas de emergencia según política |

## Máquina de Estados (`customer_apps.storage_state`)

```
storage_ok ──> storage_warning ──> storage_critical ──> storage_over_quota
                                                              │
                                                              ├──> storage_grace_period ──> storage_suspended
                                                              │         │                          │
                                                              │         ├── emergency quota hit ───┘
                                                              │         └── usuario libera/sube ──> storage_ok
                                                              │
                                                              └──> storage_suspended (si quota de emergencia se alcanza antes)
```

## Eventos Auditables

Cada transición de estado registra una operación con `action` descriptiva:

- `storage_warning_detected`
- `storage_critical_detected`
- `storage_quota_exceeded`
- `storage_grace_period_started`
- `storage_grace_period_expired`
- `storage_emergency_limit_reached`
- `app_suspended_due_to_storage`
- `app_reactivated_after_storage_recovery`

## Columnas Reales en `customer_apps` (Esquema de Base de Datos)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `storage_state` | TEXT | Estado de almacenamiento (e.g., `ok`, `warning`, `critical`, `over_quota`, `suspended`, `unknown`). Durante el período de gracia activo, el valor registrado es `over_quota` con una fecha límite en `grace_period_ends_at`. |
| `emergency_limit_bytes` | BIGINT | Límite de cuota de emergencia calculado (`storage_emergency_bytes` a nivel conceptual). |
| `grace_period_starts_at` | TIMESTAMP (nullable) | Inicio del período de gracia (`storage_grace_started_at` conceptual). |
| `grace_period_ends_at` | TIMESTAMP (nullable) | Fin del período de gracia (`storage_grace_expires_at` conceptual). |

*Nota:* No existe una columna física `storage_paused_reason` en la base de datos de `customer_apps`. En su lugar, cuando una aplicación es pausada por exceder los límites de almacenamiento o expirar su periodo de gracia, su `technical_status` general se actualiza a `paused_for_storage`.

## Columnas Nuevas en `nodes`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `storage_state` | TEXT | `ok`, `warning`, `degraded`, `emergency` |

## Flujo Completo

```
fleet (cada heartbeat)
  │
  ├── mide uso de volumen por app
  ├── calcula porcentaje vs tier.Storage
  ├── detecta cambio de estado
  └── envía StorageEvent en HealthReport
        │
        ▼
admirald
  │
  ├── actualiza customer_apps.storage_state
  ├── si over_quota: inicia grace period, calcula emergency_quota
  ├── si emergency alcanzado: encola ActionPauseAppStorage
  ├── si grace vencido: encola ActionPauseAppStorage
  ├── si nodo degradado: evita nuevos provisionamientos
  └── registra eventos auditables en operations
        │
        ▼
admiral-harbor (fase posterior)
  │
  ├── muestra alertas en UI
  ├── notifica por correo
  ├── permite subir de tier
  └── muestra countdown de grace period
```

## Priorización de Implementación

1. **Fase 1 (fleet)**: Medición, detección, notificación en heartbeat.
2. **Fase 2 (admirald)**: Máquina de estados, grace period, emergency quota, scheduling.
3. **Fase 3 (admiralctl)**: Visibilidad para el operador.
4. **Fase 4 (harbor)**: Experiencia de usuario final (posterior).
