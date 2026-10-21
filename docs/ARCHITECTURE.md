# msuiter architecture design (ARCHITECTURE)

> Version: **v2.2 (2026-09-28, whole-repo documentation alignment edition)**. Review evidence: [docs/reviews/00-synthesis.md](reviews/00-synthesis.md) (the adjudication table) plus the 01–05 originals. Research base drafts: docs/research/00–08 (snapshot nature; see the header declaration of each piece). Completeness checklist: [docs/CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md).
> Positioning: **a Rust computational substrate + an R(S7) user interface -- a mutational signature ecosystem**; the domain algorithms are pluggable components (so each can be benchmarked one by one), the self-developed statistical-inference layer is the paper headline, and scientific accuracy (claims aligned with protocols) is unified with simplicity (the S7 unified interface).
> **The v2.1 highlights** (vs v2): the statistical contracts written up (estimand/calibration/boundary), conformal reduced to Mondrian stratification, the method naming contracted to the three methods MSU-Fit/LowCount/Infer, stateless FFI, the self-developed RNG, the thread-invariance contract, the two-tier acceptance terminology, the upgraded benchmark scenarios, refdb governance, the dual-track roadmap.

---

## 0. Decision record (the ADR index; the formal ADRs migrate progressively into docs/adr/)

| # | Decision | Choice | Status |
|---|---|---|---|
| D1 | License | Apache-2.0; GPL sources are re-implemented from the paper formulas only | accepted |
| D2 | Package architecture | a single R package + the `src/rust/` workspace; the engine crate is the only candidate cut surface for a future split into crates.io; splitting the R side is only the contingency plan for CRAN rejecting the size | accepted |
| D3 | COSMIC data | bundled + updated on demand into `tools::R_user_dir`; the provenance pinned to the Alexandrov-lab BSD-2 mirror | accepted |
| D4 | Distribution | CRAN-ready design (cargo vendor), with r-universe + GitHub Releases first | accepted |
| D5 | API style | the tidy-style `ms_*`; channels validated by label; zero magic strings | accepted |
| D6 | Engine kernel | beta-MM MU (the KL default = the multinomial MLE) + ARD + NNDSVDa/dual random initialization; the volume regularization and the correlation engine are components | accepted (the v2.1 revision: removed the "three noise models" marketing; β=1 is the default with its statistical meaning declared) |
| D7 | Genome reading | the BSgenome compatibility layer + the Rust fast path (the twobit crate over `Cursor<Mmap>` vs the self-developed reader, the two options adjudicated by the M0 spike ADR) | accepted |
| D8 | The R object system | S7 implemented throughout; the floor R ≥ 4.3; S7 only at the API boundary | accepted |
| D9 | Method framework | the unified framework + the engine registry table; external tools never enter the `ms_*` API (bench comparison only) | accepted |
| D10 | Self-developed naming | **only three methods are named: MSU-Fit / MSU-LowCount / MSU-Infer**; the rest are framework components (contracted per the review in v2.1) | accepted (supersedes the v2 naming of 8 methods) |
| **D11** | **Acceptance terminology** | **bit-for-bit semantics** (the channel arithmetic / the protocol steps / the tie rules / the default parameters: the integers and the labels golden, the hard acceptance) ≠ **numerical-protocol equivalence** (the floating kernels: the fixed seed + the tolerance cosine>1−1e-6). The "bit-level alignment" target against the external ones such as R NMF/MuSiCal is abandoned | accepted (new in v2.1) |
| **D12** | **The FFI shape** | **stateless**: no handle registry table, no `.state`; one entry and one exit per call; the mmap is used and released within the process | accepted (new in v2.1, supersedes the caugi handle pattern) |
| **D13** | **Statistical-claim discipline** | every statistical claim must give at once the estimand, the generative model, the calibration protocol and the failure conditions; the "first" claims are qualified to a defensible scope | accepted (new in v2.1) |
| **D14** | **The paper positioning** | headline = "Calibrated inference of mutational signature exposures" (Framing A) + the five-modal-ecosystem support (B); the leading coverage experiment is the kill-criterion gate | accepted (new in v2.1) |
| **D15** | **The engine-parity principle** | the engine/method layer provides **interface-parity native implementations** for **all the mainstream and advanced algorithms** (the hot kernel Rust native, the statistical glue R native; the external tools are only the bench reference -- parity ≠ packaging someone else's API, consistent with D9); the domain user can run any mainstream method through the unified interface for comparison | accepted (the 2026-09-28 user directive) |
| **D16** | **The platform positioning** | **the Seurat of the mutational-signatures domain**: the central object model + the unified workflow grammar + the engine-registry ecosystem + the tutorial culture; the self-developed methods are the default path and the mainstream algorithms are optional engines -- every design decision is measured by "becoming the domain's default entry" | accepted (the 2026-09-28 user directive) |

---

## 1. The system-layering overview

```
┌──────────────────────────────────────────────────────────────────────┐
│ L4 the application workflows (R/S7)                                    │
│   ms_hrd_report() · ms_exposure_panel() · ms_lowcount_report()       │
│   ms_atlas_fit() (the common/rare two stages) ·                      │
│   ms_stratify_hypermutants()                                         │
│   (v1.x per the collaborator: ms_rna_report() · therapy forensics)  │
├──────────────────────────────────────────────────────────────────────┤
│ L3 the method layer (R/S7) -- the unified method framework +        │
│   the engine registry table                                          │
│   ms_extract(cat, method)   method = an MsEngine subclass           │
│                             (the objects are first-class citizens,   │
│                             the strings are only sugar)               │
│   ms_fit(cat, sigs, method) / ms_fit_bootstrap() /                  │
│   ms_test_presence()                                                  │
│   ms_select_k() (the default adjudication rule) ·                    │
│   ms_benchmark() (the mlr3-style grid)                               │
├──────────────────────────────────────────────────────────────────────┤
│ L2 the representation and data layer (R/S7)                          │
│   S7: MsVariants · MsCatalog · MsSignature · MsFit · MsRefDb         │
│   (the cross-object references are always **snapshot summaries**:   │
│    the dimensions + the channel-table hash + the refdb version --    │
│    not an embedded full object, guarding against the memory          │
│    doubling and the waldo noise)                                     │
│   the channel-registry table (the canonical order + the metadata) · │
│   the reference library · the calibrated similarity library          │
├──────────────────────────────────────────────────────────────────────┤
│ L1 the computational engines (Rust, workspace:                      │
│   engine/catalog/ffi)                                                │
│   the NMF kernel family (KL/EU/HALS/ARD/volume-reg/correlation/NTF) │
│   · NNLS/QP · the multinomial/negative-binomial likelihood +        │
│   χ²₁ LRT + Fisher (interior) · **the self-developed PCG64 RNG** ·   │
│   the resampling / consensus clustering / HMM / GMM ·                │
│   SBS/DBS/**MNV/complex routing**/ID83 · the twobit fast path ·      │
│   exactPcf                                                           │
└──────────────────────────────────────────────────────────────────────┘
   the external tools (SigProfiler*/MuSiCal/mmsig/…) -> the containerized
   comparison under bench/g0/adapters/ and bench/m7/adapters/, never
   entering the ms_* API (D9)
```

The orthogonality rules: L1 has no sample/COSMIC concepts; L2 monopolizes the channel semantics and the reference-data versioning; L3 only composes L2 and L1; L4 only assembles L3; the S7 dispatch only at the API boundary (the hot paths all Rust). The R-side architecture tests enforce: `R/<section>/` may call only its own section + `classes/` + the FFI wrappers + the explicit whitelist.

## 1.5 The platform doctrine: the Seurat of mutational signatures (D15/D16)

Seurat became the center of the single-cell ecosystem not because it invented the most algorithms but because it provided **the default entry**: the unified object, the unified workflow grammar, the integration of all the domain's methods, and a tutorial culture that gets people working immediately. msuiter copies these four things:

1. **The central object model**: MsVariants → MsCatalog → MsSignature/MsFit form the analysis trunk, the provenance carried along the whole chain (version/seed/method); the cross-object references go through snapshot summaries.
2. **The unified workflow grammar**: `ms_variants() |> ms_tally() |> ms_extract() |> ms_fit() |> ms_compare() |> plot()` -- the six variant classes (SBS/DBS/ID/CN/SV/RNA-SBS) share one grammar; swapping the engine does not change the pipeline.
3. **The engine parity (D15)**: the mainstream and advanced algorithms all enter the registry table through the unified interface with native implementations (`method = ms_nmf(...) / ms_ard(...) / ms_lda(...) / ...`); the user can swap the engine in one line for a methodological comparison -- **this is the key that makes the benchmark culture an everyday operation rather than a paper appendix**. The external tools serve only as the bench reference, not entering the API.
4. **The default is the self-developed**: the default path is always our independent method (the extraction default = the consensus-CV pipeline; the fitting default = MSU-Fit; the low counts = MSU-LowCount; the association = MSU-Infer) -- out of the box the user gets our calibrated statistics, not the 2013 raw NNLS.
5. **The tutorial culture and adoption**: the vignettes, the COSMIC-style figures out of the box, the `ms_sitrep()` diagnostics, the nf-core/CLI interoperability -- measured by "the domain PI switches the pipeline to msuiter tomorrow".

The implication for the ROADMAP: the engine-parity matrix (which mainstream algorithm enters the registry table in which version track) updates with each milestone; the "per-algorithm comparison" of the benchmark chapter is generated driven directly by the registry table.

**The completeness checklist**: the platform's complete capability space (data/QC/preprocessing → catalog representation → identification → quantification → post-fitting analysis → **basic visualization** → **the application workflows and visual mining** → the platform layer, incl. the "you might not have thought of" list) is authoritative in [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md) -- per capability the identification/quantification/visualization/mining annotate the methods, the parity engine, the default path, the visualization deliverable and the milestone, updated at each milestone's acceptance.


## 2. The Rust workspace (src/rust/)



```
src/rust/
├── Cargo.toml        # the dependency budget (the v2.1 contraction):
                      #   extendr-api(default-features=false, the ndarray
                      #   feature only), ndarray, rayon, memmap2,
                      #   twobit (pending the spike).
                      #   ★ no rand -- the randomness is self-developed
                      #   (see below). The MSRV target 1.71 (the extendr
                      #   0.9 official).
                      #   the engine/catalog two crates:
                      #   #![forbid(unsafe_code)]; the dependency direction
                      #   ffi→catalog→engine: deny bans the rand family
                      #   globally, the reverse/extendr seepage asserted by
                      #   tools/check-dep-direction.sh + enforced by the
                      #   manifest structure.
├── engine/           # pure numerical, zero FFI, standalone cargo test
│   ├── nmf.rs        # the KL(β=1, default)/EU MM-MU + HALS + ARD + the
│   │                 #   volume-regularization component
│   ├── correlated.rs # the correlation-aware component (the low-rank
│   │                 #   exposure in the log space; the gauge-fixed
│   │                 #   output protocol)
│   ├── tensor.rs     # NTF+NB (exploratory; the rank fixed by the held-out
│   │                 #   likelihood + the Kruskal condition check)
│   ├── rng.rs        # ★ the self-developed PCG64 + SplitMix64 seed-stream
│   │                 #   layout (the per-replicate/rank/fold counter
│   │                 #   streams; the layout written into the paper
│   │                 #   Methods). the multinomial/Dirichlet sampling is
│   │                 #   in resample.rs (U-M1s-04), not in this module
│   ├── nndsvd.rs     # NNDSVDa/ar: the randomized SVD with a fixed q≥3
│   │                 #   power iterations + oversampling≥16 + the "exact
│   │                 #   Gram-SVD cross-check" property test; the KL
│   │                 #   denominators max(·,ε)/log(ε+·)
│   ├── nnls.rs       # Lawson-Hanson on the Gram: the pivoted LDLᵀ + the
│   │                 #   ε‖G‖ ridge + the KKT assertions
│   ├── likelihood.rs # the multinomial/negative-binomial LL + the ϵ stepping
│   │                 #   + the χ²₁ LRT + Fisher (the interior support only)
│   ├── resample.rs   # the multinomial resampling + the NB-calibrated
│   │                 #   sampling (the Jiang protocol)
│   ├── consensus.rs  # the cosine distance + the rectangular Hungarian
│   │                 #   (the explicit split/merge semantics for
│   │                 #   unmatched) + silhouette
│   ├── stats.rs      # the 1-D GMM (the stratifier), Wilcoxon (diagnostic),
│   │                 #   HMM (the lesion segregation, v1.x)
│   └── linalg.rs     # the pivoted Cholesky/LDLᵀ, the triangular solve
├── catalog/          # the channel semantics (FFI-free)
│   ├── sbs.rs        # the SBS96/192/384/1536 byte arithmetic
│   ├── mnv.rs        # ★ the MNV 2–5bp / >5bp / complex indel / double
│   │                 #   indel routing tables + the split-VCF adjacent
│   │                 #   record re-join (the skip ledger into the
│   │                 #   provenance)
│   ├── dbs.rs        # DBS78 (the Q-chain rules; accepting only the
│   │                 #   distance-exactly-1 doublet after the re-join)
│   ├── indel83.rs    # ID83 (the SPMG semantics bit-for-bit replica)
│   ├── pcf.rs        # exactPcf (the SV clustered)
│   └── genome.rs     # the 2bit fast path (adjudicated: twobit 0.2.2 over
│                     #   Cursor<Mmap>, see docs/adr/0001; the self-developed
│                     #   fallback prototype of 244 lines verified, filed into
│                     #   tools/spike/)
└── (the root crate = the FFI shell msuiter)  # the extendr FFI shell
                                              #   (stateless, ~25 exports;
                                              #   governed frozen by
                                              #   docs/ffi-surface.md).
                                              #   Implementation note: rextendr
                                              #   hard-convention puts the FFI
                                              #   crate manifest at
                                              #   src/rust/Cargo.toml, hence
                                              #   the root-package + members
                                              #   shape (settled by the
                                              #   U-M0-01 real measurement); the
                                              #   msuiter/ sub-directory of the
                                              #   diagram above folds into the
                                              #   root crate.
```

**The FFI hard contracts (all written up in v2.1)**:
1. **Stateless**: `ms_tally_rust(genome_path, variants, …)` uses and releases the in-process mmap; `ms_extract_rust(counts, params, seeds)` one entry one exit. No handles, no `.state`, no silent recomputation.
2. **The memory layout**: the crossing matrices use a unified explicit column-major view; the "square-matrix transpose detector" unit test (the asymmetric golden round-trip).
3. **NA/NaN**: the R validator enforces the `anyNA()` rejection; the Rust `debug_assert!(!is_nan())` and never produces NaN (the ε policy: the denominators `max(·,ε)`, `log(ε+·)`, the ε value documented); the catalog layer carries **zero pseudo-counts** (the contrast test against musicatk's +ε).
4. **The indexing**: the i32→usize explicit conversion + the bounds check; out of bounds returns an R error rather than panicking.
5. **Errors**: the kernel returns `Result<_, MsError>`, converted to an R condition only at the ffi-crate boundary; calling a throwing API inside the kernel is forbidden (`Rf_error`'s longjmp skips the Rust destructors); any panic → the whole call errors, no partial results.
6. **Concurrency**: **the rayon global pool abandoned** -- each top-level call builds its own per-call ThreadPool (the `msuiter.threads` option; default 2 under `_R_CHECK_LIMIT_CORES_`); **the parallelism exists only between the independent units** (the replicate/sample/bootstrap), single-threaded within a unit with the fixed reduction order -- **the thread-count invariance**: with the same seed the outputs for threads∈{1,N} are `identical()` (the CI hard test).
7. **Interrupts**: the main thread pols `R_CheckUserInterrupt` at the chunk boundaries; the workers check only the AtomicBool; no residue after an interrupt (holds automatically given statelessness).
8. **Build**: Makevars.in per the string2path pattern (vendor.tar.xz + offline + `CARGO_BUILD_JOBS=2` + cleanup); DESCRIPTION `SystemRequirements: cargo, rustc (>= 1.71)`; rust-toolchain.toml not entering the tarball; **the M0 spike produces the real vendor + xz byte counts and the rustc 1.71 build proofs**.

## 3. The R package structure and the S7 class system

### 3.1 The directory layout (modular, reserving the package-split line; each section carries a three-line README declaring the allowed dependency directions)

> **Implementation note (the U-M0-03 real measurement)**: the R package machinery (WRE §1.1.5) installs only the top-level `.R` files of `R/` -- the `R/<section>/` sub-directories of the diagram above cannot land literally. The convention changed to **flat prefixed naming** `<section>-<topic>.R` (e.g. `classes-variants.R`, the future `io-variants.R`, `catalog-tally.R`); the section membership is expressed by the file-name prefix and the load order is controlled by the DESCRIPTION `Collate`; each section's dependency-direction rules are enforced by the static architecture tests (carried by the M2 contract test suite, the pattern same as `tools/check-dep-direction.sh` and `tools/docs-sync.R`).

```
R/
├── msuiter-package.R  zzz.R          # S7::methods_register(); the on_load hooks
├── classes/                           # ★ the S7 class definitions (the single source of truth)
│   ├── variants.R  catalog.R  signature.R  fit.R  refdb.R
│   ├── engines.R                      # the MsEngine abstract + the concrete engine spec subclasses
│   ├── benchmark.R  utils.R           # MsBenchmark; the union types
├── io/                      # the input layer (the only place touching the external formats, validated on read -> MsVariants)
│   ├── variants.R           # VCF/BCF/MAF/TSV/Xena; the somaticness validation
│   ├── segments.R  bedpe.R  genome.R
├── catalog/
│   ├── channels.R           # the channel-registry table (the canonical-order labels + the metadata, asserted consistent with the COSMIC files at build)
│   ├── tally.R  normalize.R # the ms_tally() generic dispatch; the GMM stratification/TMB recalibration
│   ├── cnv_features.R  sv_features.R
├── engines/                 # ★ the algorithm-zoo implementation site (one file per engine, the unified fit_engine interface)
│   ├── nmf.R  ard.R  sparse.R  correlated.R  tensor.R  lda.R  supervised.R
├── fit/
│   ├── fit.R  bootstrap.R  presence.R  assign.R  coda.R
├── kselect/   select.R                # ms_select_k(): the stability + CV + Wilcoxon multi-evidence and the adjudication rule
├── qc/                                # ★ the sample-QC first-class layer
│   ├── sample.R  artifacts.R          # ms_qc_report(); the FFPE/oxoG/amber-red filter registry table
├── refdata/
│   ├── refdb.R  update.R              # the versioned reference library + the precedence/manifest governance
├── similarity/
│   ├── metrics.R  calibration.R       # the calibrated similarity library (ms_compare): the null distributions + the three matching protocols
├── analyses/                          # the post-fitting analysis family
│   ├── tsb.R  rta.R  lesion.R  rainfall.R  timing.R
├── viz/                     # ggplot2 native (the 10 figure-type families of CAPABILITY-MATRIX L-F)
│   ├── profile.R  exposure.R  similarity.R  stability.R  strand.R
│   ├── calibration.R  mining.R  palette.R
├── workflows/               # L4 (HRD/exposure/lowcount/atlas/report; the RNA v1.x conditional)
│   ├── hrd.R  exposure.R  lowcount.R  atlas.R  report.R
│   ├── rna.R  therapy.R               # v1.x
└── extendr-wrappers.R                 # rextendr-generated
```

### 3.2 The S7 classes (the v2.1 revision)

```r
MsVariants  : table + genome + provenance
              validator: the required columns / the coordinate legality +
              **the anyNA rejection + the somaticness signals**
              (the caller and matched-normal provenance required, the VAF
               floor option, the FILTER confidence-class passthrough -- the
               defense against the first failure mode of ctDNA/CHIP)
MsCatalog   : counts(channels×samples) + the channel-registry snapshot +
              samples + provenance
              validator: the dimension consistency + the label exact
              agreement + non-negativity + the anyNA rejection
MsSignature : signatures/exposures/stability/k_evidence/engine/seed
              + **catalog_summary** (the snapshot summary: the dimensions +
                 the channel-table hash + the build, not the full
                 MsCatalog -- guarding against the memory doubling)
              (v2.1: the .state property deleted -- after the FFI went
                 stateless no handles exist)
MsFit       : exposures/support/tests + **reference_summary** + engine
MsRefDb     : matrices + metadata(version/class/build/**schema_version**/
              sha256/license/**build_independent**/availability)
MsEngine    : the abstract spec (name/mode/params/deterministic/packages/label)
MsBenchmark : results(.engine/.scenario/.metric/.estimate) + settings
```

The generics: `ms_tally / ms_extract / ms_fit / ms_select_k / ms_fit_bootstrap / ms_test_presence / ms_benchmark / ms_compare / ms_sitrep / fit_engine / required_pkgs / ms_extract_signatures / ms_extract_exposures / ms_extract_fit_time` -- **all `ms_` prefixed** (the hardhat naming serves only as a documentation concept correspondence); the `print/format/summary/plot/knit_print` reuse registrations.

The `method` argument settled: `ms_extract(cat, method = ms_nmf(engine = "kl", ...))` with the S7 object as a first-class citizen; the `method = "nmf"` string sugar resolves through `match_ms_engine()`, listing every available engine name on failure.

### 3.3 The S7 engineering iron laws (invariant): the dispatch only at the API boundary; no `@<-` on the hot paths; the batch changes via `set_props(check=FALSE)` + one validate; the RDS naturally safe (after removing the externalptr the re-attachment problem is fully eliminated).

### 3.4 The engine registry (v2.1 adds the governance fields)

`register_ms_engine(name, mode, engine_class, fit_fn, packages, tags, engine_version, contract_version, certified)`. `certified ∈ {certified, self-reported, unknown}`; `ms_benchmark()` emits an explicit warning for a non-certified engine (implementation note: the warning is at the engine-resolution point match_ms_engine()/ms_extract()/ms_fit() once per session per engine, and the benchmark filter reads the same registry state); the documentation declares the trust boundary ("registering an engine's code executes with your privileges"); a monthly reverse-dependency compatibility matrix job for the maintainer. The extension contract: the third-party package registers in `.onLoad()` + `S7::methods_register()`; `vignettes/extending.Rmd` + the companion harness.

### 3.5 Error & lifecycle (new in v2.1)

The error class convention `msuiter_error_<topic>` (the rlang abort + the cnd payload + the i/j/c three-segment message); the lint bans the raw `stop()`; the lifecycle: the `@experimental` annotation before v1.0, the deprecation via `lifecycle::deprecate_warn`, NEWS.md being the changelog; `docs/ffi-surface.md` is a per-release review artifact (the diff entering the PR-template check item).

## 4. The unified framework and the algorithm zoo

The layered zoo and the implementation strategy are in [research/07-algorithm-zoo.md](research/07-algorithm-zoo.md) §2 (the status table: Rust/R/Adapt/Skip). The v2.1 revisions:
- **The Catalog IR declaration corrected**: "lossless coarse-graining (fine→coarse) + variant-level recomputation (coarse→fine requires variants)"; ID83↔89 provides the explicit mapping table annotating the unmappable channels.
- The correlation engine, the damage tempo, the tensor, the catalog IR, **the calibrated similarity library (`ms_compare()`)** are **framework components** (no longer prefixed MSU-); the tensor reduced to exploratory (the rank fixed by the held-out likelihood + the Kruskal condition check + adding only one pattern at a time). The corresponding API names: `ms_correlated()` (the correlation engine), `ms_tensor()` (NTF), `ms_supervised()` (the SuperSigs lineage), `ms_hdp()` / `ms_bayes()` (the bench-comparison slots, the native implementations deferred to v1.x), `ms_damage_tempo()` (the damage tempo, v1.x). The extraction engines are uniformly constructed as S7 objects via the factory functions: `ms_nmf(engine=)` / `ms_ard()` / `ms_sparse()` / `ms_lda()`; the input side adds `ms_segments()` (the allele-specific CN segments) and `ms_sv()` (the SV calls) + `ms_simulate()` (the catalog simulator, shared by the benchmark and the tests) -- **all through the registry table, the same interface as `ms_extract()`/`ms_fit()`**.

## 5. The method system (v2.1 contracted to three named methods + components)

**The default path (D16)**: the `ms_extract(method = NULL)` default = the consensus-CV extraction pipeline; the `ms_fit(method = NULL)` default = MSU-Fit (starting with nnls + the `ms_test_presence()` report); the low-count context automatically suggests MSU-LowCount; the association analysis defaults to MSU-Infer. The mainstream algorithms all swap in one line through the registry table (the D15 parity principle) -- **the default is the self-developed calibrated statistics; swapping the engine serves only the methodological comparison**. The complete capability space (the identification/quantification/visualization/workflows/mining and all the sub-capabilities) is in [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md) -- that matrix is the authoritative completeness checklist of the platform, updated with the milestones.


### The named methods (the paper abstract layer)
| Method | Content | The precise claim (the D13 discipline) |
|---|---|---|
| **MSU-Fit** | the likelihood sparsified fitting (the ϵ threshold + the χ²₁ LRT dual mode) + the background-signature policy + the connected-group configuration + the bootstrap CI + the CI zeroing + the calibration experiment faces (the `ms_calibration_grid()` coverage grid / the `ms_calibration_verdict()` verdict window / the `plot_calibration_curve()` curve plot / the `ms_calibration_sanity()` real-data downsampling sanity harness, the protocol in inst/sanity/README.md -- sanity is never written as calibration evidence) | The claim: "**the first inference layer that measures the empirical coverage of exposure intervals and reports it over the full grid**". The estimand three layers: ① presence = the χ² LRT (per-sample the Self–Liang boundary asymptotic + when pooled across the cohort the exact Binomial(½)-mixture χ² null distribution -- the U-M3a-03 audit correction, the χ²₁ reference statistic invalid for n≥2); ② magnitude = **the absolute exposure under the support condition** (the component version also reported); ③ zeroing = a decision rule, the compound-procedure coverage measured separately. The calibration: the multinomial and NB (the Jiang color scatter) **dual generative models**, the coverage turned into curves over N × the Shannon entropy; BCa or the layered calibrated-percentile; the real-data sanity = the high-TMB downsampling coverage test; the Fisher intervals only at the interior support ("boundary parameters get tests, not intervals"). The degeneration-semantics note: when all the replicates zero a minor signature the CI degenerates to the sample total (the honest degeneration of zeroing+rescaling, not numerical noise) |
| **MSU-LowCount** | the panel/ctDNA low-count refit: the NB likelihood + the sparse prior + the explicit residual channel + the conformal intervals | The claim: "**per-TMB-stratum conformal intervals (Mondrian by N bin, studentized score) with empirical coverage verified on stratified simulations and retrospective real panel data**". Explicitly the exchangeability holds only within a bin; the simulation-fidelity sensitivity curves published with the package |
| **MSU-Infer** | the DM/logistic-normal mixture-model differential abundance (reproducing Morrill 2025 → extended) + the CoDA test + the survival/longitudinal + the uncertainty propagation (the multiple-imputation protocol) | The claim: "the first exposure-association framework covering **survival/case-control/longitudinal** (the DM mixture model for between-group differential abundance already exists in Morrill 2025, we reproduce and extend it)"; the extension list explicitly including the structural zeros / the hurdle |

### The framework components (the paper Methods layer)
- **The consensus-CV extraction pipeline** (the `ms_extract` default): the GMM **stratification** (`ms_stratify_hypermutants`: classification + de novo exclusion + forced refit, not "normalization") → the multi-initialization KL-MM ensemble → the Hungarian consensus (the explicit split/merge semantics for unmatched) → **the default K adjudication rule** (SUITOR argmin → the stability veto → the Wilcoxon diagnostic-only; the meta-rule evaluated over the full grid) → the NNLS refit. The Delta narrative: deterministic (incl. the thread invariance) + a transparent evidence table + the Rust acceleration "making calibrated statistics affordable".
- **The correlation engine** (correlated.rs): **the pre-registered falsifiable claim** -- over the Wu 2022 grid r∈{0.8,0.9,0.95} the exposure L1 must simultaneously defeat (i) the recalibrated-catalog plain KL-NMF (ii) the pure MvNMF (iii) the original Cornet (iv) the correlation-aware refit, by a significant margin; reporting only the gauge-fixed quantities (h/W/reconstruction; interpreting the embedded vectors forbidden); m<K selected through the held-out likelihood, with m fixed while scanning K; the volume regularization and the embedding are separated ablation axes; the Cornet 10–40× recalibration = an engine-internal hyperparameter (sweep {1,10,40,100}, the flat-signature underestimate a guard metric, the absolute exposure restored by the de-rescale, forbidden on the NMF path); the five modalities reduced to the SBS+DBS demonstration until proven.
- **The damage-tempo analysis** (v1.x), the **NTF tensor engine** (exploratory, v1.x), the **catalog IR** (the §4 corrected semantics), **the calibrated similarity library** (`ms_compare()`, M4: the null-distribution calibration + the Hungarian/Islam/Jiang three matching protocols).

The platform capability full space (incl. the QC layer, the 10 visualization figure-type families, the application workflows and visual mining, the "you might not have thought of" list) is authoritative in [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md) as the completeness checklist, updated with the milestones.

## 6. Data and standards (the v2.1 revision)

1. **The channel-registry table**: the single source of truth (data-raw generating the R CSV + the Rust constants + the build-time assertions).
2. **The reference-library governance**:
   - **v1 bundles human SBS/DBS/ID only** (GRCh37/GRCh38 SBS/DBS + GRCh37 ID; aligned with the CRAN 5MB guidance line); CN/SV/RNA-SBS/mouse obtained via the `ms_update_refdb()` cache.
   - **A missing build = the `build_independent: true` declaration** (the ID/CN/SV/RNA-SBS channel labels and the signature matrices are build-independent -- a relabel rather than derived); queried honestly as "no official reference set for this build, the closest is YY".
   - **precedence**: an analysis is always pinned to the specific version recorded in the object's provenance; the default bundled-first, the cache only on the explicit request; a `schema_version` above what the package supports stops (the forward rejection).
   - **Integrity**: the update pins the commit SHA + burns a manifest at build (the lib-sums.tsv pattern) + fail-closed; the update-path tests fully fixture-ized (zero network during checks).
3. **Genome hygiene**: the contig whitelist (the primary assembly), the sex-chromosome opportunity correction, the per-sample opportunity-vector option (the CN segments + the callable BED into MsCatalog), the explicit chrM routing, T2T compatibility (natively supported at the twobit layer); **the exome/panel opportunity-normalized reference sets** are first-class citizens (refitting a WES against a WGS reference systematically biases the flat signatures).
4. **The report checklist**: the provenance (the catalog version, the build, the channel order, the method + version, the **seed-stream layout**, the software version, the thread count [promised not to affect the result]).

## 7. The algorithmic science contracts (the v2.1 rewrite)

1. **The two-tier acceptance** (D11): **bit-for-bit semantics** (the hard acceptance, the integers/labels golden): the SPMG ID83 and the MNV/complex routing, the DBS Q-flag, the CN48/SV32 labels, the Koh ID89 mapping (v1.x), the SUITOR fold in-order modulo and the conditional-mean imputation semantics, the HRDetect coefficients, the Macintyre/Drews features, the Islam/Jiang/Medo **metric-protocol steps**; **numerical-protocol equivalence** (the fixed seed + the tolerance): the KL-MU vs R NMF brunet (the fixed-platform one-off experiment, `‖ΔW‖/‖W‖<1e-10`, not a CI gate), the MuSiCal bidirectional numerical trajectory, the consensus-clustering statistics.
2. **The catalog-completeness contract**: the input-event-class routing table (SNV/DBS/MNV2-5/MNV>5/complex indel/double indel → each one's destination), the skip ledger into the provenance; the split-VCF adjacent-record re-join algorithm specification and its failure modes; the MNV-adjacent and complex golden fixtures.
3. **The statistical contracts** (D13): the estimand/generative-model/calibration-protocol of the §5 table are the contract; any new statistical claim must supply the four-piece kit before entering §5.
4. **The zero pseudo-count policy**: no +ε at the catalog layer; the numerical protection enters only the division.
5. The GPL sources re-implemented from the paper formulas only (unchanged).

## 8. Performance and benchmark (the v2.1 upgrade)

**The scenario grid (upgraded)**: the TMB 10²–10⁶ × the signature count 1–20 × the correlation {0, 0.5, 0.8, 0.95} × **the flat-signature within-group r=0.8 + the rare-signature coexistence (joint)** × the purity {1.0, 0.7, 0.4, 0.2} × the caller axis (≥2 SNV + ≥2 indel callers) × the platform WGS/WES/panel (the opportunity normalized) × the reference mis-set + **the out-of-catalog signature cell** × **the hypermutator arms (5–10% of samples TMB 100×, the APOBEC/POLE P/R pair cutoff sensitivity)** × the subclonal exposure structure × **the category-specific count ranges (SV 10–10³, CN segments 10–10⁴)**.

**The three-layer scenario isolation**: the calibration scenarios / the model-selection scenarios / the evaluation scenarios use different generators (SigProfilerSimulator / SynSig / the PCAWG-anchored real mixtures); the protocol frozen before publication and published with the package.

**The metrics**: **the primary metric = the P/R/F1 of the Hungarian one-to-one matching** (the greedy max-cosine + the threshold sweep 0.80–0.90 as the robustness appendix; the split behavior explicitly penalized / the dedup statistics); the exposure L1/cosine (the absolute and compositional calibers consistent with each engine's estimand); the mis-allocation mass onto the absent signatures; the runtime/memory. The Jiang Combined Score and the Islam protocol replicated bit-for-bit (the semantics layer golden).

**The performance budgets (the acceptance at the hardware-pinned bench; the CI carries only a sanity bound)**:
| Kernel | Baseline | Target |
|---|---|---|
| the catalog generation SBS96 (10⁶ mutations) | SPMG | ≥50× and <5 s single core |
| NMF KL (96×1000, k=10, 100 iter) | R NMF / rust-NMF | ≥100× R NMF; the rust-NMF alignment (tolerance) |
| the batch NNLS (101×10³) | scipy nnls per sample | ≥10× |
| the all-sample fitting | SPA ~0.21 s/sample | aligned or better |
| bootstrap (10³×10³) | sigminer serial | ≥100× |

**The G0 leading coverage experiment (the kill-criterion gate, before any paper narrative)**: the nominal vs actual coverage of 2 competing tools × the TMB grid -- the outcome decides whether the headline runs Framing A (calibrated statistics) or Framing B (the ecosystem).

## 9. TDD and CI (the v2.1 completion)

- Rust: the channel-arithmetic property/golden (incl. the MNV routing); the KL monotonicity and the ε behavior; the NNLS KKT + the ill-conditioned Gram (the pivot LDLᵀ); the Hungarian brute-force cross-check; the RNG cross-version golden (a fixed seed → the fixed first N u64); the **thread-invariance identical() tests**; the correlation-engine low-correlation degeneration tests.
- R: the S7 construction validation (a bad label/dimension/NA must throw, the error class asserted); the catalog vs sigminer/MP toy cross-validation; the extraction end-to-end (cosine>0.95); the fitting vs quadprog/nnls (tolerance); the bootstrap seed determinism + **the cross-thread-count consistency**; the refdb precedence/schema rejection/manifest validation (the fixture-ized update path); the error-path tests (a condition rather than a crash, the session continuable).
- CI: 3 OS × {release, oldrel, **R-4.3 (Linux)**, devel (allowed to fail)}; rcmdcheck --as-cran + cargo test/clippy/deny (the ban rules)/audit; the **valgrind + ASAN/UBSAN scheduled job**; the per-PR arms run the testthat suite as attested parallel shards against one committed manifest (docs/devlog/2026-10-21-ci-shard-parallel.md) -- the arm split is a schedule, the test coverage per platform is unchanged; the benchmark gate = the sanity bound; codecov (R≥85%, the Rust reported without a gate); the docs-sync check (the ROADMAP `ms_*` ↔ ARCH/R layout cross-check, the drift goes red); rhub/win-builder before submission.

## 10. The paper positioning (D14)

- **The headline (Framing A)**: "Calibrated inference of mutational signature exposures" -- the domain's exposure intervals have never been validated for calibration; MSU-Fit/LowCount/Infer provide the first complete inference layer; the Rust performance makes the calibrated statistics feasible in minutes at cohort scale ("fast *so that* statistical honesty is affordable"). Target: Nature Methods (the sprint) / Nat Commun (the realistic landing).
- **The support (Framing B)**: the five-modality unified ecosystem + the bit-for-bit semantics compatibility + the versioned reference library. Target: the Genome Biology floor.
- **The case-study upgrade's three paths** (needing the cohort collaboration, the G gate): the treatment-record concordance / the RNA-only cohort / the low-count panel diagnostic-grade detection (the MUTYH/MSI pattern).
- **The kill criteria** (pivot upon triggering, see reviews/05 §9): the leading experiment refuting, the Cornet formal publication suppressing, no cohort collaboration before M3b, a competitor publishing calibrated CIs, the schedule slipping >100%, no co-maintainer.

## 11. The risk register (the v2.1 additions)

| Risk | Mitigation |
|---|---|
| the rand-ecosystem RNG drifting across versions | the self-developed PCG64 + the documented stream layout + the cross-version golden (D6/A6) |
| the thread count changing the numerical result | the parallelism between the units + the fixed reduction + the identical() CI test (A7) |
| the "bit-for-bit" acceptance clashing with clean-room | the two-tier terminology (D11); the R NMF cross-check as a one-off platform experiment |
| a statistical claim pierced by a statistical reviewer | the D13 four-piece kit upfront + the G0 leading experiment + a statistics co-author (an organizational action item) |
| the Cornet formal publication suppressing the correlation component | the pre-registered falsifiable claim + the componentization downgrade (A4) + the quarterly competitive review (**the 2026-09-28 event already occurred**: bioRxiv 2026.09.14.751548; the review conclusion = the strategy maintained, the kill not triggered, see the devlog G3 review; the threat surface escalated: the Park group + MuSiCal, G0 promoted to a key path for Framing A) |
| the vendor size exceeding the limit | the M0 spike settling the numbers + the dependency contraction (dropping rand) + faer defaulted off |
| the CRAN 2-thread/fork | the per-call pool + the option double-read + Makevars -j2 + the BiocParallel compatibility documentation |
| the refdb dual-source drift | the precedence + schema_version + the manifest + the fixture tests (A13) |
| the timeline fantasy | the dual-track v0.1/v0.2/v1.0 + the hardened Non-goals (ROADMAP v3) |
| the bus factor | the co-maintainer pulled forward to M1s (an organizational action item) |
