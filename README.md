# Admiral

Admiral is a simple, billing-aware Platform as a Service (PaaS) designed for software agencies and SaaS builders who want to provision, monetize, and operate customer applications quickly without the operational complexity of Kubernetes.

Admiral focuses on simplicity, predictable operations, low cost, and a secure-by-default deployment model.

**Status:** Early development — not production ready.

Current integration status in this repository:

* `admirald`, `admiral-fleet`, and `admiralctl` are the active backend E2E focus.
* `admiral-flagship` is functional, with working dashboard and instance management views.
* `admiral-flagship` is part of the normal single-node installation flow.
* `admiral-harbor` remains pre-alpha and is planned for a later phase.

---

# What Admiral Is

Admiral is a lightweight PaaS for running SaaS applications using containers.

It helps software agencies and independent software vendors:

* Provision customer applications
* Operate SaaS products
* Monetize software offerings
* Manage customer lifecycle
* Pause and resume customer environments
* Execute backups
* Scale application resources
* Offer subscription-based services

Admiral is intentionally designed around simple, well-understood infrastructure:

* Linux servers
* Containers
* Podman
* systemd
* PostgreSQL
* PostgreSQL-backed durable queue (`admiral_queue`)

No Kubernetes required.

The goal is simple:

> Install platform, provision customers, ship software.

---

# What Admiral Is NOT

Admiral is **not**:

* A Kubernetes replacement for hyperscale workloads
* A cloud provider
* A general-purpose container orchestration system
* A platform for arbitrary enterprise infrastructure
* A complex DevOps framework

Admiral exists to solve a specific problem:

> Small and medium software agencies need a practical way to deploy and operate SaaS products without building a DevOps department.

If you need:

* service meshes
* hundreds of microservices
* multi-region orchestration
* advanced scheduling
* cluster-level elasticity
* hyperscale infrastructure

You probably want Kubernetes.

If what you need is:

> Provision customer → charge customer → operate software

Admiral may be a good fit.

---

# Why Admiral Exists

Modern infrastructure is often unnecessarily complex for small SaaS businesses.

Many software agencies simply need:

* Customer provisioning
* Billing and subscriptions
* Backups
* Resource management
* Secure operations
* Predictable infrastructure
* Customer self-service

But frequently end up managing:

* Kubernetes
* Helm
* ingress controllers
* complex networking
* secret management systems
* cluster administration
* overengineered CI/CD pipelines

For many small and medium SaaS businesses, this complexity is operationally expensive and unnecessary.

Admiral embraces boring, predictable infrastructure.

Principles:

* Simple
* Secure by default
* Low operational cost
* Easy to install
* Easy to understand
* Minimal moving parts
* Linux-native
* Pragmatic scaling
* Billing-aware operations

Sometimes boring technology is the best technology.

---

# Billing First Principle

Admiral is designed around a **billing-first architecture**.

Billing is not an afterthought.

Billing is a first-class concern of the platform.

Every provisioned application is assumed to exist within a commercial relationship.

This architectural principle influences the entire system.

Examples:

* Applications belong to subscriptions
* Tiers define allowed resources
* Resource changes may affect billing
* Suspension and resume are billing-aware operations
* Backup retention may depend on plan limits
* Provisioning assumes a commercial plan
* Customer lifecycle is tied to subscription lifecycle
* Operational actions can be constrained by plan capabilities

Admiral intentionally avoids a common mistake:

> Build infrastructure first, figure out monetization later.

Instead:

> Infrastructure and monetization are designed together.

The result is a platform optimized for agencies that want to launch SaaS products quickly while maintaining predictable operational and commercial behavior.

A simple rule summarizes this philosophy:

> Every application exists within a commercial context.

---

# Architecture

Admiral consists of five components.

## admirald

The core control plane.

Responsibilities:

* Provision applications
* Deprovision applications
* Pause and resume workloads
* Execute backups
* Change application resources
* Expose the provisioning API
* Coordinate fleet operations
* Propagate application state

## admiral-fleet

The worker runtime.

Responsibilities:

* Execute provisioning instructions
* Manage application containers
* Perform health checks
* Enforce resource policies
* Monitor node state
* Execute node-level actions
* Report execution status to admirald

## admiral-harbor

Customer portal.

Responsibilities:

* User accounts
* Application catalog
* Subscription lifecycle
* Billing experience
* Plan selection
* Backup access
* Pause and resume applications
* Resource upgrades and downgrades

## admiral-flagship

Administrative interface.

Responsibilities:

* Node management
* Fleet visibility
* Application definitions
* Tier management
* Operational administration
* Platform configuration

## admiralctl

Administrative command line interface.

Responsibilities:

* Platform administration
* Diagnostics
* Provisioning workflows
* Debugging
* Maintenance operations

---

# Deployment Modes

Admiral supports multiple deployment models.

## Single Node

Everything runs on one server.

Recommended for:

* Small agencies
* Early-stage SaaS businesses
* MVP products
* Internal systems
* Low operational complexity

Typical deployment:

* admirald
* admiral-harbor
* admiral-flagship
* admiral-fleet
* PostgreSQL
* Redis

Running on a single server.

Target experience:

> One VPS. One command. One platform.

## Distributed Workers

Control plane and workers are separated.

Recommended for:

* Growing SaaS businesses
* Higher workload density
* Better workload isolation
* Incremental scaling

Example concept:

* Control plane in one server
* Multiple worker nodes executing workloads

## Fully Distributed

Administrative, commercial, and execution layers are separated.

Recommended for:

* Mature platforms
* Larger customer fleets
* Operational isolation requirements

---

# Security Model

Admiral is secure by default.

Official installation methods enable an additional SSH tunnel protection layer for the API.

Default philosophy:

* Secure defaults
* Least privilege
* Linux-native isolation
* Container isolation
* SSH-protected API access by default

Admiral can also operate without SSH tunneling if desired.

The goal is practical security without unnecessary complexity.

---

# Installation

## Single Node Installation

Requirements:
* Fedora or Enterprise Linux >= 9 (RHEL, Rocky Linux, AlmaLinux, CentOS Stream)
* Fresh server with root or sudo access
* Python 3
* For production: a public domain with DNS management access

### Quick Start

Run the installer as root:

```bash
curl -fsSL https://raw.githubusercontent.com/admiral-project/admiral/main/scripts/install.sh | sudo bash -s -- --single-node
```

Or clone the repository and run:

```bash
git clone https://github.com/admiral-project/admiral.git
cd admiral
sudo bash scripts/install.sh --single-node
```

The installer will:
1. Enable EPEL and COPR repositories
2. Install all Admiral RPM packages via DNF
3. Run the Ansible configuration playbook
4. Generate secure credentials and self-signed TLS certificates
5. Start all services: `postgresql`, `caddy`, `admirald`, `admiral-fleet`, `admiral-flagship`, `admiral-harbor`, `cockpit.socket`

On success, all services will be active and the API health endpoint will respond:

```bash
curl -sk https://127.0.0.1:8080/api/v1/health
# {"status":"healthy"}
```

### Secrets Safeguard

During installation, all platform secrets are generated and stored at `/etc/admiral/secrets`:

| Secret | Purpose |
|---|---|
| `ADMIRAL_POSTGRES_PASSWORD` | PostgreSQL authentication |
| `ADMIRAL_SHARED_TOKEN` | Internal component authentication |
| `ADMIRAL_SECRETS_KEY` | Encryption key for stored secrets |
| `FLAGSHIP_BOOTSTRAP_USER` | Admin console initial user |
| `FLAGSHIP_BOOTSTRAP_PASSWORD` | Admin console initial password |
| `HARBOR_BOOTSTRAP_USER` | Customer portal initial user |
| `HARBOR_BOOTSTRAP_PASSWORD` | Customer portal initial password |

**This file is critical.** If it is lost, the platform cannot be recovered. Back it up to a secure location off the node immediately:

```bash
scp /etc/admiral/secrets user@backup-server:/backup/admiral/
```

### DNS and HTTPS (Production)

HTTPS is intentionally not configured by the installer. A valid wildcard certificate for `*.apps.<YOUR_DOMAIN>` is required.

Run the HTTPS setup script:

```bash
sudo admiral_https_setup --domain cloud.example.com
```

This script uses certbot with a DNS-01 ACME challenge to obtain a Let's Encrypt wildcard certificate. **DNS-01 requires manual intervention** — you must add a TXT record to your DNS zone when prompted.

Supported DNS providers (install the corresponding certbot plugin):

```bash
# Cloudflare
dnf install -y certbot-dns-cloudflare

# Route53 (Amazon AWS)
dnf install -y certbot-dns-route53

# Google Cloud DNS
dnf install -y certbot-dns-google

# Other providers: certbot-dns-<provider>
```

After obtaining the certificate, the platform automatically configures Caddy as TLS terminator and restarts the affected services.

### QA / Development Mode (No DNS)

For testing without a public domain, configure the platform in QA mode:

```bash
# Generate a self-signed wildcard certificate
cd /etc/admiral/tls
openssl genrsa -out caddy-local-key.pem 2048
openssl req -new -key caddy-local-key.pem \
  -out caddy-local.csr \
  -subj "/C=US/ST=Test/O=Admiral/CN=*.apps.qa.admiral.test"
openssl x509 -req -in caddy-local.csr \
  -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out caddy-local.pem -days 365 \
  -extfile <(printf "subjectAltName=DNS:*.apps.qa.admiral.test,DNS:apps.qa.admiral.test")

# Update admirald configuration
cat >> /etc/admirald.ini << 'EOF'
networking_base_domain=qa.admiral.test
networking_tls_provider=internal
networking_tls_cert_file=/etc/admiral/tls/caddy-local.pem
networking_tls_key_file=/etc/admiral/tls/caddy-local-key.pem
EOF

# Allow self-signed certs in the customer portal
sed -i 's/ADMIRAL_INSECURE_SKIP_VERIFY=0/ADMIRAL_INSECURE_SKIP_VERIFY=1/' /etc/admiral/harbor.env

# Restart services
systemctl restart admirald admiral-fleet admiral-flagship admiral-harbor
```

In QA mode the web consoles are accessible directly:

| Service | URL |
|---|---|
| Admin Console (flagship) | `https://<SERVER_IP>:5000` |
| Customer Portal (harbor) | `https://<SERVER_IP>:5001` |

---

# Repository Structure

This repository acts as the umbrella project for Admiral.

It contains all platform components as Git submodules and allows Admiral to be developed as a coherent product.

Structure:

admiral/
├── admirald/
├── admiral-fleet/
├── admiral-harbor/
├── admiral-flagship/
└── admiralctl/

---

# Design Philosophy

Admiral optimizes for:

* Operational simplicity
* Predictable behavior
* Low infrastructure cost
* Secure defaults
* Fast onboarding
* Minimal operational burden
* Billing-aware operations
* Linux-native tooling
* Practical scalability

Tradeoffs are intentional.

Admiral favors simplicity over abstraction.

It prefers understandable systems over operational complexity.

It scales pragmatically instead of architecting for problems most small SaaS businesses will never encounter.

---

# Project Status

Admiral is currently under active development.

It is not yet production ready.

Interfaces, APIs, workflows, and deployment mechanisms may change until a stable release is announced.

Early contributors and testers should expect rapid iteration.

---

# License

Licensed under the Apache 2.0 License.
