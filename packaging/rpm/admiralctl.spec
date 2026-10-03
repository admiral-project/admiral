# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 68551d9398c32417f2b374ece074c2a1ab6f4d45

%ifarch x86_64
%global admiral_goarch amd64
%endif
%ifarch aarch64
%global admiral_goarch arm64
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%endif

Name:    admiralctl
Version: 0.0.1rc5
Release: 19%{?dist}
Summary: Admiral Command-Line Interface

License: Apache-2.0
ExclusiveArch: x86_64 aarch64
URL:     https://github.com/admiral-project/admiralctl
Source0: https://github.com/admiral-project/admiralctl/archive/%{commit}.tar.gz
Source1: admiralctl.yaml
Source2: https://github.com/admiral-project/admirald/archive/d53681ca3335f41d6681195734fa70c78c9b30bb.tar.gz

BuildRequires: golang >= 1.26.5
BuildRequires: binutils
BuildRequires: git

Requires: admiral-common
Requires: openssh-clients

%description
admiralctl is the official command-line interface for Admiral.
It communicates with admirald and provides commands for initialization,
diagnostics, configuration, app management, node management, instance
management, backup operations, and troubleshooting.

%prep
%setup -q -n admiralctl-%{commit}
mkdir -p admirald
tar -xzf %{SOURCE2} --strip-components=1 -C admirald

%build
export GOWORK=off
export GOOS=linux
export GOARCH=%{admiral_goarch}
export CGO_ENABLED=0
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go build -trimpath -buildmode=pie -ldflags="-s -w -X github.com/admiral-project/admiral/admiralctl/internal/version.Version=%{version}" -o admiralctl ./cmd/admiralctl/

%install
install -Dm0755 admiralctl %{buildroot}%{_bindir}/admiralctl
install -Dm0600 %{SOURCE1} %{buildroot}%{_sysconfdir}/admiralctl/config.yaml
install -Dm0644 docs/admiralctl.1 %{buildroot}%{_mandir}/man1/admiralctl.1
install -Dm0644 docs/admiralctl-admin.8 %{buildroot}%{_mandir}/man8/admiralctl-admin.8

%check
export GOWORK=off
export PATH=/usr/lib/golang/bin:%{_bindir}:$PATH
export GOCACHE=%{_tmppath}/go-cache
mkdir -p "$GOCACHE"
go test ./...
%ifarch aarch64
readelf -h ./admiralctl | grep -Eq 'Machine:[[:space:]]+AArch64'
env -u GOOS -u GOARCH -u CGO_ENABLED go build -trimpath -buildmode=pie \
    -ldflags="-s -w -X github.com/admiral-project/admiral/admiralctl/internal/version.Version=%{version}" \
    -o admiralctl-native-check ./cmd/admiralctl/
test "$(./admiralctl-native-check version 2>&1)" = "admiralctl %{version}"
%else
readelf -h ./admiralctl | grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64'
test "$(./admiralctl version 2>&1)" = "admiralctl %{version}"
%endif

%files
%license LICENSE
%{_bindir}/admiralctl
%{_mandir}/man1/admiralctl.1*
%{_mandir}/man8/admiralctl-admin.8*
%dir %{_sysconfdir}/admiralctl
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admiralctl/config.yaml

%post
restorecon -F %{_bindir}/admiralctl 2>/dev/null || :

%changelog
* Fri Oct 02 2026 Codex <codex@openai.com> - 0.0.1rc5-18
- Rebuild the coordinated RC5 set with Fleet version telemetry fix

* Fri Oct 02 2026 Codex <codex@openai.com> - 0.0.1rc5-17
- Add the worker WireGuard peer to the hub before the Fleet readiness gate

* Fri Oct 02 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-15
- Rebuild coordinated RC5 set after fixing Fleet token status selection

* Fri Oct 02 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-14
- Rebuild coordinated RC5 set after Fleet heartbeat readiness fix

* Fri Oct 02 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-13
- Wait for the backup storage test operation to finish before reporting success

* Fri Oct 02 2026 Codex <codex@openai.com> - 0.0.1rc5-9
- Rebuild all six RC5 RPMs after adding bounded database readiness before backups

* Thu Oct 01 2026 Codex <codex@openai.com> - 0.0.1rc5-8
- Rebuild the coordinated RC5 RPM set with clean-install fixes

* Thu Oct 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-7
- Accept readelf's variable header spacing in target architecture checks

* Thu Oct 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-6
- Fix cross-architecture RPM checks and keep the coordinated release set aligned

* Thu Oct 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-5
- Rebuild the coordinated RC5 set with Fedora multi-node fixes and arm64 support

* Thu Oct 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-4
- Rebuild RC5 with Harbor support-reply and provision-contract fixes

* Wed Sep 30 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-3
- Rebuild RC5 with a version assertion capturing the CLI diagnostic output

* Wed Sep 30 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-2
- Rebuild the coordinated RC5 set with corrected CLI version injection

* Wed Sep 30 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-1
- Prepare the coordinated RC5 candidate for complete functional validation

* Wed Sep 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc4-10
- Rebuild the coordinated RC4 candidate after the EL version guard fix

* Wed Sep 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc4-9
- Rebuild the coordinated RC4 set with the Fedora Rawhide TLS compatibility fix

* Wed Sep 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc4-6
- Rebuild the coordinated RC4 RPM set for secure Fedora Tier 2 validation

* Wed Sep 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc4-5
- Rebuild RC4 packages with EPEL-provided Caddy

* Wed Sep 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc4-3
- Correct the source archive URL and extraction directory for reproducible RPM builds

* Tue Sep 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc4-1
- Release 0.0.1rc4

* Tue Sep 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc3-1
- Release 0.0.1rc3

* Mon Sep 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc2-3
- Rebuild RC2 set with rootless pasta workload isolation

* Mon Sep 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc2-2
- Rebuild RC2 set with the spoke peer exchange token fix

* Mon Sep 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc2-1
- Release 0.0.1rc2

* Fri Aug 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc1-51
- Rebuild RC1 with resilient spoke SSH post-revocation validation

* Wed Aug 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta21-44
- Bump to beta21: coordinated release validation candidate

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
