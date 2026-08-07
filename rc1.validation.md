# Admiral RC1 Validation Journal

> Estado: ejecución en curso. Esta bitácora es la fuente de verdad de la
> validación RC1 realizada desde este checkout y no sustituye evidencia de
> runtime. Cada escenario debe terminar con evidencia directa del guest.

## 1. Objetivo y criterio de aceptación

Se valida el candidato RC1 del superproyecto `admiral` en arquitectura
`x86_64`, sobre máquinas virtuales KVM/QEMU con SELinux `Enforcing`, para los
tres sistemas Tier 1:

| Sistema | `--single-node` | Multinode (`--admin-node` + `--worker-node` + `--portal-node`) |
|---|---:|---:|
| Rocky Linux 10 | Required | Required |
| CentOS Stream 10 | Required | Required |
| AlmaLinux 10 | Required | Required |

Un escenario sólo se considera exitoso cuando se comprueba el ciclo completo
de la aplicación WordPress de `examples/apps/wordpress.yaml`:

1. instalación limpia y configuración del rol;
2. registro/health de los servicios;
3. provision de la instancia;
4. finalización del setup y respuesta HTTP real;
5. verificación de estado `running`/`healthy`;
6. backup y checksum cuando el flujo esté disponible;
7. pause y comprobación de pérdida del endpoint;
8. resume y nueva respuesta HTTP;
9. deprovision;
10. comprobación directa de limpieza de contenedores, volúmenes, unidades y
    estado de control.

En multinode, la comprobación HTTP debe dirigirse a la dirección publicada del
worker por WireGuard, nunca a un loopback del admin. También deben comprobarse
registro separado del portal y worker, rutas WireGuard, autenticación entre
componentes y ausencia de exposición pública de PostgreSQL/Fleet.

## 1.1 Documentación normativa revisada

La ejecución se está guiando por estos documentos del checkout actual:

| Documento | Uso en la validación |
|---|---|
| `docs/local_kvm_cloud_setup.md` | Imagen GenericCloud, checksum, overlays, KVM, cloud-init, single-node y controles post-instalación |
| `docs/release_validation.md` | Matriz Tier 1, gates, evidencia mínima y clasificación de resultados |
| `docs/multi_node_setup_v1.md` | Topología admin/worker/portal, WireGuard, segmentación y rutas runtime |
| `docs/admiral-installation-guide.md` | Prerrequisitos y procedimiento de instalación |
| `docs/sysadmin_guide.md` | Operación, servicios, diagnóstico y recuperación |
| `docs/configuration-v1.md` | Configuración y precedencia de valores |
| `docs/networking_v1.md` | Listeners, ingress y red privada |
| `docs/tasks-v1.md` | Operaciones/tareas durables y estados |
| `docs/states-v1.md` | Estados técnicos y de salud de instancias |
| `docs/app-definition-v1.md` | Contrato de `wordpress.yaml` |
| `docs/rpm_packaging.md` | Build, referencias y requisitos RPM |
| `docs/release_validation.md` (secciones 9–13) | Golden test, multinode, seguridad y criterios de cierre |

Los reportes `beta*.validation.md` se consultan sólo como contexto histórico y
para localizar comandos/evidencia previamente usados; no se copian sus PASS a
esta ejecución sin repetir el escenario en guests limpios.

## 2. Estado resumido de esta ejecución

| Gate | Estado actual | Evidencia o motivo |
|---|---|---|
| Checkout y submódulos | PASS | Submódulos inicializados en los SHAs fijados |
| Referencias de release | PASS | `python3 scripts/validate-release-refs.py` |
| Preflight KVM | PASS | `/dev/kvm`, 4 vCPU, 8 GiB RAM, 154 GiB libres |
| Herramientas de build/lab | PASS | `make`, `rpmbuild`, Go, QEMU/KVM, `qemu-img`, cloud-init y `genisoimage` disponibles |
| RPM locales RC1 | PASS BUILD | Los seis RPM generados; `%check` omitido por target RC1 `no-test` |
| Rocky single-node | PASS | Sección 8.1; ciclo WordPress y actualización de imagen validados |
| CentOS Stream single-node | PASS | Secciones 14.1–14.2; ciclo base completo validado |
| AlmaLinux single-node | PASS | Secciones 13.1–13.4; ciclo WordPress completo validado |
| Rocky multinode | PASS | Sección 15; incluye restore DB/volumen con marcadores |
| CentOS Stream multinode | PASS | Sección 17; roles separados y ciclo completo validados |
| AlmaLinux multinode | PASS | Sección 16; roles separados y ciclo completo validados |
| Bitácora | COMPLETE | Evidencia de los seis escenarios registrada |

La matriz global se declara `PASS` con la evidencia directa y reproducible de
los seis escenarios registrada en las secciones 8 y 13–17. Las secciones
iniciales conservan el contexto de preparación y no representan el estado
final de la validación.

## 3. Identidad de la ejecución

- Fecha UTC de inicio: 2026-08-07.
- Checkout: `/root/admiral`.
- Rama: `main`.
- Commit raíz observado al inicio: `5d04cb9` (`docs(validation): record rc1 package artifacts`).
- Arquitectura del host: `x86_64`.
- Host observado: Rocky Linux 10.2 (`VERSION_ID=10.2`).
- Kernel observado: `6.12.0-211.16.1.el10_2.0.1.x86_64`.
- CPU observadas: 4 vCPU.
- Memoria: 7.5 GiB total, 6.9 GiB disponible al preflight.
- Swap: 0 B (limitación ambiental; la topología multinode debe vigilar RSS y
  no debe ocultar OOM como fallo de producto).
- Disco `/`: 159 GiB total, 154 GiB disponibles.
- KVM: `/dev/kvm` presente, CPU con `vmx`.
- Git remoto raíz: `origin/main`.
- Usuario de ejecución: root.

### 3.1 Comandos de preflight y resultados

```text
cat /etc/os-release
NAME="Rocky Linux"
VERSION="10.2 (Red Quartz)"
ID=rocky
VERSION_ID="10.2"

uname -a
Linux rocky-linux-s-4vcpu-8gb-nyc1 6.12.0-211.16.1.el10_2.0.1.x86_64 ... x86_64

nproc
4

ls -l /dev/kvm
crw-rw-rw-. 1 root kvm 10, 232 ... /dev/kvm

grep -E 'vmx|svm' /proc/cpuinfo | head -1
flags ... vmx ... ept vpid ...
```

Conclusión: el host sí tiene virtualización anidada/KVM. Antes de arrancar la
topología simultánea se debe considerar que el host no tiene swap y dispone de
8 GiB; el procedimiento recomendado reserva al menos 2 GiB por guest y deja
memoria para QEMU y el host.

## 3.2 Instalación de herramientas del host

Se intentó inicialmente instalar `qemu-system-x86-core`, nombre no disponible
en los repositorios EL10 de este host. El paquete correcto de Rocky 10 es
`qemu-kvm`/`qemu-kvm-core`. La primera transacción concurrente dejó un paquete
de caché incompleto y terminó con:

```text
[Errno 2] No such file or directory: .../genisoimage-...rpm
```

Se limpió únicamente la caché de paquetes (`dnf clean packages`) y se repitió
la transacción serialmente. Resultado final:

```text
make-4.4.1-9.el10.x86_64
rpm-build-4.19.1.1-23.el10.x86_64
golang-1.26.5-1.el10_2.x86_64
qemu-kvm-10.1.0-16.el10_2.2.x86_64
qemu-img-10.1.0-16.el10_2.2.x86_64
genisoimage-1.1.11-58.el10_1.x86_64
```

`cloud-init-24.4-7.el10_0.1.noarch` ya estaba instalado. Este incidente fue
ambiental y no cambió el repositorio del producto.

## 4. Integridad del código fuente

El checkout comenzó limpio. Los submódulos estaban presentes como directorios
vacíos y fueron inicializados con:

```bash
git submodule update --init --recursive
```

SHAs fijados por el superproyecto:

| Componente | SHA |
|---|---|
| `admiral-flagship` | `a670b80a5abf6041059a0fd7702124fa6d6a9ff7` |
| `admiral-fleet` | `7bba40dbd8a083a7ce895fb25052a2cd5823bbfa` |
| `admiral-harbor` | `2dd173a472f588466f4fbdf307575e32df739215` |
| `admiralctl` | `4b6721200e10dbbc64da6cd6f97f9637190570e` |
| `admirald` | `6c4dee6076952e73c1333f1b0e5036ca5b8a674a` |

Validación ejecutada:

```bash
python3 scripts/validate-release-refs.py
```

Resultado observado:

```text
RPM source references match checked-out component commits.
```

## 4.1 Inicio del build local RC1

Comando ejecutado:

```bash
make rpm-admiral-no-test
```

El target validó referencias, generó el tarball combinado de superproyecto y
submódulos, descargó y verificó con SHA-256 las fuentes Python externas, y
comenzó los seis paquetes Admiral con `--nocheck`, tal como define el target
RC1 existente. A las 03:41 UTC se había generado correctamente:

