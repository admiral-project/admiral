# Análisis de seguridad — install.sh, playbooks Ansible y .spec

> Actualización: análisis profundo posterior a beta18. Incluye hallazgos
> nuevos sobre templates, systemd units, spec scriptlets y flujo de secrets.
>
> Revisión 2026-07-29: añadidos hallazgos derivados de la bitácora de
> validación `beta18.check.md` (single-node EL10 y topologías privadas KVM)
> y hallazgos transversales no cubiertos por la revisión anterior. Todos los
> hallazgos previos fueron re-verificados contra el estado actual del repo.

## Estado de remediación — 2026-07-29

Este documento conserva también hallazgos abiertos; una instalación exitosa no
los cierra automáticamente. El estado comprobado contra las fuentes es:

| Hallazgo | Estado | Evidencia |
|---|---|---|
| C1, peers WireGuard del hub | **Corregido y validado** | `peers.d/rocky-worker.conf` persistió el peer y sobrevivió una segunda ejecución de `install.sh --admin-node`; handshake activo. |
| H2, API administrativa de Caddy | Fix aplicado y probado en single-node | Socket Unix, `SupplementaryGroups=caddy`, ACL explícita y watcher `PathChanged`. |
| S3/firewall y M4/M5 | Fix aplicado; backup/restore real pendiente | Credenciales locales restringidas, variables limpiadas y egress permite endpoint S3 compatible. |
| H1, tokens en argv | Abierto | El registro de spokes todavía usa `admiralctl nodes register --token`. |
| H3, SSH `NOPASSWD` | Abierto por diseño | Sigue siendo el modelo bootstrap documentado. |
| M1/M2/M3/M6 y hallazgos bajos | Abiertos | Requieren cambios independientes; M6 necesita además una prueba S3 con TLS. |

La bitácora beta18 registra qué fixes fueron aplicados y cuáles fueron
validados en una topología completa; no se marcarán como resueltos los segundos
hasta cerrar el multinodo y el golden test correspondiente.

---

## 1. Hallazgo crítico nuevo

### C1. WireGuard hub pierde todos los peers al re-ejecutar el instalador

> Estado actual: **corregido y validado**. La descripción y la recomendación
> siguientes documentan el defecto original y no describen el comportamiento
> vigente. La prueba de re-convergencia se ejecutó con un worker conectado.

**Archivos**: `ansible/roles/admiral_wireguard/templates/wg-admiral.conf.j2`,
`ansible/roles/admiral_wireguard/tasks/main.yml:146-152`

**Descripción histórica**: La plantilla del hub generaba la lista de peers desde
`admiral_wireguard_peers | default([])`. Esta variable **nunca se popula en el
rol** `admiral_wireguard` — solo existe en el playbook separado
`wireguard-peers.yml`. Cuando el operador re-ejecuta `install.sh --admin-node`
(por ejemplo para aplicar actualizaciones), el rol despliega la plantilla con
peers vacíos y reinicia WireGuard, **desconectando todos los spokes**.

El flujo actual es:

1. `install.sh --admin-node` → Ansible despliega hub con 0 peers
2. `install.sh --worker-node` → agrega peer via `wg set` + `wg-quick save`
3. Re-run `install.sh --admin-node` → Ansible despliega hub con 0 peers → **DoS**

**Impacto**: Denegación de servicio de todos los nodos worker y portal.

**Recomendación histórica**: Antes de desplegar la plantilla en el rol, leer los peers
existentes desde `/etc/wireguard/peers.d/*.conf` (igual que hace
`wireguard-peers.yml:110-131`) y pasarlos como `admiral_wireguard_peers`.

---

## 2. install.sh — Fortalezas

- `set -euo pipefail`, trap EXIT/HUP/INT/TERM, limpieza de temporales
- Validación estricta de inputs: IPs, hostnames, node IDs, usuarios SSH, fingerprint SHA256, WireGuard subnet `10.99.0.0/24`
- S3 credentials parseadas con Python, validación de keys requeridas
- Secrets transferidos a Ansible vía JSON en archivo temporario `umask 077`
- `ssh-keyscan` read-only con verificación de fingerprint antes de confiar
- Verificación de usuario non-root + sudo antes de deshabilitar `PermitRootLogin`
- Security checklist post-instalación: SELinux, sshd, firewalld, audit, fail2ban, nftables, chrony, rootless Podman

## 3. install.sh — Hallazgos

