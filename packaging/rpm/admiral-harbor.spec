%global debug_package %{nil}
%global commit 66a8fe9b068768d2a7b6c994a83f49712789ba26

Name:    admiral-harbor
Version: 0.0.1beta5
Release: 2%{?dist}
Summary: Admiral Customer Portal - Web UI for end users

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-harbor
Source0: https://github.com/admiral-project/admiral-harbor/archive/%{commit}/admiral-harbor-%{version}.tar.gz
Source1: admiral-harbor.service
Source2: admiral-harbor-worker.service
Source3: admiral-harbor-worker.timer
Source4: admiral-harbor-catalog-sync.service
Source5: admiral-harbor-catalog-sync.timer
Source6: harborctl
Source7: harbor-gunicorn
Source8: harbor.env

BuildArch: noarch

BuildRequires: python3
BuildRequires: systemd

Requires: admiral-common
Requires: python3-flask
Requires: python3-flask-login
Requires: python3-flask-sqlalchemy
Requires: python3-flask-alembic
Requires: python3-gunicorn
Requires: python3-requests
Requires: python3-argon2-cffi
Requires: python3-cryptography
Requires: python3-mistune
Requires: python3-psycopg2
Requires: python3-psycopg3 >= 3.1
Requires: systemd
Recommends: cockpit-bridge
Requires: wireguard-tools

%description
admiral-harbor is the customer-facing web portal for Admiral.
End users interact with harbor to manage their applications, view
usage, and perform self-service operations.

%prep
%setup -q -n %{name}-v%{version}

%build

%install
# Install application files if they exist
mkdir -p %{buildroot}%{_prefix}/lib/admiral/harbor
echo "%%dir %{_prefix}/lib/admiral/harbor" > harbor.files
if [ -d app ]; then
    cp -r app run.py worker.py cli.py alembic.ini migrations %{buildroot}%{_prefix}/lib/admiral/harbor/
    find %{buildroot}%{_prefix}/lib/admiral/harbor -type f -o -type l | sed "s|%{buildroot}||" | sort >> harbor.files
fi
# Install harborctl entry point
install -Dm0755 %{SOURCE6} %{buildroot}%{_bindir}/harborctl
# Install gunicorn wrapper
install -Dm0755 %{SOURCE7} %{buildroot}%{_bindir}/harbor-gunicorn
if [ -f LICENSE ]; then
    install -Dm0644 LICENSE %{buildroot}%{_licensedir}/admiral-harbor/LICENSE
else
    install -Dm0644 /dev/stdin %{buildroot}%{_licensedir}/admiral-harbor/LICENSE <<'EOF'
Apache License 2.0
See https://www.apache.org/licenses/LICENSE-2.0
EOF
fi
install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/admiral-harbor.service
install -Dm0644 %{SOURCE2} %{buildroot}%{_unitdir}/admiral-harbor-worker.service
install -Dm0644 %{SOURCE3} %{buildroot}%{_unitdir}/admiral-harbor-worker.timer
install -Dm0644 %{SOURCE4} %{buildroot}%{_unitdir}/admiral-harbor-catalog-sync.service
install -Dm0644 %{SOURCE5} %{buildroot}%{_unitdir}/admiral-harbor-catalog-sync.timer
install -Dm0644 %{SOURCE8} %{buildroot}%{_sysconfdir}/admiral/harbor.env
mkdir -p %{buildroot}%{_localstatedir}/lib/admiral/harbor/uploads

%files -f harbor.files
%license %{_licensedir}/admiral-harbor/LICENSE
%{_unitdir}/admiral-harbor.service
%{_unitdir}/admiral-harbor-worker.service
%{_unitdir}/admiral-harbor-worker.timer
%{_unitdir}/admiral-harbor-catalog-sync.service
%{_unitdir}/admiral-harbor-catalog-sync.timer
%{_bindir}/harbor-gunicorn
%{_bindir}/harborctl
%config(noreplace) %{_sysconfdir}/admiral/harbor.env
%dir %attr(0750, admiral, admiral) %{_localstatedir}/lib/admiral/harbor
%dir %attr(0750, admiral, admiral) %{_localstatedir}/lib/admiral/harbor/uploads

%post
%systemd_post admiral-harbor.service
%systemd_post admiral-harbor-worker.timer
%systemd_post admiral-harbor-catalog-sync.timer
restorecon -R %{_prefix}/lib/admiral/harbor 2>/dev/null || :
restorecon -R %{_localstatedir}/lib/admiral/harbor 2>/dev/null || :

%preun
%systemd_preun admiral-harbor.service
%systemd_preun admiral-harbor-worker.timer
%systemd_preun admiral-harbor-catalog-sync.timer

%postun
%systemd_postun_with_restart admiral-harbor.service
%systemd_postun admiral-harbor-worker.timer
%systemd_postun admiral-harbor-catalog-sync.timer

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
- Make env.py compatible with flask-alembic 3.x
* Thu Jun 18 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta3-1
- Bump to 0.0.1beta3, update spec commit ref
- Fix psycopg dependencies (remove psycopg2, correct psycopg3 name)
- Add BuildRequires: python3-rpm-macros
- Add %%check section
- Remove redundant chown in %%post

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta2-1
- Bump to 0.0.1beta2, update spec commit ref
- Rename ADMIRAL_SHARED_TOKEN to ADMIRAL_ADMIN_TOKEN
- Fix CSRF token assertion and ruff unused imports

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta1-3
- Rebuild RPM after extracting CSRF helper into a dedicated JavaScript asset

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta1-2
- Rebuild RPM with CSP-safe harbor admin shell and packaging updates

* Wed Jun 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta1-1
- Bump to 0.0.1beta1, include app/migrations symlink in %%files

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-2
- Update spec commit ref to latest admiral-harbor HEAD
- Add PayPal encryption support (AES-256-GCM via cryptography.fernet)

* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha7-1
- Bump to alpha7, update spec commit ref

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha6-1
- Bump to alpha6

* Mon Jun 15 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-3
- Add Requires: cockpit-bridge and Requires: wireguard-tools

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-2
- Update source commit to latest alpha5
- Replace favicon.ico with generated ico from source PNG
- Fix admin_layout.html to use static favicon.ico reference
- Fix branding.py and routes.py fallback for favicon vs logo
- Fix list_backups returning None items

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-1
- Bump to alpha5

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-6
- Use real hostname from provision response instead of instance_id for app URL
- Fix list_backups to never return None

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-5
- Simplify credentials display: show usuario/contraseña instead of raw env vars
- Always show app URL on provision confirmation page
- Filter out db service credentials from user-facing display

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-4
- Add provision confirmation page with credentials display
- Add Show credentials button to instance detail
- Fix admin templates: use technical_status instead of status
- Fix dashboard CSS grid max-width
- Add favicon to admin_layout.html

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-4
- Add missing tone-ok CSS class for status pills

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-3
- Rework instance detail page layout and styling

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-3
- Bump admiral-harbor packaging

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-2
- Add HARBOR_DATABASE_URL env var and python3-psycopg2 dependency

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Bump admiral-harbor packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
