Admiral — Fase 6: Distributed Workload under WG Simple VPN

Objetivo

Implementar soporte multinodo simple para Admiral usando una red privada WireGuard entre el nodo de control y los nodos worker.

La meta de esta fase es permitir que "admirald" pueda registrar, administrar y enrutar workloads hacia múltiples nodos "admiral-fleet", manteniendo la arquitectura simple:

- Caddy central en el nodo de control.
- Workers remotos ejecutando Podman rootless.
- Comunicación privada vía WireGuard.
- Setup automatizado vía SSH y Ansible.
- Registro automático del nodo worker en "admirald".

Alcance

La Fase 6 cubre:

- Instalación remota de nodos worker vía SSH.
- Acceso preferente por llave pública/privada.
- Despliegue automatizado con Ansible.
- Configuración de WireGuard en topología star.
- Preparación completa del host worker para Podman rootless.
- Instalación y configuración de "admiral-fleet".
- Registro automático del worker en "admirald".
- Validación de conectividad control-plane → worker vía WG.
- Provisionamiento de workloads en nodos remotos.
- Routing desde Caddy central hacia servicios remotos vía IP WireGuard.

Arquitectura objetivo

Internet
   |
   v
+-------------------------------+
| Control Plane                 |
| admirald                      |
| Caddy                         |
| flagship                      |
| harbor                        |
| wg0: 10.99.0.1                |
+-------------------------------+
          |
          | WireGuard
          |
+-------------------------------+
| Worker Node 1                 |
| admiral-fleet                 |
| Podman rootless               |
| wg0: 10.99.0.2                |
+-------------------------------+

+-------------------------------+
| Worker Node 2                 |
| admiral-fleet                 |
| Podman rootless               |
| wg0: 10.99.0.3                |
+-------------------------------+

Reglas de diseño

1. WireGuard será la red oficial para multinodo

La instalación oficial multinodo debe usar WireGuard por defecto.

El modo directo sin VPN puede existir más adelante como modo avanzado, pero no será el flujo recomendado.

2. Topología star

No se implementará mesh completo.

Solo se requiere comunicación:

- control-plane → worker
- worker → control-plane

No se requiere comunicación worker → worker.

3. Caddy permanece centralizado

Los workers no ejecutan Caddy público.

Caddy en el nodo de control enruta hacia:

<worker_wireguard_ip>:<published_service_port>

Ejemplo:

app001.cloud.example.com → 10.99.0.2:49123

4. Ansible es el mecanismo oficial de bootstrap

El setup multinodo debe ejecutarse desde el nodo de control o desde una estación administrativa usando Ansible.

Ansible debe:

- conectarse por SSH
- instalar dependencias
- configurar rootless Podman
- configurar WireGuard
- instalar "admiral-fleet"
- habilitar servicios systemd
- registrar el nodo en "admirald"
- ejecutar pruebas de conectividad

5. SSH por llave como método preferido

El flujo recomendado debe usar autenticación SSH por llave pública/privada.

No se debe depender de contraseñas SSH como mecanismo normal.

Componentes a implementar

1. Inventario Ansible

Debe existir un inventario para nodos worker.

Ejemplo:

[admiral_workers]
node1 ansible_host=192.0.2.10 admiral_node_name=node1 admiral_wg_ip=10.99.0.2
node2 ansible_host=192.0.2.11 admiral_node_name=node2 admiral_wg_ip=10.99.0.3

2. Playbook de preparación del host

Debe validar e instalar:

- "podman"
- "wireguard-tools"
- "systemd"
- "sudo"
- dependencias necesarias para Quadlets
- usuario rootless
- subuid/subgid
- lingering systemd
- firewall mínimo requerido
- directorios de configuración de Admiral

3. Playbook de WireGuard

Debe:

- generar o instalar claves WireGuard
- configurar "wg0"
- asignar IP privada al nodo
- registrar peer en el control plane
- habilitar "wg-quick@wg0"
- validar conectividad con "ping" o handshake WireGuard

4. Playbook de "admiral-fleet"

