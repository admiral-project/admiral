# R26 Ansible security baseline assertions

Date: 2026-10-29 UTC  
Candidate root: `b6146a46be93f1a9c242361e27b10dbbb2164bf6`  
Candidate: Fedora Rawhide x86_64, R26

Reused the exact Fedora Admin, Worker, and Portal installation logs from the R26 Multi-Node cell. The three Ansible runs completed with `failed=0` and `unreachable=0`.

The captured playbook results show:

- **Role-scoped public exposure:** Admin assertions accepted the Admin public-service profile; Worker and Portal each asserted that only SSH services remained public. All three roles asserted the allowed public ports.
- **Dual-stack firewall:** all three role runs asserted the effective managed dual-stack egress reject rule. Worker also reasserted runtime IPv4 and IPv6 forwarding disabled after WireGuard startup, then passed the forwarding assertion.
- **Production profile defaults:** `admiral_dev_mode` is treated as false when unset. In all three production role logs, dev-mode certificates, public services/ports, development environment, relaxed service binding, and removal of the secure egress policy were skipped. Production-profile tasks removed the Cockpit web service and disabled its socket.
- **Auditd:** Admin, Worker, and Portal runs successfully executed `Verify Admiral audit rules are loaded`.
- **Fail2ban:** Admin and Worker ran the SSH jail readiness check, inserted the documentation-only address `192.0.2.1`, verified that nftables contained the ban, and removed it in the `always` cleanup.
- **Ansible secret redaction:** sensitive tasks in the WireGuard and Admirald roles declare `no_log: true`; the three captured installer logs contain 71 `(censored due to no_log)` records and no task output exposing those values.

This evidence supports the #307 controls **“Los valores seguros son los predeterminados en instalaciones de producción”**, **“Worker y Portal no exponen servicios administrativos a Internet”**, **“Las excepciones de `dev-mode` no contaminan los despliegues de producción”**, **“Los puertos abiertos corresponden al rol del nodo”**, **“Firewall IPv4 e IPv6 aplican la política esperada”**, **“No existe IP forwarding generalizado entre nodos”**, **“`no_log` protege las tareas Ansible sensibles”**, and **“Auditd y Fail2ban funcionan efectivamente”** for the tested Fedora R26 installation path. These are installer-level assertions, not a separate packet-capture or post-reboot host snapshot.

No product file changed; the candidate and six-cell matrix are unchanged.
