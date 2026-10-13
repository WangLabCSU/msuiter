#!/usr/bin/env python3
"""GO-05 anchor-gate amendment: the median clause moves from a flat relative
tolerance to a CI-noise-envelope criterion (controller ruling @09:45, RB-09
doctrine: a criterion is replaced by principle, never refitted to save a
claim, and the constants are fixed a-prior before any evaluation).

Amended per-cell median agreement (gate fractions unchanged: MIN_OVERLAP 0.90,
MIN_MEDIAN_OK 0.95):

    |med_A1 - med_A2| <= K_CI * max(ci_halfwidth_A1, ci_halfwidth_A2),
    K_CI := 1.0 fixed a-prior, no tuning;
    and if |med_A1| < EPS and |med_A2| < EPS the cell auto-passes the median
    clause, EPS := 0.005 fixed a-prior.

The retired clause |m1 - m2| / max(|m1|, 1e-12) <= MEDIAN_REL_TOL is malformed
at near-zero estimands (the probe witness proved it: 108 oracle breaches / 103
symmetric breaches, every one inside half the larger CI half-width, i.e.
statistically indistinguishable noise). These units pin BOTH directions: a
near-zero-in-noise pair that the old rule failed now passes, a true divergence
that the old (symmetric-denominator) rule would have passed now fails, the
both-zero pair auto-passes, and the boundary cells are pinned exactly.

Group (V) of the m7 suite (run_all registration). The attested probe witnesses
(determinism attestation: probe1 and probe2 anchor files are byte-identical)
are adjudicated offline by V6; the RB-10 shot is never touched here.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import tools.verify_campaign as vc                              # noqa: E402

REPO = Path(__file__).resolve().parents[3]
VERIFY_CLI = REPO / "bench" / "m7" / "tools" / "verify_campaign.py"
# The attested offline witness set for the RB-10 anchor (controller contract
# item (5)), committed as fixtures so the gate is measurable on every clean
# checkout: a witness missing from the repo is a HARD FAIL, never a silent
# skip (a /tmp-resident attestation is one macOS sweep away from zombiing V6).
# Digests pinned so V6 can never silently measure a drifted file.
ATTESTED_DIR = Path(__file__).resolve().parent / "fixtures"
ATTESTED_WITNESS_NAMES = ("go05_probe2_anchor_A1.jsonl",
                          "go05_probe2_anchor_A2.jsonl")
ATTESTED_A1_SHA = ("1fa9ed3e5c099930635e4aabcefb40baaf36330d5405be"
                   "4db864085cc4895090")
ATTESTED_A2_SHA = ("d2d9fb2fb63825a5d79870ebd19f732e574fdbf2c0c12d"
                   "5c837137c3157f663e")


# -- fixture builders -------------------------------------------------------------------
def _cell(key: str, median: float, halfwidth: float) -> dict:
    lo, hi = median - halfwidth, median + halfwidth
    return {"sample": f"s{key}", "sig": f"k{key}", "median": str(median),
            "lo": str(lo), "hi": str(hi)}


def _pair(rows1: list[tuple[float, float]], rows2: list[tuple[float, float]]
          ) -> tuple[list[dict], list[dict]]:
    assert len(rows1) == len(rows2)
    keys = [f"{i:04d}" for i in range(len(rows1))]
    return ([_cell(k, m, hw) for k, (m, hw) in zip(keys, rows1)],
            [_cell(k, m, hw) for k, (m, hw) in zip(keys, rows2)])


def _healthy(n: int) -> list[tuple[float, float]]:
    return [(1.0, 0.02)] * n


# The retired clause's tolerance, kept here as a historical fact so the
# disclosure reimplementation outlives the oracle's retirement of the constant.
LEGACY_MEDIAN_REL_TOL = 0.15


def _old_rule_breaches(a1: list[dict], a2: list[dict]) -> int:
    """Verbatim reproduction of the retired oracle clause, for disclosure."""
    m2 = {(r["sample"], r["sig"]): r for r in a2}
    n = 0
    for r in a1:
        m1 = float(r["median"])
        d = abs(m1 - float(m2[(r["sample"], r["sig"])]["median"]))
        if d / max(abs(m1), 1e-12) > LEGACY_MEDIAN_REL_TOL:
            n += 1
    return n


# -- (V1) the constants are frozen a-prior, and the old constant is retired -------------
def test_amendment_constants_frozen_apriori():
    src = (REPO / "bench" / "m7" / "tools" / "verify_campaign.py") \
        .read_text(encoding="utf-8")
    # verbatim a-prior pinning (controller ruling text, K_CI := 1.0)
    assert "K_CI = 1.0" in src
    assert "EPS = 0.005" in src
    # gate fractions unchanged (controller item (2))
    assert "MIN_OVERLAP, MIN_MEDIAN_OK = 0.90, 0.95" in src
    # retirement of the malformed clause (Necessary law: dead code is deleted)
    assert "MEDIAN_REL_TOL" not in src
    assert (vc.K_CI, vc.EPS, vc.MIN_OVERLAP, vc.MIN_MEDIAN_OK) == (1.0, 0.005,
                                                                   0.90, 0.95)


# -- (V2) near-zero-in-noise pair: old rule failed it, the envelope passes it ------------
def test_near_zero_in_noise_passes_where_old_rule_failed():
    # ten near-zero pairs: both medians under EPS -> auto-pass; five near-zero
    # pairs outside EPS whose |d| sits well inside the larger half-width.
    rows1 = [(0.008, 0.007)] * 10 + [(0.03, 0.01)] * 5 + _healthy(5)
    rows2 = [(0.0, 0.01)] * 10 + [(0.04, 0.01)] * 5 + _healthy(5)
    a1, a2 = _pair(rows1, rows2)
    # the old clause failed every near-zero cell (proven at probe scale in V6)
    assert _old_rule_breaches(a1, a2) >= 10
    g = vc.anchor_gates(a1, a2)
    assert g["n_cells"] == 20
    assert g["ok"] is True
    assert g["overlap_frac"] == 1.0
    assert g["median_ok_frac"] == 1.0          # both legs agree everywhere


# -- (V3) true divergence: old symmetric-denominator rule passed, envelope fails ---------
def test_true_divergence_fails_under_envelope():
    # m1=1.0 m2=1.10 against half-widths of 0.06: the CIs still overlap (the
    # overlap leg passes) and the symmetric relative gap is 0.10/1.10 = 0.091,
    # inside the retired 0.15 tolerance -- but the medians sit 10x apart from
    # the noise envelope, so the amended clause rejects the cell and one
    # failure over 19 sinks the gate below MIN_MEDIAN_OK.
    rows1 = [(1.0, 0.06)] + _healthy(18)
    rows2 = [(1.10, 0.06)] + _healthy(18)
    a1, a2 = _pair(rows1, rows2)
    g = vc.anchor_gates(a1, a2)
    assert g["n_cells"] == 19
    assert g["overlap_frac"] == 1.0            # isolation: overlap leg is clean
    assert g["median_ok_frac"] == 18 / 19
    assert g["ok"] is False                    # 18/19 < MIN_MEDIAN_OK


# -- (V4) both-zero auto-pass -------------------------------------------------------------
def test_both_zero_auto_passes_median_clause():
    a1, a2 = _pair([(0.0, 0.0)] * 20, [(0.0, 0.0)] * 20)
    g = vc.anchor_gates(a1, a2)
    assert g["ok"] is True
    assert g["median_ok_frac"] == 1.0


# -- (V5) boundary cells pinned exactly ---------------------------------------------------
def test_envelope_and_eps_boundaries_pinned():
    # |d| == K_CI * max(hw) exactly -> in (clause is <=)
    a1, a2 = _pair([(1.0, 0.01)] + _healthy(19), [(1.01, 0.01)] + _healthy(19))
    assert vc.anchor_gates(a1, a2)["median_ok_frac"] == 1.0
    # a hair past the envelope -> out
    a1, a2 = _pair([(1.0, 0.01)] + _healthy(19), [(1.0101, 0.01)] + _healthy(19))
    assert vc.anchor_gates(a1, a2)["median_ok_frac"] == 19 / 20
    # EPS side: 0.0049 + 0.0001 both below EPS -> auto-pass even at zero width
    a1, a2 = _pair([(0.0049, 0.0)] + _healthy(19), [(0.0001, 0.0)] + _healthy(19))
    assert vc.anchor_gates(a1, a2)["median_ok_frac"] == 1.0
    # 0.0051 is NOT below EPS and the zero-width envelopes cannot carry d -> out
    a1, a2 = _pair([(0.0049, 0.0)] + _healthy(19), [(0.0051, 0.0)] + _healthy(19))
    assert vc.anchor_gates(a1, a2)["median_ok_frac"] == 19 / 20


# -- (V6) offline adjudication of the attested probe witnesses (contract item (6)) -------
def test_attested_probe_witnesses_adjudicate_green():
    a1p, a2p = (ATTESTED_DIR / n for n in ATTESTED_WITNESS_NAMES)
    for p in (a1p, a2p):
        assert p.is_file(), (
            f"attested witness {p} missing from the repo fixtures: this gate "
            "must never degrade to a silent skip (contract item (6))")
    assert hashlib.sha256(a1p.read_bytes()).hexdigest() == ATTESTED_A1_SHA
    assert hashlib.sha256(a2p.read_bytes()).hexdigest() == ATTESTED_A2_SHA
    a1 = vc.read_jsonl(a1p)
    a2 = vc.read_jsonl(a2p)
    # verbatim old-rule disclosure: the probe outcome stands on the record
    assert len(a1) == 1250
    assert _old_rule_breaches(a1, a2) == 108        # oracle-convention count
    # amended gate: every breach sat inside half the larger CI half-width, so
    # at K_CI = 1.0 the whole cell-set agrees
    g = vc.anchor_gates(a1, a2)
    assert g["ok"] is True
    assert g["n_cells"] == 1250
    assert g["overlap_frac"] == 1.0
    assert g["median_ok_frac"] == 1.0
    # the reader-facing CLI path agrees with the in-process call
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        (d / "witnesses").mkdir()
        # the oracle's --anchor-check resolves the canonical witness names, so
        # the fixture files (repo-distinct, run-labelled) are staged under the
        # canonical reader-schema names in the temp campaign dir
        for p, canon in zip((a1p, a2p),
                            ("anchor_A1.jsonl", "anchor_A2.jsonl")):
            (d / "witnesses" / canon).write_bytes(p.read_bytes())
        proc = subprocess.run(
            [sys.executable, str(VERIFY_CLI), "--campaign", str(d),
             "--anchor-check"], capture_output=True, text=True, timeout=60)
    assert proc.returncode == 0, proc.stdout
    assert json.loads(proc.stdout)["ok"] is True
