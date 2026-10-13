# Research report 06: the state of play of the S7 class system, the design patterns and the method-framework blueprint
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-28. Verified against CRAN, the RConsortium/S7 repository, the R base NEWS, the official vignettes, the tidymodels/mlr3 sources and local measurements (R 4.5.2 + S7 0.2.2, arm64). The **[unverified]** items are marked.

---

## 1. The state of play of S7 (late 2026)

- The repository migrated to **`RConsortium/S7`** (the docs at rconsortium.github.io/S7), active (a commit on 2026-09-26).
- CRAN **S7 0.2.2** (2026-04-22), `Depends: R (>= 3.5.0)`. The version history: 0.1.0 (2023-08) → 0.2.0 (2024-11, the new construction semantics, lazy defaults, the `prop()` C rewrite) → 0.2.1 (2025-11) → 0.2.2 (2026-04).
- **It has not yet been merged into base R** (the R 4.6.1 NEWS mentions the S7 body zero times; what was merged are the "enabling hooks": R 4.3's `@` becoming an S3 generic + `nameOfClass()`, R 4.4's OBJSXP). The RConsortium/S7 issue #542 confirms **no merge timetable** (the maintainer Michael Lawrence: adoption first).
- **The dependency strategy**: depending on S7 today is safe (104 CRAN packages already declare it), you need `Imports: S7` + `methods_register()` in `.onLoad()`; if you support R ≥ 4.3 no `@` compatibility shim is needed. **The recommendation: the floor R >= 4.3.**

## 2. The S7 feature inventory (the exports verified at 0.2.2)

- Classes: `new_class(name, parent, package, properties, validator, constructor)`; **abstract classes** `abstract = TRUE`; `new_union(...)` union types; `new_S3_class()` wrapping S3; `S4_register()` (dev already supports bidirectional S7↔S4 inheritance). An S7 object is essentially an S3 object (class = `c("pkg::Foo", "S7_object")`) — **the RDS round-trip is safe** (dev handles the `_S7_class` attribute renaming and the old-serialization fallback).
- Properties: `new_property(class, default(lazy), getter, setter, validator, name)` — **dynamic/computed properties, read-only setters, lazy defaults**; `x@prop` reads/writes, `set_props(check=)` batched skipping validation, `prop_names()/prop_exists()`.
- Validation: a class-level `validator = function(self) returning a character vector of problems`; validated at construction and at property writes; `validate()/valid_eventually()/valid_implicitly()` control the timing.
- Generics: `new_generic` + `S7_dispatch()`; `method(foo, Class) <- ...` multiple dispatch; **methods can be registered onto base/S3/S4 generics** (print/plot/summary/`$`/the math groups); `new_external_generic("pkg", "gen", "sig")` declares a method onto a suggested-package generic (lazily wired); extension packages go through `methods_register()` in `zzz.R` (dev: `S7_on_load/S7_on_unload/S7_on_build`).
- **No `class_externalptr`, no altrep classes**: an externalptr is held via a `class_any` property + a custom validator (the r-polars direction confirms this is the official intent); S7 preserves ALTREP but does not manufacture it.
- **Performance (the local measurements, 200k calls)**: a single dispatch ≈ 6.2 µs (S3 ≈ 2.0); a double dispatch ≈ 10.1 µs; the property read `@` ≈ 1.2 µs, **the write ≈ 17 µs** (a write triggers a full-object revalidation); construction+validation ≈ 50–85 µs/object.
- **The engineering iron laws**: S7 lives only at the API boundary; the per-channel/per-sample loops never enter R (push them into Rust); the hot path avoids `@<-` (use `set_props(check=FALSE)` to stash + a one-time `validate()`); an externalptr does not survive the RDS → you need a reconnect/serialization policy (the polars pattern: store the inputs+parameters, rebuild the handle on demand).

## 3. The production adoption (the evidence)

- **ggplot2 4.0.3** (2025-09): the NEWS explicitly says "S3 parts replaced with S7 bits" — the strongest endorsement; the ggiraph/GGally/ggrepel etc. of the gg ecosystem follow.
- Posit/r-lib: ellmer, marquee, ragnar, shinychat, **filtro** (Max Kuhn, the first tidymodels-family S7 registry, see §5), desirability2; the Rust/R hybrid: **caugi 1.3.0** (extendr + S7, our best precedent, see §4); computation: osqp/CVXR/quickr.
- Bioconductor: officially keen but early — `Bioconductor/S7Examples` (the BiocClasses working group), plyxp/anansi; **the BioC2026 keynote "S7 for Bioconductor" (Michael Lawrence)**. If one later submits to Bioc, keep `S4_register()` interoperability reserved.
- There is no old r-lib/s7 address (it migrated); rextendr 0.5.0 has **no S7 codegen** — write the S7 layer yourself (thin, one-off work).

## 4. The S7 + extendr integration precedent: the caugi pattern (our template)

- The Rust state is hidden inside a lazily built **"Session"**: the S7 class's `session` property is a `class_any`, **its setter errors outright** (read-only, rebuilt only via the domain verbs `add_nodes()`/`add_edges()`) — a write-guard on the Rust state.
- **Derived properties = computed getters**: the `nodes`/`edges` properties have no storage, the getters call the Rust accessors and return fresh R data. *Store an opaque handle, project the R-friendly views on demand.*
- The `zzz.R` full dance: `methods_register()` + the S4 hooks + waldo `compare_proxy` (for the testthat comparisons).
- The Rust-side registry (the edge types) is held as an externalptr environment singleton, R exposes only the `list_/register_/reset_` verbs.

