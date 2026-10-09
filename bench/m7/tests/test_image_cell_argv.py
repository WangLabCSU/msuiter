"""Group (L) test_image_cell_argv -- live cell-argv probe contract (U-M7-03, RB-01).

The pilot's exit-127 catch (sigminer image ships the python m7_entry.py wrapper
but carries no python interpreter) must live in the audit trail as an
executable test shape, not only as a transcript: the probe executes the REAL
cell argv (python3 /work/m7_entry.py --params ... --outdir ... -- <runner>)
against the registry-pinned image and asserts the sidecar-schema-valid depth
the controller's ruling demands -- "not a python3 --version smoke".

Offline units here pin the probe's pure assessment contract (what counts as
OK vs DEFECT) so the live witness rides code the suite has already exercised.
The live pass itself is a single manual command whose JSON verdict is
committed next to the matrix records:

  python3 tools/probe_sigminer_cell_argv.py --json <path>

Exit contract mirrors the repo idiom: 0 OK, 1 DEFECT (exec or sidecar chain),
2 inadmissible invocation (unresolvable cell / registry absent).
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import tools.probe_sigminer_cell_argv as probe                   # noqa: E402


def _good_sidecar(outdir: Path) -> None:
    (outdir / "timing.json").write_text(json.dumps(
        {"ru_utime": 1.5, "ru_stime": 0.5, "cpu_seconds": 2.0,
         "exit_status": 0}, sort_keys=True), encoding="utf-8")


def _full_cell(outdir: Path) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    for name in ("intervals.csv", "errors.log", "manifest.json"):
        (outdir / name).write_text("x\n", encoding="utf-8")
    _good_sidecar(outdir)


# -- sidecar schema validation -------------------------------------------------

def test_validate_sidecar_accepts_schema_valid():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td)
        _good_sidecar(p)
        assert probe.validate_sidecar(p / "timing.json") is None


def test_validate_sidecar_rejects_missing_key():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "timing.json"
        p.write_text(json.dumps({"ru_utime": 1.0, "ru_stime": 0.5,
                                 "exit_status": 0}), encoding="utf-8")
        reason = probe.validate_sidecar(p)
        assert reason is not None and "cpu_seconds" in reason


def test_validate_sidecar_rejects_nonzero_child_exit():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "timing.json"
        p.write_text(json.dumps({"ru_utime": 0.01, "ru_stime": 0.0,
                                 "cpu_seconds": 0.01, "exit_status": 127}),
                     encoding="utf-8")
        reason = probe.validate_sidecar(p)
        assert reason is not None and "exit_status" in reason


def test_validate_sidecar_rejects_cpu_inconsistency():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "timing.json"
        p.write_text(json.dumps({"ru_utime": 1.0, "ru_stime": 0.5,
                                 "cpu_seconds": 7.0, "exit_status": 0}),
                     encoding="utf-8")
        reason = probe.validate_sidecar(p)
        assert reason is not None and "cpu_seconds" in reason


def test_validate_sidecar_rejects_negative_cpu():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "timing.json"
        p.write_text(json.dumps({"ru_utime": -1.0, "ru_stime": 0.0,
                                 "cpu_seconds": -1.0, "exit_status": 0}),
                     encoding="utf-8")
        assert probe.validate_sidecar(p) is not None


def test_validate_sidecar_rejects_absent_file():
    with tempfile.TemporaryDirectory() as td:
        assert probe.validate_sidecar(Path(td) / "timing.json") is not None


# -- cell assessment -----------------------------------------------------------

def test_assess_cell_defect_on_missing_guard_files():
    with tempfile.TemporaryDirectory() as td:
        code, verdict = probe.assess_cell(Path(td), run_rc=0, provenance={})
        assert code == 1 and verdict["verdict"] == "DEFECT"
        assert set(verdict["missing"]) == {"intervals.csv", "errors.log",
                                           "manifest.json", "timing.json"}


def test_assess_cell_defect_despite_zero_rc_when_sidecar_broken():
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "out"
        _full_cell(out)
        (out / "timing.json").write_text("{not json", encoding="utf-8")
        code, verdict = probe.assess_cell(out, run_rc=0, provenance={})
        assert code == 1 and verdict["verdict"] == "DEFECT"
        assert "sidecar" in verdict["reason"]


def test_assess_cell_defect_on_nonzero_run_rc():
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "out"
        _full_cell(out)
        code, verdict = probe.assess_cell(out, run_rc=1, provenance={})
        assert code == 1 and verdict["verdict"] == "DEFECT"
        assert verdict["run_rc"] == 1


def test_assess_cell_ok_reports_provenance_and_sidecar():
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "out"
        _full_cell(out)
        prov = {"image_ref": "msuiter-sigminer:slice3-r2",
                "image_digest": "sha256:" + "0" * 64}
        code, verdict = probe.assess_cell(out, run_rc=0, provenance=prov)
        assert code == 0 and verdict["verdict"] == "OK"
        assert verdict["provenance"] == prov
        assert verdict["sidecar"]["cpu_seconds"] == 2.0


def test_verdict_json_round_trips_machine_readable():
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "out"
        _full_cell(out)
        _, verdict = probe.assess_cell(out, run_rc=0, provenance={})
        assert json.loads(json.dumps(verdict, sort_keys=True)) == verdict


# -- witness provenance extras (RB-09(ii)/(5)) -------------------------------------
# A floor witness must carry its FULL argv (including --reps) and its host-side
# wall: every anchor claim becomes mechanically auditable for the reps-match that
# the floor_semantics units (group (P), 5a) gate on.

_RB = ["--profile", "degraded", "--adapter", "docker", "--competitors",
       "sigminer", "--arms", "main", "--n-list", "100", "--reps", "100",
       "--provider", "synthetic", "--provider-seed", "0"]


def test_witness_extras_echo_full_argv_and_reps():
    extras = probe.witness_extras(_RB, tool="sigminer", arm="main",
                                  n=100, wall_seconds=412.5)
    assert extras["argv"] == _RB
    assert extras["reps"] == 100
    assert extras["tool"] == "sigminer" and extras["arm"] == "main"
    assert extras["n"] == 100 and extras["wall_seconds"] == 412.5


def test_witness_extras_refuse_argv_without_reps():
    argv = [a for a in _RB if a != "100" and a != "--reps"]
    try:
        probe.witness_extras(argv, tool="sigminer", arm="main", n=100,
                             wall_seconds=1.0)
    except ValueError:
        return
    raise AssertionError("witness argv without --reps was admitted")


def test_witness_extras_refuse_non_integral_reps():
    bad = list(_RB)
    bad[bad.index("--reps") + 1] = "many"
    try:
        probe.witness_extras(bad, tool="sigminer", arm="main", n=100,
                             wall_seconds=1.0)
    except ValueError:
        return
    raise AssertionError("non-integral --reps echo was admitted")


def test_freshness_law_defects_cached_replays():
    # A witness must MEASURE. The orchestrator's 'cached' row means the
    # four-file guard replayed an older run — the host wall of the verdict
    # would be staging fiction riding a replayed sidecar.
    assert probe.freshness_law("cached") is not None
    assert probe.freshness_law("  cached  ") is not None          # tolerant
    assert probe.freshness_law("ok") is None
    assert probe.freshness_law("fail: container run failed (exit 137)") is None
