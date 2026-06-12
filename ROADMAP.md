Fase 1 - Production Readiness (obligatoria)

Objetivo: Que una agencia pueda instalar Admiral y operar clientes reales sin miedo.

1. Harbor E2E completo

Validar:

registro

login

compra

aprovisionamiento

upgrade

downgrade

pausa

resume

backup

restore

cancelación


Resultado:

Suite E2E automatizada.



---

2. Instalador oficial

Debe existir:

curl ... | bash

o

dnf install admiral-platform

y quedar funcional.

Validar:

Fedora

AlmaLinux

Rocky

RHEL



---

3. Seguridad por defecto

Implementar:

WireGuard obligatorio entre nodos

Firewall automático

Certificados automáticos

Rotación de credenciales iniciales

Secrets fuera de archivos planos


Resultado:

Escaneo externo no debe descubrir:

PostgreSQL

Redis

RabbitMQ

Fleet



---

4. Multinodo

Topología:

Principal
 ├─ admirald
 ├─ admiralctl
 └─ flagship

Comercial
 └─ harbor

Workers
 └─ fleet

Validar:

1 principal

1 comercial

N workers



---

5. Backups reales

No simulados.

Probar:

crear backup

descargar backup

restaurar backup


Resultado:

Restore exitoso en entorno limpio.


---

Fase 2 - Operabilidad

Objetivo: Poder administrar decenas de clientes.

6. Observabilidad mínima

Agregar:

métricas

health checks

eventos


No necesitas Prometheus inicialmente.

Basta:

Node status
Worker status
Pod status
Last backup
Disk usage
CPU usage
RAM usage

visible desde Flagship.


---

7. Auditoría

Registrar:

quién

cuándo

qué


Para:

deploys

upgrades

backups

restores

cambios de tier

pausas



---

8. Recuperación ante fallos

Validar:

cae Harbor

clientes siguen funcionando

cae Admirald

clientes siguen funcionando

cae Worker

pods afectados únicamente

vuelve Worker

reconcilia estado


---

9. Idempotencia

Toda operación debe poder ejecutarse dos veces sin romper nada.

Especialmente:

deploy

backup

restore

pause

resume

upgrade



---

Fase 3 - Escalamiento comercial

Objetivo: Que una agencia pueda vender SaaS encima de Admiral.

10. Marketplace de aplicaciones

Ya está implícito en Harbor.

Formalizar:

name:
version:
tiers:
volumes:
environment:

como contrato oficial.


---

11. Catálogo de templates

Ejemplos:

Cacao Accounting

NOW LMS

WordPress

ERPNext

Nextcloud


Esto convierte Admiral en plataforma.


---

12. Billing sólido

Validar:

pago inicial

renovación

cancelación

suspensión por impago

reactivación



---

Fase 4 - Release 1.0

Objetivo: Declarar Admiral estable.

Checklist:

Arquitectura

[ ] Single node validado

[ ] Multinodo validado

[ ] VPN validada


Operación

[ ] Backup validado

[ ] Restore validado

[ ] Upgrade validado


Seguridad

[ ] Firewall validado

[ ] Certificados validados

[ ] Secrets gestionados


Testing

[ ] Unitarios

[ ] Integración

[ ] E2E

[ ] Failure testing


Comercial

[ ] Harbor completo

[ ] Billing completo

[ ] Catálogo completo

