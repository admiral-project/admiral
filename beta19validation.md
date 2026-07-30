# Bitácora de validación beta19

Fecha de inicio: 2026-07-30  
Responsable: William Moreno Reyes <williamjmorenor@gmail.com>

Esta bitácora es viva: se actualiza al terminar cada hito de validación, al
encontrar un bloqueo y al corregir un defecto que pueda afectar el lanzamiento.

## Alcance

- RPMs locales beta19 de Admiral; no se compilan paquetes Python.
- Repositorios COPR habilitados: `admiral-project/admiral` y `@caddy/caddy`.
- Validación `--single-node` en CentOS Stream 10, Rocky Linux 10 y AlmaLinux 10.
- Validación multinodo en nube local simulada con un nodo
  `--admin-portal-node` y un nodo `--worker-node`.
- Revisión del alta SSH y del handshake entre `admiral-fleet` y `admirald`.
- Despliegue de WordPress rootless con Podman.
- Revisión y cierre fundamentado de los issues abiertos. PayPal real queda fuera
  del alcance de beta19.

## Artefactos bajo prueba

Los RPMs se usan desde `packaging/build/RPMS/`:

- `admiral-common-0.0.1beta19-34.el10.noarch.rpm`
- `admirald-0.0.1beta19-4.el10.x86_64.rpm`
- `admiral-fleet-0.0.1beta19-2.el10.x86_64.rpm`
- `admiralctl-0.0.1beta19-1.el10.x86_64.rpm`
- `admiral-flagship-0.0.1beta19-1.el10.noarch.rpm`
- `admiral-harbor-0.0.1beta19-2.el10.noarch.rpm`

## Resultados

| Área | Entorno | Estado | Evidencia |
|---|---|---|---|
| Pruebas de instalador | Host de validación | Aprobado | `python3 -m unittest discover -s scripts -p 'test_*.py'`: 45 pruebas correctas. |
| Pruebas Go | Host de validación | Aprobado | `go test ./admirald/... ./admiral-fleet/... ./admiralctl/...` correcto. |
| Single node | Rocky Linux 10 | Aprobado | `admiral-install --single-node` terminó con `ok=214`, `changed=104`, `failed=0`; servicios activos. |
| WordPress | Rocky Linux 10 | Aprobado | Operación `op_45a77d013a8fdd86` correcta; instancia `inst_e8c7b3742bb647a5` sana y en ejecución. El HTTP local respondió 301 y los contenedores se ejecutaron como `admiral-apps` con Podman rootless. |
| Single node | AlmaLinux 10 | En curso | Dependencias del sistema y COPR ya preparados; falta instalar RPMs locales y ejecutar el instalador. |
| Single node | CentOS Stream 10 | Pendiente | Falta iniciar y validar la VM. |
| Multinodo | Nube local simulada | Pendiente | Falta crear red aislada, instalar nodo administrativo y enrolar el worker. |
| SSH y handshake | Multinodo | Pendiente | La revisión estática confirma identidad SSH por nodo y autenticación Fleet--Admirald por token; falta evidencia de ejecución y revocación de la llave bootstrap. |
| Issues de GitHub | `admiral-project/admiral` | En curso | #3 cerrado fuera de alcance (PayPal real); #12 cerrado tras corregir los nombres de comandos RPM. |

## Hallazgos corregidos antes de continuar

1. La precondición del instalador shell trataba una instalación RPM nueva como
   una configuración heredada. Corregido en
   `fix(installer): allow fresh RPM baseline configuration`.
2. La misma condición existía en el playbook Ansible. Corregido en
   `fix(installer): accept clean RPM baseline in playbook`.
3. Los comandos instalados tenían guion bajo cuando la interfaz documentada usa
   guiones. Corregido en `fix(cli): standardize installed command names`.

## Hallazgos en curso

4. En EL10, una instalación nueva necesita el repositorio CRB además de EPEL
   para resolver dependencias de instalación. Rocky y Alma se prepararon con
   CRB explícitamente para continuar la matriz. El bootstrap shell y el rol
   Ansible ahora habilitan CRB de forma explícita antes de instalar paquetes de
   Admiral; la prueba de regresión pasó (46 pruebas). Falta reconstruir el RPM
   `admiral-common` y repetir la validación en una instalación EL10 limpia.

Actualización: el RPM local `admiral-common-0.0.1beta19-34.el10.noarch.rpm`
fue reconstruido correctamente con la corrección de CRB y sus referencias de
fuente fueron validadas. Se utilizará para las instalaciones restantes.

5. En Alma, la primera convergencia dejó una máscara ACL vacía en el socket
   administrativo de Caddy, con lo cual Admirald no podía reconciliar rutas.
   El token de Fleet sí quedó correcto tras el registro del nodo; los `401`
   iniciales fueron previos a ese registro. Se añade una tarea explícita para
   aplicar la ACL al socket ya existente y se repetirá la convergencia antes
   de aprobar la plataforma.

Actualización: la tarea explícita reparó la ACL correctamente. Durante esa
prueba, `PathChanged` se disparó por la misma modificación del ACL y produjo
un bucle de arranques del servicio auxiliar. El watcher queda limitado a
`PathExists`, que cubre la recreación del socket por Caddy sin reactivarse por
su propia reparación. Falta repetir la convergencia con este ajuste final.

## Criterio de salida

beta19 queda validado únicamente cuando las tres instalaciones single-node y el
flujo multinodo terminen sin fallos, se compruebe el handshake Fleet--Admirald,
WordPress rootless permanezca sano y cada issue abierto tenga una resolución con
evidencia o una justificación explícita de fuera de alcance.
