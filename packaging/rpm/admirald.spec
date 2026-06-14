# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit ecd6fd476c90d1e3243a69ba8dac9db6dc714785

Name:    admirald
Version: 0.0.1alpha4
Release: 5%{?dist}
Summary: Admiral Control Plane - Core API and orchestration service

License: Apache-2.0
URL:     https://github.com/admiral-project/admirald
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admirald.service
Source2: admirald.ini

BuildRequires: golang >= 1.22
BuildRequires: systemd

Requires: admiral-common
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
go build -buildmode=pie -ldflags="-s -w -X main.Version=%{version}" -o admirald ./cmd/admirald/

%install
cd admirald
install -Dm0755 admirald %{buildroot}%{_bindir}/admirald
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admirald.service
install -Dm0644 %{SOURCE2} %{buildroot}%{_sysconfdir}/admirald.ini

%check
cd admirald
go test ./...

%files
%license admirald/LICENSE
%{_bindir}/admirald
%{_unitdir}/admirald.service
%config(noreplace) %{_sysconfdir}/admirald.ini

%post
%systemd_post admirald.service
restorecon -F %{_bindir}/admirald 2>/dev/null || :

%preun
%systemd_preun admirald.service

%postun
%systemd_postun_with_restart admirald.service

%changelog
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