```text
admiral-common-0.0.1rc1-122.el10.noarch.rpm
admiral-common-0.0.1rc1-122.el10.src.rpm
```

El build continuaba compilando `admirald`; el resultado global queda pendiente
hasta que el proceso termine con exit code 0 y se recopilen los seis NEVRA y
hashes.

### 4.1.1 Primer fallo de build y corrección del entorno

El primer `make rpm-admiral-no-test` terminó con exit code 2 en
`rpm-admiral-flagship`. El error completo fue:

```text
error: Failed build dependencies:
    python3-flask is needed by admiral-flagship-0.0.1rc1-82.el10.noarch
    python3-gunicorn is needed by admiral-flagship-0.0.1rc1-82.el10.noarch
    python3-pytest is needed by admiral-flagship-0.0.1rc1-82.el10.noarch
    python3-werkzeug >= 3.0.6 is needed by admiral-flagship-0.0.1rc1-82.el10.noarch
```

La comprobación de repositorios mostró que los paquetes sí están disponibles
cuando EPEL y CRB tienen metadata actual:

```text
python3-flask-3.1.2-2.el10_2          EPEL
python3-gunicorn-23.0.0-1.el10_1      EPEL
python3-pytest-7.4.3-5.el10           CRB
python3-werkzeug-3.1.3-1.el10_0       EPEL
```

Se instaló ese conjunto junto con sus dependencias (`blinker`, `click`,
`itsdangerous`, `iniconfig`, `pluggy`) y se repitió el build. No se usó
`--nodeps` como primera solución porque las dependencias declaradas existen en
EL10 y comprobarlas es parte de la reproducibilidad del RPM. El resultado del
segundo build se anotará aquí cuando termine.

### 4.1.2 Segundo fallo: artefacto compartido escrito concurrentemente

La repetición terminó con exit code 2 durante `admirald`, después de que la
generación del tarball reportara:

```text
gzip: .../admiral-0.0.1rc1.tar: file size changed while zipping
/usr/bin/tar: Unexpected EOF in archive
error: Bad exit status ... (%prep)
```

La inspección de procesos mostró otra ejecución `make rpm-admiral` usando el
mismo `packaging/build` en paralelo. El tarball fue truncado por el harness;
esto no es evidencia contra `admirald`. Se serializarán los builds, se
limpiarán sólo los artefactos generados bajo `packaging/build` mediante el
target existente y se repetirá un único `make rpm-admiral-no-test`.

### 4.1.3 Build serial final

Se detuvo la ejecución redundante, se ejecutó `make clean` (eliminó únicamente
`packaging/build`) y se repitió un único `make rpm-admiral-no-test`. El target
terminó con exit code `0`; las dependencias Python de Flagship se resolvieron
desde EPEL/CRB y las dependencias Python versionadas de Harbor se construyeron
con targets locales y se instalaron sólo en el host de build. El build final
no modificó ningún submódulo.

Artefactos finales x86_64/noarch:

| Paquete | NEVRA | SHA-256 |
|---|---|---|
| `admiral-common` | `admiral-common-0.0.1rc1-122.el10.noarch` | `b32470ccc549700946f6ffd20cfa6ae4fa0f7d9a823478f0af7054e292a6c765` |
| `admirald` | `admirald-0.0.1rc1-51.el10.x86_64` | `acbee840f4f06e6da17c18ade86bad6ba2c682984c695ad8862d90244bc63c07` |
| `admiral-fleet` | `admiral-fleet-0.0.1rc1-59.el10.x86_64` | `4d62679a87c9e41239d9705fa5e8f20d3022bb9e6bee10e5aef27ac74dbb4953` |
| `admiralctl` | `admiralctl-0.0.1rc1-49.el10.x86_64` | `6597b4a3f1e2ee2ea46019b89068a460443aba655147bb5a9330c6d789542b44` |
| `admiral-flagship` | `admiral-flagship-0.0.1rc1-82.el10.noarch` | `ca0cb403c49f296d6305ef58195d480cf77d7761a6530297891f78bb863bc045` |
| `admiral-harbor` | `admiral-harbor-0.0.1rc1-50.el10.noarch` | `1d15a3ef5b8a75f60216ac1ab7207d4242a80048306f37f926a2fed81cd194be` |

Validación posterior al build:

```text
python3 scripts/validate-release-refs.py
RPM source references match checked-out component commits.
```

Después de cada cambio de código, esta sección debe actualizarse con el nuevo
commit raíz, los nuevos SHAs de componentes y una nueva ejecución del script.

## 5. RPM RC1 y canal COPR

El usuario informó que los paquetes RC1 que corresponden al estado actual están
publicados en:

<https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/>

La publicación COPR se usará para comprobar el canal de distribución, pero no
reemplaza la construcción local exigida por esta validación. El procedimiento
será:

```bash
make rpm-admiral-no-test
python3 scripts/validate-release-refs.py
find packaging/build/RPMS -type f -name '*.rpm' -print0 \\
  | sort -z \\
  | xargs -0 sha256sum
rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\\n' <artifact>.rpm
```

Para cada uno de los seis RPM Admiral se registrarán nombre, NEVRA, SHA-256,
commit fuente y resultado de `%check`. Los seis paquetes son:

- `admiral-common`;
- `admirald`;
- `admiral-fleet`;
- `admiralctl`;
- `admiral-flagship`;
- `admiral-harbor`.

En la VM se debe confirmar que DNF instala el candidato local o el RC1 COPR
intencionado, y que no se está mezclando silenciosamente una versión distinta
desde otro repositorio.

## 6. Preparación del laboratorio KVM

La guía base es `docs/local_kvm_cloud_setup.md`. El laboratorio debe usar
imágenes GenericCloud oficiales con checksum verificado, overlays QCOW2
descartables y cloud-init con únicamente la clave pública temporal.

### 6.0 Preparación efectiva del host

Se instalaron `libvirt-daemon-kvm`, `libvirt-client`, `virt-install` y la red
libvirt. El servicio `virtqemud` quedó activo y la red NAT persistente `default`
quedó activa/autostart. Se creó el directorio de evidencia temporal:

```text
/var/lib/libvirt/rc1/images
/var/lib/libvirt/rc1/evidence
```

Descargas iniciadas con checksum separado:

| OS | Fuente |
|---|---|
| Rocky 10.2 | `https://download.rockylinux.org/pub/rocky/10.2/images/x86_64/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2` |
| AlmaLinux 10.2 | `https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-10.2-20260526.0.x86_64.qcow2` |
| CentOS Stream 10 | `https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2` |

Las tres transferencias terminaron y el checksum directo coincidió:

| Archivo local | Tamaño observado | SHA-256 observado | Resultado |
|---|---:|---|---|
| `rocky.qcow2` | 519 MiB | `9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48` | PASS |
| `alma.qcow2` | 547 MiB | `47f2218668dd4776be140dd92fa3bea700be1766e2c7d88bdfd6a4b50f477b4d` | PASS |
| `centos.qcow2` | 2.2 GiB | `9116da2c148c2a3da55579238a543ee9bd238265eba89234201d680e19ae1fbc` | PASS |

Los tamaños y hashes corresponden respectivamente a los archivos oficiales
referenciados en la tabla anterior. Los tres archivos se conservan como bases
inmutables; los guests usarán overlays.

### 6.1 Single-node

Recursos por guest: mínimo 2 vCPU, 2 GiB RAM y overlay de aproximadamente 24
GiB. La red de instalación usa NAT con SSH publicado sólo en loopback del host.
No se deben publicar accidentalmente HTTP, HTTPS, Cockpit o PostgreSQL en el
host.

Para cada OS se registrarán:

- URL y nombre exacto de la imagen;
- SHA-256 y archivo de checksum;
- nombre del overlay;
- puerto SSH local;
- fingerprint SSH;
- hora de boot y fin de cloud-init;
- `getenforce`;
- ausencia inicial de paquetes/usuarios/servicios Admiral.

La instalación soportada se ejecutará con `admiral-install --single-node` y la
IP pública/NAT documentada para el guest. No se copiará la clave privada del
operador al guest.

### 6.2 Multinode

La topología requerida es una ejecución independiente por OS con tres guests:

```text
admin   --admin-node
worker  --worker-node
portal  --portal-node
```

Cada guest necesita salida NAT y una LAN privada compartida. Las direcciones
WireGuard de laboratorio se registrarán explícitamente, por ejemplo:

```text
admin  10.99.0.1
worker 10.99.0.2
portal 10.99.0.100
```

SSH sólo se usa para bootstrap/operación. El runtime debe usar la API
autenticada sobre WireGuard. Se comprobará que el worker no requiere ingress
público directo y que Caddy/admin enruta al endpoint WireGuard publicado.

## 7. Checklist común por guest

Antes de instalar:

```bash
cat /etc/os-release
getenforce
rpm -qa | grep -E '^(admiral|admirald)' || true
systemctl list-unit-files 'admiral*' || true
id admiral admiral-apps || true
```

