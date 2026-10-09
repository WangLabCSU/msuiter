"""⑫ Matrix-runner extensions for U-M7-03 (arms × N × reps @ pinned seeds).

Seams under contract (GREEN implements; RED-by-absence now):

  run_bench.main(--n-list <csv>)   per-arm N-point filter — the pilot/shard
      selection hook; mirrors the --arms filter idiom exactly (nonmatching
      filter => exit 2 with a printed reason, never a silent empty matrix).
  run_bench.main(--dry-run)        print the machine-readable matrix plan as
      one JSON document on stdout and exit 0 WITHOUT touching the
      filesystem (no cachedir/outdir creation, no seeds, no invocations).
  run_bench.build_plan(args)       the pure planner behind --dry-run.
  tools/verify_seed_determinism.py re-execute one cell from a completed
      cachedir through the same frozen pipeline into a scratch cache and
      byte-compare intervals.csv / errors.log / manifest.json — timing.json
      stays the documented exclusion (wall/jitter channel, verify_rehearsal
      precedent). Exit 0 identical, 1 drift, 2 inadmissible input.

Seed pinning (the reproducibility contract of the mission): every tool seed
flows through the frozen g0.seeds derivation (master 20260928, FNV-1a +
SplitMix64, m7-tool namespace, int32 fold). Unit ⑥ pins the exact numbers
for representative cells AND re-derives them in a fresh interpreter, so the
committed records stay re-runnable-to-the-same-numbers across processes and
across any future refactor of the harness.
"""

from __future__ import annotations

