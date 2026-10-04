//! Calibration Monte Carlo driver (U-M3b-03): the pure (R-type-free) heart
//! of `ms_calibration_grid_rust` — the grid simulation behind the M3b
//! empirical-coverage measurement (design memo
//! `docs/devlog/2026-10-04-M3b-design-memo.md` §1–§3, PI ruling 2026-10-04).
//!
//! # What one grid cell measures (estimand ②)
//!
//! A cell fixes a truth: a dictionary `sigs` (row-major m×k, embodying the
//! Shannon-entropy axis) and a truth exposure spectrum `h*` (count scale,
//! length k; zero entries are decoys). Each Monte Carlo replicate draws a
//! catalog `counts` whose channel expectation is `μ = W·h*`, fits it with
//! the PRODUCTION face (the U-M3a-03 [`super::fit::bootstrap`] pipeline:
//! `likelihood_bidirectional` exposures at the frozen `FIT_EPS`/`FIT_MAX_ITER`,
//! share zeroing at the sigfit anchor 0.01, `rescale_to_totals`-aligned
//! percentile CI, optional U-M3b-02 BCa face), and tallies whether the true
//! `h*_a` lies inside the returned CI for every truth-supported signature
//! (the "每真值 share 格" marginal tally; decoys enter the estimand-③
//! confusion tally only). M replicates aggregate into the cell's coverage
//! fraction with its binomial standard error.
//!
//! # Two generative arms (memo §2)
//!
//! * [`GenerativeArm::Multinomial`] — the main arm: per sample
//!   `counts ~ Multinomial(N, μ/Σμ)` via `engine::resample::multinomial`
//!   (exactly N stream words; the calibration-declaration carrier).
//! * [`GenerativeArm::NegativeBinomial`] — the Jiang overdispersion stress
//!   arm: per channel `counts_c ~ NB(μ_c, size)` independently via
//!   `engine::resample::nb_sample` (mSigAct size semantics; `size = +∞` is
//!   the exact Poisson limit). The two arms must never be mixed in one
//!   calibration claim (memo §2.2).
//!
//! # Stream layout (extends the PCG64 canonical layout v1)
//!
//! Per memo §2.1 the MC streams are `StreamId { replicate: rep, rank:
//! grid_cell_id, fold: 0 }` with **1-based** cell ids, so MC streams never
//! meet the bootstrap's `rank = 0` nor CV's `fold ≥ 1` streams. The NB arm
//! offsets its ranks by the cell count (`rank = cell_id + n_cells`), keeping
//! the two arms' streams disjoint while both stay in the fold-0 band. The
//! first word of each replicate's MC stream is the master seed handed to the
//! inner [`super::fit::bootstrap`] call (whose own boot streams live under
//! that derived seed's `rank = 0` band) — a frozen, pure derivation, so the
//! whole grid is a bitwise function of `seed`.
//!
//! # Grid layout and the frozen truth convention
//!
//! [`calibration_grid`] sweeps `n_grid × shares` cells over ONE caller
//! dictionary (one entropy-bin arm of the memo's 11 × 3 × 6 grid; the
//! entropy axis is a separate call per truth dictionary). The frozen truth
//! convention ([`cell_spectrum`]): signature 0 is the TARGET carrying the
//! swept share; the residual mass is split equally over signatures 1..k. A
//! swept share of 0 makes the target a decoy (the estimand-③ FPR point).
//!
//! # Threads / interrupt (contracts 6/7)
//!
//! Parallelism exists ONLY between (cell, replicate) units, scheduled in
//! chunks with main-thread boundary interrupt polling and workers seeing
//! only the `cancelled` flag — the `replicates.rs` skeleton, copied locally
//! from `fit.rs::run_boots_in_chunks` (the driver there is module-private
//! and the crates' file discipline keeps each unit self-contained). Every
//! unit is sequential inside (its bootstrap runs at one thread, its own
//! per-call pool), so `threads ∈ {1, N}` are bit-identical (A7); chunks are
//! gathered in chunk-index order with no order-sensitive float reduction.
//!
//! # Compound zeroing tally (estimand ③, memo §3)
//!
//! Per (replicate, sample, signature) the frozen decision rule
//! `final_zero = (point support = 0) ∨ (stability < 0.95) ∨ (ci_lower
//! share < 0.01)` is crossed with the truth to fill the confusion cells:
//! `true_zero` / `false_keep` (truth absent; FPR direction),
//! `false_zero` (truth present, zeroed; FNR direction) and the kept cell
//! split into `kept_covered` / `kept_missed` (the estimand-② coverage
//! event among kept signatures). The CI face read by both the coverage
//! event and the rule is the selected one (percentile, or BCa when
//! `bca = true`; BCa fallback cells are bit-identical to percentile).

use std::sync::atomic::{AtomicBool, Ordering};

use rayon::prelude::*;

use msuiter_engine::error::MsError;
use msuiter_engine::likelihood::SIGFIT_ZERO_SHARE;
use msuiter_engine::resample;
use msuiter_engine::rng::{MsRng, StreamId};

use super::fit::{self, FitMethod};
use super::probes::build_call_pool;

/// The PI-ruled 4SE acceptance window of the calibration verdict (memo
/// §1.3: M = 2000 reps/cell gives 4·√(0.95·0.05/2000) ≈ 0.0195 around the
/// 0.95 nominal level). Membership is inclusive at both ends. The FFI
/// takes the window explicitly (the bench may re-judge at a different
/// band), so this frozen constant is the default the R side passes —
/// surfaced here as the single source both sides reference.
#[allow(dead_code)]
pub const CALIBRATION_WINDOW: (f64, f64) = (0.930, 0.970);

/// Support-stability floor of the compound zeroing rule's second clause
/// (memo §3: `support_stability_a < 0.95` — the boot support is unstable).
pub const CALIBRATION_STABILITY_FLOOR: f64 = 0.95;

/// Generative model of one calibration arm (memo §2; see the module docs).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GenerativeArm {
    /// Multinomial main arm: `counts ~ Multinomial(N, μ/Σμ)` per sample —
    /// the total is conserved exactly (the calibration-declaration carrier).
    Multinomial,
    /// Negative-binomial stress arm with the mSigAct size κ:
    /// `counts_c ~ NB(μ_c, κ)` per channel, independent — no total-count
    /// constraint. `κ = f64::INFINITY` is the exact Poisson limit.
    NegativeBinomial(f64),
}

