"""Group (R) test_floor_calibration — the RB-09 calibrated floor table.

RB-09 (controller ruling 2026-10-09) refuted the REP-1-anchor floor table
(the r5 probe ran --reps 1 while the protocol runs REP-100 cells; no green
cell was ever physically possible) and ordered the replacement: floors must
descend from per-class REP-100 uncontended witnesses, the sweep
{1,5,10}x n {100,1e3,1e4} pins the probe-scale linearity and the measured
n-saturation SHAPE, residuals are pinned here, and the 3.0x gate ratio
remains untouchable — the repair fixes what the ratio multiplies, never
the ratio.

These units read the committed calibration artifacts (witness JSONs under
bench/results/m7_floor_calibration_20261009/ + the table constants in
tools/matrix_governance). They are pure/CI-safe: no docker, no live run —
the batch that produced the witnesses ran under the probe's own freshness
law (no cached replays) and --floor-gate off (a probe measures, it never
self-adjudicates against the table it is recalibrating).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import tools.matrix_governance as gov                           # noqa: E402

SWEEP_N = (100, 1000, 10000)
SWEEP_REPS = (1, 5, 10)
LINEAR_RESID_TOL = 0.15          # probe-scale reps-linearity: fit residual cap


def _sweep_points(tool: str, n: int):
    """((reps, cpu_seconds), ...) for the committed main-arm sweep points."""
    pts = []
    for reps in SWEEP_REPS:
        raw = gov._SWEEP_RAW[f"{tool}|N{n}"]
        pts.append((reps, float(raw[str(reps)])))
    return pts


def _least_squares(points):
    (x0, y0), (x1, y1), (x2, y2) = points
    mx = (x0 + x1 + x2) / 3
    my = (y0 + y1 + y2) / 3
    num = ((x0 - mx) * (y0 - my) + (x1 - mx) * (y1 - my)
           + (x2 - mx) * (y2 - my))
    den = (x0 - mx) ** 2 + (x1 - mx) ** 2 + (x2 - mx) ** 2
    slope = num / den
    return slope, my - slope * mx


# -- (1) the frozen grid is fully anchored, reps-matched, verbatim ----------------

def test_every_grid_class_carries_a_reps_matched_committed_anchor():
    from g0 import grid
    seen = set()
    for arm in grid.arms_for_profile("degraded"):
        for n in arm.n_list:
            for tool in ("sigminer", "sigprofiler"):
                key = (tool, arm.name, n)
                seen.add(key)
                assert key in gov._FLOOR_ANCHORS, f"unanchored class {key}"
                a = gov._FLOOR_ANCHORS[key]
                assert a["reps"] == gov.PROTOCOL_REPS, key
                path = gov.anchor_witness_path(a)
                assert path.exists(), f"anchor witness missing: {path}"
                doc = json.loads(path.read_text(encoding="utf-8"))
                argv = doc["argv"]
                assert argv[argv.index("--reps") + 1] == str(a["reps"]), key
                assert doc["verdict"] == "OK" and doc["status_tail"] == "ok"
                assert doc["sidecar"]["cpu_seconds"] == a["cpu_seconds"], key
    assert seen == set(gov._FLOOR_ANCHORS), (
        "table holds classes the frozen degraded grid does not run")


# -- (2) the sweep pins probe-scale linearity and the n-saturation shape ----------

def test_sweep_is_reps_linear_within_tolerance_at_probe_scale():
    for tool in ("sigminer", "sigprofiler"):
        for n in SWEEP_N:
            pts = _sweep_points(tool, n)
            fit = gov._SWEEP_FIT[f"{tool}|N{n}"]
            slope, boot = _least_squares(pts)
            assert slope > 0, (tool, n)
            resid = max(abs(y - (boot + slope * x)) / y for x, y in pts)
            assert resid <= LINEAR_RESID_TOL, (tool, n, resid)
            assert abs(fit["per_rep"] - slope) / slope < 0.02   # committed fit

def test_measured_main_arm_costs_are_finite_and_n_saturating():
    # RB-09(3)(iii): the n-shape is MEASURED, never assumed — the committed
    # rows are non-monotone in total cost across n (sigminer 1330/1063/1878
    # s at n=1e2/1e3/1e4: small-n convergence work dominates), so the old
    # monotonicity expectation was itself a fabricated shape. The law the
    # gate needs: costs are positive and SUBLINEAR in n — a 10x grid
    # growth may never move total cost by more than 4x (a superlinear-in-n
    # regime would mean the frozen grid is unmeasurable and every floor
    # suspect). sigprofiler saturates flat (~0.40 s/rep across all n).
    for tool in ("sigminer", "sigprofiler"):
        costs = [gov.anchor_measured(gov._FLOOR_ANCHORS[(tool, "main", n)])
                 for n in SWEEP_N]
        assert all(c > 0 for c in costs), (tool, costs)
        assert costs[1] <= 4.0 * costs[0], (tool, "1e2->1e3", costs)
        assert costs[2] <= 4.0 * costs[1], (tool, "1e3->1e4", costs)


# -- (3) the floor is the measured witness, ratio untouched -----------------------

def test_floor_equals_the_committed_rep100_witness_cost():
    # RB-09(3)(iii): floor := f(reps-100 measured witness). The table is the
    # witness; there is no model degrees of freedom left to tune.
    for key, a in gov._FLOOR_ANCHORS.items():
        assert gov.floor_for(*key) == gov.anchor_measured(a), key


def test_gate_ratio_remains_the_pre_registered_three():
    assert gov.FLOOR_RATIO == 3.0                       # untouchable law
    assert gov.PASS_STATUSES == ("ok", "cached")


def test_superlinearity_of_protocol_scale_is_recorded_by_the_sweep():
    # The RB-09 discovery in both of its observed signs — a short probe may
    # pin SHAPE, never MAGNITUDE, and the data showed the extrapolation can
    # err on either side:
    #   sigminer (the ruling's finding): protocol per-rep cost is AT LEAST
    #     the probe-scale linear projection (superlinear — ratios 1.0-8.6);
    #     an extrapolated floor would sit BELOW reality and self-halt the
    #     matrix (pass-1: floor 310 < rep-1 witness 360).
    #   sigprofiler (the mirror image): the 100-rep cost amortizes BELOW the
    #     probe slope (fixed startup ~11 s dominates at reps<=10; protocol
    #     per-rep ratio ~0.2). An extrapolated floor would sit ABOVE reality
    #     — arbitrary, which RB-09 forbids equally.
    # Pinned as data so any regression to sweep-extrapolated floors is
    # visible; the floor itself remains the measured witness (unit above).
    for n in SWEEP_N:
        slope = gov._SWEEP_FIT[f"sigminer|N{n}"]["per_rep"]
        anchor_cpu = gov._FLOOR_ANCHORS[("sigminer", "main", n)]["cpu_seconds"]
        assert (anchor_cpu / gov.PROTOCOL_REPS) >= 0.9 * slope, ("superlinear", n)
    for n in SWEEP_N:
        slope = gov._SWEEP_FIT[f"sigprofiler|N{n}"]["per_rep"]
        anchor_cpu = gov._FLOOR_ANCHORS[("sigprofiler", "main", n)]["cpu_seconds"]
        assert (anchor_cpu / gov.PROTOCOL_REPS) <= slope, ("amortizing", n)
