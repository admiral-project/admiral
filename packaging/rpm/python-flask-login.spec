# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global srcname flask_login

Name:    python3-flask-login
Version: 0.6.3
Release: 2%{?dist}
Summary: User session management for Flask

License: MIT
URL:     https://github.com/maxcountryman/flask-login
Source0: Flask_Login-%{version}-py3-none-any.whl

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-rpm-macros

Requires: python3-flask

%description
Flask-Login provides user session management for Flask. It handles the
common tasks of logging in, logging out, and remembering user sessions.

%prep

%build

%install
mkdir -p %{buildroot}%{python3_sitelib}
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile

wheel = Path("%{SOURCE0}")
target = Path("%{buildroot}%{python3_sitelib}")
with ZipFile(wheel) as zf:
    zf.extractall(target)
PY

%files
%license %{python3_sitelib}/Flask_Login-%{version}.dist-info/LICENSE
%{python3_sitelib}/flask_login/
%exclude %{python3_sitelib}/Flask_Login-%{version}.dist-info/LICENSE
%{python3_sitelib}/Flask_Login-%{version}.dist-info/

%changelog
* Tue Jun 09 2026 Admiral Project <dev@admiral-project.org> - 0.6.3-1
- Initial packaging for Admiral