impl GenerativeArm {
    /// Parse the wire name from the R side: `"multinomial"`, `"poisson"`
    /// (the exact NB limit), `"nb"` (κ = the FFI `nb_size`) or `"nb:<κ>"`
    /// with a positive finite (or `inf`) κ. Errors list the legal names
    /// (contract 4: errors not panics).
    pub fn parse(name: &str) -> Result<Self, MsError> {
        let legal = "\"multinomial\", \"poisson\", \"nb\" or \"nb:<size>\"";
        match name {
            "multinomial" => Ok(GenerativeArm::Multinomial),
            "poisson" => Ok(GenerativeArm::NegativeBinomial(f64::INFINITY)),
            "nb" => Err(MsError::new(
                "argument",
                format!("arm \"nb\" needs an explicit size: use nb:<size> or one of {legal}"),
            )),
            other => {
                if let Some(size) = other.strip_prefix("nb:") {
                    let size: f64 = size
                        .parse()
                        .map_err(|_| MsError::new("argument", format!("arm size \"{size}\" is not a number; legal arms are {legal}")))?;
                    if size.is_nan() || size <= 0.0 {
                        return Err(MsError::new(
                            "argument",
                            format!("arm size must be positive (or +inf for the Poisson arm), got {size}"),
                        ));
                    }
                    return Ok(GenerativeArm::NegativeBinomial(size));
                }
                Err(MsError::new(
                    "argument",
                    format!("arm \"{other}\" is not one of {legal}"),
                ))
            }
        }
    }

    /// Canonical wire name (echoed back in the result list).
    pub fn as_str(self) -> &'static str {
        match self {
            GenerativeArm::Multinomial => "multinomial",
            GenerativeArm::NegativeBinomial(s) if s.is_infinite() => "poisson",
            GenerativeArm::NegativeBinomial(_) => "nb",
        }
    }
}

/// Outcome of one [`calibration_cell`] run: M replicates of one grid cell.
///
/// Crate-internal face (the grid FFI is the production entry): the pure
/// single-cell runner is the calibration bench's recheck instrument (the
/// memo §1.3 boundary-share recheck batches) and this test suite's unit of
/// verification; `#[allow(dead_code)]` documents exactly that consumer
/// split without narrowing the face.
#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq)]
pub struct CellResult {
    /// Per (replicate, sample, truth-supported signature) — replicate-major,
    /// ascending signature within — whether the true `h*_a` lay inside the
    /// selected CI face (estimand ② marginal coverage event).
    pub coverage_per_cell: Vec<bool>,
    /// Same layout: whether the point estimate (kept value; 0 when zeroed)
    /// lay inside the same CI (a sanity diagnostic, always true on the
    /// percentile face up to zeroing-edge effects).
    pub point_in_ci: Vec<bool>,
    /// Pooled coverage fraction over `coverage_per_cell`.
    pub coverage_frac: f64,
    /// Pooled point-in-CI fraction over `point_in_ci`.
    pub point_in_ci_frac: f64,
    /// Confusion cell (estimand ③): truth `h*_a = 0`, `final_zero = true`.
    pub true_zero: u64,
    /// Truth absent but kept (false-keep; the FPR direction).
    pub false_keep: u64,
    /// Truth present but `final_zero = true` (false-zero; the FNR direction).
    pub false_zero: u64,
    /// Truth present, kept, and `h*_a ∈ CI` (the coverage hit).
    pub kept_covered: u64,
    /// Truth present, kept, but missed (kept-but-miss).
    pub kept_missed: u64,
}

/// One grid cell's aggregate over its M replicates (the element type of
/// [`calibration_grid`]).
#[derive(Debug, Clone, PartialEq)]
pub struct CellAggregate {
    /// Pooled marginal coverage fraction of the cell's M replicates.
    pub mean_coverage: f64,
    /// Binomial standard error `√(p(1−p)/n)` at the observed `p`, with
    /// `n` the number of pooled coverage tallies.
    pub se: f64,
    /// The number of replicates aggregated (echo).
    pub n_reps: usize,
    /// Confusion tallies over the cell (see [`CellResult`]).
    pub true_zero: u64,
    pub false_keep: u64,
    pub false_zero: u64,
    pub kept_covered: u64,
    pub kept_missed: u64,
}

/// Window verdict over a grid ([`calibration_verdict`]).
#[derive(Debug, Clone, PartialEq)]
pub struct Verdict {
    /// Every cell's `mean_coverage` lay inside the (inclusive) window.
    pub all_in_window: bool,
    /// Window membership per grid cell (input order).
    pub per_cell_in: Vec<bool>,
    /// 0-based indices of the cells outside the window (ascending).
    pub failing_cells: Vec<usize>,
}

/// Truth exposure spectrum of one grid cell (the frozen convention, module
/// docs "Grid layout"): signature 0 carries `share · n_total`; the residual
/// `n_total − h*_0` splits equally over signatures `1..k` (the last entry
/// takes the exact remainder, so the spectrum sums to `n_total` in f64
/// arithmetic). `k == 1` degenerates to the single signature carrying the
/// whole catalog (the swept share is vacuous there).
fn cell_spectrum(n_total: f64, share: f64, k: usize) -> Vec<f64> {
    let mut h = vec![0.0f64; k];
    if k == 1 {
        h[0] = n_total;
        return h;
    }
    h[0] = share * n_total;
    let rest = n_total - h[0];
    let per = rest / (k - 1) as f64;
    let mut acc = 0.0f64;
    for entry in h.iter_mut().skip(1).take(k - 2) {
        *entry = per;
        acc += per;
    }
    h[k - 1] = rest - acc;
    h
}

/// Stream rank of one cell's MC replicates (module docs "Stream layout"):
/// 1-based cell id for the multinomial arm, offset by the cell count for
/// the NB arm — both arms stay disjoint from each other, from the
/// bootstrap's `rank = 0` band and from CV's `fold ≥ 1` band.
fn stream_rank(cell_id: usize, n_cells: usize, arm: GenerativeArm) -> u64 {
    match arm {
        GenerativeArm::Multinomial => cell_id as u64,
        GenerativeArm::NegativeBinomial(_) => (cell_id + n_cells) as u64,
    }
}

