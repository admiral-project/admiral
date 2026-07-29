# Admiral beta16 project status and validation check

Date: 2026-07-17
Workspace: `/root/admiral`

## Current project status

Admiral is in Beta and all six product repositories are functional. The
current release work has addressed the triaged security, reliability,
packaging, CLI, installer, and Harbor billing findings. The tracked GitHub
issue queue is empty: `gh issue list --state open` returns zero issues in
`admiral`, `admirald`, `admiral-fleet`, `admiralctl`, `admiral-flagship`, and
`admiral-harbor`. `ADM-SEC-062` (MFA) is intentionally closed as not planned
for the current release scope.

All new commits were created with semantic English commit messages and
`Signed-off-by: William Moreno Reyes <williamjmorenor@gmail.com>`. The latest
installer/documentation commits include:

- `ad8475c fix(installer): preserve Fleet token during convergence`.
- `866f2ea docs(status): update issue and golden test status`.
- The component fixes and packaging references are pinned in the superproject
  Makefile and RPM specs.

The individual component CI workflows previously completed successfully for
the current component revisions. Local installer checks also pass (`18`
tests). RPM packaging was performed with individual targets, never with
`make rpm`: `admiral-common-0.0.1beta16-5.el10.noarch.rpm` was built and
installed, and the Ansible single-node flow completed with `failed=0`.
Fleet configuration now contains both the task-signature public key and the
persisted node token, so convergence is idempotent and real task
authentication works.

## Golden single-node test

The approved flow was executed on the installed single-node host using the
demo WordPress application and real rootless Podman containers. The full
cycle completed successfully:

1. Provision: succeeded; workload containers were created by
   `admiral-fleet` using the `systemd-podman` executor.
2. Health/setup: instance reached `running`, `healthy`, with
   `setup_completed=true`.
3. Pause: succeeded.
4. Resume: succeeded.
5. Database backup: succeeded; backup ID was
   `bk_306018030f35b3a2`.
6. Restore with checksum verification: succeeded while the app was paused.
7. Deprovision: succeeded.

The four installed services—`admirald`, `admiral-fleet`, `admiral-flagship`,
and `admiral-harbor`—remain active after the cycle. This validates the
control-plane/Fleet handshake and the real rootless workload path, not merely
service startup.

## Validation scope still pending

No multi-node check has been performed with the latest binaries and RPM
references. The historical multi-node notes below describe an earlier beta
environment and must not be interpreted as current-binary multi-node
validation. A fresh admin/portal/worker multi-node run remains required
before claiming that release gate complete.

---

# Historical beta12/beta13 multinode check

Date: 2026-06-26
Workspace: `/root/admiral`
Admin VPS: `161.35.112.132`

## Beta13 release update

Date: 2026-06-27

- Bumped all Admiral components to `0.0.1beta13`.
- Committed component release bumps in the submodules:
  - `admirald`: `6dee59c` then `36452ce` for the logging test correction.
  - `admiral-fleet`: `8013eed`.
  - `admiralctl`: `cad24d5`.
  - `admiral-flagship`: `bbfec70`.
  - `admiral-harbor`: `8c678d6`.
- Pushed all submodule `main` branches to origin before packaging.
- Added multinode portal routing fixes:
  - Ansible now binds Harbor to `127.0.0.1:5001` only for `--single-node` or a supported same-host admin+portal installation.
  - Dedicated `--portal-node` binds Harbor to its WireGuard IP on port `5001`.
  - Portal-node installation updates the admin `admirald` override with the effective portal target and runs `admiralctl routes sync`.
  - `admirald` now allows replacing a default portal route target of `https://127.0.0.1:5001` with the Ansible-provided target while preserving custom targets.
- Corrected the existing `admirald/internal/logging` test to match the current secure behavior: sensitive values are fully masked as `****`.
- Updated release packaging:
  - `Makefile` version is `0.0.1beta13`.
  - All six Admiral specs use `Version: 0.0.1beta13`.
  - All six Admiral specs reset to `Release: 1%{?dist}`.
  - Monorepo-backed specs currently pin `%global commit` to the repo-mother commit that includes the `admirald` test fix.
  - `admiral-flagship` and `admiral-harbor` specs pin their submodule release commits directly.
- RPM rebuild started from a clean `packaging/build` after the logging test fix. The clean rebuild is expected to produce:
  - `admiral-common-0.0.1beta13-1.el10.noarch.rpm`
  - `admirald-0.0.1beta13-1.el10.x86_64.rpm`
  - `admiral-fleet-0.0.1beta13-1.el10.x86_64.rpm`
  - `admiralctl-0.0.1beta13-1.el10.x86_64.rpm`
  - `admiral-flagship-0.0.1beta13-1.el10.noarch.rpm`
  - `admiral-harbor-0.0.1beta13-1.el10.noarch.rpm`
- Clean RPM rebuild completed successfully and produced all six beta13 RPMs.
- Published the six beta13 SRPMs for COPR import over temporary HTTP on port 8000, then closed the port after import.
- Confirmed component CI with `gh`:
  - `admirald` `36452ce`: green.
  - `admiral-fleet` `8013eed`: green.
  - `admiralctl` `cad24d5`: green.
  - `admiral-flagship` `bbfec70`: green.
  - `admiral-harbor` `8c678d6`: green.
  - Repo mother `admiral` had no Actions run recorded for the beta13 packaging commit at the time checked.

## Beta13 common package follow-up

Date: 2026-06-27

- First COPR build of `admiral-common-0.0.1beta13-1` failed on upgrade because `%sysusers_create_package` was left literal in the generated RPM scriptlet:
  - Runtime error: `/var/tmp/rpm-tmp.*: line 1: fg: no job control`.
  - Root cause: COPR build environment did not have the sysusers macro available during spec parsing.
- Kept the sysusers macro approach and fixed packaging by adding `BuildRequires: systemd-rpm-macros`.
- Released `admiral-common-0.0.1beta13-2` and imported the SRPM into COPR.
- Re-ran `dnf --refresh update 'admiral*'`:
  - Admin node updated to `admiral-common-0.0.1beta13-2.el10`, `admirald-0.0.1beta13-1.el10`, `admiral-flagship-0.0.1beta13-1.el10`, and `admiralctl-0.0.1beta13-1.el10`.
  - Portal node updated to `admiral-common-0.0.1beta13-2.el10`, `admiral-harbor-0.0.1beta13-1.el10`, and `admiralctl-0.0.1beta13-1.el10`.
  - EL10 workers updated to `admiral-common-0.0.1beta13-2.el10`, `admiral-fleet-0.0.1beta13-1.el10`, and `admiralctl-0.0.1beta13-1.el10`.
  - Fedora worker still needs the Fedora `admiral-common` rebuild equivalent because COPR exposed `0.0.1beta13-1.fc44` during that update attempt.
