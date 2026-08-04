# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit d9cded4e371892ad5c794145a0ce494168ef6c81

Name:    admiralctl
Version: 0.0.1beta20
Release: 68%{?dist}
Summary: Admiral Command-Line Interface

License: Apache-2.0
URL:     https://github.com/admiral-project/admiralctl
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admiralctl.yaml

BuildRequires: golang >= 1.26.5
BuildRequires: git

Requires: admiral-common
Requires: openssh-clients

%description
admiralctl is the official command-line interface for Admiral.
It communicates with admirald and provides commands for initialization,
diagnostics, configuration, app management, node management, instance
management, backup operations, and troubleshooting.

%prep
%setup -q -n admiral-v%{version}

%build
cd admiralctl
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go build -trimpath -buildmode=pie -ldflags="-s -w -X main.Version=%{version}" -o admiralctl ./cmd/admiralctl/

%install
cd admiralctl
install -Dm0755 admiralctl %{buildroot}%{_bindir}/admiralctl
install -Dm0600 %{SOURCE1} %{buildroot}%{_sysconfdir}/admiralctl/config.yaml
install -Dm0644 docs/admiralctl.1 %{buildroot}%{_mandir}/man1/admiralctl.1
install -Dm0644 docs/admiralctl-admin.8 %{buildroot}%{_mandir}/man8/admiralctl-admin.8

%check
cd admiralctl
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
    go test ./...

%files
%license admiralctl/LICENSE
%{_bindir}/admiralctl
%{_mandir}/man1/admiralctl.1*
%{_mandir}/man8/admiralctl-admin.8*
%dir %{_sysconfdir}/admiralctl
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admiralctl/config.yaml

%post
restorecon -F %{_bindir}/admiralctl 2>/dev/null || :

%changelog
* Mon Jul 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-1
- Bump version to 0.0.1beta18

* Mon Jul 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-3
- Align the superproject, build, and RPM refs with admiralctl origin/main
- Include the expanded CLI regression test suite in the source release

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-2
- Install the global CLI token configuration as root-only
- Rebuild with latest submodule refs and release bump

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-1
- Bump to 0.0.1beta17 and rebuild with latest security hardening

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-6
- Document idempotent secret rotation in CLI manuals

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-5
- Install the CLI and administration manpages

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-4
- Add idempotent secrets rotate command

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-2
- Rebase hardened CLI release onto origin/main

* Tue Jul 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-1
- chore(release): bump to 0.0.1beta16

* Tue Jul 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta15-3
- Fix instances list requiring customer_id when called without --customer flag
- Add optional --customer flag for filtering by customer

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
- Update source commit ref for Authorization Bearer migration

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-1
- chore(release): bump to 0.0.1beta14 and update source commit refs to latest HEAD

* Sat Jun 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta13-1
- Bump to 0.0.1beta13 and update source commit ref

* Fri Jun 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta12-1
- Bump to 0.0.1beta12 and update source commit ref
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta11-1
- Bump to 0.0.1beta11 and reset packaging release to 1
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-2
- Add instances credentials subcommand
- Improve provision --wait to display post-setup credentials and hostname
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-1
- Coordinate beta10 release for setup_command catalog validation
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-3
- Update source commit for SharedVolumes / DependsOn API types
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-1
- Bump to 0.0.1beta9, update source commit ref
- Multi-node beta: sync man pages with CLI
- Add admin man8 page
- Update README with complete CLI reference
- Expand test coverage for CLI output and client helpers
* Mon Jun 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta8-2
- Bump to 0.0.1beta8, update source commit ref
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta5-2
- Rebuild against current superproject HEAD
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-2
- Rebuild against current superproject HEAD
- Remove hardcoded ADMIRAL_LISTEN_ADDRESS from admirald systemd unit
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-1
- Bump to 0.0.1beta4, update spec commit ref
- Add nodes remove subcommand with --force flag

* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta3-1
- Bump to 0.0.1beta3, update spec commit ref

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta2-1
- Bump to 0.0.1beta2, update spec commit ref
- Rename ADMIRAL_SHARED_TOKEN to ADMIRAL_ADMIN_TOKEN

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-2
- Update spec commit ref to latest monorepo HEAD

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-1
- Bump to alpha7, update spec commit ref

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha6-1
- Bump to alpha6

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-2
- Update source commit to latest alpha5

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-1
- Bump to alpha5

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Bump admiralctl packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
