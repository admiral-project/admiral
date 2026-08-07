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
| Rocky single-node | NOT TESTED IN THIS RUN | Sin VM iniciada todavía |
| CentOS Stream single-node | NOT TESTED IN THIS RUN | Sin VM iniciada todavía |
| AlmaLinux single-node | NOT TESTED IN THIS RUN | Sin VM iniciada todavía |
| Rocky multinode | NOT TESTED IN THIS RUN | Sin topología iniciada todavía |
| CentOS Stream multinode | NOT TESTED IN THIS RUN | Sin topología iniciada todavía |
| AlmaLinux multinode | NOT TESTED IN THIS RUN | Sin topología iniciada todavía |
| Bitácora | IN PROGRESS | Este documento se actualiza durante la ejecución |

No se declara PASS global hasta que los seis escenarios de la matriz tengan
evidencia directa y reproducible.

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

- Estado: `IN PROGRESS — INSTALL PASS, LIFECYCLE PARTIAL`.
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
- AVC/unidades fallidas: no hay unidades fallidas observadas; revisión AVC final
  pendiente.
- resultado final: instalación y lifecycle base PASS; gate WordPress completo
  aún no cerrado hasta deprovision, limpieza y los checks restantes.

### 8.2 CentOS Stream 10 — single-node

- Estado: `NOT TESTED IN THIS RUN`.
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

- Estado: `NOT TESTED IN THIS RUN`.
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

- Estado: `NOT TESTED IN THIS RUN`.
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

- Estado: `NOT TESTED IN THIS RUN`.
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

- Estado: `NOT TESTED IN THIS RUN`.
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

Veredicto de esta bitácora al momento de creación: **IN PROGRESS**.

La falta de resultados en las seis filas no implica fallo de Admiral; implica
que todavía no se ha ejecutado el escenario correspondiente. El veredicto sólo
se cambiará a `PASS`, `PASS WITH KNOWN ISSUES` o `BLOCKED` después de completar
la auditoría requisito por requisito con evidencia actual.

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
global de RC1 permanece abierto hasta completar la matriz single-node,
multinode y el ciclo funcional WordPress en las tres distribuciones.

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
secretos; la verificación privilegiada queda pendiente junto con el resto del
gate funcional.

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
actualización de imagen y deprovision/cleanup. Restauración DB/volumen y
datos marcadores en una segunda instancia aún son gates pendientes.

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

El ciclo WordPress, incluyendo deprovision/cleanup, queda pendiente de
ejecutar en esta VM; la bitácora no lo marca como PASS anticipadamente.

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
- deprovision/cleanup: `op_f9141421f98b2728`, `succeeded`; verificación de
  unidades fallidas, contenedores y volumen remanente pendiente de cerrar en
  la siguiente inspección de la VM.

Resultado del ciclo base CentOS Stream 10: `PASS` en apply, provision/setup,
HTTP, backups/checksums, pause/resume, image update y deprovision. Los gates de
restore con datos marcadores y multinode siguen abiertos.
