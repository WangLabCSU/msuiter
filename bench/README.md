# bench/ — benchmark and evidence campaigns

Everything in this tree is campaign tooling and committed campaign evidence.
It is **outside the R package**: excluded from the build via `.Rbuildignore`,
never loaded at runtime, and not part of the pkgdown site. Package tests do
read committed files here — the scenario witness laws under `tests/testthat/`
re-adjudicate the frozen bytes in `bench/scenarios/out/`, which is why the
bytes in `out/` are governed as evidence, not scratch output.

## Layout

| Directory | What it is |
|---|---|
| `scenarios/` | The 21 witness-scenario drivers (`run_*.R`) and their committed witness tables (`out/`, 104 files). Each `run_*` pairs with a `test-scenario-*.R` law. |
| `m7/` | The benchmark-matrix campaign: the driver harness, competitor adapters (SigProfiler, signeR, sigminer), governance probes and tests. |
| `g0/` | The G0 coverage-measured PI campaign (protocol, harness, adjudication records). |
| `bootstrap/` | The GO-05 bootstrap-vs-sigminer campaign. |
| `jiang/` | The Jiang 2025 fitting-protocol acceptance evidence. |
| `m1s/` | Milestone-1s engine microbenchmarks (NNLS, NMF, SBS tally). |
| `xval/`, `xval-m2/` | Cross-validation of extraction against sigminer. |
| `results/` | Committed campaign evidence (witnesses, judgment records, seeds, hardware pins). Reading law: `test-peer-evidence.R` derives the sanctioned peer-evidence corpus from this walk. |

Per-campaign details live in each directory's own `README.md`.

## Running

Campaigns are driven from their own directories (see the per-campaign
READMEs), generally via `python3` harnesses (`g0/`, `m7/`) or `Rscript`
drivers (`scenarios/`, `jiang/`, `xval/`). The one-command reproduction face
for the paper's headline numbers is `inst/repro/reproduce.sh` at the
repository root.

## Dependencies

Campaign dependencies are declared here, not in the package `DESCRIPTION`:

- **R** (≥ 4.3) with the msuiter tree loadable (`pkgload::load_all()` from
  the repository root, or an installed msuiter).
- **Python 3** for the `g0/` and `m7/` harnesses (standard library only for
  the harness core; `g0` adapters may need campaign-specific extras).
- **Docker** for the authoritative PI campaigns (the frozen protocol runs
  competitors inside pinned images).
- **scarHRD 0.1.1** for `scenarios/run_hrd_baselines.R` only. scarHRD is a
  GitHub package (not on CRAN), so it cannot ride `Suggests`; the scenario
  driver requires it, while the committed witness is adjudicated against
  hand-traced goldens, so package tests never invoke it.

Anything a campaign needs beyond the package's own `Suggests` belongs in
this section, declared by the campaign that needs it.