| # | Archivo:línea | Hallazgo | Severidad |
|---|---------------|----------|-----------|
| I1 | `install.sh:724-826` | Secrets pasan por env vars a Python para construir JSON. `env` se hereda a procesos hijo y es visible en `/proc/<pid>/environ` del mismo usuario. Alternativa: escribir JSON directo desde Bash o usar fd anónimos. | **Media** |
| I2 | `install.sh:937` | `ssh ... sudo sh -c 'wg pubkey < /etc/wireguard/admiral.key'` — shell inline frágil. Si `INSTALL_PUBLIC_IP` fuese manipulable (no debería, está validado), habría inyección. | **Baja** |
| I3 | `install.sh:913` | `ssh ... "sudo sh -c '...'"` con heredoc para aplicar `PermitRootLogin no` — escaping complejo, un error silencioso dejaría root habilitado. El código posterior verifica, pero el patrón es frágil. | **Baja** |
| I4 | `install.sh:957` | `wg set wg-admiral peer "$SPOKE_KEY"` — `SPOKE_KEY` viene de stdout SSH. Si el nodo spoke está comprometido podría devolver una key maliciosa y establecer un peer no autorizado. Mitigación: la verificación WireGuard handshake posterior detecta falta de conectividad. | **Baja** |
| I5 | `install.sh:370-399` | **Sin verificación de permisos del archivo S3 credentials.** El archivo podría ser world-readable (`0644`) y el instalador lo acepta sin advertencia. Se recomienda verificar que no sea legible por grupo/otros. | **Media** |
| I6 | `install.sh:397-398` | **`S3_ACCESS_KEY_VALUE` y `S3_SECRET_KEY_VALUE` nunca se eliminan del entorno.** El bloque `unset` en líneas 843-847 limpia los secrets Harbor pero omite las variables S3. Permanecen en `/proc/<pid>/environ` hasta que el script termina. | **Baja** |
| I7 | `install.sh:67-73` | `is_loopback_host` solo verifica `127.0.0.1`, `localhost`, `::1`. No cubre `127.0.0.2`–`127.255.255.255` (toda la red `127.0.0.0/8` es loopback). Un valor como `127.0.0.2` se trataría como IP pública. | **Baja** |
| I8 | `install.sh:193-210` | El checklist de listeners debe excluir loopback, WireGuard, RFC-1918 y link-local; el contrato se mantiene directamente en el `awk` remoto del checklist. | **Baja** |
| I9 | `install.sh:958-970` | Indentación inconsistente (8 espacios vs 4 del bloque circundante). No es un bug funcional (bash no depende de indentación) pero dificulta la revisión y puede ocultar errores. | **Info** |
| I10 | `install.sh:116` | `install.env` se escribe con `0640` — contiene solo `ADMIRAL_PUBLIC_IP`, no es crítico. | **Info** |

## 4. Playbooks Ansible — Fortalezas

- SSH hardening comprensivo: `PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitEmptyPasswords no`, `X11Forwarding no`, `AllowAgentForwarding no`, `MaxAuthTries 3`, `LoginGraceTime 30`
- `no_log: true` en todas las tareas que manejan secrets
- `/etc/admiral/secrets` modo `0600`, ownership verificado (`admiral_common/tasks:466-479`)
- Secrets eliminados de nodos worker/portal después de instalación (`admiral_common/tasks:481-487`)
- PostgreSQL: `scram-sha-256`, SSL habilitado, listen `127.0.0.1` solamente
- CA private key eliminada de nodos spoke después de firmar certificado
- Firewall: egress filtering con nftables, default reject, política por perfil
- SELinux setenforce 1, booleans `httpd_can_network_connect` y `container_manage_cgroup`
- auditd con reglas específicas para `/etc/admiral`, secrets, TLS, data y WireGuard
- fail2ban: jail sshd, flagship y harbor, backend nftables, ban test con 192.0.2.1
- Cockpit bind a loopback (excepto dev-mode)
- Harbor bind a WireGuard IP o loopback
- WireGuard zone firewalld con target DROP
- IP forwarding deshabilitado (`net.ipv4.ip_forward=0`)
- dnf-automatic con `upgrade_type=security`, `apply_updates=yes`
- chrony para sincronización horaria
- Harbor: rotación de contraseña admin legacy, desactivación del usuario `admin` por defecto
- Ed25519 signing key generada por `admiralctl init --generate-signing-key`, leída desde archivo (no stdout)

## 5. Playbooks Ansible — Hallazgos

