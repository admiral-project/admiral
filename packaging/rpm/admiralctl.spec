# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 646e612f349b4973d074b4f0c7f9a56e1bee4e00

Name:    admiralctl
Version: 0.0.1beta3
Release: 1%{?dist}
Summary: Admiral Command-Line Interface

License: Apache-2.0
URL:     https://github.com/admiral-project/admiralctl
Source0: https://github.com/admiral-project/admiral/archive/%{commit}/admiral-%{version}.tar.gz
Source1: admiralctl.yaml

BuildRequires: golang >= 1.22

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
go build -buildmode=pie -ldflags="-s -w -X main.Version=%{version}" -o admiralctl ./cmd/admiralctl/

%install
cd admiralctl
install -Dm0755 admiralctl %{buildroot}%{_bindir}/admiralctl
install -Dm0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/admiralctl/config.yaml
# man page not yet generated from docs/man.md
# install -Dm0644 docs/admiralctl.1 %{buildroot}%{_mandir}/man1/admiralctl.1

%check
cd admiralctl
go test ./...

%files
%license admiralctl/LICENSE
%{_bindir}/admiralctl
# %{_mandir}/man1/admiralctl.1*
%dir %{_sysconfdir}/admiralctl
%config(noreplace) %{_sysconfdir}/admiralctl/config.yaml

%post
restorecon -F %{_bindir}/admiralctl 2>/dev/null || :

%changelog
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
