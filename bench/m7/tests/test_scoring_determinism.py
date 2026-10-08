"""⑩ Byte-reproducible benchmark tables (hard rule: no RNG at score time).

Scoring is a pure function of the committed cell artifacts plus the
seed-derived truth: the same cachedir scored twice, in separate calls,
produces byte-identical CSV. The ts is file-name metadata and must not
leak into table bytes. This test is the standing gate for that rule; the
gate-level demo runs the same double-emission over the same cachedir and
diffs the bytes.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

# The tests-package imports bind BEFORE scoring: scoring.truth prepends
# bench/g0 to sys.path, which would otherwise let bench/g0/tests claim the
# `tests` name in a fresh interpreter.
from tests import scoring_fixtures as fx
from tests.test_scoring_pipeline import _build_fixture                 # same fixture
from scoring import run_products                                        # noqa: E402 (RED seam)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_same_cachedir_twice_yields_byte_identical_benchmark_csv():
    root = _build_fixture()
    try:
        meta = {"profile": "smoke", "adapter": "mock"}
        p1, p2 = root / "b1.csv", root / "b2.csv"
        for out in (p1, p2):
            rep = run_products.score_cachedir(root, profile="smoke",
                                              provider_name="synthetic",
                                              provider_seed=0)
            run_products.write_benchmark_csv(rep, out, meta=meta)
        assert _sha(p1) == _sha(p2), \
            "same cachedir must reproduce a byte-identical benchmark table"
    finally:
        fx.cleanup(root)


def test_row_objects_match_between_independant_scoreings():
    """Not just bytes: the structured rows themselves must be value-equal
    across independent score passes (catches accidental dict-order or
    float-accumulation-order drift before it reaches the CSV layer)."""
    root = _build_fixture()
    try:
        a = run_products.score_cachedir(root, profile="smoke",
                                        provider_name="synthetic", provider_seed=0)
        b = run_products.score_cachedir(root, profile="smoke",
                                        provider_name="synthetic", provider_seed=0)
        assert a.rows == b.rows and a.skipped == b.skipped
    finally:
        fx.cleanup(root)


def test_timestamp_is_file_name_metadata_not_table_content():
    """The ts stamps file identity for the outdir contract; the bytes of the
    tables over the same cachedir must not depend on it."""
    root = _build_fixture()
    try:
        meta = {"profile": "smoke", "adapter": "mock"}
        rep = run_products.score_cachedir(root, profile="smoke",
                                         provider_name="synthetic", provider_seed=0)
        for ts in ("20261008-000000", "20261231-235959"):
            path = root / f"benchmark_m7_{ts}.csv"
            run_products.write_benchmark_csv(rep, path, meta=meta)
        a, b = (root / "benchmark_m7_20261008-000000.csv",
                root / "benchmark_m7_20261231-235959.csv")
        assert a.read_bytes() == b.read_bytes()
    finally:
        fx.cleanup(root)