| # | Archivo:línea | Hallazgo | Severidad |
|---|---------------|----------|-----------|
| A1 | `admirald/tasks:17-43` | `admirald.ini` contiene TODOS los secrets en texto plano (db password, admin token, signing key, encryption key, etc.) modo `0600`. Necesario por diseño pero sería mejorable con `systemd-creds` o similar. | **Media** |
| A2 | `admiral_fleet/tasks:203-218` | `admiralctl nodes register --token <token>` — el token se pasa como argumento CLI, visible en `ps` en el nodo admin durante la ejecución. Mitigación parcial: `no_log: true` en Ansible. | **Baja** |
| A3 | `admiral_harbor/tasks:192-207` | Mismo problema: token de nodo Harbor visible en `ps` durante `admiralctl nodes register --token`. | **Baja** |
| A4 | `admiral_harbor/tasks:107` | `HARBOR_DATABASE_URL=postgresql://user:password@...` — contraseña PostgreSQL en texto plano en `harbor.env` modo `0600`. Mitigado por permisos, pero es información sensible persistente. | **Media** |
| A5 | `admiral_harbor/tasks:111-113` | `HARBOR_PAYPAL_CLIENT_ID=`, `HARBOR_PAYPAL_CLIENT_SECRET=`, `HARBOR_PAYPAL_WEBHOOK_ID=` se despliegan vacíos por defecto. El operador debe llenarlos. Si el archivo queda con permisos incorrectos, hay exposición. | **Baja** |
| A6 | `admiral_fleet/tasks:164-188` | `fleet.env` contiene fleet token y S3 keys en texto plano, modo `0600`. Mitigado por permisos. | **Media** |
| A7 | `admiral_common/tasks:523-541` | SSH admin user con `NOPASSWD: ALL` — documentado como intencional para Ansible. Cualquier compromiso de esa key SSH da root inmediato. | **Alta** por diseño |
| A8 | `admiral_common/tasks:553-563` | TLS SAN incluye la IP pública del nodo. Si el certificado se filtra, expone la topología. Bajo riesgo en la práctica. | **Baja** |
| A9 | `admiral_common/tasks:210` | `openssl rand -base64 36 \| tr '+/' '-_' \| tr -d '='` — genera password de PostgreSQL. Inconsistente con el resto que usa `-hex 32`. Entropía suficiente (~268 bits) pero no uniforme. | **Info** |
| A10 | `admiral_common/tasks:567-572` | CA autofirmada con `-days 3650` (10 años) y `-nodes` (sin passphrase). Esperable para automatización, pero cualquier root en nodo hub tiene acceso a la CA key. Mitigado: `0600`, removida de spokes. | **Info** |
| A11 | `admiral_wireguard/tasks:167-192` | WireGuard zone `admiral` con target DROP, correcto. Sin embargo, no hay rate-limiting en el plano WireGuard. | **Info** |
| A12 | `admiral_cockpit/tasks:54-61` | `openssl passwd -6 -stdin` con `no_log: true` — correcto, no expone la contraseña. | **Info** |

## 6. Templates Jinja2 — Hallazgos

| # | Archivo | Hallazgo | Severidad |
|---|---------|----------|-----------|
| T1 | `wg-admiral.conf.j2` | **Ver C1 (crítico)** — peers del hub se generan desde variable nunca populada en el rol principal. | **Alta** |
| T2 | `admiral-egress.nft.j2` | Egress permite TCP/587 (SMTP submission) desde todos los perfiles. Si Harbor no usa SMTP, es superficie innecesaria. Considerar condicional. | **Info** |
| T3 | `admiral-egress.nft.j2` | Worker/portal egress permite TCP/9000 (S3/MinIO). Sin validación de destino — cualquier host en TCP/9000 es alcanzable. Documentado como decisión de diseño (modelo Kubernetes). | **Info** |
| T4 | `admiral-tunnel@.service.j2` | SSH tunnel con `StrictHostKeyChecking accept-new` en `/etc/admiral/ssh/config`. TOFU sin fingerprint — un MITM en el primer arranque podría interceptar. El túnel está deshabilitado por defecto (`admiral_enable_ssh_tunnel=false`). | **Baja** |

## 7. Systemd units — Fortalezas

