# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:           python3-flask-sqlalchemy
Version:        3.1.1
Release:        5%{?dist}
Summary:        Add SQLAlchemy support to a Flask application

License:        BSD-3-Clause
URL:            https://github.com/pallets-eco/flask-sqlalchemy/
Source0:        https://github.com/pallets-eco/flask-sqlalchemy/archive/refs/tags/%{version}/flask-sqlalchemy-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  pyproject-rpm-macros

Requires:       python3-flask
Requires:       python3-sqlalchemy

%description
Flask-SQLAlchemy adds SQLAlchemy support to Flask applications and
provides useful defaults and helpers for common database tasks.

%prep
%autosetup -n flask-sqlalchemy-%{version}

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files flask_sqlalchemy

%files -f %{pyproject_files}
%license LICENSE.rst

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-5
- Migrate to pyproject-rpm-macros for PEP 517 compliant build
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-3
- Rebuild for admiral 0.0.1alpha7
* Sun Jun 07 2026 Admiral Project <dev@admiral-project.org> - 3.1.1-1
- Initial packaging for Admiral
