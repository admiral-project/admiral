# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global tag_version %(echo %{version} | tr '.' '_')

Name:           python3-alembic
Version:        1.18.4
Release:        5%{?dist}
Summary:        A database migration tool for SQLAlchemy

License:        MIT
URL:            https://alembic.sqlalchemy.org/
Source0:        https://github.com/sqlalchemy/alembic/archive/refs/tags/rel_%{tag_version}/alembic-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  pyproject-rpm-macros

Requires:       python3-sqlalchemy >= 1.4.23
Requires:       python3-mako
Requires:       python3-typing-extensions >= 4.12

%description
Alembic is a lightweight database migration tool for SQLAlchemy that
makes it simple to create and manage database schema versions.

%prep
%autosetup -n alembic-rel_%{tag_version}
cat > setup.cfg <<CFG
[metadata]
name = alembic
version = %{version}
license = MIT

[options]
packages =
    alembic
CFG

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files alembic

%files -f %{pyproject_files}
%license LICENSE

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 1.18.4-5
- Migrate to pyproject-rpm-macros and fix source directory name
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 1.18.4-4
- Migrate from wheel to source build, use GitHub archive for source
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 1.18.4-3
- Rebuild for admiral 0.0.1alpha7
* Tue Jun 09 2026 Admiral Project <dev@admiral-project.org> - 1.18.4-1
- Updated for compatibility with flask-alembic 3.1.1+
