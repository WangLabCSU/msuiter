"""P6 acceptance predicates — pure mechanical adjudicators over campaign data.

These functions are the executable face of the pre-registration manifest §5:
P-1 parity (<= 2x sigprofiler wall, per judged cell), P-2 TP-only judgment
non-regression (frozen metric floors + the PI-ruling-D2 matched-status surface),
P-3 the attribution split (mechanical ratios, no hand-typed figures), and the
yardstick two-state law (MEASURED or LEDGERED-PENDING, no third state).

Law encoded here, restated from the zero-fabrication law (docs/PERFORMANCE.md
and the RB-10 MEASURED-false precedent): an adjudication DISCOVERS an outcome.
Missing data or a non-ok row is REFUSE, never a silent PASS; a failing cell is
NAMED, never averaged away; the boundary of the 2x gate is inclusive exactly at
2.0 because the pre-registration says "<= 2x".

Pure over row dicts (the committed timings/benchmark CSV shapes). No IO, no
docker, no clock. Callers feed bytes from the campaign outdir only.
"""

from __future__ import annotations

FLOAT_EPS = 1e-9                    # boundary-inclusive float guard, frozen a-prior
YARD_STATES = ("MEASURED", "LEDGERED-PENDING")


def _index(rows, tool=None):
    """{(arm, n): row} for row_type==cell rows of one tool (or as given)."""
    out = {}
    for r in rows:
        if r.get("row_type", "cell") != "cell":
            continue
        if tool is not None and r.get("tool") != tool:
            continue
        out[(r["arm"], int(r["n"] if "n" in r else r["N"]))] = r
    return out


# ------------------------------------------------------------------ P-1 parity --

def parity_verdict(den_rows, num_rows, classes, *, ratio=2.0):
    """Per judged class: numerator wall <= ratio x denominator wall.

    classes: [(arm, n), ...] judged (judge=True) classes only — sensitivity
    arms are report columns, never gates (frozen grid law). REFUSE when any
    side lacks an ok row for any class; FAIL names every offending cell."""
    den, num = _index(den_rows), _index(num_rows)
    cells, refusals = [], []
    for arm, n in classes:
        d, u = den.get((arm, n)), num.get((arm, n))
        if d is None or u is None:
            refusals.append(f"{arm}/N{n}: side "
                           + ("denominator" if d is None else "numerator")
                           + " row absent")
            continue
        for side, row in (("denominator", d), ("numerator", u)):
            if row.get("status") != "ok":
                refusals.append(f"{arm}/N{n}: {side} status "
                               f"{row.get('status')!r} is not a measurement")
    if refusals:
        return {"verdict": "REFUSE", "cells": cells, "why": refusals}
    failed = False
    for arm, n in classes:
        d, u = den[(arm, n)], num[(arm, n)]
        ds, us = float(d["seconds"]), float(u["seconds"])
        ok = us <= ratio * ds + FLOAT_EPS
        failed |= not ok
        cells.append({"cell": u["cell"], "arm": arm, "n": n,
                      "den_seconds": ds, "num_seconds": us,
                      "ratio": (us / ds if ds else None), "passed": ok})
    return {"verdict": "FAIL" if failed else "PASS", "cells": cells, "why": []}


# --------------------------------------------------- P-2 TP-only non-regression --

def _prf(tp, fp, fn):
    """Frozen metric conventions (scoring slice): count-pooled, zero-safe."""
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) else 0.0
    return prec, rec, f1


def _pool(rows, tool, arm, n):
    """Count-pool the per-rep cell rows of one class; None when absent."""
    acc = None
    for r in rows:
        if (r.get("row_type", "cell") == "cell"
                and r.get("tool") == tool and r["arm"] == arm
                and int(r["N"]) == int(n)):
            tp, fp, fn = (int(r["tp"]), int(r["fp"]), int(r["fn"]))
            acc = [0, 0, 0] if acc is None else acc
            acc[0] += tp
            acc[1] += fp
            acc[2] += fn
    return tuple(acc) if acc is not None else None


def _matched_set(rows, tool, arm, n):
    """The committed TP judgment surface for one class: the matcher's own
    verdict per signature (PI ruling D2 — matched/false_called/missed)."""
    return {r["signature"] for r in rows
            if r.get("row_type") == "signature" and r.get("tool") == tool
            and r["arm"] == arm and int(r["N"]) == int(n)
            and r.get("status") == "matched"}


