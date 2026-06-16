# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global srcname mistune

Name:    python3-mistune
Version: 3.2.1
Release: 3%{?dist}
Summary: A sane Markdown parser with useful plugins and rules

License: BSD-3-Clause
URL:     https://github.com/lepture/mistune
Source0: %{srcname}-%{version}-py3-none-any.whl

BuildArch: noarch

BuildRequires: python3
BuildRequires: python3-rpm-macros

Requires: python3
Provides: python3dist(mistune) = %{version}
Provides: python3.12dist(mistune) = %{version}

%description
A sane Markdown parser with useful plugins and rules in pure Python.

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
%license %{python3_sitelib}/mistune-%{version}.dist-info/licenses/LICENSE
%exclude %{python3_sitelib}/mistune-%{version}.dist-info/licenses/LICENSE
%{python3_sitelib}/mistune/
%{python3_sitelib}/mistune-%{version}.dist-info/

%changelog
* Tue Jun 16 2026 Admiral Project <dev@admiral-project.org> - 3.2.1-3
- Rebuild for admiral 0.0.1alpha7

* Tue Jun 16 2026 Admiral Project <dev@admiral-project.org> - 3.2.1-1
- Initial packaging of mistune for Admiral
