# RC6 R26 — Final Security Review & Residual Risk Register

Fecha: 2026-10-29 UTC  
Candidato: RC6 E5 R26, x86_64  
Cambios de producto durante esta revisión: **NO**  
R26 invalidado: **NO**

## Veredicto

**Bueno para la topología y los controles probados; evidencia insuficiente para afirmar que todos los controles A–L estén validados.** En el alcance probado no se confirmó ninguna vulnerabilidad explotable CRITICAL o HIGH. Esto no es una afirmación de ausencia de defectos fuera de ese alcance.

El issue [#307](https://github.com/admiral-project/admiral/issues/307) conserva **82/111 PASS**, **19 PARTIAL**, **10 NOT TESTED** y **0 FAIL confirmado**. Los probes R26 de secretos en el Worker, SSH efectivo en los tres roles CentOS y binds efectivos de las APIs en los tres roles CentOS permitieron marcar J.1, J.2, H.3 y H.8. Los otros 29 controles sin marcar no tienen evidencia suficiente para marcarlos PASS. La sección L describe el alcance de validación y no contiene casillas.

R26 sigue congelado. Su matriz funcional continúa **6/6 PASS** y los seis repositorios conservan CI verde en los SHA del candidato. #307 y el tracker #308 siguen abiertos; por tanto, el release no se declara Gold. La aceptación de riesgos y el cierre de #307 corresponden al propietario.

## Candidato y evidencia de release preservada

Los SHA de checkout coinciden con los pins R26: root `b6146a46be93f1a9c242361e27b10dbbb2164bf6`; admirald `8efa1dec8e9540210d9f86d016dce4677dcc6543`; fleet `edc0a0d486eb102e9aaa4f250a08f777d7441f12`; admiralctl `d0e98414115c9628e59b33678cfcbd9bc0e342d5`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.

Las seis celdas Single-Node y Multi-Node de Rocky Linux 10, CentOS Stream 10 y Fedora Rawhide permanecen PASS sobre los RPM nativos R26. Los seis workflows CI correspondientes terminaron `success` para los SHA anteriores; véase el [comentario de CI y SHA exactos](https://github.com/admiral-project/admiral/issues/307#issuecomment-6486040680). AlmaLinux sigue fuera de la matriz por la limitación externa de tooling. PayPal (#106) queda fuera de este gate por depender de servicios externos.

## Estado A–L

Los 82 controles marcados en el cuerpo vigente de [#307](https://github.com/admiral-project/admiral/issues/307) se clasifican PASS con la evidencia publicada allí. Resumen por sección:

| Sección | PASS | PARTIAL | NOT TESTED | FAIL |
|---|---:|---:|---:|---:|
| A. Arquitectura y límites de confianza | 8 | 0 | 0 | 0 |
| B. Aislamiento entre clientes | 11 | 2 | 0 | 0 |
| C. Investigación `UserNS=auto` | 7 | 2 | 0 | 0 |
| D. SELinux y almacenamiento | 6 | 1 | 2 | 0 |
| E. Podman y Quadlet | 12 | 0 | 1 | 0 |
| F. systemd user manager | 5 | 1 | 1 | 0 |
| G. Fleet y operaciones privilegiadas | 8 | 2 | 0 | 0 |
| H. Baseline Ansible | 12 | 1 | 2 | 0 |
| I. Red, WireGuard y exposición | 3 | 6 | 1 | 0 |
| J. Secretos y backups | 6 | 1 | 3 | 0 |
| K. Autorización entre clientes | 4 | 3 | 0 | 0 |
| L. Validación proporcionada | N/A | N/A | N/A | N/A |
| **Total de casillas** | **82** | **19** | **10** | **0** |

Los siguientes controles no están marcados. PARTIAL significa que existe evidencia acotada, pero no cubre toda la afirmación; NOT TESTED significa que la prueba efectiva no se ejecutó o no quedó acreditada. Los checks marcados y su evidencia fuente se encuentran en el issue y sus comentarios enlazados.

| Control | Estado | Alcance o limitación |
|---|---|---|
| B.9 A no puede detener ni administrar contenedores de B | PARTIAL | El runtime control socket y los buses no aparecen en los snapshots de contenedores probados; no se ejecutó un intento de administración desde un workload A. |
| B.12 Servicios publicados respetan el contrato de red | PARTIAL | Se verificaron rutas positivas; no se probó el acceso entre workloads a puertos publicados. |
| C.4 Compatibilidad PostgreSQL, MariaDB, MySQL y web | PARTIAL | Se ejecutaron PostgreSQL y una aplicación web; MariaDB/MySQL no se probaron. |
| C.6 Backup, restore, rebuild, update y deprovision | PARTIAL | PostgreSQL backup/restore y deprovision pasaron; rebuild y update no se ejercitaron. |
| D.4 Etiquetas SELinux de volúmenes | PARTIAL | MCS de procesos y accesos cruzados están observados; las etiquetas efectivas de los paths de volumen Quadlet no quedaron capturadas. |
| D.6 Semántica de volúmenes privados/compartidos | NOT TESTED | No se probó el modo de volumen compartido soportado. |
| D.9 Revisión de AVC | NOT TESTED | No hay revisión archivada de los AVC del intervalo de workload R26. |
| E.9 Comportamiento ante OOM | NOT TESTED | No se provocó agotamiento de memoria para proteger al host y al laboratorio. |
| F.1 Alcance de un proceso comprometido respecto del user manager | PARTIAL | Los sockets/buses de control no estaban montados en los contenedores inspeccionados; no se hizo un intento directo contra el manager. |
| F.5 Aislamiento del resto ante una unidad fallida | NOT TESTED | No se inyectó una unidad fallida para medir impacto entre unidades. |
| G.1 Privilegios mínimos de Fleet | PARTIAL | Revisión estática y runtime respaldan límites existentes; no se determinó experimentalmente el conjunto mínimo de privilegios. |
| G.8 Minimización de secretos recibidos por helpers | PARTIAL | Hay cobertura de redacción de secretos conocidos; no hay inventario campo por campo del payload del helper. |
| H.9 Owner y modos de archivos de secretos | NOT TESTED | No se revisaron de forma completa los archivos sensibles instalados por Ansible. |
| H.10 Rotación de credenciales iniciales | NOT TESTED | No se probó el estado efectivo de todas las credenciales iniciales. |
| H.14 Idempotencia al reaplicar playbooks | NOT TESTED | No se hizo una segunda aplicación comparativa del baseline. |
| I.3 Exposición IPv6 frente a la política IPv4 | PARTIAL | Playbooks verificaron reglas dual-stack y los flujos normales; falta una sonda negativa desde una red externa. |
| I.4 Acceso efectivo tras revocar un nodo | PARTIAL | Existe evidencia de código y de revocación previa, pero no un probe live de revocación sobre R26. |
| I.5 Worker no administra Admin | PARTIAL | Se revisaron roles y reglas; no se intentó una operación administrativa desde Worker. |
| I.6 Portal no administra el runtime de Worker | PARTIAL | El flujo esperado fue probado; falta un intento negativo contra el runtime. |
| I.7 Comunicación legítima Worker–Portal | PARTIAL | Se verificó la topología y rutas normales; no se cubrieron todos los endpoints y direcciones. |
| I.8 Puertos de apps accesibles desde otros workloads | PARTIAL | El puerto privado de PostgreSQL fue inaccesible; no se hizo un probe cruzado de todos los puertos publicados. |
| I.10 Health checks como vía a redes internas | NOT TESTED | No se probaron destinos internos manipulados en health checks. |
| J.4 Secretos ausentes de logs, comandos y errores | PARTIAL | Pruebas focalizadas cubren secretos conocidos en rutas Fleet de command/inspect; no abarcan todos los logs y errores de la plataforma. |
| J.5 Permisos de archivos temporales | NOT TESTED | No se auditó este conjunto de archivos de forma efectiva. |
| J.6 Alcance mínimo de credenciales de almacenamiento externo | NOT TESTED | No se verificó el scope de cada credencial externa. |
| J.9 Rechazo de paths/objetos manipulados al restaurar | NOT TESTED | No se ejecutó este intento negativo. |
| K.1 Cliente A no consulta información privada de B | PARTIAL | Tests de ownership de handlers cubren rutas seleccionadas; no hubo ataque A→B live a la API privada. |
| K.5 Worker no reclama tareas de otro nodo | PARTIAL | CI/tests verifican binding `node_id` y firmas; no hubo intento live con otro nodo. |
| K.6 Tokens revocados dejan de autorizar | PARTIAL | Pruebas focalizadas de scopes/tokens pasaron; no hubo probe live de revocación de token de nodo. |

L no tiene checks individuales. Su validación proporcionada se cubrió con las tres VMs Multi-Node ya existentes, el flujo de cliente real, dos workloads A/B en el mismo Worker Fedora R26, PostgreSQL persistente, backup/restore y deprovision. No se repitieron las seis celdas para esta revisión de seguridad.

## Evidencia directa de aislamiento A/B

La corrida Fedora Rawhide Multi-Node R26 creó dos clientes Harbor reales en el mismo Worker con los RPM exactos. Los mapas rootless `auto` fueron distintos y sin solapamiento (`720896+1024` y `721920+1024`); los namespaces de red/PID y etiquetas SELinux MCS fueron diferentes. Los paths de datos PostgreSQL se separaron. A no pudo leer el marker ni el volumen de B, ni escribir en el volumen de B; las rutas/nombres de secretos PostgreSQL del otro cliente no estaban disponibles. El puerto PostgreSQL 5432 no estaba publicado y no era alcanzable desde A. Las rutas válidas del workload devolvieron HTTP 200 con TLS verificado. La limpieza posterior no encontró contenedores, pods, volúmenes, secretos, units, Quadlets ni paths de esas instancias.

Evidencia publicada: [pruebas A/B R26 en #307](https://github.com/admiral-project/admiral/issues/307#issuecomment-6480994640), [probe del driver de secretos](https://github.com/admiral-project/admiral/issues/307#issuecomment-6486556506), [SSH efectivo en los tres roles CentOS](https://github.com/admiral-project/admiral/issues/307#issuecomment-6486701478), [actualización de checklist y límites](https://github.com/admiral-project/admiral/issues/307#issuecomment-6486040680), y [resultado de las seis celdas en #308](https://github.com/admiral-project/admiral/issues/308#issuecomment-6485534608). Los logs y snapshots A/B están en `runtime/fedora-multi/`; los probes, scripts y guards están en `runtime/centos-multi/`. Ambos manifiestos SHA-256 pasan `sha256sum -c`.

La evidencia no demuestra que un contenedor A sea incapaz de administrar B bajo cualquier ataque imaginable; en particular, no hubo un intento live de invocar `systemd --user` o administrar una unidad ajena. Tampoco demuestra compatibilidad de todas las bases de datos o una política universal de red para apps publicadas.

## Probe adicional de secretos en CentOS R26

El 2026-10-29 se inició únicamente el Worker CentOS Stream 10 R26 existente. En el host, `admiral-fleet` era `5:0.0.1rc6-26.el10.x86_64`; Podman reportó 6.1.0; `admiral-apps` (UID 990) estaba rootless y su user manager activo. Se creó un secreto con contenido sintético no sensible, se inspeccionó su driver efectivo y se eliminó; una segunda inspección confirmó que ya no existía. Resultado: `effective_secret_driver=file`, `at_rest_classification=read_protected_file_not_encrypted`, `cleanup_verified=true`.

Esto acredita J.1 en el Worker CentOS R26 probado. J.2 PASS significa que el review documenta explícitamente que el driver observado no cifra el secreto en reposo y no infiere cifrado a partir de permisos. Permanece una discrepancia en `renderer.go:331`, que afirma “encrypted at rest”. El riesgo residual es MEDIUM si un atacante obtiene acceso al almacenamiento host o a una snapshot que contenga los archivos del driver; no es un escape entre workloads demostrado. El driver efectivo sólo se verificó en este Worker, no en los otros OS.

El probe, su script reproducible y el guard están en `runtime/centos-multi/security-podman-secret-driver-20261029.log`, `security-podman-secret-driver-probe.sh` y `security-resource-guard-20261029.jsonl`; sus SHA-256 se registraron en `R26-CENTOS-SECURITY-PROBE-SHA256SUMS.txt`. La definición persistida de la VM conserva las tres NIC, incluida la red `admiral-ipv6-validation`; la desconexión temporal de esa NIC fue `--live` solamente y permitió que el guest terminara `NetworkManager-wait-online` para esta prueba no relacionada con red.

## Probe de SSH efectivo en los tres roles CentOS R26

Con las VMs CentOS R26 existentes, una activa a la vez, se capturó `sshd -T` global y para el contexto de `validator` en Admin, Worker y Portal. `sshd` estaba activo en todos; los tres reportaron `PasswordAuthentication=no`, `KbdInteractiveAuthentication=no` y `PubkeyAuthentication=yes`. Admin permite root sólo por clave (`PermitRootLogin=without-password`); Worker y Portal tienen root login deshabilitado. La configuración coincide con el rol Ansible común R26, que establece `PermitRootLogin prohibit-password`, `PasswordAuthentication no` y `KbdInteractiveAuthentication no`.

La prueba marcó H.3 PASS para los tres roles CentOS Multi-Node. La revisión de la tarea Ansible común cubre el default en otras distribuciones, pero esta captura runtime no sustituye una prueba dinámica Fedora/Rocky. Log, script y guard están en `runtime/centos-multi/security-sshd-effective-20261029.log`, `security-sshd-effective-probe.sh` y `security-resource-guard-sshd-20261029.jsonl`; el primer intento con MAC incorrecto está conservado como fallo del harness y no se cuenta como resultado.

## Probe de binds de APIs internas en CentOS R26 — H.8 PASS

El 2026-10-29 se capturó `ss -H -lntp` en las tres VMs CentOS R26 Multi-Node existentes, una por vez, con la NIC IPv6 desconectada sólo durante la ejecución. Admin escuchó Admirald en `10.99.0.1:8080`, Caddy admin en `127.0.0.1:2019` y PostgreSQL en `127.0.0.1:5432`. Worker escuchó Fleet en `10.99.0.2:9099`. Esos binds coinciden con las interfaces previstas.

En la primera captura del Portal, Harbor aún ejecutaba el `ExecStartPre` de migración. Una segunda captura esperó a `ActiveState=active`: systemd reportó `active/running`, `Result=success`, `NRestarts=0`, `ExecStartPre` terminado con estado 0 y `ExecStart` con `--bind 10.99.0.3:5001`. El socket efectivo de Gunicorn fue exactamente `10.99.0.3:5001`; la interfaz `wg-admiral` tenía `10.99.0.3/24`. El único otro listener de aplicación fue PostgreSQL en loopback. El journal registró que Harbor arrancó y escuchó en esa dirección.

Por ello H.8 queda PASS para las APIs Admin/Worker/Portal probadas en CentOS Multi. Los reports E2E R26 de Rocky Multi, CentOS Multi y Fedora Multi además verificaron Harbor por su dirección WireGuard a través de Caddy con TLS estricto y HTTP 200. La configuración de bind es común al role Ansible; no se modificó producto ni candidato. La evidencia directa y sus hashes están publicados en el [comentario H.8](https://github.com/admiral-project/admiral/issues/307#issuecomment-6486833606). Los tres guests se apagaron ordenadamente y las definiciones guardadas conservan sus NIC.

El guard de la captura inicial registró 31 muestras, mínimo 4.36 GiB RAM y 41.16 GiB disco disponibles, sin alertas. El guard de la captura posterior registró 15 muestras, mínimo 4.41 GiB RAM y 41.10 GiB disco disponibles, sin alertas ni solicitudes de apagado.

## Decisión sobre `UserNS=auto`

R26 lo configura como default de instalación. En el escenario A/B probado, los pods recibieron rangos UID/GID distintos, además de namespaces y MCS distintos. Esto reduce el acceso accidental entre volúmenes de clientes y añade una capa útil de aislamiento con el modelo rootless existente. **Recomendación: conservar `UserNS=auto` en el candidato actual.** No es aislamiento frente a compromiso de la cuenta host `admiral-apps` o root: esas identidades siguen siendo un límite de confianza compartido y podrían administrar el almacén rootless.

La evidencia de workload cubre PostgreSQL y una aplicación web; no permite afirmar que MariaDB/MySQL o todos los entrypoints de terceros funcionen con los rangos y ownership del candidato.

## Hallazgo y riesgos residuales

### R1 — Secretos en reposo protegidos por permisos, no cifrados (MEDIUM residual)

En `admiral-fleet/internal/quadlet/renderer.go:331` el comentario de `renderSecretMounts` afirma que Podman mantiene los secretos “encrypted at rest”. El driver efectivo `file` se midió en el Worker CentOS R26 probado. La documentación actual de Podman describe `file` como archivo protegido por permisos y `pass` como archivo cifrado con GPG: [Podman `secret create`](https://docs.podman.io/en/latest/markdown/podman-secret-create.1.html). La revisión estática no encontró configuración de otro driver en Fleet/Ansible R26.

Los secretos del Worker medido están protegidos por permisos, no cifrados en reposo; el comentario de Fleet es inexacto. **Inferencia de riesgo:** quien tenga acceso root o acceso offline al archivo/snapshot del host podría leerlos; no comprobamos si la plataforma de almacenamiento cifra el disco. La prueba A/B no mostró acceso desde un contenedor de otro cliente. Es un riesgo MEDIUM condicionado a acceso al host storage, no un exploit cross-tenant reproducido. No se cambió código ni configuración por la congelación de R26; el propietario debe aceptar o rechazar el riesgo residual. No se encontró un CRITICAL/HIGH en este alcance.

### R2 — Compromiso de la cuenta host compartida

Todos los workloads del Worker se ejecutan bajo `admiral-apps`. `UserNS=auto`, SELinux MCS, namespaces, cgroups y ausencia de sockets de control dentro de los contenedores reducen las rutas de acceso directo observadas entre workloads. No eliminan el impacto de comprometer la cuenta host `admiral-apps` o root, que queda fuera del aislamiento entre contenedores. No se reprodujo una escalada desde contenedor.

### R3 — Controles operativos sin prueba efectiva completa

Permanecen sin prueba directa el efecto entre unidades systemd, el comportamiento OOM, algunas credenciales de guest, los negativos IPv6/roles/nodos y rutas de restore manipuladas. OOM se dejó sin ejecutar para no agotar RAM ni poner en riesgo el host. Los elementos se clasifican PARTIAL o NOT TESTED arriba; la ausencia de prueba no se presenta como vulnerabilidad.

## Recursos y cambios

Se reutilizaron sólo las VMs existentes; al cierre están apagadas. Los guards no registraron alertas ni solicitudes de apagado; el host quedó con 5.1 GiB RAM y 42 GiB disco disponibles. Las definiciones guardadas de las tres VMs conservan sus NIC. No se crearon VMs, no se indujo agotamiento, no se cambiaron fuentes, Ansible, installer, RPM ni configuración instalada. No hubo rebuild ni reinicio de celdas: `PRODUCT_CHANGED=NO`, `CANDIDATE_INVALIDATED=NO`.

## Recomendación al propietario

La evidencia permite revisar y decidir sobre el riesgo residual sin más hardening exploratorio. Antes de cerrar #307, el propietario debe aceptar o rechazar explícitamente el límite de confianza de `admiral-apps`, la falta de evidencia de cifrado en reposo y los controles PARTIAL/NOT TESTED. No se recomienda declarar Gold mientras #307 y #308 sigan abiertos. No hay un CRITICAL/HIGH confirmado dentro de las pruebas realizadas; no se afirma que los 111 controles hayan pasado.
