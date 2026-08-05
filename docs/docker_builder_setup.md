# Docker/Podman builder setup for EL10 RPMs

This document captures a verified workflow to build the six Admiral RPMs inside an EL10 container and keep the resulting artifacts under the repository's packaging build tree.

## What this builds

The build target produces these RPMs:

- admiral-common
- admirald
- admiral-fleet
- admiralctl
- admiral-flagship
- admiral-harbor

It also produces the matching source RPMs (SRPMs).

## Verified build command

Run the following from the repository root:

```bash
docker run --rm \
  -v "$PWD":/workspace/admiral \
  -w /workspace/admiral \
  quay.io/centos/centos:stream10 bash -lc '
    set -e
    dnf update -y
    dnf install -y git dnf-plugins-core epel-release
    git config --global --add safe.directory "*"
    dnf config-manager --set-enabled crb
    dnf copr enable -y @caddy/caddy
    dnf copr enable -y admiral-project/admiral
    dnf install -y make gcc rpm-build rpmdevtools redhat-rpm-config \
      systemd-devel pkgconfig which file wget curl ca-certificates \
      golang python3 python3-devel python3-pip python3-wheel \
      python3-setuptools python3-requests python3-flask python3-werkzeug \
      python3-gunicorn python3-pytest python3-flask-sqlalchemy \
      python3-flask-alembic python3-flask-login python3-mistune \
      python3-psycopg2 python3-yaml python3-cryptography \
      python3-argon2-cffi caddy certbot podman postgresql-server shadow-utils
    rpmdev-setuptree
    make rpm-admiral
  '
```

## Notes

- The build enables the required COPR repositories:
  - @caddy/caddy
  - admiral-project/admiral
- The container must have Git installed before the release-reference validator runs.
- The build uses the repository's Makefile target `make rpm-admiral`.

## Output location

The generated artifacts are written under the repository's packaging build directory:

- Binary RPMs: packaging/build/RPMS/
- Source RPMs: packaging/build/SRPMS/

Examples:

```bash
packaging/build/RPMS/noarch/
packaging/build/RPMS/x86_64/
packaging/build/SRPMS/
```

After a successful build, you should see files such as:

```bash
packaging/build/RPMS/noarch/admiral-common-*.rpm
packaging/build/RPMS/x86_64/admirald-*.rpm
packaging/build/SRPMS/admiral-common-*.src.rpm
```

## Verification

You can verify the produced artifacts with:

```bash
find packaging/build -maxdepth 3 \( -name '*.rpm' -o -name '*.src.rpm' \) | sort
```
