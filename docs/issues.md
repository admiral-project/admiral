# Issues accionables

Estado al 2026-09-21. Fuente: `gh issue list -R admiral-project/admiral --state open`.
Solo se listan issues que requieren acción (lab o implementación). #102 es el
tracker maestro y no requiere acción directa.

## Trabajo actual

Release `0.0.1rc2-3` en preparación: los cinco submódulos están versionados y
pineados, los seis specs usan `Release: 3` e incluyen los fixes #113 y #99;
#99 declara `Network=pasta` por pod rootless, sin bridge Netavark generado.
Falta compilar/publicar la nueva tanda en COPR y validar en guests.

El issue #99 está cerrado. La validación confirmó namespaces `pasta` separados:
un pod no comparte localhost ni alcanza los puertos internos de otro pod. Un
servicio que declara un puerto se publica intencionalmente en la IP WireGuard
del worker y puede recibir tráfico de otros workloads, igual que recibe tráfico
no confiable a través de Caddy. La aplicación publicada es responsable de su
autenticación y autorización. No se usa A → puerto publicado de B como prueba
negativa de aislamiento; la prueba negativa corresponde a localhost, puertos
no publicados, volúmenes y secretos.

El laboratorio abrió el issue [#113](https://github.com/admiral-project/admiral/issues/113)
contra RC2: el playbook remoto del portal termina correctamente, pero el
intercambio final de peers WireGuard falla porque el wrapper busca
`ADMIRAL_ADMIN_TOKEN`, mientras el inventario generado solo contiene
`ADMIRAL_INTERNAL_TOKEN`.

## Candidatos a cerrarse

Los issues #96, #97 y #98 fueron cerrados después de validar sus cambios y
registrar evidencia adicional en GitHub el 2026-09-22. #96 pasó un dry-run y
una limpieza real de claves Ed25519 temporales; #97 combinó los tests de PSK
con los handshakes multinodo de rc2-3; #98 pasó las pruebas de autorización de
scopes y expiración/revocación sobre admirald.

El trabajo local confirma la implementación de varios fixes, pero no sustituye
la validación del artefacto COPR ni la ejecución en guests. Los siguientes
issues son candidatos a cerrarse cuando completen su gate:

| Issue | Evidencia local | Gate de cierre |
|---|---|---|
| #107 | Fix en `89a58a5` y tests de contrato del instalador | Confirmar `Deploy admiralctl configuration` en single-node |
| #109 | Fix en `112f580` y tests locales del instalador | Probar `harborctl ping` y catalog sync con el RPM COPR |
| #110 | Fix en `112f580` y tests locales del instalador | Validar `--portal-node` dedicado con el RPM COPR |
| #104 | Seis RPM `0.0.1rc2-2` compilados localmente con NEVRA y SHA-256 | Completar exitosamente los seis builds COPR de `0.0.1rc2-3` |

La implementación de #92 y #95 también está completada localmente, pero no se
consideran candidatos inmediatos de cierre porque requieren restore real en un
guest limpio y verificación de Object Lock en S3, respectivamente. #105 además
requiere ejecutar el runbook completo.

## Validación en laboratorio (accionable ya)

| Issue | Título | Acción lab requerida | Estado del fix |
|---|---|---|---|
| #103 | test(release): re-validate Tier 1 matrix on alpha candidate RPMs | Matriz Rocky/Alma/CentOS 10, single + multinodo, golden WordPress desde COPR | Pendiente publicar `0.0.1rc2-3` en COPR; laboratorio en paralelo |
| #109 | fix(installer): generated Harbor token rejected by Admirald | Single-node fresco: `harborctl ping` y catalog sync con token generado | Corregido; validar con `0.0.1rc2-3` en COPR |
| #110 | fix(installer): dedicated portal registration uses undefined admin token variable | `--portal-node` dedicado registra el portal y continúa a route checks | Corregido; validar con `0.0.1rc2-3` en COPR |
| #113 | fix(installer): RC2 peer exchange reads missing `ADMIRAL_ADMIN_TOKEN` | Repetir portal dedicado y verificar resolución del token, intercambio de peers y handshake WireGuard | Fix en `9884b76`; validar `0.0.1rc2-3` en COPR y rerun |
| #107 | fix(installer): define admin token for single-node admiralctl config | Confirmar en single-node que `Deploy admiralctl configuration` pasa y cerrar | Probablemente resuelto (`89a58a5`); runs de #109 llegaron a `failed=0` |
| #106 | test(billing): verify PayPal sandbox E2E flow as first alpha gate | Ciclo completo en guests limpios: producto/plan → checkout sandbox → webhook → provisión → upgrade/downgrade/pausa | Sin implementar evidencia |
| #105 | docs(ops): prove control-plane and workload recovery runbooks | Probar (no solo redactar): HTTPS DNS-01, backup off-node de secrets, S3, SMTP, renovación TLS, restore del hub en guests limpios | Runbook ampliado; falta evidencia operativa completa |
| #92 | sec(dr): add control-plane state backup and hub recovery runbook | Restore real del backup del control plane en guest limpio | Implementado (`b93cd1c`); restore documentado, falta evidencia real |
| #97 | sec(wireguard): add per-peer preshared keys (+PSK) | Verificar `PresharedKey` por peer y handshake hub↔spoke en multinodo | Cerrado; payload pinneado (`da57130`), tests focalizados y handshake rc2-3 |

## Implementar primero, laboratorio después

| Issue | Título | Bloqueador |
|---|---|---|
| #100 | sec(storage): document and verify disk encryption (LUKS) for customer data | Documentar prerequisito LUKS2 en workers; luego verificar en lab |
| #96 | sec(bootstrap): minimize and expire SSH delivery credentials | Implementar inventario/cleanup explícito; luego verificar en lab | Cerrado; dry-run y limpieza real verificados |
| #95 | sec(backups): immutable off-site backup profile and automated restore verification | Definir perfil S3 con Object Lock; luego probar restore | Perfil Object Lock Governance de 30 días implementado; falta verificación en S3 |
| #98 | sec(api): per-operator tokens with scope/expiry/revocation | Completar el modelo de operadores; luego validar scope/revocación en lab | Cerrado; modelo, pruebas de scopes y expiración/revocación verificados |
| #94 | sec(flagship): require single-use email verification code (`needs-work`, posible falso positivo) | Implementar MFA email; luego probar flujo de login |

## Sin laboratorio

| Issue | Título | Nota |
|---|---|---|
| #104 | build(release): reproducible release process for first alpha candidate | Preparando seis RPM `0.0.1rc2-3`; falta compilación local y publicación COPR |
