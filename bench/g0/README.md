# The G0 pilot-coverage-experiment harness (the own part)

> All the own components that are independent of the competitor environment: the simulation generation, the seed discipline, the coverage-rate computation, the own presence
> LRT, the grid configuration, the container adapter layer and the orchestrator. The protocol was frozen on 2026-09-28
> ([pi-adjudication](../../docs/devlog/2026-09-28-G0-pi-adjudication.md)
> F1–F4); this harness is the runnable implementation of the frozen protocol, **it does not alter any frozen parameter**.
>
> Status: the harness initial build is complete and passed the independent-audit repairs (2026-09-28: the NB-branch EM-mathematics error P0-1, the sensitivity-arm leakage P0-2, the frozen-space shrinkage P0-3 and the P1/P2 batches all landed);
> the self-check tests take the whole-table green as the condition (`python3 -m tests.run_all`); the degraded lane has been closed-looped — the authoritative degraded run
> 2026-10-08 verdict=A (the evidence `bench/results/docker_degraded_pi_20261007-212438/`, see the docs/ROADMAP.md
> G0 row); the primary lane (primary × docker × cosmic-file) **has not been started**, waiting for the F5 execution environment to land.

## 1. The frozen-protocol essentials (the implementation basis of this harness)

| The frozen item | The content | The implementation location |
|---|---|---|
| The falsifiable proposition | the competitors' 95% exposure intervals have their empirical coverage rate significantly below the nominal 0.95 (worse on the low-TMB and the flat-signature grid points); if basically calibrated → accept the Framing B | the judgment semantics in `g0/coverage.py::judge` |
| The F1 judgment thresholds | supporting the A: ① any Tier-1 tool's any cell with ĉ≤0.85 and the CP 95% upper bound <0.90, or ② the flat layer (SBS5/40) N≥300 all cells ĉ≤0.90; kill→B: both tools' every N≥300 cell with ĉ≥0.90 and no monotone worsening along N; gray → double the reps of the borderline cells to 400 and re-judge, still gray then default to the B | `g0/coverage.py` (`judge`, `clopper_pearson`); the threshold constants in `g0/grid.py` |
| The F2 tool pair | Tier-1 = sigfit v2.2.0 (the HPD + the default zeroing lower<0.01⇒0, with the raw column additionally reported) + signature.tools.lib v2.5.2 (the bootstrap nboot=200 + the default filtering); Tier-0 (MuSiCal/SPA/mSigAct) does not enter the coverage matrix | `adapters/` (the runners + the Dockerfiles locked by tag) |
| The F3 ground truth and catalog | the 5 ground-truth signatures SBS1/2/13/5/40 @ 15/15/15/30/25% (= the composition-axis master, the inventory ② "+APOBEC"); the fitting catalog = the COSMIC v3.6 SBS96 GRCh37 all the 101 signatures (a user-supplied file, never checked into the repository) | `g0/grid.py::MASTER_TRUTH_COMPOSITION`; `g0/providers.py::CosmicFileProvider` |
| The grid | the geometric grid 30→10⁶, 19 points in all (raised by the adjudication's clause 3); the 10²–10⁴ cliff region 9 points (the ≥6 densification meets the bar) | `g0/grid.py::PRIMARY_GRID` |
| The ground-truth composition axis | ≥6 groups (the adjudication's clause 3): the master / the clock-only / the +MMR group / the POLE hypermutator (the high-N tier) / the flat triplet of small exposures / the strong signature + flat background; the shares take realistic anchors (Alexandrov 2020; Campbell 2017), the literature basis annotated entry by entry inline | `g0/grid.py::COMPOSITIONS` |
| The repetition count | 200/tool/signature/grid point (the statistical power: −10pp ≈6σ, −5pp ≈3.3σ); the degraded tier's 3 points {100,1000,10000} × 100 reps (the adjudication explicitly kept them) | `g0/grid.py::REPS_*`, `arms_for_profile` |
| The seed discipline | the master seed = 20260928; the per-(arm,N,rep) derivation of a SplitMix64 counter stream (the same shape as the ARCH §2 rng.rs); all the seeds land on disk in Seeds.txt (the manifest records the runtime commit SHA) | `g0/seeds.py`; `run_grid.py::git_sha` |
| The generative model | the main arm the multinomial X~Mult(N,Σf_k·S_k) (f traversing the frozen composition axis); the NB over-dispersion arm is a must-pick (size=8, the Gamma-Poisson construction); the clock-mixing arm (the purity 0.4 equivalent); the sparse arm (SBS13→2% @ N=1000) | `g0/sim.py` |
| The judgment-input contract | the sensitivity arms (nb/clock/sparse) only refine, they do not overturn the judgment (the frozen addendum clause b) — only the main model arm enters `judge`; every judgment sub-sentence is filtered by the Tier-1 tools, and the kill requires both tools present; the borderline carries no N≥300 qualification (the §2.4 original wording) | `run_grid.py` (judge_arms); `g0/coverage.py::judge` |
| The addendum diagnostic columns (touching no judgment rule) | ① the NB arm appends the own χ²₁ presence LRT empirical size/power (P3, the Self–Liang boundary p = ½·erfc(√(stat/2)); the NB branch uses the monotone MM update h←h·Wᵀ(x/μ)/Wᵀ((x+s)/(μ+s)), repaired 2026-09-28); ② the flat layer gets the single-column attribution by the P1 mechanism (i) | `g0/lrt.py`; the coverage-table `p1_mechanism_i` column; `run_grid.py --with-lrt-diagnostic` |

The discipline: report per-signature per-grid-point, **cross-signature averaging that masks the flat layer is forbidden**; the primary estimand =
the absolute exposure (the user-visible interval), the compositional version and the raw column being secondary and never entering the judgment; each rep re-draws
only the counts, never the composition (the conditional coverage).

## 2. The directory structure

```
bench/g0/
├── README.md               this file
├── run_grid.py             the orchestrator (generate→adapter→parse→coverage→judge→persist)
├── g0/
│   ├── seeds.py            the master seed + the deterministic derivation + the Seeds.txt manifest
│   ├── grid.py             the frozen grid / the ground-truth composition axis / the repetition counts / the threshold constants + the arm configurations (primary/degraded/smoke)
│   ├── providers.py        the synthetic (default) / the cosmic-file (the SBS96.txt canonical-order hard validation)
│   ├── sim.py              the four-arm simulation generator (the multinomial / the NB / the clock mixing / the sparse)
│   ├── lrt.py              the own χ²₁ presence LRT (the Poisson + NB-semantics EM, zero scipy)
│   └── coverage.py         the CP exact interval (the self-implemented incomplete beta) + the per-cell coverage rate + the frozen judgment
├── adapters/
│   ├── adapter_protocol.md the in/out contract (counts/catalog/params → intervals.csv)
│   ├── mock_runner.py      the parameter-self-serving placeholder runner (validates only the pipeline, not a competitor measurement)
│   ├── run_sigfit.R        the sigfit container runner (the HPD + the zeroing + the raw column)
│   ├── run_stl.R           the STL container runner (the bootstrap nboot=200 + the filtering)
│   ├── Dockerfile.sigfit   the r-ver 4.3.3 + rstan + sigfit@v2.2.0
│   └── Dockerfile.stl      the r-ver 4.3.3 + signature.tools.lib@v2.5.2
├── tests/                  python3 -m tests.run_all (the whole-table green is the condition, pytest not enforced)
├── results/                in git: the Seeds.txt, the coverage_*.csv, the judgment_*.md,
│                           the timings_*.csv, the diagnostic_lrt_nb.csv
└── cache/                  gitignored: the counts, the truth, the cell input/output intermediates
```

## 3. The licensing declaration (a constitutional-grade red line)

- **The COSMIC signature matrices are never checked into the repository** (the D3 conservative stance, the same handling logic as the
  `tools/channel-reference`). No COSMIC value exists, is embedded or is derived inside the repository.
- The dual-provider design:
  - `synthetic` (the default): the Dirichlet synthetic signatures (the construction formula documented in
    `g0/providers.py`, the slot labels keep using SBS1/2/13/5/40 but the values are non-COSMIC),
    the tests and the development use this tier throughout;
  - `cosmic-file`: reads the **files the user obtained by themselves** from the environment variables
    `G0_SIGNATURES_PATH` (the 5×96 ground-truth matrix) and `G0_CATALOG_PATH` (the fitting catalog, F3 = the COSMIC v3.6 all the 101),
    validating item by item against the `tools/channel-reference/SBS96.txt` canonical order on load (order-sensitive; a wrong order / a missing signature / a wrong channel count are all rejected). The data acquisition and the license acceptance are the user's action; the files are referenced/mounted read-only and never copied into the repository.
- The result tables (`results/`) contain only the coverage rates and the judgment statistics, never the signature matrices themselves.

## 4. The way of running

```bash
cd bench/g0

# ① the self-check (~15 s; the tests whole-table green is the condition for the harness being usable)
python3 -m tests.run_all

# ② the pipeline smoke (the mock adapter + the synthetic provider; validates only the harness itself)
python3 run_grid.py --profile smoke --adapter mock --provider synthetic --with-lrt-diagnostic

# ③ the formal-tier dry-run (only lays down the Seeds.txt + the counts/truth, for the F5 environment cross-check)
python3 run_grid.py --profile primary --adapter docker --provider cosmic-file --dry-run

# ④ the degraded tier (the protocol §6/§7-R7: the 3-point grid × 100 reps; the degradation is automatically noted in the judgment table head)
python3 run_grid.py --profile degraded --adapter docker --provider cosmic-file

# ⑤ the formal G0 (to be executed by the author after the harness passes the audit + the F5 lands)
python3 run_grid.py --profile primary --adapter docker --provider cosmic-file \
    --tools sigfit,stl --with-lrt-diagnostic

# the gray re-judgment (the protocol §2.4): double the reps on the borderline cells
python3 run_grid.py --profile primary --adapter docker --provider cosmic-file --reps 400

# rebuild all the intermediate artifacts (ignoring the cache reuse)
#   append --force-rerun
```

The prerequisites (the formal tier): the Docker daemon running and the `g0-sigfit`/`g0-stl` images already built
(`docker build -f adapters/Dockerfile.sigfit -t g0-sigfit adapters/`);
the environment variables `G0_SIGNATURES_PATH`, `G0_CATALOG_PATH` pointing at the user-supplied matrix files.
The mock tier has zero external dependency (zero dependency besides numpy).

## 5. The relation to the msuiter package

This directory is **a bench counterpart, and never enters the package** (the D9): the `g0/`, `adapters/`, `tests/`
do not import package code (`R/`, `src/`), and the package code does not depend on this directory. The G0 conclusions
(the Framing A/B) enter the mainline through the devlog and the ARCH §10/D14, rather than through code coupling.
The own presence LRT (`g0/lrt.py`) is the reference implementation of the P3 addendum column; should it ever enter the package, it must be rewritten per the package discipline and independently tested — no direct porting.

## 6. The known boundaries (the honest annotations, the D13)

- The R runners were written per the sigfit/STL documented semantics, and the **API-level reconciliation points** are listed in
  `adapters/adapter_protocol.md` §5 (the W1/D2 smoke task: on the first container run,
  check the actual parameter names and the returned-object field names one by one, the version locked by the Dockerfile tag).
  The STL runner's errors.log lands first (the failure information appended), and the run_grid cache-skip guard applies to the STL.
- The W1 compatibility check is not done: the STL supports only the organ RefSig catalogs, and before the formal run the
  Breast RefSig T1 must be verified to contain all the 5 ground-truth signatures (the protocol §3; a missing one follows the degraded path).
- **The NB-arm LRT diagnostic (the caliber after the 2026-09-28 repair)**: before the repair, the NB branch treated
  the Gamma-Poisson stratified E-step weight as a multiplicative update, the NB log-likelihood decreasing monotonely within the iterations
  (the 40-rep batch measurement ll −1.3×10⁵ → −4.7×10⁵, 100% of the h pinned at the defensive h_cap in a false convergence), and the committed diagnostic showed the nb arm power=0.04. After the repair to the auditor-verified monotone MM update `h ← h·Wᵀ(x/μ)/Wᵀ((x+s)/(μ+s))`, the same data gives ll =
  −1.0×10⁴ and rises monotonically. The regenerated `results/diagnostic_lrt_nb.csv`
  (N=1000, 200 reps, 1000 tests per rate): the NB-semantics empirical size = 0.015, the present-signature pooled power = 0.613; the Poisson-misspecified-semantics size = 0.065 (the inflation direction matching the P3 expectation). The per-signature breakdown (the 400-rep verification): the easy tier (SBS1/2/13 @
  the 15% share) power = 1.0; the flat near-duplicate pair (SBS5/40 @ 30/25%) per-signature power
  ≈ 0.085/0.015 (measured on the current seeds) — the 3% spectral difference is drowned in the NB over-dispersion variance, which is an honest annotation of the identifiability limit
  (what the G0 measures on the flat signatures is the interval coverage rate, not the presence power); the power plausibility floor (the easy per-signature ≥0.5, the pooled ≥0.5) has entered tests/test_lrt.py against regressions.
- **The clock-mixing-arm estimand caliber (a pending annotation)**: what the current implementation outputs as the ground truth
  h_k = f_k·N is the **undiluted** tumour composition (the diagnostic caliber); the diluted "observable ground truth of the tool"
  (how the normal-clock share counts into the absolute-exposure estimand) involves
  a definitional choice, **awaiting the author's adjudication**. This arm serves only as a sensitivity report column until the adjudication (the frozen
  addendum clause b, which never entered the judgment anyway), and the judgment semantics are unaffected.
- The judgment-input contract: the sensitivity arms (nb/clock/sparse) only produce report columns and never enter the judgment (the frozen
  addendum clause b); the borderline cells carry no N≥300 qualification (the protocol-memo §2.4
  original wording), and every cell with ĉ<0.90 on every grid point may enter the gray-doubling procedure.
- The smoke (mock) results' verdict has no scientific meaning and proves only the pipeline connectivity; the formal judgment
  may come only from a docker × cosmic-file run under the frozen protocol.