import io
import json
import subprocess
import shutil
import sys
import tempfile
import contextlib
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
for _p in (str(HERE), str(HERE / "tools")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import run_bench                                      # noqa: E402
from competitors import docker_cmd                     # noqa: E402
from competitors.registry import REGISTRY              # noqa: E402


# ---- shared helpers ------------------------------------------------------

def _tmp() -> Path:
    return Path(tempfile.mkdtemp(prefix="m7mr_"))


def _run(argv: list[str]) -> tuple[int, str, str]:
    """Call run_bench.main, normalising argparse rejections (SystemExit) to
    an rc so a missing flag reports FAIL, not a dispatcher crash."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = run_bench.main(argv)
        except SystemExit as e:                        # argparse: unknown flag
            rc = int(e.code) if e.code is not None else 2
    return rc, out.getvalue(), err.getvalue()


def _base(tmp: Path, competitors: str, adapter: str) -> list[str]:
    return ["--profile", "smoke", "--adapter", adapter,
            "--competitors", competitors,
            "--cachedir", str(tmp / "cache"), "--outdir", str(tmp / "results")]


def _tool_rows(tmp: Path) -> list[dict]:
    results = tmp / "results"
    files = sorted(p for p in results.iterdir()
                   if p.name.startswith("timings_m7_") and p.name.endswith(".csv"))
    assert len(files) == 1, f"expected one authoritative table, got {files}"
    import csv as _csv
    with files[0].open(newline="", encoding="utf-8") as fh:
        return list(_csv.DictReader(fh))


# ---- ①②③ --n-list: the pilot/shard N-selection hook ----------------------

def test_n_list_filter_selects_requested_grid_points():
    """The smoke grid main{100,1000} + comp_clock_only{1000} + nb{1000},
    filtered to --n-list 100, must leave exactly the main@100 cell."""
    tmp = _tmp()
    try:
        rc, out, err = _run(_base(tmp, "mock", "mock") + ["--n-list", "100"])
        assert rc == 0, f"n-list flag not honored (rc={rc}) err={err[-300:]}"
        rows = _tool_rows(tmp)
        assert [(r["tool"], r["arm"], int(r["n"])) for r in rows] == \
            [("mock", "main", 100)], f"unexpected cell set: {rows}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_n_list_rejects_grid_with_no_match():
    """A grid point absent from every arm is a caller error: exit 2 with a
    printed reason, no authoritative artifacts written (mirrors --arms)."""
    tmp = _tmp()
    try:
        rc, out, err = _run(_base(tmp, "mock", "mock") + ["--n-list", "7"])
        assert rc == 2, f"nonmatching n-list must exit 2, got {rc}"
        assert "--n-list" in err and "matched no" in err, \
            f"missing fail-fast reason in stderr: {err!r}"
        results = tmp / "results"
        tables = [p for p in results.iterdir()
                  if p.name.startswith("timings_m7_")] if results.exists() else []
        assert not tables, "failed selection must not emit a timings table"
        assert not (results / "Seeds.txt").exists()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_n_filter_drops_empty_arms_but_keeps_others():
    """Arms whose n_list empties under the filter drop out; the run stays
    green on the surviving arms (per-arm intersection, not all-or-nothing)."""
    tmp = _tmp()
    try:
        rc, out, err = _run(_base(tmp, "mock", "mock")
                            + ["--arms", "main,comp_clock_only", "--n-list", "100"])
        assert rc == 0, f"rc={rc} err={err[-300:]}"
        rows = _tool_rows(tmp)
        assert {(r["arm"], int(r["n"])) for r in rows} == {("main", 100)}, \
            f"expected main@100 only, got {rows}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---- ④⑤ --dry-run: machine-readable plan, zero side effects --------------

def test_dry_run_plan_is_pinned_shape_and_side_effect_free():
    """The pilot projection needs a committed, machine-readable statement of
    the matrix actually selected — and a dry run must not touch the disk."""
    tmp = _tmp()
    try:
        rc, out, err = _run([
            "--profile", "degraded", "--adapter", "docker",
            "--competitors", "sigminer,sigprofiler",
            "--arms", "main", "--n-list", "100", "--reps", "1",
            "--cachedir", str(tmp / "cache"), "--outdir", str(tmp / "results"),
            "--dry-run"])
        assert rc == 0, f"rc={rc} err={err[-300:]}"
        plan = json.loads(out[out.index("{"):])        # tolerate log lines
        assert plan["profile"] == "degraded" and plan["adapter"] == "docker"
        assert plan["competitors"] == ["sigminer", "sigprofiler"]
        assert plan["caps"] == list(docker_cmd.THREAD_CAPS)
        assert plan["cells"] == [
            {"tool": t, "arm": "main", "n": 100, "reps": 1}
            for t in ("sigminer", "sigprofiler")]
        assert plan["invocations"] == 2 and plan["samples_total"] == 2
        assert plan["master_seed"] == 20260928 and plan["tool_namespace"] == "m7-tool"
        for tool in ("sigminer", "sigprofiler"):
            prov = plan["provenance"][tool]
            spec = REGISTRY[tool]
            assert prov == {"version": spec.version, "image_ref": spec.image_ref,
                           "image_digest": spec.image_digest, "status": spec.status}, \
                f"plan provenance drifted from the registry for {tool}"
        assert not (tmp / "results").exists() and not (tmp / "cache").exists(), \
            "dry-run wrote to disk"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_dry_run_plan_matches_executed_cell_set():
    """The plan is the contract for the execution: same argv through the
    mock adapter must produce exactly the planned (tool, arm, n) cells."""
    tmp = _tmp()
    try:
        argv = _base(tmp, "sigminer,sigprofiler", "mock") + \
            ["--arms", "main", "--n-list", "1000", "--reps", "1"]
        rc, out, err = _run(argv + ["--dry-run"])
        assert rc == 0, f"rc={rc} err={err[-300:]}"
        planned = {(c["tool"], c["arm"], c["n"]) for c in json.loads(out[out.index("{"):])["cells"]}
        rc, out, err = _run(argv)
        assert rc == 0, f"rc={rc} err={err[-300:]}"
        executed = {(r["tool"], r["arm"], int(r["n"])) for r in _tool_rows(tmp)}
        assert planned == executed, f"plan/exec mismatch: {planned} vs {executed}"
        assert all(r["status"] in ("ok", "cached") for r in _tool_rows(tmp))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---- ⑥ seed pinning: golden numbers + cross-process re-derivation ---------

GOLDENS = {
    ("sigminer", "main", 100, 3): {
        "batch": 1815578668,
        "samples": {"main__N100__r0": 378370763,
                    "main__N100__r1": 1473519166,
                    "main__N100__r2": 1018102052}},
    ("sigprofiler", "main", 100, 3): {
        "batch": 690095989,
        "samples": {"main__N100__r0": 157346364,
                    "main__N100__r1": 1802517059,
                    "main__N100__r2": 762205177}},
    ("mock", "main", 1000, 5): {
        "batch": 1013628229,
        "samples": {"main__N1000__r0": 1978792614,
                    "main__N1000__r1": 383088338,
                    "main__N1000__r2": 1888956016,
                    "main__N1000__r3": 245782274,
                    "main__N1000__r4": 150645486}},
}

_CHILD = ("import sys, json; sys.path.insert(0, '.'); "
          "from run_bench import m7_seeds; "
          "print(json.dumps(list(m7_seeds(*json.loads(sys.argv[1])))))")


def test_seed_maps_are_pinned_and_cross_process_stable():
    """Two independent proofs of the reproducibility contract: the derived
    maps equal the committed golden numbers, and a fresh interpreter process
    re-derives exactly the same values from the seed record alone."""
    for (comp, arm, n, reps), want in GOLDENS.items():
        batch, samples = run_bench.m7_seeds(comp, arm, n, reps)
        assert batch == want["batch"], f"{comp}/{arm}/{n}: batch drift"
        assert samples == want["samples"], f"{comp}/{arm}/{n}: sample-map drift"
        proc = subprocess.run([sys.executable, "-c", _CHILD,
                               json.dumps([comp, arm, n, reps])],
                              cwd=str(HERE), capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr[-300:]
        got_batch, got_samples = json.loads(proc.stdout)
        assert [got_batch, got_samples] == [want["batch"], want["samples"]], \
            f"{comp}/{arm}/{n}: cross-process re-derivation diverged"


# ---- ⑩ cache-key hygiene ----------------------------------------------------

def test_cell_identity_covers_provider_seed():
    """Cache-key completeness (the 2026-10-07 stale-cache cure class): the
    provider seed changes the generated counts, so it must sit inside the
    hashed identity — one cachedir can never silently serve two seeds."""
    args = run_bench.parse_args(["--profile", "smoke", "--adapter", "mock",
                                 "--provider-seed", "7"])
    ident = run_bench.cell_identity("sigminer", REGISTRY["sigminer"], args)
    assert ident.get("provider_seed") == 7, \
        f"provider_seed absent from cache identity: {sorted(ident)}"
    assert ident["caps"] == list(docker_cmd.THREAD_CAPS)


# ---- ⑦⑧⑨ resample-verify: the seed-determinism gate ----------------------

def _mock_cell(tmp: Path, provider_seed: int = 0) -> str:
    argv = _base(tmp, "mock", "mock") + ["--arms", "main", "--n-list", "1000",
                                         "--reps", "1",
                                         "--provider-seed", str(provider_seed)]
    rc, out, err = _run(argv)
    assert rc == 0, f"canonical mock run failed rc={rc} err={err[-300:]}"
    return "mock__main__N1000"


def _verify(argv: list[str]) -> tuple[int, dict]:
    """Contract: the tool's final stdout line is the machine-readable JSON
    verdict (human lines may precede it; nothing else trails)."""
    import verify_seed_determinism as vsd
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = vsd.main(argv)
    lines = [ln for ln in out.getvalue().splitlines() if ln.strip()]
    assert lines, "resample-verify printed no verdict line"
    return rc, json.loads(lines[-1])


def test_resample_verify_ok_on_reexecuted_mock_cell():
    """Same seed record through the same pipeline in a fresh cache must come
    back byte-identical on the three attestable files."""
    tmp = _tmp()
    try:
        cell = _mock_cell(tmp)
        rc, verdict = _verify(["--cachedir", str(tmp / "cache"), "--cell", cell,
                              "--profile", "smoke", "--adapter", "mock",
                              "--work", str(tmp / "work")])
        assert rc == 0, f"verdict rc={rc}: {verdict}"
        assert verdict["ok"] and verdict["cell"] == cell
        assert verdict["reps"] == 1
        assert set(verdict["byte_equal"]) == {"intervals.csv", "errors.log",
                                             "manifest.json"}
        assert all(verdict["byte_equal"].values()), verdict
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_resample_verify_detects_drift_from_crossed_provider_seed():
    """The detector must actually detect: re-deriving the inputs under a
    different provider seed produces different counts, and the tool must say
    DRIFT (exit 1), never green over a changed cell."""
    tmp = _tmp()
    try:
        cell = _mock_cell(tmp, provider_seed=0)
        rc, verdict = _verify(["--cachedir", str(tmp / "cache"), "--cell", cell,
                               "--profile", "smoke", "--adapter", "mock",
                               "--provider-seed", "7", "--work", str(tmp / "work")])
        assert rc == 1, f"crossed provider-seed resample must report DRIFT, rc={rc}"
        assert not verdict["ok"]
        assert not verdict["byte_equal"]["intervals.csv"]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_resample_verify_refuses_incomplete_canonical_cell():
    """skip-not-skip on the read side: an incomplete canonical cell is
    inadmissible input (exit 2), never a vacuous pass."""
    tmp = _tmp()
    try:
        cell = _mock_cell(tmp)
        (tmp / "cache" / "cells" / cell / "out" / "intervals.csv").unlink()
        rc, verdict = _verify(["--cachedir", str(tmp / "cache"), "--cell", cell,
                               "--profile", "smoke", "--adapter", "mock",
                               "--work", str(tmp / "work")])
        assert rc == 2, f"incomplete canonical cell must exit 2, got {rc}"
        assert "intervals.csv" in verdict.get("reason", ""), verdict
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
