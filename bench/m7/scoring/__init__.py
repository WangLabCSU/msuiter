"""U-M7-02 scoring slice — the attestation half turned into a benchmark table.

Everything here is a *read-only consumer*: scoring is a pure function of the
committed cell artifacts (``<cachedir>/cells/<tool>__<arm>__N<n>/out/``)
and the seed-derived ground truth (generation parameters of the frozen G0
simulator, imported read-only through ``sys.path`` exactly as the harness
run path does). No RNG at score time — the same cachedir must reproduce the
benchmark CSV byte-identically (pinned by tests/test_scoring_determinism.py).

Primary metric: Hungarian one-to-one assignment of predicted signatures onto
truth under the catalog cosine similarity, with the frozen match tolerance
and every convention pinned on ``scoring.match`` / ``scoring.metrics`` and
in the design-memo addendum. The package never writes into cachedirs, never
touches ``bench/g0/``, and never references the G0 cache tree.
"""

from __future__ import annotations

from .match import MATCH_MIN_COSINE, MATCH_ROBUSTNESS_BAND, cosine, hungarian_assign
from .metrics import (exposure_errors, is_countable_call, mean_or_none,
                      precision_recall_f1)

__all__ = ["MATCH_MIN_COSINE", "MATCH_ROBUSTNESS_BAND", "cosine",
           "hungarian_assign", "precision_recall_f1", "exposure_errors",
           "is_countable_call", "mean_or_none"]
