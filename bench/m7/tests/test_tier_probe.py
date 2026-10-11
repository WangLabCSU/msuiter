#!/usr/bin/env python3
"""GO-05 tier-oracle amendment: report-only fits report, consumed fits govern
(controller ruling @10:45 on the tier-probe halt; RB-09 doctrine: principle,
not outcome).

The single-source-of-laws law stays total: the non-physical fit law bites
EVERYWHERE a fit is consumed (the decision's A1 budget, its projections, the
floor gate's projection). It must never act as a silent veto over a
report-only payload: tonight's death was A2's report-only fit raising
through the decision's fits comprehension, where the code's own comment
says "A1 gates the budget". Hence:

  --decide        A1 fit failing the physical/structural test -> rc 2
                  (consumed). A2/A3 failing fits become report entries
                  {"fit_status": "non-identifiable-at-probe-scale", ...}
                  WITHOUT raising: the decision rc and the A1-governed
                  tier/cap/projections are INVARIANT to every A2/A3 fit
                  state (pristine, non-identifiable, structurally unusable,
                  absent) -- pinned as byte-equality below.
  --floor-check   gate from the arm's probe fit; a physically clean fit
                  verdicts rc 0/4 exactly as before; a provably
                  non-identifiable fit is the UNMEASURABLE leg (dedicated
                  rc 3, ruling @12:50 -- the gate records, it never vetoes;
                  group (X) owns that law); missing or structural bytes
                  still hard-refuse (rc 2) via the committed governance-
                  table ladder and NEVER on a fabricated floor.

Frozen-shape bar: S_PROBE/R_PROBE and the protocol SS2 sampling constants
are untouchable -- no R-bump, no identifiability-eps, no rate-sign carve-out.
The new --tier-probe rehearsal mode rides census+data+probes+decide at the
full shape and quits before any timed arm, claim-free, ledger-invisible to
the RB-10 shot counter. Group (W) of the m7 suite; the harness toolbox is
reused from the (U) group.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
from tools import verify_campaign as vc                         # noqa: E402
from tests import test_anchor_probe as ap                      # noqa: E402

# The probe shape the harness runs (frozen protocol mirror) and tonight's
# verbatim sigminer-main witness walls: the halt is evidence, its bytes are
# the golden regression.
S_PROBE, R_LO, R_HI = 5, 10, 20
TONIGHT_LO = [0.884, 0.869, 0.889]
TONIGHT_HI = [0.914, 0.873, 0.864]
TONIGHT_RATE = (0.873 - 0.884) / (S_PROBE * (R_HI - R_LO))      # -0.00022...
TONIGHT_P = (0.884 - TONIGHT_RATE * S_PROBE * R_LO) / S_PROBE   # 0.179...
A1_CLEAN = (1.1, 2.1)      # rate 0.02, p 0.02: tier-A, physically clean


def _probe_walls(arm: str, lo_walls: list[float] | None,
                 hi_walls: list[float] | None) -> str:
    def rows(reps: int, walls: list[float]) -> list[str]:
        return [json.dumps({"kind": "probe", "arm": arm,
                            "shape": {"S": S_PROBE, "R": reps},
                            "wall": w, "cpu": w, "rep": i})
                for i, w in enumerate(walls, 1)]
    out = (rows(R_LO, lo_walls) if lo_walls is not None else []) \
        + (rows(R_HI, hi_walls) if hi_walls is not None else [])
    return "".join(r + "\n" for r in out)


def _clean(med_lo: float, med_hi: float) -> tuple[list[float], list[float]]:
    return ([med_lo - 0.01, med_lo, med_lo + 0.01],
            [med_hi - 0.01, med_hi, med_hi + 0.01])


def _decide_fixture(parent: str, tag: str, variants: dict[str, object]) -> Path:
    """A campaign dir whose witnesses/ carry exactly the given arm->walls map
    (None => no witness file at all; (walls, None) => the R_LO shape only)."""
    d = Path(parent) / tag / "campaign"
    (d / "witnesses").mkdir(parents=True, exist_ok=True)
    for arm, spec in variants.items():
        if spec is None:
            continue
        lo, hi = (spec, spec) if not isinstance(spec, tuple) else spec
        (d / "witnesses" / f"probe_{arm}_1.jsonl").write_text(
            _probe_walls(arm, lo, hi), encoding="utf-8")
    return d


# -- (W1) golden regression: tonight's verbatim A2 bytes, reported not raised ----
def test_tonight_a2_reports_not_raises() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _decide_fixture(tmp, "w1", {"A1": _clean(*A1_CLEAN),
                                       "A2": (TONIGHT_LO, TONIGHT_HI),
                                       "A3": _clean(0.9, 1.0)})
        proc = ap._vc_cli("--campaign", str(d), "--decide")
        assert proc.returncode == 0, \
            f"report-only A2 must not veto the decision: {proc.stdout}"
        out = json.loads(proc.stdout)
        a2 = out["fits"]["A2"]
        assert a2["fit_status"] == "non-identifiable-at-probe-scale"
        assert a2["rate"] == TONIGHT_RATE and a2["p"] == TONIGHT_P
        a1 = out["fits"]["A1"]
        assert a1["fit_status"] == "ok"
        assert abs(a1["rate"] - 0.02) < 1e-12, a1      # float law, not equality law
        assert abs(a1["p"] - 0.02) < 1e-12, a1
        assert out["tier"] == "A"


# -- (W2) decision invariance: A1-governed bytes identical across report states --
def test_decision_is_invariant_to_report_only_fits() -> None:
    states = {"pristine": _clean(0.9, 1.0),
              "tonight": (TONIGHT_LO, TONIGHT_HI),
              "absent": None,
              "single-shape": ([0.9] * 3, None)}
    digests = []
    with tempfile.TemporaryDirectory() as tmp:
        for la, a2 in states.items():
            for lb, a3 in states.items():
                d = _decide_fixture(tmp, f"inv-{la}-{lb}",
                                    {"A1": _clean(*A1_CLEAN), "A2": a2,
                                     "A3": a3})
                proc = ap._vc_cli("--campaign", str(d), "--decide")
                assert proc.returncode == 0, f"{la}/{lb}: {proc.stdout}"
                out = json.loads(proc.stdout)
                consumed = {k: out[k] for k in ("tier", "cap", "projections")}
                consumed["fit_A1"] = out["fits"]["A1"]
                digests.append(json.dumps(consumed, sort_keys=True))
    assert len(set(digests)) == 1, "the decision drifted on report-only payload"


# -- (W3) the consumed law still bites: non-physical A1 keeps the veto -----------
def test_non_physical_a1_still_refuses() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _decide_fixture(tmp, "w3", {"A1": (TONIGHT_LO, TONIGHT_HI),
                                       "A2": _clean(0.9, 1.0),
                                       "A3": _clean(0.9, 1.0)})
        proc = ap._vc_cli("--campaign", str(d), "--decide")
        assert proc.returncode == 2, \
            f"a consumed non-physical fit must still refuse: {proc.stdout}"
        out = json.loads(proc.stdout)
        assert out["ok"] is False and "A1" in out["error"]
        assert (f"non-physical cost fit: p={TONIGHT_P} rate={TONIGHT_RATE}"
                in out["error"]), f"legacy verbatim error text: {out['error']}"


# -- (W4) missing A1 witnesses is a consumed-side refusal --------------------------
def test_missing_a1_witnesses_refuse() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _decide_fixture(tmp, "w4", {"A1": None, "A2": _clean(0.9, 1.0),
                                        "A3": _clean(0.9, 1.0)})
        proc = ap._vc_cli("--campaign", str(d), "--decide")
        assert proc.returncode == 2
        assert json.loads(proc.stdout)["ok"] is False


# -- (W5) the floor gate never stands on a non-physical fit --------------------------
def test_floor_check_falls_back_never_on_bad_fit() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _decide_fixture(tmp, "w5", {"A1": _clean(*A1_CLEAN),
                                        "A2": (TONIGHT_LO, TONIGHT_HI)})
        good = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A1",
                          "--observed", "0.5", "--reps", "200")
        assert good.returncode == 0, good.stdout
        body = json.loads(good.stdout)
        assert body["gate"] == "pass" and body["floor_source"] == "probe-fit"
        bad = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A2",
                         "--observed", "0.5", "--reps", "200")
        assert bad.returncode == 3, \
            f"tonight's non-identifiable leg is the @12:50 UNMEASURABLE class: {bad.stdout}"
        why = json.loads(bad.stdout)
        assert why["ok"] is True and why["floor_gate"] == "unmeasurable" \
            and why["arm"] == "A2"
        absent = _decide_fixture(tmp, "w5h", {"A1": _clean(*A1_CLEAN)})
        hard = ap._vc_cli("--campaign", str(absent), "--floor-check",
                          "--arm", "A2", "--observed", "0.5", "--reps", "200")
        assert hard.returncode == 2, \
            f"no bytes at all stays a hard refusal, never an unmeasurable pass: {hard.stdout}"
        err = json.loads(hard.stdout)["error"]
        assert "governance floor" in err and "A2" in err


# -- (W6) the frozen-shape bar -------------------------------------------------------
def test_frozen_probe_shape_untouched() -> None:
    src = ap._campaign_src()
    assert "S_PROBE <- 5L; R_PROBE <- c(10L, 20L)" in src, \
        "the probe shape is protocol-frozen: no R-bump, no eps-tuning"
    assert "SEED <- 20260928L" in src
    assert "--identifiability" not in src and "--rate-floor" not in src


# -- (W7) the --tier-probe rehearsal mode ((U)-group discipline) ----------------------
def test_tier_probe_mode_laws() -> None:
    src = ap._campaign_src()
    assert re.search(r'tierProbe\s*<-\s*!is\.na\(match\("--tier-probe",'
                     r' args\)\)', src), "valueless switch, house arg idiom"
    assert re.search(r"if \(tierProbe && \(smoke \|\| mode != \"full\"\)\)"
                     r" abort", src), "pairing guard missing"
    assert "tierProbe && dir.exists(outdir)" in src, "fresh-outdir guard missing"
    line = [ln for ln in src.splitlines()
            if '"kind":"tier-probe","grade":"calibration"' in ln]
    assert len(line) == 1 and '"mode"' not in line[0], \
        "the tier-probe ledger line must carry no mode key (shot-counter law)"
    parts = src.split("if (tierProbe) {", 1)
    assert len(parts) == 2, "tier-probe dispatch missing"
    tail = parts[1].split("\n}\n", 1)[0]           # to the block's own close
    assert "quit(status = 0L)" in tail, "the rehearsal must exit zero, not die"
    assert "call_oracle_rc(character(0))" in tail, "reader pass required"
    for banned in ('append_ledger("full")', "--launch-gate", "arm_A",
                   "ratio(A1/A2)", "--floor-check"):
        assert banned not in tail, f"the rehearsal path must never touch {banned}"


def test_tier_probe_refusals_executed() -> None:
    if not ap.RSCRIPT:
        print("  [skip] Rscript absent")
        return
    src = ap._campaign_src()
    # Fail-safe pre-flight: executed harness calls run real programs, so they
    # proceed only once the mode AND both guards exist -- until then the
    # unknown switch could ride past into a real campaign (witnessed live in
    # the RED phase; never again).
    if ('--tier-probe' not in src
            or 'tierProbe && (smoke || mode != "full")' not in src
            or 'tierProbe && dir.exists(outdir)' not in src):
        print("  [skip] tier-probe guards not all in place yet")
        return
    with tempfile.TemporaryDirectory() as tmp:
        for label, argv in (("pilot", ["--mode", "pilot", "--tier-probe"]),
                            ("smoke", ["--mode", "pilot", "--smoke",
                                       "--tier-probe"])):
            d = Path(tmp) / f"ref-{label}"
            out = ap._harness(["--outdir", str(d), *argv])
            assert out.returncode == 2, \
                f"{label} pairing must refuse, rc={out.returncode}\n{out.stdout}"
            assert "--tier-probe" in out.stdout + out.stderr, \
                f"{label}: the refusal must name the mode\n{out.stdout}"
        d = Path(tmp) / "dirty"
        d.mkdir()
        (d / "campaign.rds").write_bytes(b"stale-bytes\n")
        out = ap._harness(["--outdir", str(d), "--mode", "full",
                           "--tier-probe"])
        assert out.returncode == 2 and "--tier-probe" in out.stdout + out.stderr, \
            f"dirty-outdir refusal expected\n{out.stdout}"


def test_tier_probe_md_is_claim_free() -> None:
    if not ap.RSCRIPT:
        print("  [skip] Rscript absent")
        return
    with tempfile.TemporaryDirectory() as tmp:
        dec_text = ('{"tier": "A", "fits": {"A1": {"p": 0.02,'
                    ' "rate": 0.02}}, "projections": {"A": 20020.0}}')
        (Path(tmp) / "seal.json").write_text('{"sha256": "fixture"}\n',
                                             encoding="utf-8")
        program = ap._capture_defs(str(ap.CAMPAIGN),
                                   ["write_tier_result", "say", "abort"]) + f'''
paste0 <- function(...) paste(..., collapse = "")
outdir <- "{tmp}"
K <- 1000L; S <- 1000L; N_SIG <- 50L
SEED <- 20260928L; CAMPAIGN_HW_PIN <- "{ap.HW_PROFILE}"
host_name <- function() "fixture-host"
R <- list(version.string = "9.9.9")
S_PROBE <- 5L; R_PROBE <- c(10L, 20L)   # the frozen shape, as the (W6) bar pins
get("write_tier_result", env)('{dec_text}')
'''
        ap._r(program)
        text = (Path(tmp) / "result.md").read_text(encoding="utf-8")
        assert "tier-probe (not a claim)" in text
        assert dec_text in text          # oracle verbatim, never re-typed
        assert "ratio(A1/A2)" not in text
        claims = vc._parse_result_md(text)
        assert claims["ratio"] is None and claims["verdict"] is None, \
            f"the reader must not be able to read this as a claim: {claims}"


def test_tier_probe_ledger_invisible_to_shot_counter() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        line = '{"kind":"tier-probe","grade":"calibration","ts":"x"}\n'
        d = ap._fixture_campaign(str(Path(tmp) / "l1"), ledger=line)
        proc = ap._vc_cli("--campaign", str(d), "--launch-gate", "--mode",
                          "full")
        assert proc.returncode == 0 and json.loads(proc.stdout)["allowed"] \
            is True, f"the rehearsal entry must not count as a shot: {proc.stdout}"
        d2 = ap._fixture_campaign(
            str(Path(tmp) / "l2"),
            ledger=line + '{"kind":"launch","mode":"full","ts":"y"}\n')
        blocked = ap._vc_cli("--campaign", str(d2), "--launch-gate", "--mode",
                             "full")
        assert blocked.returncode == 3, "the one-shot law still binds real shots"
