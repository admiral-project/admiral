"""Guard seed evidence manifests against self-inclusion and incomplete tee logs."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEED_BUILDER = (
    ROOT
    / "docs/audits/admiral-production-readiness-2026-10-21/scripts/create_seed_os.sh"
)


def test_seed_manifest_waits_for_log_tee_and_excludes_itself():
    builder = SEED_BUILDER.read_text(encoding="utf-8")

    assert 'exec 9>&1\nexec > >(tee -a "$host_log") 2>&1\nhost_log_tee_pid=$!' in builder
    tee_wait = builder.index('wait "$host_log_tee_pid"')
    manifest_find = builder.index(
        'find . -maxdepth 1 -type f ! -name SHA256SUMS -print0'
    )
    assert tee_wait < manifest_find
    assert 'sha256sum -c SHA256SUMS --quiet' in builder
    assert 'sha256sum "$evidence_dir"/* > "$evidence_dir/SHA256SUMS"' not in builder