- Re-ran `scripts/install.sh --portal-node` for `157.245.81.44` from the admin node with:
  - `--admin-endpoint 161.35.112.132`
  - `--node-id portal-001`
  - `--wireguard-ip 10.99.0.100`
- The portal-node playbook completed with `failed=0` and registered/synchronized the portal route to `https://10.99.0.100:5001`.
- Found one remaining idempotency bug: changing the Harbor systemd bind override did not restart an already running `admiral-harbor` service because the task used `state: started`.
- Manually restarted `admiral-harbor` on the portal node, after which Harbor listened on `10.99.0.100:5001` and responded `HTTP/1.1 200 OK`.
- Confirmed public portal recovery:
  - `https://portal.pinky.bmogroup.solutions` returned `HTTP/2 200`.
  - `admiralctl routes list --output json` showed the portal route as `healthy` and targeting `https://10.99.0.100:5001`.
- Fixed the playbook so Harbor restarts automatically when `/etc/systemd/system/admiral-harbor.service.d/override.conf` changes.
- Released `admiral-common-0.0.1beta13-3` with the Harbor restart fix and served `admiral-common-0.0.1beta13-3.el10.src.rpm` for COPR import over temporary HTTP on port 8000.

## Session summary

- Reviewed `scripts/install.sh`, Ansible playbooks, and `packaging/`.
- Confirmed multinode spoke installs are intended to run serially from the admin node.
- Confirmed `/etc/admiral/secrets` and `/etc/admiral/tls/ca.pem` are created during the first admin install.
- Confirmed `/var/lib/admiral/know_host.yaml` is regenerated by `admirald` after node registration and heartbeat syncs.
- Agreed that the preferred multinode flow is to pass explicit spoke parameters and keep `know_host.yaml` as operator sugar and fallback.
- Decided to update `admiral-common` before the real multinode run so `install.sh` and the packaged playbooks match the preferred operator workflow.
- Moved system account creation into `admiral-common` packaging via RPM `sysusers`, removing the temporary Ansible bootstrap workaround.
- Admin-node validation completed successfully on `161.35.112.132`.
- Portal-node validation completed successfully on `157.245.81.44`.
- Worker-001, worker-002, worker-003, and worker-004 all completed via `install.sh` after preinstalling `admiral-common-0.0.1beta12-8.el10` on each worker host.
- `worker-001` required an `admiral-fleet` restart after the bootstrap to clear a transient HTTP 401 heartbeat failure; it is now healthy.

## Findings from review

- `install.sh` needed explicit `--wireguard-ip` support for `--worker-node` and `--portal-node`.
- `install.sh` needed a better `--admin-node` default than persisting loopback for later spoke bootstraps.
- `admiral_wireguard` only rendered `wg-admiral.conf` on first install, which made retries and config changes brittle.
- `admiral_harbor` generated `harbor.env` with two misindented lines:
  - `ADMIRAL_CA_FILE`
  - `ADMIRAL_INSECURE_SKIP_VERIFY`
- `portal-node` registration happened before Harbor was installed and started.
- `install.sh` final portal verification missed Harbor timers.
- `admiral-common` should own `admiral` and `admiral-apps` system account creation through the RPM, not Ansible.
- `--single-node` must keep its current behavior.

## Runtime status

- Admin node: installed and active.
- Portal node: installed and active.
- Worker-001: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Worker-002: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Worker-003: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Worker-004: installed and active with `admiral-common-0.0.1beta12-8.el10`.
- Control plane snapshot shows worker-001 through worker-004 as `active` and `healthy` in `admirald`.

## Commands used during analysis

```bash
rg --files -g 'install.sh' -g 'ansible/**' -g 'packaging/**' -g 'Makefile' -g '*.md'
```

```bash
sed -n '1,240p' scripts/install.sh
sed -n '240,420p' scripts/install.sh
sed -n '1,220p' ansible/site.yml
sed -n '1,260p' ansible/roles/admiral_common/tasks/main.yml
sed -n '260,760p' ansible/roles/admiral_common/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_fleet/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_harbor/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_wireguard/tasks/main.yml
sed -n '1,220p' ansible/roles/admirald/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_flagship/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_firewall/tasks/main.yml
sed -n '1,220p' ansible/roles/admiral_selinux/tasks/main.yml
sed -n '1,220p' packaging/rpm/admiral-common.spec
sed -n '1,340p' Makefile
```

```bash
rg -n "know_host\\.yaml|next\\.worker|next\\.portal|wireguard_ip|nodes register|register node|known host" admirald admiralctl admiral-fleet ansible -S
sed -n '1,240p' /var/lib/admiral/know_host.yaml
sed -n '1,280p' admirald/internal/api/handlers_nodes.go
sed -n '140,220p' admirald/internal/api/api.go
```

```bash
bash -n scripts/install.sh
python3 - <<'PY'
import yaml
for path in ['ansible/site.yml', 'ansible/wireguard-peers.yml']:
    with open(path) as f:
        yaml.safe_load(f)
    print(path, 'YAML_OK')
PY
ansible-playbook ansible/site.yml -i ansible/inventory/localhost.yml --syntax-check -e admiral_install_mode=admin-node -e fleet_public_ip=161.35.112.132
```

## Preferred setup commands

Admin:

```bash
admiral_install --admin-node --public-ip 161.35.112.132
```

Portal:

```bash
admiral_install --portal-node \
  --public-ip 157.245.81.44 \
  --admin-endpoint 161.35.112.132 \
  --node-id portal-001 \
  --wireguard-ip 10.99.0.100 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

Workers:

```bash
admiral_install --worker-node \
  --public-ip 161.35.101.241 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-001 \
  --wireguard-ip 10.99.0.2 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

Worker-001 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@161.35.101.241:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@161.35.101.241 'dnf install -y /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

Worker-002 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@161.35.102.59:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@161.35.102.59 'rpm -Uvh --nodeps /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

Worker-003 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@159.223.163.220:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@159.223.163.220 'rpm -Uvh --nodeps /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

Worker-004 package refresh:

```bash
scp -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key /root/admiral/packaging/build/RPMS/noarch/admiral-common-0.0.1beta12-8.el10.noarch.rpm root@143.198.163.223:/tmp/
ssh -o StrictHostKeyChecking=accept-new -i /root/keys/ssh-key-2025-05-24.key root@143.198.163.223 'rpm -Uvh --nodeps /tmp/admiral-common-0.0.1beta12-8.el10.noarch.rpm'
```

```bash
admiralctl nodes list --output json
wg show wg-admiral
```

