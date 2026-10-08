#!/usr/bin/env python3
"""U-M7-02 competitor harness test entry: python3 -m tests.run_all (no pytest).

Mirrors the bench/g0/tests/run_all.py idiom (plain test_* functions, sorted
discovery, same PASS/FAIL line shape and "x/y tests passed." tail). One
deliberate hardening over the G0 original: module-level import failures are
captured per module and reported as a failing unit instead of crashing the
dispatcher — during the TDD RED phase the harness modules under test are
intentionally absent (RED-by-absence), and the evidence we want is the
per-seam ModuleNotFoundError transcript, not a dead runner.

Groups (task contract, docs/devlog/2026-10-08-m7-competitor-harness-design.md §7):
  ① test_registry            competitor registry load + pinned provenance
  ② test_adapters            refuse-to-run seam + frozen thread-cap injection
  ③ test_timings_schema      timings columns = G0 six-column prefix + cpu_seconds
  ④ test_output_contract     cache-hit guard + authoritative outdir file set
Scoring slice (benchmark table + scoring verdicts, U-M7-02 follow-on):
  ⑤ test_scoring_match       Hungarian assignment + frozen cosine tolerance
  ⑥ test_scoring_metrics     P/R/F1 conventions + exposure-error semantics
  ⑦ test_scoring_truth       seed-derived truth == frozen generator truth
  ⑧ test_scoring_pipeline    closed-form fixture cells -> rows/skips/CSV
  ⑨ test_scoring_judgment    preserved fairness half + appended verdict half
  ⑩ test_scoring_determinism byte-reproducible benchmark CSV over one cachedir
SigMiner API-contract pin (slice-3 realignment to the witnessed sig_* family):
  ⑪ test_sigminer_api_contract  verbatim NAMESPACE fixture + eradication gates
Matrix-runner extensions (U-M7-03, arms×N×reps @ pinned seeds):
  ⑫ test_matrix_runner          N-point filter, dry-run plan, resample-verify
Live image-probe (U-M7-03, controller ruling RB-01 -- pilot-catch witness):
  (L) test_image_cell_argv        real cell argv, sidecar-schema-valid depth
Executed-surface audit (U-M7-03, controller ruling RB-03 -- convergence gate):
  (M) test_executed_surface_audit  closure of the two /work scripts vs recipe
"""

from __future__ import annotations

import importlib
import sys
import time
import traceback

MODULES = ["test_registry", "test_adapters", "test_timings_schema",
           "test_output_contract",
           # U-M7-02 scoring slice (benchmark table + scoring verdicts):
           "test_scoring_match", "test_scoring_metrics", "test_scoring_truth",
           "test_scoring_pipeline", "test_scoring_judgment",
           "test_scoring_determinism",
           # slice-3: adapter API realignment contract (memo §9c.2/§9d):
           "test_sigminer_api_contract",
           # U-M7-03: matrix-runner extensions (N-selection, dry-run plan,
           # seed-pinned resample-verify gate):
           "test_matrix_runner",
           # U-M7-03 RB-01: live cell-argv probe (pilot-catch witness):
           "test_image_cell_argv",
           # U-M7-03 RB-03: executed-surface dependency closure (convergence gate):
           "test_executed_surface_audit"]


def _collect(mod_name):
    """Import one test module and enumerate its test_* callables.

    An import-time failure (the expected RED state: the implementation module
    is absent) is surfaced as a single synthetic failing unit so the seam,
    the module name and the traceback stay in the transcript.
    """
    try:
        mod = importlib.import_module(f"tests.{mod_name}")
    except Exception:
        print(f"FAIL  {mod_name}.<module-import>  (0.0s)")
        traceback.print_exc()
        return [(f"{mod_name}.<module-import>", None)]
    return [(f"{mod_name}.{name}", fn)
            for name, fn in sorted(vars(mod).items())
            if name.startswith("test_") and callable(fn)]


def main() -> int:
    units, failures = [], []
    for mod_name in MODULES:
        units += _collect(mod_name)
    for label, fn in units:
        t0 = time.time()
        if fn is None:
            failures.append(label)
            continue
        try:
            fn()
            print(f"PASS  {label}  ({time.time() - t0:.1f}s)")
        except Exception:
            failures.append(label)
            print(f"FAIL  {label}  ({time.time() - t0:.1f}s)")
            traceback.print_exc()
    total = len(units)
    print(f"\n{total - len(failures)}/{total} tests passed.")
    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
