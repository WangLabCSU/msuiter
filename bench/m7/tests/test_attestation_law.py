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
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools import attestation as att                   # noqa: E402 (RED-by-absence)
from tools import matrix_governance as gov             # noqa: E402
from tools import parity_recompute as pr               # noqa: E402
from tools import probe_sigminer_cell_argv as probe    # noqa: E402


def _good_coex_record() -> dict:
    return {"schema": 1, "shape": "coex-inversion/N=3",
            "legs": [{"probe": "r1", "wall_s": 1101.0, "cpu_s": 1101.5},
                    {"probe": "r2", "wall_s": 1096.0, "cpu_s": 1096.2},
                    {"probe": "r3", "wall_s": 1089.0, "cpu_s": 1089.9}],
            "solo_mean_s": 969.9, "deltas_pct": [13.5, 13.0, 12.3],
            "bar_pct": 5.0, "verdict": "NOT-FLAT",
            "measured_utc": "2026-10-28T00:00:00Z"}


def _write(path: Path, doc) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, sort_keys=True), encoding="utf-8")
    return path


def _preflight_log(tmp: Path, *, decision="GO") -> Path:
    log = tmp / "preflight_log.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": "2026-10-28T00:00:00Z",
                            "cell": "tool__arm__N100",
                            "live_measurement_containers": 0,
                            "decision": decision}) + "\n")
    return log


# -- (1) mint-side law ---------------------------------------------------------

def test_build_requires_the_preflight_quiet_verdict(tmpdir=None):
    """No preflight record for the cell => no attestation => no mint: the
    quiet-gate verdict must be provable from bytes, not remembered."""
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="att_"))
    try:
        _write(tmp / "coex.json", _good_coex_record())
        os.environ[att.COEX_ENV] = str(tmp / "coex.json")
        try:
            att.build_attestation(preflight_log=tmp / "absent.jsonl",
                                 cell="tool__arm__N100", epoch="e1")
            raised = ""
        except att.AttRefusal as exc:
            raised = str(exc)
        assert "preflight" in raised.lower(), \
            "missing quiet-gate record must refuse the mint with a spoken reason"
    finally:
        os.environ.pop(att.COEX_ENV, None)
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def test_build_requires_a_well_formed_coex_probe_record():
    """The deliberate-inversion (N=3 class) probe record is mandatory and
    shape-checked: absent, malformed, or a non-inversion shape all refuse."""
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="att_"))
    try:
        log = _preflight_log(tmp)
        os.environ.pop(att.COEX_ENV, None)
        for bad in (None, "notjson", "wrongshape", "wrongverdict"):
            if bad is None:
                os.environ[att.COEX_ENV] = str(tmp / "missing.json")
            elif bad == "notjson":
                _write(tmp / "bad.json", "{nope")
                os.environ[att.COEX_ENV] = str(tmp / "bad.json")
            elif bad == "wrongshape":
                rec = _good_coex_record()
                rec["shape"] = "solo"
                _write(tmp / "ws.json", rec)
                os.environ[att.COEX_ENV] = str(tmp / "ws.json")
            else:
                rec = _good_coex_record()
                rec["verdict"] = "PRETTY-FLAT"
                _write(tmp / "wv.json", rec)
                os.environ[att.COEX_ENV] = str(tmp / "wv.json")
            try:
                att.build_attestation(preflight_log=log,
                                     cell="tool__arm__N100", epoch="e1")
                spoke = False
            except att.AttRefusal:
                spoke = True
            assert spoke, f"coex-probe forgery [{bad}] must refuse the mint"
        _write(tmp / "good.json", _good_coex_record())
        os.environ[att.COEX_ENV] = str(tmp / "good.json")
        a = att.build_attestation(preflight_log=log, cell="tool__arm__N100",
                                  epoch="post-cap-epoch-1")
        assert a["law"] == att.ATTEST_LAW
        assert a["preflight"]["decision"] == "GO"
        assert a["coex_probe"]["verdict"] == "NOT-FLAT"
        assert a["epoch"] == "post-cap-epoch-1"
    finally:
        os.environ.pop(att.COEX_ENV, None)
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def test_probe_mints_only_attested_witnesses():
    """The mint face stamps the attestation into the witness bytes; the
    refusal path converts a mint without the proofs into a DEFECT verdict —
    never a silent un-attested OK."""
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="att_"))
    try:
        _write(tmp / "coex.json", _good_coex_record())
        os.environ[att.COEX_ENV] = str(tmp / "coex.json")
        log = _preflight_log(tmp)
        doc = {"verdict": "OK", "cell": "tool__arm__N100"}
        stamped = att.stamp_witness(doc, preflight_log=log,
                                    cell="tool__arm__N100", epoch="e7")
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
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


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
    import tempfile
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
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def test_reporter_admits_a_fully_attested_witness():
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "y.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW,
                                        "preflight": {"decision": "GO"},
                                        "coex_probe": {"verdict": "NOT-FLAT"},
                                        "epoch": gov.floor_table_epoch()})
        anchor = _anchor_for(tmp, "y.json", 100.0, 100.0)
        cpu, wall, doc = pr._witness_face(anchor)
        assert (cpu, wall) == (100.0, 100.0)
    finally:
        gov._RESULTS_DIR = old_results
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def test_reporter_refuses_a_refused_preflight_verdict():
    """A leg whose quiet-gate record speaks REFUSE cannot be reported as a
    measurement — the co-tenancy law is not decorative."""
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "z.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW,
                                        "preflight": {"decision": "REFUSE"},
                                        "coex_probe": {"verdict": "FLAT"},
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
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


def test_reporter_refuses_a_stale_epoch_attestation():
    """Post-cap witness law codified: an attested witness carrying an epoch
    token other than the table being adjudicated against is epoch-mismatched
    material — refused, not quietly consumed."""
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="att_rep_"))
    old_results = gov._RESULTS_DIR
    try:
        gov._RESULTS_DIR = tmp
        w = tmp / "c" / "witnesses" / "stale.json"
        _companion_witness(w, cpu=100.0, wall=100.0,
                           attestation={"law": att.ATTEST_LAW,
                                        "preflight": {"decision": "GO"},
                                        "coex_probe": {"verdict": "FLAT"},
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
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


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
