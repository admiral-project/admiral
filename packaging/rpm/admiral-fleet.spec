# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 070d777797daa58befab4aa40c2dee2e74b0e9f2

Name:    admiral-fleet
Version: 0.0.1alpha7
Release: 4%{?dist}
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
Requires: cockpit-bridge
Requires: admiralctl

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
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-4
- Ensure rootless user manager is ready before Quadlet reload and start

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-2
- Update spec commit ref to latest monorepo HEAD

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-1
- Bump to alpha7, update spec commit ref

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha6-1
- Bump to alpha6

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-4
- Add Requires: admiralctl for worker bootstrap and node registration

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-3
- Add Requires: cockpit-bridge for remote monitoring via Cockpit

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-2
- Update source commit to latest alpha5

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-1
- Bump to alpha5

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-3
- Add CAP_FOWNER to systemd unit CapabilityBoundingSet

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-2
- Bump admiral-fleet packaging to alpha3-2

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Bump admiral-fleet packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
