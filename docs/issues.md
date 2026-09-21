# Issues accionables

Estado al 2026-09-21. Fuente: `gh issue list -R admiral-project/admiral --state open`.
Solo se listan issues que requieren acción (lab o implementación). #102 es el
tracker maestro y no requiere acción directa.

## Trabajo actual

Release `0.0.1rc2` en preparación: los cinco submódulos están versionados y
pineados, los seis specs usan `Release: 1` y los seis RPM ya están compilados
localmente con NEVRA y SHA-256. Falta publicación COPR y validación en guests.

## Validación en laboratorio (accionable ya)

| Issue | Título | Acción lab requerida | Estado del fix |
|---|---|---|---|
| #103 | test(release): re-validate Tier 1 matrix on alpha candidate RPMs | Matriz Rocky/Alma/CentOS 10, single + multinodo, golden WordPress desde COPR | Bloqueado hasta publicar COPR de `0.0.1rc2-1` |
| #109 | fix(installer): generated Harbor token rejected by Admirald | Single-node fresco: `harborctl ping` y catalog sync con token generado | Corregido; RPM `admirald-0.0.1rc2-1` pendiente COPR |
| #110 | fix(installer): dedicated portal registration uses undefined admin token variable | `--portal-node` dedicado registra el portal y continúa a route checks | Corregido; RPM `admiral-common-0.0.1rc2-1` pendiente COPR |
| #107 | fix(installer): define admin token for single-node admiralctl config | Confirmar en single-node que `Deploy admiralctl configuration` pasa y cerrar | Probablemente resuelto (`89a58a5`); runs de #109 llegaron a `failed=0` |
| #106 | test(billing): verify PayPal sandbox E2E flow as first alpha gate | Ciclo completo en guests limpios: producto/plan → checkout sandbox → webhook → provisión → upgrade/downgrade/pausa | Sin implementar evidencia |
| #105 | docs(ops): prove control-plane and workload recovery runbooks | Probar (no solo redactar): HTTPS DNS-01, backup off-node de secrets, S3, SMTP, renovación TLS, restore del hub en guests limpios | Runbook ampliado; falta evidencia operativa completa |
| #92 | sec(dr): add control-plane state backup and hub recovery runbook | Restore real del backup del control plane en guest limpio | Implementado (`b93cd1c`); restore documentado, falta evidencia real |
| #99 | sec(workloads): validate and prevent lateral access between instances | Experimento: dos instancias en el mismo worker, probar conectividad intra-host a puertos publicados (posible falso positivo) | Hipótesis sin probar |
| #97 | sec(wireguard): add per-peer preshared keys (+PSK) | Verificar `PresharedKey` por peer y handshake hub↔spoke en multinodo | Payload pinneado (`da57130`); falta evidencia en vivo |

## Implementar primero, laboratorio después

| Issue | Título | Bloqueador |
|---|---|---|
| #100 | sec(storage): document and verify disk encryption (LUKS) for customer data | Documentar prerequisito LUKS2 en workers; luego verificar en lab |
| #96 | sec(bootstrap): minimize and expire SSH delivery credentials | Implementar inventario/cleanup explícito; luego verificar en lab |
| #95 | sec(backups): immutable off-site backup profile and automated restore verification | Definir perfil S3 con Object Lock; luego probar restore | Perfil Object Lock Governance de 30 días implementado; falta verificación en S3 |
| #98 | sec(api): per-operator tokens with scope/expiry/revocation (`needs-work`) | Completar el modelo de operadores; luego validar scope/revocación en lab |
| #94 | sec(flagship): require single-use email verification code (`needs-work`, posible falso positivo) | Implementar MFA email; luego probar flujo de login |

## Sin laboratorio

| Issue | Título | Nota |
|---|---|---|
| #104 | build(release): reproducible release process for first alpha candidate | Seis RPM `0.0.1rc2-1` compilados localmente con NEVRA y SHA-256; falta evidencia COPR |
