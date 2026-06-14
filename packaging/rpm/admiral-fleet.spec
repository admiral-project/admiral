# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit b0d899ee0263e046080d3c29f4c9043fec7e3bed

Name:    admiral-fleet
Version: 0.0.1alpha4
Release: 1%{?dist}
Summary: Admiral Fleet Worker Agent

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-fleet
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admiral-fleet.service
Source2: fleet.env

BuildRequires: golang >= 1.22
BuildRequires: systemd

Requires: admiral-common
Requires: podman >= 5
Requires: openssh-clients
Requires: shadow-utils
Requires: systemd
Requires: wireguard-tools

%description
admiral-fleet is the worker agent component of Admiral. It runs on
workload nodes and executes authorized tasks received from admirald.
It interacts locally with Podman, systemd, volumes, backups, and
node-level resources.

%prep
%setup -q -n admiral-v%{version}

%build
cd admiral-fleet
go build -buildmode=pie -ldflags="-s -w" -o admiral-fleet ./cmd/admiral-fleet/

%install
cd admiral-fleet
install -Dm0755 admiral-fleet %{buildroot}%{_bindir}/admiral-fleet
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admiral-fleet.service
install -Dm0644 %{SOURCE2} %{buildroot}%{_sysconfdir}/admiral/fleet.env

%check
cd admiral-fleet
go test ./...

%files
%license admiral-fleet/LICENSE
%{_bindir}/admiral-fleet
%{_unitdir}/admiral-fleet.service
%config(noreplace) %{_sysconfdir}/admiral/fleet.env

%post
%systemd_post admiral-fleet.service
restorecon -F %{_bindir}/admiral-fleet 2>/dev/null || :

%preun
%systemd_preun admiral-fleet.service

%postun
%systemd_postun_with_restart admiral-fleet.service

%changelog
* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Bump admiral-fleet packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