```bash
admiral_install --worker-node \
  --public-ip 161.35.102.59 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-002 \
  --wireguard-ip 10.99.0.3 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

```bash
admiral_install --worker-node \
  --public-ip 159.223.163.220 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-003 \
  --wireguard-ip 10.99.0.4 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

```bash
admiral_install --worker-node \
  --public-ip 143.198.163.223 \
  --admin-endpoint 161.35.112.132 \
  --node-id worker-004 \
  --wireguard-ip 10.99.0.5 \
  --ssh-key /root/keys/ssh-key-2025-05-24.key
```

## Verification commands

Admin:

```bash
systemctl is-active postgresql caddy admirald cockpit.socket
admiralctl nodes list --output json
wg show wg-admiral
cat /var/lib/admiral/know_host.yaml
```

Portal:

```bash
ssh -i /root/keys/ssh-key-2025-05-24.key root@157.245.81.44 \
  systemctl is-active postgresql admiral-harbor admiral-harbor-worker.timer admiral-harbor-catalog-sync.timer
```

Workers:

```bash
ssh -i /root/keys/ssh-key-2025-05-24.key root@161.35.101.241 systemctl is-active admiral-fleet
ssh -i /root/keys/ssh-key-2025-05-24.key root@161.35.102.59 systemctl is-active admiral-fleet
ssh -i /root/keys/ssh-key-2025-05-24.key root@159.223.163.220 systemctl is-active admiral-fleet
ssh -i /root/keys/ssh-key-2025-05-24.key root@143.198.163.223 systemctl is-active admiral-fleet
```

---

# Bitácora de control de calidad: sesión 2026-07-29

## Objetivo de la sesión

Iniciar la validación reproducible del instalador y del setup completo usando
máquinas virtuales KVM sobre el VPS de laboratorio. La prioridad acordada es
validar primero EL10 en modo `single-node`, en este orden:

1. CentOS Stream 10.
2. Rocky Linux 10.
3. AlmaLinux 10.

El criterio golden definido para cada setup es que `admiral-fleet` ejecute con
éxito al menos una instancia real de WordPress. Si aparece un error del
producto, la corrección debe hacerse en las fuentes, recompilar los RPM e
instalar los RPM locales mediante el flujo del instalador; no se deben aplicar
correcciones manuales de Admiral dentro de las VMs.

## Plataforma anfitriona

El trabajo se ejecutó en `/root/admiral`, sobre el siguiente VPS:

- Fedora Linux 44 Cloud Edition.
- Arquitectura `x86_64`.
- 8 vCPU.
- 16 GiB de RAM; aproximadamente 14 GiB disponibles al inicio.
- 8 GiB de swap.
- 320 GiB libres en `/`.
- KVM anidado disponible: `/dev/kvm` existe y el procesador expone `vmx`.
- El host ya era una VM KVM de DigitalOcean.

El repositorio estaba limpio antes de iniciar la preparación, salvo los
artefactos temporales creados durante esta sesión. No se modificaron fuentes
de Admiral ni se ejecutó aún el instalador dentro de una VM.

## Preparación de virtualización

Se comprobó que `virsh`, `virt-install`, `qemu-system-x86_64`, `qemu-img` y
`cloud-localds` no estaban disponibles inicialmente, y que `libvirtd` no
estaba activo. Se eligió QEMU/KVM directo con networking user-mode para evitar
modificar la red pública del VPS y mantener el laboratorio aislado.

Se instalaron en el host los paquetes:

```text
qemu-img
qemu-system-x86-core
edk2-ovmf
genisoimage
cloud-utils-growpart (ya estaba instalado)
openssh-clients (ya estaba instalado)
```

La instalación de estos paquetes terminó correctamente. La pila utilizada
publica SSH solamente mediante loopback del host y usa una imagen base
inmutable con overlays QCOW2 desechables.

## Imágenes EL10

Se descargaron las imágenes cloud oficiales `x86_64`:

- CentOS Stream 10:
  `CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2`.
- Rocky Linux 10:
  `Rocky-10-GenericCloud-Base.latest.x86_64.qcow2`.
- AlmaLinux 10:
  `AlmaLinux-10-GenericCloud-latest.x86_64.qcow2`.

Las tres imágenes reportaron formato QCOW2 y tamaño virtual de 10 GiB antes
de crear los overlays. Se descargaron los archivos oficiales de checksum.
Los SHA-256 calculados fueron:

```text
CentOS Stream 10: 193219fd15a9985cf6d23dab0732a39fa5d672b45566c0b78f28054c7ee247d0
Rocky Linux 10:   9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48
AlmaLinux 10:     47f2218668dd4776be140dd92fa3bea700be1766e2c7d88bdfd6a4b50f477b4d
```

Los tres valores coincidieron con los verificadores oficiales consultados.

## Primera VM iniciada

Se creó una VM Rocky Linux 10 de prueba con:

- 2 vCPU.
- 4 GiB de RAM.
- Overlay QCOW2 de 24 GiB sobre la imagen base.
- Semilla NoCloud con usuario `rocky`, sudo temporal y una clave SSH Ed25519
  temporal del laboratorio.
- SSH reenviado de `127.0.0.1:2222` del host hacia el puerto 22 de la VM.
- Disco y red virtio.
- QEMU/KVM con CPU del host.

La VM arrancó mediante QEMU. En el momento de cerrar esta parte de la sesión,
el proceso de espera todavía estaba esperando que SSH y `cloud-init` quedaran
listos; por tanto no se registra todavía como una validación exitosa ni como
un fallo de Admiral. No se llegó a ejecutar `admiral_install` ni el golden
test dentro de esta VM.

## Estado de validación al cierre de la sesión

| Validación | Estado | Evidencia |
|---|---|---|
| Capacidad KVM del VPS | completada | `/dev/kvm`, 8 vCPU, 16 GiB RAM |
| Herramientas QEMU | completada | paquetes instalados correctamente |
| Imagen CentOS Stream 10 | preparada | descarga y SHA-256 coincidente |
| Imagen Rocky Linux 10 | preparada | descarga y SHA-256 coincidente |
| Imagen AlmaLinux 10 | preparada | descarga y SHA-256 coincidente |
| Boot Rocky Linux 10 | iniciado | proceso QEMU creado; cloud-init pendiente |
| `install.sh` en single-node | pendiente | aún no ejecutado en VM |
| Golden WordPress/Fleet | pendiente | aún no ejecutado |
| Corrección y recompilación de RPM | no requerida todavía | no apareció error de Admiral |
| Topologías de nube privada | pendiente | se hará después de single-node |

## Artefactos de laboratorio

