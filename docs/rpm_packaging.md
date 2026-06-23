# RPM Packaging Guide for Admiral Python Dependencies

This document records the patterns and platform-specific workarounds
required to build Python library RPMs for Admiral across three target
distributions simultaneously:

- Amazon Linux 2023 (Python 3.9, setuptools 59.6.0)
- CentOS Stream 10 / RHEL 10 (Python 3.12, setuptools 69.0.3)
- Fedora Rawhide (current development)

## Build System

All Python packages use `pyproject-rpm-macros` with PEP 517 builds.
The `%pyproject_wheel` macro calls `pip wheel --no-build-isolation`,
which means build backends must be installed system-wide.

### Common BuildRequires

Every Python package must include:

```
BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  pyproject-rpm-macros
```

Additionally, one of:

```
BuildRequires:  python3-setuptools   # for setuptools-based packages
BuildRequires:  python3-flit-core    # for flit_core-based packages
```

And in all cases:

```
BuildRequires:  python3-wheel
```

`python3-wheel` is needed because `bdist_wheel` (the `wheel` package)
is not always pulled transitively. It is available on all three targets.

## Platform Detection Macros

AL2023 defines `%fedora 34` for RPM compatibility, which makes naive
`%if 0%{?fedora}` checks unreliable. Always use:

```
%if (0%{?rhel} >= 10 || 0%{?fedora}) && !0%{?amzn}
```

To exclude AL2023, check `!0%{?amzn}`.

| Macro  | AL2023  | EL10   | Fedora |
|--------|---------|--------|--------|
| %rhel  | undef   | 10     | undef  |
| %fedora| 34      | undef  | 45     |
| %amzn  | 2023    | undef  | undef  |

## setup.cfg Overrides for PEP 621

AL2023 ships setuptools 59.6.0, which does not support the PEP 621
`[project]` table in `pyproject.toml`. To make a package build there,
create a `setup.cfg` in `%prep` that duplicates the metadata fields
from `pyproject.toml`.

Example from `python-mistune.spec`:

```
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
```

These overrides are harmless on newer setuptools (69+): they take
precedence over `pyproject.toml` but produce the same result.

### License Field

EL10's setuptools 69.0.3 validates PEP 621 strictly. A plain string
`license = "MIT"` in `pyproject.toml` is rejected (must be inline
table `{text = "..."}` or `{file = "..."}`). Use `sed` to patch it:

```
sed -i 's/^license = "MIT"/license = {text = "MIT"}/' pyproject.toml
```

When using a `setup.cfg` override, the `license` string there is
fine — the conflict only arises if *both* files define it. Patching
`pyproject.toml` to the correct format and keeping `license` in
`setup.cfg` works on all three targets.

### license-files (PEP 639)

The `license-files` key in `pyproject.toml` (PEP 639) is not fully
supported by all setuptools versions. Remove it with `sed`:

```
sed -i '/^license-files/d' pyproject.toml
```

License files are shipped via `%license LICENSE` in `%files` instead.

## Entry Points and bindir

`pyproject-rpm-macros` 1.16.1 (AL2023) does **not** install entry
point scripts into `%{_bindir}`. Versions 1.18+ (EL10, Fedora) do.
If a package provides a CLI entry point (e.g. alembic), the bindir
entry must be conditional:

```
%files -f %{pyproject_files}
%license LICENSE
%if (0%{?rhel} >= 10 || 0%{?fedora}) && !0%{?amzn}
%{_bindir}/alembic
%endif
```

## Source Archives

Use GitHub archive URLs instead of PyPI sdists for deterministic
fetching and to avoid PyPI sdist breakage.

Format:
```
Source0: https://github.com/<owner>/<repo>/archive/refs/tags/<tag>/<archive>.tar.gz
```

The archive directory name is `<repo>-<tag>` (tag without a leading `v`
if present). Use `%autosetup -n <repo>-<tag>` to match.

For tags without a `v` prefix (e.g. `rel_1_18_4`), pass through
literally.

## EL10: CRB Repository

CentOS Stream 10 / RHEL 10 requires the CRB repository enabled for
`pyproject-rpm-macros`:

```
dnf config-manager --set-enabled crb
```

## Summary of Patterns

| Concern | Solution |
|---------|----------|
| PEP 621 on old setuptools | setup.cfg override |
| license plain string invalid | sed to inline table |
| license-files rejected | sed remove, ship via %license |
| entry points not in bindir | conditional %{_bindir} |
| build backend isolation | explicit BR for setuptools/flit-core |
| wheel availability | unconditional BuildRequires: python3-wheel |
| pip availability | unconditional BuildRequires: python3-pip |
| EL10 CRB repo | document for deployer |
| AL2023 %fedora false positive | guard with !0%{?amzn} |
| GitHub archive dirname | %autosetup -n <repo>-<tag> |