- `admirald.service`: `NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, `ProtectSystem=strict`, `ProtectProc=invisible`, `ProcSubset=pid`, `CapabilityBoundingSet=` (vacío), `MemoryDenyWriteExecute`, `RestrictRealtime`, `LockPersonality`, `RestrictSUIDSGID`, `DevicePolicy=closed`, `LoadCredential` para config
- `admiral-fleet.service`: hardening con capacidades mínimas necesarias (`CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETUID CAP_SETGID`), `PrivateDevices`, `DevicePolicy=closed`
- `admiral-harbor.service`, `admiral-flagship.service`, `admiral-harbor-worker.service`, `admiral-harbor-catalog-sync.service`: `NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, `ProtectSystem=strict`, `CapabilityBoundingSet=` (vacío), usuario/grupo `admiral`

## 8. Systemd units — Hallazgos

| # | Archivo | Hallazgo | Severidad |
|---|---------|----------|-----------|
| S1 | `admiral-fleet.service` | **Sin `User=`/`Group=`** — corre como root. Necesario por diseño (gestiona rootless Podman, subuids, systemd-machined), pero un compromiso de Fleet da root inmediato. `NoNewPrivileges=false` explícito. | **Alta** por diseño |
| S2 | `admiral-flagship.service:23` | `ReadWritePaths=/var/lib/admiral` — demasiado amplio. Harbor solo obtiene `/var/lib/admiral/harbor/uploads`. Flagship podría escribir en paths de otros servicios. | **Baja** |
| S3 | `admiral-harbor.service:23` vs `admiral-harbor-worker.service:21` | `ProtectHome=read-only` vs `ProtectHome=true` — inconsistente. El servicio principal puede leer `/home` pero el worker no. Alinear. | **Baja** |
| S4 | `admiral-flagship.service:21` | `ProtectHome=read-only` — mismo problema que S3. | **Baja** |
| S5 | `admiral-fleet.service:25` | `ProtectHome=read-only` — Fleet puede leer `/home`. Necesario para acceder a `/var/lib/admiral-apps` (home de admiral-apps), pero podría restringirse con `BindPaths` o `BindReadOnlyPaths`. | **Info** |
| S6 | Caddy admin API | `admin 127.0.0.1:2019` — HTTP plano sin autenticación. Solo loopback, pero **cualquier proceso local** puede reconfigurar rutas de Caddy. Admirald lo usa sin auth header. Considerar socket Unix con permisos. | **Media** |

## 9. RPM Specs — Fortalezas

- `admirald` y `admiral-fleet` compilados con `-buildmode=pie` (binarios independientes de posición)
- Binarios stripped (`-s -w`)
- System accounts creados via `sysusers` (RPM declarativo, no scripts ad-hoc)
- SELinux `restorecon` en `%post` para paths de Admiral
- `container_file_t` para storage rootless
- `%systemd_post`/`%systemd_preun`/`%systemd_postun_with_restart` correctos
- Directorios con ownership y permisos específicos
- Config files marcados como `%config(noreplace)` — no se sobreescriben en upgrade
- `admiral-harbor.spec` tiene `%check` con pytest

## 10. RPM Specs — Hallazgos

| # | Archivo:línea | Hallazgo | Severidad |
|---|---------------|----------|-----------|
| R1 | `admiral-common.spec:115-119` | **`/usr/lib/tmpfiles.d/admiral-apps.conf` generado en `%post` no está en `%files`.** Queda huérfano al desinstalar el paquete. Debe ser un archivo empaquetado o limpiarse en `%preun`. | **Baja** |
| R2 | `admiral-common.spec:136` | **`semanage fcontext -a` nunca se revierte.** Al desinstalar, la regla SELinux persiste. Debe limpiarse en `%preun` con `semanage fcontext -d`. | **Baja** |
| R3 | `admiral-common.spec` | **Sin `%preun` ni `%postun`.** No hay limpieza de: tmpfiles.d, semanage fcontext, `loginctl enable-linger`. | **Baja** |
| R4 | `admiral-common.spec:106` | `ADMIRAL_APPS_UID=$(id -u admiral-apps)` — puede fallar si sysusers no creó el usuario antes de `%post`. En la práctica funciona por orden de rpm, pero es frágil. | **Baja** |
| R5 | `admiral-fleet.spec:67` | `loginctl enable-linger admiral-apps` duplicado en spec y en Ansible (`admiral_fleet/tasks:39`). Redundante. | **Info** |
| R6 | `packaging/config/fleet.env:9` | **`ADMIRAL_QUEUE_DATABASE_URL=__REQUIRED__` en el default del RPM pero no se usa en el código de producción** (solo en tests). La plantilla Ansible no lo incluye. Es un leftover que causa confusión. | **Baja** |
| R7 | `admirald.spec:42` | No usa `-buildvcs=false`. El binario puede contener info del VCS. | **Info** |
| R8 | `admiral-flagship.spec` | Sin `%check` — no se ejecutan tests Python durante el build. | **Info** |

