#!/usr/bin/env python3
"""GO-05 floor-gate unmeasurable path (controller ruling @12:50; RB-09 doctrine:
principle, not outcome).

THE HAZARD, verbatim from the ruling: two same-seed, byte-identical-sealed
observations (the frozen shot and the rehearsal) gave A2's probe fit rate
-0.0002200000000000002 and +8.000000000000007e-05 — the sign is random
under wall jitter at the frozen probe shape. A 3x floor built on such a fit
is a coin flip, and tonight's residual — the floor oracle rc 2 aborting the
campaign at the timed site — would spend the ONE lawful shot to enforce that
coin flip. The decide defect, transplanted into the timed path.

THE RULING's contract, pinned here:
  (1) oracle  --floor-check with a probe fit that comes back
      fit_status==NON_IDENTIFIABLE returns the dedicated payload
      {"ok":true,"floor_gate":"unmeasurable","arm":...,"reason":
      "probe-fit non-identifiable at probe scale","fit":<verbatim report>}
      with NEW DEDICATED rc 3. rc 2 stays reserved for genuine hard refusals
      (missing args, missing witnesses, structural). rc 0/4 byte-untouched.
  (2) instrument accepts {0,4} PLUS rc 3: the arm witness records
      "gate":"UNMEASURED(probe-fit non-identifiable)" plus the oracle's
      reason, and the campaign CONTINUES. Every other rc still aborts
      verbatim; rc 3 is inert at every other oracle site.
  (3) the A1 consumed law is untouched ((W) group pins it).
  (4) the MEASURED-true hold law is untouched; the unmeasurable leg is
      DISCLOSED: marker verbatim in the arm witness, visible in result.md.
  (5) CAMPAIGN_FLOOR_CLASSES stays committed EMPTY — the unmeasurable path
      supersedes the (never-fired) governance-table fallback.

Group (X) of the m7 suite; the (U) toolbox and the (W) golden bytes are
reused, and the contested (A) module is imported read-only for its complete
campaign builder.
"""

from __future__ import annotations

import json
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))          # bench/m7
from tools import matrix_governance as gov                             # noqa: E402
from tools import verify_campaign as vc                                # noqa: E402
from tests import test_anchor_probe as ap                              # noqa: E402
from tests import test_bootstrap_campaign as bc                        # noqa: E402
from tests import test_tier_probe as tp                                # noqa: E402

# the verbatim ruling strings — law text, not style choices
GATE_MARKER = "UNMEASURED(probe-fit non-identifiable)"
UNMEASURABLE_REASON = "probe-fit non-identifiable at probe scale"


# -- (X1) golden: tonight's frozen A2 bytes are UNMEASURABLE, never a veto ---------
def test_tonight_a2_floor_check_is_unmeasurable_rc_three() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = tp._decide_fixture(tmp, "x1", {"A1": tp._clean(*tp.A1_CLEAN),
                                           "A2": (tp.TONIGHT_LO, tp.TONIGHT_HI),
                                           "A3": tp._clean(0.9, 1.0)})
        proc = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A2",
                          "--observed", "0.5", "--reps", "200")
        assert proc.returncode == 3, \
            f"the unmeasurable leg must carry its own dedicated rc 3: {proc.stdout}"
        out = json.loads(proc.stdout)
        assert out["ok"] is True, "an unmeasurable gate is not a refusal"
        assert out["floor_gate"] == "unmeasurable"
        assert out["arm"] == "A2"
        assert out["reason"] == UNMEASURABLE_REASON, "ruling verbatim"
        # the fit entry is the verbatim report — the halt's own bytes, no re-type
        fit = out["fit"]
        assert fit["fit_status"] == vc.NON_IDENTIFIABLE
        assert fit["rate"] == tp.TONIGHT_RATE and fit["p"] == tp.TONIGHT_P, \
            f"golden bytes: {fit}"
        # no fabricated floor: the coin-flip fit lends no number to anything
        for invented in ("floor", "projection", "gate"):
            assert invented not in out, \
                f"an unmeasurable leg must not fabricate {invented}: {out}"