Las imágenes, overlays, semillas, logs de consola y la clave temporal se
ubicaron fuera del repositorio bajo `/var/lib/admiral-lab/`. La clave privada
es exclusiva del laboratorio y no se copió a ninguna VM como secreto de
Admiral; solamente se utilizó para el acceso SSH de bootstrap.

La semilla NoCloud sólo crea el usuario técnico temporal necesario para
arrancar y operar la VM. La configuración de Admiral debe continuar siendo
realizada por `install.sh`, no mediante modificaciones manuales en el guest.

## Próximos pasos

1. Completar el arranque/cloud-init de Rocky Linux 10.
2. Confirmar SELinux, disco, repositorios y ausencia de estado Admiral.
3. Ejecutar el modo soportado apropiado para la distribución y registrar toda
   la salida de `install.sh`.
4. Ejecutar el golden test WordPress/MariaDB con Fleet rootless.
5. Repetir en CentOS Stream 10 y AlmaLinux 10.
6. Si falla el producto, corregir fuentes, reconstruir los RPM y repetir desde
   una VM nueva usando el instalador.
7. Crear la red privada KVM y validar `--admin-node`, `--admin-portal-node`,
   `--portal-node` y `--worker-node` con WordPress en un worker.


## Comandos ejecutados durante esta sesión

Los siguientes comandos forman parte de la evidencia de preparación y setup.
Las rutas bajo `/var/lib/admiral-lab/` corresponden al laboratorio temporal.

### Inspección inicial del VPS

```bash
hostnamectl
cat /etc/os-release
nproc
free -h
df -h /
command -v virsh || true
command -v virt-install || true
command -v qemu-system-x86_64 || true
command -v qemu-img || true
command -v cloud-localds || true
command -v podman || true
systemd-detect-virt
systemctl is-active libvirtd 2>/dev/null || true
virsh list --all 2>&1 || true
ls -l /dev/kvm 2>&1 || true
grep -E 'vmx|svm' /proc/cpuinfo | head -1 || true
git status --short
command -v rpmbuild || true
go version 2>&1 || true
python3 --version 2>&1 || true
ls -l scripts/install.sh packaging/rpm/admiral-common.spec
```

### Instalación de herramientas KVM/QEMU

```bash
dnf install -y qemu-img qemu-system-x86-core edk2-ovmf \
  cloud-utils-growpart genisoimage openssh-clients
dnf provides '*/cloud-localds' 2>/dev/null | head -30
rpm -qa | grep -E '^cloud|qemu|geniso' | sort
```

### Preparación del almacenamiento

```bash
lab=/var/lib/admiral-lab
mkdir -p "$lab/images" "$lab/runs"
```

### Descarga de imágenes oficiales

```bash
cd /var/lib/admiral-lab/images
curl -fL --retry 3 --continue-at - -o \
  CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2 \
  https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2
curl -fL --retry 3 --continue-at - -o \
  Rocky-10-GenericCloud-Base.latest.x86_64.qcow2 \
  https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2
curl -fL --retry 3 --continue-at - -o \
  AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 \
  https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2
```

### Verificación de checksums

```bash
cd /var/lib/admiral-lab/images
curl -fsSL -o centos.CHECKSUM \
  https://cloud.centos.org/centos/10-stream/x86_64/images/CHECKSUM
curl -fsSL -o rocky.CHECKSUM \
  https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2.CHECKSUM
curl -fsSL -o alma.CHECKSUM \
  https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/CHECKSUM
rg 'GenericCloud|AlmaLinux-10' centos.CHECKSUM rocky.CHECKSUM alma.CHECKSUM
sha256sum *qcow2
```

### Clave temporal del laboratorio

```bash
lab=/var/lib/admiral-lab
ssh-keygen -q -t ed25519 -N '' -f "$lab/lab_key" -C admiral-lab
cat "$lab/lab_key.pub"
```

La clave privada quedó en `/var/lib/admiral-lab/lab_key` y no se copió al
guest como credencial de Admiral.

### Overlay y semilla NoCloud Rocky

```bash
lab=/var/lib/admiral-lab
run="$lab/runs/rocky-single"
mkdir -p "$run"
cp lab/kvm/user-data lab/kvm/meta-data "$run/"
genisoimage -quiet -output "$run/seed.iso" -volid cidata \
  -joliet -rock "$run/user-data" "$run/meta-data"
qemu-img create -f qcow2 -F qcow2 -b \
  "$lab/images/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2" \
  "$run/disk.qcow2" 24G
```

### Arranque QEMU/KVM

El primer intento añadió simultáneamente `-nographic` y `-daemonize`, y
QEMU lo rechazó. El comando corregido fue:

```bash
qemu-system-x86_64 \
  -enable-kvm -machine q35 -cpu host -smp 2 -m 4096 \
  -drive file="$run/disk.qcow2",if=virtio,format=qcow2 \
  -cdrom "$run/seed.iso" \
  -nic user,model=virtio,hostfwd=tcp:127.0.0.1:2222-:22 \
  -display none -serial "file:$run/console.log" \
  -pidfile "$run/qemu.pid" -daemonize
```

### Espera y comprobación del guest

```bash
for i in $(seq 1 90); do
  if ssh -i "$lab/lab_key" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=2 -p 2222 rocky@127.0.0.1 \
    'cloud-init status --wait >/dev/null 2>&1 && echo READY' 2>/dev/null \
    | rg -q READY; then
    break
  fi
  sleep 2
done
ssh -i "$lab/lab_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 \
  rocky@127.0.0.1 \
  'cat /etc/os-release; getenforce; free -h; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS'
```

Comprobación posterior:

```bash
if [[ -f "$lab/runs/rocky-single/qemu.pid" ]]; then
  ps -fp "$(cat "$lab/runs/rocky-single/qemu.pid")" || true
fi
ssh -i "$lab/lab_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=5 -p 2222 rocky@127.0.0.1 \
  'cloud-init status --long; cat /etc/os-release; getenforce'
tail -40 "$lab/runs/rocky-single/console.log"
```

### Transferencia y ejecución de install.sh

El primer intento omitió el puerto reenviado y falló sin modificar el guest:

```bash
scp -q -i "$lab/lab_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  scripts/install.sh rocky@127.0.0.1:/tmp/admiral_install.sh
```

El intento correcto utilizó `-P 2222`:

```bash
scp -q -P 2222 -i "$lab/lab_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  scripts/install.sh rocky@127.0.0.1:/tmp/admiral_install.sh

ssh -i "$lab/lab_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 \
  rocky@127.0.0.1 \
  'chmod 0755 /tmp/admiral_install.sh && \
   sudo /tmp/admiral_install.sh --single-node \
     --public-ip 10.0.2.15 \
     --ssh-public-key /home/rocky/.ssh/authorized_keys' \
  2>&1 | tee "$run/install.log"
```

