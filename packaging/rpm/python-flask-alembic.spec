# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global srcname flask_alembic

Name:    python3-flask-alembic
Version: 3.1.1
Release: 2%{?dist}
Summary: Integrate Alembic with Flask

License: MIT
URL:     https://github.com/pallets-eco/flask-alembic/
Source0: %{srcname}-%{version}-py3-none-any.whl

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-rpm-macros

Requires: python3-alembic >= 1.13
Requires: python3-flask >= 3.0
Requires: python3-sqlalchemy >= 2.0

%description
Flask-Alembic provides a configurable Alembic migration environment
for Flask applications, with direct support for Flask-SQLAlchemy and
plain SQLAlchemy applications.

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
%license %{python3_sitelib}/flask_alembic-3.1.1.dist-info/LICENSE.txt
%exclude %{python3_sitelib}/flask_alembic-3.1.1.dist-info/LICENSE.txt
%{python3_sitelib}/flask_alembic/
%{python3_sitelib}/flask_alembic-3.1.1.dist-info/

%changelog
* Sun Jun 07 2026 Admiral Project <dev@admiral-project.org> - 3.1.1-1
- Initial packaging for Admiral