# -- (X2) rc 2 stays reserved for the genuine hard refusals ------------------------
def test_floor_check_hard_refusals_stay_hard() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = {"A1": tp._clean(*tp.A1_CLEAN), "A2": (tp.TONIGHT_LO,
                                                      tp.TONIGHT_HI),
                "A3": tp._clean(0.9, 1.0)}
        d = tp._decide_fixture(tmp, "x2-args", base)
        proc = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A2",
                          "--observed", "0.5")                       # no --reps
        assert proc.returncode == 2, \
            f"a missing argument is a hard refusal, not an unmeasurable leg: {proc.stdout}"
        assert "--floor-check needs" in json.loads(proc.stdout)["error"]

        d = tp._decide_fixture(tmp, "x2-missing", {**base, "A2": None})
        proc = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A2",
                          "--observed", "0.5", "--reps", "200")
        assert proc.returncode == 2, "no bytes at all is a refusal, not unmeasurable"
        why = json.loads(proc.stdout)["error"]
        assert "governance floor" in why and "A2" in why, \
            f"the structural rung keeps its provenance ladder wording: {why}"

        d = tp._decide_fixture(tmp, "x2-struct", {**base,
                                                  "A2": ([0.9] * 3, None)})
        proc = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A2",
                          "--observed", "0.5", "--reps", "200")
        assert proc.returncode == 2, "structural unusability is a refusal class"
        assert "probe fit unusable" in json.loads(proc.stdout)["error"]


# -- (X3) the probe-fit rung: rc 0 semantics byte-untouched -------------------------
def test_physical_gate_rc_zero_is_byte_untouched() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = tp._decide_fixture(tmp, "x3", {"A1": tp._clean(*tp.A1_CLEAN),
                                           "A2": tp._clean(0.9, 1.0),
                                           "A3": tp._clean(0.9, 1.0)})
        proc = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A1",
                          "--observed", "0.5", "--reps", "200")
        assert proc.returncode == 0, proc.stdout
        out = json.loads(proc.stdout)
        assert set(out) == {"arm", "observed", "floor_ratio", "projection",
                           "floor", "fit", "floor_source", "gate"}, \
            f"the pre-amendment rc-0 payload shape, unchanged: {sorted(out)}"
        fit = vc._arm_fit(d, "A1")
        assert out["floor_source"] == "probe-fit" and out["gate"] == "pass"
        assert out["fit"] == json.loads(json.dumps(fit)), \
            "same consumed entry, JSON-normalized (shapes are (S, R) pairs)"
        assert out["projection"] == vc.project_wall(fit, reps=200)
        assert out["floor"] == gov.FLOOR_RATIO * out["projection"]
        assert abs(fit["rate"] - 0.02) < 1e-12 and abs(fit["p"] - 0.02) < 1e-12


# -- (X4) the breach path: rc 4 unchanged, the one way a gate still kills -----------
def test_breach_path_rc_four_is_byte_untouched() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = tp._decide_fixture(tmp, "x4", {"A1": tp._clean(*tp.A1_CLEAN),
                                           "A2": tp._clean(0.9, 1.0),
                                           "A3": tp._clean(0.9, 1.0)})
        fit = vc._arm_fit(d, "A1")
        floor = gov.FLOOR_RATIO * vc.project_wall(fit, reps=200)
        proc = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A1",
                          "--observed", repr(floor * 1.0001), "--reps", "200")
        assert proc.returncode == 4, \
            f"a real breach must still verdict rc 4: {proc.stdout}"
        out = json.loads(proc.stdout)
        assert out["gate"] == "breach" and out["floor_source"] == "probe-fit"
        edge = ap._vc_cli("--campaign", str(d), "--floor-check", "--arm", "A1",
                          "--observed", repr(floor), "--reps", "200")
        assert edge.returncode == 0 and json.loads(edge.stdout)["gate"] == "pass", \
            "the pre-registered <= comparison is part of the untouched 0/4 law"