Después de instalar:

```bash
systemctl --failed
systemctl list-units --type=service 'admiral*' --all
systemctl list-unit-files 'admiral*'
getenforce
firewall-cmd --list-all
ss -lntup
find /etc/admiral /etc -maxdepth 2 -type f -name '*admiral*' -printf '%m %u:%g %p\\n'
journalctl -b -p warning..alert --no-pager
ausearch -m avc -ts boot --success no --raw || true
```

Se verificarán además SELinux booleans requeridos, permisos `0600` de secretos,
PostgreSQL no expuesto públicamente, rootless Podman, `systemd` como cgroup
manager, subuid/subgid y linger del usuario de workloads.

## 8. Registro por escenario

### 8.1 Rocky Linux 10 — single-node

Estado final: `PASS`. El bloque histórico de esta sección conserva la
ejecución inicial y sus observaciones; la repetición y el gate de lifecycle
quedaron cerrados durante esta validación.

- Estado: `PASS`.
- Guest/image: `rc1-rocky-single`, Rocky Linux 10.2, `192.168.122.4`;
  GenericCloud SHA-256 `9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48`.
- checksum: imagen verificada antes de crear el overlay.
- SSH forward/fingerprint: acceso cloud-init por `admiraltest`; fingerprint
  temporal validada por el harness.
- RPMs instalados: los seis NEVRA RC1 esperados; `admiral-common-0.0.1rc1-122`,
  `admirald-51`, `admiralctl-49`, `admiral-fleet-59`, `admiral-harbor-50`,
  `admiral-flagship-82`, todos `.el10` y coincidentes con COPR.
- comando de instalación: `sudo admiral-install --single-node
  --public-ip 192.168.122.4 --ssh-public-key /home/admiraltest/.ssh/authorized_keys`.
- exit code: `0`.
- Ansible `failed/unreachable`: `failed=0`, `unreachable=0`, recap
  `ok=222 changed=100 skipped=125 rescued=0 ignored=0`.
- servicios: `admirald`, `admiral-fleet`, `admiral-harbor`,
  `admiral-flagship`, Caddy, PostgreSQL, firewalld y fail2ban `active`; sin
  unidades fallidas.
- seguridad: SELinux `Enforcing`; zona pública sólo `http https ssh`; puertos
  internos en loopback; secretos `0600 root:root`; Podman `rootless=true`,
  cgroup `systemd`, graph root `/var/lib/admiral-apps/.local/share/containers/storage`.
- WordPress provision operation: `op_0f0b75bde0cf826c`, instancia
  `inst_fe189ade76ba1822`, `status=succeeded`, `setup_completed=true`,
  `technical_status=running`, `health_status=healthy`.
- HTTP inicial: `HTTP 301` en `http://127.0.0.1:40000/`; cuatro contenedores
  rootless (infra, MariaDB, WordPress web y WordPress CLI setup).
- backup/checksum: DB `op_704a6ac0ec6e40f9`, backup
  `bk_639ff162d11dd757`, SHA-256 registrado
  `6cb1534e62372a34223bb81b44d37e62a6534c2d645d7389eb91954bb88f1149`;
  volumen `op_9f3ab87d4a219945`, backup `bk_d893ab491580bccc`, SHA-256
  registrado `2f958477af765b0613a2abdf5403da91401659c23d47a21d59f4ef06ec4ac58e`.
- pause operation y HTTP ausente: `op_85f62b06735f9b38` succeeded; estado
  `stopped`; conexión a `127.0.0.1:40000` rechazada.
- resume operation y HTTP restaurado: `op_03b0c818120eb953` succeeded; HTTP
  volvió a `301` después de un intento transitorio `500`.
- image update: aplicación temporal de `wordpress:6.8.1` produjo
  `need_restarting=true`; el primer `start_app` terminó con `signal: killed`
  en la VM de 2 GiB. Se elevó sólo la memoria del guest a 4 GiB y se repitió
  el restart; `op_09c782e0a1234e5d` succeeded, `need_restarting=false`, HTTP
  `301` y el inspect mostró digest `sha256:9ca181730570f82df91e301d2e53efc0ce2f98aa8112d2f95ef780bd341ffd12`
  para `wordpress:6.8.1`. El primer fallo queda clasificado como presión de
  capacidad del harness, no como defecto de Admiral.
- deprovision operation: `op_b09ea8ec2bd08258`, succeeded; estado técnico
  `deprovisioned`, comercial `cancelled`.
- limpieza directa: no quedaron pods, contenedores, volúmenes ni unidades
  Quadlet con el ID de instancia; el registro histórico `deprovisioned` se
  conserva en la base de datos para auditabilidad.
- AVC/unidades fallidas: no hay unidades fallidas observadas; no se detectó un
  AVC bloqueante del lifecycle.
- resultado final: instalación, lifecycle WordPress, actualización de imagen,
  deprovision y limpieza `PASS`.

### 8.2 CentOS Stream 10 — single-node

Estado final: `PASS`; la evidencia detallada y los IDs de operación están en
la sección 14.

- Checklist histórico completado; el detalle verificable está en la sección 14.
- Guest/image:
- checksum:
- SSH forward/fingerprint:
- RPMs instalados:
- comando de instalación:
- exit code:
- Ansible `failed/unreachable`:
- servicios:
- WordPress provision operation:
- HTTP inicial:
- backup/checksum:
- pause operation y HTTP ausente:
- resume operation y HTTP restaurado:
- deprovision operation:
- limpieza directa:
- AVC/unidades fallidas:
- resultado final:

### 8.3 AlmaLinux 10 — single-node

Estado final: `PASS`; la evidencia detallada y los IDs de operación están en
la sección 13.

- Checklist histórico completado; el detalle verificable está en la sección 13.
- Guest/image:
- checksum:
- SSH forward/fingerprint:
- RPMs instalados:
- comando de instalación:
- exit code:
- Ansible `failed/unreachable`:
- servicios:
- WordPress provision operation:
- HTTP inicial:
- backup/checksum:
- pause operation y HTTP ausente:
- resume operation y HTTP restaurado:
- deprovision operation:
- limpieza directa:
- AVC/unidades fallidas:
- resultado final:

### 8.4 Rocky Linux 10 — multinode

- Estado final: `PASS`; evidencia detallada en la sección 15.
- Admin guest/image/fingerprint:
- Worker guest/image/fingerprint:
- Portal guest/image/fingerprint:
- IPs LAN/WireGuard:
- RPMs y NEVRAs por nodo:
- instalación admin:
- instalación worker:
- instalación portal:
- peers/rutas/handshakes WireGuard:
- registro y health de worker:
- registro y health de portal:
- segmentación y listeners:
- WordPress en worker:
- HTTP por dirección publicada del worker:
- backup/pause/resume/deprovision:
- cleanup y auditoría:
- resultado final:

### 8.5 CentOS Stream 10 — multinode

- Estado final: `PASS`; evidencia detallada en la sección 17.
- Admin guest/image/fingerprint:
- Worker guest/image/fingerprint:
- Portal guest/image/fingerprint:
- IPs LAN/WireGuard:
- RPMs y NEVRAs por nodo:
- instalación admin:
- instalación worker:
- instalación portal:
- peers/rutas/handshakes WireGuard:
- registro y health de worker:
- registro y health de portal:
- segmentación y listeners:
- WordPress en worker:
- HTTP por dirección publicada del worker:
- backup/pause/resume/deprovision:
- cleanup y auditoría:
- resultado final:

### 8.6 AlmaLinux 10 — multinode

- Estado final: `PASS`; evidencia detallada en la sección 16.
- Admin guest/image/fingerprint:
- Worker guest/image/fingerprint:
- Portal guest/image/fingerprint:
- IPs LAN/WireGuard:
- RPMs y NEVRAs por nodo:
- instalación admin:
- instalación worker:
- instalación portal:
- peers/rutas/handshakes WireGuard:
- registro y health de worker:
- registro y health de portal:
- segmentación y listeners:
- WordPress en worker:
- HTTP por dirección publicada del worker:
- backup/pause/resume/deprovision:
- cleanup y auditoría:
- resultado final:

## 9. Defectos y cambios de código

Regla de clasificación:

- `PRODUCT DEFECT`: reproducible en guest limpio y atribuible al código/RPM.
- `ENVIRONMENTAL`: falta de capacidad, red, imagen, herramienta o limitación
  del harness, con evidencia que descarte producto.
- `BLOCKED`: no se puede ejecutar el gate sin autoridad/estado externo nuevo.

Si aparece un defecto de producto, se conservarán logs, operación, traceback,
NEVRA y pasos mínimos de reproducción. Cualquier corrección debe:

1. hacerse en el submódulo responsable;
2. usar commit semántico en inglés;
3. incluir `Signed-off-by: William J. Moreno <williamjmorenor@gmail.com>`;
4. añadir o actualizar pruebas;
5. actualizar el pin raíz y las referencias RPM;
6. incrementar `Release` de los seis RPM en cada rebuild;
7. ejecutar `python3 scripts/validate-release-refs.py`;
8. reconstruir y reiniciar la validación del candidato.

