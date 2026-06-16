# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global srcname typing_extensions

Name:    python3-typing-extensions
Version: 4.15.0
Release: 3%{?dist}
Summary: Backported and Experimental Type Hints for Python

License: PSF-2.0
URL:     https://github.com/python/typing_extensions
Source0: %{srcname}-%{version}-py3-none-any.whl

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-rpm-macros

Requires: python3
Provides: python3.12dist(typing-extensions) = %{version}
Provides: python3dist(typing-extensions) = %{version}

%description
The typing_extensions module provides backported and experimental type hints
for Python. It is used by the alembic database migration tool.

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
%license %{python3_sitelib}/typing_extensions-4.15.0.dist-info/licenses/LICENSE
%exclude %{python3_sitelib}/typing_extensions-4.15.0.dist-info/licenses/LICENSE
%{python3_sitelib}/typing_extensions.py
%{python3_sitelib}/__pycache__/typing_extensions.cpython-312*
%{python3_sitelib}/typing_extensions-4.15.0.dist-info/

%changelog
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-3
- Rebuild for admiral 0.0.1alpha7

* Fri Jun 12 2026 Admiral Project <dev@admiral-project.org> - 4.15.0-1
- Initial packaging for Admiral
