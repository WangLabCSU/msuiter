# bench/m1s · the M1s acceptance-gate performance bench (the docs/ARCHITECTURE.md §8 budget rows)

"catalog generation ≥50× SPMG (the pinned-hardware bench; the CI carries only the sanity bound <5s); NMF ≥100× R NMF"
(the docs/ROADMAP.md the M1s acceptance row). **Not belonging to the CI**: the CI carries only the sanity bound.

## The layout

| The directory | The content | The criterion |
|---|---|---|
| `sbs/` | the catalog generation SBS96 (the 10⁶ mutations) vs SPMG (the custom-genome install + the per-cell correctness cross-check) | ≥50× SPMG and ours <5s single-core |
| `nmf/` | the NMF KL (96×1000, k=10, 100 iter) vs R NMF 0.28 brunet | ≥100× |
| `nnls/` | the batch NNLS (101×10³, k=10) vs the per-sample scipy nnls | ≥10× |

## The one-key re-run

```bash
# 0) the SPMG venv (one-off; gitignored)
python3 -m venv bench/m1s/.venv
bench/m1s/.venv/bin/pip install SigProfilerMatrixGenerator   # 1.3.6

# 1) the SBS catalog-generation bench (deterministic fixture generation → our timing → the SPMG baseline → the per-cell cross-check → the criterion)
python3 bench/m1s/sbs/gen_fixtures.py
Rscript   bench/m1s/sbs/run_bench.R

# 2) the NMF bench
Rscript bench/m1s/nmf/run_bench.R

# 3) the NNLS bench
python3 bench/m1s/nnls/run_bench.py
```

The numbers and the criterion verdicts of each bench are written into its own `result.md`; see the aggregation in `result.md`.

## The measurement discipline

- The timing environment is honestly written into each result.md (the local Apple Silicon, the power status not
  controllable — the numbers are for this pinned-hardware caliber); the protocol is unified as "warm-up 1 + timed 3 take the median"
  (the SPMG full run is a minute-scale single wall-clock, honestly annotated).
- All our timings go through the real path of the **un-altered package code** (ms_tally / .ms_tally_rust /
  the engine crate public API); every driver is an independent `[workspace]`, a path dependency only,
  the package tree zero changes (the reason the Rust-bin pure-core caliber is unattainable is in the sbs/result.md annotation).
- The custom genome of the SPMG baseline is registered via a runtime validation check that bypasses the upstream 1.3.6 hard-coded whitelist
  (no upstream file is altered); the per-cell correctness cross-check is a harder anchor than the speed.
- The fixtures (genome/variants/VCF/matrix) are all deterministically generated (the seeds
  recorded in each script header), the cache/ regenerates locally and does not enter the repository.