## 10. Comandos de cierre y evidencia

Al finalizar se guardarán en un directorio de evidencia fuera de los overlays:

```bash
git status --short --branch
git submodule status
python3 scripts/validate-release-refs.py
find packaging/build/RPMS -type f -name '*.rpm' -print0 | sort -z | xargs -0 sha256sum
```

Por cada guest se conservarán como mínimo `os-release`, SELinux, servicios,
firewall/listeners, logs de instalación, salida de operaciones WordPress,
checksums de backup y limpieza post-deprovision. Las claves privadas temporales
se destruirán al terminar la ejecución; nunca se copiarán al guest ni se
registrarán en esta bitácora.

## 11. Veredicto

Veredicto histórico de esta bitácora al momento de creación: **IN PROGRESS**.

Ese veredicto corresponde únicamente al momento de creación de la plantilla.
El veredicto actual, tras las ejecuciones registradas en las secciones 13–17,
es `PASS` para los seis escenarios de la matriz.

## 12. Análisis de `install.sh` y equivalencia empaquetada — 2026-08-07

### 12.1 Pruebas estáticas

| Prueba | Resultado |
|---|---:|
| `bash -n scripts/install.sh` | PASS |
| `python3 scripts/test_installer_modes.py` | PASS — 50 pruebas |
| `shellcheck scripts/install.sh` | NO EJECUTADA — no está instalado |
| Ejecución funcional | NO EJECUTADA en esta fase |

### 12.2 Fuente frente al RPM

El RPM `admiral-common-0.0.1rc1-122.el10.noarch.rpm` entrega el mismo
instalador como `/usr/bin/admiral-install`. Se extrajo el RPM y se comparó
contra `scripts/install.sh`. La única diferencia es la normalización del
shebang durante el empaquetado:

```diff
-#!/usr/bin/env bash
+#!/usr/bin/bash
```

El cuerpo del script y el orden de sus transacciones DNF son equivalentes.
SHA-256 observado:

```text
d63f88cc3a0789bca693391cd5882f2c87c208259670cbeb5bde58b88bd8eeff  scripts/install.sh
1143ec44b8a542096a5b4111926eb5f801f1734d4ca84e12b13cda60aaa73e1f  instalador extraído del RPM
```

### 12.3 Orden de repositorios antes de `dnf install admiral-*`

Para `single-node`, `admin-node` y `admin-portal-node`, el script hace lo
siguiente antes de instalar Admiral:

1. instala `epel-release`;
2. instala `dnf-plugins-core`;
3. habilita CRB con `dnf config-manager --set-enabled crb`;
4. habilita `@caddy/caddy` en COPR;
5. habilita `admiral-project/admiral` en COPR;
6. verifica ambos `.repo` y `gpgcheck=1`;
7. instala `ansible-core`;
8. instala en una transacción conjunta `admiral-common`, `admirald`,
   `admiralctl`, `admiral-fleet`, `admiral-harbor` y `admiral-flagship`.

La evidencia está en `scripts/install.sh:687-749`. Por tanto, la condición
indicada por el usuario sí se cumple para los `dnf install admiral-*` internos.

### 12.4 Bootstrap del RPM que contiene el instalador

`admiral-install` sólo existe después de instalar `admiral-common`. La
documentación propone ese RPM como paso previo. En una VM limpia, ese primer
comando no puede depender de que `install.sh` ya haya habilitado repositorios.

La secuencia que debe usarse para la prueba es:

```bash
dnf install -y epel-release dnf-plugins-core
dnf config-manager --set-enabled crb
dnf copr enable -y @caddy/caddy
dnf copr enable -y admiral-project/admiral
dnf install -y admiral-common
admiral-install --single-node --public-ip <IP>
```

Ejecutar `dnf install admiral-common` antes de EPEL/CRB/COPR puede fallar por
falta de origen para el paquete o para dependencias como `ansible-core`,
`ansible-collection-ansible-posix`, `wireguard-tools` y utilidades SELinux.
Ese fallo sería de bootstrap del procedimiento, no del cuerpo de
`install.sh`.

### 12.5 Spokes

`--worker-node` y `--portal-node` se ejecutan desde el admin y no preparan los
repositorios locales del spoke. El controlador debe tener `ansible-playbook`
y `admiral-common`; Ansible converge el nodo remoto según el contrato. No es
un `dnf install admiral-*` local independiente.

### 12.6 Gate antes de continuar

El gate de equivalencia fuente/RPM y orden de bootstrap queda `PASS`. El gate
global de RC1 queda `PASS`: la matriz single-node, multinode y el ciclo
funcional WordPress están documentados para las tres distribuciones.

### 13. Validación single-node: AlmaLinux 10

Fecha de ejecución: 2026-08-07 UTC. VM `rc1-alma-single`, IP
`192.168.122.68`, 2 vCPU, 2 GiB RAM, disco overlay de 24 GiB sobre la imagen
AlmaLinux 10.2. Se utilizó la clave SSH temporal del laboratorio; no se
registran aquí credenciales ni secretos generados por el instalador.

#### 13.1 Bootstrap reproducible

Se transfirieron a `/tmp` los RPM locales de producto y el manifiesto
`examples/apps/wordpress.yaml`. El primer bootstrap se ejecutó serialmente:

```bash
dnf install -y epel-release dnf-plugins-core
dnf config-manager --set-enabled crb
dnf copr enable -y @caddy/caddy
dnf copr enable -y admiral-project/admiral
dnf makecache
dnf install -y /tmp/admiral-common-0.0.1rc1-122.el10.noarch.rpm
```

Resultado: `PASS`. Se instalaron dependencias de AlmaLinux BaseOS/AppStream,
CRB y EPEL, quedaron habilitados los COPR de Caddy y Admiral, y
`/usr/bin/admiral-install` quedó disponible desde `admiral-common`.

#### 13.2 Instalación oficial

Se ejecutó una única vez el instalador empaquetado:

```bash
sudo admiral-install --single-node --public-ip 192.168.122.68 \
  --ssh-public-key /home/admiraltest/.ssh/authorized_keys
```

El instalador actualizó primero el sistema, instaló desde COPR los seis
paquetes RC1 exactos (`common-122`, `admirald-51`, `admiralctl-49`,
`fleet-59`, `harbor-50`, `flagship-82`) y ejecutó Ansible sin errores:

```text
ok=222 changed=100 unreachable=0 failed=0 skipped=125 rescued=0 ignored=0
```

La comprobación final de Harbor también pasó:

```text
admirald reachable at https://127.0.0.1:8080/api/v1/harbor_ping
Admiral installation completed.
```

Resultado del gate de instalación single-node en AlmaLinux: `PASS`.
El mensaje `restorecon: lstat(/var/log/caddy) failed` apareció durante un
scriptlet de Caddy, pero no provocó fallo de DNF ni del playbook; debe
mantenerse como observación de empaquetado y verificarse contra los servicios
finales.

#### 13.3 Post-instalación inmediata

La comprobación posterior encontró los ocho servicios esperados en estado
`active`: `admirald`, `admiral-fleet`, `admiral-harbor`, `admiral-flagship`,
`caddy`, `postgresql`, `firewalld` y `fail2ban`. No hubo unidades fallidas,
SELinux quedó `Enforcing`, y `/etc/admirald.ini` mostró permisos `0600` y
propietario `root:root`. La inspección de `/etc/admiral/secrets` sin privilegios
fue rechazada por permisos, comportamiento esperado para un inventario de
secretos; el control de permisos se considera satisfecho y no se expusieron
credenciales en la bitácora.

#### 13.4 Ciclo WordPress

La definición se aplicó con `admiralctl apps apply -f /tmp/wordpress.yaml`.
Se intentó primero el tier `standard`, que no existe en el manifiesto; el CLI
respondió correctamente `HTTP 404 - Tier not found for this app definition`.
La ejecución válida usó el tier declarado `small`.

- apply: `PASS`, aplicación `wp` aplicada.
- provision: `op_1696d91e3a38abe4`, instancia `inst_112770f836e7cf49`,
  `succeeded`.
- estado final tras setup: comercial `active`, técnico `running`.
- inspect: cuatro contenedores rootless (infra, MariaDB, WordPress web y CLI
  setup), todos `running`; cgroup bajo `user.slice`/systemd y storage en
  `/var/lib/admiral-apps/.local/share/containers/storage`.
- HTTP: `http://127.0.0.1:40000/` devolvió `301`.
- backup DB: `op_9e7a13c12b3ac440`, backup `bk_343545fa6c05e6e4`, SHA-256
  `14caaea81f23605247dab3773e65d3df8337657ba5d456efc29f8ec1c75fe186`.
- backup volumen: `op_db008194c3006b0e`, backup `bk_2ced77c3efa76c93`,
  SHA-256 `fdc3eaee4d7164882d1e72842e09c91d15c1adb06799f89c423e5c39dcf1ac10`.
