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
  (L) test_image_cell_argv_sigprofiler  per-tool floor probe (RB-09, sigprofiler twin)
Executed-surface audit (U-M7-03, controller ruling RB-03 -- convergence gate):
  (M) test_executed_surface_audit  closure of the two /work scripts vs recipe
Hash provenance (U-M7-03, controller ruling RB-06 -- explicit-algorithm seal):
  (O) test_hash_provenance  byte-pin triangle + manifest-entry rehash +
      control-vector self-check; no re-typed digest survives this gate
Launch governance (U-M7-03, controller ruling RB-07/RB-08 -- postmortem seals):
  (P) test_matrix_governance  exact-stamp parsing (no substring classes),
      judgment refuse-to-claim, pre-flight co-tenant refusal, worker census,
      pre-registered 3x-floor gate
  (R) test_floor_calibration  RB-09 calibrated floor table: per-class
      REP-100 anchors verbatim, sweep-pinned linearity + n-saturation shape,
      ratio untouchable, probe-scale extrapolation refuted in BOTH signs
      (sigminer superlinear, sigprofiler amortizing)
Hardware-pin completeness (U-M7-04 GO-05, ROADMAP:100 钉硬件 bench 全表):
  (S) test_hardware_pin        every authoritative row pinned to the measured
      environment; the docker-authoritative pass refuses to file without the
      operator's M7_HW_PROFILE; reader-side verifier verdicts a committed
      table from its own bytes
Bootstrap campaign instrument (U-M7-04 GO-05, charter SCOPE B,
pre-registration law docs/devlog/2026-10-10-m7-bootstrap-campaign.md):
  (T) test_bootstrap_campaign  deterministic frozen generator (double-run byte
      identity + seal), decisive tier ladder, anchor gates, SCIENCE-FIRST
      reader-side verifier (inflated claim / failed anchor / self-adjudicating
      probe / unpinned table all refused), single-full-shot ledger law
Anchor-probe mode (GO-05 follow-on): calibrating the anchor gate at the full
shape WITHOUT spending the RB-10 single authoritative shot:
  (U) test_anchor_probe       probe rides the full shape table, quits before
      the probe stage (no probes/tier/timed arms/timings/ratio), its ledger
      entry is non-shot by the reader predicate, probe-grade result.md is
      claim-free with the oracle verbatim, dirty-outdir and mispaired modes
      refused executed, anchor gates frozen
  (V) test_anchor_gate        the amended anchor median clause: CI-noise
      envelope K_CI x larger half-width with the EPS zero floor, constants
      frozen a-prior; both directions pinned (near-zero-in-noise passes,
      true divergence fails, both-zero auto-passes, boundaries exact) and the
      attested probe witnesses adjudicate offline (the shot stays unspent)
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
           # U-M7-03 RB-09(3)(ii): per-tool floor probes (sigprofiler twin):
           "test_image_cell_argv_sigprofiler",
           # U-M7-03 RB-03: executed-surface dependency closure (convergence gate):
           "test_executed_surface_audit",
           # U-M7-03 RB-06: hash-provenance gates (explicit-algorithm doctrine):
           "test_hash_provenance",
           # U-M7-03 RB-07/RB-08: launch governance (postmortem seals):
           "test_matrix_governance",
           "test_floor_calibration",
           # U-M7-04 GO-05: hardware-pin completeness (ROADMAP:100 钉硬件全表):
           "test_hardware_pin",
           # U-M7-04 GO-05: bootstrap-vs-sigminer campaign instrument (SCOPE B):
           "test_bootstrap_campaign",
           # GO-05 follow-on: anchor-probe calibration mode (RB-10-safe):
           "test_anchor_probe",
           # GO-05 amendment: CI-noise-envelope anchor gate (TDD, a-prior):
           "test_anchor_gate"]


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
