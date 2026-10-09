#!/usr/bin/env python3
"""Resample-verify one matrix cell against its seed record (U-M7-03).

The mission's reproducibility contract in executable form: a benchmark record
is worth paper only if re-running it from its own seeds comes back
byte-identical. This tool re-executes one cell of a completed cachedir
through the same frozen pipeline — same profile/adapter/provider flags, the
reps count read back from the cell's own manifest — into an isolated scratch
cache, then byte-compares the three attestable output files.

timing.json is the documented exclusion (it is the wall/jitter channel; its
attribution is the timings table's job — verify_rehearsal precedent).

Exit contract:
  0  byte-identical resample (the cell reproduces from its seed record)
  1  DRIFT — a seed-pinned cell that does not reproduce, or an incomplete
     resample run (never green over a changed cell)
  2  inadmissible input — unparseable cell key or incomplete canonical cell
     (skip-not-skip on the read side: a broken record is reported, never
     vacuously passed)

The final stdout line is the machine-readable JSON verdict (committed as the
determinism evidence next to the matrix records); human-readable detail goes
to stderr.

Usage:
  python3 tools/verify_seed_determinism.py --cachedir cache/bench_degraded_docker \
      --cell sigminer__main__N100 --profile degraded --adapter docker \
      [--provider synthetic --provider-seed 0 --work DIR --json PATH]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # bench/m7
for _p in (str(HERE), str(HERE.parent / "g0")):         # frozen g0, read-only
    if _p not in sys.path:
        sys.path.insert(0, _p)

import run_bench                                         # noqa: E402
from run_bench import GUARD_FILES                        # noqa: E402
from scoring.cells import parse_cell_key                # noqa: E402

# The three attestable outputs (timing.json excluded by documented design).
BYTE_EQUAL_FILES = ("intervals.csv", "errors.log", "manifest.json")


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def parse_args(argv=None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cachedir", required=True)
    ap.add_argument("--cell", required=True,
                    help="cell key <tool>__<arm>__N<n> under <cachedir>/cells/")
    ap.add_argument("--profile", default="degraded")
    ap.add_argument("--adapter", default="docker", choices=["mock", "docker"])
    ap.add_argument("--provider", default="synthetic")
    ap.add_argument("--provider-seed", type=int, default=0)
    ap.add_argument("--work", default=None,
                    help="scratch root (default: fresh mkdtemp)")
    ap.add_argument("--json", default=None, dest="json_path",
                    help="also write the verdict JSON to this path")
    return ap.parse_args(argv)


def verify_cell(*, cachedir, cell: str, profile: str, adapter: str,
                provider: str, provider_seed: int, work=None) -> tuple:
    """Re-run one cell into a scratch cache and byte-compare. Returns
    ``(exit_code, verdict)`` — the single source of the exit contract."""
    verdict = {"cell": cell, "ok": False}
    parsed = parse_cell_key(cell)
    if parsed is None:
        verdict["reason"] = (f"not a cell key: {cell!r} "
                             f"(want <tool>__<arm>__N<n>)")
        return 2, verdict
    tool, arm, n = parsed
    canonical = Path(cachedir) / "cells" / cell / "out"
    missing = [name for name in GUARD_FILES if not (canonical / name).exists()]
    if missing:
        verdict["reason"] = f"incomplete canonical cell, missing: {missing}"
        return 2, verdict
    manifest = json.loads((canonical / "manifest.json").read_text(encoding="utf-8"))
    reps = int(manifest["reps"])
    verdict["reps"] = reps

    scratch = (Path(work) if work is not None
               else Path(tempfile.mkdtemp(prefix="m7resample_")))
    cell_cache = scratch / f"resample_{cell}"           # isolate repeats
    argv = ["--profile", profile, "--adapter", adapter,
            "--competitors", tool, "--arms", arm, "--n-list", str(n),
            "--reps", str(reps), "--provider", provider,
            "--provider-seed", str(provider_seed),
            "--shard-tag", "resample",                   # non-authoritative pass
            "--cachedir", str(cell_cache), "--outdir", str(cell_cache / "out")]
    print(f"[resample] re-executing {cell} (reps={reps}) via run_bench "
          f"into {cell_cache}", file=sys.stderr)
    rc = run_bench.main(argv)

    fresh = cell_cache / "cells" / cell / "out"
    missing2 = [name for name in GUARD_FILES if not (fresh / name).exists()]
    if missing2:
        verdict["reason"] = f"resample run incomplete (rc={rc}), missing: {missing2}"
        verdict["resample_rc"] = rc
        return 1, verdict
    byte_equal, digests = {}, {}
    for name in BYTE_EQUAL_FILES:
        ha, hb = _digest(canonical / name), _digest(fresh / name)
        byte_equal[name] = ha == hb
        digests[name] = [ha, hb]
    verdict.update({"byte_equal": byte_equal, "digests": digests,
                    "resample_rc": rc, "canonical": str(canonical),
                    "resample": str(fresh)})
    verdict["ok"] = rc == 0 and all(byte_equal.values())
    if not verdict["ok"]:
        verdict["reason"] = ("resample rc non-zero or bytes differ: "
                             f"{ {k: v for k, v in byte_equal.items() if not v} }")
    return (0 if verdict["ok"] else 1), verdict


def main(argv=None) -> int:
    args = parse_args(argv)
    rc, verdict = verify_cell(cachedir=args.cachedir, cell=args.cell,
                              profile=args.profile, adapter=args.adapter,
                              provider=args.provider,
                              provider_seed=args.provider_seed,
                              work=args.work)
    verdict["verdict"] = {0: "OK", 1: "DRIFT", 2: "INADMISSIBLE"}[rc]
    if args.json_path:
        Path(args.json_path).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json_path).write_text(
            json.dumps(verdict, sort_keys=True, indent=1), encoding="utf-8")
    print(json.dumps(verdict, sort_keys=True))          # final stdout line
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
