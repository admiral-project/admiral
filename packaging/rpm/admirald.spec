# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit bb2084f383cf8027fa3548ef83db29e515660a19

Name:    admirald
Version: 0.0.1beta20
Release: 12%{?dist}
Summary: Admiral Control Plane - Core API and orchestration service

License: Apache-2.0
URL:     https://github.com/admiral-project/admirald
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admirald.service
Source2: admirald.ini

BuildRequires: golang >= 1.26.5
BuildRequires: systemd
BuildRequires: git

Requires: admiral-common
Requires: caddy
Requires: certbot
Requires: podman >= 5
Requires: postgresql-server
Requires: shadow-utils
Requires: systemd

%description
admirald is the control plane of Admiral. It exposes the platform API,
maintains system state, validates operations, coordinates provisioning,
dispatches tasks to fleet workers, and maintains auditability.

%prep
%setup -q -n admiral-v%{version}

%build
cd admirald
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go build -trimpath -buildmode=pie -ldflags="-s -w -X main.Version=%{version}" -o admirald ./cmd/admirald/

%install
cd admirald
install -Dm0755 admirald %{buildroot}%{_bindir}/admirald
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admirald.service
install -Dm0600 %{SOURCE2} %{buildroot}%{_sysconfdir}/admirald.ini
install -d %{buildroot}/etc/systemd/system/admirald.service.d

%check
cd admirald
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
    go test ./...

%files
%license admirald/LICENSE
%{_bindir}/admirald
%{_unitdir}/admirald.service
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admirald.ini
%dir %attr(0750, root, admiral) /etc/systemd/system/admirald.service.d

%post
%systemd_post admirald.service
restorecon -F %{_bindir}/admirald 2>/dev/null || :

%preun
%systemd_preun admirald.service

%postun
%systemd_postun_with_restart admirald.service

%changelog
* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-5
- Align the control-plane package documentation with idempotent spoke reconvergence

* Thu Jul 30 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-4
- Centralize single-node routing detection and enable production S3 TLS policy

* Wed Jul 29 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-2
- Use a restricted Unix socket for the Caddy admin API

* Mon Jul 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-1
- Bump version to 0.0.1beta18

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-2
- Load control plane secrets from systemd credentials
- Keep the queue encryption key inside the control plane
- Install the control-plane configuration as root-only
- Verify checksums for internal restores
- Rebuild with latest submodule refs and release bump

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-1
- Bump to 0.0.1beta17 and rebuild with latest security hardening

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-7
- Add atomic secret re-encryption endpoint for idempotent rotation

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-6
- Add encrypted secret key versioning and rotation support
- Enforce WireGuard-only routing and redact app secret values

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-4
- Persist administrative authentication rate limits in PostgreSQL

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-3
- Invalidate other administrator sessions after a password change

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-2
- Bind worker requests to authenticated nodes and update PostgreSQL client security fixes

* Tue Jul 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-1
- Harden the control-plane systemd unit with strict filesystem and device policy

* Tue Jul 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta15-2
- Update source commit refs to include security audit fixes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-9
- Add private_key, encryption_key, signing_key to logger sensitiveKeys
- Block newlines in setup_command validation

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-8
- Update source commit ref to include gofmt fix

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-7
- Update submodule commit refs and bump release

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-6
- Update source commit ref for CI Go version fix

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-5
- Update source commit ref for mockPublisher test fix

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-4
- Update source commit ref for gofmt fix

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-3
- Update source commit ref for customer_id and test publisher fixes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-2
- Update source commit ref for TaskSignature/SignedAt fields in FleetTask

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-1
- chore(release): bump to 0.0.1beta14 and update source commit refs to latest HEAD

* Sat Jun 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta13-1
- Bump to 0.0.1beta13 and update source commit ref

* Fri Jun 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta12-1
- Bump to 0.0.1beta12 and update source commit ref
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta11-1
- Bump to 0.0.1beta11 and reset packaging release to 1
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-2
- Bump release to 2 for coordinated packaging update
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-1
- Preserve initializing/setup_failed lifecycle and cleanup failed setup_command runs
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-3
- Update source commit to support shared volumes and depends_on
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-1
- Bump to 0.0.1beta9, update source commit ref
- Multi-node beta: 4 OS distribution validation (Fedora 44, CentOS Stream 10,
  AlmaLinux 10.2, Rocky Linux 10.2)
- Add paranoid S3 verification and backup verifier goroutine
- Fix Caddy upstream to use WireGuard IP for multi-node routing
- Add localhost as portal health check candidate
- Fix admin auth middleware (X-Admiral-Token + static token fallback)
- Relax S3 endpoint validation for WireGuard private network
- Add migration 12: verified_at column in backup_records
- Move S3 client to shared package (admirald + admiral-fleet)
- Fix admin login with bootstrap credentials
* Mon Jun 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta8-2
- Bump to 0.0.1beta8, update source commit ref
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta5-2
- Rebuild against current superproject HEAD
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-2
- Rebuild against current superproject HEAD
- Remove hardcoded ADMIRAL_LISTEN_ADDRESS from systemd unit
- Fix node removal: filter cancelled instances in active count check
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-1
- Bump to 0.0.1beta4, update spec commit ref
- Derive node token type from NodeRole instead of hardcoded worker
- Add generateUUID helper for UUID v4 claim IDs
- Add RemoveNode database operation with transaction support
- Add DELETE /api/v1/nodes/{id} endpoint

* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta3-2
- Rebuild against current superproject HEAD

* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta3-1
- Bump to 0.0.1beta3, update spec commit ref
- Demote cockpit-bridge to Recommends
- Remove redundant chown in %%post

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta2-1
- Bump to 0.0.1beta2, update spec commit ref
- Add per-node token authentication replacing shared token
- Replace gofmt and black formatting fixes

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-2
- Update spec commit ref to latest monorepo HEAD
- Add RateLimiter middleware for fleet endpoints
- Propagate request context in sync handlers
- Fix golangci-lint findings

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-1
- Bump to alpha7, update spec commit ref

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha6-1
- Bump to alpha6

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-2
- Update source commit to latest alpha5

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-1
- Bump to alpha5

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-5
- Include hostname in provision response for real app URL

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-4
- Add generate type to credentials response for cleaner UI display

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-3
- Add GET /api/v1/customer-apps/{id}/credentials endpoint for exposed secrets

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-2
- Handle Caddy reverse proxy routes via admirald

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Add X-Forwarded-Proto header to reverse proxy routes for Cockpit compatibility

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha3-1
- Bump admirald packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
