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
      [--arm main] [--n 100] [--reps N]
Floor witnesses (RB-09): pass --reps 100 — a REP-1 witness may never gate
a REP-100 protocol class. The --reps default stays 1 for the (L) cell-argv
smoke contract, which certifies EXECUTABILITY, not floor cost.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import tempfile
import time
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


def witness_extras(rb_argv: list[str], *, tool: str, arm: str, n: int,
                    wall_seconds: float) -> dict:
    """Floor-witness provenance extras (controller ruling RB-09(ii)/(5)).

    A probe verdict that seeds a floor anchor must carry its FULL argv —
    ``--reps`` included — plus the host-side wall clock, so a reps mismatch
    (the RB-09 root cause: REP-1 anchors gating REP-100 cells) is
    mechanically detectable by the floor_semantics units instead of living
    in audit folklore. The child-side cpu/utime/stime quartet arrives with
    the validated timing.json sidecar; wall is host-side by design.
    """
    if "--reps" not in rb_argv:
        raise ValueError("witness argv carries no --reps token")
    raw = rb_argv[rb_argv.index("--reps") + 1]
    try:
        reps = int(raw)
    except ValueError:
        raise ValueError(f"witness --reps echo is not integral: {raw!r}") from None
    return {"argv": list(rb_argv), "reps": reps, "tool": tool, "arm": arm,
            "n": n, "wall_seconds": wall_seconds}


def freshness_law(status_tail: str) -> str | None:
    """A floor witness must MEASURE: the orchestrator returning the cell as
    ``cached`` means the four-file guard replayed an earlier run, so the
    host-side wall of this verdict would be staging fiction riding a replayed
    sidecar. Defect the replay; the caller must clear the cell (or use a
    fresh work dir) instead of certifying a replay as a measurement."""
    if status_tail.strip() == "cached":
        return ("probe refused: cell replayed from cache (status 'cached') — "
                "a witness must be a fresh measurement")
    return None


def run_probe(tool: str, *, arm: str, n: int, reps: int,
              json_path: str | None = None, work: str | None = None) -> int:
    """Drive one synthetic ``tool`` cell end-to-end and emit the witness JSON.

    Shared core for the per-tool probe entry points; the tool name is the
    only difference between the sigminer and sigprofiler witnesses (the
    registry row selects image, entrypoint and runner)."""
    try:
        spec = registry.lookup(tool)
    except Exception as exc:                       # row absent/unloadable
        print(f"probe: inadmissible registry state: {exc}", file=sys.stderr)
        return 2
    provenance = {"name": spec.name, "version": spec.version,
                  "image_ref": spec.image_ref, "image_digest": spec.image_digest,
                  "status": spec.status}
    scratch = (Path(work) / f"probe_{hashlib.sha256(f'{tool}|{arm}|{n}|{reps}'.encode()).hexdigest()[:8]}"
               if work is not None
               else Path(tempfile.mkdtemp(prefix="m7cellprobe_")))
    cachedir = scratch / "probe_cache"
    cell = f"{tool}__{arm}__N{n}"
    rb_argv = ["--profile", "degraded", "--adapter", "docker",
               "--competitors", tool, "--arms", arm,
               "--n-list", str(n), "--reps", str(reps),
               "--provider", "synthetic", "--provider-seed", "0",
               "--floor-gate", "off",          # RB-09: a probe measures, it
                                               # never self-adjudicates
               "--shard-tag", "cell-argv",
               "--cachedir", str(cachedir), "--outdir", str(cachedir / "out")]
    print(f"[probe] executing real cell argv for {cell} at REP-{reps} against "
          f"{spec.image_ref} ({spec.image_digest[:18]}...) into {cachedir}",
          file=sys.stderr)
    t0 = time.monotonic()
    run_rc = run_bench.main(rb_argv)
    wall = round(time.monotonic() - t0, 3)
    status_tail = _cell_status_tail(cachedir, cell)
    code, verdict = assess_cell(cachedir / "cells" / cell / "out",
                                run_rc=run_rc, provenance=provenance)
    replay = freshness_law(status_tail)
    if replay is not None:
        code, verdict = 1, {"verdict": "DEFECT", "reason": replay}
    verdict.update({"cell": cell, "run_rc": run_rc, "status_tail": status_tail})
    verdict.update(witness_extras(rb_argv, tool=tool, arm=arm, n=n,
                                  wall_seconds=wall))
    if json_path:
        out_json = Path(json_path)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(json.dumps(verdict, sort_keys=True, indent=1),
                            encoding="utf-8")
    print(json.dumps(verdict, sort_keys=True))             # final stdout line
    return code


def parse_args(argv=None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--work", default=None,
                    help="scratch root (default: fresh mkdtemp)")
    ap.add_argument("--json", default=None, dest="json_path",
                    help="also write the verdict JSON to this path")
    ap.add_argument("--arm", default="main")
    ap.add_argument("--n", type=int, default=100, dest="n_point")
    ap.add_argument("--reps", type=int, default=1,
                    help="protocol reps for a floor witness: pass --reps 100 "
                         "(RB-09: REP-1 anchors cannot gate REP-100 cells)")
    return ap.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    return run_probe("sigminer", arm=args.arm, n=args.n_point,
                     reps=args.reps, json_path=args.json_path,
                     work=args.work)


if __name__ == "__main__":
    raise SystemExit(main())
