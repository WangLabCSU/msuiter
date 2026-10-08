"""⑤ Hungarian assignment + cosine kernel of the scoring slice (ARCHITECTURE §8).

Contract pinned here (implementation is the GREEN slice — RED-by-absence now):

  scoring.match.MATCH_MIN_COSINE      frozen match tolerance (primary table)
  scoring.match.MATCH_ROBUSTNESS_BAND the frozen 0.80-0.90 sweep band,
                                      appendix-only (never the primary table)
  scoring.match.cosine(a, b)          cosine similarity of two vectors
  scoring.match.hungarian_assign(rows, min_cosine=...)
                                      one-to-one maximum-weight assignment
                                      over the cosine matrix; pairs below
                                      the tolerance are rejected, never
                                      counted; result normalized (ascending
                                      by row index) and fully deterministic.

The one-to-one semantics is the load-bearing property: a greedy
max-cosine picker would double-assign the same truth signature (ARCHITECTURE
§8 deliberately makes that the robustness appendix, not the primary metric),
so the anti-greedy case below is the test that distinguishes the two.
"""

from __future__ import annotations

from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from scoring import match                            # noqa: E402 (RED seam)

TOL = 1e-12


def test_match_tolerance_is_the_frozen_sweep_midpoint():
    """ARCHITECTURE §8 pins the sweep at 0.80-0.90; the primary table fixes
    its midpoint so the headline number is never swept post-hoc."""
    assert match.MATCH_MIN_COSINE == 0.85, \
        f"primary-table tolerance drifted: {match.MATCH_MIN_COSINE}"
    assert tuple(match.MATCH_ROBUSTNESS_BAND) == (0.80, 0.90), \
        "the appendix sweep band is frozen too — it must match ARCH §8"


def test_cosine_identity_and_orthogonality():
    v = [1.0, 2.0, 3.0, 4.0]
    assert abs(match.cosine(v, v) - 1.0) < TOL
    assert abs(match.cosine([1.0, 0.0], [0.0, 1.0])) < TOL


def test_hungarian_is_one_to_one_not_greedy():
    """Two predictions both hug truth #0; the optimum must re-pair the
    second prediction onto truth #1 (total 1.88) instead of greedy
    double-picking truth #0 (total 1.09 + a lost match)."""
    cos = [[0.99, 0.90],
           [0.98, 0.10]]
    pairs = match.hungarian_assign(cos, min_cosine=0.85)
    assert sorted(pairs) == [(0, 1, 0.90), (1, 0, 0.98)], \
        f"assignment is not maximum-weight one-to-one: {pairs}"
    assert pairs == sorted(pairs), "result must be normalized ascending by row"


def test_pairs_below_tolerance_are_rejected_not_counted():
    """A near-3/4 match is a false-positive/miss pair, never a TP — the
    tolerance is a hard gate, not a weight."""
    assert match.hungarian_assign([[0.84]], min_cosine=0.85) == []
    assert match.hungarian_assign([[0.86]], min_cosine=0.85) == [(0, 0, 0.86)]


def test_assignment_handles_rectangular_and_empty_inputs():
    # more predictions than truth: the extra prediction simply stays unmatched
    pairs = match.hungarian_assign([[0.95, 0.93, 0.10]], min_cosine=0.85)
    assert pairs == [(0, 0, 0.95)], f"rectangular case wrong: {pairs}"
    assert match.hungarian_assign([], min_cosine=0.85) == []
    assert match.hungarian_assign([[]], min_cosine=0.85) == []


def test_assignment_is_deterministic():
    """Byte-reproducible benchmark tables start here: same cosine matrix,
    same pair list — no tie-order lottery."""
    cos = [[0.91, 0.90, 0.10],
           [0.90, 0.92, 0.11],
           [0.10, 0.10, 0.99]]
    first = match.hungarian_assign(cos, min_cosine=0.85)
    for _ in range(8):
        assert match.hungarian_assign(cos, min_cosine=0.85) == first