- pause: `op_6efa773e719d186f`, `succeeded`; el endpoint devolvió `000` y
  conexión rechazada.
- resume: `op_a3a3d959477ac6e6`, `succeeded`; el endpoint volvió a `301`.
- image update: se aplicó temporalmente `wordpress:6.8.1`; restart
  `start=op_1a13b0b99c6078ab`, `stop=op_a7ea51098df50e96`, `succeeded`.
  Inspect confirmó `ImageDigest=sha256:9ca181730570f82df91e301d2e53efc0ce2f98aa8112d2f95ef780bd341ffd12`.
- deprovision: `op_21aeb869f21df916`, `succeeded`.
- limpieza: no quedaron unidades fallidas, contenedores con el ID de instancia
  ni el volumen `shared-site` en el storage rootless; se conserva el registro
  histórico para auditabilidad.

Resultado del ciclo WordPress base en AlmaLinux: `PASS` para apply,
provision/setup/health, HTTP, rootless, backups/checksums, pause/resume,
actualización de imagen y deprovision/cleanup. La restauración DB/volumen con
datos marcadores se cubrió en el gate multinodo Rocky; no es un requisito
adicional para declarar PASS el ciclo demo de esta matriz.

### 14. Validación single-node: CentOS Stream 10

Fecha de ejecución: 2026-08-07 UTC. VM `rc1-centos-single`, CentOS Stream 10
(Coughlan), IP `192.168.122.68`, 2 vCPU, 2 GiB RAM. La imagen no traía un
usuario cloud utilizable por SSH; se creó `admiraltest` offline en el overlay
con clave pública del laboratorio y sudo NOPASSWD. Esto es una preparación del
harness, no un cambio del instalador Admiral.

#### 14.1 Bootstrap e instalación

Se ejecutó el orden requerido: EPEL, `dnf-plugins-core`, CRB, Caddy COPR,
Admiral COPR y finalmente `admiral-common`. El RPM resolvió correctamente
`ansible-core`, la colección POSIX y `wireguard-tools` desde AppStream/EPEL.

El instalador ejecutó los seis NEVRA RC1 exactos desde COPR y finalizó con:

```text
ok=221 changed=100 unreachable=0 failed=0 skipped=126 rescued=0 ignored=0
admirald reachable at https://127.0.0.1:8080/api/v1/harbor_ping
Admiral installation completed.
```

Podman en CentOS es `6.0.2`. Durante la transacción apareció la observación
de scriptlet `restorecon: open(/var/log/caddy) failed: No such file or directory`,
sin convertir la transacción ni el playbook en error; se debe comprobar contra
el estado final de Caddy. Resultado del gate de instalación single-node en
CentOS Stream 10: `PASS`.

El ciclo WordPress, incluyendo deprovision/cleanup, quedó ejecutado y se
documenta en la subsección siguiente.

#### 14.2 Ciclo WordPress base

- apply: `PASS`, `wp` aplicado.
- provision: `op_bc6447986ec3ffa2`, instancia `inst_9b0f16bba097b3c5`,
  `succeeded`; cuatro contenedores rootless terminaron `running`.
- HTTP: `http://127.0.0.1:40000/` devolvió `301`.
- backup DB: `op_4f4c1a4055ee0996`, backup `bk_51da8379a9bf42b6`, SHA-256
  `4b9ad26be6a93b52b617e365ef7120d29038f71fe9a4bc8d698da5853842bf07`.
- backup volumen: `op_5856cc0b40fac41d`, backup `bk_9694c1c5e6d43ca9`,
  SHA-256 `472e04d70a789f76749b3e4f4b4f922c18e4ad06f827ec3976a62dc458afc06f`.
- pause/resume: `op_883578ba0d4d159e` y `op_bc1574440899ed66`, ambos
  `succeeded`; durante pause hubo conexión rechazada y después volvió `301`.
- image update: restart con `wordpress:6.8.1`,
  `start=op_2c4d213210fec651`, `stop=op_4604ed4793b1d330`, `succeeded`.
- deprovision/cleanup: `op_f9141421f98b2728`, `succeeded`; la inspección final
  confirmó la limpieza de unidades, contenedores y volumen remanente.

Resultado del ciclo base CentOS Stream 10: `PASS` en apply, provision/setup,
HTTP, backups/checksums, pause/resume, image update y deprovision. Restore con
datos marcadores se cubrió en Rocky multinodo; la validación multinodo CentOS
está documentada en la sección 17.

### 15. Validación multinodo: Rocky Linux 10

Fecha de ejecución: 2026-08-07 UTC. Esta es la primera topología multinodo
completa de la matriz. Se usaron cuatro overlays Rocky Linux 10.2 para separar
roles y repetir el bootstrap del rol portal en una VM limpia:

| Rol | VM | IPv4 libvirt | IPv4 WireGuard | Identidad |
|---|---|---:|---:|---|
| admin | `rc1-rocky-admin` | `192.168.122.140` | `10.99.0.1` | control plane + Harbor + Flagship |
| worker | `rc1-rocky-worker` | `192.168.122.141` | `10.99.0.2` | `rocky-worker-01` |
| portal inicial | `rc1-rocky-portal` | `192.168.122.142` | `10.99.0.100` | `rocky-portal-01` |
| portal limpio | `rc1-rocky-portal-fixed` | `192.168.122.143` | `10.99.0.101` | `rocky-portal-fixed` |

El portal inicial se conserva como evidencia de la primera ejecución; el
portal limpio se utilizó para repetir el one-shot después de corregir la
carrera de SSH. La preparación offline del usuario `admiraltest` y del perfil
DHCP NetworkManager pertenece al harness libvirt y no al instalador.

#### 15.1 Bootstrap del admin y worker

Antes de cualquier `dnf install admiral*` se verificó en cada guest el orden
obligatorio del instalador: `epel-release`, `dnf-plugins-core`, CRB, Caddy COPR,
Admiral COPR y luego una transacción única de los RPM Admiral. La versión
empaquetada se ejecutó mediante `admiral-install`; la fuente equivalente se
comparó previamente con el cuerpo extraído de `/usr/bin/admiral-install`.

El admin terminó con exit code `0` y recap Ansible:

```text
ok=193 changed=97 unreachable=0 failed=0 skipped=153
```

`admirald`, PostgreSQL, Harbor, Harbor worker/timers, Flagship, Caddy,
firewalld, auditd, fail2ban y `wg-quick@wg-admiral` quedaron activos. SELinux
quedó `Enforcing`; `systemctl --failed --no-legend` no produjo unidades. El
handshake WireGuard del worker apareció en el primer intento.

El worker terminó con exit code `0` y recap:

```text
ok=145 changed=58 unreachable=0 failed=0 skipped=199
```

El nodo quedó registrado como `active/healthy/available=true`, con
`admiral-fleet 0.0.1rc1`, Podman `5.8.2` y endpoint WireGuard `10.99.0.2`.
La salida de `admiralctl nodes list --output json` confirmó que el worker no
se registró por su IP libvirt sino por la identidad privada esperada.

#### 15.2 Portal, carrera detectada y repetición limpia

La primera ejecución del portal obtuvo:

```text
ok=190 changed=87 unreachable=0 failed=0 skipped=154
WireGuard handshake: PASS
Per-node SSH identity stopped working after bootstrap revocation.
```

La clasificación inicial fue `PRODUCT_DEFECT`: el one-shot verificaba una
identidad que acababa de ser revocada sin tolerar la convergencia del canal
SSH. Se añadió una espera activa de diez intentos de un segundo en
`scripts/install.sh`, junto con una prueba del modo portal. La sintaxis Bash y
las 51 pruebas del instalador pasaron.

El portal limpio se ejecutó después con los RPM reconstruidos. Resultado:

```text
ok=190 changed=88 unreachable=0 failed=0 skipped=154
Bootstrap SSH credential revoked; per-node admiral-ssh identity is now authoritative.
Admiral installation completed.
```

El portal limpio mostró activos PostgreSQL, Harbor, sus timers, firewalld,
auditd, fail2ban y WireGuard; SELinux quedó `Enforcing`, Harbor respondió a
`harborctl ping` y `systemctl show -p Result admiral-harbor-catalog-sync.service`
devolvió `Result=success`.

Durante la primera ejecución, el reinicio del servicio Harbor terminó un
catálogo en `SIGTERM`, pero dejó una auditoría `in_progress`. El siguiente
timer falló repetidamente con `Sync already in progress`, aunque la red y el
portal estaban sanos. Se clasificó como `PRODUCT_DEFECT` y se corrigió en
`admiral-harbor/app/catalog_service.py`: una auditoría `in_progress` de más de
cinco minutos se marca como abandonada antes de comenzar una sincronización
nueva. La corrección tiene 13 pruebas de catálogo exitosas.

La evidencia posterior al fix contiene:

```text
Marked abandoned catalog sync sync_2e95f42f17bd4f19 as failed
Catalog sync completed: 0 new, 0 updated, 0 marked missing
```

#### 15.3 RPM utilizado en la repetición corregida

Los seis paquetes se reconstruyeron juntos, incrementando `Release` en todos,
y `python3 scripts/validate-release-refs.py` pasó. NEVRA y SHA-256 local:

| Paquete | NEVRA | SHA-256 |
|---|---|---|
| common | `admiral-common-0.0.1rc1-124.el10.noarch` | `76503951434609294043abff7e8599b5a68d6edd1b17c9a5a38536705b82a89c` |
| admirald | `admirald-0.0.1rc1-53.el10.x86_64` | `a70b1b5320d70fc4fabbf590c26b274fceb62a5a5109b33ef0a9ef8422e57ba9` |
| fleet | `admiral-fleet-0.0.1rc1-61.el10.x86_64` | `0e7867d5ea82dfc00d89f0f6148a455ad1cac6bbf3179e63042e36c461ed76ed` |
| admiralctl | `admiralctl-0.0.1rc1-51.el10.x86_64` | `e1dd055c4e07b8f157627464e6c5aa52d046c7ec12351a6503324721d8dd9258` |
| flagship | `admiral-flagship-0.0.1rc1-84.el10.noarch` | `fefff097c5b3532159fea7121f2868c3c3f7afc82abc2cd8356a15d4e4952472` |
| harbor | `admiral-harbor-0.0.1rc1-52.el10.noarch` | `f79e8a7e0283cbc917508020840326e2455bf59d4864bd53bbca74298e430571` |

Los cambios quedaron firmados en `9f29ec8 fix(catalog): recover abandoned
synchronization`, con el pin del superproyecto y la Release conjunta en los
commits root `dec12bcf` y `e43b0ee`. El portal limpio recibió `admiral-common`
y `admiral-harbor` desde este conjunto; el admin recibió el conjunto común y
los binarios de control.

#### 15.4 Ciclo WordPress en worker Rocky

Se aplicó `examples/apps/wordpress.yaml` como `wp` y se seleccionó
explícitamente `rocky-worker-01`; no se validó accidentalmente el loopback del
admin. La operación y la inspección fueron:

- provision/setup: `op_a4138de24f0eec78`, instancia
  `inst_4d149ef5965fca11`, `succeeded`; `setup_completed=true`,
  `technical_status=running`, `health_status=healthy`.
- inspect: cuatro contenedores rootless (infra, MariaDB, WordPress web y CLI
  setup), cgroup `user.slice`/systemd, almacenamiento bajo
  `/var/lib/admiral-apps/.local/share/containers/storage` y publicación
  `10.99.0.2:40000`.
- HTTP: `curl http://10.99.0.2:40000/` devolvió `301`.
- backup DB: operación `op_9cc3cf95471ceff9`, backup
  `bk_a86c23f2183e6d6f`, SHA-256
  `54f6658a5f4979e49f726a69893f4da4e8aebcd7baea568802483bf85d5f4765`.
- backup volumen: operación `op_222c90666dad3a2b`, backup
  `bk_83dc1551abb3cc62`, SHA-256
  `9130a714ce035db0102976fb89382cdce6bd625430e9c71a4b2919c23cbd489f`.
- pause/resume: `op_cf95352c17ec8b32` y `op_72b252f2f86f963c`, ambos
  `succeeded`; el endpoint dio `000` durante pause y `301` después de resume.
- image update: se aplicó temporalmente `wordpress:6.8.1`; stop
  `op_7d1a12cf169d0597` y start `op_3ef4735e8b928bcf` fueron `succeeded`.
  Una inspección nueva confirmó `ImageName=wordpress:6.8.1`, digest
  `sha256:9ca181730570f82df91e301d2e53efc0ce2f98aa8112d2f95ef780bd341ffd12`,
  HTTP `301` y `need_restarting=false`.

#### 15.5 Restore con datos marcadores y limpieza

Para respetar el gate de restore se aplicó una definición temporal
`wp-restore` con `restore_allowed=true`. En la instancia fuente se creó el
archivo `rc1-rocky-marker.txt` con valor `rc1-rocky-volume-marker` y una tabla
MariaDB `rc1_validation_marker` con valor `rc1-rocky-db-marker`. Los backups
fuente adicionales fueron `bk_43526ae7688a8bfc` (DB, SHA-256
`915e7f64bbd0db6fb4366c1bc3a055567b1906fcf896e2036814a9ba3cc7524b`) y
`bk_ec5f2d824ff1999b` (volumen, SHA-256
`1f8fda868d15b027b614ade33c136f5763316d283ad6c47ffabcb4d893991a34`).

La instancia destino fue `inst_fc0614cc0251cf90` (`wp-restore`, nodo
`rocky-worker-01`). Provision `op_2a9c825bf76cf21f` y pause
`op_b5163d972f789cbb` fueron exitosos. El restore DB `op_a5a6ce6f88385365`
y restore volumen `op_f3dbe6d164da1466` terminaron `succeeded` con verificación
de checksum. El producto exige que la instancia esté pausada antes de cada
restore; por eso se volvió a pausar con `op_a2d5561620c0d96e` entre DB y
volumen. Resume `op_43b981aa593666ea` fue exitoso.

La comprobación directa dentro de los contenedores restaurados produjo,
concatenados sin separador por el comando de shell:

```text
rc1-rocky-volume-marker
rc1-rocky-db-marker
```

El ciclo terminó con deprovision exitoso de fuente y destino:
`op_ed48bab4135b48d0` y `op_e5049ede1297d470`. Ambas filas quedaron
`technical_status=deprovisioned`, `commercial_status=cancelled`; no quedaron
contenedores ni volúmenes runtime con esos IDs y el historial permaneció en
PostgreSQL para auditoría.

Resultado Rocky multinodo: `PASS` para one-shot admin/worker/portal, registro
WireGuard, Harbor/portal, WordPress en worker, backups/checksums, pause/resume,
image update, restore DB/volumen con marcadores y deprovision/cleanup. Los
gates equivalentes de AlmaLinux y CentOS están documentados en las secciones
16 y 17.

### 16. Validación multinodo: AlmaLinux 10

Fecha: 2026-08-07 UTC. Topología limpia: admin `192.168.122.27`, worker
`192.168.122.28` (`alma-worker-01`, WireGuard `10.99.0.2`) y portal
`192.168.122.29` (`alma-portal-01`, WireGuard `10.99.0.100`). Se habilitaron
EPEL, CRB, Caddy COPR y Admiral COPR antes de instalar; se usó el conjunto
local de seis RPM `124/53/61/51/84/52`.

El admin terminó con PostgreSQL, Caddy, admirald, Flagship, firewalld, auditd,
fail2ban y WireGuard activos, SELinux `Enforcing` y cero unidades fallidas.
Los spokes se configuraron desde el admin con fingerprints
`SHA256:Dt4ZI77/cjMtZZ/x+GV8aHkzPcLDFZyvRtLxX9TmPMU` (worker) y
`SHA256:32T0GfB9RGOuK8eScPzBGAhqw7v+ctGPquOTGzOUzCs` (portal). Ambos
revocaron la clave bootstrap. `admiralctl nodes list` confirmó worker y portal
`active/healthy/available=true`; el worker reportó fleet `0.0.1rc1`, Podman
`5.8.2`, AlmaLinux `10.2`, y Harbor ping pasó por `10.99.0.1`.

El primer timer de catálogo fue terminado con `SIGTERM` durante el bootstrap y
el siguiente vio `Sync already in progress`. Tras cinco minutos, el mismo RPM
recuperó el estado huérfano:

```text
Result=success
Marked abandoned catalog sync sync_c212bd6edafc47ae as failed
Catalog sync completed: 0 new, 0 updated, 0 marked missing
```

El ciclo WordPress se ejecutó sobre `alma-worker-01`:

- apply y provision/setup: `op_beedd7ba1b860840`, instancia
  `inst_758f207cb1f49f75`, `running/healthy`, setup completado.
- HTTP real hacia `10.99.0.2:40000`: `301`.
- backup DB `op_63778ae910b9faed` y volumen `op_394d83e5707c8d0f`:
  ambos `succeeded`.
- pause `op_d6ef0b43812ee2f9`: `succeeded`, comprobación inmediata `HTTP=000`.
  Resume `op_28fd2a66806fff61`: `succeeded`, HTTP restaurado.
- image update: `op_30688adbcddb47a7` falló al descargar `wordpress:6.8.1`
  con `signal: killed` en un worker de 768 MiB; se clasificó presión de
  capacidad del harness. Con 1.5 GiB, stop `op_51210fc986570d20` y start
  `op_ec6d0a5d29c8f7f6` pasaron; inspección confirmó digest
  `sha256:9ca181730570f82df91e301d2e53efc0ce2f98aa8112d2f95ef780bd341ffd12`
  y HTTP `301`.
- deprovision/cleanup: `op_4c0e86ef44de801d`, `succeeded`; estado final
  `deprovisioned/cancelled`.

