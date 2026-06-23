# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:    python3-flask-sqlalchemy
Version: 3.1.1
Release: 4%{?dist}
Summary: Add SQLAlchemy support to a Flask application

License: BSD-3-Clause
URL:     https://github.com/pallets-eco/flask-sqlalchemy/
Source0: https://files.pythonhosted.org/packages/source/f/flask-sqlalchemy/Flask-SQLAlchemy-%{version}.tar.gz

BuildArch: noarch

BuildRequires: gcc
BuildRequires: python3-devel
BuildRequires: python3-pip
BuildRequires: python3-flit-core

Requires: python3-flask
Requires: python3-sqlalchemy

%description
Flask-SQLAlchemy adds SQLAlchemy support to Flask applications and
provides useful defaults and helpers for common database tasks.

%prep
%autosetup -n Flask-SQLAlchemy-%{version}

%build
# pure Python; no compilation needed

%install
python3 -m pip install --root=%{buildroot} --no-deps --no-cache-dir --no-build-isolation .

%files
%license %{python3_sitelib}/flask_sqlalchemy-3.1.1.dist-info/LICENSE.rst
%exclude %{python3_sitelib}/flask_sqlalchemy-3.1.1.dist-info/LICENSE.rst
%{python3_sitelib}/flask_sqlalchemy/
%{python3_sitelib}/flask_sqlalchemy-3.1.1.dist-info/

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-3
- Rebuild for admiral 0.0.1alpha7
* Sun Jun 07 2026 Admiral Project <dev@admiral-project.org> - 3.1.1-1
- Initial packaging for Admiral
