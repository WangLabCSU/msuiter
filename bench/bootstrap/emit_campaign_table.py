#!/usr/bin/env python3
"""Emit the campaign's 9-column pinned timings table from its arm witnesses.

(U-M7-04 GO-05, charter SCOPE B.) One row per arm, read from
witnesses/arm_A{1,2,3}.jsonl — the same bytes the reader-side verifier will
re-derive the ratio from, so the table can never disagree with the witnesses.
host/hw_profile are written from the live environment (socket.gethostname /
M7_HW_PROFILE), exactly the pins verify_campaign.py --hw-profile attests.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent               # bench/bootstrap
M7 = HERE.parent / "m7"                              # bench/m7
if str(M7) not in sys.path:
    sys.path.insert(0, str(M7))

from competitors import timings                       # noqa: E402

# (arm, cell middle, tool) — the row identity of the three competing entries
ROWS = (("A1", "sigminer_serial", "sigminer"),
        ("A2", "msuiter_pool", "msuiter"),
        ("A3", "msuiter_single", "msuiter"))


def arm_record(witness: Path) -> dict:
    if not witness.is_file():
        raise FileNotFoundError(str(witness))
    recs = [json.loads(line) for line in
            witness.read_text(encoding="utf-8").splitlines() if line.strip()]
    arms = [r for r in recs if r.get("kind") == "arm"]
    if len(arms) != 1:                    # single authoritative shot, again
        raise ValueError(f"{witness.name}: expected one arm witness, "
                         f"{len(arms)} found")
    return arms[0]


def main(argv: list[str] | None = None) -> tuple[int, str]:
    ap = argparse.ArgumentParser(prog="emit_campaign_table")
    ap.add_argument("--campaign", required=True)
    ap.add_argument("--host", default=socket.gethostname())
    args = ap.parse_args(list(sys.argv[1:] if argv is None else argv))
    campaign = Path(args.campaign)
    witnesses = campaign / "witnesses"
    profile = os.environ.get(timings.HW_PROFILE_ENV, "")
    if not profile.strip():
        return 2, "M7_HW_PROFILE unset — an unpinned campaign table is refuse-to-file"
    try:
        rows, shape = [], None
        for arm, middle, tool in ROWS:
            rec = arm_record(witnesses / f"arm_{arm}.jsonl")
            shape = rec["shape"]
            rows.append({"cell": f"bootstrap__{middle}__K{shape['K']}S{shape['S']}",
                         "tool": tool, "arm": arm, "n": str(shape["S"]),
                         "seconds": rec["wall"], "status": "ok",
                         "cpu_seconds": rec["cpu"], "host": args.host,
                         "hw_profile": profile})
    except (ValueError, KeyError, FileNotFoundError) as exc:
        return 2, f"unemitable campaign table: {exc}"
    out = campaign / "campaign_timings.csv"
    timings.write_timings(out, rows)
    return 0, json.dumps({"rows": len(rows), "out": str(out),
                          "shape": shape, "host": args.host})


if __name__ == "__main__":
    rc, out = main()
    print(out)
    sys.exit(rc)
