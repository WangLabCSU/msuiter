"""Co-tenancy attestation law (Phase-9 O3): the two proven practices become
harness bytes, not lane folklore.

Phase-5 Q2 established that the only variable between byte-identical cells
measured 376 s and 616 s was the measurement environment, and Phase-6 O2
measured the post-cap residual: at three-way co-tenancy the same capped cell
inflates ~12-13.5 % against the solo mean (wall/cpu pinned at ~1.000 —
shared-VM memory-bandwidth contention). The practices that contain it:
quiet-serial enforcement (RB-08(3), already spoken through the driver) and
the deliberate coex-inversion probe (N=3 class) whose verdict qualifies
which machine a number was taken on. Codified here:

  MINT SIDE  a witness is only ever minted together with (a) the preflight
             quiet-gate record that let its leg launch and (b) a
             well-formed inversion-probe record; no proofs, no mint — the
             leg comes back DEFECT with the reason, never as a silent
             un-attested OK.
  REPORT SIDE  the parity reporter refuses a witness that claims the
             attestation law yet lacks the fields, refuses a REFUSEd quiet
             gate, refuses an epoch-mismatched attestation (the post-cap
             witness law), admits fully-attested bytes, and prints the
             epoch token plus the honest attestation state on every row.
             Witnesses predating the law remain re-derivable — the committed
             record must never be made unquotable — but are labelled
             pre-law on their face.

Immutability: stamp_witness returns a NEW document; it never mutates the
caller's verdict.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

ATTEST_LAW = "attestation-lv1"
#: Operator/lane-set path to the current coex-inversion probe record (JSON).
COEX_ENV = "MSUITER_COEX_PROBE"
#: The inversion probe's verdict vocabulary (the 5 % flatness bar decides it;
#: NOT-FLAT is a banked gate outcome, not an error — Phase-6 O2).
FLAT_VERDICTS = ("FLAT", "NOT-FLAT")
COEX_SHAPE_PREFIX = "coex-inversion/"


class AttRefusal(RuntimeError):
    """The mint may not happen: one of the two attestation proofs is absent
    or inadmissible. The reason is spoken, never swallowed."""


def _read_json(path: Path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def coex_record_ok(rec) -> str | None:
    """Why an inversion-probe record is inadmissible, or ``None``. Shape:
    deliberate co-tenancy, N=3 legs, numerics present, verdict in the
    sanctioned vocabulary."""
    if not isinstance(rec, dict):
        return "record is not a JSON object"
    if rec.get("schema") != 1:
        return f"schema is {rec.get('schema')!r}, want 1"
    shape = str(rec.get("shape", ""))
    if not shape.startswith(COEX_SHAPE_PREFIX):
        return (f"shape {shape!r} is not a deliberate inversion probe "
                f"({COEX_SHAPE_PREFIX}N=<n> class)")
    legs = rec.get("legs")
    if not isinstance(legs, list) or not legs:
        return "no legs enumerated"
    for leg in legs:
        if not isinstance(leg, dict):
            return "a leg is not an object"
        for col in ("wall_s", "cpu_s"):
            v = leg.get(col, -1)
            if not isinstance(v, (int, float)) or not v > 0:
                return f"leg {leg.get('probe')!r} column {col} not positive"
    solo = rec.get("solo_mean_s", -1)
    if not isinstance(solo, (int, float)) or not solo > 0:
        return "solo_mean_s missing or non-positive"
    deltas = rec.get("deltas_pct")
    if not isinstance(deltas, list) or len(deltas) != len(legs) \
            or not all(isinstance(d, (int, float)) for d in deltas):
        return "deltas_pct does not pair one-to-one with the legs"
    if rec.get("verdict") not in FLAT_VERDICTS:
        return f"verdict {rec.get('verdict')!r} outside {FLAT_VERDICTS}"
    if not str(rec.get("measured_utc", "")):
        return "record carries no measured_utc stamp"
    return None


def read_preflight_verdict(preflight_log, cell: str) -> dict | None:
    """The LAST RB-08(3) decision recorded for this exact stamp."""
    try:
        lines = Path(preflight_log).read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    found = None
    for ln in lines:
        try:
            rec = json.loads(ln)
        except ValueError:
            continue
        if isinstance(rec, dict) and rec.get("cell") == cell:
            found = rec
    return found


def build_attestation(*, preflight_log, cell: str, epoch: str) -> dict:
    """The two proofs as one block, or an AttRefusal with the spoken reason."""
    pre = read_preflight_verdict(preflight_log, cell)
    if pre is None:
        raise AttRefusal(
            f"preflight quiet-gate verdict absent for cell {cell!r} — the "
            f"RB-08(3) GO/REFUSE record must exist in bytes (attestation "
            f"cannot be remembered, only read)")
    if pre.get("decision") != "GO":
        raise AttRefusal(f"preflight decision is {pre.get('decision')!r} "
                         f"for {cell!r} — a refused launch is not a measurement")
    raw = (os.environ.get(COEX_ENV) or "").strip()
    if not raw:
        raise AttRefusal(
            f"coex inversion-probe record absent ({COEX_ENV} unset) — parity "
            f"bytes may not be reported without the flatness qualifier")
    rec = _read_json(Path(raw))
    if rec is None:
        raise AttRefusal(f"coex-probe record at {raw!r} is not parseable JSON")
    reason = coex_record_ok(rec)
    if reason is not None:
        raise AttRefusal(f"coex-probe record inadmissible: {reason}")
    return {"law": ATTEST_LAW, "preflight": pre, "coex_probe": rec,
            "epoch": epoch}


def stamp_witness(doc: dict, *, preflight_log, cell: str,
                  epoch: str) -> dict:
    """Attach the attestation to a minted witness — or DEFECT the mint with
    the reason. Returns a new document (immutability)."""
    try:
        block = build_attestation(preflight_log=preflight_log, cell=cell,
                                  epoch=epoch)
    except AttRefusal as exc:
        return {**doc, "verdict": "DEFECT",
                "reason": f"attestation refused: {exc}"}
    return {**doc, "attestation": block}


# -- report side ---------------------------------------------------------------

def reportability(doc: dict, current_epoch: str) -> str | None:
    """Why this witness may not be reported, or ``None``. Pre-law witnesses
    (no attestation block at all) are admissible history — the O0
    re-derivation law forbids making the committed record unquotable."""
    att = doc.get("attestation")
    if att is None:
        return None
    if not isinstance(att, dict) or att.get("law") != ATTEST_LAW:
        return ("attestation block present but not a well-formed "
                f"{ATTEST_LAW!r} document — fields absent is a refusal, "
                "not a rounding")
    pre, co = att.get("preflight"), att.get("coex_probe")
    if not isinstance(pre, dict) or pre.get("decision") != "GO":
        return "attestation lacks a GO preflight quiet-gate verdict"
    if not isinstance(co, dict) or co.get("verdict") not in FLAT_VERDICTS:
        return "attestation lacks the coex inversion-probe verdict"
    if str(att.get("epoch", "")) != str(current_epoch):
        return (f"attestation epoch {att.get('epoch')!r} is not the "
                f"adjudicated epoch {current_epoch!r} — epoch-mismatched "
                f"material is history, not a measurement")
    return None


def row_tokens(doc: dict, current_epoch: str) -> str:
    """The printed row's honesty stamp: the epoch the adjudication rides and
    the witness's own attestation state, spoken on every row."""
    att = doc.get("attestation")
    if isinstance(att, dict) and att.get("law") == ATTEST_LAW:
        pre = att.get("preflight") or {}
        co = att.get("coex_probe") or {}
        state = (f"lv1(preflight={pre.get('decision')!r},"
                 f"coex={co.get('verdict')!r},"
                 f"epoch={att.get('epoch')!r})")
    else:
        state = "pre-law"
    return f"epoch={current_epoch} attestation={state}"
