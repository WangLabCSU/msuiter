#!/usr/bin/env python3
"""Nine-column authoritative rollup for the G0 primary campaign timings.

Merges the shard-pass timings tables (shard-root/<tag>/timings_primary_*.csv)
with the final serial pass table (the repair leg: a shard cell lost to an
exit-137 re-measures there). Per cell the FIRST measured row wins
(shard ok/cached beats a later cache-hit restatement); a shard fail row is
replaced by the final pass row when that one measured. Adds the pin columns
of the nine-column contract; cpu_seconds carries the literal `unmeasured`
because the adapter protocol reports no container CPU accounting and
fabricating one would be a false claim (see the design booking §7).
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

HEADER = ["cell", "tool", "arm", "n", "seconds", "status",
          "cpu_seconds", "host", "hw_profile"]


def _read6(path: Path) -> list:
    with path.open(newline="", encoding="utf-8") as fh:
        rows = [r for r in csv.DictReader(fh) if r.get("cell")]
    return rows


def merge(shard_root: Path, final_path: Path) -> dict:
    """cell -> merged row dict (six measured columns)."""
    merged = {}
    for f in sorted(shard_root.glob("*/timings_primary_*.csv")):
        for r in _read6(f):
            if r["cell"] not in merged:
                merged[r["cell"]] = r
    for r in _read6(final_path):
        prev = merged.get(r["cell"])
        if prev is None or not prev["status"].startswith(("ok", "cached")):
            merged[r["cell"]] = r
    return merged


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--shard-root", required=True)
    ap.add_argument("--final", required=True)
    ap.add_argument("--host", required=True)
    ap.add_argument("--hw-profile", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    shard_root, final = Path(a.shard_root), Path(a.final)
    if not shard_root.is_dir() or not final.is_file():
        print(f"rollup: unreadable inputs ({shard_root}, {final})", file=sys.stderr)
        return 2
    merged = merge(shard_root, final)
    if not merged:
        print("rollup: zero measured rows — refusing to birth an empty "
              "authoritative table", file=sys.stderr)
        return 2
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(HEADER)
        for cell in sorted(merged):
            r = merged[cell]
            w.writerow([r["cell"], r["tool"], r["arm"], r["n"], r["seconds"],
                        r["status"], "unmeasured", a.host, a.hw_profile])
    print(f"[rollup] {len(merged)} rows -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
