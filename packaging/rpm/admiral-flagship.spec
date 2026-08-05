# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit 34fd70c380649cd85c76cd1bd905650222b2d0d9

Name:    admiral-flagship
Version: 0.0.1beta21
Release: 80%{?dist}
Summary: Admiral Administrative Web Console

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-flagship
Source0: https://github.com/admiral-project/admiral-flagship/archive/%{commit}/admiral-flagship-%{version}.tar.gz
Source1: admiral-flagship.service
Source2: flagship.env

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-flask
BuildRequires: python3-werkzeug >= 3.0.6
BuildRequires: python3-gunicorn
BuildRequires: python3-pytest
BuildRequires: python3-requests
BuildRequires: systemd

Requires: admiral-common
Requires: python3
Requires: python3-flask >= 3.1.3
Requires: python3-werkzeug >= 3.0.6
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
install -Dm0600 %{SOURCE2} %{buildroot}%{_sysconfdir}/admiral/flagship.env
install -d %{buildroot}/etc/systemd/system/admiral-flagship.service.d

%files -f flagships.files
%license %{_licensedir}/admiral-flagship/LICENSE
%{_unitdir}/admiral-flagship.service
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admiral/flagship.env
%dir %attr(0750, root, admiral) /etc/systemd/system/admiral-flagship.service.d

%post
%systemd_post admiral-flagship.service
restorecon -R %{_prefix}/lib/admiral/flagship 2>/dev/null || :

%preun
%systemd_preun admiral-flagship.service

%postun
%systemd_postun_with_restart admiral-flagship.service

%check
%{python3} -m pytest tests/ -x --tb=short

%changelog
* Wed Aug 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta21-77
- Bump to beta21: coordinated release validation candidate

* Mon Jul 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-1
- Bump version to 0.0.1beta18

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-2
- Install the Flagship token configuration as root-only
- Rebuild with latest submodule refs and release bump

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-1
- Bump to 0.0.1beta17 and rebuild with latest security hardening

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-5
- Self-host browser assets and restrict the CSP to same-origin resources

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-3
- Package latest origin/main formatting fixes

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-2
- Rebase security hardening release onto origin/main

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-2
- Add missing BuildRequires for %%check section

* Tue Jul 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-1
- Harden the Flagship systemd unit with strict filesystem and device policy

* Tue Jul 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-1
- chore(release): bump to 0.0.1beta16

* Tue Jul 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta15-2
- Update source commit refs to include security audit fixes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-3
- Update submodule commit refs and bump release

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-2
- Update source commit ref for Authorization Bearer migration and test fixes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-1
- chore(release): bump to 0.0.1beta14 and update source commit refs to latest HEAD

* Sat Jun 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta13-1
- Bump to 0.0.1beta13 and update source commit ref

* Fri Jun 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta12-1
- Bump to 0.0.1beta12 and update source commit ref
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta11-1
- Bump to 0.0.1beta11 and reset packaging release to 1
* Thu Jun 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-2
- Add BFF endpoint for instance credentials
- Display credentials in instance create and detail views
* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-1
- Surface initializing and setup_failed states in dashboard summaries and labels
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-1
- Bump to 0.0.1beta9, update source commit ref
- Multi-node beta: show instance hostname in detail view
- Filter portal nodes from instance placement (node_role=worker)
- Harden flagship for direct internet exposure
- Add rate limiting coverage for in-memory limiter
- Throttle repeated unauthorized flagship access
* Mon Jun 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta8-2
- Rebuild against current superproject HEAD
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
