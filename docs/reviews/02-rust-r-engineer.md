# The review 02: the Rust/R systems-development expert (an independent review, 2026-09-28)

> The reviewer persona: a CRAN maintainer of extendr-family R packages, deeply versed in the R C API, cross-platform packaging and cargo vendoring. The load-bearing claims were re-checked first-hand against upstream (the extendr-macros wrapper source, crates.io extendr-api 0.9.0, docs.rs rand/twobit, the CRAN Using Rust page).
> **The overall verdict: conditional pass (conditional go).** The contract density of the R/algorithm/licensing layers is rarefaction-grade high, but **the contracts of the Rust runtime layer (the random numbers, the concurrency, the panics, the FFI boundary, the distribution budget) are almost wholly absent** — and that is the ground of the "orders-of-magnitude speedup + reproducibility" narrative.

## P0

### 1.[P0] The reproducibility contract is built on quicksand: `rand`'s output carries no across-version consistency guarantee
- The docs.rs original sentence: `SmallRng` **"Non-portable: any future library version may replace the algorithm"**; for reproducibility one should use `rand_pcg/rand_xoshiro`; rand 0.9 is a destructively major version and crates has already rolled to 0.10.x — during the reviewing window one `cargo update` silently voids the "seed-reproducible across the whole chain".
- **The fix**: do not touch rand's RNG surface. Self-write PCG64 (~60 lines) + self-write the multinomial/Dirichlet (rand_distr has no multinomial to begin with); the seed protocol = the user seed → SplitMix64 → the per-(replicate, rank, fold) counter streams, with the stream layout written into the paper's Methods; Cargo.lock + vendor pinned; the across-version CI golden tests.

## P1

### 2.[P1] The CRAN 2-thread compliance and the fork-safety mechanism are not landed, each carrying a set-once trap
- The rayon global pool is lazy set-once: `RAYON_NUM_THREADS` is read once only at the first parallel call; a resident pool turned into a corpse after a `mcfork` (common in the Bioc ecosystem) fork; CRAN requires the install-time cargo be capped at `-j 1/2`, which the rextendr default Makevars does not do.
- **The fix**: **abandon the global pool** — inside every top-level FFI call `ThreadPoolBuilder::new().num_threads(n).build()` + a scoped `install()` (~100µs, negligible); n comes from the R side `getOption("msuiter.threads")` (defaulting to 2 under `_R_CHECK_LIMIT_CORES_`); Makevars.in explicitly `CARGO_BUILD_JOBS=2`; document the BiocParallel `threads=1` compatibility.

### 3.[P1] The FP determinism gap: the thread count must not change the numerical result
- The parallel reduction order varies with the thread count → 2 threads (the checks) and 16 threads (the user) produce bit-level different results — the reproducibility claim gets pierced.
- **The fix**: parallelism exists only across the independent units (the replicate/sample/bootstrap); within a unit the kernel is single-threaded with a fixed reduction order; the hard CI test: the same seed over threads∈{1,4} outputs `identical()`.

### 4.[P1] The handle registry + `.state` is complexity paid for a capability that does not exist: make the FFI stateless
- `MsSignature` is the fitting's **final product** — all ready-made matrices, with no state to reside on the Rust side; the genome mmap+parse is microsecond-grade. The price of the handles: an externalptr does not enter RDS → a user's load followed by one touch of `.state` triggers a **silent refit**; leaks; fork risk; it breaks the waldo comparisons.
- **The fix**: make the v1 FFI wholly stateless (`ms_tally_rust(2bit_path, ...)` computes over an in-process mmap then releases; `ms_extract_rust(counts, params, seeds)` goes in and out once); **delete `.state` from the S7 class**; keep of the caugi pattern only the "read-only property" aesthetics; should resumable computation ever be needed, introduce the handle + `reg.finalizer` + an explicit `ms_close()` + a reconnect error (never a silent recompute).

### 5.[P1] The hand-written randomized SVD/Cholesky degrade exactly in the hardest benchmark scenario
- The leading singular triplet needed by NNDSVD has its singular gaps collapse under Wu 2022 r=0.8–0.95 (the flagship scenario), and insufficient power iterations amplify the error; when the signatures are near-collinear (SBS1/5) `G=PᵀP` is ill-conditioned and a pivot-less Cholesky takes a negative square root; the placement of ε in the KL denominator's zero channels directly decides whether NaN ships out of the factory.
- **The fix**: the randomized SVD gets fixed q≥3 power iterations + oversampling ≥16 + an "exact Gram-SVD cross-check" property test (the 1536² Gram is fully doable); the NNLS Gram uses a **pivoted LDLᵀ** + the `ε·‖G‖` ridge + the KKT residual assertion; the KL denominator gets `max(·,ε)`, `log(ε+·)`, with the ε value entering the documentation and the TDD.

### 6.[P1] Ctrl-C: a long-running Rust call is uninterruptible
- `R_CheckUserInterrupt` may be called only from the main thread (it is UB inside a rayon worker).
- **The fix**: the main thread polls `R_CheckUserInterrupt` at the parallel chunk boundaries; the workers check only an `AtomicBool` cancellation flag; the exported contract: interruptible, and with no residue after the interrupt (which falls out automatically together with the stateless design).

