# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global commit b7325bbc71fc474a521496e593b2967e4d555ac1

Name:    admiral-flagship
Version: 0.0.1rc6
Epoch:          5
Release:        6%{?dist}
Summary: Admiral Administrative Web Console

License: Apache-2.0
URL:     https://github.com/admiral-project/admiral-flagship
Source0: https://github.com/admiral-project/admiral-flagship/archive/%{commit}.tar.gz
Source1: admiral-flagship.service
Source2: flagship.env

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3dist(flask) = 3.1.3
BuildRequires: python3-werkzeug >= 3.0.6
BuildRequires: python3-gunicorn
BuildRequires: python3-pytest
BuildRequires: python3-requests
BuildRequires: systemd

Requires: admiral-common
Requires: python3
Requires: python3dist(flask) = 3.1.3
Requires: python3-werkzeug >= 3.0.6
Requires: python3-requests
Requires: python3-gunicorn
Requires: systemd

%description
admiral-flagship is the administrative web console for Admiral.
Operators use flagship to manage nodes, applications, instances,
backups, and platform operations through a web interface.

%prep
%setup -q -n %{name}-%{commit}

%build

%install
# Install application files if they exist
mkdir -p %{buildroot}%{_prefix}/lib/admiral/flagship
touch flagships.files
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

%files -f flagships.files
%license %{_licensedir}/admiral-flagship/LICENSE
%{_unitdir}/admiral-flagship.service
%attr(0600, root, root) %config(noreplace) %{_sysconfdir}/admiral/flagship.env

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
* Mon Oct 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 5:0.0.1rc6-6
- Rebuild coordinated RC6 candidate after spoke WireGuard PSK preservation fix

* Mon Oct 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 5:0.0.1rc6-5
- Rebuild coordinated Admiral candidate with Fedora dev-mode Caddy SELinux fix

* Mon Oct 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 5:0.0.1rc6-4
- Rebuild coordinated x86_64 candidate after Worker-to-Portal peer reconciliation fix

* Mon Oct 26 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 5:0.0.1rc6-3
- Rebuild coordinated Admiral candidate with automatic spoke peer reconciliation

* Sun Oct 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 5:0.0.1rc6-1
- Prepare coordinated RC6 Release 1 validation candidate using RPM Epoch

* Sun Oct 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc6-2
- Rebuild coordinated RC6 Release 2 with stale worker startup reconciliation

* Sun Oct 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc6-5
- Rebuild coordinated RC6 Release 5 with direct Worker-to-Portal WireGuard restore path

* Sun Oct 25 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc6-4
- Rebuild coordinated RC6 Release 4 with Harbor mutation redirect fix

* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-75
- Rebuild coordinated RPM set with node-removal history fix

* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-74
- Prepare coordinated Release 74 validation package set

* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-73
- Rebuild coordinated RC5 Release 73 package set

* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-70
- Rebuild coordinated Rocky Linux 10 x86_64 functional candidate

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-66
- Rebuild coordinated RC5 packages with retryable node authentication database errors

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-65
- Rebuild coordinated RC5 packages with Fedora-compatible dependency capabilities

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-63
- Rebuild coordinated RC5 packages for stale-health reboot recovery fix

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-62
- Rebuild coordinated RC5 packages with rootless manager state monitoring

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-61
- Revalidate after Fleet health invalidation fix for rootless manager restarts

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-60
- Rebuild coordinated RC5 packages for bounded declared-service health detection

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-59
- Rebuild the coordinated package set for rootless manager health recovery

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-58
- Pin the Flask build and runtime dependency to the validated package version

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-57
- Rebuild the coordinated RC5 package set with validation-seed update mode
- Pin the common installer and Ansible payload to the tested root commit

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-55
- Rebuild coordinated RC5 packages with the concurrent provisioning idempotency fix

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-53
- Rebuild coordinated Admiral RC5 package set with the resize secret fix

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-52
- Rebuild coordinated Admiral RC5 package set with the lifecycle availability correction

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-51
- Rebuild coordinated Release 51 with common RPM payload checks

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-50
- Rebuild coordinated six-package candidate with current main source refs

* Wed Oct 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-45
- Rebuild with safe Harbor links and idempotent Fleet cleanup

* Wed Oct 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-44
- Rebuild the coordinated candidate with idempotent missing-unit cleanup

* Wed Oct 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-43
- Preserve provisioning idempotency keys across client retries

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-42
- Rebuild coordinated RC5 Release 42 candidate after R41 validation rejection

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-40
- Rebuild the coordinated six-package set with restore staging permission fix

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-39
- Rebuild coordinated Admiral packages with package-owned data roots

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-38
- Rebuild coordinated Admiral RPM set after packaging permission correction

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-37
- Centralize Admiral setup directory ownership in admiral-common

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-36
- Rebuild coordinated RC5 candidate with RPM-owned runtime directories

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-32
- Rebuild the coordinated RC5 candidate with refreshed source pins

* Sun Oct 04 2026 Codex <codex@openai.com> - 0.0.1rc5-31
- Rebuild all six RC5 RPMs using the latest origin/main source pins

* Sun Oct 04 2026 Codex <codex@openai.com> - 0.0.1rc5-30
- Rebuild coordinated RC5 RPMs with Harbor packaging permission fix

* Sun Oct 04 2026 Codex <codex@openai.com> - 0.0.1rc5-29
- Rebuild coordinated RC5 RPMs with Harbor cancellation-state fix

* Sun Oct 04 2026 Codex <codex@openai.com> - 0.0.1rc5-28
- Fix admin-portal Harbor reachability over WireGuard in star mode

* Sat Oct 03 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-25
- Rebuild coordinated RC5 RPMs with Fleet rootless restore CA handoff fix

* Sat Oct 03 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-23
- Rebuild coordinated RC5 RPMs with Fleet Harbor restore trust fix

* Fri Oct 02 2026 Codex <codex@openai.com> - 0.0.1rc5-18
- Rebuild the coordinated RC5 set with Fleet version telemetry fix

* Fri Oct 02 2026 Codex <codex@openai.com> - 0.0.1rc5-17
- Add the worker WireGuard peer to the hub before the Fleet readiness gate

* Fri Oct 02 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-15
- Rebuild coordinated RC5 set after fixing Fleet token status selection

* Fri Oct 02 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-14
- Rebuild coordinated RC5 set after Fleet heartbeat readiness fix

* Fri Oct 02 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-13
- Rebuild coordinated RC5 package set

* Fri Oct 02 2026 Codex <codex@openai.com> - 0.0.1rc5-9
- Rebuild all six RC5 RPMs after adding bounded database readiness before backups

* Thu Oct 01 2026 Codex <codex@openai.com> - 0.0.1rc5-8
- Rebuild the coordinated RC5 RPM set with clean-install fixes

* Thu Oct 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-7
- Rebuild the coordinated RC5 RPM set after correcting architecture checks

* Thu Oct 01 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc5-6
- Rebuild the coordinated RC5 RPM set after a cross-architecture packaging fix

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
- Require single-use email verification for login on untrusted browsers

* Mon Sep 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc2-3
- Rebuild RC2 set with rootless pasta workload isolation

* Mon Sep 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc2-2
- Rebuild RC2 set with the spoke peer exchange token fix

* Mon Sep 21 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc2-1
- Release 0.0.1rc2

* Fri Aug 07 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.0.1rc1-84
- Rebuild RC1 with resilient spoke SSH post-revocation validation

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
