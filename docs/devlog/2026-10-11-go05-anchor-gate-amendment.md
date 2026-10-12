# GO-05 anchor-gate amendment — the median clause moves to the CI-noise envelope

Date: 2026-10-11. Lane: GO-05 successor (anchor-probe + gate amendment), branch
`go-05-anchor-probe`, base 550b658. Doctrine: RB-09 — a criterion is replaced
by principle, never refitted to save a claim; the verbatim red outcome stays
disclosed; replacement constants are fixed a-prior. Controller ruling @09:45.

## 1. The instrument (unchanged law)

`bench/bootstrap/run_campaign.R --anchor-probe --mode full` (committed
ef1c563, TDD group (U)) rides the full shape table (K=1000, S=1000, n_sig=50,
S_ANCHOR=25, R_ANCHOR=200) through data-gen, seal, census and both anchor arms,
adjudicates with the reader oracle, writes a claim-free probe-grade result.md,
and quits before the probe stage. No probes, no tier decision, no timed arms,
no timings, no result ratio. Its ledger line is the non-shot calibration entry
`{"kind":"anchor-probe","grade":"calibration",...}` — invisible to the
reader's `mode == "full"` shot counter. The RB-10 shot stays unspent.

## 2. The verbatim old-rule outcome (stays disclosed, RB-09 law)

Probe: `/tmp/go05lane/probe_20261011T013344Z` (+ `.log`).
Seal of the sealed campaign bytes:
`sha256 cc094225d599a6765dbc7958a445609459ded0f32f2481f87c5cb9e8762b3263`
- reader verifier: rc=0 ("0 full shot(s) on the ledger")
- anchor oracle (anchor_A1 vs anchor_A2), verbatim:
  `{"ok": false, "n_cells": 1250, "overlap_frac": 1.0, "median_ok_frac": 0.9136, "n_failed_overlap": 0}`
- PROBE-COMPLETE, anchor-ok=false.

Under the then-active clause — per-cell median agreement iff
`|m1 - m2| / max(|m1|, 1e-12) <= MEDIAN_REL_TOL`, MEDIAN_REL_TOL = 0.15 — the
gate is RED: 1142/1250 pass, 0.9136 < MIN_MEDIAN_OK = 0.95.

## 3. Denominator reconciliation (108 vs 103), byte-computed on the attested witnesses

The oracle's clause denominates by the A1 median alone (asymmetric):
`|m1 - m2| / max(|m1|, 1e-12)` — reproducing it gives **108** breaches (this
lane's analyzer, hence "108"). The controller's independent pass denominates
symmetrically: `|d| / max(|m1|, |m2|, 1e-12)` — reproducing that convention
gives **103** breaches. Same 103-population; the 5-cell delta is exactly the
asymmetric-only cells (zero/near-zero A1 denominator where the symmetric max is
larger). Neither definition is load-bearing for the ruling: every one of the
103 symmetric breaches (hence, per-cell, the 108) satisfies
`|d| <= HALF the larger CI half-width` — 103/103 measured — i.e. the two
bootstrap medians are statistically indistinguishable under either reading.

Magnitude buckets of the 103, computed here on the witness bytes:
`|d| < 0.01: 84 | 0.01-0.05: 19 | 0.05-0.1: 0 | >=0.1: 0`.
The controller's pass reported `51 / 50 / 2 / 0` for the same 103 — the two
splits agree that NOTHING breaches at magnitude >= 0.1 and disagree only in
the bucket assignment of the small-|d| tail; disclosed without resolution
because nothing in the ruling depends on it. Near-zero population: both
medians < 0.005 in **992**/1250; at least one in **1028**/1250 (the
controller reported "1017 near-zero" — a population-definition variance
around the same EPS threshold, likewise disclosed).

The diagnosis is definitional, not datal: a flat relative tolerance has no
floor to stand on at near-zero estimands (msuiter's bootstrap medians floor at
exactly 0 where sigminer leaves small nonzero floors — a convention mismatch
of zeros, which any relative measure reads as infinite divergence).

## 4. Determinism attestation (contract item (5))

Independent relaunch (`run_probe2.sh`, same branch ef1c563, same seed
20260928, same full shape), fresh outdir
`/tmp/go05lane/probe2_20261011T014912Z`:
- `witnesses/anchor_A1.jsonl` sha256 `1fa9ed3e5c099930635e4aabcefb40baaf36330d5405be4db864085cc4895090`
- `witnesses/anchor_A2.jsonl` sha256 `d2d9fb2fb63825a5d79870ebd19f732e574fdbf2c0c12d5c837137c3157f663e`
- probe1 bytes byte-identical to probe2 bytes; `campaign.rds` byte-identical
  across the two probes (seal `cc094225...` in both)
- ledger: single `{"kind":"anchor-probe","grade":"calibration","ts":"2026-10-11T01:49:13"}`;
  reader rc=0; PROBE-COMPLETE.
This licenses OFFLINE adjudication of the shot's anchor from attested bytes:
the anchor stage is reproducible, so the amended gate can be evaluated on the
probe witnesses without spending the shot.

## 5. The amended clause (contract items (1)-(4))

Per-cell agreement := CI-overlap (unchanged, measured 100% on the probe) AND
the median clause

    |med_A1 - med_A2| <= K_CI * max(halfwidth_A1, halfwidth_A2), or
    (|med_A1| < EPS and |med_A2| < EPS)

with **K_CI := 1.0** and **EPS := 0.005**, both fixed a-prior by the ruling
before any evaluation of the amendment on real bytes — no tuning, no
refit. Gate fractions unchanged: MIN_OVERLAP = 0.90, MIN_MEDIAN_OK = 0.95.
Implemented in `tools/verify_campaign.py::anchor_gates`; the retired
`MEDIAN_REL_TOL` constant is deleted (no R-side mirror exists — the harness
only ever calls the oracle's `--anchor-check`; audited). TDD: group (V)
`test_anchor_gate.py` pins both directions on synthetic fixtures
(near-zero-in-noise passes where the old rule failed; true divergence fails
where the old symmetric rule would have passed; both-zero auto-passes;
envelope and EPS boundaries pinned to the exact bit, inclusive at
`|d| == K_CI * maxhw`) and adjudicates the attested probe witnesses offline.

## 6. Offline evaluation of the amended gate (contract item (6))

Executed in-suite (`test_anchor_gate.py::test_attested_probe_witnesses_adjudicate_green`,
digest-pinned to the attestation above) and re-verified by command against
`/tmp/go05lane/probe2_20261011T014912Z/witnesses`:

    n_cells = 1250, overlap_frac = 1.0, median_ok_frac = 1.0, ok = True
    (K_CI*maxHW failures under the amended rule: 0; every former breach sits
     inside half the larger CI half-width, hence inside the K_CI = 1.0 envelope)

AMENDED GATE: GREEN on the attested witnesses. The RB-10 shot remains unspent;
authorization to fire it is the controller's call, not this lane's.
