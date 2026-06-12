# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 4ce36394ab5bb2a3aa7f753b1d3d615317efecc7

Name:    admiral-flagship
Version: 0.0.1alpha2
Release: 1%{?dist}
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

%changelog
* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