/// One (cell × replicate) tally: the raw material of [`CellResult`] /
/// [`CellAggregate`]. `coverage` / `point_in_ci` are (sample × supported
/// signature)-major within the replicate.
struct RepTally {
    coverage: Vec<bool>,
    point_in_ci: Vec<bool>,
    true_zero: u64,
    false_keep: u64,
    false_zero: u64,
    kept_covered: u64,
    kept_missed: u64,
}

/// Shared per-cell draw/fit setup, built once per cell and read by every
/// replicate unit (Send/Sync by construction: plain slices and scalars).
struct CellJob<'a> {
    sigs: &'a [f64],
    m: usize,
    n: usize,
    k: usize,
    h_star: Vec<f64>,
    /// Channel expectation `μ = W·h*` — the multinomial weights / NB means.
    mu: Vec<f64>,
    /// Catalog total per sample: the rounded `Σμ` (integral by validation).
    draw_total: u64,
    nb_size: f64,
    n_boot: usize,
    bca: bool,
    arm: GenerativeArm,
    seed: u64,
    rank: u64,
}

/// One replicate of one cell: draw `counts` on the replicate's MC stream,
/// fit the production face, and tally coverage + the compound rule. Pure
/// function of `(seed, rank, rep, truth)` — the bitwise determinism unit.
fn run_calibration_rep(job: &CellJob, rep: usize, cancelled: &AtomicBool) -> Result<RepTally, MsError> {
    let mut rng = MsRng::from_stream(
        job.seed,
        StreamId {
            replicate: rep as u64,
            rank: job.rank,
            fold: 0,
        },
    );
    // The inner bootstrap's master seed: the first word of THIS replicate's
    // MC stream (module docs "Stream layout") — its boot streams then live
    // under the derived seed's own rank-0 band, disjoint from every other
    // (cell, replicate) unit.
    let boot_seed = rng.next_u64();

    // --- draw the catalog (the generative arm) --------------------------
    let mut counts = vec![0.0f64; job.m * job.n];
    match job.arm {
        GenerativeArm::Multinomial => {
            for j in 0..job.n {
                let draws = resample::multinomial(&mut rng, &job.mu, job.draw_total);
                for i in 0..job.m {
                    counts[i * job.n + j] = draws[i] as f64;
                }
            }
        }
        GenerativeArm::NegativeBinomial(size) => {
            // Row-major n×m draw buffer (resample.rs layout) transposed into
            // the row-major m×n counts this module shares with fit.rs.
            let flat = resample::nb_sample(&mut rng, &job.mu, size, job.n as u64);
            for j in 0..job.n {
                for i in 0..job.m {
                    counts[i * job.n + j] = flat[j * job.m + i] as f64;
                }
            }
        }
    }

    // --- production fit face + CI ---------------------------------------
    let point = fit::fit(
        &counts,
        job.sigs,
        job.m,
        job.n,
        job.k,
        FitMethod::LikelihoodBidirectional,
        job.nb_size,
        fit::FIT_EPS,
        fit::FIT_MAX_ITER,
        SIGFIT_ZERO_SHARE,
    )?;
    let mut no_poll = || {};
    let boots = fit::bootstrap(
        &counts,
        job.sigs,
        job.m,
        job.n,
        job.k,
        FitMethod::LikelihoodBidirectional,
        job.n_boot,
        job.nb_size,
        SIGFIT_ZERO_SHARE,
        boot_seed,
        1, // units are the grid's parallelism: the inner bootstrap is sequential
        job.bca,
        cancelled,
        &mut no_poll,
    )?;

    // --- coverage event + compound zeroing tally ------------------------
    // The coverage tallies cover the truth-supported signatures only
    // (estimand ② conditions on truth support); the confusion tally
    // covers the FULL dictionary — decoys (h* = 0) feed the FPR/TN
    // cells of the estimand-③ fourfold (memo §3).
    let n_supported = (0..job.k).filter(|&a| job.h_star[a] > 0.0).count();
    let mut tally = RepTally {
        coverage: Vec::with_capacity(n_supported * job.n),
        point_in_ci: Vec::with_capacity(n_supported * job.n),
        true_zero: 0,
        false_keep: 0,
        false_zero: 0,
        kept_covered: 0,
        kept_missed: 0,
    };
    for j in 0..job.n {
        // The sample's actual mutation total: the §3 share-scale divisor
        // (multinomial draws conserve it exactly; NB draws fluctuate).
        let total_j: f64 = (0..job.m).map(|i| counts[i * job.n + j]).sum();
        for a in 0..job.k {
            let idx = a * job.n + j;
            let truth = job.h_star[a];
            let (lo, hi) = match (&boots.bca, job.bca) {
                (Some(bca), true) => (bca.lower[idx], bca.upper[idx]),
                _ => (boots.ci_lower[idx], boots.ci_upper[idx]),
            };
            let covered = truth > 0.0 && lo <= truth && truth <= hi;
            if truth > 0.0 {
                tally.coverage.push(covered);
                let point_value = point.exposures[idx];
                tally
                    .point_in_ci
                    .push(point_value >= lo && point_value <= hi);
            }
            // Compound decision rule (memo §3, frozen): the existing
            // share-zeroing decision (the point fit's support column) OR
            // unstable boot support OR CI-lower share below the sigfit
            // anchor. A zero-total sample has no scale: the share clause
            // reads 0 (zero it) — the honest degenerate verdict.
            let share_lo = if total_j > 0.0 { lo / total_j } else { 0.0 };
            let final_zero = point.support[idx] == 0
                || boots.support_stability[idx] < CALIBRATION_STABILITY_FLOOR
                || share_lo < SIGFIT_ZERO_SHARE;
            match (truth > 0.0, final_zero) {
                (true, false) => {
                    if covered {
                        tally.kept_covered += 1;
                    } else {
                        tally.kept_missed += 1;
                    }
                }
                (true, true) => tally.false_zero += 1,
                (false, true) => tally.true_zero += 1,
                (false, false) => tally.false_keep += 1,
            }
        }
    }
    Ok(tally)
}

