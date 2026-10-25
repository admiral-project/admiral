# Python RPM dependency refresh — 2026-10-24

## Candidate status

This refresh republished all eight Python helper source RPMs for the Admiral RC5 Release 73 dependency set. It fixes the SQLAlchemy source build requirement for `typing-extensions`; it does not itself constitute a COPR build or a runtime matrix run. The R75 Single-Node results remain historical candidate-specific evidence; its Multi-Node runs used the wrong admin/portal-plus-workers topology and do not validate the required independent portal. See [`RELEASE75_VALIDATION_CLOSURE.md`](../RELEASE75_VALIDATION_CLOSURE.md).

Issue [#274](https://github.com/admiral-project/admiral/issues/274) is closed: the COPR rebuild, which was its external confirmation gate, succeeded. Master tracker: [#277](https://github.com/admiral-project/admiral/issues/277).

## Published sources

The HTTP publication page contains six Admiral Release 73 sources and only these eight current Python SRPMs. Each listed Python artifact returned HTTP 200 and its bytes matched the published `SHA256SUMS` on 2026-10-24.

| SRPM / NEVRA | SHA-256 |
|---|---|
| `python3-alembic-1.20.1-5.el10.src.rpm` | `d7ca1e30b9f40658302f202a915aa401c15e97270176b8e5832a615a466d6ba7` |
| `python3-flask-3.1.3-4.el10.src.rpm` | `91dd0c2061c1d27d87f4babe29676f6da6b9cb0304dedcf5b07af3a674de8ffe` |
| `python3-flask-alembic-3.3.0-5.el10.src.rpm` | `e4fd92ed7e481ade663cdaabd9e437c0f7266d49f4b79e935ae2cb20f7e88b1a` |
| `python3-flask-login-0.6.3-10.el10.src.rpm` | `01c538548f495068ee17a4d0cb328660948c095728e09586d726ab02c5e959b6` |
| `python3-flask-sqlalchemy-3.1.1-11.el10.src.rpm` | `57135fe3baf57d3a20b64ad4a0214b99ed0bee66a5ae38d2f6cd3d7ad5196891` |
| `python3-mistune-3.4.0-2.el10.src.rpm` | `ad73b0d04d835f51a334efba3d4237acd16410589e7b265881b543aaed0be598` |
| `python3-sqlalchemy-2.0.55-5.el10.src.rpm` | `e3f31eeca13fb544d42564ddeb9110d006ed3ac584cde7e66b848f1529b80e3b` |
| `python3-typing-extensions-4.16.0-2.el10.src.rpm` | `75e383027668ca820ede890deadc2d48de3740e8694db2bf74d845ff1b67dac7` |

All eight Python library spec `Release` values were incremented. SQLAlchemy now declares `python3dist(typing-extensions) = 4.16` as both `BuildRequires` and runtime `Requires`; Alembic's runtime requirement uses the same exact capability pin. Fedora builds must use Fedora-native buildroots/RPMs; the published `.el10` SRPMs are sources, not EL10 binaries to install on Fedora.

## Build evidence

| Test ID | Type / environment | Procedure and observed result | Status |
|---|---|---|---|
| `PY-RPM-SQLA-EL10-01` | Native package build; Rocky Linux 10.2 x86_64 | Build `python3-sqlalchemy-2.0.55-5.el10`; `%check` imports SQLAlchemy and `sqlalchemy.cyextension.util`, asserts version 2.0.55 and a native `.so` extension. RPM SHA-256 `bf8735376c74f786b45cc0740172997ef9fecc0deef929a6b503aa59d9dac18f`; build log SHA-256 `5d77bb815638b3f6ccb7090012c6cefd0a7f6b4b7e44ba1854ff7bebe6d39c07`. | PASS — local build; not COPR |
| `PY-RPM-SQLA-FEDORA-01` | Native package build; fresh Fedora Rawhide container / Fedora 46 x86_64 | Rebuild the SRPM with Fedora-native Python 3.15 and `python3-typing-extensions-4.16.0-4.fc46`; same `%check` assertions passed. | PASS — local build; not COPR |
| `PY-RPM-SQLA-METADATA-01` | RPM metadata inspection | Confirm exact generic capability `python3dist(typing-extensions) = 4.16` in build and runtime requirements. | PASS |
| `PY-RPM-SQLA-COPR-01` | COPR clean buildroots | Build all eight helper SRPMs in `alma+epel-10-x86_64_v2`, `rhel+epel-10-x86_64` and `fedora-rawhide-x86_64`; SQLAlchemy `%check` passed in the relevant x86_64 chroots. | PASS — eight COPR build records below |

Local Fedora build artifact SHA-256: `c708b60df0739a4f6ed7461bee5ea473b35650bbf5e5730a0e9674991033d1ed`.

The ignored local validation directory retains detailed logs and binaries at `packaging/build/validation/rc5-r73/python-deps-republish-20261024/`; those generated files are not checked into Git. The Fedora verified build log SHA-256 is `a6382d50fabfdbc6c14f133deba606bdab3719129af012f75948bd8d146718ca`.

COPR build records (all eight have `succeeded` state in the target x86_64 chroots):

| Package | COPR build |
|---|---|
| `python3-alembic` | [11202990](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202990/) |
| `python3-flask` | [11202991](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202991/) |
| `python3-flask-alembic` | [11202992](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202992/) |
| `python3-flask-login` | [11202993](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202993/) |
| `python3-flask-sqlalchemy` | [11202994](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202994/) |
| `python3-mistune` | [11202995](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202995/) |
| `python3-sqlalchemy` | [11202996](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202996/) |
| `python3-typing-extensions` | [11202997](https://copr.fedorainfracloud.org/coprs/admiral-project/admiral/build/11202997/) |

The six coordinated Admiral Release 73 COPR builds also completed successfully: builds 11203001–11203006. The refreshed R73 set remains historical and earns no cell credit for Release 74.

## Reproduction

1. Download the eight `.src.rpm` files from `http://67.205.190.75/` and run `sha256sum -c SHA256SUMS`.
2. Build SQLAlchemy in a clean native EL10 mock/COPR chroot with the pinned `python3dist(typing-extensions) = 4.16` provider available; run `%check` without `--nodeps`.
3. Rebuild the same source in a Fedora Rawhide chroot with Fedora-native dependencies and verify `%check`; do not install EL10 binaries into Fedora.
4. After successful COPR builds, rebuild the coordinated six Admiral RPMs, publish the exact NEVRAs and hashes, and begin a fresh 0/8 matrix run.
