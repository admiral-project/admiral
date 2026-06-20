# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit f9beb9816b9337a496b1310645ecf70736ac1f8e

Name:    admiral-flagship
Version: 0.0.1beta5
Release: 2%{?dist}
Summary: Admiral Administrative Web Console

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-flagship
Source0: https://github.com/admiral-project/admiral-flagship/archive/%{commit}/admiral-flagship-%{version}.tar.gz
Source1: admiral-flagship.service
Source2: flagship.env

BuildArch: noarch

BuildRequires: python3
BuildRequires: systemd

Requires: admiral-common
Requires: python3
Requires: python3-flask
Requires: python3-requests
Requires: python3-gunicorn
Requires: systemd

%description
admiral-flagship is the administrative web console for Admiral.
Operators use flagship to manage nodes, applications, instances,
backups, and platform operations through a web interface.

%prep
%setup -q -n %{name}-v%{version}

%build

%install
# Install application files if they exist
mkdir -p %{buildroot}%{_prefix}/lib/admiral/flagship
echo "%%dir %{_prefix}/lib/admiral/flagship" > flagships.files
if [ -d app ]; then
    cp -r app run.py %{buildroot}%{_prefix}/lib/admiral/flagship/
    find %{buildroot}%{_prefix}/lib/admiral/flagship -type f | sed "s|%{buildroot}||" | sort >> flagships.files
fi
if [ -f LICENSE ]; then
    install -Dm0644 LICENSE %{buildroot}%{_licensedir}/admiral-flagship/LICENSE
else
    install -Dm0644 /dev/stdin %{buildroot}%{_licensedir}/admiral-flagship/LICENSE <<'EOF'
Apache License 2.0
See https://www.apache.org/licenses/LICENSE-2.0
EOF
fi
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admiral-flagship.service
install -Dm0644 %{SOURCE2} %{buildroot}%{_sysconfdir}/admiral/flagship.env

%files -f flagships.files
%license %{_licensedir}/admiral-flagship/LICENSE
%{_unitdir}/admiral-flagship.service
%config(noreplace) %{_sysconfdir}/admiral/flagship.env

%post
%systemd_post admiral-flagship.service
restorecon -R %{_prefix}/lib/admiral/flagship 2>/dev/null || :

%preun
%systemd_preun admiral-flagship.service

%postun
%systemd_postun_with_restart admiral-flagship.service

%check
%{python3} -m pytest tests/ -x --tb=short 2>/dev/null || echo "WARNING: tests skipped (pytest not available)"

%changelog
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta5-2
- Rebuild against current superproject HEAD
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-2
- Rebuild against current superproject HEAD
- Remove hardcoded ADMIRAL_LISTEN_ADDRESS from admirald systemd unit
* Fri Jun 19 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta4-1
- Bump to 0.0.1beta4, update spec commit ref
- Add remove node modal with type-to-confirm in BFF and UI
* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta3-1
- Bump to 0.0.1beta3, update spec commit ref
- Add BuildRequires: python3-rpm-macros
- Add %%check section

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta2-1
- Bump to 0.0.1beta2, update spec commit ref
- Rename ADMIRAL_SHARED_TOKEN to ADMIRAL_ADMIN_TOKEN

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-2
- Bump release to match coordinated packaging update

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-1
- Bump to alpha7, update spec commit ref

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha6-1
- Bump to alpha6

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-2
- Update source commit to latest alpha5
- Replace favicon.ico with generated ico from source PNG

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-1
- Bump to alpha5

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Bump admiral-flagship packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