def tp_only_regression_verdict(baseline_rows, arm_rows, classes_by_tool,
                               *, tol=0.02):
    """Every judged class of every arm under test must hold precision/recall/f1
    within tol of the baseline (count-pooled), and must not flip any
    signature's matched status against the baseline's judgment set.

    classes_by_tool: {tool: [(arm, n), ...]} — adjudication passes judged
    classes only. REFUSE on missing baseline or missing arm data (no data, no
    claim); FAIL names the class and its flipped signatures."""
    base_tools = {r.get("tool") for r in baseline_rows
                  if r.get("row_type", "cell") == "cell"}
    if len(base_tools) != 1:
        return {"verdict": "REFUSE", "cells": [],
                "why": [f"baseline spans {sorted(base_tools)}; exactly one "
                        f"baseline tool is admissible"]}
    bt = base_tools.pop()
    cells, refusals, failed = [], [], False
    for tool, classes in classes_by_tool.items():
        for arm, n in classes:
            b, a = _pool(baseline_rows, bt, arm, n), _pool(arm_rows, tool, arm, n)
            if b is None or a is None:
                refusals.append(f"{tool}|{arm}/N{n}: "
                               + ("baseline" if b is None else "arm")
                               + " class rows absent — cannot adjudicate")
                continue
            bp, br, bf = _prf(*b)
            ap, ar, af = _prf(*a)
            metric_ok = (ap >= bp - tol - FLOAT_EPS and ar >= br - tol
                         and af >= bf - tol)
            flips = sorted(_matched_set(baseline_rows, bt, arm, n)
                           ^ _matched_set(arm_rows, tool, arm, n))
            passed = metric_ok and not flips
            failed |= not passed
            cells.append({"tool": tool, "arm": arm, "n": n, "passed": passed,
                         "flips": flips,
                         "why": ([] if passed else
                                 ([] if metric_ok else ["metric below floor"])
                                 + ([f"judgment flip: {f}" for f in flips]))})
    if refusals:
        return {"verdict": "REFUSE", "cells": cells, "why": refusals}
    return {"verdict": "FAIL" if failed else "PASS", "cells": cells, "why": []}


# ------------------------------------------------------------ P-3 attribution --

#: (stage key, numerator tool, denominator tool, note) — the pre-registered
#: decomposition. Every entry names MEASURED arms only; no phantom 4th arm,
#: no config toggle (manifest §5 P-3).
ATTRIBUTION_STAGES = (
    ("legacy_to_233", "sigminer", "sigminer_pre_v3",
     "whole 2.3.1 -> 2.3.3 delta incl. the #479 era (see amendment A1)"),
    ("phase_p1_r", "sigminer_pre_v3", "sigminer_post_p1",
     "kernel-boundary phase cost on the R path"),
    ("kernel_face", "sigminer_post_p1", "sigminer_post_p1_rust",
     "certified-kernel share of the same tree"),
    ("phase_p2_ka", "sigminer_post_p1", "sigminer_post_p2",
     "K-arbitration port"),
    ("phase_p0_p3", "sigminer_post_p2", "sigminer_post_v3",
     "P0-P3 tip delta"),
    ("tip_face", "sigminer_post_v3", "sigminer_post_v3_rust",
     "certified-kernel share at the tip (parity-gate face)"),
)


def attribution_split(rows, *, n, arms=("main",)):
    """Machine-computed stage ratios from the campaign table only.

    For each stage the ratio is the WORST per-class ratio over the classes
    both stage arms carry ok rows for at this N (a stage is as slow as its
    worst cell — averaging cannot launder a hotspot). REFUSE when a stage has
    no shared class or any contributing row is not a measurement."""
    by_tool = {tool: _index(rows, tool=tool) for tool in
               {t for stage in ATTRIBUTION_STAGES for t in stage[1:3]}}
    stages, refusals = {}, []
    for key, num_t, den_t, note in ATTRIBUTION_STAGES:
        num_i, den_i = by_tool.get(num_t, {}), by_tool.get(den_t, {})
        shared = [arm for arm in arms
                  if (arm, n) in num_i and (arm, n) in den_i]
        if not shared:
            refusals.append(f"stage {key}: no shared ok class for "
                           f"{num_t} vs {den_t} at N={n}")
            continue
        ratios = []
        for arm in shared:
            u, d = num_i[(arm, n)], den_i[(arm, n)]
            if u.get("status") != "ok" or d.get("status") != "ok":
                refusals.append(f"stage {key}|{arm}/N{n}: non-ok contributing row")
                continue
            ratios.append({"arm": arm,
                           "ratio": float(u["seconds"]) / float(d["seconds"])})
        if len(ratios) != len(shared):
            continue
        stages[key] = {"note": note, "numerator": num_t, "denominator": den_t,
                       "ratio": max(r["ratio"] for r in ratios),
                       "per_class": ratios}
    if refusals:
        return {"verdict": "REFUSE", "stages": stages, "why": refusals}
    return {"verdict": "OK", "stages": stages, "why": []}


# ------------------------------------------------------------------- yardstick --

def yardstick_status(measured, *, pending_reason, evidence_path):
    """The rust-NMF yardstick two-state law: MEASURED (both sides produced
    bytes here) or LEDGERED-PENDING (spoken reason + fetch evidence). The
    paper's 76-280x claims stay UNMEASURED in committed text until the
    MEASURED branch itself produces the fixture bytes."""
    if measured is not None:
        if pending_reason or evidence_path:
            raise ValueError("yardstick states are exclusive: measured data "
                             "arrived beside pending evidence")
        try:
            rust = float(measured["rust_seconds"])
            rr = float(measured["r_seconds"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"yardstick needs both sides measured "
                             f"(rust_seconds, r_seconds), got {exc}") from None
        if rust <= 0 or rr <= 0:
            raise ValueError("yardstick timings must be positive measurements")
        return {"state": "MEASURED", "ratio": rr / rust,
                "rust_seconds": rust, "r_seconds": rr}
    if not pending_reason or not evidence_path:
        raise ValueError("a skipped yardstick must speak the sanctioned ledger "
                         "language: reason code + evidence path (Skip Law)")
    return {"state": "LEDGERED-PENDING", "reason": pending_reason,
            "evidence_path": evidence_path}