En ese punto intermedio la ejecución había llegado a instalar
`epel-release`, `ansible-core` y `admiral-common-0.0.1beta18-1.el10` desde
COPR, junto con `ansible-collection-ansible-posix`. La ejecución continuó
posteriormente y su resultado final quedó documentado en la sección del
golden test Rocky.


### Ejecución paralela de las tres validaciones

Rocky ya estaba ejecutando su instalación en el puerto 2222. Se iniciaron
CentOS Stream 10 y AlmaLinux 10.2 en paralelo, con 3 GiB y 2 vCPU cada una:

```bash
for spec in \
  'centos-single|CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2|2223' \
  'alma-single|AlmaLinux-10-GenericCloud-latest.x86_64.qcow2|2224'; do
  IFS='|' read -r name image port <<< "$spec"
  run="$lab/runs/$name"
  mkdir -p "$run"
  cp "$lab/runs/rocky-single/user-data" "$lab/runs/rocky-single/meta-data" "$run/"
  sed -i "s/instance-id: admiral-lab/instance-id: $name/; \
s/local-hostname: admiral-lab/local-hostname: $name/" "$run/meta-data"
  genisoimage -quiet -output "$run/seed.iso" -volid cidata \
    -joliet -rock "$run/user-data" "$run/meta-data"
  qemu-img create -f qcow2 -F qcow2 -b "$lab/images/$image" \
    "$run/disk.qcow2" 24G
  qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 2 -m 3072 \
    -drive "file=$run/disk.qcow2,if=virtio,format=qcow2" \
    -cdrom "$run/seed.iso" \
    -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:$port-:22" \
    -display none -serial "file:$run/console.log" \
    -pidfile "$run/qemu.pid" -daemonize
done
```

Se comprobó el boot de ambas VMs con:

```bash
ssh -i "$lab/lab_key" -p 2223 rocky@127.0.0.1 \
  'cloud-init status --long; cat /etc/os-release'
ssh -i "$lab/lab_key" -p 2224 rocky@127.0.0.1 \
  'cloud-init status --long; cat /etc/os-release'
```

Después se transfirió y ejecutó el mismo instalador en sesiones simultáneas:

```bash
scp -q -P 2223 -i "$lab/lab_key" scripts/install.sh \
  rocky@127.0.0.1:/tmp/admiral_install.sh
ssh -i "$lab/lab_key" -p 2223 rocky@127.0.0.1 \
  'chmod 0755 /tmp/admiral_install.sh && sudo /tmp/admiral_install.sh \
   --single-node --public-ip 10.0.2.15 \
   --ssh-public-key /home/rocky/.ssh/authorized_keys'

scp -q -P 2224 -i "$lab/lab_key" scripts/install.sh \
  rocky@127.0.0.1:/tmp/admiral_install.sh
ssh -i "$lab/lab_key" -p 2224 rocky@127.0.0.1 \
  'chmod 0755 /tmp/admiral_install.sh && sudo /tmp/admiral_install.sh \
   --single-node --public-ip 10.0.2.15 \
   --ssh-public-key /home/rocky/.ssh/authorized_keys'
```

### Comandos del golden test Rocky

Se copiaron la definición oficial y se ejecutó el flujo usando la configuración
generada por el instalador:

```bash
scp -q -P 2222 -i "$lab/lab_key" examples/apps/wordpress.yaml \
  rocky@127.0.0.1:/tmp/wordpress.yaml

sudo bash -s <<'EOF'
set -e
export ADMIRAL_ADMIN_TOKEN=$(awk -F= '$1=="ADMIRAL_ADMIN_TOKEN" \
  {print substr($0,index($0,"=")+1)}' /etc/admiral/secrets)
export ADMIRAL_SERVER_URL=https://127.0.0.1:8080
export ADMIRAL_TLS_CA_FILE=/etc/admiral/tls/ca.pem
admiralctl status
admiralctl nodes list --output json
admiralctl apps apply -f /tmp/wordpress.yaml
admiralctl apps activate --name wp
admiralctl instances provision --app wp --tier small \
  --customer qa-rocky --wait --output json
EOF
```

La instancia creada fue `inst_85ea6506fc0239d4`. Las comprobaciones de
lifecycle ejecutadas fueron:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:40000
admiralctl instances inspect inst_85ea6506fc0239d4 --result
admiralctl instances backup --service db inst_85ea6506fc0239d4 --wait
admiralctl instances pause inst_85ea6506fc0239d4 --wait
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:40000
admiralctl instances resume inst_85ea6506fc0239d4 --wait
admiralctl instances deprovision inst_85ea6506fc0239d4 --wait --force
admiralctl instances list --output json
```

El primer HTTP posterior a `resume` se ejecutó inmediatamente y devolvió
`000` por conexión todavía en recuperación. La repetición con reintentos
devolvió `301`, por lo que no se clasificó como fallo. Provision,
backup, pause, resume y deprovision terminaron con estado `succeeded`;
`setup_completed=true` y el estado final fue `deprovisioned`.


## Actualización de bitácora: conflicto AlmaLinux y RPM local

### Incidencia observada

La primera ejecución de `install.sh --single-node` en AlmaLinux 10.2
falló en:

```text
TASK [admiral_common : Apply available security updates]
fatal: Depsolve Error occurred
vim-minimal-2:9.1.083-9.el10_2.3 requires vim-data =
2:9.1.083-9.el10_2.3, but vim-data-2:9.1.083-9.el10_2.4 was selected
```

El fallo ocurrió antes de configurar servicios de Admiral. El play recap fue:

```text
ok=16 changed=1 unreachable=0 failed=1 skipped=5 ignored=0
```

Durante esa misma instalación se observó además un warning no fatal del
scriptlet de `admiral-common` sobre `/run/user/<uid>/libpod`; la transacción
RPM terminó correctamente y el fallo bloqueante fue el depsolve de DNF.

### Reproducción del problema

En la VM AlmaLinux fallida se ejecutó únicamente una simulación, sin aplicar
cambios:

```bash
ssh -i "$lab/lab_key" -p 2224 rocky@127.0.0.1 \
  'sudo dnf update --security --refresh --allowerasing --assumeno'
```

La simulación resolvió el conflicto seleccionando las versiones compatibles
de `vim-data` y `vim-minimal`. Esto confirmó que el problema estaba en la
resolución estricta del módulo Ansible frente al estado temporal de los
repositorios AlmaLinux.

### Corrección aplicada en fuentes

Se modificó `ansible/roles/admiral_common/tasks/main.yml` para que la tarea
de actualizaciones de seguridad utilice:

```yaml
allowerasing: true
```

La corrección se limitó a la tarea existente de actualización de seguridad;
no se hicieron cambios manuales de configuración de Admiral dentro de la VM.

El RPM se incrementó de release `1` a release `2` en
`packaging/rpm/admiral-common.spec`, y se actualizó la referencia de fuente
al commit actual para satisfacer `validate-release-refs.py`.

### Commit y firma de autoría

```bash
git add ansible/roles/admiral_common/tasks/main.yml \
  packaging/rpm/admiral-common.spec
