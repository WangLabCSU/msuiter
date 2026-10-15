"""Group (AA) test_p6_predicates — the three pre-declared acceptance predicates
plus the yardstick law, pinned as pure functions over committed campaign data.

Source of truth: the pre-registration manifest SS5 (banked before any build).
The tolerances, denominators and refusal semantics are FIXED HERE, in the RED
batch, before any measurement exists — the adjudication later discovers an
outcome, it cannot negotiate a threshold. Every predicate answers PASS / FAIL /
REFUSE; REFUSE (missing data, non-ok row) is never collapsible into PASS and
never averaged around.

Consumes ONLY: the campaign timings rows (cell/tool/arm/n/seconds/status), the
campaign + baseline benchmark CSV row dicts (row_type cell|signature rows as
emitted by scoring/run_products), and the frozen judgment arm set from g0.grid
(read-only). No docker, no wall — CI-safe synthetic fixtures.

RED-by-absence: tools.p6_predicates is introduced by the GREEN slice.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import p6_predicates                     # noqa: E402  (RED seam)

JUDGEMENT_ARMS = ("main", "comp_clock_only", "comp_mmr",
                  "comp_flat_triple", "comp_pole")
SENSITIVITY_ARMS = ("nb", "clock", "sparse")
PARITY_RATIO = 2.0          # manifest SS5 P-1: "<= 2x sigprofiler wall"
TOL = 0.02                  # manifest SS5 P-2(a): fixed a-prior metric floor


def _rows(tool, seconds_by_class, status="ok"):
    return [{"cell": f"{tool}__{a}__N{n}", "tool": tool, "arm": a, "n": n,
             "seconds": s, "status": status}
            for (a, n), s in seconds_by_class.items()]


def _classes():
    return [(a, n) for a in JUDGEMENT_ARMS
            for n in ((100, 1000, 10000) if a != "comp_pole"
                     else (100000, 300000, 1000000))]


# -- P-1 parity ----------------------------------------------------------------

def test_parity_passes_strictly_under_two_and_at_exactly_two():
    den = {c: 100.0 for c in _classes()}
    num = {c: 199.9 for c in _classes()}
    v = p6_predicates.parity_verdict(
        _rows("sigprofiler", den), _rows("sigminer_post_v3_rust", num),
        _classes(), ratio=PARITY_RATIO)
    assert v["verdict"] == "PASS", v
    assert len(v["cells"]) == len(_classes()), "every judged cell enumerated"
    # boundary: ratio == 2.0 is <= 2, passes
    v2 = p6_predicates.parity_verdict(
        _rows("sigprofiler", den), _rows("sigminer_post_v3_rust",
                                         {c: 200.0 for c in _classes()}),
        _classes(), ratio=PARITY_RATIO)
    assert v2["verdict"] == "PASS", v2


def test_parity_fails_by_a_hair_and_names_the_launderer():
    den = {c: 100.0 for c in _classes()}
    num = {c: 199.0 for c in _classes()}
    bad = ("comp_pole", 1000000)
    num[bad] = 200.1                                   # 2.001x — one cell over
    v = p6_predicates.parity_verdict(
        _rows("sigprofiler", den), _rows("sigminer_post_v3_rust", num),
        _classes(), ratio=PARITY_RATIO)
    assert v["verdict"] == "FAIL", v
    assert any(c["cell"].endswith(f"__N{bad[1]}") and c["arm"] == bad[0]
               and not c["passed"] for c in v["cells"]), (
        "the offending cell must be named — no averaging across cells "
        "can launder a fail (manifest SS5)")


def test_parity_refuses_on_missing_or_nonok_side():
    den = {c: 100.0 for c in _classes()}
    num = {c: 150.0 for c in _classes()}
    missing = _rows("sigprofiler", den)[:-1]            # one denominator absent
    v = p6_predicates.parity_verdict(
        missing, _rows("sigminer_post_v3_rust", num), _classes(),
        ratio=PARITY_RATIO)
    assert v["verdict"] == "REFUSE", v
    stale = _rows("sigminer_post_v3_rust", num, status="cached")
    v2 = p6_predicates.parity_verdict(
        _rows("sigprofiler", den), stale, _classes(), ratio=PARITY_RATIO)
    assert v2["verdict"] == "REFUSE", (
        f"non-ok rows may never adjudicate (zero-cached law): {v2}")


def test_parity_ignores_sensitivity_arms():
    den = {c: 100.0 for c in _classes()}
    num = {c: 150.0 for c in _classes()}
    extra = _rows("sigminer_post_v3", {("clock", 1000): 9e9})   # poison outside
    v = p6_predicates.parity_verdict(
        _rows("sigprofiler", den),
        _rows("sigminer_post_v3", num) + extra, _classes(), ratio=PARITY_RATIO)
    assert v["verdict"] == "PASS", v


# -- P-2 TP-only judgment non-regression -----------------------------------------

def _cell_row(tool, arm, n, *, tp, fp, fn):
    tot = tp + fp
    prec = tp / tot if tot else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) else 0.0
    return {"row_type": "cell", "tool": tool, "arm": arm, "N": n,
            "judge_class": "primary", "tp": tp, "fp": fp, "fn": fn,
            "precision": prec, "recall": rec, "f1": f1}


def _sig_rows(tool, arm, n, matched):
    return [{"row_type": "signature", "tool": tool, "arm": arm, "N": n,
             "judge_class": "primary", "signature": s, "status": "matched"}
            for s in matched]


def test_tp_only_regression_passes_within_tolerance():
    base = [_cell_row("sigminer", "main", 100, tp=90, fp=10, fn=10)]
    arm = [_cell_row("sigminer_post_v3", "main", 100, tp=89, fp=12, fn=11)]
    v = p6_predicates.tp_only_regression_verdict(
        base, arm, {"sigminer_post_v3": _classes()}, tol=TOL)
    assert v["verdict"] == "PASS", v


def test_tp_only_regression_fails_below_tolerance():
    base = [_cell_row("sigminer", "main", 100, tp=90, fp=10, fn=10)]
    arm = [_cell_row("sigminer_post_v3", "main", 100, tp=80, fp=20, fn=20)]
    v = p6_predicates.tp_only_regression_verdict(
        base, arm, {"sigminer_post_v3": _classes()}, tol=TOL)
    assert v["verdict"] == "FAIL", v
    bad = [c for c in v["cells"] if not c["passed"]]
    assert bad and bad[0]["arm"] == "main", "failing class named per cell"


def test_judgment_flips_are_counted_from_the_matched_set():
    """The per-signature TP judgment surface is the committed row_type ==
    'signature' status (PI ruling D2 TP-only: the matcher's own verdict)."""
    base = ([_cell_row("sigminer", "main", 100, tp=90, fp=10, fn=10)],
            _sig_rows("sigminer", "main", 100, ("SBS1", "SBS2", "SBS3")))
    arm = ([_cell_row("sigminer_post_v3", "main", 100, tp=90, fp=10, fn=10)],
           _sig_rows("sigminer_post_v3", "main", 100, ("SBS1", "SBS2")))
    v = p6_predicates.tp_only_regression_verdict(
        base[0] + base[1], arm[0] + arm[1],
        {"sigminer_post_v3": [("main", 100)]}, tol=TOL)
    assert v["verdict"] == "FAIL", v      # SBS3 lost its matched status = flip
    flip = [c for c in v["cells"] if c["flips"]]
    assert flip and flip[0]["flips"] == ["SBS3"], (
        "the flipped signature must be named, not tallied away")


def test_missing_baseline_class_refuses_not_passes():
    base = [_cell_row("sigminer", "main", 100, tp=90, fp=10, fn=10)]
    arm = [_cell_row("sigminer_post_v3", "main", 1000, tp=50, fp=0, fn=0)]
    v = p6_predicates.tp_only_regression_verdict(
        base, arm, {"sigminer_post_v3": [("main", 100), ("main", 1000)]},
        tol=TOL)
    assert v["verdict"] == "REFUSE", v


# -- P-3 attribution --------------------------------------------------------------

def test_attribution_is_mechanically_computed():
    def rows(tool, s):
        return [{"cell": f"{tool}__main__N100", "tool": tool, "arm": "main",
                 "n": 100, "seconds": s, "status": "ok"}]
    table = (rows("sigminer", 1600.0) + rows("sigminer_pre_v3", 1500.0)
             + rows("sigminer_post_p1", 1490.0)
             + rows("sigminer_post_p1_rust", 700.0)
             + rows("sigminer_post_p2", 710.0)
             + rows("sigminer_post_v3", 690.0)
             + rows("sigminer_post_v3_rust", 350.0))
    v = p6_predicates.attribution_split(table, n=100)
    assert v["stages"]["legacy_to_233"]["ratio"] == 1600.0 / 1500.0
    assert v["stages"]["kernel_face"]["ratio"] == 1490.0 / 700.0
    # mutation test: halving a stage's row moves that stage's ratio, only it
    table2 = [dict(r) for r in table]
    for r in table2:
        if r["tool"] == "sigminer_post_p1_rust":
            r["seconds"] = 350.0
    v2 = p6_predicates.attribution_split(table2, n=100)
    assert v2["stages"]["kernel_face"]["ratio"] == 1490.0 / 350.0
    assert v2["stages"]["legacy_to_233"]["ratio"] == 1600.0 / 1500.0


def test_attribution_refuses_on_missing_stage():
    table = [{"cell": "sigminer__main__N100", "tool": "sigminer", "arm": "main",
              "n": 100, "seconds": 1600.0, "status": "ok"}]
    v = p6_predicates.attribution_split(table, n=100)
    assert v["verdict"] == "REFUSE", v


# -- yardstick: no third state ------------------------------------------------------

def test_yardstick_measured_requires_both_sides():
    got = p6_predicates.yardstick_status(
        measured={"rust_seconds": 2.0, "r_seconds": 300.0},
        pending_reason=None, evidence_path=None)
    assert got["state"] == "MEASURED" and got["ratio"] == 150.0, got
    try:
        p6_predicates.yardstick_status(measured={"rust_seconds": 2.0},
                                       pending_reason=None, evidence_path=None)
    except ValueError:
        pass
    else:
        raise AssertionError("half-measured yardstick must be a hard error")


def test_yardstick_pending_requires_spoken_evidence():
    got = p6_predicates.yardstick_status(
        measured=None, pending_reason="nmf-rs wheel unfetchable (bounded retries)",
        evidence_path="bench/results/p6_yardstick/fetch.log")
    assert got["state"] == "LEDGERED-PENDING" and got["evidence_path"], got
    try:
        p6_predicates.yardstick_status(measured=None, pending_reason=None,
                                       evidence_path=None)
    except ValueError:
        pass
    else:
        raise AssertionError("silent skip smuggled through (Skip Law breach)")