Debe:

- instalar binario o paquete RPM de "admiral-fleet"
- crear configuración del worker
- configurar endpoint privado de "admirald"
- configurar token/credenciales
- habilitar e iniciar "admiral-fleet.service"
- validar heartbeat

5. Registro automático en "admirald"

Al finalizar el playbook, el nodo debe quedar registrado en "admirald" con:

- node name
- public IP administrativa
- WireGuard IP
- estado inicial
- versión de fleet
- capacidades básicas
- rootless user
- storage path
- supported runtime

6. Validación automática post-install

Ansible debe ejecutar checks mínimos:

- SSH OK
- WireGuard handshake OK
- control-plane puede alcanzar worker por WG
- worker puede alcanzar "admirald"
- "admiral-fleet" activo
- heartbeat recibido
- Podman rootless funcional
- Caddy puede alcanzar un puerto publicado en worker

Criterios de aceptación

La Fase 6 se considera completada cuando:

1. Se puede agregar un worker remoto desde Ansible.
2. El worker queda conectado por WireGuard.
3. El worker queda registrado automáticamente en "admirald".
4. "admiralctl nodes list" muestra el nodo como healthy.
5. Se puede provisionar una app en el worker remoto.
6. Caddy central enruta tráfico público hacia la app remota vía WireGuard.
7. La app remota puede pausarse, reanudarse, respaldarse y desaprovisionarse.
8. La caída de un worker no afecta apps en otros workers.
9. La documentación describe claramente el setup multinodo.
10. El flujo funciona en Enterprise Linux 10 compatible: Rocky, Alma o CentOS Stream 10.

Fuera de alcance para esta fase

No incluir en Fase 6:

- alta disponibilidad de Caddy
- balanceo automático entre múltiples nodos
- migración live de workloads
- autoscaling
- service mesh
- networking worker-to-worker
- soporte universal para cualquier topología VPN
- multi-region
- Kubernetes
- Consul/etcd
- scheduling avanzado tipo bin-packing

Resultado esperado

Al finalizar esta fase, Admiral tendrá un modelo multinodo simple y validable:

«Control plane central + Caddy central + workers remotos conectados por WireGuard + setup automatizado por Ansible.»

Esta fase habilita el primer claim distribuido real de Admiral sin abandonar la filosofía del proyecto: simple, seguro, barato, rootless y operable.

---

## Anexo: WireGuard Key Rotation y Deprovisioning

### Rotación de claves WireGuard

1. Generar nuevo par de claves en el nodo de control:
   ```bash
   wg genkey | tee /etc/wireguard/control_private.key | wg pubkey > /etc/wireguard/control_public.key
   ```

2. Actualizar `[Peer]` en cada worker reemplazando `PublicKey` por la nueva clave pública del control.

3. Aplicar configuración sin interrupción de sesiones activas (WireGuard maneja rotación sin reinicio):
   ```bash
   wg set wg0 peer <WORKER_PUBKEY> endpoint <WORKER_ENDPOINT>
   ```

4. Verificar handshake en control:
   ```bash
   wg show wg0
   ```

### Rotación de clave de un worker específico

1. Generar nuevo par en el worker:
   ```bash
   wg genkey | tee /etc/wireguard/worker_private.key | wg pubkey > /etc/wireguard/worker_public.key
   ```

2. Actualizar `[Peer]` en el control con la nueva `PublicKey` del worker.

3. Verificar handshake:
   ```bash
   wg show wg0
   ```

### Deprovisioning de un nodo worker (WireGuard)

Al remover un worker del cluster:

1. Eliminar su bloque `[Peer]` de la configuración WireGuard del control:
   ```bash
   wg set wg0 peer <WORKER_PUBKEY> remove
   ```

2. (Opcional) Detener WireGuard en el worker si será reutilizado:
   ```bash
   systemctl disable --now wg-quick@wg0
   ```

3. Verificar que el peer fue removido:
   ```bash
   wg show wg0
   ```

4. Actualizar inventario Ansible para excluir el nodo en futuros playbooks.
