# Laboratorio cloud local con KVM

Este documento describe cómo validar instalaciones nuevas de Admiral en VMs
KVM x86_64 sin borrar el host de desarrollo ni confundir una reconciliación
con una primera instalación.

La prueba usa KVM porque una máquina virtual conserva los elementos que un
contenedor de sistema no reproduce de forma suficientemente fiel:

- kernel y arranque normal de systemd;
- SELinux `Enforcing`;
- firewalld y nftables;
- servicios de sistema y de usuario;
- linger y `user@<uid>.service`;
- Podman rootless y Quadlet;
- disco, cuentas, `/etc/subuid` y `/etc/subgid` inicialmente independientes.

## Recursos

Para la matriz Rocky Linux 10, AlmaLinux 10, CentOS Stream 10 y Fedora Rawhide:

| Recurso | Host de prueba | VM |
|---|---:|---:|
| vCPU | 2 o más | 2 |
| RAM | 8 GiB | 2 GiB por VM |
| Swap del host | 4 GiB | no requerido |
| Disco libre | 50 GiB o más | overlay de 24 GiB por VM |

El swap evita que una descarga, actualización de seguridad o construcción de
imágenes mate el host por OOM. No convierte un host pequeño en una plataforma
adecuada para pruebas de rendimiento. Durante la validación debe vigilarse
`MemAvailable`, el uso de swap y el RSS de QEMU.

La matriz actual tiene ocho celdas: los cuatro sistemas en Single-Node y
Multi-Node. Cada Multi-Node usa tres VMs independientes del mismo sistema:
`--admin-node` (Admirald, Flagship, PostgreSQL y Caddy), `--worker-node` (Fleet
y Podman) y `--portal-node` (Harbor). Harbor no se instala en el admin ni en el
worker para obtener crédito en esta matriz. Con tres VMs de 2 GiB y 4 GiB de
swap se ejecuta un clúster a la vez; vigila `MemAvailable`, swap y RSS de QEMU.
Single-Node usa una VM de 2 GiB.

## Imagen y aislamiento

La validación de Rocky usa una imagen GenericCloud oficial. Fedora Rawhide debe
usar su imagen cloud oficial vigente. Descarga y verifica el checksum publicado
por cada proyecto antes de crear overlays; conserva las imágenes base
inmutables y registra sus hashes en el reporte.

La referencia Rocky usada anteriormente fue:

```text
Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2
```

El disco de prueba es un overlay QCOW2; la imagen base permanece inmutable y el
overlay puede descartarse.

QEMU usa user-mode networking:

- la VM obtiene salida NAT para repositorios;
- SSH se publica sólo como un puerto alto de `127.0.0.1` en el host;
- ningún puerto HTTP, Cockpit o de Admiral se publica accidentalmente;
- no se habilita IP forwarding en el host.

La clave SSH creada para esta prueba es temporal. Cloud-init instala únicamente
su mitad pública. Para instalaciones locales se pasa:

```bash
sudo admiral-install --single-node \
  --public-ip 10.0.2.15 \
  --ssh-public-key /home/rocky/.ssh/authorized_keys
```

No se debe copiar la clave privada del operador dentro de la VM para satisfacer
el bootstrap local. `--ssh-key` continúa reservado para la conexión desde el
admin hacia spokes remotos.

## Secuencia de validación

1. Verificar checksum de la imagen oficial.
2. Crear un overlay vacío y una semilla NoCloud con un usuario sudo y una clave
   pública temporal.
3. Arrancar la VM con KVM, 2 vCPU, 2 GiB de RAM y SSH reenviado a loopback.
4. Esperar a que `cloud-init status --wait` termine.
5. Confirmar Rocky Linux 10, SELinux `Enforcing`, disco expandido y ausencia de
   paquetes o estado Admiral.
6. Habilitar EPEL, instalar el RPM `admiral-common` construido desde el commit
   bajo prueba y ejecutar el instalador empaquetado.
7. Exigir que Ansible termine con `failed=0` y que el checklist de seguridad del
   instalador no produzca advertencias.
8. Verificar servicios, listeners, firewall, nftables, auditd, Fail2ban,
   sincronización de reloj y permisos de secretos.
9. Verificar `subuid`/`subgid`, linger, bus D-Bus, `systemd-machined`,
   `user@<uid>.service` y graph root de Podman.
10. Ejecutar el golden test real de WordPress/MariaDB:
    provision, setup, HTTP, propietario/cgroup de procesos, backup con checksum,
    pause/resume, nueva respuesta HTTP y deprovision.