git -c user.name='William Moreno Reyes' \
  -c user.email='williamjmorenor@gmail.com' \
  commit -s -m 'fix(installer): tolerate EL10 security update conflicts'
python3 scripts/validate-release-refs.py
```

Resultado:

```text
cb1c24f fix(installer): tolerate EL10 security update conflicts
Signed-off-by: William Moreno Reyes <williamjmorenor@gmail.com>
RPM source references match checked-out component commits.
```

### Recompilación del RPM local

En el host Fedora se instalaron las herramientas necesarias:

```bash
dnf install -y rpm-build systemd-rpm-macros make
make rpm-admiral-common
```

La compilación terminó correctamente y produjo:

```text
packaging/build/RPMS/noarch/admiral-common-0.0.1beta18-2.fc44.noarch.rpm
packaging/build/SRPMS/admiral-common-0.0.1beta18-2.fc44.src.rpm
```

### Recreación de AlmaLinux desde imagen limpia

La VM AlmaLinux que falló se apagó y se creó una segunda VM con un overlay
nuevo, conservando los logs de la primera ejecución:

```bash
oldpid=$(cat "$lab/runs/alma-single/qemu.pid")
kill "$oldpid"
run="$lab/runs/alma-single-retry"
mkdir -p "$run"
genisoimage -quiet -output "$run/seed.iso" -volid cidata \
  -joliet -rock "$run/user-data" "$run/meta-data"
qemu-img create -f qcow2 -F qcow2 -b \
  "$lab/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2" \
  "$run/disk.qcow2" 24G
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 2 -m 3072 \
  -drive "file=$run/disk.qcow2,if=virtio,format=qcow2" \
  -cdrom "$run/seed.iso" \
  -nic user,model=virtio,hostfwd=tcp:127.0.0.1:2224-:22 \
  -display none -serial "file:$run/console.log" \
  -pidfile "$run/qemu.pid" -daemonize
