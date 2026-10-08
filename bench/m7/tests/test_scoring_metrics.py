"""⑥ P/R/F1 and exposure-error math of the scoring slice (ARCHITECTURE §8).

Zero-denominator conventions are *frozen decisions* recorded in
scoring/metrics.py and pinned here — an empty arm must not poison a mean,
and "nothing predicted, nothing missed" is agreement, not division-by-zero.

Exposure-error rows follow the benchmark-memo rule (2026-10-05 §4): the
absolute/relative exposure error is only defined on pairs the Hungarian
assignment actually matched; anything without a matched bound reads NaN
("na" in the CSV) so absent bounds can never masquerade as zero error.
"""

from __future__ import annotations

import math
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from scoring import metrics                          # noqa: E402 (RED seam)

TOL = 1e-12


def _close(triple, p, r, f):
    return (abs(triple[0] - p) < TOL and abs(triple[1] - r) < TOL
            and abs(triple[2] - f) < TOL)


def test_prf_exact_matches_score_perfect():
    assert _close(metrics.precision_recall_f1(5, 0, 0), 1.0, 1.0, 1.0)


def test_prf_missing_and_spurious_cases():
    # one truth signature missed
    assert _close(metrics.precision_recall_f1(4, 0, 1),
                   1.0, 4.0 / 5.0, 2.0 * 0.8 / 1.8)
    # one spurious call
    assert _close(metrics.precision_recall_f1(5, 1, 0),
                   5.0 / 6.0, 1.0, 2.0 * (5.0 / 6.0) / (5.0 / 6.0 + 1.0))


def test_prf_zero_denominator_conventions_are_frozen():
    """Pinned conventions (documented on precision_recall_f1):
    - tp=0 & fp=0  -> nothing claimed  => P = 1 (no false claim to penalize)
    - tp=0 & fn=0  -> nothing missed   => R = 1
    - f1 = 0 whenever P + R == 0."""
    assert _close(metrics.precision_recall_f1(0, 0, 0), 1.0, 1.0, 1.0)
    assert _close(metrics.precision_recall_f1(0, 2, 0), 0.0, 1.0, 0.0)
    assert _close(metrics.precision_recall_f1(0, 0, 3), 1.0, 0.0, 0.0)


def test_exposure_errors_defined_only_on_matched_bounds():
    abs_err, rel_err = metrics.exposure_errors(550.0, 300.0)
    assert abs(abs_err - 250.0) < TOL and abs(rel_err - 250.0 / 300.0) < TOL
    abs_err, rel_err = metrics.exposure_errors(250.0, 250.0)
    assert abs_err == 0.0 and rel_err == 0.0


def test_exposure_errors_nan_for_absent_bounds():
    """truth_h <= 0 (no truth bound) or a NaN estimate => both errors are
    NaN — an absent bound is reported as absent, never as a zero error."""
    for est, th in ((10.0, 0.0), (10.0, -1.0), (float("nan"), 100.0)):
        abs_err, rel_err = metrics.exposure_errors(est, th)
        assert math.isnan(abs_err) and math.isnan(rel_err), \
            f"({est}, {th}) must yield NaN errors, got {(abs_err, rel_err)}"


def test_call_predicate_follows_the_intervals_contract():
    """A call is a finite, strictly positive, non-zeroed absolute-estimand
    row. Tiny positive leakage on an absent signature IS a call (a measured
    false positive, per the ARCH §8 absent-signature quality metric) — the
    filter is zero, not a tuned epsilon."""
    assert metrics.is_countable_call(150.0, False) is True
    assert metrics.is_countable_call(0.0001, False) is True
    assert metrics.is_countable_call(0.0, False) is False
    assert metrics.is_countable_call(-3.0, False) is False
    assert metrics.is_countable_call(150.0, True) is False
    assert metrics.is_countable_call(float("nan"), False) is False


def test_mean_of_finite_values_ignores_nan_and_reports_none_when_empty():
    assert metrics.mean_or_none([2.0, float("nan"), 4.0]) == 3.0
    assert metrics.mean_or_none([float("nan")]) is None
    assert metrics.mean_or_none([]) is None
