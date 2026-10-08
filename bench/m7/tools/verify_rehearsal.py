#!/usr/bin/env python3
"""Verification half of the mock smoke rehearsal (see smoke_rehearsal.sh).

Checks, exit non-zero with a printed verdict on any violation:
  ① every cell exists under BOTH caches with all four guard files, and
     intervals.csv / errors.log / manifest.json are byte-identical between
     the sharded and the serial tree (timing.json excluded by design — the
     wall/jitter channel; its attribution is check ③);
  ② the sharded tree's final serial pass is all-cached with 0.0 seconds;
  ③ timings_sharded_master.csv carries exactly one measured row per cell,
     status ok, seconds > 0 — every measured second attributable;
  ④ Seeds.txt row-sets identical between the orchestration modes.
"""

from __future__ import annotations

import csv
import hashlib
import sys
from pathlib import Path

GUARD_FILES = ("intervals.csv", "errors.log", "manifest.json", "timing.json")
BYTE_EQUAL_FILES = ("intervals.csv", "errors.log", "manifest.json")


def _timings(outdir: Path) -> list[dict]:
    files = sorted(p for p in outdir.iterdir()
                   if p.name.startswith("timings_m7_") and p.name.endswith(".csv"))
    assert files, f"no timings table in {outdir}"
    with files[-1].open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def _seeds_rows(path: Path) -> set[str]:
    body = [ln for ln in path.read_text(encoding="utf-8").splitlines()
            if ln and not ln.startswith("#")]
    return set(body[1:])                       # drop the column header


def main(a: Path, b: Path) -> int:
    problems: list[str] = []
    cells_a = sorted(p for p in (a / "cache" / "cells").iterdir() if p.is_dir())
    cells_b = sorted(p for p in (b / "cache" / "cells").iterdir() if p.is_dir())
    if [p.name for p in cells_a] != [p.name for p in cells_b] or not cells_a:
        problems.append(f"cell sets differ: {len(cells_a)} vs {len(cells_b)}")
    for pa, pb in zip(cells_a, cells_b):
        for name in GUARD_FILES:
            fa, fb = pa / "out" / name, pb / "out" / name
            if not fa.exists():
                problems.append(f"sharded cell {pa.name} missing {name}")
            if not fb.exists():
                problems.append(f"serial cell {pb.name} missing {name}")
        for name in BYTE_EQUAL_FILES:
            ha = _digest(pa / "out" / name)
            hb = _digest(pb / "out" / name)
            if ha != hb:
                problems.append(f"{pa.name}/{name} not byte-equal: {ha} vs {hb}")

    final_rows = _timings(a / "final")
    if not final_rows:
        problems.append("sharded final pass emitted no rows")
    bad_cached = [r["cell"] for r in final_rows
                  if r["status"] != "cached" or float(r["seconds"]) != 0.0]
    if bad_cached:
        problems.append(f"final pass re-invoked cells: {bad_cached[:5]}")

    with (a / "timings_sharded_master.csv").open(newline="", encoding="utf-8") as fh:
        master = list(csv.DictReader(fh))
    by_cell = {r["cell"]: r for r in master}
    expected = {r["cell"] for r in _timings(b / "final")}
    if set(by_cell) != expected:
        problems.append(f"master coverage mismatch: missing {sorted(expected - set(by_cell))[:5]}")
    for cell, r in by_cell.items():
        if r["status"] != "ok" or float(r["seconds"]) <= 0.0:
            problems.append(f"unattributable measured second: {cell} "
                           f"status={r['status']} seconds={r['seconds']}")
    if _seeds_rows(a / "final" / "Seeds.txt") != _seeds_rows(b / "final" / "Seeds.txt"):
        problems.append("Seeds.txt row-sets differ between orchestration modes")

    print(f"[rehearsal] cells={len(cells_a)} master_rows={len(master)} "
          f"(measured ok) final_pass_cached={len(final_rows)}")
    for cell, r in sorted(by_cell.items()):
        print(f"[mock cell] {cell}: wall={r['seconds']}s cpu={r['cpu_seconds']}s "
              f"status={r['status']}")
    if problems:
        print("REHEARSAL-FAILED:")
        for p in problems:
            print(f"  ✗ {p}")
        return 1
    print("REHEARSAL-VERDICT: shard-vs-serial byte-equal; cache-hit final pass; "
          "all measured seconds attributable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1]), Path(sys.argv[2])))