```

La segunda VM AlmaLinux se encuentra en proceso de boot/cloud-init. La
instalación del RPM local y la nueva ejecución de `install.sh` quedan
pendientes de completar en esta sesión.

## Actualización de bitácora: continuación 2026-07-29

### Estado de las validaciones single-node

- Rocky Linux 10: `install.sh --single-node` completado; el golden test de
  WordPress ejecutó Fleet rootless con éxito y completó provision, backup,
  pause, resume y deprovision.
- CentOS Stream 10: `install.sh --single-node` completado; el golden test de
  WordPress ejecutó Fleet rootless con éxito y completó el mismo ciclo.
- AlmaLinux 10: se creó una VM limpia con 2 vCPU y 4 GiB de RAM. La primera
  repetición con `admiral-common-0.0.1beta18-7.fc44` no pudo resolver la
  dependencia `ansible-collection-ansible-posix` antes de habilitar EPEL.
  La ejecución soportada se relanzó mediante `install.sh`; el instalador ya
  completó las actualizaciones EL10, EPEL, COPR, Ansible y la entrada al
  playbook de configuración. El golden test AlmaLinux quedó completado en la
  VM `alma-single-final2` y se documenta en la sección de resultado corregido.

La dependencia RPM faltante no modificó Admiral ni la VM manualmente. El
flujo se mantuvo en `install.sh`; la repetición corregida usó el RPM local
beta18-9 después de habilitar los repositorios requeridos.

### Fedora para topología multinodo

Fedora no se validará con `--single-node`. Se reservará como nodo
`--worker-node` dentro de la nube privada KVM, conectado a un administrador
EL10 mediante WireGuard. Su resultado se registrará como validación
adicional de desarrollo y no sustituirá las tres validaciones Tier 1.

La imagen Fedora Rawhide descargada fue verificada con SHA-256:

```text
1f3ebc76ccf985887700d22fbd98218653ccfa13674c36840c4e4673880d7ee2
```

El intento histórico `--dev-node` de Fedora Rawhide falló al crear el
override systemd de `admirald` porque no existía previamente
`/etc/systemd/system/admirald.service.d`; ese intento no corresponde al
flujo Fedora `--worker-node` solicitado y queda registrado como antecedente,
no como resultado multinodo.

### Resultado AlmaLinux single-node con la fuente corregida

La VM limpia `alma-single-final2` se ejecutó con `install.sh --single-node`
usando el RPM local `admiral-common-0.0.1beta18-9.fc44.noarch.rpm`. La primera
pasada con el RPM COPR beta18-1 reprodujo el fallo de `auditctl`; después se
instalaron los RPM locales y se transfirió la copia actualizada de
`install.sh` desde el repositorio.

La ejecución corregida terminó con `failed=0` en Ansible y con el checklist de
seguridad del instalador aprobado. El golden WordPress/Fleet produjo:

- instancia: `inst_395975851db8b99b`;
- `setup_completed=true`;
- HTTP inicial: `301`;
- backup de base de datos: `succeeded`;
- pause: `succeeded`, HTTP pausado `000`;
- resume: `succeeded`, HTTP recuperado `301`;
- deprovision: `succeeded`;
- estado técnico final: `deprovisioned`.

### Correcciones de auditoría y empaquetado

- `b5b3b36 fix(installer): tolerate audit rule files without auditctl`.
- `f348626 build(rpm): package audit checklist fallback` (`beta18-8`).
- `73a0eaa fix(installer): detect auditctl availability reliably`.
- `eb6cb7b build(rpm): package reliable auditctl detection` (`beta18-9`).

Todos los commits fueron creados por William Moreno Reyes,
`williamjmorenor@gmail.com`, con `Signed-off-by`.

### Actualización de bitácora: topologías privadas 2026-07-29

Se levantó una red privada KVM para Rocky Linux 10 con:

- administrador: `192.168.100.1`;
- worker: `192.168.100.2`;
- WireGuard previsto: `10.99.0.1` y `10.99.0.2`.

La conectividad de ambas interfaces privadas fue comprobada antes de ejecutar
los instaladores.

#### Rocky Linux 10 — `--admin-node`

La primera ejecución de `install.sh` completó el playbook con `failed=0` y
configuró TLS, PostgreSQL, SELinux, firewall, auditd, fail2ban, WireGuard,
`admirald` y `admiral-flagship`. El checklist final falló con:

```text
The WireGuard firewalld zone does not use a DROP target.
```

La causa fue específica del comando de comprobación: en firewalld de EL10,
`--get-target` requiere `--permanent`; la zona sí tenía `target: DROP` y
`wg-admiral` estaba asignada correctamente.

Corrección aplicada:

- `076ff2b fix(installer): read permanent firewalld zone target`;
- `c7876d9 build(rpm): package permanent firewalld target check`;
- RPM local construido: `admiral-common-0.0.1beta18-10.fc44.noarch.rpm`.

El RPM-10 y la copia actual de `install.sh` fueron transferidos a la VM. El
rerun terminó con `PLAY RECAP failed=0` y `Admiral installation completed` en
modo `admin-node`; el checklist ya no reportó el falso fallo de `DROP`.

El siguiente paso es registrar el worker contra este administrador y ejecutar
el golden test con storage S3 externo.

#### Storage externo para backup/restore

Se levantó una VM Rocky Linux 10 separada (`rocky-storage`) para simular un
EC2 de almacenamiento. MinIO se ejecutará en un contenedor Podman con el
volumen persistente `/var/lib/minio-data`; el endpoint se expondrá al
administrador únicamente mediante el puerto de laboratorio. Este resultado
se conservará como evidencia de backup/restore fuera del disco del nodo
Admiral.

### Actualización de bitácora: storage externo y estado 2026-07-29

La validación de storage externo se amplió con una VM Rocky Linux 10 separada,
`rocky-storage`, que ejecuta MinIO en un contenedor Podman rootful sobre el
volumen persistente `/var/lib/minio-data`. La imagen MinIO se descargó
correctamente y el contenedor quedó creado; el primer intento rootless terminó
al cerrar la sesión SSH porque el usuario auxiliar no tenía linger, por lo que
se relanzó como contenedor rootful del nodo de storage.

El primer acceso mediante `hostfwd` del host no fue aceptado como evidencia de
storage externo: el guest Admiral no pudo alcanzar ese puerto a través de su
NAT. Se está usando una red L2 privada del laboratorio mediante bridge/TAP,
con perfiles NetworkManager persistentes por MAC en ambas VMs. El endpoint
MinIO solo se considerará válido cuando el admin y el worker lo alcancen por
esa red privada.

Se detectó además que la configuración S3 requería credenciales en Fleet y
Admirald, pero `install.sh` no las provisionaba. Se corrigió en fuentes:

- `ca384f4 feat(backup): provision S3 credentials through installer`;
- `4581149 build(rpm): package installer S3 credential support`;
- RPM local construido: `admiral-common-0.0.1beta18-11.fc44.noarch.rpm`.

El nuevo flujo usa `--s3-credentials-file` y queda pendiente de instalarse y
validarse en las VMs antes de ejecutar backup, comprobar el objeto externo,
eliminar la copia local y restaurar WordPress.

### Actualización de bitácora: firewall y bootstrap del worker 2026-07-29

Se confirmó que la política nftables de egreso rechazaba el acceso del admin y
del worker a un endpoint MinIO en TCP/9000. El admin mostró inicialmente
`Destination Port Unreachable` al intentar `192.168.200.2:9000`; esto impedía
validar backup externo real.

Corrección aplicada en origen, con commits semánticos y sign-off:

- `a50cb91 fix(firewall): permit S3 backup egress`: permite TCP/9000 para
  endpoints S3-compatible en perfiles admin, worker y portal; HTTPS S3 sigue
  usando TCP/443.
- `1bd087a build(rpm): package S3 backup egress policy` (RPM `-12`).
- `8c199fc fix(fleet): correct S3 environment task syntax` y
  `e59dbd0 build(rpm): package fleet task syntax fix` (RPM `-13`).
- `516314b fix(installer): ignore ssh keyscan comments` y
  `3804ebf build(rpm): package SSH bootstrap parser fix` (RPM `-14`).
- `01c8306 fix(installer): create spoke config directory early` y
  `99ca44f build(rpm): package spoke directory bootstrap fix` (RPM `-15`).

El admin Rocky fue reinstalado mediante `install.sh` con RPM-13 y credenciales
S3. Evidencia obtenida:

```text
PLAY RECAP: ok=161 changed=26 unreachable=0 failed=0
tcp dport { 22, 53, 80, 443, 587, 9000 } accept
minio=200
admirald=active
```

El worker Rocky tiene ahora una interfaz L2 privada de storage en
`192.168.200.3`, además de `192.168.100.2` para la red privada Admiral. El
bootstrap remoto se está ejecutando desde el admin con RPM-15; ya superó la
persistencia del rol `worker`, la creación de directorios, la copia de CA y la
configuración inicial, pero todavía está ejecutando las actualizaciones de
seguridad y no tiene aún un `PLAY RECAP` final. Por tanto, el worker y el
backup/restore S3 real siguen pendientes de cierre.

### Actualización de bitácora: validación EL10 y estado de hallazgos 2026-07-29

Se repitió la instalación mediante el instalador empaquetado, sin editar
manualmente las VMs, usando RPM locales construidos desde referencias Git
completas:

- `admiral-common-0.0.1beta18-27.fc44.noarch.rpm`;
- `admirald-0.0.1beta18-3.fc44.x86_64.rpm`.

CentOS 10 y AlmaLinux 10 terminaron `install.sh` con `failed=0` y
`Admiral installation completed`. En ambas VMs quedaron activos `caddy`,
`admirald` y `admiral-caddy-socket-permissions.path`. El socket Unix de Caddy
conservó permisos para `admiral`, y el acceso de `admirald` se comprobó antes y
después de recargar la configuración de Caddy.

Las VMs single-node fueron apagadas limpiamente para liberar memoria; sus
discos y logs se conservaron. El laboratorio multinodo sigue activo, pero el
worker Rocky permanece `offline/degraded`, por lo que el golden multinodo y el
backup/restore S3 externo todavía no están aprobados.

#### Estado explícito de `notas.md`

El informe de seguridad no se considera cerrado por el mero hecho de que la
instalación termine correctamente:

- Caddy/H2: corregido en fuentes con socket Unix, grupo/ACL y watcher de
  permisos; falta consolidar la evidencia en el golden multinodo.
- WireGuard/C1: se añadió preservación de la configuración existente del hub;
  falta validar la convergencia con un worker realmente registrado y sano.
- S3, firewall y credenciales del instalador: corregidos en fuentes y
  empaquetados; falta cerrar backup/restore contra storage privado real.
- H1 (tokens en argumentos), H3 (SSH `NOPASSWD`), M1/M2/M3/M6 y los hallazgos
  de prioridad baja siguen abiertos y no deben presentarse como resueltos.

La bitácora separa desde este punto “fix aplicado” de “fix validado en una
topología completa”.

### Actualización de bitácora: diagnóstico de worker multinodo 2026-07-29

El worker Rocky no está todavía validado: `admiral-fleet` permanece activo,
pero el administrador lo ve como `offline/degraded`, con
`heartbeat_timeout`. En el worker no hay handshake WireGuard reciente y el
hub no tiene aún el peer efectivo del worker. Por tanto, no se ejecutó todavía
el golden test WordPress multinodo.

Se recompiló `admiral-fleet` desde el commit referenciado por el spec; el RPM
terminó `go test ./...` correctamente. La primera transferencia de ese RPM al
worker mediante `scp` falló por autenticación SSH, antes de modificar la
configuración del worker. El intento no se registra como instalación exitosa.

Siguiente acción: resolver la ruta de bootstrap SSH y repetir exclusivamente
la opción `admiral_install --worker-node`, con los RPM locales, para que el
intercambio WireGuard y el registro del nodo ocurran desde el instalador.

### Actualización de bitácora: golden rootless con Fleet corregido — 2026-07-29

La validación posterior cerró la discrepancia entre single-node y multinodo.
El defecto no estaba en la comunicación entre componentes: `admiral-fleet`
se comunica con `admirald` por la API sobre WireGuard. El defecto estaba en los
healthchecks TCP/HTTP de Fleet, que usaban `127.0.0.1` aun cuando el workload
multinodo publicaba el puerto sobre la IP WireGuard del worker.

Corrección aplicada en el repositorio `admiral-fleet`:

- `7eec3c25b81a7babf7967a8039241c66546cdfd9 fix(fleet): probe published workload address`
  calcula la dirección publicada mediante el renderer y la usa para los
  healthchecks TCP/HTTP; los command healthchecks continúan ejecutándose dentro
  del contenedor sobre loopback, como corresponde.
- El root `admiral` fijó esa referencia completa en
  `c162862b0456e65ec42f92810367a6812b83acb2`.
- RPM construido: `admiral-fleet-0.0.1beta18-2.fc44.x86_64.rpm`.

#### Rocky Linux 10 single-node

El RPM local `-2` se instaló en la VM Rocky single-node y `admiral-fleet`
quedó activo. El golden WordPress terminó con:

```text
operation: op_b1495918c987c418
status: succeeded
instance: inst_d081353e86baa922
setup_completed: true
health_status: healthy
technical_status: running
```

La comprobación en la VM confirmó `rootless=true`, graph root
`/var/lib/admiral-apps/.local/share/containers/storage` y los contenedores
`infra`, `db`, `web` y `setup` ejecutándose como `admiral-apps`.

#### Rocky Linux 10 multinodo privado

El RPM local `-2` se instaló en `rocky-worker` y el servicio se reinició. El
worker permaneció activo, saludable y registrado mediante WireGuard
(`10.99.0.2`). El golden WordPress terminó con:

```text
operation: op_df39da2f8d865d6a
status: succeeded
instance: inst_2c4721f1ddf5719e
node_id: rocky-worker
setup_completed: true
health_status: healthy
technical_status: running
```

En el worker se confirmó `rootless=true` y los cuatro contenedores rootless
publicaron el workload sobre `10.99.0.2:40001`. Los avisos iniciales del
healthcheck MariaDB fueron transitorios durante el arranque; la operación
terminó correctamente.

El ejemplo `examples/apps/wordpress.yaml` configura `siteurl` como
`http://localhost`. Por eso una petición directa al puerto efímero multinodo
redirecciona a `:80`; esto es una limitación de URL del fixture, no un fallo de
provisionamiento ni de Fleet. `setup_completed`, salud y ciclo de vida quedan
validados: pause `op_2ea2f4294bb27622` terminó `succeeded` con estado
`stopped`, y resume `op_e63b3b48ff73e922` terminó `succeeded`.

