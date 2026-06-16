# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global srcname flask_sqlalchemy

Name:    python3-flask-sqlalchemy
Version: 3.1.1
Release: 3%{?dist}
Summary: Add SQLAlchemy support to a Flask application

License: BSD-3-Clause
URL:     https://github.com/pallets-eco/flask-sqlalchemy/
Source0: %{srcname}-%{version}-py3-none-any.whl

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-rpm-macros

Requires: python3-flask
Requires: python3-sqlalchemy

%description
Flask-SQLAlchemy adds SQLAlchemy support to Flask applications and
provides useful defaults and helpers for common database tasks.

%prep
# Nothing to unpack; the wheel is extracted directly into the buildroot.

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
%license %{python3_sitelib}/flask_sqlalchemy-3.1.1.dist-info/LICENSE.rst
%exclude %{python3_sitelib}/flask_sqlalchemy-3.1.1.dist-info/LICENSE.rst
%{python3_sitelib}/flask_sqlalchemy/
%{python3_sitelib}/flask_sqlalchemy-3.1.1.dist-info/

%changelog
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-3
- Rebuild for admiral 0.0.1alpha7

* Sun Jun 07 2026 Admiral Project <dev@admiral-project.org> - 3.1.1-1
- Initial packaging for Admiral
