"""Hungarian assignment + cosine kernel — the ARCHITECTURE §8 primary metric.

The primary benchmark metric is the **Hungarian one-to-one** assignment of
predicted signatures onto truth signatures under the catalog cosine
similarity. Deliberately *not* the primary metric: greedy max-cosine with a
threshold sweep (0.80–0.90), which is the robustness appendix. One-to-one
semantics matter because several predictions can individually resemble the
same truth signature (the near-duplicate flat pair is the designed stress
case): a greedy picker double-claims it and hides the miss the assignment
must expose.

Frozen decisions (pinned by tests/test_scoring_match.py):

* ``MATCH_MIN_COSINE = 0.85`` — the **midpoint** of the frozen
  0.80–0.90 sweep band (ARCHITECTURE §8 / benchmark memo 2026-10-05 §3).
  The primary table must fix one operating point so the headline number is
  never swept post-hoc; the sweep lives on as an appendix. The band is a
  protocol fact, not a tuned value, so the midpoint is the least-chosen
  choice. TODO(paper): pin the citation for the band with its source ref.
* A cosine pair below the tolerance is **rejected, never counted** — the
  tolerance is a gate, not a weight; the pair falls out as FP/FN.
* Output is normalized (ascending by row index) and taken from a
  deterministic solver, because the benchmark CSV must be byte-reproducible.
"""

from __future__ import annotations

import numpy as np
from scipy.optimize import linear_sum_assignment

MATCH_MIN_COSINE = 0.85
MATCH_ROBUSTNESS_BAND = (0.80, 0.90)


def cosine(a, b) -> float:
    """Cosine similarity of two numeric vectors; a zero-norm side is 0.0
    (no direction to agree on) rather than a division blow-up."""
    va, vb = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    na, nb = float(np.linalg.norm(va)), float(np.linalg.norm(vb))
    if na <= 0.0 or nb <= 0.0:
        return 0.0
    return float(va @ vb / (na * nb))


def hungarian_assign(cos_rows, min_cosine: float = MATCH_MIN_COSINE) -> list:
    """Maximum-weight one-to-one assignment over the (predictions x truth)
    cosine matrix; returns ``[(row_idx, col_idx, cos)]`` ascending by row.

    Pairs scoring below ``min_cosine`` are dropped after the optimum — they
    are rejected matches, not weak matches. Rectangular and empty inputs are
    well-defined (the surplus side simply stays unmatched)."""
    if not len(cos_rows) or not len(cos_rows[0]):
        return []
    matrix = np.asarray(cos_rows, dtype=float)
    if matrix.ndim != 2 or 0 in matrix.shape:
        return []
    row_ind, col_ind = linear_sum_assignment(matrix, maximize=True)
    pairs = [(int(r), int(c), float(matrix[r, c]))
             for r, c in zip(row_ind, col_ind) if matrix[r, c] >= min_cosine]
    return sorted(pairs)
