# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 65721ccce087f400640e17a17d3d9a1b2bf8edae

Name:    admirald
Version: 0.0.1alpha3
Release: 1%{?dist}
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
* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha3-1
- Bump admirald packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
