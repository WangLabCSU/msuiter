"""④ cache-hit guard + authoritative outdir contract (U-M7-02 §4.4/§4.5).

The orchestrator seam under contract (GREEN implements; RED-by-absence now):

  run_bench.main(argv)  — mirrors run_grid.py's argument idiom:
      --profile {smoke,...}  --adapter {mock,docker}  --competitors <csv>
      --cachedir <dir>  --outdir <dir>  [--force-rerun]

  cell layout (inherited from G0): <cachedir>/cells/<competitor>__<arm>__N<n>/
      in/   {counts.csv, catalog.csv, params.json, .data_hash}
      out/  {intervals.csv, errors.log, manifest.json, timing.json}

  re-run guard: a cell is trusted only when all FOUR out/ guard files are
  present alongside a matching .data_hash (stricter than G0's two-file
  guard: the fairness table is not attestable without manifest+timing).

  authoritative outdir (final cache-hit pass): Seeds.txt, timings_m7_*.csv
  (7-col schema), judgment_m7_*.md (fairness attestation per §4.5).
"""

from __future__ import annotations

import csv
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import run_bench                                      # noqa: E402 (RED seam)

GUARD_FILES = ("intervals.csv", "errors.log", "manifest.json", "timing.json")


def _tmp() -> Path:
    return Path(tempfile.mkdtemp(prefix="m7oc_"))


def _smoke_argv(tmp: Path) -> list:
    return ["--profile", "smoke", "--adapter", "mock",
            "--competitors", "sigminer",
            "--cachedir", str(tmp / "cache"), "--outdir", str(tmp / "results")]


def _timings_rows(results: Path) -> list:
    files = sorted(p for p in results.iterdir()
                    if p.name.startswith("timings_m7_") and p.name.endswith(".csv"))
    assert files, f"no timings_m7_*.csv in authoritative outdir: {sorted(p.name for p in results.iterdir())}"
    assert len(files) == 1, "final pass must emit exactly one authoritative timings table"
    with files[0].open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        assert reader.fieldnames == ["cell", "tool", "arm", "n", "seconds",
                                     "status", "cpu_seconds"], \
            f"authoritative timings header drifted: {reader.fieldnames}"
        return list(reader)


def test_smoke_pass_emits_authoritative_file_set():
    """§4.5: the authoritative outdir carries Seeds.txt + the 7-col timings
    table + the fairness attestation document."""
    tmp = _tmp()
    try:
        rc = run_bench.main(_smoke_argv(tmp))
        assert rc == 0, f"smoke pass exited {rc}"
        results = tmp / "results"
        names = {p.name for p in results.iterdir()}
        assert "Seeds.txt" in names, f"Seeds.txt missing: {sorted(names)}"
        assert any(n.startswith("timings_m7_") for n in names)
        jud = [n for n in names if n.startswith("judgment_m7_")]
        assert jud, f"judgment_m7_*.md missing: {sorted(names)}"
        text = (results / jud[0]).read_text(encoding="utf-8")
        assert "fairness" in text.lower() and "attestation" in text.lower(), \
            "judgment doc must carry the §4.5 fairness attestation framing"
        rows = _timings_rows(results)
        assert rows, "authoritative timings table has no cells"
        assert {r["tool"] for r in rows} == {"sigminer"}
        assert all(r["status"] in ("ok", "cached") for r in rows), \
            "a green smoke pass may not leave failed cells silent"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_second_pass_is_cache_hit_and_records_zero_seconds():
    """§4.4 cache-hit recompute pass: the serial authoritative pass after a
    complete run must not re-invoke competitors (status cached, seconds 0),
    exactly like the G0 sharded-then-serial idiom."""
    tmp = _tmp()
    try:
        assert run_bench.main(_smoke_argv(tmp)) == 0
        assert run_bench.main(_smoke_argv(tmp)) == 0
        # both passes share --outdir; the last-written timings emission is
        # the authoritative final pass (same convention as G0's serial tail)
        results = tmp / "results"
        files = sorted(p for p in results.iterdir()
                       if p.name.startswith("timings_m7_") and p.name.endswith(".csv"))
        with files[-1].open(newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        assert rows and all(r["status"] == "cached" for r in rows), \
            f"second pass re-invoked competitors: " \
            f"{[(r['cell'], r['status']) for r in rows if r['status'] != 'cached'][:5]}"
        assert all(float(r["seconds"]) == 0.0 for r in rows)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_missing_sidecar_guard_forces_rerun_not_trust():
    """Losing any of the four guard files must demote the cell from
    cache-hit to re-run — the four-way guard is the fairness-table contract."""
    tmp = _tmp()
    try:
        assert run_bench.main(_smoke_argv(tmp)) == 0
        cells = tmp / "cache" / "cells"
        assert cells.is_dir(), f"cell layout not at <cachedir>/cells: {cells}"
        cell_dirs = sorted(p for p in cells.iterdir() if p.is_dir())
        assert cell_dirs, "smoke profile produced no cells"
        victim = cell_dirs[0]
        assert victim.name.count("__") == 2 and victim.name.split("__")[0] == "sigminer", \
            f"cell key layout must be <competitor>__<arm>__N<n>, got {victim.name}"
        (victim / "out" / "manifest.json").unlink()     # one guard file gone
        assert run_bench.main(_smoke_argv(tmp)) == 0
        results = tmp / "results"
        files = sorted(p for p in results.iterdir()
                       if p.name.startswith("timings_m7_") and p.name.endswith(".csv"))
        with files[-1].open(newline="", encoding="utf-8") as fh:
            rows = {r["cell"]: r for r in csv.DictReader(fh)}
        assert victim.name in rows, f"tampered cell absent from timings: {victim.name}"
        assert rows[victim.name]["status"] == "ok", \
            f"tampered cell was trusted despite missing manifest.json " \
            f"(status={rows[victim.name]['status']!r})"
        untouched = [n for n, r in rows.items() if n != victim.name]
        assert all(rows[n]["status"] == "cached" for n in untouched), \
            "untouched cells must stay cache-hit while the victim re-runs"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
