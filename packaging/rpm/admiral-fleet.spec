# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit ebf906e5a052437832c538561c7136ce37b2f7bc

Name:    admiral-fleet
Version: 0.0.1beta20
Release: 48%{?dist}
Summary: Admiral Fleet Worker Agent

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-fleet
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admiral-fleet.service
Source2: fleet.env

BuildRequires: golang >= 1.26.5
BuildRequires: systemd >= 250
BuildRequires: git

Requires: admiral-common
Requires: podman >= 5
Requires: openssh-clients
Requires: shadow-utils
Requires: systemd >= 250
Requires: systemd-container
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
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go build -trimpath -buildmode=pie -ldflags="-s -w" -o admiral-fleet ./cmd/admiral-fleet/
go build -trimpath -buildmode=pie -ldflags="-s -w" -o admiral-fleet-lifecycle ./cmd/admiral-fleet-lifecycle/
go build -trimpath -buildmode=pie -ldflags="-s -w" -o admiral-fleet-setup ./cmd/admiral-fleet-setup/
go build -trimpath -buildmode=pie -ldflags="-s -w" -o admiral-fleet-backup ./cmd/admiral-fleet-backup/

%install
cd admiral-fleet
install -Dm0755 admiral-fleet %{buildroot}%{_bindir}/admiral-fleet
install -Dm0755 admiral-fleet-lifecycle %{buildroot}%{_bindir}/admiral-fleet-lifecycle
install -Dm0755 admiral-fleet-setup %{buildroot}%{_bindir}/admiral-fleet-setup
install -Dm0755 admiral-fleet-backup %{buildroot}%{_bindir}/admiral-fleet-backup
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admiral-fleet.service
install -Dm0600 %{SOURCE2} %{buildroot}%{_sysconfdir}/admiral/fleet.env

%check
cd admiral-fleet
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
    go test ./...

%files
%license admiral-fleet/LICENSE
%{_bindir}/admiral-fleet
%{_bindir}/admiral-fleet-lifecycle
%{_bindir}/admiral-fleet-setup
%{_bindir}/admiral-fleet-backup
%{_unitdir}/admiral-fleet.service
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admiral/fleet.env

%post
%systemd_post admiral-fleet.service
restorecon -F %{_bindir}/admiral-fleet 2>/dev/null || :
restorecon -F %{_bindir}/admiral-fleet-lifecycle 2>/dev/null || :
restorecon -F %{_bindir}/admiral-fleet-setup 2>/dev/null || :
restorecon -F %{_bindir}/admiral-fleet-backup 2>/dev/null || :
loginctl enable-linger admiral-apps 2>/dev/null || :

%preun
%systemd_preun admiral-fleet.service

%postun
%systemd_postun_with_restart admiral-fleet.service

%changelog
* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-8
- Delegate all Podman operations through specialized rootless helpers
- Share one systemd user-session transport across lifecycle, setup and backup

* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-9
- Preserve rootless ownership for delegated temporary environment files

* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-7
- Hand storage trees to the rootless user without following symlinks
- Skip symlinks during tree migration (Lchown, no TOCTOU dereference)

* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-6
- Hand pre-existing backup/restore trees to the rootless user

* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-5
- Route helper podman operations through systemd-run for the rootless session
- Preserve the helper's structured error on task failure

* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-4
- Run backup/restore data plane as the rootless user via admiral-fleet-backup
- Ship the admiral-fleet-backup helper binary in the fleet package
- Remove root-to-rootless chown workarounds from the restore data path

* Sat Aug 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta19-3
- Make restore staging dirs and artifacts readable by the rootless user
- Fix S3/HTTPS database restore "permission denied" on podman cp

* Wed Jul 29 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-2
- Probe published workload address for multinode healthchecks

* Mon Jul 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-1
- Bump version to 0.0.1beta18

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-2
- Create backup artifacts with private permissions
- Stop distributing the queue encryption key to Fleet
- Install the Fleet token configuration as root-only
- Rebuild with latest submodule refs and release bump

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-1
- Bump to 0.0.1beta17 and rebuild with latest security hardening

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-2
- Rebase hardened worker release onto origin/main

* Tue Jul 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-1
- Run rootless Podman exec through the persistent user bus
- Keep transient env files visible across PrivateTmp namespaces
- Record restorable local backup keys
- Harden the Fleet systemd service with the EL10-validated profile

* Tue Jul 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta15-3
- Fix quadlet DropCapabilities key (use DropCapability singular)
- Remove DropCapability=all that breaks MariaDB setuid
- Document rationale in code comment

* Tue Jul 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta15-2
- Update source commit refs to include security audit fixes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-7
- Update submodule commit refs and bump release

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-6
- Update source commit ref

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-5
- Update source commit ref

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-4
- Update source commit ref

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-3
- Update source commit ref for super-repo hash

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-2
- Update source commit ref for signature verification, auth header migration, security fixes, and gofmt

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-1
- chore(release): bump to 0.0.1beta14 and update source commit refs to latest HEAD

* Sat Jun 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta13-1
- Bump to 0.0.1beta13 and update source commit ref

* Fri Jun 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta12-1
- Bump to 0.0.1beta12 and update source commit ref
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta11-1
- Bump to 0.0.1beta11 and reset packaging release to 1
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-3
- Revert to validated systemctl --machine=<user>@ --user invocation
- Add Requires: systemd-container so rootless user manager access works on EL10

* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-2
- Bump release to 2 for coordinated packaging update
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-1
- Coordinate beta10 release for setup_command catalog validation
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-4
- Replace LoadCredentialEncrypted with Quadlet native Secret= directive
- Secrets injected via Podman secret store (encrypted at rest)
- Fix provisioning on systemd >=256 and credential delivery to containers
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-3
- Move LoadCredentialEncrypted from [Container] to [Service] section
- Fix quadlet-generator rejection on systemd >=256
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
