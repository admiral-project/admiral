# SPDX-FileCopyrightText: William Moreno Reyes <williamjmorenor@gmail.com>
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}
%global __brp_python_bytecompile %{nil}

Name:           python3-flask
Epoch:          1
Version:        3.1.3
Release:        4%{?dist}
Summary:        A lightweight WSGI web application framework

License:        BSD-3-Clause
URL:            https://github.com/pallets/flask
Source0:        https://files.pythonhosted.org/packages/7f/9c/34f6962f9b9e9c71f6e5ed806e0d0ff03c9d1b0b2340088a0cf4bce09b18/flask-3.1.3-py3-none-any.whl

BuildArch:      noarch

BuildRequires:  python3-rpm-macros
BuildRequires:  python3
BuildRequires:  unzip

Provides:       python%{python3_version}-flask = 1:%{version}-%{release}
Provides:       python-flask = 1:%{version}-%{release}
Provides:       python%{python3_version}dist(flask) = %{version}
Provides:       python3dist(flask) = %{version}
Requires:       python3
Requires:       python3-blinker >= 1.9
Requires:       python3-click >= 8.1.3
Requires:       python3-itsdangerous >= 2.2
Requires:       python3-jinja2 >= 3.1.2
Requires:       python3-markupsafe >= 2.1.1
Requires:       python3-werkzeug >= 3.1.0

%description
Flask is a lightweight WSGI web application framework. This package uses the
upstream Flask 3.1.3 wheel to provide its security fix on EL10, where the
available EPEL package is older.

%prep
%setup -q -c -T

%build

%install
mkdir -p %{buildroot}%{python3_sitelib}
unzip -q %{SOURCE0} -d %{buildroot}%{python3_sitelib}
find %{buildroot}%{python3_sitelib}/flask \
    %{buildroot}%{python3_sitelib}/flask-3.1.3.dist-info \
    -type f ! -path '*/licenses/LICENSE.txt' \
    | sed 's|%{buildroot}||' | sort > flask.files

%files -f flask.files
%license %{python3_sitelib}/flask-3.1.3.dist-info/licenses/LICENSE.txt

%check
test -f %{buildroot}%{python3_sitelib}/flask/__init__.py
test -f %{buildroot}%{python3_sitelib}/flask-3.1.3.dist-info/METADATA

%changelog
* Sat Oct 24 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.3-4
- Rebuild with the coordinated pinned Python dependency set

* Thu Oct 22 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.3-3
- Install Python before expanding the Python site-packages macro
- Check that Flask is packaged under the interpreter's import path

* Tue Oct 20 2026 William Moreno Reyes <williamjmorenor@gmail.com> - 3.1.3-2
- Package upstream Flask 3.1.3 for EL10 security compatibility