#### Estado de seguridad revisado

- C1 WireGuard: corregido en fuentes; falta únicamente la prueba explícita de
  re-convergencia del admin con un peer conectado.
- H2 Caddy: corregido y probado en single-node con socket Unix, ACL y watcher.
- M4/M5 S3: corregidos en `install.sh`; permisos restringidos y variables
  limpiadas.
- H1/B10, H3/B9, M1/M2/M3 y M6: permanecen abiertos o parcialmente mitigados.
- B7/N8: obsoleto; el root check está al inicio de `install.sh`.
- Backup/restore S3 sobre storage privado con TLS: pendiente.

#### Estado de cierre de esta ronda

El golden rootless queda confirmado en Rocky single-node y Rocky multinodo.
CentOS 10 y AlmaLinux 10 conservan evidencia de instalación single-node en
esta bitácora; se debe distinguir esa evidencia histórica de una repetición con
el RPM Fleet `-2`. Permanecen pendientes una segunda topología multinodo, el
backup/restore S3 real y la actualización final de la guía de sysadmin.

### Actualización de bitácora: cierre de C1 WireGuard — 2026-07-29

La primera re-convergencia del admin reveló que el peer existía solo en el
estado runtime; una nueva ejecución de `install.sh --admin-node` podía perderlo.
Se corrigió en fuentes y se reconstruyó el RPM común:

- `613b2651497fd5032d4ce2f80a23928605d81147 fix(wireguard): persist spoke peers across reconciliation`;
- `admiral-common-0.0.1beta18-29.fc44.noarch.rpm`;
- el instalador ahora escribe `/etc/wireguard/peers.d/<node>.conf` y el rol del
  hub lee esos fragmentos durante la reconciliación.

El RPM local `-29` se instaló en admin y worker. El worker se volvió a
configurar mediante `admiral_install --worker-node`:

```text
PLAY RECAP: ok=120 changed=13 unreachable=0 failed=0 skipped=198 rescued=0 ignored=0
Admiral installation completed.
```

Después se ejecutó nuevamente `admiral_install --admin-node`:

```text
PLAY RECAP: ok=170 changed=24 unreachable=0 failed=0 skipped=149 rescued=0 ignored=0
Admiral installation completed.
```

La evidencia posterior confirmó:

- `/etc/wireguard/peers.d/rocky-worker.conf` presente;
- peer `4PnINr0+Hd7taYxhKsqGh7kgbfWevuOusjM6NoYAQ3Q=` presente en `wg show`;
- `AllowedIPs=10.99.0.2/32`;
- handshake reciente y worker `status=active`, `health_status=healthy`;
- `admiral-fleet-0.0.1beta18-2` y `admiral-common-0.0.1beta18-29` instalados;
- Podman del worker continúa `rootless=true`.

C1 queda validado en una re-convergencia real con un worker conectado.
