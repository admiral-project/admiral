# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:           python3-flask-alembic
Version:        3.3.0
Release:        5%{?dist}
Summary:        Integrate Alembic with Flask

License:        MIT
URL:            https://github.com/pallets-eco/flask-alembic/
Source0:        https://github.com/pallets-eco/flask-alembic/archive/refs/tags/%{version}/flask-alembic-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  python3-flit-core
BuildRequires:  pyproject-rpm-macros

Requires:       python3dist(alembic) >= 1.16
Requires:       python3dist(flask) = 3.1.3
Requires:       python3dist(sqlalchemy) >= 2.0.31

%description
Flask-Alembic provides a configurable Alembic migration environment
for Flask applications, with direct support for Flask-SQLAlchemy and
plain SQLAlchemy applications.

%prep
%autosetup -n flask-alembic-%{version}
# Keep the PEP 621 license metadata compatible with EL10's flit-core.
sed -i 's/^license = "MIT"$/license = {text = "MIT"}/' pyproject.toml
sed -i '/^license-files/d' pyproject.toml

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files flask_alembic

%files -f %{pyproject_files}
%license LICENSE.txt

%changelog
* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.3.0-5
- Rebuild with the coordinated pinned Python dependency set

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.3.0-4
- Express runtime requirements as Python module capabilities, independent of RPM release

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.3.0-3
- Require the coordinated Alembic and corrected SQLAlchemy package builds

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.3.0-2
- Update Flask-Alembic to the latest upstream release
- Pin Alembic, Flask, and SQLAlchemy runtime versions

* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-7
- Rebuild for admiral 0.0.1beta14

* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-6
- Add explicit BuildRequires: python3-flit-core for EL10 compatibility
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-5
- Migrate to pyproject-rpm-macros and switch to GitHub source archive
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.1-3
- Rebuild for admiral 0.0.1alpha7
* Sun Jun 07 2026 Admiral Project <dev@admiral-project.org> - 3.1.1-1
- Initial packaging for Admiral
