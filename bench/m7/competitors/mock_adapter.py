"""Mock-style local adapter — the pipeline-selfcheck idiom (G0 mirror).

Same role as ``bench/g0/adapters/mock_runner.py``: proves the orchestration
(generation → adapter → parse → table → authoritative pass, shard vs serial)
without measuring a competitor. Registered as a **fourth spec** for the
smoke rehearsal (memo §10.4) — deliberately kept out of
``competitors.registry.REGISTRY``: the registry table is the PI-approved
competitor selection of memo §2 and the registry test pins its key set;
the mock is an adapter-implementation choice (``--adapter mock``), not a
competitor.

It executes through the same measurement wrapper the containers use
(``adapters/m7_entry.py`` launching G0's mock runner as its single child),
so the mock path exercises the identical rusage/timing.json surface — the
CPU column is measured on the host here exactly as it is measured in the
container there. The mock is deterministic in its seed, which is what makes
the shard-vs-serial byte-equality claim checkable.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from . import docker_cmd
from .registry import CompetitorSpec, STATUS_READY

HERE = Path(__file__).resolve().parents[1]                  # bench/m7
G0_DIR = HERE.parent / "g0"                                 # read-only reuse
M7_ENTRY = HERE / "adapters" / "m7_entry.py"
G0_MOCK_RUNNER = G0_DIR / "adapters" / "mock_runner.py"     # never modified

MOCK_SPEC = CompetitorSpec(
    name="mock",
    runtime="python",
    version="pipeline-selfcheck",
    image_ref="(host-side; no image)",
    image_digest="N/A (host-side mock, no container)",
    status=STATUS_READY,
    entrypoint="python3",
    runner_script="mock_runner.py",
    provenance=("G0 pipeline-selfcheck idiom, executed via "
                "bench/g0/adapters/mock_runner.py read-only through the "
                "shared m7_entry measurement wrapper (memo §10.4)"),
)


def run(cell: dict, spec, catalog_mount: Path | str | None = None) -> dict:
    """Execute one mock cell (no container, no image gate — there is no
    image to be absent). ``spec`` names the *measured-as* competitor for
    the cell identity; the executed work is the deterministic mock."""
    in_dir, out_dir = Path(cell["in_dir"]), Path(cell["out_dir"])
    child = [sys.executable, str(G0_MOCK_RUNNER),
             "--counts", str(in_dir / "counts.csv"),
             "--catalog", str(catalog_mount if catalog_mount is not None
                              else in_dir / "catalog.csv"),
             "--params", str(in_dir / "params.json"),
             "--outdir", str(out_dir)]
    cmd = [sys.executable, str(M7_ENTRY),
           "--params", str(in_dir / "params.json"), "--outdir", str(out_dir),
           "--", *child]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "")[-400:]
        raise RuntimeError(f"mock run failed (exit {proc.returncode}): {tail}")
    missing = docker_cmd.verify_cell_outputs(out_dir, ("intervals.csv",
                                                        "errors.log",
                                                        "timing.json"))
    if missing is not None:
        raise RuntimeError(
            f"mock exited 0 but produced no {missing} — refusing to score "
            f"an empty cell")
    from . import timings
    sidecar = timings.read_timing_sidecar(out_dir / "timing.json")
    return {"cpu_seconds": timings.cpu_seconds_of(sidecar), "sidecar": sidecar}
