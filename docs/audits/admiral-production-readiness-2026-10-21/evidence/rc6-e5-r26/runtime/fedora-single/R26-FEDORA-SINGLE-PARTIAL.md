# R26 Fedora Single — instalación correcta, ejecución parcial

Fecha: 2026-10-28 UTC  
Candidato: Epoch 5, Release 26 (`0.0.1rc6-26.fc46`)  
VM reutilizada: `rc6e5r18-ipv6-worker`, Fedora 46 x86_64, SELinux Enforcing. No se creó una VM.

## Resultado

**PARTIAL / NOT PASS.** La instalación exacta terminó correctamente: Ansible recap `ok=268 changed=110 failed=0 unreachable=0`; los seis RPM Fedora nativos del candidato quedaron instalados y los servicios PostgreSQL, Admirald, Fleet, Caddy, Harbor y Flagship quedaron activos. El chequeo confirmó `userns = "auto"`, rootless Podman para `admiral-apps`, y ningún unit de Admiral fallido.

La primera etapa funcional alcanzó provisionamiento satisfactorio (`op_9410f9453fe6783c`), replay idempotente sobre la misma operación e instancia, marcador PostgreSQL leído, e HTTP 200. Se interrumpió la lane antes de sus etapas de resize, backup/restore, ciclo de control-plane, reboot y verificación final porque RAM disponible en el host bajó del umbral operativo elegido de 3 GiB: muestra 64 = 2,955 MiB; el invitado tenía 1,124 MiB disponibles y el disco del host 34.19 GiB disponibles. No hubo OOM ni agotamiento de disco. El monitor escribe una etiqueta estática “below 2 GiB”; durante esta corrida el umbral configurado fue 3 GiB.

El cleanup dejó la instancia `inst_0dfd0c5545cfaf16` como `deprovisioned`, con cero contenedores, pods, volúmenes y units de instancia. La operación `op_4b596f129aa34159` terminó `succeeded`; una segunda solicitud duplicada de cleanup, `op_2ddece13fc4b64c0`, seguía `queued` al apagar la VM. La VM se apagó de forma ordenada para liberar RAM. Esto requiere seguimiento y no se cuenta como cierre completo del ciclo.

## Impacto en el release

No hubo cambios de producto ni invalidación de R26. Esta ejecución **no** acredita la celda Fedora Single. En el momento de ese intento, la matriz seguía en **0/6 celdas PASS**; esta evidencia parcial no se cuenta para la celda. Posteriormente las seis celdas R26 pasaron sobre el candidato exacto; véanse los informes finales de cada celda. #307 sigue abierto por los controles de seguridad no acreditados y R26 no se declara Gold.

## Evidencia protegida

Los logs completos permanecen con permisos restringidos en `/var/lib/libvirt/images/admiral-validation/evidence/rc6-e5-r26/runtime/fedora-single/`. Sus hashes SHA-256 están en `protected-log-sha256.txt`.

