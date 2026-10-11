#!/usr/bin/env python3
"""Reader-side verifier + decision oracle for the bootstrap-vs-sigminer campaign.

(U-M7-04 GO-05, charter SCOPE B.) The campaign's claims are only as good as the
witness bytes behind them: this tool re-derives every number in result.md from
the witnesses themselves — R is not trusted after the fact, exactly as
verify_hardware_pin.py verdicts a timings table from its own CSV columns. It is
also the SINGLE SOURCE OF LAWS the R harness calls (decide-tier, launch-gate),
so the measurement side and the reader side can never drift apart.

The SCIENCE-FIRST LAW is machine-enforced here: an inflated ratio claim, a
MEASURED verdict riding over a failed anchor, a self-adjudicating probe
witness, an unpinned campaign table, or a second full launch into one campaign
dir are each a refusal, not a warning.

Usage:
    python3 -m tools.verify_campaign --campaign <dir> [--host H] [--hw-profile P]
    python3 -m tools.verify_campaign --decide      --campaign <dir> [--cap 21600]
    python3 -m tools.verify_campaign --launch-gate --campaign <dir> --mode full
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import timings                     # noqa: E402
from tools import matrix_governance as gov          # noqa: E402

# Frozen protocol constants (docs/devlog/2026-10-10-m7-bootstrap-campaign.md §2)
S_FULL, N_SIG, K_FULL = 1000, 50, 1000
R_TIER_A, R_TIER_B = 1000, 200
CAP_SECONDS = 21600                                  # six hours, the pre-registered cap
ANCHOR_S, ANCHOR_R = 25, 200
MIN_OVERLAP, MIN_MEDIAN_OK = 0.90, 0.95
# GO-05 amendment (controller ruling @09:45, RB-09 doctrine): the median clause
# is a CI-noise envelope, not a flat relative tolerance -- a relative tolerance
# explodes at near-zero estimands, which is a property of the definition, not
# of the data. Both constants are fixed a-prior; see
# docs/devlog/2026-10-11-go05-anchor-gate-amendment.md for the verbatim
# retired outcome and the K_CI/EPS a-prior provenance.
K_CI = 1.0                                             # envelope multiple
EPS = 0.005                                            # both-below auto-pass floor
CLAIM_REL_TOL = 1e-9
ARMS = ("A1", "A2", "A3")
# Base bytes every lawful campaign dir must carry, whatever its verdict. The
# heavy artifacts (arm witnesses, table, anchors) are claim-conditional: a
# Tier-C UNMEASURED campaign legitimately never produced them.
REQUIRED = ("seal.json", "campaign.rds", "campaign_launches.jsonl")


def read_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        raise FileNotFoundError(str(path))
    return [json.loads(line) for line in
            path.read_text(encoding="utf-8").splitlines() if line.strip()]


# -- the cost model (probe medians -> tier decision) ----------------------------------
def fit_cost_model(probes: list[dict]) -> dict:
    """Two probe shapes (same S, R_lo<R_hi) pin the linear model
    wall = S*(p + rate*R): med_hi-med_lo = rate*S*(R_hi-R_lo)."""
    if not probes:
        raise ValueError("fit_cost_model: no probe records")
    by_shape: dict[tuple, list[float]] = {}
    for r in probes:
        s, rep_n = r["shape"]["S"], r["shape"]["R"]
        by_shape.setdefault((s, rep_n), []).append(float(r["wall"]))
    if len({s for s, _ in by_shape}) != 1:
        raise ValueError(f"probe shapes disagree on S: {sorted(by_shape)}")
    s = next(iter(by_shape))[0]
    if len(by_shape) != 2:
        raise ValueError(f"exactly two probe shapes required, got {sorted(by_shape)}")
    (s, r_lo), m_lo = sorted(by_shape.items())[0]
    (_, r_hi), m_hi = sorted(by_shape.items())[1]
    if r_hi == r_lo:
        raise ValueError("probe replicate counts are identical; cannot identify rate")
    med_lo, med_hi = statistics.median(m_lo), statistics.median(m_hi)
    rate = (med_hi - med_lo) / (s * (r_hi - r_lo))
    p = (med_lo - rate * s * r_lo) / s
    if rate < 0 or p < 0:
        raise ValueError(f"non-physical cost fit: p={p} rate={rate}")
    return {"p": p, "rate": rate, "shapes": sorted(by_shape)}


def project_wall(fit: dict, S: int = S_FULL, reps: int = R_TIER_A) -> float:
    return S * (fit["p"] + fit["rate"] * reps)


def decide_tier(fit: dict, cap: float = CAP_SECONDS) -> str:
    if project_wall(fit, reps=R_TIER_A) <= cap:
        return "A"
    if project_wall(fit, reps=R_TIER_B) <= cap:
        return "B"
    return "C"


# -- the correctness anchor (before any ratio may be spoken) --------------------------
def anchor_gates(a1: list[dict], a2: list[dict]) -> dict:
    key = lambda r: (r["sample"], r["sig"])
    k1, k2 = map(key, a1), map(key, a2)
    if len(a1) == 0 or sorted(k1) != sorted(k2):
        return {"ok": False, "reason": "cell-set mismatch or empty anchor",
                "n_cells": min(len(a1), len(a2)), "overlap_frac": 0.0,
                "median_ok_frac": 0.0, "n_failed_overlap": len(a1)}
    m2 = {key(r): r for r in a2}
    overlap = median_ok = 0
    for r1 in a1:
        r2 = m2[key(r1)]
        if not (float(r1["hi"]) < float(r2["lo"]) or float(r2["hi"]) < float(r1["lo"])):
            overlap += 1
        a1m, a2m = float(r1["median"]), float(r2["median"])
        hw1 = (float(r1["hi"]) - float(r1["lo"])) / 2.0
        hw2 = (float(r2["hi"]) - float(r2["lo"])) / 2.0
        # CI-noise-envelope clause (amended; constants fixed a-prior above):
        # the two bootstrap medians must sit within K_CI of the larger CI
        # half-width; a pair with both medians under EPS is indistinguishable
        # from zero and auto-passes the median leg.
        if (abs(a1m) < EPS and abs(a2m) < EPS) \
                or abs(a1m - a2m) <= K_CI * max(hw1, hw2):
            median_ok += 1
    n = len(a1)
    of, mf = overlap / n, median_ok / n
    return {"ok": of >= MIN_OVERLAP and mf >= MIN_MEDIAN_OK,
            "n_cells": n, "overlap_frac": of, "median_ok_frac": mf,
            "n_failed_overlap": n - overlap}


# -- the single-shot ledger law ---------------------------------------------------------
def launch_gate(ledger: Path, mode: str) -> bool:
    """RB-10/RB-11(ii): exactly ONE full shot per campaign dir; pilots are free."""
    try:
        entries = read_jsonl(ledger)
    except FileNotFoundError:
        return True
    fulls = sum(1 for e in entries if e.get("mode") == "full")
    return mode != "full" or fulls == 0


# -- the claim re-derivation --------------------------------------------------------------
def _parse_result_md(text: str) -> dict:
    out = {"tier": None, "ratio": None, "verdict": None}
    for line in text.splitlines():
        s = line.strip().lstrip("-").strip()
        if s.startswith("tier:"):
            out["tier"] = s.split(":", 1)[1].strip()
        elif s.startswith("ratio(A1/A2)"):
            rhs = s.split("=", 1)[1].strip()
            try:
                out["ratio"] = float(rhs)
            except ValueError:
                out["ratio"] = rhs                      # kept for the refusal message
        elif s.startswith("verdict:"):
            out["verdict"] = s.split(":", 1)[1].strip()
    return out


def _last_arm(path: Path) -> dict:
    recs = [r for r in read_jsonl(path) if r.get("kind") == "arm"]
    if len(recs) != 1:                                 # the single-shot law, again
        raise ValueError(f"{path.name}: expected exactly one arm witness, {len(recs)} found")
    return recs[0]


# -- the verdict assembly -----------------------------------------------------------------
def verdict_for(campaign: Path, host: str, hw_profile: str) -> tuple[int, dict]:
    checks: list[dict] = []
    def note(name: str, ok: bool, detail: str = "") -> bool:
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        return ok

    missing = [f for f in REQUIRED if not (campaign / f).is_file()]
    if missing:
        return 2, {"ok": False, "error": f"unreadable campaign, missing: {missing}"}

    seal = json.loads((campaign / "seal.json").read_text(encoding="utf-8"))
    digest = hashlib.sha256((campaign / "campaign.rds").read_bytes()).hexdigest()
    note("seal-sha256", digest == seal.get("sha256"), f"data bytes {digest[:16]}...")

    probe_ok = True
    for arm in ARMS:
        for p in sorted((campaign / "witnesses").glob(f"probe_{arm}_*.jsonl")):
            for rec in read_jsonl(p):
                if "verdict" in rec or "gate" in rec:
                    probe_ok = False
                    break
    note("probe-purity", probe_ok, "probe witnesses measure, never adjudicate")

    fulls = sum(1 for e in read_jsonl(campaign / "campaign_launches.jsonl")
                if e.get("mode") == "full")
    note("launch-ledger", fulls <= 1,
         f"{fulls} full shot(s) on the ledger — at most one is lawful (RB-10); a "
         "MEASURED claim additionally requires exactly one (via its arm witnesses)")

    result_md = campaign / "result.md"
    claims = _parse_result_md(result_md.read_text(encoding="utf-8")) \
        if result_md.is_file() else {"tier": None, "ratio": None, "verdict": None}
    verdict = claims["verdict"] or "UNMEASURED-with-pilot"
    measured = verdict.startswith("MEASURED")

    arms: dict[str, dict] = {}
    recomputed: dict[str, float] = {}
    anchor: dict | None = None
    table = campaign / "campaign_timings.csv"
    if measured:
        # A MEASURED claim is where the heavy laws bite: arms, floor gates,
        # the pinned table, the anchor — all required, all re-derived.
        note("full-shot-on-ledger", fulls == 1,
             f"a MEASURED claim needs its one authoritative full shot on the "
             f"ledger ({fulls} present)")
        try:
            for arm in ARMS:
                arms[arm] = _last_arm(campaign / "witnesses" / f"arm_{arm}.jsonl")
        except (ValueError, FileNotFoundError) as exc:
            return 2, {"ok": False,
                       "error": f"a MEASURED claim without full arm witnesses: {exc}"}
        note("floor-gates", all(a.get("gate") == "pass" for a in arms.values()),
             "3x-projection sanity gate passed per arm witness")
        if not table.is_file():
            note("nine-column-pins", False, "MEASURED claim with no campaign table")
        else:
            note("nine-column-pins", gov.hardware_pin_verdict(
                timings.read_timings(table), host=host, hw_profile=hw_profile)["ok"],
                "campaign table attests its machine from its own bytes")
        anchor = anchor_gates(
            read_jsonl(campaign / "witnesses" / "anchor_A1.jsonl"),
            read_jsonl(campaign / "witnesses" / "anchor_A2.jsonl"))
        note("anchor-gates", anchor["ok"], json.dumps(anchor))
        recomputed = {"ratio": arms["A1"]["wall"] / arms["A2"]["wall"],
                      "secondary_ratio": arms["A1"]["wall"] / arms["A3"]["wall"]}
    else:
        # UNMEASURED is never refused; artifacts, where present, stay lawful.
        if table.is_file():
            note("nine-column-pins", gov.hardware_pin_verdict(
                timings.read_timings(table), host=host, hw_profile=hw_profile)["ok"],
                "campaign table attests its machine from its own bytes")
        a1p = campaign / "witnesses" / "anchor_A1.jsonl"
        a2p = campaign / "witnesses" / "anchor_A2.jsonl"
        if a1p.is_file() and a2p.is_file():
            # The anchor failure IS the sanctioned UNMEASURED-with-pilot reason,
            # so here the gate result is disclosed, not binding.
            anchor = anchor_gates(read_jsonl(a1p), read_jsonl(a2p))
            note("anchor-gates-informational", True, json.dumps(anchor))

    if claims["ratio"] is not None:
        if not measured:
            note("ratio-fidelity", False,
                 "an UNMEASURED campaign may not carry a ratio(A1/A2) claim line")
        else:
            try:
                close = abs(float(claims["ratio"]) - recomputed["ratio"]) \
                    <= CLAIM_REL_TOL * max(recomputed["ratio"], 1e-12)
                note("ratio-fidelity", close,
                     f"claimed {claims['ratio']!r} vs recomputed {recomputed['ratio']!r}")
            except (TypeError, ValueError):
                note("ratio-fidelity", False,
                     f"unparsable claimed ratio {claims['ratio']!r}")

    if verdict.startswith("MEASURED-true"):
        note("measured-true-holds", anchor["ok"] and recomputed["ratio"] >= 100.0,
             f"ratio {recomputed['ratio']!r}, anchor ok={anchor['ok']}")
    elif verdict.startswith("MEASURED-false"):
        has_number = any(ch.isdigit() for ch in verdict)
        note("measured-false-holds", anchor["ok"] and recomputed["ratio"] < 100.0
             and has_number,
             f"ratio {recomputed['ratio']!r}, number stated={has_number}")

    ok = all(c["ok"] for c in checks)
    return (0 if ok else 1), {"ok": ok, "checks": checks,
                              "recomputed": recomputed, "claims": claims}


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="verify_campaign")
    ap.add_argument("--campaign", required=True)
    ap.add_argument("--host", default=socket.gethostname())
    ap.add_argument("--hw-profile", default=None)
    ap.add_argument("--decide", action="store_true")
    ap.add_argument("--launch-gate", dest="launch_gate", action="store_true")
    ap.add_argument("--floor-check", dest="floor_check", action="store_true")
    ap.add_argument("--anchor-check", dest="anchor_check", action="store_true")
    ap.add_argument("--arm", default=None, choices=ARMS)
    ap.add_argument("--observed", type=float, default=None)
    ap.add_argument("--reps", type=int, default=None)
    ap.add_argument("--mode", default="full", choices=("full", "pilot"))
    ap.add_argument("--cap", type=float, default=CAP_SECONDS)
    return ap.parse_args(argv)


def _arm_fit(campaign: Path, arm: str) -> dict:
    probes: list[dict] = []
    for p in sorted((campaign / "witnesses").glob(f"probe_{arm}_*.jsonl")):
        probes += read_jsonl(p)
    return fit_cost_model(probes)


def main(argv: list[str] | None = None) -> tuple[int, str]:
    args = parse_args(list(sys.argv[1:] if argv is None else argv))
    campaign = Path(args.campaign)
    profile = args.hw_profile if args.hw_profile is not None \
        else os.environ.get(timings.HW_PROFILE_ENV, "")

    if args.launch_gate:
        allowed = launch_gate(campaign / "campaign_launches.jsonl", args.mode)
        return (0 if allowed else 3), json.dumps(
            {"allowed": allowed, "mode": args.mode, "campaign": str(campaign)})

    if args.decide:
        try:
            fits = {arm: _arm_fit(campaign, arm) for arm in ARMS}
        except (ValueError, FileNotFoundError) as exc:
            return 2, json.dumps({"ok": False, "error": str(exc)})
        tier = decide_tier(fits["A1"], cap=args.cap)      # A1 gates the budget
        return 0, json.dumps({"tier": tier, "fits": fits, "cap": args.cap,
                              "projections": {
                                  "A": project_wall(fits["A1"], reps=R_TIER_A),
                                  "B": project_wall(fits["A1"], reps=R_TIER_B)}})

    if args.floor_check:
        # Pre-registered 3x-floor gate, campaign-scoped, adjudicated HERE only
        # (probes and the harness measure; this oracle decides). Breach => rc 4.
        if args.arm is None or args.observed is None or args.reps is None:
            return 2, json.dumps({"ok": False, "error":
                                  "--floor-check needs --arm, --observed, --reps"})
        try:
            fit = _arm_fit(campaign, args.arm)
        except (ValueError, FileNotFoundError) as exc:
            return 2, json.dumps({"ok": False, "error": str(exc)})
        projection = project_wall(fit, reps=args.reps)
        floor = gov.FLOOR_RATIO * projection
        gate = "pass" if args.observed <= floor else "breach"
        return (0 if gate == "pass" else 4), json.dumps(
            {"arm": args.arm, "gate": gate, "observed": args.observed,
             "projection": projection, "floor": floor, "fit": fit,
             "floor_ratio": gov.FLOOR_RATIO})

    if args.anchor_check:
        try:
            anchor = anchor_gates(
                read_jsonl(campaign / "witnesses" / "anchor_A1.jsonl"),
                read_jsonl(campaign / "witnesses" / "anchor_A2.jsonl"))
        except (ValueError, FileNotFoundError) as exc:
            return 2, json.dumps({"ok": False, "error": str(exc)})
        return (0 if anchor["ok"] else 1), json.dumps(anchor)

    rc, report = verdict_for(campaign, args.host, profile)
    return rc, json.dumps(report)


if __name__ == "__main__":
    rc, out = main()
    print(out)
    sys.exit(rc)
