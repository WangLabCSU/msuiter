# GO-05 bootstrap-vs-sigminer campaign — pre-registered protocol (2026-10-10)

Pre-registration law: this file is committed **before** any campaign execution; every
number the campaign reports must be traceable to a witness this protocol names. The
SCIENCE-FIRST LAW binds: *the number is whatever the measurement says*. `≥100×` is the
target quoted at docs/ARCHITECTURE.md:266 (`| bootstrap（10³×10³） | sigminer 串行 | ≥100× |`)
— a target, not a result. If the measured ratio falls short, docs/PERFORMANCE.md states
the measured truth with protocol details; no inflation, ever.

## 1. Competing implementations (witnessed, not assumed)

| arm | entry point | engine facts |
|---|---|---|
| **A1** sigminer serial | `sigminer::sig_fit_bootstrap_batch(counts, methods="NNLS", n=R, use_parallel=FALSE, seed=S, job_id=NULL)` | batch: one whole-matrix `sig_fit` point pass, then a **serial `for` over samples** calling `sig_fit_bootstrap` — itself a serial `sapply(1:n, ...)`; per replicate: multinomial resample `sample(seq(K), total_count, replace=TRUE, prob=catalog/sum(catalog))` (total-preserving) + `sig_fit` refit; per-sample `on.exit(gc())`. No worker knob engaged (`use_parallel=FALSE` ⇒ no future plan installed). |
| **A2** msuiter pool | `msuiter::ms_fit_bootstrap(catalog, signatures, method="nnls", n_boot=R, seed=S, n_threads=10)` | one `ms_fit`-shape point fit + `.ms_fit_bootstrap_rust` FFI; per-replicate PCG64 streams (`StreamId{replicate:b}`); percentile CIs kernel-side post-zeroing/rescale. |
| **A3** msuiter single-core | same, `n_threads=1` | isolates pool-scaling from kernel speedup (secondary ratio). |

Data-byte identity between arms is the comparison's foundation: both arms consume the
**same serialized `campaign.rds`** whose SHA-256 is sealed in `seal.json` before any
timing starts (same-window literal law).

## 2. Frozen workload constants (zero runtime touch)

- `SEED = 20260928` (G0 master seed; the frozen seed domain — arms carry it into their
  own RNG regimes: R's `sample` via batch `set.seed(L'Ecuyer)`, PCG64 for the Rust
  kernel. RNG-stream equality is NOT claimed; data bytes, not streams, carry identity).
- Data shape (target-row literal, ARCHITECTURE.md:266 `10³×10³`): **K=1000** mutation
  rows × **S=1000** samples; **n_sig=50** signatures (column-normalized, deterministic
  from `SEED`); per-sample counts Poisson around a sparse-true-exposure mixture
  (`gen_campaign.R` is the sole generator; deterministic; double-run byte-identity is a
  TDD unit).
- **R (replicates) tier ladder** — decided ONLY by the probe projection, before any
  full arm runs:
  - Tier-A (literal): `R=1000` — taken iff projected A1 wall ≤ **21600 s** (6 h).
  - Tier-B (default-budget): `R=200` (msuiter's own documented default) — taken iff
    projected A1 wall ≤ 21600 s.
  - Tier-C: neither ⇒ campaign stops at pilot; PERFORMANCE row stays
    **UNMEASURED-with-pilot-link** (the charter's sanctioned fallback; the number is
    not manufactured).
  The projected wall: `base + rate × (S × R)` fitted from the probe witnesses (§4).

## 3. Arms' measurement discipline (m1s idiom, RB-07/08/10 laws)

- Host-side bench, both arms the same physical machine; strict serial fan-out=1;
  starts only after the m7 matrix fully completes and `docker ps` shows no live
  measurement container; co-tenants recorded verbatim (`shiny-server-test` is
  non-measurement scaffolding per governance scope, present throughout).
- Heavy arms are **single-shot timed** (RB-10 single-authoritative-shot doctrine;
  4× repetition of multi-hour arms is not measurement budget — disclosure lives in
  `result.md`); the probe witnesses (small shape) carry the repeatability evidence:
  warmup 1 + timed 3, median.
- Pre-registered 3×-floor gate, campaign-scoped (this lane's classes are host-R,
  not the container `_FLOOR_ANCHORS`): each full arm's observed wall gated at
  **3 × the probe-projected wall** for its own class; breach ⇒ **HALT-AND-REPORT**
  (no rerun, no floor refit, no averaging away).
- Probes measure, never adjudicate: probe witnesses record measurements only; the
  gate is adjudicated by the campaign pass against the embedded projection.
- Fresh witnesses per launch; `campaign_launches.jsonl` counts full-campaign
  launches — a second full launch into the same campaign dir is refused
  (RB-11(ii) no-reuse law, harness-enforced); log paths are never reused across
  launches (`>` targets unique per launch).

## 4. Witness inventory (all committed under the campaign outdir)

```
bench/results/bootstrap_vs_sigminer_<ts>/
  seal.json                    # sha256 of campaign.rds + generator argv + host facts
  campaign.rds                 # the shared data bytes
  witnesses/probe_A1_*.jsonl   # probe medians (per-replicate cost model inputs)
  witnesses/probe_A2_*.jsonl
  witnesses/probe_A3_*.jsonl
  witnesses/anchor_A1.rds      # anchor-subset bootstrap CIs, sigminer
  witnesses/anchor_A2.rds      # anchor-subset bootstrap CIs, msuiter pool
  witnesses/arm_A{1,2,3}.jsonl # full-arm records: wall/cpu, loadavg before/after, tier
  campaign_timings.csv         # 9-column pinned table (timings.write_timings schema)
  campaign_launches.jsonl      # single-shot ledger
  result.md                    # numbers + verdict, each line path-witnessed
  Seeds.txt                    # provenance block (SEED, commit, R versions, digests n/a host-side)