# -- (X5) the instrument: accept {0,3,4}, record, continue; everything else dies ----
def test_instrument_floor_site_maps_the_unmeasurable_leg() -> None:
    src = ap._campaign_src()
    assert re.search(r"fc\$rc %in% c\(0L, 3L, 4L\)", src), \
        "the accept set must grow by the dedicated rc 3 and nothing else"
    assert src.count("fc$rc %in%") == 1, \
        "rc 3 is inert everywhere the floor oracle is not consulted"
    assert '"floor oracle failed (rc "' in src, "every other rc aborts verbatim"
    start = src.index('fc <- call_oracle_rc(c("--floor-check"')
    stop = src.index("fits[[arm]] <- t$value", start)
    region = src[start:stop]
    assert "write_unmeasurable_gate(arm, tier, K, S, N_SIG, reps_taken, t," \
        in region, "the rc-3 branch delegates to the dedicated writer"
    assert 'oj(fc$text, "reason")' in region, "the oracle's reason rides the witness"
    writer = src.split("write_unmeasurable_gate <- function", 1)
    assert len(writer) == 2, "the dedicated writer must exist at top level"
    body = writer[1].split("\n}", 1)[0]
    assert f'"gate":"{GATE_MARKER}"' in body, "the marker is ruling-verbatim law"
    assert '"gate_reason":"' in body, "the reason rides the witness verbatim"
    assert '"floor_projection":null,"floor_ratio":null' in body, \
        "no number is fabricated for an unmeasurable leg"
    r3 = region.split("if (fc$rc == 3L) {", 1)
    assert len(r3) == 2, "the rc-3 branch must exist at the floor site"
    assert "quit(" not in r3[1].split("} else {", 1)[0], \
        "the unmeasurable leg records and CONTINUES — it never vetoes the shot"
    halt = src[src.index("fits[[arm]] <- t$value"):]
    assert "HALT-AND-REPORT" in halt[:800] and "quit(status = 3L)" in halt[:800], \
        "the rc-4 halt stays the verbatim quit-3 the RB-10 ledger remembers"
    # law (4) visibility: the leg is disclosed in the shot's own result.md
    assert "floor gate UNMEASURED" in src, "result.md must disclose the leg"
    assert "unmeasured <- c()" in src and "unmeasured <- c(unmeasured, arm)" in src


def test_unmeasurable_gate_writer_executes_on_the_target_interpreter() -> None:
    if not ap.RSCRIPT:
        print("  [skip] Rscript absent")
        return
    with tempfile.TemporaryDirectory() as tmp:
        program = ap._capture_defs(str(ap.CAMPAIGN),
                                   ["write_unmeasurable_gate", "json_load3"]) + f'''
paste0 <- function(...) paste(..., collapse = "")
wit <- "{tmp}"
t <- list(wall = 0.873, cpu = 0.9, load_before = c(2.6, 2.5, 2.4),
          load_after = c(2.7, 2.5, 2.4))
get("write_unmeasurable_gate", env)("A2", "A", 1000L, 1000L, 50L, 200L, t,
  "{UNMEASURABLE_REASON}")
'''
        ap._r(program)
        rec = json.loads((Path(tmp) / "arm_A2.jsonl").read_text(encoding="utf-8"))
        assert rec["kind"] == "arm" and rec["arm"] == "A2" and rec["tier"] == "A"
        assert rec["gate"] == GATE_MARKER, "one byte off and the reader would veto"
        assert rec["gate_reason"] == UNMEASURABLE_REASON
        assert rec["floor_projection"] is None and rec["floor_ratio"] is None
        assert abs(rec["wall"] - 0.873) < 1e-9, "the measured bytes still ride"
        assert rec["load_before"] == [2.6, 2.5, 2.4]


# -- (X6) the reader: the marker is tolerated, breach and junk never are ------------
def _reader_on_leg(gate: str) -> tuple[int, dict]:
    """One MEASURED-true campaign whose A2 arm witness carries the given gate."""
    with tempfile.TemporaryDirectory() as tmp:
        a2 = bc._arm("A2", 1000.0 / 250.0)
        a2["gate"] = gate
        if gate == GATE_MARKER:                      # mirror the instrument's bytes
            a2.update({"floor_projection": None, "floor_ratio": None,
                      "gate_reason": UNMEASURABLE_REASON})
        d = bc._campaign_dir(Path(tmp) / "c", ratio=250.0,
                             arms={"A1": [bc._arm("A1", 1000.0)],
                                   "A2": [a2],
                                   "A3": [bc._arm("A3", 1000.0 / 31.25)]})
        bc._result_md(d, "MEASURED-true ≥100x", 250.0, "B")
        rc, text = bc._vc().main(["--campaign", str(d), "--host",
                                 "measurement-host", "--hw-profile",
                                 bc.HW_PROFILE])
        return rc, json.loads(text)


def test_reader_tolerates_the_unmeasurable_marker_only() -> None:
    rc, report = _reader_on_leg(GATE_MARKER)
    assert rc == 0, \
        f"the gate lost its say on this leg; it may not borrow a veto later: {report}"
    floors = [c for c in report["checks"] if c["check"] == "floor-gates"]
    assert floors[0]["ok"] is True and GATE_MARKER in floors[0]["detail"], \
        "the leg must be DISCLOSED in the verdict, not silently forgiven"
    for forged in ("breach", "unmeasurable", GATE_MARKER.lower()):
        rc, report = _reader_on_leg(forged)
        floors = [c for c in report["checks"] if c["check"] == "floor-gates"]
        assert rc == 1 and floors[0]["ok"] is False, \
            f"only the verbatim marker is tolerated, {forged!r} must still fail: {report}"