## 11. Config defaults — Hallazgos

| # | Archivo | Hallazgo | Severidad |
|---|---------|----------|-----------|
| D1 | `packaging/config/harbor.env:16-17` | `HARBOR_PAYPAL_RETURN_URL` y `HARBOR_PAYPAL_CANCEL_URL` apuntan a `localhost:5000` — puerto de Flagship, no de Harbor (5001). Placeholder incorrecto que podría confundir al operador. | **Baja** |
| D2 | `packaging/config/harbor.env:18` | `HARBOR_SMTP_FROM=noreply@example.com` — placeholder visible. | **Info** |
| D3 | `packaging/config/harbor.env:19` | `HARBOR_EXTERNAL_URL=https://localhost:5000` — mismo problema de puerto. | **Baja** |

## 12. Firewall/egress — Hallazgos

| # | Archivo | Hallazgo | Severidad |
|---|---------|----------|-----------|
| F1 | `admiral-egress.nft.j2` vs firewalld `https` service | El checklist espera `udp/443` (HTTP/3 QUIC) pero el servicio firewalld `https` solo abre TCP/443. Caddy v2.7+ habilita HTTP/3 por defecto y bindea UDP/443, pero el firewall lo bloquea. Inconsistencia funcional, no de seguridad. | **Info** |
| F2 | `admiral-egress.nft.j2:34` | Worker/portal egress permite TCP/9000 a cualquier destino. Esto es necesario para S3/MinIO pero sin restricción de destino. Documentado como decisión de diseño. | **Info** |

---

## 13. Hallazgos derivados de la bitácora beta18 y transversales

Hallazgos identificados al contrastar el flujo real documentado en
`beta18.check.md` (validación single-node Rocky/CentOS/AlmaLinux 10 y setup
multinodo con WireGuard + MinIO) con el código actual de `install.sh`,
playbooks y templates. Se verificó además que las notas previas siguen
vigentes; aquí se documentan los nuevos y los que consisten en fortalezas
no enfatizadas.

### 13.1 Fortalezas adicionales a destacar

- `install.sh:636-642` **rechaza repos COPR sin `gpgcheck=1`**. Verifica el
  contenido de ambos `.repo` tras `dnf copr enable` y aborta si falta la
  verificación de metadatos firmados. Defensa en profundidad contra downgrade
  silencioso a paquetería sin firmar.
- `admiral_common/tasks:905-921` **crea la role Postgres vía stdin** de `psql`
  en lugar de argumentos CLI; la contraseña viaja por el pipe y no por `ps`.
  Comportamiento opuesto al problema documentado en H1/H2.
- `admiral_cockpit/tasks:54-61` **hash de password por stdin** con
  `openssl passwd -6 -stdin`; la contraseña nunca aparece como argv de proceso.
- `admirald/tasks:118-131` despliega `config.yaml` de `admiralctl` en
  `/root/.config/admiralctl/` con modo `0600` y `no_log`. El token admin queda
  restringido a root.

### 13.2 Hallazgos nuevos

