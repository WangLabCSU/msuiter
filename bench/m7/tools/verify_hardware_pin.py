#!/usr/bin/env python3
"""Reader-side hardware-pin verifier for a committed authoritative table.

(U-M7-04 GO-05, ROADMAP:100 hardware-pinned bench full table.) The authoring gate in
run_bench makes an unattested authoritative table impossible to birth; this
tool is the other half: the check a *reader* re-runs against a table that
already sits in the repository, so a docs citation can point at a same-window
verdict instead of at prose. It verdicts the table from its own bytes — the
pin columns are data in the CSV, not a story in a document.

Usage (repository root bench/m7):
    python3 -m tools.verify_hardware_pin --table \
        ../results/docker_m7_degraded_<ts>/timings_sharded_master.csv \
        --host <measured-hostname> --hw-profile '<machine-class pin>'

The JSON verdict on stdout is the citable artifact (rc 0 = ok; rc 1 = named
offender cells; rc 2 = the table itself unreadable). Defaults: --host from
socket.gethostname(), --hw-profile from M7_HW_PROFILE (the operator channel).
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import timings                     # noqa: E402
from tools import matrix_governance as gov          # noqa: E402


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        prog="verify_hardware_pin",
        description="Verdict a committed timings table's hardware pins from "
                    "its own bytes (U-M7-04 GO-05).")
    ap.add_argument("--table", required=True,
                    help="path to a timings CSV (9-column pin schema)")
    ap.add_argument("--host", default=socket.gethostname(),
                    help="measured environment hostname (default: this host)")
    ap.add_argument("--hw-profile", default=None,
                    help="machine-class pin the rows must carry (default: "
                         f"{timings.HW_PROFILE_ENV})")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> tuple[int, str]:
    args = parse_args(list(sys.argv[1:] if argv is None else argv))
    path = Path(args.table)
    if not path.is_file():
        return 2, json.dumps({"ok": False, "error": f"no such table: {path}"})
    try:
        rows = timings.read_timings(path)
    except Exception as exc:                      # unreadable/foreign table
        return 2, json.dumps({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
    profile = args.hw_profile if args.hw_profile is not None \
        else os.environ.get(timings.HW_PROFILE_ENV, "")
    verdict = gov.hardware_pin_verdict(rows, host=args.host, hw_profile=profile)
    verdict["table"] = str(path)
    return (0 if verdict["ok"] else 1), json.dumps(verdict, sort_keys=True)


if __name__ == "__main__":
    rc, out = main()
    print(out)
    sys.exit(rc)
