#!/usr/bin/env python3
"""Execute the REAL sigprofiler cell argv against the registry-pinned image.

SigProfilerAssignment's counterpart to probe_sigminer_cell_argv.py
(controller ruling RB-09(3)(ii)): floor anchors must exist per TOOL, so the
sigprofiler floor gets its own entrypoint probe rather than riding the
sigminer one. The assessment chain, the sidecar schema law and the witness
provenance extras (argv echo with --reps, host wall) are the SAME certified
code — this module parameterizes the shared core only; the registry row
selects image (m7-sigprofiler), entrypoint and runner (run_sigprofiler.py).

Exit contract identical to the sigminer probe: 0 OK, 1 DEFECT, 2 inadmissible
invocation. The final stdout line is the machine-readable JSON verdict.

Usage:
  python3 tools/probe_sigprofiler_cell_argv.py [--work DIR] [--json PATH]
      [--arm main] [--n 100] [--reps 100]
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from tools.probe_sigminer_cell_argv import run_probe       # noqa: E402
import tools.probe_sigminer_cell_argv as _sigminer_probe    # noqa: E402


def parse_args(argv=None):
    return _sigminer_probe.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    return run_probe("sigprofiler", arm=args.arm, n=args.n_point,
                     reps=args.reps, json_path=args.json_path,
                     work=args.work)


if __name__ == "__main__":
    raise SystemExit(main())