Resultado Alma multinodo: `PASS` para one-shot admin/worker/portal, registro
WireGuard, Harbor, WordPress en worker, backups, pause/resume, image update
tras ajuste de capacidad y deprovision. Restore DB/volumen con marcadores se
cubrió en Rocky.

### 17. Validación multinodo: CentOS Stream 10

Fecha: 2026-08-07 UTC. Topología limpia: admin `192.168.122.167`, worker
`192.168.122.168` (`centos-worker-01`, WireGuard `10.99.0.2`) y portal
`192.168.122.169` (`centos-portal-01`, WireGuard `10.99.0.100`). Antes de
cualquier instalación de componentes se habilitaron EPEL, CRB, Caddy COPR y
Admiral COPR en los hosts; los paquetes se instalaron desde el conjunto local
RC1, no desde una resolución accidental de `admiral*` contra un repositorio
incompleto:

```text
admiral-common-0.0.1rc1-124.el10.noarch
admirald-0.0.1rc1-53.el10.x86_64
admiral-fleet-0.0.1rc1-61.el10.x86_64
admiralctl-0.0.1rc1-51.el10.x86_64
admiral-flagship-0.0.1rc1-84.el10.noarch
admiral-harbor-0.0.1rc1-52.el10.noarch
```

El `--admin-node` terminó con `ok=192 changed=97 failed=0 unreachable=0
skipped=154`. La configuración dejó PostgreSQL, Caddy, admirald, Flagship,
firewalld, auditd, fail2ban y WireGuard configurados; la instalación verificó
SELinux y las reglas nftables. El `--worker-node` terminó con
`ok=144 changed=53 failed=0 unreachable=0 skipped=200`; el handshake de
WireGuard se verificó en el primer intento y Podman reportó `6.0.2`. El
`--portal-node` terminó con `ok=189 changed=82 failed=0 unreachable=0
skipped=155`; el handshake se verificó en el primer intento, Harbor quedó
registrado y sus timers fueron habilitados. En ambos spokes se verificaron
fingerprints de host antes de Ansible y se revocó la clave bootstrap al final:

```text
worker host: SHA256:VQUfnV0LijJlqkVoBKovNpaO7ZTMPnKw9BePa9nq7vk
portal host: SHA256:AqKcmBVHVrjDPH0Dzc31s6r/Q4Hfd5UTLR/IVufuMPE
worker admin identity: SHA256:sbVViZ8ggzWlCXcT0tCKdENr+VdEvIdhUzAuysUzJ0Y
portal admin identity: SHA256:mwOTJzpdUAfDWg6wrE7rZer+R9iydB5FRwg2b0dZzF4
```

`admiralctl nodes list` confirmó ambos spokes `active`, `healthy` y
`available_for_provisioning=true`. El worker reportó CentOS 10,
`fleet_version=0.0.1rc1`, Podman `6.0.2`, y el portal reportó Harbor activo
con la ruta WireGuard `10.99.0.100`. En estas imágenes CentOS quedó además
`kdump.service` fallido, igual que en las imágenes de laboratorio anteriores;
es una limitación del perfil de la imagen y no una unidad Admiral. No se
contabilizó como fallo funcional del rol, pero queda visible para el operador.

La primera ejecución del timer de catálogo fue terminada por systemd con
`SIGTERM` durante el arranque. El RPM con recuperación de sincronizaciones
abandonadas detectó y cerró ese estado, y la ejecución siguiente terminó bien:

```text
Result=success
Marked abandoned catalog sync sync_8851cce83f7e47b1 as failed
Catalog sync completed: 0 new, 0 updated, 0 marked missing
```

El ciclo WordPress se ejecutó sobre `centos-worker-01`, instancia
`inst_e34993bb6aeca2dd`:

- provision/setup: `running/healthy`, `setup_completed=true` y
  `storage_state=ok`.
- HTTP real hacia `10.99.0.2:40000`: `301`.
- backup DB `op_9d9ca6dd0e6f918b`, backup de volumen
  `op_7b3dc45008636594`; ambos `succeeded`, con backups
  `bk_f28e9632fcddcf6e` (SHA-256
  `28218e9f02332ffaa6cda4fcfb29dbc674ceeaf15256a950ed88f09a41b25315`) y
  `bk_0126b6cb5ad9defd` (SHA-256
  `28155478f9fe9b86659d9e56128c60c9dc0f89406772b9d55c81f89a72ac27a7`).
- pause `op_d00f5d780a9eb3cf`: `succeeded`; comprobación inmediata
  `HTTP=000`. Resume `op_99b3f25457190ab4`: `succeeded`.
- image update a `wordpress:6.8.1`: la primera descarga falló con
  `op_078b4278d22c207f` y `signal: killed` en el worker de 768 MiB. Se
  clasificó como presión de memoria del harness, igual que en Alma. Después
  de ampliar el worker a 1.5 GiB, stop `op_432931eecc160c06` y start
  `op_7442fa6472c28ea2` del restart fueron exitosos. La inspección
  `op_e155d12b07e1a962` confirmó la imagen `docker.io/library/wordpress:6.8.1`
  con digest
  `sha256:9ca181730570f82df91e301d2e53efc0ce2f98aa8112d2f95ef780bd341ffd12`.
- deprovision/cleanup: `op_d3052abec8d9e234`, `succeeded`; la instancia quedó
  deprovisionada y no quedaron contenedores ni volúmenes runtime activos.

Resultado CentOS multinodo: `PASS` para one-shot admin/worker/portal, repos
previos a la instalación, registro WireGuard, Harbor, WordPress en worker,
backups con checksum, pause/resume, image update tras ajuste de capacidad y
deprovision. Restore DB/volumen con marcadores ya está validado en Rocky;
la cobertura funcional de instalación y ciclo operativo queda completada en
los tres sistemas objetivo.

### 18. Resultado de la matriz multinodo

La matriz RC1 de instalación one-shot queda cerrada para Rocky Linux 10,
AlmaLinux 10 y CentOS Stream 10. En cada sistema se validaron roles separados
admin/worker/portal, repositorios EPEL/CRB/COPR antes de instalar, identidad
SSH posterior al bootstrap, WireGuard, salud de nodos y ciclo WordPress.
Rocky incluye además el gate explícito de restore DB/volumen con marcadores;
Alma y CentOS cubren el mismo ciclo de operación y actualización de imagen.

### 19. Validación del último release publicado en COPR — ejecución nueva

Estado actualizado al `2026-08-07T11:59:27Z`: `IN PROGRESS`. Esta sección corresponde a
una ejecución independiente de la matriz y no reutiliza los resultados de las
secciones anteriores como evidencia de instalación. El objetivo de este gate
es validar únicamente los RPM que COPR está compilando ahora, en máquinas
virtuales frescas, y conservar tanto los resultados positivos como los fallos
de infraestructura o empaquetado.

#### 19.1 Fuente del release y regla de selección

Se consultó la API pública de COPR para
`admiral-project/admiral`. La página HTML está protegida por Anubis, por lo
que la API JSON es la fuente operativa utilizada para observar los builds. La
nueva tanda visible en COPR es:

| Build COPR | Paquete | Versión | Estado inicial |
|---:|---|---|---|
| `10835523` | `admiral-common` | `0.0.1rc1-124` | `succeeded` |
| `10835524` | `admiral-flagship` | `0.0.1rc1-84` | `succeeded` |
| `10835525` | `admiral-fleet` | `0.0.1rc1-61` | `succeeded` |
| `10835526` | `admiral-harbor` | `0.0.1rc1-52` | `succeeded` |
| `10835527` | `admiralctl` | `0.0.1rc1-51` | `succeeded` |
| `10835528` | `admirald` | `0.0.1rc1-53` | `succeeded` |

Los seis builds fueron enviados al mismo tiempo (`submitted_on` equivalente
en la API). En la reconsulta final de `2026-08-07T11:59:27Z`, los seis
terminaron con `succeeded` y ya tienen `ended_on`. Los builds anteriores
`10827914`–`10827919` son versiones antiguas ya exitosas y quedan excluidos de
esta ejecución. No se usará ningún RPM anterior como sustituto si uno de los
seis builds nuevos falla o todavía no aparece en metadata DNF.

#### 19.2 Preparación del laboratorio fresco

Las VMs de la ejecución anterior permanecen separadas de esta matriz. Las
máquinas `rc1-rocky-*`, `rc1-alma-*` y `rc1-centos-*` existentes no se tomarán
como guests de prueba para este release. Se crearán overlays nuevos sobre las
imágenes base verificadas:

```text
/var/lib/libvirt/rc1/images/rocky.qcow2
/var/lib/libvirt/rc1/images/alma.qcow2
/var/lib/libvirt/rc1/images/centos.qcow2
```

Cada overlay tendrá usuario cloud-init nuevo del harness, 2 vCPU, memoria
registrada por guest y estado limpio de paquetes/configuración Admiral. Antes
de instalar se documentarán `os-release`, SELinux, estado de firewalld,
paquetes Admiral ausentes y la dirección DHCP obtenida.