| # | Archivo:línea | Hallazgo | Severidad |
|---|---------------|----------|-----------|
| B1 | `admiral_fleet/tasks:181-184`, `admirald/tasks:51-53`, `admiral-egress.nft.j2:21,34` | **Credenciales S3 en cleartext sobre la red de storage.** Las `ADMIRAL_S3_*_KEY` se entregan a Fleet y Admirald y viajan al endpoint S3/MinIO en TCP/9000 en plano (la bitácora beta18 levanta MinIO en `192.168.200.x:9000` sin TLS). Un atacante con presencia en la red privada de storage puede sniffar las claves de backup. No hay guía ni verificación de que el endpoint S3 use HTTPS. | **Media** |
| B2 | `admiral-egress.nft.j2:21,24` | **Egress permite SSH saliente (TCP/22) a cualquier destino** tanto en admin/single como en spokes. Un nodo admin comprometido podría pivotar por SSH o exfiltrar hacia infraestructura atacante. Es inusual permitir SSH saliente desde un control plane; revisar si es estrictamente necesario o acotar a destinos operativos. | **Baja** |
| B3 | `admiral_common/tasks:566-613` | **Sin renovación automatizada de certificados.** CA 3650 días (`-days 3650`), cert de servidor 730 días (`-days 730`). La generación es por `/creates`, no idempotente en cuanto a expiración. No existe timer ni helper tipo `admiral_https_setup` para rotar el cert interno antes de expirar; un operador despistadoque no re-corra `install.sh` a tiempo provoca falla silenciosa de TLS interno. | **Baja** |
| B4 | `admiral_common/tasks:566-572,576-580` | **CA y cert de servidor usan RSA 4096/2048.** Internal-facing; aceptable pero anacrónico frente al resto del stack (WireGuard es Curve25519). Migrar la CA y `admirald-key.pem` a Ed25519 reduce tamaño de cert/SAN, tiempo de handshake y alinea con el resto. Sin impacto de seguridad hoy. | **Info** |
| B5 | `admiral_harbor/tasks:107`, `admirald/tasks:23-24` | **Password Postgres embebido en URL de conexión.** `HARBOR_DATABASE_URL=postgresql://user:{{ password }}@host…` y `database_url = postgres://…`. Hoy es seguro porque los passwords se generan con `openssl rand -hex 32` (URL-safe). Si la generación cambia a incluir `@:/?#%&` el parser de URL cortaría o filtraría parte del secreto. Defensa: URL-encodear el password al interpolar o no embeberlo en la URL. | **Baja** |
| B6 | `install.sh:660-676` | **Parser frágil de `know_host.yaml` con `grep`/`awk`.** Resuelve `node_id` y `wireguard_ip` del spoke con `grep -A2 "^  ${ROLE_KEY}:" … \| awk '{print $2}'` sin fallback ni validación de YAML. Cualquier cambio del esquema (indentación, keys duplicadas en `nodes:` vs `next:`) puede devolver un valor erróneo silenciosamente y configurar el spoke con el WG-IP equivocado. Hay Python disponible; reusar `yaml.safe_load` como ya se hace con `notas.md` y el inventario de Ansible. | **Baja** |
| B7 | `install.sh:577` | **Root check desplazado.** `[[ $EUID -eq 0 ]]` ocurre después de `ssh-keyscan` y `preflight_remote_node_role` (líneas 532-574). Las operaciones remotas son de solo lectura y usan la llave del operador, pero un invocador no-root podría ejecutar el keyscan y el probe de rol en el spoke antes de que el script aborte localmente. Mover el check de EUID al inicio, antes de cualquier interacción SSH, refuerza semántica de errores y defensa en profundidad. | **Info** |
| B8 | `admiral_wireguard/tasks:118-127` | **`ip_forward=0` en el hub** es correcto solo porque los spokes limitan `AllowedIPs` a `10.99.0.1/32` (sin ruteo spoke↔spoke). Si en el futuro se habilita peer-to-peer en WG con `AllowedIPs` más amplios, el `sysctl=0` del rol rompería silenciosamente la conectividad. Añadir un `assert` que rechace `AllowedIPs` más amplios que `/32` en el hub si `ip_forward=0`, o documentar la restricción de topología en el template. | **Info** |
| B9 | `admiral_common/tasks:523-541` + `admiral_wireguard/templates/wg-admiral.conf.j2` | **Acceso por llave SSH = root inmediato en TODOS los nodos.** El usuario admin `opsa_*` recibe `NOPASSWD: ALL` en admin, worker y portal. La misma llave pública bootstrap desplegada en `install.sh` queda autorizada en cada spoke. Comprometer esa llave y/o la máquina del operador compromete TODO el cluster (todos los nodos son root via sudo). Mitigación: emitir llaves SSH distintas por rol/nodo, o un CA SSH con short-lived certs (OpenSSH `sshdial-cert`) en lugar de raw `authorized_keys` permanentes. | **Alta** por diseño |
| B10 | `admiral_harbor/tasks:192-207`, `admiral_fleet/tasks:203-218` | Reconfirma A2/A3: en beta18 el flujo de `admiralctl nodes register --token …` se ejecuta con el token como argv (visible en `ps` del admin durante la ventana de registro). La bitácora muestra registro exitoso pero no mide exposición; el riesgo sigue. Ver H1. | **Baja** |

### 13.3 Revisión contra las fuentes actuales — 2026-07-29

La revisión separa el estado del hallazgo de la evidencia que todavía falta:

