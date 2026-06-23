# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:    python3-typing-extensions
Version: 4.15.0
Release: 4%{?dist}
Summary: Backported and Experimental Type Hints for Python

License: PSF-2.0
URL:     https://github.com/python/typing_extensions
Source0: https://files.pythonhosted.org/packages/source/t/typing-extensions/typing-extensions-%{version}.tar.gz

BuildArch: noarch

BuildRequires: gcc
BuildRequires: python3-devel
BuildRequires: python3-pip

Requires: python3
Provides: python3dist(typing-extensions) = %{version}

%description
The typing_extensions module provides backported and experimental type hints
for Python. It is used by the alembic database migration tool.

%prep
%autosetup -n typing-extensions-%{version}

%build
# pure Python; no compilation needed

%install
python3 -m pip install --root=%{buildroot} --no-deps --no-cache-dir --no-build-isolation .

%files
%license %{python3_sitelib}/typing_extensions-%{version}.dist-info/licenses/LICENSE
%exclude %{python3_sitelib}/typing_extensions-%{version}.dist-info/licenses/LICENSE
%{python3_sitelib}/typing_extensions.py
%{python3_sitelib}/__pycache__/typing_extensions.cpython-3*
%{python3_sitelib}/typing_extensions-%{version}.dist-info/

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-3
- Rebuild for admiral 0.0.1alpha7
* Fri Jun 12 2026 Admiral Project <dev@admiral-project.org> - 4.15.0-1
- Initial packaging for Admiral