/// Structured validation of the truth setup shared by [`calibration_cell`]
/// and [`calibration_grid`] (contract 4: explicit, errors not panics —
/// before any replicate burns work).
#[allow(clippy::too_many_arguments)]
fn validate_truth(
    h_star: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    nb_size: f64,
    n_boot: usize,
    n_reps: usize,
) -> Result<(), MsError> {
    if m == 0 || n == 0 || k == 0 {
        return Err(MsError::new(
            "argument",
            "calibration needs at least one channel, one sample and one signature",
        )
        .with_i(m as i64)
        .with_j(k as i64));
    }
    if sigs.len() != m * k {
        return Err(MsError::new(
            "argument",
            "signatures storage must be m*k elements (row-major m x k)",
        )
        .with_i(sigs.len() as i64)
        .with_j((m * k) as i64));
    }
    for i in 0..m {
        for a in 0..k {
            let s = sigs[i * k + a];
            if !s.is_finite() {
                return Err(MsError::new("na", "signatures must be finite (no NaN/Inf)")
                    .with_i(i as i64 + 1)
                    .with_j(a as i64 + 1));
            }
            if s < 0.0 {
                return Err(
                    MsError::new("argument", "signatures must be non-negative")
                        .with_i(i as i64 + 1)
                        .with_j(a as i64 + 1),
                );
            }
        }
    }
    if h_star.len() != k {
        return Err(MsError::new(
            "argument",
            "truth spectrum must hold one exposure per signature (k elements)",
        )
        .with_i(h_star.len() as i64)
        .with_j(k as i64));
    }
    for (a, &h) in h_star.iter().enumerate() {
        if !h.is_finite() {
            return Err(MsError::new("na", "truth spectrum must be finite (no NaN/Inf)")
                .with_j(a as i64 + 1));
        }
        if h < 0.0 {
            return Err(MsError::new("argument", "truth spectrum must be non-negative")
                .with_j(a as i64 + 1));
        }
    }
    let total: f64 = h_star.iter().sum();
    if total <= 0.0 || !total.is_finite() {
        return Err(MsError::new(
            "argument",
            "truth spectrum must have a positive finite total (a zero spectrum has no catalog)",
        ));
    }
    if !nb_size.is_finite() || nb_size <= 0.0 {
        return Err(MsError::new(
            "argument",
            "nb_size must be finite and positive (the fit face's nbinom.size)",
        ));
    }
    if n_boot == 0 {
        return Err(MsError::new("argument", "n_boot must be >= 1"));
    }
    if n_reps == 0 {
        return Err(MsError::new("argument", "n_reps must be >= 1"));
    }
    Ok(())
}

/// Static per-cell configuration shared by the two pure drivers (a struct
/// freezes the eight-scalar set the cell/grid runners pass through).
struct CellConfig {
    m: usize,
    n: usize,
    k: usize,
    nb_size: f64,
    n_boot: usize,
    bca: bool,
    arm: GenerativeArm,
    seed: u64,
}

/// Build the per-cell draw setup: spectrum (frozen convention), channel
/// expectation, and the primitive-level draw validation (weights / NB
/// regime) so workers never hit the panic contract.
fn build_cell_job<'a>(
    h_star: Vec<f64>,
    sigs: &'a [f64],
    cfg: &CellConfig,
    rank: u64,
) -> Result<CellJob<'a>, MsError> {
    let m = cfg.m;
    let k = cfg.k;
    let mut mu = vec![0.0f64; m];
    for i in 0..m {
        let acc: f64 = (0..k).map(|a| sigs[i * k + a] * h_star[a]).sum();
        mu[i] = acc;
    }
    let total: f64 = mu.iter().sum();
    // Integral draw total (truth spectra are integer-scaled by
    // construction; the tolerance absorbs last-ulp spectrum remainders).
    if !total.is_finite() || total < 0.0 || (total - total.round()).abs() > 1e-6 {
        return Err(MsError::new(
            "argument",
            "the channel expectation total must be a near-integer catalog size",
        )
        .with_i(total as i64));
    }
    let draw_total = total.round() as u64;
    resample::validate_weights(&mu, draw_total)?;
    if let GenerativeArm::NegativeBinomial(size) = cfg.arm {
        resample::validate_nb_sample(&mu, size, cfg.n as u64)?;
    }
    Ok(CellJob {
        sigs,
        m,
        n: cfg.n,
        k,
        h_star,
        mu,
        draw_total,
        nb_size: cfg.nb_size,
        n_boot: cfg.n_boot,
        bca: cfg.bca,
        arm: cfg.arm,
        seed: cfg.seed,
        rank,
    })
}

/// Reduce replicates (fixed order — no order-sensitive float accumulation:
/// counts then one division each) into the aggregate cell statistics.
fn aggregate_cell(reps: &[RepTally], n_reps: usize) -> CellAggregate {
    let mut covered = 0u64;
    let mut tallies = 0u64;
    let mut agg = CellAggregate {
        mean_coverage: 0.0,
        se: 0.0,
        n_reps,
        true_zero: 0,
        false_keep: 0,
        false_zero: 0,
        kept_covered: 0,
        kept_missed: 0,
    };
    for rep in reps {
        for &b in &rep.coverage {
            tallies += 1;
            if b {
                covered += 1;
            }
        }
        agg.true_zero += rep.true_zero;
        agg.false_keep += rep.false_keep;
        agg.false_zero += rep.false_zero;
        agg.kept_covered += rep.kept_covered;
        agg.kept_missed += rep.kept_missed;
    }
    let p = covered as f64 / tallies as f64;
    agg.mean_coverage = p;
    agg.se = (p * (1.0 - p) / tallies as f64).sqrt();
    agg
}