| Hallazgo | Estado actual | Atención requerida |
|---|---|---|
| C1, peers WireGuard | **Corregido y validado** | Commit `613b2651497fd5032d4ce2f80a23928605d81147`; bootstrap creó el fragmento durable y la re-convergencia posterior conservó el peer y el handshake. |
| H2, API administrativa Caddy | **Corregido en fuentes y validado en single-node** | Ninguna corrección pendiente; actualizar evidencia si se recrea una VM antigua. |
| M4, permisos del archivo S3 | **Corregido en fuentes** | El instalador rechaza archivos legibles por grupo/otros; falta una prueba negativa documentada si se desea cerrar el test. |
| M5, limpieza de variables S3 | **Corregido en fuentes** | `install.sh` ejecuta `unset S3_ACCESS_KEY_VALUE S3_SECRET_KEY_VALUE`. |
| B7/N8, root check tardío | **Obsoleto** | El check de root está en la línea 7, antes de cualquier SSH. El hallazgo debe retirarse. |
| B1/M6, S3 sin TLS | **Abierto real** | No aprobar backup/restore de producción sobre MinIO HTTP; configurar TLS o documentar explícitamente el riesgo de laboratorio. |
| H1/B10, token en `argv` | **Abierto real, ventana de bootstrap** | Migrar el registro a stdin o a un mecanismo que no exponga el token en `ps`. |
| H3/B9, SSH con sudo total | **Abierto por diseño de bootstrap** | Reducir a credenciales temporales y por nodo; no afecta la comunicación Fleet↔Admirald. |
| M1/M2/M3 | **Abierto real, mitigado parcialmente** | Evaluar `systemd-creds`/credenciales temporales y eliminar exposición transitoria en `/proc`. |
| F1/N4, UDP/443 | **Pendiente funcional** | Abrir UDP/443 solo si se promete HTTP/3; no es un fallo del plano Fleet. |
| D1/D3 | **Abierto documental** | Cambiar los defaults PayPal/Harbor que todavía apuntan a `localhost:5000` cuando el servicio correspondiente usa 5001. |
| B6/L12, parser `know_host.yaml` | **Abierto de robustez** | Sustituir `grep`/`awk` por parseo YAML validado. |

Los restantes hallazgos de prioridad baja e informativa son mejoras de
endurecimiento o limpieza de empaquetado; no bloquean el golden WordPress.

---

## 14. Recomendaciones priorizadas

### Resueltos en fuentes

| # | Evidencia |
|---|---|
| C1 | `613b2651497fd5032d4ce2f80a23928605d81147`; el instalador persiste fragmentos en `peers.d` y el rol los conserva durante la reconciliación. |
| H2 | Caddy usa `/run/caddy/admin.sock`, ACL para `admiral` y `admiral-caddy-socket-permissions.path`. |
| M4 | `install.sh` verifica que el archivo S3 no sea legible por grupo u otros usuarios. |
| M5 | `install.sh` limpia las variables S3 después de generar los extra-vars. |
| B7/N8 | El check `EUID` está al inicio del instalador, antes de cualquier interacción SSH. |

### Críticas

| # | Acción | Archivos afectados |
|---|--------|-------------------|
| — | No quedan hallazgos críticos de código sin corregir. | `ansible/roles/admiral_wireguard/tasks/main.yml`, `wg-admiral.conf.j2` |

### Altas

| # | Acción | Archivos afectados |
|---|--------|-------------------|
| H1 | **Tokens en argumentos CLI**: migrar `admiralctl nodes register --token` a stdin o env var. | `admiral_fleet/tasks:203-218`, `admiral_harbor/tasks:192-207` |
| H2 | Resuelto: socket Unix con permisos de servicio y watcher. | `ansible/roles/admiral_common/tasks/main.yml`, `packaging/config/admirald.ini` |
| H3 | **Llave SSH → root en todo el cluster**: emitir llaves por rol/nodo o adoptar certificados SSH de corta vida签 con un CA SSH dedicado en vez de `authorized_keys` permanentes. Reducir blast radius si la llave bootstrap del operador se compromete. | `install.sh:523-525`, `admiral_common/tasks:523-551` |

### Medias

