# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:    python3-flask-login
Version: 0.6.3
Release: 4%{?dist}
Summary: User session management for Flask

License: MIT
URL:     https://github.com/maxcountryman/flask-login
Source0: https://files.pythonhosted.org/packages/source/f/flask-login/Flask-Login-%{version}.tar.gz

BuildArch: noarch

BuildRequires: gcc
BuildRequires: python3-devel
BuildRequires: python3-pip
BuildRequires: python3-flit-core

Requires: python3-flask

%description
Flask-Login provides user session management for Flask. It handles the
common tasks of logging in, logging out, and remembering user sessions.

%prep
%autosetup -n Flask-Login-%{version}

%build
# pure Python; no compilation needed

%install
python3 -m pip install --root=%{buildroot} --no-deps --no-cache-dir --no-build-isolation .

%files
%license %{python3_sitelib}/Flask_Login-%{version}.dist-info/LICENSE
%exclude %{python3_sitelib}/Flask_Login-%{version}.dist-info/LICENSE
%{python3_sitelib}/flask_login/
%{python3_sitelib}/Flask_Login-%{version}.dist-info/

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 0.6.3-3
- Rebuild for admiral 0.0.1alpha7
* Tue Jun 09 2026 Admiral Project <dev@admiral-project.org> - 0.6.3-1
- Initial packaging for Admiral