```

Hardware pins for this lane (host-R domain, NOT the docker VM): `host` =
orchestrator `socket.gethostname()`; `hw_profile` = verbatim
`"host-R campaign | Apple Silicon | 10 cores | hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2"`
exported through `M7_HW_PROFILE`; reader-side `verify_campaign.py` re-verdicts the
committed table from its own bytes (same shape as `verify_hardware_pin.py`).

## 5. Correctness anchor (before any ratio may be spoken)

Subset: first **25** samples × **R_anchor=200**, `bca=FALSE`, same data bytes.
Gates (both must pass or the campaign yields UNMEASURED, anchor witness committed
with the failure named):

1. **CI-overlap ≥ 90 %** of the 25×50 cells: percentile interval from A1 vs A2
   non-empty-intersection (the arms share the estimand: total-preserving multinomial
   resample + NNLS refit + percentile bounds; RNG streams differ by design).
2. **median relative agreement ≤ 15 % on ≥ 95 %** of cells (per-cell replicate median).
3. **Thread-count invariance witness** (the package law re-used as harness
   instrument): A2 vs A3 full-run point exposures + `ci_lower`/`ci_upper` must be
   `identical()` — same seed, same data, threads ∈ {1,10}.

**Comparison-scale addendum (pre-registration, before any launch).** The two arms'
raw intervals do not share a scale by construction: msuiter's kernel CIs ride the
post-zeroing/rescale path while sigminer's bootstrap `expo` is the raw refit scale.
The anchor therefore compares both arms in **share space**: per sample, every
`lo`/`hi`/`median` cell is divided by the sum over signatures of that arm's own
per-cell replicate medians. Both sides take the 2.5/50/97.5 percentiles
(type-7 quantile) from the **raw replicate draws** — sigminer's `expo` columns,
msuiter's `boot_draws` slab (`[signature, sample, replicate]`, the RAW cube) —
never from the rescaled CI attributes, so the percentile pipeline is symmetric.
The `identical()` invariance witness of gate 3 is the separate determinism law
(it legitimately reads the kernel CI attributes) and is not an equality claim
about the anchor scale.

## 6. Verdict vocabulary and doc writeback (exact, no third option)

- `MEASURED-true  ≥100x`  — ratio(A1/A2) ≥ 100 at the taken tier, anchors green.
- `MEASURED-false <value>` — ratio(A1/A2) < 100, anchors green: PERFORMANCE.md and the
  `R/fit.R` docstring L-D claim (CAPABILITY-MATRIX L-D) state the measured ratio with
  tier/shape disclosure, no inflation.
- `UNMEASURED-with-pilot` — Tier-C, or anchor failure: the row says so and links the
  pilot witnesses. The ≥100× wording remains a target quote, never a result.

Ratio definition (frozen): `ratio = median(A1 wall) / median(A2 wall)` over each arm's
single timed authoritative run; secondary `A1/A3` disclosed alongside. Every committed
number is verbatim command output (same-window literal law).

## 7. TDD instrument (group (T), `bench/m7/tests/test_bootstrap_campaign.py`)

Units run seconds-scale on the attested host (R 4.5.2 + installed sigminer 2.3.1 +
msuiter 0.1.0.9000 — the local gate lane; a missing host library FAILS, it is seen,
never tallied green — skip-not-skip). Coverage: generator double-run byte identity;
tier-decision pure function (all three tiers + boundary); projection math (cost-model
fit); anchor gates pass/fail fixtures; refuse-to-report (result.md cannot carry
MEASURED while anchor/witness bytes contradict); 9-column pin contract on the
campaign table; probe-schema law (probe witnesses carry no verdict fields);
launch-ledger refusal of a second full shot; SEED pin scan (constant frozen, no
G0-protocol-token drift).