**The application to this project**: the opaque state extendr returns (catalog handles, fit state) goes into a `class_any` read-only property; everything user-visible is a typed+validated property; the domain verbs mutate through the Rust round-trip; implement `print/format/plot` early; register `compare_proxy` for the tests.

## 5. The method-framework design patterns for the benchmarking (extracted from the sources)

| The ecosystem | The object system | The registry pattern | The key API |
|---|---|---|---|
| **parsnip** (S3) | a spec object (the `model_spec` subclasses) + a namespace-environment registry (data, not a method table) | `set_new_model/set_model_engine/set_fit/set_pred/set_dependency`; `translate()` resolves first, executes after | third-party extension = `.onLoad()` calling `set_*` to write data rows |
| **yardstick** (S3) | a metric registry | the `new_numeric_metric(fn, direction)` constructors + the `metric_set()` combiner | the result tibble carries `.metric/.estimator/.estimate` |
| **dials** (S3) | a parameter space | `new_quant_param/new_qual_param` (range/trans/label, `unknown()`) | — |
| **workflows/hardhat** (S3) | orchestration + **the extraction-generic contract** | `extract_preprocessor/extract_recipe/extract_mold/extract_fit_parsnip/extract_fit_engine/extract_fit_time` | **makes every engine's products uniformly introspectable — the key to benchmark friendliness, copy its spirit** |
| **mlr3** (R6) | the abstract `Learner` (`$train/$predict` delegating to the private `$.train`) + a Dictionary registry (registered at `.onLoad`, `register_namespace_callback`) | the `mlr_learners` dictionary; `benchmark()/benchmark_grid()` Task×Learner×Resampling → the `rr$score()` tibble | the benchmark grid + the unified scoring |
| **filtro** (S7!) | the S7 `class_score`: metadata properties (direction/range/tuning/packages/label/calculating_fn=class_function/results=class_data.frame) + a subclass per method + `method(required_pkgs, class_score)` | **the S7 template closest to our problem** | — |

**The unified template**: a spec object (small, serializable, metadata-rich) → a registry row (spec type, engine, mode) → resolve/translate → fit → a result object (embedding the spec + the extract_* generic family) → extension = writing the-registry data at load time.

## 6. The S7 blueprint for this project (the recommendation)

```r
# ---- the data layer ----
MsVariants  : the variant table + genome + provenance (the input container)
MsCatalog   : counts (channel×sample, a dimension-consistency validator) + channels (a registry snapshot)
              + samples + provenance -- the channel-label matching is enforced in the constructor
# ---- the specification layer (the parsnip/filtro-style spec) ----
MsEngine    : abstract (name/mode/packages/params(dials-style)/deterministic/label)
  ├─ MsNmf        # the KL/EU/HALS variants selected via params
  ├─ MsArd        # the automatic-K triage
  ├─ MsSparse     # the volume regularization (our self-built realization of the mvNMF idea)
  ├─ MsCorrelated # the correlation-aware (our self-built optimized realization)
  ├─ MsLda        # the topic model
  └─ MsSupervised # the SuperSigs-style supervised extraction
# ---- the result layer ----
MsSignature : signatures + exposures + stability + K evidence + engine + seed
              + .state (class_any, the setter errors -- the caugi-style read-only Rust handle)
MsFit       : exposures + support + tests (CI/LRT) + reference + engine
MsRefDb     : the versioned signature library (the per-build availability metadata)
MsBenchmark : the Task×Engine×scenario grid results (the mlr3-style score tibble)
```

- The custom generics (a small set): `ms_tally()`, `ms_extract()`, `ms_fit()`, `fit_engine()`, `extract_signatures()/extract_exposures()/extract_state()/extract_fit_time()` (the hardhat naming), `required_pkgs()` (the filtro precedent), `ms_benchmark()`.
- Reuse the base/S3 generics: print/format/plot/summary/knit_print (`new_external_generic("knitr",...)`).
- **The registry = data, not class explosion**: thin engines use registry rows, the engines with heavy invariants use S7 subclasses (a hybrid policy).
- Interoperability: `as.data.frame()/convert()` to tibble; ggplot2 4.x is itself S7, seamless; RDS serialization = store the spec+inputs, rebuild the handles on demand.
- **Hedging the risk that S7 never enters base R**: an S7 object is an S3 object — the semantic fallback is natively safe; the floor R ≥ 4.3.

## 7. The citations/evidence

- CRAN S7 0.2.2; RConsortium/S7 (the docs: rconsortium.github.io/S7); the base R NEWS (the 4.3/4.4 enabling hooks; 4.6.1 without S7); the R Core blog "Generalizing Support for Functional OOP in R" (2024-05)
- the ggplot2 4.0.0 NEWS #6352; the CRAN dependency scan (104 packages); the BioC2026 schedule; Bioconductor/S7Examples
- the caugi 1.3.0 source (session/read-only properties/the zzz.R dance); the extendr crate 0.9.0 (the ALTREP warning + the issues #945/#743)
- parsnip `R/aaa_models.R`, the yardstick NAMESPACE, dials, the workflows/hardhat extract_* generics, the mlr3 1.8.0 `Learner`/Dictionary/zzz.R, filtro (the S7 class_score)
- the local measured performance numbers (R 4.5.2, S7 0.2.2)