11. Revisar AVC de SELinux y unidades fallidas.
12. Apagar la VM y conservar únicamente logs y evidencia necesaria.

Instalar primero el RPM local sin EPEL no reproduce el orden soportado:
`admiral-common` depende de `ansible-collection-ansible-posix`, que EL10 obtiene
de EPEL. El orden real del instalador es EPEL, dependencias/RPM y Ansible.

## Resultado de referencia

El 27 de julio de 2026 se completó la secuencia anterior sobre una VM Rocky
Linux 10.2 recién creada, con SELinux `Enforcing`, usando
`admiral-common-0.0.1beta17-12.el10`.

La primera ejecución limpia encontró un defecto real de orden: el rol SELinux
intentaba activar `container_manage_cgroup` antes de que la instalación de
Fleet incorporara `container-selinux`. El checklist bloqueó la instalación. El
RPM `beta17-12` trasladó esa configuración al rol Fleet, eliminó los errores
SELinux ignorados y limitó la comprobación a hosts que ejecutan workloads.

Para demostrar la corrección se dejó deliberadamente el booleano en `off` antes
de reconciliar. La tarea Fleet lo cambió a `on`; Ansible terminó con
`failed=0` y el checklist imprimió `Admiral installation completed`.

La evidencia posterior confirmó:

- todas las unidades Admiral y de seguridad activas, sin unidades fallidas;
- `httpd_can_network_connect` y `container_manage_cgroup` en `on`;
- secretos `0600 root:root`;
- sólo SSH, HTTP y HTTPS permitidos en la zona pública;
- servicios internos ligados a loopback;
- `admiral-apps:655360:131072` sin UID numérico asumido;
- Podman `rootless=true`, cgroup manager `systemd` y graph root correcto;
- clave pública del operador autorizada sin claves privadas en el usuario
  administrativo generado.

El golden test aprovisionó `wp` con tier `small` y confirmó HTTP `200`, setup
completo y estado `healthy/running`. El backup MariaDB produjo un archivo
`0600 root:root` cuyo SHA-256 recalculado coincidió con el registrado. Pause
cerró el endpoint, resume devolvió HTTP `200` y deprovision eliminó contenedores,
unidades y Quadlets. No se encontraron AVC de contenedores durante la prueba.

## Extensión a multi-node

El mismo enfoque valida la topología multi-node requerida:

```text
admin VM  --admin-node
worker VM --worker-node
portal VM --portal-node (Harbor independiente)
```

Cada VM necesita una interfaz con NAT para instalar paquetes y una segunda LAN
privada compartida para la topología del laboratorio. Los puertos SSH del host
se asignan individualmente y sólo a loopback.

La comunicación en runtime no usa SSH: después del bootstrap, `admirald` y
`admiral-fleet` se comunican mediante la API autenticada sobre WireGuard. SSH
es únicamente el transporte que usa `install.sh` mientras configura un spoke
remoto.

Para un workload publicado sobre la IP WireGuard del worker, por ejemplo
`10.99.0.2`, el healthcheck debe validar esa dirección. No se debe asumir que
`127.0.0.1` en el admin representa el workload del worker. Fleet resuelve la
dirección publicada del renderer para healthchecks TCP/HTTP; los command
healthchecks se ejecutan dentro del contenedor y pueden usar loopback.

La prueba multi-node debe comprobar además:

- fingerprint SSH de cada spoke antes del primer acceso;
- generación e intercambio de peers WireGuard;
- rutas `/32` hub-and-spoke y ausencia de comunicación lateral;
- API y PostgreSQL no expuestos públicamente;
- certificados y autenticación entre componentes;
- registro separado de portal y worker;
- Harbor ejecutándose únicamente en la VM portal y comunicándose con
  `admirald` por la VPN;
- ruta pública en Caddy hacia la dirección WireGuard de la VM portal;
- registro/login de cliente, catálogo y una acción del cliente que llegue al
  control plane y cree el workload en la VM worker;
- workload WordPress real en un worker rootless;
- backup, lifecycle, callbacks y auditoría a través de la VPN.

`--admin-portal-node` es un perfil combinado y no satisface esta celda. La
instalación, el enrutamiento y los flujos de Harbor deben ejecutarse en la VM
portal independiente para que el resultado cuente.

KVM proporciona una prueba funcional y de seguridad muy cercana a VPS reales,
pero no sustituye una prueba de capacidad, latencia, proveedor de red o pago
PayPal real.