| # | Acción | Archivos afectados |
|---|--------|-------------------|
| M1 | **`admirald.ini` con todos los secrets en texto plano**: evaluar `systemd-creds encrypt` para secrets cifrados. | `admirald/tasks:17-43` |
| M2 | **`harbor.env` con DB password y PayPal secrets**: igual que M1. | `admiral_harbor/tasks:107` |
| M3 | **Secrets visibles en `/proc` durante install.sh**: escribir JSON directo desde Bash en lugar de pasar por env vars. | `install.sh:724-826` |
| M4 | Resuelto: el instalador rechaza credenciales S3 legibles por grupo u otros usuarios. | `scripts/install.sh` |
| M5 | Resuelto: las variables S3 se limpian después de escribir los extra-vars. | `scripts/install.sh` |
| M6 | **Forzar/requisar TLS en endpoint S3 de backup**: detectar scheme y rechazar `http://` para MinIO/S3 en producción, o guiar al operador a servir MinIO con TLS y permitir solo `https://` en el eggress. Cubre el caso de la bitácora beta18 (MinIO TCP/9000 sin TLS). | `admiral_fleet/tasks:181-184`, `admirald/tasks:51-53`, `admiral-egress.nft.j2` |

### Bajas

| # | Acción | Archivos afectados |
|---|--------|-------------------|
| L1 | **Shell inline frágil en spoke WG key exchange**: extraer la public key por SCP en lugar de `ssh cmd \| wg pubkey`. | `install.sh:937` |
| L2 | **`is_loopback_host` incompleto**: cubrir `127.0.0.0/8`. | `install.sh:67-73` |
| L3 | **El checklist de listeners debe excluir RFC-1918 y link-local**: mantener un único contrato en el `awk` remoto y cubrirlo con tests. | `install.sh:1228-1240` |
| L4 | **`%post` en spec frágil**: guards para `admiral-apps`, empaquetar tmpfiles.d como archivo, agregar `%preun` para limpieza. | `admiral-common.spec` |
| L5 | **`fleet.env` default con `ADMIRAL_QUEUE_DATABASE_URL` no usado**: remover del default del RPM. | `packaging/config/fleet.env` |
| L6 | **`ReadWritePaths=/var/lib/admiral` en flagship**: restringir a subdirectorio específico. | `admiral-flagship.service` |
| L7 | **Alinear `ProtectHome`** entre harbor service (`read-only`) y harbor worker (`true`). | `admiral-harbor.service` |
| L8 | **PayPal URLs placeholder con puerto incorrecto**: cambiar `localhost:5000` a `localhost:5001`. | `packaging/config/harbor.env` |
| L9 | **Acotar egress SSH saliente**: revisar si `tcp dport 22` en el egres admin/single es imprescindible; si no, retirarlo o limitarlo a destinos operativos. | `admiral-egress.nft.j2:21,24` |
| L10 | **Renovación de cert internos**: añadir timer/hook para detectar expiración del cert de `admirald` (730 días) y regenerar idempotentemente antes de expirar. | `admiral_common/tasks:566-613` |
| L11 | **URL-encode del password Postgres** al interpolarlo en `HARBOR_DATABASE_URL`/`database_url`, o separar password del DSN. | `admiral_harbor/tasks:107`, `admirald/tasks:23-24` |
| L12 | **Parser YAML robusto para `know_host.yaml`** en `install.sh`: reemplazar `grep`/`awk` por `python3 -c 'import yaml…'` con validación. | `install.sh:660-676` |
| L13 | **Aserción de topología en WG**: documentar o fallar si el hub recibe `AllowedIPs` más amplios que `/32` mientras `ip_forward=0`. | `admiral_wireguard/tasks:118-127`, `wg-admiral.conf.j2` |

### Información

| # | Acción |
|---|--------|
| N1 | `openssl rand -base64 36 \| tr '+/' '-_'` → cambiar a `-hex 32` por consistencia. |
| N2 | Duplicación de `loginctl enable-linger` entre spec y Ansible. |
| N3 | `-days 3650` en CA → aceptable para CA interna. |
| N4 | firewalld `https` service no incluye UDP/443 para HTTP/3 — inconsitencia funcional, no de seguridad. |
| N5 | SSH tunnel template usa `StrictHostKeyChecking accept-new` — TOFU sin fingerprint (deshabilitado por defecto). |
| N6 | `admiral-flagship.spec` sin `%check` — tests Python no ejecutados durante build. |
| N7 | Migrar CA y `admirald-key.pem` de RSA 4096/2048 a Ed25519 para alinear con WireGuard (Curve25519) y reducir tamaño/handshake. Internal-facing, sin impacto de seguridad hoy. |
| N8 | Mover el `[[ $EUID -eq 0 ]]` de `install.sh:577` al inicio del script, antes de cualquier `ssh-keyscan`/preflight remoto, para semántica de errores más clara y defensa en profundidad. |