### 7.[P1] The distribution budget has no numbers: the vendor volume, the MSRV and the install-time behavior are parked to M8 to be "audited"
- The estimate: the vendor expansion ~15–25MB, ~4–8MB after xz, which stacked easily pokes through the CRAN 10MB guidance line and needs a waiver; **the good news: extendr-api 0.9.0's official MSRV = 1.71** (meeting CRAN's two-year cargo requirement); rust-toolchain.toml must never enter the tarball.
- **The fix**: pull the volume/MSRV audit **forward to the M0 spike** (one week to produce the real vendor + xz byte counts + a rustc 1.71 build proof); `extendr-api default-features=false` keeping only ndarray; cut the rand tree per P0-1; Makevars on the string2path pattern (vendor.tar.xz + cargo_vendor_config.toml + CARGO_NET_OFFLINE + -j2 + cleanup); DESCRIPTION `SystemRequirements: cargo, rustc (>= 1.71)`.

## P2

### 8.[P2] "Bit-level alignment with R NMF brunet" is an unachievable acceptance standard
- R brunet goes through the platform BLAS (Accelerate/OpenBLAS/reference), and the multiply-add order varies with the vendor — inherently flaky across a 3-OS CI.
- **The fix**: two-level acceptance — for the R NMF cross-check use a relative tolerance (`‖ΔW‖/‖W‖ < 1e-10`, the same-seed convergence point); the bit-level golden locks only **your own implementation's historical versions**.

### 9.[P2] The FFI boundary lacks hard contracts: the memory order, the NA/NaN, the i32 boundary
- R column-major vs ndarray row-major — **a 96×96 square matrix will silently transpose**; `NA_integer_`=INT_MIN becomes a legitimate large number under `as usize`; a "non-negative" validation that does not pair with `anyNA()` leaks.
- **The fix**: ① crossing-boundary matrices get a uniform explicit column-major view + a square-transposition detector unit test (an asymmetric golden round-trip); ② the NA contract = the R validator enforces an `anyNA()` rejection, the Rust side `debug_assert!`s and produces no NaN; ③ the indices i32→usize + a bounds check, out-of-bounds returning an R error.

### 10.[P2] The panic policy should be written into the documentation
- Verified that the extendr-macros wrapper uses `catch_unwind(AssertUnwindSafe(...))` to turn panics into R errors — it does not punch through the FFI. But the error path `throw_r_error → Rf_error → longjmp` **skips the Rust stack unwinding**: calling a throwing helper deep in the kernel leaks heap buffers; a rayon worker panic propagates back to the calling thread and gets caught, but the "partially complete output" state needs defining.
- **The fix**: "the kernel returns `Result<_, MsError>`, converting to an R error only at the ffi crate boundary; calling throwing APIs inside the kernel is forbidden; any panic → the whole call errors, no partial results". The R-side tests assert the error paths yield a condition and the session remains continuable.

### 11.[P2] The twobit crate positioning is self-contradictory
- twobit 0.2.2 is a `Read + Seek` generic reader: `open()` does buffered ordinary reads (a million-variant random access = a million small reads), `open_and_read()` pulls the whole file into RAM (hg38 ~800MB) — **it does not mmap itself**; the byte-swap (big-endian) file support is unexplained.
- **The fix**: put the two-way choice into an ADR: (a) `TwoBitFile` over `Cursor<Mmap>` (the memmap2 + Cursor composition), batched by chromosome order, each 4bit word decoded once, vendor-pinned =0.2.2; (b) a self-developed ~300-line reader + a cross-check against `rtracklayer::import`. Either road first validates the byte-swap/duplicate-chrom/N/softmask semantics.

### 12.[P2] The workspace three-crate split goes the right direction, missing two guardrails
- **The fix**: a single dependency direction (ffi→catalog→engine, the reverse forbidden); the engine/catalog get `#![forbid(unsafe_code)]`, unsafe confined to the ffi crate with a per-site SAFETY comment; cargo deny adds ban rules forbidding the engine/catalog from depending on extendr-api.

## The overall verdict and the highlights
- **Conditional go**. The clauses of the Rust runtime layer (the RNG version contract, the concurrency/fork/interrupt, the panic/longjmp, the FFI hard contracts, the distribution-budget numbers) must be written into the ADRs at M0, not paying the tuition at M8.
- **The three things done well**: the three-surface FFI convergence (the indices do not return strings / one normalization at the boundary / a small export surface); the Rust/R engineering research is accurate and actionable (no "getting onto CRAN is easy" illusion); the S7 cost model measured into a discipline (6µs/17µs → the API-boundary iron law) — "the first time I have seen it in an extendr+S7 proposal I have reviewed".
- Sources: docs.rs SmallRng; CRAN Using Rust; crates.io extendr-api 0.9.0 (MSRV 1.71); extendr-macros wrappers.rs; docs.rs twobit.