/// Run one calibration cell (module docs "What one grid cell measures"):
/// `n_reps` replicates, each a full draw → production fit → CI → coverage
/// cycle. Deterministic in `(h_star, sigs, m, n, k, nb_size, n_boot, bca,
/// arm, n_reps, seed)`; `n_threads` schedules whole replicate units only.
///
/// Crate-internal face (see [`CellResult`]): the production entry is the
/// grid FFI; the single-cell runner serves the bench's boundary-share
/// recheck batches and this test suite.
#[allow(dead_code)]
#[allow(clippy::too_many_arguments)]
pub fn calibration_cell(
    h_star: &[f64],
    sigs: &[f64],
    m: usize,
    n: usize,
    k: usize,
    nb_size: f64,
    n_boot: usize,
    bca: bool,
    arm: GenerativeArm,
    n_reps: usize,
    seed: u64,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<CellResult, MsError> {
    validate_truth(h_star, sigs, m, n, k, nb_size, n_boot, n_reps)?;
    let cfg = CellConfig {
        m,
        n,
        k,
        nb_size,
        n_boot,
        bca,
        arm,
        seed,
    };
    // Single-cell stream layout: cell id 1 of a 1-cell grid (module docs).
    let rank = stream_rank(1, 1, arm);
    let job = build_cell_job(h_star.to_vec(), sigs, &cfg, rank)?;
    let per = run_units_in_chunks(
        n_reps,
        n_threads,
        cancelled,
        check_user_interrupt,
        |rep| run_calibration_rep(&job, rep, cancelled),
    )?;
    let mut coverage = Vec::new();
    let mut point_in_ci = Vec::new();
    for tally in &per {
        coverage.extend_from_slice(&tally.coverage);
        point_in_ci.extend_from_slice(&tally.point_in_ci);
    }
    let agg = aggregate_cell(&per, n_reps);
    let point_in: usize = point_in_ci.iter().filter(|&&b| b).count();
    Ok(CellResult {
        coverage_frac: agg.mean_coverage,
        point_in_ci_frac: point_in as f64 / point_in_ci.len() as f64,
        coverage_per_cell: coverage,
        point_in_ci,
        true_zero: agg.true_zero,
        false_keep: agg.false_keep,
        false_zero: agg.false_zero,
        kept_covered: agg.kept_covered,
        kept_missed: agg.kept_missed,
    })
}

/// Run the `n_grid × shares` calibration grid over ONE truth dictionary
/// (module docs "Grid layout"). Cell `c = n_idx · shares.len() + share_idx`
/// gets the frozen spectrum [`cell_spectrum`]`(`n_grid[n_idx]`,
/// shares[share_idx], k)`; results return in the same n_grid-major order.
/// Deterministic in the inputs and `seed`; `threads ∈ {1, N}` bit-identical.
#[allow(clippy::too_many_arguments)]
pub fn calibration_grid(
    sigs: &[f64],
    n_grid: &[usize],
    shares: &[f64],
    m: usize,
    n: usize,
    k: usize,
    nb_size: f64,
    n_boot: usize,
    bca: bool,
    arm: GenerativeArm,
    n_reps: usize,
    seed: u64,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<Vec<CellAggregate>, MsError> {
    if n_grid.is_empty() {
        return Err(MsError::new("argument", "n_grid must contain at least one catalog size"));
    }
    if shares.is_empty() {
        return Err(MsError::new("argument", "shares must contain at least one truth share"));
    }
    for (pos, &sz) in n_grid.iter().enumerate() {
        if sz == 0 {
            return Err(MsError::new(
                "argument",
                "every n_grid entry must be >= 1 (a zero-mutation catalog has no likelihood)",
            )
            .with_i(pos as i64 + 1));
        }
    }
    for (pos, &s) in shares.iter().enumerate() {
        if !s.is_finite() {
            return Err(MsError::new("na", "shares must be finite (no NaN/Inf)")
                .with_i(pos as i64 + 1));
        }
        if !(0.0..=1.0).contains(&s) {
            return Err(MsError::new("argument", "every share must lie in [0, 1]")
                .with_i(pos as i64 + 1));
        }
    }
    validate_truth(
        &cell_spectrum(n_grid[0] as f64, shares[0], k),
        sigs,
        m,
        n,
        k,
        nb_size,
        n_boot,
        n_reps,
    )?;

    let n_cells = n_grid.len() * shares.len();
    let cfg = CellConfig {
        m,
        n,
        k,
        nb_size,
        n_boot,
        bca,
        arm,
        seed,
    };
    let mut jobs: Vec<CellJob> = Vec::with_capacity(n_cells);
    for (c, &sz) in n_grid.iter().enumerate() {
        for (s_pos, &share) in shares.iter().enumerate() {
            let spectrum = cell_spectrum(sz as f64, share, k);
            let rank = stream_rank(c * shares.len() + s_pos + 1, n_cells, arm);
            jobs.push(build_cell_job(spectrum, sigs, &cfg, rank)?);
        }
    }

    let units = n_cells * n_reps;
    let per = run_units_in_chunks(units, n_threads, cancelled, check_user_interrupt, |u| {
        let c = u / n_reps;
        let rep = u % n_reps;
        run_calibration_rep(&jobs[c], rep, cancelled)
    })?;

    Ok((0..n_cells)
        .map(|c| aggregate_cell(&per[c * n_reps..(c + 1) * n_reps], n_reps))
        .collect())
}

/// Window verdict over the grid aggregates: membership in the inclusive
/// `[window.0, window.1]` band per cell (the PI-ruled default is
/// [`CALIBRATION_WINDOW`]), the overall AND, and the ascending 0-based
/// failing indices. Errors on an empty grid or a malformed window
/// (non-finite, outside [0, 1], or inverted).
pub fn calibration_verdict(
    grid_results: &[CellAggregate],
    window: (f64, f64),
) -> Result<Verdict, MsError> {
    if grid_results.is_empty() {
        return Err(MsError::new(
            "argument",
            "the verdict needs at least one grid cell",
        ));
    }
    let (lo, hi) = window;
    if !lo.is_finite() || !hi.is_finite() {
        return Err(MsError::new("na", "window bounds must be finite (no NaN/Inf)"));
    }
    if !(0.0..=1.0).contains(&lo) || !(0.0..=1.0).contains(&hi) {
        return Err(MsError::new(
            "argument",
            "window bounds must lie in [0, 1] (they are coverage levels)",
        ));
    }
    if lo > hi {
        return Err(MsError::new(
            "argument",
            "window lower bound must not exceed the upper bound",
        ));
    }
    let per_cell_in: Vec<bool> = grid_results
        .iter()
        .map(|c| lo <= c.mean_coverage && c.mean_coverage <= hi)
        .collect();
    let failing_cells: Vec<usize> = per_cell_in
        .iter()
        .enumerate()
        .filter(|(_, &in_window)| !in_window)
        .map(|(i, _)| i)
        .collect();
    Ok(Verdict {
        all_in_window: failing_cells.is_empty(),
        per_cell_in,
        failing_cells,
    })
}

/// Chunked parallel driver over independent (cell × replicate) units —
/// copied locally from `fit.rs::run_boots_in_chunks` (the `replicates.rs`
/// scheduling skeleton; that driver is module-private and the crates' file
/// discipline keeps each unit self-contained): units are scheduled in
/// chunks (≈4 per worker, capped), the main thread polls the interrupt hook
/// between chunks, each chunk runs its units in parallel on the per-call
/// pool, workers see ONLY the `cancelled` flag, and chunks are gathered in
/// chunk-index order (pure index placement — no order-sensitive
/// floating-point reduction anywhere, so `threads ∈ {1, N}` give
/// bit-identical output).
fn run_units_in_chunks<T, F>(
    units: usize,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
    unit: F,
) -> Result<Vec<T>, MsError>
where
    T: Send,
    F: Fn(usize) -> Result<T, MsError> + Sync,
{
    let pool = build_call_pool(n_threads)?;
    let target_chunks = n_threads.clamp(1, 16) * 4;
    let chunk_len = ((units + target_chunks - 1) / target_chunks).max(1);
    let n_chunks = (units + chunk_len - 1) / chunk_len;

    let mut per_chunk: Vec<(usize, Vec<T>)> = Vec::with_capacity(n_chunks);
    for c in 0..n_chunks {
        if cancelled.load(Ordering::Relaxed) {
            return Err(MsError::new(
                "interrupted",
                format!(
                    "call interrupted before chunk {}; no partial results are returned",
                    c + 1
                ),
            )
            .with_i((c + 1) as i64));
        }
        // Main-thread boundary poll (under R: R_CheckUserInterrupt).
        check_user_interrupt();
        let start = c * chunk_len;
        let end = (start + chunk_len).min(units);
        let chunk: Vec<T> = pool.install(|| {
            (start..end)
                .into_par_iter()
                .map(|u| {
                    if cancelled.load(Ordering::Relaxed) {
                        return Err(MsError::new(
                            "interrupted",
                            format!("worker observed cancellation at unit {}", u + 1),
                        )
                        .with_i((u + 1) as i64));
                    }
                    unit(u)
                })
                .collect::<Result<Vec<T>, MsError>>()
        })?;
        per_chunk.push((c, chunk));
    }

    per_chunk.sort_unstable_by_key(|(c, _)| *c);
    let mut out = Vec::with_capacity(units);
    for (_, mut vals) in per_chunk {
        out.append(&mut vals);
    }
    debug_assert_eq!(out.len(), units);
    Ok(out)
}

// ======================================================================
// Tests (authored with the implementation): perfect-model coverage,
// M=500 percentile window, BCa arm comparison, grid determinism +
// thread invariance, compound zeroing tallies at the boundary share,
// NB arm smoke + Poisson limit, cell/grid consistency, structured
// error paths, verdict membership.
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;

    const M: usize = 8;
    const K: usize = 2;

    fn no_poll() {}

    fn fresh() -> AtomicBool {
        AtomicBool::new(false)
    }

    /// Truth dictionary: a delta (peaked) target on channel 0 plus a medium
    /// partner spread over channels 1..8. Columns sum to 1; the pair is
    /// well-conditioned (G is far from singular), so the bidirectional fit
    /// keeps both signatures at every tested share.
    fn truth_sigs() -> Vec<f64> {
        let mut s = vec![0.0f64; M * K];
        s[0] = 1.0; // signature 0: delta on channel 0
        let partner = [0.0f64, 0.30, 0.25, 0.15, 0.10, 0.08, 0.07, 0.05];
        for i in 0..M {
            s[i * K + 1] = partner[i];
        }
        s
    }

    fn spectrum(n_total: f64, share: f64) -> Vec<f64> {
        cell_spectrum(n_total, share, K)
    }

    #[allow(clippy::too_many_arguments)]
    fn run_cell(
        h_star: &[f64],
        n_threads: usize,
        seed: u64,
        bca: bool,
        arm: GenerativeArm,
        n_reps: usize,
        n_boot: usize,
    ) -> CellResult {
        let cancelled = fresh();
        calibration_cell(
            h_star,
            &truth_sigs(),
            M,
            1,
            K,
            8.0,
            n_boot,
            bca,
            arm,
            n_reps,
            seed,
            n_threads,
            &cancelled,
            &mut no_poll,
        )
        .unwrap()
    }

    #[allow(clippy::too_many_arguments)]
    fn run_grid(
        n_grid: &[usize],
        shares: &[f64],
        n_threads: usize,
        seed: u64,
        bca: bool,
        arm: GenerativeArm,
        n_reps: usize,
        n_boot: usize,
    ) -> Vec<CellAggregate> {
        let cancelled = fresh();
        calibration_grid(
            &truth_sigs(),
            n_grid,
            shares,
            M,
            1,
            K,
            8.0,
            n_boot,
            bca,
            arm,
            n_reps,
            seed,
            n_threads,
            &cancelled,
            &mut no_poll,
        )
        .unwrap()
    }

    // ------------------------------------------------------------------
    // Perfect model: an exactly-fittable truth gives near-full coverage
    // (wide intervals at this N) and no false-zero decisions.
    // ------------------------------------------------------------------
    #[test]
    fn perfect_model_cell_covers_the_truth() {
        let h = spectrum(1000.0, 0.25);
        let out = run_cell(&h, 2, 2026, false, GenerativeArm::Multinomial, 40, 150);
        assert_eq!(out.coverage_per_cell.len(), 40 * 2); // 2 supported signatures
        assert!(
            out.coverage_frac >= 0.90,
            "coverage {}",
            out.coverage_frac
        );
        assert!(
            out.point_in_ci_frac >= 0.95,
            "point-in-CI {}",
            out.point_in_ci_frac
        );
        assert_eq!(out.false_zero, 0);
        assert_eq!(out.false_keep, 0);
        assert_eq!(out.true_zero, 0);
        assert_eq!(
            out.kept_covered + out.kept_missed,
            (40 * 2) as u64
        );
    }

    // ------------------------------------------------------------------
    // M = 500 reduced protocol: the multinomial main arm lands inside the
    // PI window on interior cells (shares clear of the 0.01 zeroing
    // threshold; mutation burdens where percentile is first-order exact).
    // ------------------------------------------------------------------
    #[test]
    fn percentile_arm_m500_lands_in_window() {
        let agg = run_grid(
            &[1000],
            &[0.10, 0.25],
            4,
            2026,
            false,
            GenerativeArm::Multinomial,
            500,
            200,
        );
        assert_eq!(agg.len(), 2);
        let verdict = calibration_verdict(&agg, CALIBRATION_WINDOW).unwrap();
        for (c, a) in agg.iter().enumerate() {
            assert!(
                (0.930..=0.970).contains(&a.mean_coverage),
                "cell {c} coverage {} (se {})",
                a.mean_coverage,
                a.se
            );
            assert_eq!(a.n_reps, 500);
        }
        assert!(verdict.all_in_window, "failing {:?}", verdict.failing_cells);
    }

    // ------------------------------------------------------------------
    // BCa arm comparison: the same truth under bca = true stays near
    // nominal and close to the percentile arm (the corrected levels move
    // the bounds, they do not destabilise the coverage).
    // ------------------------------------------------------------------
    #[test]
    fn bca_arm_tracks_the_percentile_arm() {
        let shares = [0.10, 0.25];
        let pct = run_grid(&[1000], &shares, 4, 2026, false, GenerativeArm::Multinomial, 120, 200);
        let bca = run_grid(&[1000], &shares, 4, 2026, true, GenerativeArm::Multinomial, 120, 200);
        for (c, (p, b)) in pct.iter().zip(bca.iter()).enumerate() {
            assert!(
                (0.88..=1.0).contains(&b.mean_coverage),
                "bca cell {c} coverage {}",
                b.mean_coverage
            );
            assert!(
                (p.mean_coverage - b.mean_coverage).abs() <= 0.08,
                "cell {c}: pct {} vs bca {}",
                p.mean_coverage,
                b.mean_coverage
            );
        }
    }

    // ------------------------------------------------------------------
    // Grid determinism: seed → bitwise; threads ∈ {1, 3} identical; a
    // different seed moves at least one cell.
    // ------------------------------------------------------------------
    #[test]
    fn grid_is_deterministic_and_thread_invariant() {
        let one = run_grid(&[100, 1000], &[0.1, 0.5], 1, 7, false, GenerativeArm::Multinomial, 6, 60);
        let three = run_grid(&[100, 1000], &[0.1, 0.5], 3, 7, false, GenerativeArm::Multinomial, 6, 60);
        assert_eq!(one, three);
        let again = run_grid(&[100, 1000], &[0.1, 0.5], 1, 7, false, GenerativeArm::Multinomial, 6, 60);
        assert_eq!(one, again);
        let other = run_grid(&[100, 1000], &[0.1, 0.5], 1, 8, false, GenerativeArm::Multinomial, 6, 60);
        assert!(
            one.iter().zip(other.iter()).any(|(a, b)| a != b),
            "a different seed must move the grid"
        );
    }

    // ------------------------------------------------------------------
    // NB stress arm: runs, deterministic, and reproduces the memo's two
    // documented stress mechanisms (§2.3): (a) per-channel NB sampling
    // does NOT conserve the catalog total, so even the exact Poisson
    // limit undercovers relative to the multinomial arm (a realized-low
    // total shifts the whole point fit down-scale while the within-sample
    // bootstrap CI is blind to total noise — both signatures miss high
    // together); (b) at the κ = 8 anchor the channel overdispersion
    // deepens the undercoverage further — coverage is monotone in κ.
    // The arms are reported separately and never mixed into one claim.
    // ------------------------------------------------------------------
    #[test]
    fn nb_arm_runs_and_undercoverage_is_monotone_in_kappa() {
        let h = spectrum(1000.0, 0.25);
        let nb = run_cell(&h, 2, 11, false, GenerativeArm::NegativeBinomial(8.0), 30, 100);
        let nb_again = run_cell(&h, 2, 11, false, GenerativeArm::NegativeBinomial(8.0), 30, 100);
        assert_eq!(nb, nb_again);
        let pois = run_cell(&h, 2, 11, false, GenerativeArm::NegativeBinomial(f64::INFINITY), 30, 100);
        let mn = run_cell(&h, 2, 11, false, GenerativeArm::Multinomial, 30, 100);
        assert!(
            (0.4..=0.9).contains(&pois.coverage_frac),
            "poisson-limit arm coverage {} (total-fluctuation level error)",
            pois.coverage_frac
        );
        assert!(
            nb.coverage_frac < pois.coverage_frac,
            "κ = 8 must undercover its own Poisson limit: {} vs {}",
            nb.coverage_frac,
            pois.coverage_frac
        );
        assert!(
            pois.coverage_frac < mn.coverage_frac,
            "Poisson-limit arm must sit below the total-conserving multinomial arm: {} vs {}",
            pois.coverage_frac,
            mn.coverage_frac
        );
    }

    // ------------------------------------------------------------------
    // Compound zeroing tally at the 0.01 boundary: a 0.005 target share is
    // below the sigfit anchor → the decision rule zeroes it on most
    // replicates (false-zero direction) and its coverage collapses; a
    // share-0 decoy target is correctly zeroed (true-zero) with a small
    // false-keep rate.
    // ------------------------------------------------------------------
    #[test]
    fn compound_zeroing_tallies_the_boundary_share() {
        let reps = 40;
        let low = run_cell(&spectrum(2000.0, 0.005), 2, 5, false, GenerativeArm::Multinomial, reps, 150);
        assert_eq!(low.true_zero, 0);
        assert_eq!(low.false_keep, 0);
        assert!(
            low.false_zero as f64 >= 0.9 * (reps as f64),
            "false_zero {} of {}",
            low.false_zero,
            reps
        );
        assert!(low.coverage_frac <= 0.15, "coverage {}", low.coverage_frac);

        let decoy = run_cell(&spectrum(2000.0, 0.0), 2, 5, false, GenerativeArm::Multinomial, reps, 150);
        // Target share 0 → the supported set is the partner only; the decoy
        // target feeds the confusion tally.
        assert_eq!(decoy.coverage_per_cell.len(), reps);
        assert!(
            decoy.true_zero as f64 >= 0.9 * (reps as f64),
            "true_zero {} of {}",
            decoy.true_zero,
            reps
        );
        assert!(
            decoy.false_keep as f64 <= 0.1 * (reps as f64),
            "false_keep {} of {}",
            decoy.false_keep,
            reps
        );
    }

    // ------------------------------------------------------------------
    // Cell/grid consistency: a 1×1 grid at cell id 1 is the same
    // experiment as calibration_cell — bitwise-equal aggregates.
    // ------------------------------------------------------------------
    #[test]
    fn single_cell_grid_matches_calibration_cell() {
        let h = spectrum(800.0, 0.2);
        let cell = run_cell(&h, 1, 99, false, GenerativeArm::Multinomial, 12, 80);
        let grid = run_grid(&[800], &[0.2], 1, 99, false, GenerativeArm::Multinomial, 12, 80);
        assert_eq!(grid.len(), 1);
        assert!((grid[0].mean_coverage - cell.coverage_frac).abs() < 1e-12);
        assert_eq!(grid[0].true_zero, cell.true_zero);
        assert_eq!(grid[0].kept_covered, cell.kept_covered);
        assert_eq!(grid[0].kept_missed, cell.kept_missed);
        assert_eq!(grid[0].false_zero, cell.false_zero);
    }

    // ------------------------------------------------------------------
    // Verdict membership: inclusive bounds, failing index list, overall
    // AND; malformed windows and empty grids are structured errors.
    // ------------------------------------------------------------------
    #[test]
    fn verdict_membership_failing_cells_and_errors() {
        let mk = |p: f64| CellAggregate {
            mean_coverage: p,
            se: 0.01,
            n_reps: 100,
            true_zero: 0,
            false_keep: 0,
            false_zero: 0,
            kept_covered: 94,
            kept_missed: 6,
        };
        let grid = vec![mk(0.94), mk(0.970), mk(0.929), mk(0.971), mk(0.930)];
        let v = calibration_verdict(&grid, CALIBRATION_WINDOW).unwrap();
        assert_eq!(
            v.per_cell_in,
            vec![true, true, false, false, true],
            "inclusive bounds at both ends"
        );
        assert_eq!(v.failing_cells, vec![2, 3]);
        assert!(!v.all_in_window);

        let ok = calibration_verdict(&grid[..2], CALIBRATION_WINDOW).unwrap();
        assert!(ok.all_in_window);
        assert!(ok.failing_cells.is_empty());

        let cancelled = fresh();
        let empty: Vec<CellAggregate> = Vec::new();
        assert_eq!(
            calibration_verdict(&empty, CALIBRATION_WINDOW).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            calibration_verdict(&grid, (0.97, 0.93)).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            calibration_verdict(&grid, (-0.1, 0.97)).unwrap_err().topic,
            "argument"
        );
        assert_eq!(
            calibration_verdict(&grid, (0.93, f64::NAN)).unwrap_err().topic,
            "na"
        );
        // Error paths of the drivers: empty axes, bad shares, bad scalars.
        let sigs = truth_sigs();
        assert_eq!(
            calibration_grid(&sigs, &[], &[0.1], M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs, &[100], &[], M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs, &[100], &[1.5], M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs, &[0], &[0.1], M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs, &[100], &[0.1], M, 1, K, 8.0, 0, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs, &[100], &[0.1], M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 0, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs[..sigs.len() - 1], &[100], &[0.1], M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        assert_eq!(
            calibration_grid(&sigs, &[100], &[0.1], M, 1, K, f64::NAN, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        // A zero truth spectrum has no catalog.
        assert_eq!(
            calibration_cell(&[0.0, 0.0], &sigs, M, 1, K, 8.0, 10, false, GenerativeArm::Multinomial, 2, 1, 1, &cancelled, &mut no_poll)
                .unwrap_err()
                .topic,
            "argument"
        );
        // Illegal arm names.
        assert_eq!(GenerativeArm::parse("wald").unwrap_err().topic, "argument");
        assert_eq!(GenerativeArm::parse("nb").unwrap_err().topic, "argument");
        assert_eq!(GenerativeArm::parse("nb:-1").unwrap_err().topic, "argument");
        assert_eq!(GenerativeArm::parse("nb:x").unwrap_err().topic, "argument");
    }

    // ------------------------------------------------------------------
    // Spectrum convention: exact total, target carries the swept share,
    // remainder split exact on the last entry; share 1 collapses onto the
    // target (the others become decoys).
    // ------------------------------------------------------------------
    #[test]
    fn cell_spectrum_convention_is_exact() {
        let h = cell_spectrum(100_000.0, 0.005, 4);
        assert!((h.iter().sum::<f64>() - 100_000.0).abs() <= 1e-9);
        assert_eq!(h[0], 500.0);
        assert!(h[1] > 0.0 && h[2] > 0.0);
        assert!((h[1] - h[2]).abs() < 1e-9);
        let one = cell_spectrum(1000.0, 0.3, 1);
        assert_eq!(one, vec![1000.0]);
        let collapsed = cell_spectrum(1000.0, 1.0, 3);
        assert_eq!(collapsed[0], 1000.0);
        assert_eq!(collapsed[1], 0.0);
        assert_eq!(collapsed[2], 0.0);
        // Arm name round trip.
        assert_eq!(GenerativeArm::parse("multinomial").unwrap().as_str(), "multinomial");
        assert_eq!(GenerativeArm::parse("poisson").unwrap().as_str(), "poisson");
        assert_eq!(
            GenerativeArm::parse("nb:8").unwrap(),
            GenerativeArm::NegativeBinomial(8.0)
        );
        assert_eq!(GenerativeArm::NegativeBinomial(8.0).as_str(), "nb");
    }

    // ------------------------------------------------------------------
    // Interrupt protocol: a pre-set flag fails the whole call before any
    // output; a trip at the first boundary poll fails at the next boundary
    // with the worker-side topic (contract 5: no partial results).
    // ------------------------------------------------------------------
    #[test]
    fn interrupt_flag_fails_the_whole_call() {
        let h = spectrum(500.0, 0.25);
        let cancelled = AtomicBool::new(true);
        let err = calibration_cell(
            &h,
            &truth_sigs(),
            M,
            1,
            K,
            8.0,
            20,
            false,
            GenerativeArm::Multinomial,
            4,
            1,
            1,
            &cancelled,
            &mut no_poll,
        )
        .unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));

        let cancelled = AtomicBool::new(false);
        let mut polls = 0usize;
        let err = calibration_cell(
            &h,
            &truth_sigs(),
            M,
            1,
            K,
            8.0,
            20,
            false,
            GenerativeArm::Multinomial,
            4,
            1,
            1,
            &cancelled,
            &mut || {
                polls += 1;
                if polls == 1 {
                    cancelled.store(true, Ordering::Relaxed);
                }
            },
        )
        .unwrap_err();
        assert_eq!(polls, 1);
        assert_eq!(err.topic, "interrupted");
        assert!(err.to_string().contains("worker observed"));
    }
}
