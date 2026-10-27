"""⑯ Parity recompute contract (Phase-7 O5): the tool must re-measure from
witness bytes, bind paths, honour the bar arithmetically, and refuse
inadmissible inputs -- never re-state table numbers from memory.

Laws under test:
  byte-exact re-measure: every committed anchor's witness re-read equals the
    table figure exactly (no tolerance) or the tool exits 2.
  path-binding: every printed line carries face and yard witness paths plus
    the class/reps echo, in one line.
  bar arithmetic: verdict matches ratio <= BAR_PARITY on the cpu basis.
  tamper refusal: a witness whose sidecar cpu was edited REFUSES (exit 2),
    it is never silently adopted.
"""
from __future__ import annotations

import io
import contextlib
import json
import shutil
import tempfile
from pathlib import Path

from tools import matrix_governance as gov              # noqa: E402
from tools import parity_recompute as pr                # noqa: E402


def _capture_main() -> tuple[int, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = pr.main()
        except SystemExit as e:
            rc, _ = e.code
    return rc, out.getvalue()


def test_full_recompute_is_admissible_and_complete():
    """The committed table recomputes clean: exit 0, one line per
    (R-face x class) cell, plus the census footer."""
    rc, out = _capture_main()
    lines = [ln for ln in out.splitlines() if " cpu-basis ratio=" in ln]
    assert rc == 0, f"recompute refused the committed table: {out[-400:]}"
    assert lines, "no ratio lines emitted"
    assert any(ln.startswith("[parity-recompute]") for ln in out.splitlines())


def test_every_anchored_witness_re_measures_byte_exact():
    """MEASURED-then-STATED, zero tolerance: all 168 anchors re-read equal
    their table figures."""
    for key, anchor in sorted(gov._FLOOR_ANCHORS.items()):
        cpu, wall, doc = pr._witness_face(anchor)
        assert cpu == float(anchor["cpu_seconds"]), key
        assert wall == float(anchor["wall_seconds"]), key
        assert doc["reps"] == gov.PROTOCOL_REPS and doc["verdict"] == "OK", key


def test_ratio_lines_are_path_bound_and_bar_consistent():
    """Every line binds both witness paths in-line and its verdict equals the
    arithmetic comparison against the hard bar."""
    rc, out = _capture_main()
    assert rc == 0
    for ln in out.splitlines():
        if " cpu-basis ratio=" not in ln:
            continue
        head, tail = ln.split(" | ", 1)
        assert "||" in tail and tail.count("bench/results/") == 2, ln
        ratio = float(head.split("ratio=")[1].split()[0])
        assert ("BREACH" in head.split()) == (ratio > pr.BAR_PARITY), ln
        assert ("PASS" in head.split()) == (ratio <= pr.BAR_PARITY), ln
        assert pr.BAR_PARITY == 2.0, "perf-parity mandate bar moved"


def test_tampered_witness_sidecar_refuses_exit_2():
    """A re-edited cpu in an otherwise pristine witness must EXITCH 2 at the
    byte-equality law, never be adopted into a ratio."""
    key = next(k for k in sorted(gov._FLOOR_ANCHORS) if k[0] == pr.YARDSTICK)
    src = gov.anchor_witness_path(gov._FLOOR_ANCHORS[key])
    tmp = Path(tempfile.mkdtemp(prefix="m7par_"))
    try:
        forged = tmp / src.name
        doc = json.loads(src.read_text(encoding="utf-8"))
        doc["sidecar"]["cpu_seconds"] = doc["sidecar"]["cpu_seconds"] * 1.02
        forged.write_text(json.dumps(doc), encoding="utf-8")
        real = gov.anchor_witness_path
        gov.anchor_witness_path = lambda a, _f=forged: _f
        try:
            raised = None
            try:
                pr._witness_face(gov._FLOOR_ANCHORS[key])
            except SystemExit as e:
                raised = e
            assert raised is not None and raised.code[0] == 2, \
                "tampered witness was adopted, not refused"
            assert "drifted" in raised.code[1]
        finally:
            gov.anchor_witness_path = real
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
