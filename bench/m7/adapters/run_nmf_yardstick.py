#!/usr/bin/env python3
"""Rust-NMF yardstick: one fixture, two cores, fixed-iteration CPU ratio.

Manifest :42 -- rust-NMF@nmf-rs wheel vs R NMF::nmf(brunet) on the SAME
fixture bytes, python-capable bench image. This is the ONLY route by which
the paper's rust-NMF speed claims can become OUR measurements; until both
sides produce bytes here the claim stays UNMEASURED in committed text
(yardstick two-state law, tools/p6_predicates.py::yardstick_status).

Fairness is by construction, not by apology: both cores run the brunet
KL multiplicative update over the identical float64 matrix for EXACTLY the
same fixed iteration count (rust stop='max_iter'; R eps=-Inf so the
improvement rule can never pre-empt). The stop count is REPORTED from each
side's own attestation (NMFResult.n_iter / NMF's niter()) -- a mismatch is
visible in the evidence, not hidden (fairness_flag). Default count 400 sits
below the MEASURED R-side refusal boundary: R's NMF run() deterministically
exits at 440 on this fixture+seed (in-loop non-convergence guard; witnessed
identically at eps=0 and eps=-Inf, 2026-10-17), so a count above 440 makes
"the same fixed iterations" physically impossible and the gate fires loudly.
Rust is pinned to one thread (co-tenancy law + the R core's serial baseline).

Timing (death #11 correction): each core's factoring call is bracketed alone
(load/IO outside the brackets) -- python side via time.process_time(), the R
leg via base R's proc.time() user+system sum (its own proc_total helper; base
R has no "total" row). The earlier claim that this mirrored a proc_time
idiom in run_sigminer_arm.R was false -- that runner times nothing (the
harness times cells host-side). The R leg reports through stdout lines,
parsed here -- no shared-memory fiction.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

RS_R = Path(__file__).resolve().parent / "yardstick_cell" / "matrix.csv"
LEG_RE = re.compile(r"^YARDS\s+r_seconds=(\S+)\s+r_niter=(\S+)\s+r_version=(\S+)"
                    r"(?:\s+r_dropped=(\S+))?$")


def _proc_total() -> float:
    return time.process_time()


def run_rust_leg(matrix: np.ndarray, k: int, iters: int, seed: int,
                 threads: int) -> dict:
    import nmf_rs
    t0 = _proc_total()
    res = nmf_rs.nmf(matrix, k, method="brunet", seed=seed,
                     max_iter=iters, stop="max_iter", num_threads=threads)
    secs = _proc_total() - t0
    return {"rust_seconds": secs, "rust_niter": int(res.n_iter),
            "rust_version": getattr(nmf_rs, "__version__", "0.1.0")}


def run_r_leg(matrix_path: Path, k: int, iters: int, seed: int) -> dict:
    """Shell out one Rscript leg; parse its YARDS lines (proc.time there)."""
    script = Path(__file__).resolve().parent / "run_nmf_yardstick_leg.R"
    argv = ["Rscript", str(script), "--matrix", str(matrix_path),
            "--k", str(k), "--iters", str(iters), "--seed", str(seed)]
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"[FATAL] R yardstick leg exited {proc.returncode}:\n"
                         f"{proc.stderr}")
    got = None
    for line in proc.stdout.splitlines():
        m = LEG_RE.match(line.strip())
        if m:
            got = {"r_seconds": float(m.group(1)),
                   "r_niter": int(m.group(2)), "r_version": m.group(3),
                   "r_dropped": m.group(4) or "-"}
    if got is None:
        raise SystemExit(f"[FATAL] R leg produced no YARDS attestation: "
                         f"{proc.stdout!r}")
    return got


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--matrix", type=Path, default=None,
                    help="fixture CSV (default: the committed yardstick_cell)")
    ap.add_argument("--k", type=int, default=2)
    ap.add_argument("--iters", type=int, default=FIXED_ITERS,
                    help="fixed iteration count both cores must attest")
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--threads", type=int, default=1)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)

    matrix_path = args.matrix or RS_R
    if not matrix_path.is_file():
        sys.stderr.write(f"[FATAL] yardstick fixture missing: {matrix_path}\n")
        return 2
    fixture_sha = hashlib.sha256(matrix_path.read_bytes()).hexdigest()
    if args.matrix is None and fixture_sha != FIXTURE_SHA:
        sys.stderr.write(f"[FATAL] committed fixture bytes drifted: "
                         f"{fixture_sha} != {FIXTURE_SHA}\n")
        return 2
    matrix = np.loadtxt(matrix_path, delimiter=",", dtype=np.float64)

    rust = run_rust_leg(matrix, args.k, args.iters, args.seed, args.threads)
    r = run_r_leg(matrix_path, args.k, args.iters, args.seed)

    block = {"fixture_sha256": fixture_sha, "shape": list(matrix.shape),
             "k": args.k, "iterations_fixed": args.iters, "seed": args.seed,
             "rust_threads": args.threads, **rust, **r,
             "ratio_r_over_rust": r["r_seconds"] / rust["rust_seconds"]}
    if block["rust_niter"] != args.iters or block["r_niter"] != args.iters:
        block["fairness_flag"] = (f"n_iter mismatch against fixed {args.iters}: "
                                  f"rust={block['rust_niter']} r={block['r_niter']}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(block, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
    print(f"[yardstick] fixture={fixture_sha[:16]} k={args.k} "
          f"iters={args.iters} rust={rust['rust_seconds']:.3f}s "
          f"({rust['rust_niter']}n) r={r['r_seconds']:.3f}s ({r['r_niter']}n) "
          f"ratio={block['ratio_r_over_rust']:.2f}x")
    return 0


FIXTURE_SHA = "10bda6beb4f457fa7f8b64e2030a05fa3cbe60c1251eb8bbfad14108a24601ae"

# Committed fair fixed-iteration count (death #11, 2026-10-17): strictly
# below the MEASURED R-side refusal boundary -- R's NMF run() exits at 440
# on this fixture+seed regardless of eps (in-loop non-convergence guard;
# witnessed identically at eps=0 and eps=-Inf, twice), while rust
# stop="max_iter" iterates mechanically. 400 keeps the margin honest; if a
# future base shifts the boundary under 400, the fairness_flag gate fires --
# loud by design.
FIXED_ITERS = 400

if __name__ == "__main__":
    raise SystemExit(main())
