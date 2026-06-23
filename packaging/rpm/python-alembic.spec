# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:    python3-alembic
Version: 1.18.4
Release: 4%{?dist}
Summary: A database migration tool for SQLAlchemy

License: MIT
URL:     https://alembic.sqlalchemy.org/
Source0: https://files.pythonhosted.org/packages/source/a/alembic/alembic-%{version}.tar.gz

BuildArch: noarch

BuildRequires: gcc
BuildRequires: python3-devel
BuildRequires: python3-pip

Requires: python3-sqlalchemy >= 1.4.23
Requires: python3-mako
Requires: python3-typing-extensions >= 4.12

%description
Alembic is a lightweight database migration tool for SQLAlchemy that
makes it simple to create and manage database schema versions.

%prep
%autosetup -n alembic-%{version}

%build
# pure Python; no compilation needed

%install
python3 -m pip install --root=%{buildroot} --no-deps --no-cache-dir --no-build-isolation .

%files
%license %{python3_sitelib}/alembic-%{version}.dist-info/licenses/LICENSE
%exclude %{python3_sitelib}/alembic-%{version}.dist-info/licenses/LICENSE
%{python3_sitelib}/alembic/
%{python3_sitelib}/alembic-%{version}.dist-info/

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 1.18.4-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 1.18.4-3
- Rebuild for admiral 0.0.1alpha7
* Tue Jun 09 2026 Admiral Project <dev@admiral-project.org> - 1.18.4-1
- Updated for compatibility with flask-alembic 3.1.1+
