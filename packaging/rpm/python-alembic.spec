# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global srcname alembic

Name:    python3-alembic
Version: 1.18.4
Release: 2%{?dist}
Summary: A database migration tool for SQLAlchemy

License: MIT
URL:     https://alembic.sqlalchemy.org/
Source0: %{srcname}-%{version}-py3-none-any.whl

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-rpm-macros

Requires: python3-sqlalchemy >= 1.4.23
Requires: python3-mako
Requires: python3-typing-extensions >= 4.12

%description
Alembic is a lightweight database migration tool for SQLAlchemy that
makes it simple to create and manage database schema versions.

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
%license %{python3_sitelib}/alembic-1.18.4.dist-info/licenses/LICENSE
%exclude %{python3_sitelib}/alembic-1.18.4.dist-info/licenses/LICENSE
%{python3_sitelib}/alembic/
%{python3_sitelib}/alembic-1.18.4.dist-info/

%changelog
* Tue Jun 09 2026 Admiral Project <dev@admiral-project.org> - 1.18.4-1
- Updated for compatibility with flask-alembic 3.1.1+
