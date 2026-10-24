# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global __brp_python_bytecompile %{nil}

Name:           python3-sqlalchemy
Version:        2.0.55
Release:        5%{?dist}
Summary:        Database toolkit and Object Relational Mapper for Python

License:        MIT
URL:            https://www.sqlalchemy.org/
Source0:        https://files.pythonhosted.org/packages/a5/bd/08864ddfffbb8914ee13b0c887d84b4b13bc8dd8da3077c0dace5a87699c/sqlalchemy-%{version}.tar.gz

BuildRequires:  python3-devel
BuildRequires:  python3-cython >= 0.29.24
BuildRequires:  python3dist(typing-extensions) = 4.16
BuildRequires:  gcc
BuildRequires:  python3-pip
BuildRequires:  python3-setuptools
BuildRequires:  python3-wheel
BuildRequires:  pyproject-rpm-macros

Provides:       python%{python3_version}dist(sqlalchemy) = %{version}
Provides:       python3dist(sqlalchemy) = %{version}
Requires:       python3
Requires:       python3-greenlet >= 1
Requires:       python3dist(typing-extensions) = 4.16

%description
SQLAlchemy is the Python SQL toolkit and Object Relational Mapper that gives
application developers the full power and flexibility of SQL.

This RPM builds SQLAlchemy's optional Cython extensions for native execution
on supported x86_64 Fedora and Enterprise Linux targets.

%prep
%autosetup -n sqlalchemy-%{version}

%build
# EL10 x86_64 COPR builds target x86_64_v2. Preserve that baseline when the
# local builder inherits a newer x86_64_v3 profile.
export RPM_OPT_FLAGS="$(printf '%s\n' "$RPM_OPT_FLAGS" | sed 's/-march=x86-64-v3/-march=x86-64-v2/')"
export CFLAGS="$RPM_OPT_FLAGS"
REQUIRE_SQLALCHEMY_CEXT=1 %pyproject_wheel

%install
%pyproject_install
mkdir -p %{buildroot}%{python3_sitelib} %{buildroot}%{python3_sitearch}
find %{buildroot}%{python3_sitelib} %{buildroot}%{python3_sitearch} \
    -type f \( -path '*/sqlalchemy/*' \
        -o -path '*/sqlalchemy-%{version}.dist-info/*' \
        -o -path '*/SQLAlchemy-%{version}.dist-info/*' \) \
    -print | sed 's|%{buildroot}||' | sort > sqlalchemy.files
test -s sqlalchemy.files

%check
PYTHONPATH=%{buildroot}%{python3_sitearch}:%{buildroot}%{python3_sitelib} %{python3} -c \
    'import sqlalchemy; import sqlalchemy.cyextension.util as util; assert sqlalchemy.__version__ == "%{version}"; assert util.__file__.endswith(".so")'

%files -f sqlalchemy.files
%license LICENSE

%changelog
* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 2.0.55-5
- Pin build and runtime typing-extensions to version 4.16
- Install the pinned module in buildroots before the SQLAlchemy import check

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 2.0.55-4
- Require compatible typing-extensions module versions without RPM release pins

* Fri Oct 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 2.0.55-3
- Include normalized lowercase dist-info payloads produced by Fedora Python 3.15

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 2.0.55-2
- Package SQLAlchemy 2.0.55 for Flask-Alembic compatibility on EL10
- Build the optional Cython extensions on the supported EL10 x86_64 target
- Declare SQLAlchemy's runtime dependencies and Python distribution provides
- Pin the runtime typing-extensions package version
