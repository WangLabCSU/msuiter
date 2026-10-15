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
  (S) test_action_pins      action-pin law helper: tag form, attested SHA form,
      mutable/short-SHA rejection (M8 supply-chain hardening)
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
  (W) test_tier_probe         the consumed/report-only fit split: tonight's
      verbatim A2 bytes report, never veto (golden regression), the decision
      is byte-invariant to report-only states, the non-physical A1 law and
      the missing-witness refusal still bite, the floor gate falls back to
      the committed governance table or hard-refuses, the frozen probe shape
      is untouched, and the --tier-probe rehearsal mode carries (U)-group
      discipline (guards executed, claim-free md, shot-counter invisible)
  (X) test_floor_gate_unmeasurable  the @12:50 unmeasurable floor leg: a
      probe fit provably non-identifiable at the probe scale carries the
      dedicated rc 3 with its verbatim fit entry (tonight's golden A2 bytes),
      never a fabricated floor; rc 2 stays reserved for missing/structural
      bytes, rc 0/4 byte-untouched; the instrument accepts {0,3,4}, records
      the verbatim UNMEASURED marker plus the oracle reason, and CONTINUES
      (dedicated writer executed on the target interpreter); the reader
      tolerates only the verbatim marker and discloses the leg, while
      breach and any forged string still fail a MEASURED claim
P6 evidence loop (pre-registration manifest SS1-SS6, sigminer v3 release table):
  (Y) test_p6_roster           six frozen arm keys, full-40hex tree echo,
      face convention (rust twins share their tree), pre-flip pending-verify
      refusal, legacy rows byte-stable under the batch
  (Z) test_p6_adapters         per-arm child-argv contract on the new
      run_sigminer_arm.R sibling, --backend passthrough, zero tuning lever,
      skip-not-skip AdapterUnavailable on unattested images
  (AA) test_p6_predicates      parity <=2x (boundary-exact, per-cell named,
      REFUSE never PASS on missing/non-ok), TP-only judgment non-regression
      on the D2 matched-status surface, mechanical attribution split,
      yardstick MEASURED-or-LEDGERED-PENDING (no third state)
  (AB) test_p6_evidence        zero-cached shard-union merge with reason-coded
      rejects, nine-column committed schema, digest-stamped cell provenance,
      machine-written result.md purity
  (AC) test_p6_floor_governance  no campaign arm rides ungated: all six P6
      tools measured, 21-class anchor completeness, reps-matched OK witnesses
      with committed bytes, calibration ledger fields, co-tenancy census
      coverage of every ready P6 image
  (AD) test_p6_yardstick       seventh-image provisioning: the wheel is
      hash-pinned against the banked fetch evidence with the unsynced
      mirror named, executed bytes COPY-pinned, the bake tool sealed
      against transcription, both cores measured at fixed iterations
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
           # U-M7-04 GO-05: hardware-pin completeness (ROADMAP:100, full-table
           # hardware attestation):
           "test_hardware_pin",
           # U-M7-04 GO-05: bootstrap-vs-sigminer campaign instrument (SCOPE B):
           "test_bootstrap_campaign",
           # GO-05 follow-on: anchor-probe calibration mode (RB-10-safe):
           "test_anchor_probe",
           # GO-05 amendment: CI-noise-envelope anchor gate (TDD, a-prior):
           "test_anchor_gate",
           # GO-05 ruling @10:45: consumed/report-only fits + tier-probe (TDD):
           "test_tier_probe",
           # GO-05 ruling @12:50: unmeasurable floor leg, rc 3 (TDD):
           "test_floor_gate_unmeasurable",
           # M8 (PR #17): the action-pin law helper:
           "test_action_pins",
           # P6 evidence loop (sigminer v3 release-attestation table):
           "test_p6_roster", "test_p6_adapters", "test_p6_predicates",
           "test_p6_evidence", "test_p6_floor_governance",
           "test_p6_yardstick"]


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
