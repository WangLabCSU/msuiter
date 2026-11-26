#!/usr/bin/env python3
"""Reader-side hardware-pin verifier for a committed G0 authoritative table.

The g0-local twin of the M7 canonical instrument (bench/m7/tools): verdicts
the nine-column table from its own bytes — no prose trust — so the docs
citation can point at a same-window JSON verdict. rc 0 ok / 1 named
offenders / 2 unreadable table. Beyond the pin equality of its M7 model it
also fails any row whose cpu_seconds is anything other than the literal
`unmeasured`: this campaign measured no CPU accounting, so a CPU claim is
constructionally unauthorized.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import socket
import sys
from pathlib import Path

HW_PROFILE_ENV = "G0_HW_PROFILE"
COLUMNS = ("cell", "tool", "arm", "n", "seconds", "status",
           "cpu_seconds", "host", "hw_profile")


def verdict(rows: list, host: str, hw_profile: str) -> dict:
    v = {"ok": True, "rows": len(rows), "missing_host": [], "missing_hw_profile": [],
         "mismatched_host": [], "mismatched_hw_profile": [], "unattested_cpu_claim": []}
    for r in rows:
        cell = r.get("cell", "?")
        if not r.get("host"):
            v["missing_host"].append(cell)
        elif r["host"] != host:
            v["mismatched_host"].append(cell)
        if not r.get("hw_profile"):
            v["missing_hw_profile"].append(cell)
        elif r["hw_profile"] != hw_profile:
            v["mismatched_hw_profile"].append(cell)
        if r.get("cpu_seconds") != "unmeasured":
            v["unattested_cpu_claim"].append(cell)
    v["ok"] = not any(v[k] for k in ("missing_host", "missing_hw_profile",
                                     "mismatched_host", "mismatched_hw_profile",
                                     "unattested_cpu_claim")) and len(rows) > 0
    return v


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--table", required=True)
    ap.add_argument("--host", default=socket.gethostname())
    ap.add_argument("--hw-profile", default=os.environ.get(HW_PROFILE_ENV, ""))
    a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    path = Path(a.table)
    if not path.is_file():
        print(json.dumps({"ok": False, "error": f"no such table: {path}"}))
        return 2
    try:
        with path.open(newline="", encoding="utf-8") as fh:
            rows = [r for r in csv.DictReader(fh) if r.get("cell")]
    except Exception as exc:
        print(json.dumps({"ok": False, "error": f"{type(exc).__name__}: {exc}"}))
        return 2
    v = verdict(rows, a.host, a.hw_profile)
    v["table"] = str(path)
    print(json.dumps(v, sort_keys=True))
    return 0 if v["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
