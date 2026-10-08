"""P/R/F1 and exposure-error arithmetic — the frozen measurement conventions.

Every judgment call in this module is a *decision*, so it is written down
and pinned by tests/test_scoring_metrics.py rather than re-litigated per
caller:

* **Zero-denominator conventions.** ``tp=0 & fp=0`` (nothing claimed) scores
  P = 1 — there is no false claim to penalise; ``tp=0 & fn=0`` (nothing
  missed) scores R = 1; F1 = 0 whenever P + R = 0. An empty stratum is
  agreement on the empty set, not a division-by-zero, and an arm-level mean
  over such strata must not be poisoned by dropping them silently.
* **Exposure errors exist only on matched bounds** (benchmark memo
  2026-10-05 §4): the absolute/relative error of a truth signature is
  defined on the (prediction, truth) pair the Hungarian assignment actually
  matched. An absent bound reads NaN and lands in the CSV as ``na`` — never
  as a zero error, which would silently flatter misses and false calls.
* **Call predicate at zero.** A call is any finite strictly-positive,
  non-zeroed absolute-estimand row. Tiny positive leakage on an absent
  signature is *measured* as a false positive (ARCHITECTURE §8 counts
  absent-signature misassignment quality on purpose); the filter is 0.0,
  not a tuned epsilon that would hide exactly what is being measured.
"""

from __future__ import annotations

import math


def precision_recall_f1(tp: int, fp: int, fn: int) -> tuple:
    """P/R/F1 from confusion counts with the frozen zero-denominator
    conventions (module docstring). Returns ``(precision, recall, f1)``."""
    p = 1.0 if tp + fp == 0 else tp / (tp + fp)
    r = 1.0 if tp + fn == 0 else tp / (tp + fn)
    f1 = 0.0 if p + r == 0 else 2.0 * p * r / (p + r)
    return p, r, f1


def exposure_errors(estimate, truth_h) -> tuple:
    """``(|estimate - truth_h|, |estimate - truth_h| / truth_h)`` on matched
    bounds; ``(nan, nan)`` when there is no truth bound (truth_h <= 0) or no
    usable estimate — an absent bound stays absent."""
    if truth_h <= 0.0 or math.isnan(float(estimate)):
        return (float("nan"), float("nan"))
    abs_err = abs(float(estimate) - truth_h)
    return (abs_err, abs_err / truth_h)


def is_countable_call(estimate, zeroed: bool) -> bool:
    """The zero-threshold call predicate (module docstring): finite, strictly
    positive, non-zeroed."""
    if zeroed:
        return False
    try:
        e = float(estimate)
    except (TypeError, ValueError):
        return False
    return math.isfinite(e) and e > 0.0


def mean_or_none(values):
    """Mean over finite values; ``None`` when nothing is finite (the CSV
    writer renders None as ``na``). Keeps NaN-mean poisoning and
    NaN-vs-missing confusion out of the table."""
    vals = [float(v) for v in values if v is not None and not math.isnan(float(v))]
    if not vals:
        return None
    return sum(vals) / len(vals)
