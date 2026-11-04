"""Group (QE) test_attestation_law — co-tenancy attestation, codified
(Phase-9 O3; the two proven practices become harness law, not folklore).

The practices this pins:
  (1) every minted witness carries, in its own bytes, the preflight quiet-gate
      verdict that let the leg launch (RB-08(3) as recorded by the driver) and
      the coex-flatness inversion-probe record (the deliberate N=3 co-tenancy
      leg class) whose verdict qualifies the machine the number was taken on;
  (2) the parity reporter REFUSES a witness that claims the attestation law
      but does not carry the fields, and stamps the post-cap epoch token on
      every printed row; witnesses predating the law stay re-derivable — the
      committed record must never be made unquotable (the O0 re-derivation
      law) — but are printed honestly as pre-law.

The refusal path itself must be seen to fire (governance-scan-integrity law:
an unseen-to-fire control is a vacuous control): the hand-made witness
without the fields is that control.

Phase-D reseed (controller ruling 2026-11-04): the admissible coex face is
no longer typed here — it is DRIVEN out of tools/coex_inversion_probe via
tests/coex_fixtures (byte-true-fixtures law), the mint leg carries its
context (image/campaign/replay-probe) so the targeted teeth bite in
isolation, and the forgery loop grew the teeth-era negatives (state C,
lying verdict, masked-serial cohort) each naming its own defect in the
refusal it speaks.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import attestation as att                   # noqa: E402 (RED-by-absence)
from tools import matrix_governance as gov             # noqa: E402
from tools import parity_recompute as pr               # noqa: E402
from tools import probe_sigminer_cell_argv as probe    # noqa: E402
from tests import coex_fixtures as fx                  # noqa: E402


def _write(path: Path, doc) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, sort_keys=True), encoding="utf-8")
    return path


def _preflight_log(tmp: Path, *, decision="GO") -> Path:
    log = tmp / "preflight_log.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": "2026-10-28T00:00:00Z",
                            "cell": fx.CELL,
                            "live_measurement_containers": 0,
                            "decision": decision}) + "\n")
    return log


def _mint_context(tmp: Path, name: str = "coex.json") -> dict:
    """The mint-side context kwargs: image/campaign agree with the staged
    record, the replay probe answers for every container. Only the face a
    unit is probing is ever left out of the honest face."""
    return {"preflight_log": _preflight_log(tmp), "cell": fx.CELL,
            "epoch": "e1", "image_digest": fx.IMAGE_DIGEST,
            "campaign": fx.CAMPAIGN, "live_probe": fx.fake_live_probe(),
            "coex_path": str(tmp / name)}


# -- (1) mint-side law ---------------------------------------------------------

def test_build_requires_the_preflight_quiet_verdict():
    """No preflight record for the cell => no attestation => no mint: the
    quiet-gate verdict must be provable from bytes, not remembered."""
    tmp = Path(tempfile.mkdtemp(prefix="att_"))
    try:
        fx.stage(tmp)                                   # honest coex + ledger
        ctx = _mint_context(tmp)
        ctx["preflight_log"] = tmp / "absent.jsonl"
        os.environ[att.COEX_ENV] = ctx.pop("coex_path")
        try:
            att.build_attestation(**ctx)
            raised = ""
        except att.AttRefusal as exc:
            raised = str(exc)
        assert "preflight" in raised.lower(), \
            "missing quiet-gate record must refuse the mint with a spoken reason"
    finally:
        os.environ.pop(att.COEX_ENV, None)


def test_build_requires_a_well_formed_coex_probe_record():
    """The deliberate-inversion (N=3 class) probe record is mandatory and
    tooth-checked: absent, malformed, self-reported (state C), a lying
    verdict, or a masked-serial cohort all refuse, each naming its own
    defect; the rig-emitted face is the shared seen-to-fire control."""
    tmp = Path(tempfile.mkdtemp(prefix="att_"))
    try:
        span = fx.LEG_SPAN_S
        # same walls, same container ids as the honest cohort -- the ONE
        # forged dimension is the windows: no common intersection (T3 keeps
        # the bind/inspect pairing honest, so a re-seal may not swap faces
        # the binding does not know about)
        disjoint = [fx.leg(10, fx.COHORT_WALLS[0], stagger_s=0.0),
                    fx.leg(11, fx.COHORT_WALLS[1], stagger_s=2.0 * span),
                    fx.leg(12, fx.COHORT_WALLS[2], stagger_s=span)]
        honest = fx.rig_record()
        cases = [
            ("missing", None, "absent"),
            ("notjson", "{nope", "coex"),
            ("wrongshape", fx.reseal(honest, shape="solo"), "shape"),
            ("wrongverdict", fx.reseal(honest, verdict="PRETTY-FLAT"),
             "verdict"),
            ("stateC", fx.handwritten_record(), "bind"),
            ("lying_verdict", fx.reseal(honest, verdict="FLAT"),
             "verdict"),
            ("masked_serial", fx.reseal(honest, legs=disjoint), "overlap"),
        ]
        for name, doc, needle in cases:
            if doc is None:
                path = tmp / f"{name}-missing.json"
            else:
                path = _write(tmp / f"{name}.json", doc)
            os.environ[att.COEX_ENV] = str(path)   # the gate reads the env face
            ctx = _mint_context(tmp)
            ctx.pop("coex_path")                    # env carries the path
            try:
                att.build_attestation(**ctx)
                spoke, reason = False, ""
            except att.AttRefusal as exc:
                spoke, reason = True, str(exc)
            assert spoke, f"coex-probe forgery [{name}] must refuse the mint"
            assert needle in reason.lower(), \
                f"[{name}] refusal must name its defect: {reason!r}"
        # firing control: the rig-emitted, rig-booked face is admissible
        fx.stage(tmp)
        os.environ[att.COEX_ENV] = str(tmp / "coex.json")
        ctx = _mint_context(tmp)
        ctx.pop("coex_path")
        ctx["epoch"] = "post-cap-epoch-1"
        a = att.build_attestation(**ctx)
        assert a["law"] == att.ATTEST_LAW
        assert a["preflight"]["decision"] == "GO"
        assert a["coex_probe"]["verdict"] == "NOT-FLAT"
        assert a["epoch"] == "post-cap-epoch-1"
    finally:
        os.environ.pop(att.COEX_ENV, None)


def test_probe_mints_only_attested_witnesses():
    """The mint face stamps the attestation into the witness bytes; the
    refusal path converts a mint without the proofs into a DEFECT verdict —
    never a silent un-attested OK."""
    tmp = Path(tempfile.mkdtemp(prefix="att_"))
    try:
        fx.stage(tmp)                                   # coex + ledger booking
        os.environ[att.COEX_ENV] = str(tmp / "coex.json")
        log = _preflight_log(tmp)
        doc = {"verdict": "OK", "cell": fx.CELL}
        stamped = att.stamp_witness(doc, preflight_log=log,
                                    cell=fx.CELL, epoch="e7",
                                    image_digest=fx.IMAGE_DIGEST,
                                    campaign=fx.CAMPAIGN,
                                    live_probe=fx.fake_live_probe())
        assert stamped["attestation"]["law"] == att.ATTEST_LAW
        assert stamped["verdict"] == "OK"
        assert doc.get("attestation") is None, \
            "stamping must not mutate the caller's document (immutable law)"
        os.environ.pop(att.COEX_ENV, None)
        refused = att.stamp_witness({"verdict": "OK"}, preflight_log=log,
                                    cell="missing-cell", epoch="e7")
        assert refused["verdict"] == "DEFECT" and "attestation" not in refused
    finally:
        os.environ.pop(att.COEX_ENV, None)


def test_freshness_law_still_rejects_plain_replay():
    """(seam pin) the Phase-9 O1 mint firewall is unchanged by O3."""
    assert probe.freshness_law("cached") is not None


# -- (2) report-side law --------------------------------------------------------

def _companion_witness(path: Path, *, cpu: float, wall: float,
                       attestation=None) -> dict:
    doc = {"verdict": "OK", "run_rc": 0,
           "argv": ["--reps", "100"], "reps": 100,
           "sidecar": {"exit_status": 0, "cpu_seconds": cpu,
                       "ru_utime": cpu, "ru_stime": 0.0},
           "wall_seconds": wall, "arm": "comp_clock_only", "n": 100,
           "tool": "sigminer"}
    if attestation is not None:
        doc["attestation"] = attestation
    _write(path, doc)
    return doc


def _anchor_for(tmp: Path, name: str, cpu: float, wall: float):
    (tmp / "c" / "witnesses").mkdir(parents=True, exist_ok=True)
    return {"witness": ("c", "witnesses", name), "reps": 100,
            "cpu_seconds": cpu, "wall_seconds": wall}


def test_reporter_refuses_a_law_claiming_witness_missing_the_fields():
    """THE FIRING CONTROL: a hand-made witness that claims the attestation
    law but carries no fields must be REFUSED (exit 2) with a spoken reason
    — the refusal path must be seen to fire."""
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "x.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW})  # fields absent
        anchor = _anchor_for(tmp, "x.json", 100.0, 100.0)
        try:
            pr._witness_face(anchor)
            code = 0
        except SystemExit as exc:
            code, _ = exc.code
        assert code == 2, "a law-claiming witness without fields must refuse"
    finally:
        gov._RESULTS_DIR = old_results


def test_reporter_admits_a_fully_attested_witness():
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "y.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW,
                                        "preflight": {"decision": "GO"},
                                        "coex_probe": fx.rig_record(),
                                        "epoch": gov.floor_table_epoch()})
        anchor = _anchor_for(tmp, "y.json", 100.0, 100.0)
        cpu, wall, doc = pr._witness_face(anchor)
        assert (cpu, wall) == (100.0, 100.0)
    finally:
        gov._RESULTS_DIR = old_results


def test_reporter_refuses_a_refused_preflight_verdict():
    """A leg whose quiet-gate record speaks REFUSE cannot be reported as a
    measurement — the co-tenancy law is not decorative."""
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "z.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW,
                                        "preflight": {"decision": "REFUSE"},
                                        "coex_probe": fx.rig_record(),
                                        "epoch": gov.floor_table_epoch()})
        anchor = _anchor_for(tmp, "z.json", 100.0, 100.0)
        try:
            pr._witness_face(anchor)
            code = 0
        except SystemExit as exc:
            code, _ = exc.code
        assert code == 2
    finally:
        gov._RESULTS_DIR = old_results


def test_reporter_refuses_a_stale_epoch_attestation():
    """Post-cap witness law codified: an attested witness carrying an epoch
    token other than the table being adjudicated against is epoch-mismatched
    material — refused, not quietly consumed."""
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "stale.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW,
                                        "preflight": {"decision": "GO"},
                                        "coex_probe": fx.rig_record(),
                                        "epoch": "not-the-current-epoch"})
        anchor = _anchor_for(tmp, "stale.json", 100.0, 100.0)
        try:
            pr._witness_face(anchor)
            code = 0
        except SystemExit as exc:
            code, _ = exc.code
        assert code == 2
    finally:
        gov._RESULTS_DIR = old_results


def test_committed_record_stays_rederivable_and_every_row_speaks_the_epoch():
    """Pre-law witnesses are history, not phantoms: the committed table must
    still recompute exit-0, and every printed row must carry the epoch token
    plus its honest attestation state."""
    import io
    import contextlib
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = pr.main()
        except SystemExit as exc:
            rc, _ = exc.code
    assert rc == 0, f"O3 must not make the committed record unquotable: {out.getvalue()[-300:]}"
    lines = [ln for ln in out.getvalue().splitlines()
             if " cpu-basis ratio=" in ln]
    assert lines
    for ln in lines:
        assert " epoch=" in ln, f"row carries no epoch stamp: {ln[:90]}"
        assert "attestation=" in ln, f"row hides its attestation state: {ln[:90]}"
