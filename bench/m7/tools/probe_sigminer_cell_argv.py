#!/usr/bin/env python3
"""Execute the REAL sigminer cell argv against the registry-pinned image and
certify it reaches sidecar-schema-valid depth (U-M7-03, controller ruling RB-01).

The pilot's exit-127 catch (the pinned image ships the python ``m7_entry.py``
wrapper but carries no python interpreter, so the cell protocol can never
start) is encoded here as an executable witness, not a transcript: this tool
drives one synthetic cell end-to-end through the frozen pipeline
(``run_bench`` composes the container command, the adapter places the frozen
thread caps before the image token and the real argv
``python3 /work/m7_entry.py --params /work/in/params.json --outdir /work/out
-- <runner...>`` after it), then independently asserts the attestation chain
the ruling demands:

    all four cell outputs present -> timing.json parseable ->
    {ru_utime, ru_stime, cpu_seconds, exit_status} well-formed, consistent,
    child exit 0 -> orchestrator rc 0

That is "cell argv executable + sidecar schema valid", deliberately NOT a
``python3 --version`` smoke. The probe reads the image reference from the
registry, so the same command is the RED witness against slice3-r2 and the
GREEN witness against slice3-r3 after the digest flip.

Exit contract: 0 OK, 1 DEFECT (missing outputs / sidecar chain invalid /
orchestrator rc non-zero), 2 inadmissible invocation (registry row absent).
The final stdout line is the machine-readable JSON verdict; human detail on
stderr.

Usage:
  python3 tools/probe_sigminer_cell_argv.py [--work DIR] [--json PATH]
      [--arm main] [--n 100] [--reps 1]
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # bench/m7
for _p in (str(HERE), str(HERE.parent / "g0")):         # frozen g0, read-only
    if _p not in sys.path:
        sys.path.insert(0, _p)

import run_bench                                          # noqa: E402
from competitors import registry                            # noqa: E402

# The full four-file cell contract (run_bench.GUARD_FILES including the
# timing sidecar -- the probe certifies the sidecar's DEPTH, not just its
# presence, so timing.json is asserted here, not only byte-compared later).
CELL_OUTPUTS = ("intervals.csv", "errors.log", "manifest.json", "timing.json")
SIDECAR_NUMERIC = ("ru_utime", "ru_stime", "cpu_seconds")
CPU_SUM_TOLERANCE = 1e-6


def validate_sidecar(path: Path) -> str | None:
    """Why the timing sidecar is not schema-valid, or ``None`` when it is.

    Schema (adapters/m7_entry.py, memo §4.3): exactly the child-tree rusage
    report -- ``ru_utime + ru_stime == cpu_seconds`` (within float tolerance),
    all numerics non-negative, and ``exit_status == 0`` so the wrapped
    runner itself completed. Wall clock is host-side by design and absent.
    """
    if not path.exists():
        return f"sidecar absent: {path}"
    try:
        sidecar = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return f"sidecar not parseable JSON: {exc}"
    if not isinstance(sidecar, dict):
        return f"sidecar is {type(sidecar).__name__}, want object"
    for key in SIDECAR_NUMERIC:
        if key not in sidecar:
            return f"sidecar missing key {key!r}"
        value = sidecar[key]
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            return f"sidecar {key!r} is {value!r}, want number"
        if value < 0:
            return f"sidecar {key!r} negative: {value!r}"
    if abs(sidecar["cpu_seconds"]
           - (sidecar["ru_utime"] + sidecar["ru_stime"])) > CPU_SUM_TOLERANCE:
        return ("sidecar cpu_seconds != ru_utime + ru_stime: "
                f"{sidecar['cpu_seconds']!r} vs "
                f"{sidecar['ru_utime'] + sidecar['ru_stime']!r}")
    if sidecar.get("exit_status") != 0:
        return (f"wrapped runner exited nonzero per sidecar: "
                f"exit_status={sidecar.get('exit_status')!r}")
    return None


def assess_cell(cell_out: Path, *, run_rc: int,
                provenance: dict) -> tuple[int, dict]:
    """Certify one executed cell; single source of the exit contract.

    Pure over the filesystem plus the orchestrator return code -- the same
    function the offline units exercise and the live witness runs.
    """
    missing = [name for name in CELL_OUTPUTS
               if not (cell_out / name).exists()]
    if missing:
        return 1, {"verdict": "DEFECT", "missing": missing}
    reason = validate_sidecar(cell_out / "timing.json")
    if reason is not None:
        return 1, {"verdict": "DEFECT", "reason": f"sidecar chain invalid: {reason}"}
    if run_rc != 0:
        return 1, {"verdict": "DEFECT", "run_rc": run_rc}
    sidecar = json.loads((cell_out / "timing.json").read_text(encoding="utf-8"))
    return 0, {"verdict": "OK", "sidecar": sidecar,
               "provenance": dict(provenance)}


def _cell_status_tail(cachedir: Path, cell: str) -> str:
    """The orchestrator's recorded status string for ``cell`` (fail tails
    carry the container-exec signature; empty string when none found)."""
    rows: list = []
    for csv_path in sorted(cachedir.glob("out/timings_m7_*.csv")):
        with csv_path.open(newline="", encoding="utf-8") as fh:
            rows = list(csv.reader(fh))
    for row in reversed(rows):
        if row and row[0] == cell:
            return row[5] if len(row) > 5 else ""
    return ""


def parse_args(argv=None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--work", default=None,
                    help="scratch root (default: fresh mkdtemp)")
    ap.add_argument("--json", default=None, dest="json_path",
                    help="also write the verdict JSON to this path")
    ap.add_argument("--arm", default="main")
    ap.add_argument("--n", type=int, default=100, dest="n_point")
    ap.add_argument("--reps", type=int, default=1)
    return ap.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    try:
        spec = registry.lookup("sigminer")
    except Exception as exc:                       # row absent/unloadable
        print(f"probe: inadmissible registry state: {exc}", file=sys.stderr)
        return 2
    provenance = {"name": spec.name, "version": spec.version,
                  "image_ref": spec.image_ref, "image_digest": spec.image_digest,
                  "status": spec.status}
    scratch = (Path(args.work) / f"probe_{hashlib.sha256(str(args).encode()).hexdigest()[:8]}"
               if args.work is not None
               else Path(tempfile.mkdtemp(prefix="m7cellprobe_")))
    cachedir = scratch / "probe_cache"
    cell = f"sigminer__{args.arm}__N{args.n_point}"
    rb_argv = ["--profile", "degraded", "--adapter", "docker",
               "--competitors", "sigminer", "--arms", args.arm,
               "--n-list", str(args.n_point), "--reps", str(args.reps),
               "--provider", "synthetic", "--provider-seed", "0",
               "--shard-tag", "cell-argv",
               "--cachedir", str(cachedir), "--outdir", str(cachedir / "out")]
    print(f"[probe] executing real cell argv for {cell} against "
          f"{spec.image_ref} ({spec.image_digest[:18]}...) into {cachedir}",
          file=sys.stderr)
    run_rc = run_bench.main(rb_argv)
    code, verdict = assess_cell(cachedir / "cells" / cell / "out",
                                run_rc=run_rc, provenance=provenance)
    verdict.update({"cell": cell, "run_rc": run_rc,
                    "status_tail": _cell_status_tail(cachedir, cell)})
    if args.json_path:
        json_path = Path(args.json_path)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(verdict, sort_keys=True, indent=1),
                             encoding="utf-8")
    print(json.dumps(verdict, sort_keys=True))             # final stdout line
    return code


if __name__ == "__main__":
    raise SystemExit(main())
