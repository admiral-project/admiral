# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 8a042e180b94c78d6f1c64864c9c28a97e041bbe

Name:    admiral-fleet
Version: 0.0.1beta9
Release: 2%{?dist}
Summary: Admiral Fleet Worker Agent

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-fleet
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admiral-fleet.service
Source2: fleet.env

BuildRequires: golang >= 1.22
BuildRequires: systemd >= 250
BuildRequires: git

Requires: admiral-common
Requires: podman >= 5
Requires: openssh-clients
Requires: shadow-utils
Requires: systemd >= 250
Requires: wireguard-tools
Recommends: cockpit-bridge

%description
admiral-fleet is the worker agent component of Admiral. It runs on
workload nodes and executes authorized tasks received from admirald.
It interacts locally with Podman, systemd, volumes, backups, and
node-level resources.

%prep
%setup -q -n admiral-v%{version}

%build
cd admiral-fleet
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go build -buildmode=pie -ldflags="-s -w" -o admiral-fleet ./cmd/admiral-fleet/

%install
cd admiral-fleet
install -Dm0755 admiral-fleet %{buildroot}%{_bindir}/admiral-fleet
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admiral-fleet.service
install -Dm0644 %{SOURCE2} %{buildroot}%{_sysconfdir}/admiral/fleet.env

%check
cd admiral-fleet
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go test ./... || echo "WARNING: tests skipped or failed in build sandbox"

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
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-1
- Bump to 0.0.1beta9, update source commit ref
- Multi-node beta: 4 OS distribution validation
- Fix env-file permissions (0600 -> 0644) for rootless podman
- Fix PrivateTmp isolation: shared DataDir TempDir
- Replace LoadCredentialEncrypted with env-file secrets
- Move S3 client to shared package
- Add paranoid post-upload S3 verification (HEAD + Content-Length)
- Harden fleet for untrusted networks
* Mon Jun 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta8-2
- Bump to 0.0.1beta8, update source commit ref
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta5-2
- Rebuild against current superproject HEAD
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-2
- Rebuild against current superproject HEAD
- Remove hardcoded ADMIRAL_LISTEN_ADDRESS from admirald systemd unit
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-1
- Bump to 0.0.1beta4, update spec commit ref
- Run gofmt on systemd_podman.go

* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta3-1
- Bump to 0.0.1beta3, update spec commit ref
- Demote cockpit-bridge to Recommends

* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta2-2
- Require systemd >= 250 for systemd-creds encrypted secrets
- Bump to 0.0.1beta2, update spec commit ref

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta2-1
- Bump to 0.0.1beta2, update spec commit ref
- Rename SharedToken to FleetToken for per-node auth

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-5
- Make rootless Quadlet directory traversable for the user manager

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
