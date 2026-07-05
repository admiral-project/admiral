# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:           python3-typing-extensions
Version:        4.15.0
Release:        7%{?dist}
Summary:        Backported and Experimental Type Hints for Python

License:        PSF-2.0
URL:            https://github.com/python/typing_extensions
Source0:        https://github.com/python/typing_extensions/archive/refs/tags/%{version}/typing_extensions-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  python3-flit-core
BuildRequires:  pyproject-rpm-macros

%description
The typing_extensions module provides backported and experimental type hints
for Python. It is used by the alembic database migration tool.

%prep
%autosetup -n typing_extensions-%{version}
# flit_core 3.7.1 on AL2023 needs dict format for license field
sed -i 's/^license = "PSF-2.0"$/license = {text = "PSF-2.0"}/' pyproject.toml
sed -i '/^license-files/d' pyproject.toml

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files typing_extensions

%files -f %{pyproject_files}
%license LICENSE

%changelog
* Sun Jul 05 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-7
- Rebuild for admiral 0.0.1beta14

* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-6
- Add explicit BuildRequires: python3-flit-core for EL10 compatibility
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-5
- Migrate to pyproject-rpm-macros and switch to GitHub source archive
* Tue Jun 23 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-4
- Migrate from wheel to source build for architecture-agnostic packaging
* Tue Jun 16 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 4.15.0-3
- Rebuild for admiral 0.0.1alpha7
* Fri Jun 12 2026 Admiral Project <dev@admiral-project.org> - 4.15.0-1
- Initial packaging for Admiral
