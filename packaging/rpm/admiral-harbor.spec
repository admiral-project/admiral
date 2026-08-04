%global debug_package %{nil}
%global commit 792e18a516997689f246740afa28a98ac09f20cf

Name:    admiral-harbor
Version: 0.0.1beta20
Release: 58%{?dist}
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
Source9: harbor-migrate

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-argon2-cffi
BuildRequires: python3-cryptography
BuildRequires: python3-flask
BuildRequires: python3-werkzeug >= 3.0.6
BuildRequires: python3-flask-alembic
BuildRequires: python3-flask-login
BuildRequires: python3-flask-sqlalchemy
BuildRequires: python3-gunicorn
BuildRequires: python3-mistune
BuildRequires: python3-pytest
BuildRequires: python3-pyyaml
BuildRequires: python3-requests
BuildRequires: systemd

Requires: admiral-common
Requires: python3-flask >= 3.1.3
Requires: python3-werkzeug >= 3.0.6
Requires: python3-flask-login
Requires: python3-flask-sqlalchemy
Requires: python3-flask-alembic
Requires: python3-gunicorn
Requires: python3-requests
Requires: python3-pyyaml
Requires: python3-argon2-cffi
Requires: python3-cryptography
Requires: python3-mistune
Requires: python3-psycopg2
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
    cp -r app run.py worker.py cli.py migrate.py alembic.ini migrations %{buildroot}%{_prefix}/lib/admiral/harbor/
    find %{buildroot}%{_prefix}/lib/admiral/harbor -type f -o -type l | sed "s|%{buildroot}||" | sort >> harbor.files
fi
# Install harborctl entry point
install -Dm0755 %{SOURCE6} %{buildroot}%{_bindir}/harborctl
# Install gunicorn wrapper
install -Dm0755 %{SOURCE7} %{buildroot}%{_bindir}/harbor-gunicorn
install -Dm0755 %{SOURCE9} %{buildroot}%{_bindir}/harbor-migrate
install -Dm0644 docs/harborctl.8 %{buildroot}%{_mandir}/man8/harborctl.8
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
install -Dm0600 %{SOURCE8} %{buildroot}%{_sysconfdir}/admiral/harbor.env
install -d %{buildroot}/etc/systemd/system/admiral-harbor.service.d
mkdir -p %{buildroot}%{_localstatedir}/lib/admiral/harbor/uploads

%files -f harbor.files
%license %{_licensedir}/admiral-harbor/LICENSE
%{_unitdir}/admiral-harbor.service
%{_unitdir}/admiral-harbor-worker.service
%{_unitdir}/admiral-harbor-worker.timer
%{_unitdir}/admiral-harbor-catalog-sync.service
%{_unitdir}/admiral-harbor-catalog-sync.timer
%{_bindir}/harbor-gunicorn
%{_bindir}/harbor-migrate
%{_bindir}/harborctl
%{_mandir}/man8/harborctl.8*
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admiral/harbor.env
%dir %attr(0750, root, admiral) /etc/systemd/system/admiral-harbor.service.d
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
%{python3} -m pytest tests/ -x --tb=short

%changelog
* Thu Jul 30 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-2
- Normalize SLA datetimes and use calendar-month revenue windows

* Mon Jul 27 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta18-1
- Bump version to 0.0.1beta18

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-2
- Fix Harbor migration path and bootstrap behavior before service startup

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-7
- Use the database PayPal mode consistently across checkout and callbacks
- Prevent mock provisioning when administrators activate live payments

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-6
- Preserve an existing PayPal secret for unchanged credentials
- Require a new secret when switching payment environment or client

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-5
- Select fixed PayPal API endpoints from the validated payment mode
- Fail closed for invalid modes and missing live credentials

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-4
- Materialize live subscriptions from their locked PayPal orders
- Provision only after a completed sale with matching amount and currency

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-3
- Send webhook_event as an object to PayPal signature verification

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-2
- Install the Harbor credential configuration as root-only
- Rebuild with latest submodule refs and release bump

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta17-1
- Bump to 0.0.1beta17 and rebuild with latest security hardening
- Preserve the raw PayPal webhook payload for signature verification

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-14
- Require POST and CSRF protection for billing and email confirmation actions

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-13
- Fix linting for the explicit migration launcher

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-12
- Install the harborctl administration manpage

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-11
- Include the explicit Harbor migration launcher in package sources

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-10
- Remove unused migration factory import

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-9
- Run Harbor schema migrations explicitly before Gunicorn startup

* Fri Jul 17 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-8
- Format billing idempotency migration for CI and packaging

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-6
- Package latest origin/main formatting fixes

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-5
- Continue worker reconciliation after an individual step failure

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-4
- Enforce minimum password strength for customer and administrator accounts

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-3
- Remove python3-psycopg3 from Requires (unused; app uses psycopg2 dialect)
- Fix changelog chronological order

* Thu Jul 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-2
- Add missing BuildRequires for %%check section

* Tue Jul 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta16-1
- Harden Harbor services with strict filesystem and device policy

* Tue Jul 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta15-2
- Update source commit refs to include security audit fixes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-6
- Set session cookie SameSite to Strict
- Reduce customer session timeout from 240 to 120 minutes

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-5
- Update submodule commit refs and bump release

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-4
- Update source commit ref for black format fix

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta14-3
- Update source commit ref for customer_id API changes

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

* Wed Jun 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta10-1
- Coordinate beta10 release for setup_command catalog validation

* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta9-1
- Bump to 0.0.1beta9, update source commit ref
- Multi-node beta: add rate limiting and audit remediation
- Harden harbor and modernize session configuration
- Fix admin login rate limit tests
- Align DATABASE_URL sslmode to require
- Fix admin login with bootstrap user credentials

* Mon Jun 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta8-2
- Bump to 0.0.1beta8, update source commit ref

* Sat Jun 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1beta7-1
- Bump to 0.0.1beta7, update source commit ref

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

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-4
- Add missing tone-ok CSS class for status pills

* Sun Jun 14 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha5-3
- Rework instance detail page layout and styling

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

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-3
- Bump admiral-harbor packaging

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-2
- Add HARBOR_DATABASE_URL env var and python3-psycopg2 dependency

* Sat Jun 13 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1alpha4-1
- Bump admiral-harbor packaging to alpha3

* Wed Jun 03 2026 Admiral Project <dev@admiral-project.org> - 0.1.0-1
- Initial Admiral packaging
