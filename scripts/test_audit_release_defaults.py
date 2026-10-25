"""Keep audit guest helpers aligned with the coordinated RPM release."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
RPM_SPECS = (
    "admiral-common",
    "admirald",
    "admiral-fleet",
    "admiralctl",
    "admiral-flagship",
    "admiral-harbor",
)
AUDIT_HELPERS = (
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/install-single-node-audit.sh",
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/bootstrap-candidate-node.sh",
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/install-admin-portal-audit.sh",
)
SEED_PREPARATION = (
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/prepare-audit-seed-guest.sh"
)
R75_SINGLE_LANE = (
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/r75/run-single-lane.sh"
)
R75_SINGLE_RUNNER = (
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/r75/run-single-release-pass.sh"
)


def test_audit_helpers_default_to_the_coordinated_rpm_release():
    releases = set()
    for package in RPM_SPECS:
        spec = ROOT / f"packaging/rpm/{package}.spec"
        match = re.search(r"^Release:\s*(\d+)%\{\?dist\}", spec.read_text(), re.MULTILINE)
        assert match, f"missing numeric Release in {spec}"
        releases.add(match.group(1))

    assert len(releases) == 1, f"Admiral RPM Release values differ: {sorted(releases)}"
    expected = releases.pop()
    for helper in AUDIT_HELPERS:
        text = helper.read_text()
        match = re.search(r"ADMIRAL_RC_RELEASE:-([0-9]+)", text)
        assert match, f"missing default candidate release in {helper}"
        assert match.group(1) == expected, (
            f"{helper} defaults to Release {match.group(1)}, but RPM specs use {expected}"
        )


def test_single_node_installer_selects_native_candidate_dist_tag():
    helper = AUDIT_HELPERS[0].read_text()
    assert re.search(
        r"el10\)\s*repo_name=admiral-local-el10\.repo;\s*rpm_suffix=el10\s*;;",
        helper,
    )
    assert re.search(
        r"fedora\)\s*repo_name=admiral-local-fedora\.repo;\s*rpm_suffix=fc46\s*;;",
        helper,
    )
    assert 'packages+=("${package}-${expected_version}-${expected_release}.${rpm_suffix}")' in helper
    assert '[[ $actual == "${expected_epoch}:${expected_version}-${expected_release}.${rpm_suffix}" ]]' in helper


def test_candidate_install_helpers_do_not_bypass_dnf_vendor_resolution():
    for helper in AUDIT_HELPERS:
        text = helper.read_text()
        assert "--allow-vendor-change" not in text, helper
        assert "--nodeps" not in text, helper


def test_rocky_and_alma_seed_profiles_pin_verified_pyopenssl():
    seed_setup = SEED_PREPARATION.read_text()
    assert 'if [[ "$os_id" == rocky || "$os_id" == almalinux ]]; then' in seed_setup
    assert 'if [[ "$os_id" == centos ]]; then' not in seed_setup
    assert "python3-pyOpenSSL-25.0.0-1.el10_1.noarch.rpm" in seed_setup
    assert "eb5d2a6be0e47099c63fa042f83afac12021820bfc0d79fa0f9dcd57b71941dc" in seed_setup
    assert 'dnf install -y "$pinned_rpm"' in seed_setup
    assert 'sed -i \'/^\\[epel\\]$/a excludepkgs=python3-pyOpenSSL\'' in seed_setup


def test_staged_candidate_python_rpms_require_the_pinned_signing_key():
    seed_setup = SEED_PREPARATION.read_text()
    assert 'ADMIRAL_AUDIT_RPM_GPG_KEY_FILE' in seed_setup
    assert "7103D33100F674D0B3DFAD17B943D0C834ED6667" in seed_setup
    assert 'rpm --import "$candidate_rpm_key"' in seed_setup
    assert 'rpmkeys --checksig --verbose "$candidate_rpm"' in seed_setup
    assert "grep -Eiq 'signature.*: OK'" in seed_setup
    assert 'dnf install -y --setopt=localpkg_gpgcheck=1' in seed_setup


def test_r75_audit_matches_lifecycle_customer_and_precreates_logs():
    lane = R75_SINGLE_LANE.read_text(encoding="utf-8")
    runner = R75_SINGLE_RUNNER.read_text(encoding="utf-8")
    lifecycle = (
        ROOT
        / "docs/audits/admiral-production-readiness-2026-10-21/scripts/r75/single-node-lifecycle.sh"
    ).read_text(encoding="utf-8")

    assert 'customer="r75-single-${suffix}"' in lifecycle
    assert "f'r75-single-r75-{os}'" in lane
    assert lane.index(': > "$evidence/functional.log"') < lane.index(
        'exec > >(tee -a "$evidence/functional.log")'
    )
    assert runner.index(': > "$runtime/orchestrator.log"') < runner.index(
        'exec > >(tee -a "$runtime/orchestrator.log")'
    )
