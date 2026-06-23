# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:    python3-mistune
Version: 3.2.1
Release: 4%{?dist}
Summary: A sane Markdown parser with useful plugins and rules

License: BSD-3-Clause
URL:     https://github.com/lepture/mistune
Source0: https://files.pythonhosted.org/packages/source/m/mistune/mistune-%{version}.tar.gz

BuildArch: noarch

BuildRequires: gcc
BuildRequires: python3-devel
BuildRequires: python3-pip

Requires: python3
Provides: python3dist(mistune) = %{version}

%description
A sane Markdown parser with useful plugins and rules in pure Python.

%prep
%autosetup -n mistune-%{version}

%build
# pure Python; no compilation needed

%install
python3 -m pip install --root=%{buildroot} --no-deps --no-cache-dir --no-build-isolation .

%files
%license %{python3_sitelib}/mistune-%{version}.dist-info/licenses/LICENSE
%exclude %{python3_sitelib}/mistune-%{version}.dist-info/licenses/LICENSE
%{python3_sitelib}/mistune/
%{python3_sitelib}/mistune-%{version}.dist-info/

%changelog
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.2.1-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 Admiral Project <dev@admiral-project.org> - 3.2.1-3
- Rebuild for admiral 0.0.1alpha7
* Tue Jun 16 2026 Admiral Project <dev@admiral-project.org> - 3.2.1-1
- Initial packaging of mistune for Admiral
