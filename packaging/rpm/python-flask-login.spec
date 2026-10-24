# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:           python3-flask-login
Version:        0.6.3
Release:        10%{?dist}
Summary:        User session management for Flask

License:        MIT
URL:            https://github.com/maxcountryman/flask-login
Source0:        https://github.com/maxcountryman/flask-login/archive/refs/tags/%{version}/flask-login-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  python3-setuptools
BuildRequires:  python3-wheel
BuildRequires:  pyproject-rpm-macros

Requires:       python3dist(flask) = 3.1.3

%description
Flask-Login provides user session management for Flask. It handles the
common tasks of logging in, logging out, and remembering user sessions.

%prep
%autosetup -n flask-login-%{version}

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files flask_login

%files -f %{pyproject_files}
%license LICENSE

%changelog
* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-10
- Rebuild with the coordinated pinned Python dependency set

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-9
- Require the pinned Flask module version without pinning its RPM release

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-8
- Pin the Flask runtime version

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-7
- Rebuild for admiral 0.0.1beta14

* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-6
- Add explicit BuildRequires: python3-setuptools for EL10 compatibility
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-5
- Migrate to pyproject-rpm-macros and switch to GitHub source archive
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-3
- Rebuild for admiral 0.0.1alpha7
* Tue Jun 09 2026 Admiral Project <dev@admiral-project.org> - 0.6.3-1
- Initial packaging for Admiral
