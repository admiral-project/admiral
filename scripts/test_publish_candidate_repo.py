"""Guard the local audit publisher against cross-distro RPM mixing."""

from pathlib import Path
import os
import subprocess
import textwrap


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/publish-candidate-repo.sh"
)
ADMIRAL_PACKAGES = (
    "admiral-common",
    "admirald",
    "admiral-fleet",
    "admiralctl",
    "admiral-flagship",
    "admiral-harbor",
)
HELPER_RPMS = (
    ("python3-alembic", "1.20.1", "4", "noarch"),
    ("python3-flask", "3.1.3", "3", "noarch"),
    ("python3-flask-alembic", "3.3.0", "4", "noarch"),
    ("python3-flask-login", "0.6.3", "9", "noarch"),
    ("python3-flask-sqlalchemy", "3.1.1", "10", "noarch"),
    ("python3-mistune", "3.4.0", "1", "noarch"),
    ("python3-sqlalchemy", "2.0.55", "4", "x86_64"),
    ("python3-typing-extensions", "4.16.0", "1", "noarch"),
)


def _touch_rpm(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()


def _create_rpm_inputs(root: Path, tag: str) -> tuple[Path, Path]:
    rpm_dir = root / f"{tag}-build/RPMS"
    support_dir = root / f"{tag}-support"

    for package in ADMIRAL_PACKAGES:
        arch = "noarch" if package in {"admiral-common", "admiral-flagship", "admiral-harbor"} else "x86_64"
        _touch_rpm(
            rpm_dir
            / arch
            / f"{package}-0.0.1rc5-67.{tag}.{arch}.rpm"
        )

    for name, version, release, arch in HELPER_RPMS:
        _touch_rpm(support_dir / f"{name}-{version}-{release}.{tag}.{arch}.rpm")

    return rpm_dir, support_dir


def _create_command_mocks(directory: Path) -> None:
    directory.mkdir()
    all_names = " ".join((*ADMIRAL_PACKAGES, *(row[0] for row in HELPER_RPMS)))
    rpm = directory / "rpm"
    rpm.write_text(
        textwrap.dedent(
            f"""\
            #!/usr/bin/env python3
            from pathlib import Path
            import sys

            names = {all_names!r}.split()
            rpm_path = Path(sys.argv[-1])
            stem = rpm_path.name.removesuffix('.rpm')
            package = next(name for name in sorted(names, key=len, reverse=True)
                           if stem.startswith(name + '-'))
            rest = stem[len(package) + 1:]
            version_release_tag, arch = rest.rsplit('.', 1)
            version_release, _tag = version_release_tag.rsplit('.', 1)
            version, release = version_release.rsplit('-', 1)
            query = sys.argv[sys.argv.index('--qf') + 1]
            if r'\\t' in query:
                print(f'{{package}}\\t0\\t{{version}}\\t{{release}}.{{_tag}}\\t{{arch}}')
            else:
                print(f'{{package}}-{{version}}-{{release}}.{{_tag}}.{{arch}}')
            """
        ),
        encoding="utf-8",
    )
    rpm.chmod(0o755)

    createrepo = directory / "createrepo_c"
    createrepo.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    createrepo.chmod(0o755)


def _run_publisher(tmp_path: Path, el10: tuple[Path, Path], fedora: tuple[Path, Path]):
    mock_bin = tmp_path / "mock-bin"
    _create_command_mocks(mock_bin)
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{mock_bin}:{env['PATH']}",
            "ADMIRAL_VALIDATION_REPO_ROOT": str(tmp_path / "repo"),
            "ADMIRAL_EL10_RPM_DIR": str(el10[0]),
            "ADMIRAL_EL10_SUPPORT_REPO": str(el10[1]),
            "ADMIRAL_FEDORA_RPM_DIR": str(fedora[0]),
            "ADMIRAL_FEDORA_SUPPORT_REPO": str(fedora[1]),
        }
    )
    return subprocess.run(
        [str(SCRIPT), "67"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_publisher_stages_matching_nevras_and_records_hashes(tmp_path):
    el10 = _create_rpm_inputs(tmp_path / "inputs", "el10")
    fedora = _create_rpm_inputs(tmp_path / "inputs", "fc46")

    result = _run_publisher(tmp_path, el10, fedora)

    assert result.returncode == 0, result.stdout + result.stderr
    for distro, tag in (("el10", "el10"), ("fedora", "fc46")):
        repo = tmp_path / "repo/rc5-r67" / distro / "x86_64"
        rpms = sorted(repo.glob("*.rpm"))
        assert len(rpms) == 6
        assert all(f".{tag}." in rpm.name for rpm in rpms)
        manifest = (repo / "RPM-MANIFEST.tsv").read_text().splitlines()
        assert len(manifest) == 7
        assert f"{tag}" in "\n".join(manifest)
        assert (repo / "SHA256SUMS").is_file()
        assert not any(rpm.name.startswith("python3-") for rpm in rpms)


def test_publisher_keeps_python_helpers_out_of_fedora_candidate_repo(tmp_path):
    el10 = _create_rpm_inputs(tmp_path / "inputs", "el10")
    fedora_build = _create_rpm_inputs(tmp_path / "fedora", "fc46")[0]

    result = _run_publisher(tmp_path, el10, (fedora_build, el10[1]))

    assert result.returncode == 0, result.stdout + result.stderr
    repo = tmp_path / "repo/rc5-r67/fedora/x86_64"
    assert len(list(repo.glob("*.rpm"))) == 6
    assert not list(repo.glob("python3-*.rpm"))


def test_publisher_rejects_stale_mixed_rpm_already_in_candidate_repo(tmp_path):
    el10 = _create_rpm_inputs(tmp_path / "inputs", "el10")
    fedora = _create_rpm_inputs(tmp_path / "inputs", "fc46")
    stale = (
        tmp_path
        / "repo/rc5-r67/fedora/x86_64/python3-alembic-1.20.1-4.el10.noarch.rpm"
    )
    _touch_rpm(stale)

    result = _run_publisher(tmp_path, el10, fedora)

    assert result.returncode != 0
    assert "fedora repository has 7 RPM files; expected exactly six Admiral RPMs" in result.stderr
