# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:    python3-flask-alembic
Version: 3.1.1
Release: 4%{?dist}
Summary: Integrate Alembic with Flask

License: MIT
URL:     https://github.com/pallets-eco/flask-alembic/
Source0: https://files.pythonhosted.org/packages/source/f/flask-alembic/Flask-Alembic-%{version}.tar.gz

BuildArch: noarch

BuildRequires: gcc
BuildRequires: python3-devel
BuildRequires: python3-pip
BuildRequires: python3-flit-core

Requires: python3-alembic >= 1.13
Requires: python3-flask >= 3.0
Requires: python3-sqlalchemy >= 2.0

%description
Flask-Alembic provides a configurable Alembic migration environment
for Flask applications, with direct support for Flask-SQLAlchemy and
plain SQLAlchemy applications.

%prep
%autosetup -n Flask-Alembic-%{version}

%build
# pure Python; no compilation needed

%install
python3 -m pip install --root=%{buildroot} --no-deps --no-cache-dir --no-build-isolation .

%files
%license %{python3_sitelib}/flask_alembic-3.1.1.dist-info/LICENSE.txt
%exclude %{python3_sitelib}/flask_alembic-3.1.1.dist-info/LICENSE.txt
%{python3_sitelib}/flask_alembic/
%{python3_sitelib}/flask_alembic-3.1.1.dist-info/

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-3
- Rebuild for admiral 0.0.1alpha7
* Sun Jun 07 2026 Admiral Project <dev@admiral-project.org> - 3.1.1-1
- Initial packaging for Admiral
