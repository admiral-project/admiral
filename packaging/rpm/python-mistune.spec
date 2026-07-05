# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:           python3-mistune
Version:        3.2.1
Release:        7%{?dist}
Summary:        A sane Markdown parser with useful plugins and rules

License:        BSD-3-Clause
URL:            https://github.com/lepture/mistune
Source0:        https://github.com/lepture/mistune/archive/refs/tags/v%{version}/mistune-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  python3-setuptools
BuildRequires:  python3-wheel
BuildRequires:  pyproject-rpm-macros

%description
A sane Markdown parser with useful plugins and rules in pure Python.

%prep
%autosetup -n mistune-%{version}
cat > setup.cfg <<CFG
[metadata]
name = mistune
version = %{version}
license = BSD-3-Clause

[options]
packages = find:
package_dir =
    = src

[options.packages.find]
where = src
CFG

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files mistune

%files -f %{pyproject_files}
%license LICENSE

%changelog
* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.2.1-7
- Rebuild for admiral 0.0.1beta14

* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.2.1-6
- Add explicit BuildRequires: python3-setuptools for EL10 compatibility
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.2.1-5
- Migrate to pyproject-rpm-macros for PEP 517 compliant build
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.2.1-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 Admiral Project <dev@admiral-project.org> - 3.2.1-3
- Rebuild for admiral 0.0.1alpha7
* Tue Jun 16 2026 Admiral Project <dev@admiral-project.org> - 3.2.1-1
- Initial packaging of mistune for Admiral