#### 19.3 Gate obligatorio de disponibilidad DNF

La validación funcional no comenzará hasta que cada VM fresca confirme, con
los repositorios habilitados antes del install, que los seis NEVRA están
disponibles desde COPR:

```bash
sudo dnf makecache --refresh
sudo dnf repoquery --available --qf '%{name}-%{epoch}:%{version}-%{release}.%{arch}' \
  admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor
```

El resultado esperado es exactamente `124/53/61/51/84/52` para los seis
paquetes, con arquitectura `noarch` para `common`, `flagship` y `harbor`, y
`x86_64` para `admirald`, `fleet` y `admiralctl`. También se conservará la
salida de `dnf repolist` demostrando EPEL, CRB, Caddy COPR y Admiral COPR
habilitados antes de resolver dependencias.

Si DNF todavía devuelve los builds anteriores o no devuelve un paquete, el
resultado del gate será `WAITING_FOR_COPR`, no `PASS`; se registrará el
timestamp de cada reconsulta y no se avanzará con una mezcla de releases.

#### 19.4 Gates funcionales previstos

Para cada OS se ejecutará, en VM fresca, el instalador empaquetado y se
registrarán los recaps completos:

1. `--single-node`, incluyendo repositorios, Ansible, servicios de seguridad,
   SELinux, listeners, Podman rootless, WordPress, HTTP, backups con checksum,
   pause/resume, actualización de imagen y deprovision/cleanup.
2. Topología separada `--admin-node` + `--worker-node` + `--portal-node`, con
   fingerprints SSH, revocación de bootstrap, peers/handshakes WireGuard,
   registro y health de ambos spokes, Harbor, WordPress publicado por la IP
   WireGuard del worker y el mismo lifecycle completo.
3. Cada operación se anotará con su `operation_id`, `task_id`, estado final,
   timestamps, checksum y salida HTTP observada. Los fallos de memoria del
   harness se registrarán por separado de los errores funcionales y se repetirá
   el gate con capacidad suficiente.

#### 19.5 Confirmación DNF del conjunto nuevo

Se crearon tres overlays nuevos y se obtuvieron sus direcciones mediante
`guest-network-get-interfaces` del agente QEMU. Las leases DHCP históricas
(`.112`, `.252` y `.139`) fueron descartadas: no se usaron para conectarse ni
como evidencia.

| OS | VM fresca | IP usada | Resultado previo | Repos habilitados antes de resolver |
|---|---|---:|---|---|
| Rocky Linux 10.2 | `rc2-rocky-single` | `192.168.122.155` | no había paquetes Admiral instalados | Admiral COPR, Caddy COPR, CRB, EPEL |
| AlmaLinux 10.2 | `rc2-alma-single` | `192.168.122.42` | no había paquetes Admiral instalados | Admiral COPR, Caddy COPR, CRB, EPEL |
| CentOS Stream 10 | `rc2-centos-single` | `192.168.122.182` | no había paquetes Admiral instalados | Admiral COPR, Caddy COPR, CRB, EPEL |

La preparación del host también quedó registrada: se creó y activó
`/var/swapfile` de 4 GiB, se añadió a `/etc/fstab`, y se apagaron todas las
VMs anteriores antes de encender estas VMs. Cada consulta ejecutó
`dnf makecache --refresh` después de habilitar EPEL, CRB, Caddy COPR y Admiral
COPR.

La consulta exacta `dnf repoquery --available --latest-limit=1` confirmó el
mismo conjunto completo en los tres sistemas:

```text
admiral-common   0.0.1rc1-124.el10.noarch
admirald         0.0.1rc1-53.el10.x86_64
admiral-fleet    0.0.1rc1-61.el10.x86_64
admiralctl       0.0.1rc1-51.el10.x86_64
admiral-flagship 0.0.1rc1-84.el10.noarch
admiral-harbor   0.0.1rc1-52.el10.noarch
```

Este bloque apareció para Rocky, Alma y CentOS sin diferencias de NEVRA. Por
tanto, el gate de publicación DNF pasa para los tres OS (`DNF PASS`). Este
resultado sólo demuestra disponibilidad del conjunto nuevo; todavía no
demuestra instalación funcional ni sustituye la matriz one-shot pendiente.

#### 19.6 Estado actual

`COPR BUILD PASS` y `DNF PASS` para las tres VMs frescas. El siguiente paso
obligatorio es instalar y validar `--single-node` en estas mismas VMs, sin
reutilizar ningún resultado de las secciones anteriores. Después se destruirán
los overlays de single-node y se crearán topologías multinodo nuevas por OS.

#### 19.7 Instalación fresh y requisito de operación de `admiralctl`

La instalación del paquete nuevo se ejecutó con el binario empaquetado
`/usr/bin/admiral-install`, no con el script del árbol fuente. En cada VM se
confirmaron antes de lanzar el rol las seis versiones `rc1` de esta tanda.

| OS | Recap | Resultado del instalador | Podman | Verificación inmediata |
|---|---|---|---|---|
| Rocky Linux 10.2 | `ok=222 changed=100 unreachable=0 failed=0 skipped=125` | completado | 5.8.2 | `harbor_ping` autenticado exitoso; worker pasó de `registered/unhealthy` durante el primer health check a `active/healthy/true` en la reconsulta |
| AlmaLinux 10.2 | `ok=222 changed=100 unreachable=0 failed=0 skipped=125` | completado | 5.8.2 | `harbor_ping` autenticado exitoso; worker y portal `active/healthy/true` |
| CentOS Stream 10 | `ok=221 changed=100 unreachable=0 failed=0 skipped=126` | completado | 6.0.2 | `harbor_ping` autenticado exitoso; worker y portal `active/healthy/true` |

Los ocho servicios de cada VM (`admirald`, `admiral-fleet`,
`admiral-harbor`, `admiral-flagship`, `caddy`, `postgresql`, `firewalld` y
`fail2ban`) quedaron `active`. Las seis NEVRA instaladas fueron exactamente:

```text
admiral-common-0.0.1rc1-124.el10.noarch
admiralctl-0.0.1rc1-51.el10.x86_64
admirald-0.0.1rc1-53.el10.x86_64
admiral-flagship-0.0.1rc1-84.el10.noarch
admiral-fleet-0.0.1rc1-61.el10.x86_64
admiral-harbor-0.0.1rc1-52.el10.noarch
```

La prueba operativa demostró una condición importante del setup: ejecutar
`admiralctl` como el usuario operador sin configuración adicional falla con
`no authentication token configured`, y usar directamente
`/etc/admiral/tls/ca.pem` falla por permisos. No se relajaron los permisos de
los secretos. La forma válida posterior al setup fue preparar el entorno del
usuario con `ADMIRAL_ADMIN_TOKEN` leído por una operación privilegiada y una
copia temporal, legible y no secreta de la CA; por ejemplo, la CA temporal se
copió a `/tmp/rc2-ca.pem` con propietario `admiraltest`, mientras
`/etc/admiral/secrets` permaneció protegido.

Con esa configuración, AlmaLinux ejecutó realmente el flujo completo:

- `admiralctl apps validate -f /tmp/wordpress.yaml`: `YAML Validation: PASSED`.
- `admiralctl apps apply`: aplicación `wp` aplicada.
- provision: `op_77b36a456d3b2ff3`, task `task_ccabfd8565c0f4e2`, instancia
  `inst_15f5e12f1222e9a1`, `succeeded`.
- inspect: operación `op_29c5cbd538435156` encolada; la instancia terminó
  `commercial=active`, `technical=running`, `storage=ok`.
- HTTP real de WordPress: `301` en `127.0.0.1:40000`.
- backup de base de datos: `op_da1131e4cea9a012`, task
  `task_7929516a8ddf0cbd`, `succeeded`.
- backup de volumen: `op_f43891463d5a942a`, task `task_b1c82459426caf11`,
  `succeeded`.
- pause: `op_dff846ee6e7ad78b`, `succeeded`; HTTP inmediato `000`.
- resume: `op_2498b083a44c59fc`, `succeeded`; tras 15 segundos HTTP `301` y
  la instancia volvió a `active/running/storage=ok`.
- deprovision: `op_d78536975ceb5d76`, task `task_1bcf5935208b633a`,
  `succeeded`; estado final `cancelled/deprovisioned`, sin contenedores de la
  instancia.

En este punto el usuario ordenó detener la ejecución. Se cancelaron las
sesiones de provisionamiento que se habían iniciado en Rocky y CentOS después
de completar la instalación; no se declara lifecycle `PASS` para esos dos OS
en esta sección. La matriz multinodo fresh tampoco se inició. Por tanto, el
estado global de esta ejecución queda `PARTIAL / STOPPED`: COPR, DNF,
instalación one-shot y operación post-setup de `admiralctl` están demostrados;
faltan el lifecycle WordPress de Rocky/CentOS y la matriz multinodo fresh.
