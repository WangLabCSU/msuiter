#!/usr/bin/env python3
"""Shared measurement entry — the single argv[1] every M7 cell runs.

In the container this is what the ``docker run`` command invokes
(``competitors/docker_cmd.py::ENTRY_SCRIPT``); the mock path drives the very
same script host-side so the timing surface is identical (memo §4.3).

Contract:
  m7_entry.py --params <params.json> --outdir <out/> -- <child argv...>

It launches the competitor's real runner as its single child, reaps it via
``os.wait4`` so the child-tree rusage (ru_utime + ru_stime) is attributed
here — the CPU column is container-reported, never a host-side guess — and
writes ``<out>/timing.json`` deterministically:

  {"ru_utime": ..., "ru_stime": ..., "cpu_seconds": ..., "exit_status": ...}

The sidecar carries no wall clock and no paths: the fairness attestation
needs the numbers to be re-derivable, and shard-vs-serial byte-equality of
the cell outputs must not hinge on when or where the cell ran (wall seconds
belong to the timings table, measured host-side around the invocation).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("child", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    argv = list(args.child)
    if argv and argv[0] == "--":
        argv = argv[1:]
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if not argv:
        (outdir / "timing.json").write_text(json.dumps(
            {"ru_utime": 0.0, "ru_stime": 0.0, "cpu_seconds": 0.0,
             "exit_status": 2, "error": "empty child argv"},
            sort_keys=True, indent=1), encoding="utf-8")
        print("m7_entry: no child argv after '--'", file=sys.stderr)
        return 2

    proc = subprocess.Popen(argv)
    _pid, raw, ru = os.wait4(proc.pid, 0)      # we reap: child-tree rusage is ours
    if os.WIFSIGNALED(raw):
        exit_status = 128 + os.WTERMSIG(raw)
    else:
        exit_status = os.WEXITSTATUS(raw)
    timing = {"ru_utime": ru.ru_utime, "ru_stime": ru.ru_stime,
              "cpu_seconds": ru.ru_utime + ru.ru_stime,
              "exit_status": exit_status}
    (outdir / "timing.json").write_text(
        json.dumps(timing, sort_keys=True, indent=1), encoding="utf-8")
    return exit_status


if __name__ == "__main__":
    raise SystemExit(main())
