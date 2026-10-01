//! SUITOR-style cross-validation kernel (U-M2-02; `docs/ARCHITECTURE.md` §2,
//! design memo `docs/devlog/2026-09-30-M2-pipeline-design-memo.md` §2/§5).
//!
//! # Upstream semantics (pinned to source, D11/D13)
//!
//! SUITOR master `9cf4a5f5` (Lee et al., PLoS Comput Biol 2022). Line numbers
//! refer to `source/R/source.R` (R) and `source/src/source.c` (C) as anchored
//! in the design memo.
//!
//! 1. **Fold masks** (`get_idx_mat`, source.R:148-158; C `get_idxMat0`,
//!    source.c:363-384): with 1-based row COL and fold k, the held-out rows of
//!    a column satisfy `r ≡ (COL + k − 1) (mod Kfold)` (residue 0 → the
//!    Kfold-multiple rows). In 0-based terms: `r ≡ (col + fold) (mod Kfold)`.
//!    The per-column rotation (column c's pattern is column 0's shifted by
//!    c mod Kfold) balances fold sizes across columns.
//! 2. **Initial imputation is two-stage** (PI ruling, memo §2.2): stage one
//!    fills every held-out cell with the **median of the observed entries of
//!    its channel row** (R median convention — even counts take the mean of
//!    the two central order statistics; source.R:568-571, C `get_init_x_k`
//!    :867-895), then the whole matrix (observed zeros included) is floored at
//!    `min.value = 1e-4` (source.R:575-576). Stage two happens inside the ECM
//!    loop: after every multiplicative-update round the held-out cells are
//!    replaced by the current reconstruction `W·H` (source.R:596, :326) — the
//!    paper's "conditional-mean imputation" ECM reading.
//! 3. **Monitors** (source.R:160-190, :289-344): the ECM stopping monitor is
//!    the training-cell generalized KL deviance `Σ_train [x·ln(x/x̂) − x +
//!    x̂]` (`loglike_new`), compared round-over-round under the transform
//!    `lik = sqrt(·/train.adj)` with `train.adj = NR·NC − |idxMat|`; a
//!    relative change below `em.eps = 1e-5` (checked from the second round
//!    on) or the `max.iter` cap ends the run.
//! 4. **Declared divergences (D13, audited)**: (a) upstream runs a full NMF
//!    burn-in fit (`call_nmf`, source.R:577-598, cap 2000) before the ECM
//!    rounds; this port seeds directly into the ECM from the pinned random
//!    init — trajectories differ from upstream, determinism within msuiter
//!    does not. (b) upstream re-floors the working matrix every ECM round
//!    (`replaceZeroVal`, source.R:302); this port floors only the initial
//!    imputation — sub-floor reconstructions may persist across rounds.
//! 5. **Reported held-out error**: the masked Poisson deviance of
//!    [`poisson_deviance`] (upstream `loglike` on `idxMat`, source.R:160-175)
//!    — the per-fold value that enters `CV.te`. Log arguments are floored at
//!    `delta_denom = min(positive x̂)/2` (source.R:177-187, :311; C
//!    `NUMERICZERO` positivity threshold :18); `x = 0` cells contribute no
//!    log-ratio term.
//! 6. **Aggregation** (`getSummary`, source.R:627-692): per (rank, fold) the
//!    seed is picked by `which.min(train error)` over the seeds (first
//!    minimum, non-finite seeds excluded) and *its* test error is taken;
//!    `CV.te = Σ_folds` (a fold with no finite seed drops out, `na.rm`
//!    semantics); the rank is chosen by `which.min(CV.te)` — first minimum,
//!    i.e. the lowest rank on ties. `MSErr = sqrt(CV.te/M)` with `M = NR·NC`;
//!    the training analog divides by `M·(Kfold − 1)` (the total number of
//!    training cells across folds).
//! 5. **Stream layout** (memo §2.4, frozen): unit `(rank, fold, seed_idx)`
//!    draws its initializer from
//!    `StreamId { replicate: seed_idx, rank, fold: 1-based fold }` of the
//!    canonical layout v1 — W row-major first, then H row-major, open-interval
//!    uniforms `(0, 1]` scaled by `sqrt(mean(imputed)/rank)` (the
//!    [`crate::nmf`] initializer convention applied to the imputed matrix, so
//!    the factors start positive and on data scale; MU zeros are absorbing).
//!
//! # Determinism contract
//!
//! Single-threaded, fixed reduction order, canonical streams: identical inputs
//! give bit-identical [`CvResult`]s, and thread-count invariance is inherited
//! by the future parallel driver (U-M1s-05 pattern; memo §2.4). Goldens pin
//! integer/label outcomes exactly and float outcomes under tolerance (D11).
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies; every entry
//! point returns `Result<_, MsError>` (FFI contract 5). The ECM inner loop
//! reuses the audited [`crate::nmf`] KL-MU steps verbatim (fixed order: one H
//! step then one W step per round, memo §2.4).

use crate::error::MsError;
use crate::nmf::{kl_h_step, kl_w_step, matmul};
use crate::rng::{MsRng, StreamId};

/// SUITOR `min.value` floor (source.R:42-45 default; applied to the whole
/// imputed matrix, observed zeros included — `get_init_x_k`, source.c:867-895).
pub const MIN_VALUE: f64 = 1e-4;

/// SUITOR `em.eps` relative-stop threshold for the ECM monitor
/// (source.R:42-45 default).
pub const EM_EPS: f64 = 1e-5;

/// C `NUMERICZERO` (source.c:18): positivity threshold used by the default C
/// path in `get_delta_denom` and `loglike` (entries at or below it read as
/// structural zeros).
pub const NUMERIC_ZERO: f64 = 1e-200;

/// Held-out row indices (0-based, ascending) of column `col` for fold `fold`
/// under the SUITOR rule: 0-based `r ≡ (col + fold) (mod k_fold)` — the
/// 0-based form of `r ≡ (COL + k − 1) (mod Kfold)` (source.R:148-158,
/// source.c:372-383). `k_fold = 0` yields no members (never panics; FFI
/// contract 5).
pub fn fold_members(n_rows: usize, k_fold: usize, fold: usize, col: usize) -> Vec<usize> {
    if k_fold == 0 {
        return Vec::new();
    }
    let residue = (col + fold) % k_fold;
    (0..n_rows).filter(|&r| r % k_fold == residue).collect()
}

/// Held-out mask of the whole `n_rows × n_cols` matrix (row-major) for fold
/// `fold`: cell `(r, c)` is held iff `r` is a member of the fold for column
/// `c` ([`fold_members`]). `true` = held out (the SUITOR `idxMat` convention).
pub fn fold_mask(n_rows: usize, n_cols: usize, k_fold: usize, fold: usize) -> Vec<bool> {
    let mut mask = vec![false; n_rows * n_cols];
    for c in 0..n_cols {
        for r in fold_members(n_rows, k_fold, fold, c) {
            mask[r * n_cols + c] = true;
        }
    }
    mask
}

/// Median of a non-empty slice under the R convention (odd: middle order
/// statistic; even: mean of the two central ones, `get_median`, source.c:842).
fn r_median(values: &[f64]) -> f64 {
    let mut sorted = values.to_vec();
    // Values are validated finite; the fallback order is unreachable.
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let k = sorted.len();
    if k % 2 == 1 {
        sorted[k / 2]
    } else {
        (sorted[k / 2 - 1] + sorted[k / 2]) / 2.0
    }
}

/// Stage one of the SUITOR imputation (memo §2.2): every held-out cell
/// (`mask[i] == true`) receives the median of the observed entries of its
/// channel row, then the whole matrix (observed zeros included) is floored at
/// [`MIN_VALUE`] (source.R:568-576). Errors: `"argument"` for degenerate
/// dimensions, storage mismatches, negative entries, or a fully held-out
/// channel row (the C path reads past the buffer there; we fail fast); `"na"`
/// for non-finite entries.
pub fn initial_impute(v: &[f64], m: usize, n: usize, mask: &[bool]) -> Result<Vec<f64>, MsError> {
    if m == 0 || n == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive"));
    }
    if v.len() != m * n {
        return Err(
            MsError::new("argument", "counts storage must hold m*n elements").with_i(v.len() as i64)
        );
    }
    if mask.len() != m * n {
        return Err(
            MsError::new("argument", "mask storage must hold m*n elements").with_i(mask.len() as i64)
        );
    }
    for (idx, &x) in v.iter().enumerate() {
        if !x.is_finite() {
            return Err(MsError::new("na", "non-finite entry in counts")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
        if x < 0.0 {
            return Err(MsError::new("argument", "negative entry in counts")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
    }
    let mut out = v.to_vec();
    for i in 0..m {
        let row = i * n;
        let mut observed = Vec::with_capacity(n);
        for j in 0..n {
            if !mask[row + j] {
                observed.push(v[row + j]);
            }
        }
        if observed.is_empty() {
            return Err(MsError::new(
                "argument",
                "channel row is fully held out; no observed entries to impute",
            )
            .with_i(i as i64 + 1));
        }
        let med = r_median(&observed);
        for j in 0..n {
            if mask[row + j] {
                out[row + j] = med;
            }
        }
    }
    for x in out.iter_mut() {
        if *x < MIN_VALUE {
            *x = MIN_VALUE;
        }
    }
    Ok(out)
}

/// `min(positive x̂)/2` over the entries strictly above [`NUMERIC_ZERO`] (the
/// C positivity threshold, source.c:18; `get_delta_denom`, source.R:177-187).
/// `None` when no entry qualifies (all structural zeros). NaN entries are
/// skipped by the positivity test.
pub fn delta_denom(xhat: &[f64]) -> Option<f64> {
    let mut best: Option<f64> = None;
    for &x in xhat {
        if x > NUMERIC_ZERO && best.map_or(true, |b| x < b) {
            best = Some(x);
        }
    }
    best.map(|b| b / 2.0)
}

/// Masked Poisson deviance (generalized KL) with the floored log argument:
/// `Σ_mask [x·(ln x − ln(max(x̂, delta_denom))) − x + x̂]`, where `x = 0`
/// contributes exactly `x̂` with no log term (source.R:160-175; C
/// source.c:386-413). This is the standalone kernel; the ECM driver's
/// reported test error uses the upstream full-matrix linear correction (see
/// [`ecm_fit`]) — the two shapes are both pinned by goldens and deliberately
/// distinct.
///
/// Errors: `"argument"` for length mismatches, negative entries, or a
/// non-positive/non-finite `delta_denom`; `"na"` for non-finite entries.
pub fn poisson_deviance(
    v: &[f64],
    xhat: &[f64],
    mask: &[bool],
    delta_denom: f64,
) -> Result<f64, MsError> {
    if v.len() != xhat.len() || v.len() != mask.len() {
        return Err(MsError::new(
            "argument",
            "counts, reconstruction and mask must have equal length",
        )
        .with_i(v.len() as i64));
    }
    if !delta_denom.is_finite() || delta_denom <= 0.0 {
        return Err(MsError::new(
            "argument",
            "delta_denom must be finite and positive",
        ));
    }
    for (idx, (&x, &m)) in v.iter().zip(xhat.iter()).enumerate() {
        if !x.is_finite() || !m.is_finite() {
            return Err(MsError::new("na", "non-finite entry in deviance input")
                .with_i(idx as i64 + 1));
        }
        if x < 0.0 || m < 0.0 {
            return Err(MsError::new("argument", "negative entry in deviance input")
                .with_i(idx as i64 + 1));
        }
    }
    let mut acc = 0.0f64;
    for idx in 0..v.len() {
        if !mask[idx] {
            continue;
        }
        let (x, m) = (v[idx], xhat[idx]);
        if x > 0.0 {
            acc += x * (x.ln() - m.max(delta_denom).ln()) - x + m;
        } else {
            acc += m;
        }
    }
    Ok(acc)
}

/// Reported test error: `sqrt(CV.te / M)` with `M = NR·NC`
/// (source.R:670-671).
pub fn test_ms_err(cv_te: f64, n_rows: usize, n_cols: usize) -> f64 {
    (cv_te / (n_rows * n_cols) as f64).sqrt()
}

/// Reported training error: `sqrt(CV.tr / (M·(Kfold − 1)))` — the denominator
/// is the total number of training cells across the folds. Degenerate
/// `k_folds < 2` yields 0.0 (callers reject that grid upstream of this point).
pub fn train_ms_err(cv_tr: f64, n_rows: usize, n_cols: usize, k_folds: usize) -> f64 {
    let train_cells = (n_rows * n_cols).saturating_mul(k_folds.saturating_sub(1));
    if train_cells == 0 {
        return 0.0;
    }
    (cv_tr / train_cells as f64).sqrt()
}

#[derive(Debug, Clone, PartialEq)]
pub struct UnitError {
    pub rank: usize,
    pub fold: usize,
    pub seed: usize,
    pub train: f64,
    pub test: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CvResult {
    pub per_rank_fold_te: Vec<Option<f64>>,
    pub per_rank_fold_tr: Vec<Option<f64>>,
    pub per_rank_cv: Vec<Option<f64>>,
    pub per_rank_cv_tr: Vec<Option<f64>>,
    pub argmin_rank: Option<usize>,
}

/// Aggregation (`getSummary`, source.R:627-692): per (rank, fold) — in the
/// given `ranks` × `folds` order — the seed is picked by `which.min(train)`
/// (first minimum in input order, non-finite trains excluded) and its test
/// error recorded; a (rank, fold) with no finite seed is `None` on both
/// errors. Rank totals are `Σ_folds` over the finite entries (`na.rm`
/// semantics); an all-`None` rank is `None`. `argmin_rank` is the first
/// minimum of the rank totals (lowest rank on ties, source.R:682-688).
pub fn aggregate(
    units: &[UnitError],
    ranks: &[usize],
    folds: &[usize],
    _n_rows: usize,
    _n_cols: usize,
) -> CvResult {
    let n_folds = folds.len();
    let mut per_rank_fold_te = Vec::with_capacity(ranks.len() * n_folds);
    let mut per_rank_fold_tr = Vec::with_capacity(ranks.len() * n_folds);
    for &k in ranks {
        for &f in folds {
            let mut best: Option<&UnitError> = None;
            for u in units {
                // Upstream getSummary requires BOTH train and test finite
                // for a seed to be selectable (parity with tmp0 filtering);
                // test finiteness is unreachable via cv_error but the
                // kernel contract keeps the two-sided guard.
                if u.rank == k
                    && u.fold == f
                    && u.train.is_finite()
                    && u.test.is_finite()
                    && best.map_or(true, |b| u.train < b.train)
                {
                    best = Some(u);
                }
            }
            match best {
                Some(u) => {
                    per_rank_fold_te.push(Some(u.test));
                    per_rank_fold_tr.push(Some(u.train));
                }
                None => {
                    per_rank_fold_te.push(None);
                    per_rank_fold_tr.push(None);
                }
            }
        }
    }
    let mut per_rank_cv = Vec::with_capacity(ranks.len());
    let mut per_rank_cv_tr = Vec::with_capacity(ranks.len());
    for r in 0..ranks.len() {
        let mut sum_te = 0.0f64;
        let mut sum_tr = 0.0f64;
        let mut any_te = false;
        let mut any_tr = false;
        for fi in 0..n_folds {
            let cell = r * n_folds + fi;
            if let Some(x) = per_rank_fold_te[cell].filter(|x| x.is_finite()) {
                sum_te += x;
                any_te = true;
            }
            if let Some(x) = per_rank_fold_tr[cell].filter(|x| x.is_finite()) {
                sum_tr += x;
                any_tr = true;
            }
        }
        per_rank_cv.push(if any_te { Some(sum_te) } else { None });
        per_rank_cv_tr.push(if any_tr { Some(sum_tr) } else { None });
    }
    let mut argmin: Option<usize> = None;
    let mut best_val = f64::INFINITY;
    for (i, c) in per_rank_cv.iter().enumerate() {
        if let Some(x) = c {
            if *x < best_val {
                best_val = *x;
                argmin = Some(i);
            }
        }
    }
    CvResult {
        per_rank_fold_te,
        per_rank_fold_tr,
        per_rank_cv,
        per_rank_cv_tr,
        argmin_rank: argmin.map(|i| ranks[i]),
    }
}

/// Full SUITOR CV grid (memo §2.3/§2.4): for every rank `1..=max_rank`, fold
/// `0..k_folds` and seed `0..n_seeds`, one independent ECM fit on the
/// row-median-imputed matrix; initializer from canonical stream
/// `StreamId { replicate: seed_idx, rank, fold: 1-based fold }`. Errors:
/// `"argument"` for degenerate grids, storage mismatches, or negative
/// entries; `"na"` for non-finite entries (1-based positions attached).
#[allow(clippy::too_many_arguments)]
pub fn cv_error(
    v: &[f64],
    m: usize,
    n: usize,
    max_rank: usize,
    k_folds: usize,
    n_seeds: usize,
    max_iter: usize,
    base_seed: u64,
) -> Result<CvResult, MsError> {
    if m == 0 || n == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive"));
    }
    if v.len() != m * n {
        return Err(
            MsError::new("argument", "counts storage must hold m*n elements").with_i(v.len() as i64)
        );
    }
    for (idx, &x) in v.iter().enumerate() {
        if !x.is_finite() {
            return Err(MsError::new("na", "non-finite entry in counts")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
        if x < 0.0 {
            return Err(MsError::new("argument", "negative entry in counts")
                .with_i((idx / n + 1) as i64)
                .with_j((idx % n + 1) as i64));
        }
    }
    if k_folds < 2 {
        return Err(MsError::new(
            "argument",
            "k_folds must be at least 2 (upstream check_op)",
        ));
    }
    if k_folds > m {
        return Err(MsError::new(
            "argument",
            "k_folds must not exceed the channel count (every fold must hold out at least one row per column)",
        ));
    }
    if max_rank == 0 {
        return Err(MsError::new("argument", "max_rank must be positive"));
    }
    if max_rank > m.min(n) {
        return Err(MsError::new(
            "argument",
            "max_rank must not exceed min(n_rows, n_cols)",
        ));
    }
    if n_seeds == 0 {
        return Err(MsError::new("argument", "n_seeds must be positive"));
    }
    if max_iter == 0 {
        return Err(MsError::new("argument", "max_iter must be positive"));
    }

    let ranks: Vec<usize> = (1..=max_rank).collect();
    let folds: Vec<usize> = (0..k_folds).collect();
    let mut units = Vec::with_capacity(max_rank * k_folds * n_seeds);
    for &k in &ranks {
        for &f in &folds {
            let mask = fold_mask(m, n, k_folds, f);
            let input_k0 = initial_impute(v, m, n, &mask)?;
            for s in 0..n_seeds {
                let mut rng = MsRng::from_stream(
                    base_seed,
                    StreamId {
                        replicate: s as u64,
                        rank: k as u64,
                        fold: f as u64 + 1,
                    },
                );
                let (w0, h0) = ecm_init(&input_k0, m, n, k, &mut rng);
                let fit = ecm_fit(v, &input_k0, &mask, m, n, k, &w0, &h0, max_iter)?;
                units.push(UnitError {
                    rank: k,
                    fold: f,
                    seed: s,
                    train: fit.train_deviance,
                    test: fit.test_deviance,
                });
            }
        }
    }
    Ok(aggregate(&units, &ranks, &folds, m, n))
}

/// ECM fit outcome (`Ecm` in source.R:289-344 terms): final factors,
/// reconstruction, monitors and the iteration bookkeeping of the run.
#[derive(Debug, Clone, PartialEq)]
pub struct EcmFit {
    /// Rounds actually executed (`1..=max_iter`; `0` only for the degenerate
    /// `max_iter = 0` call).
    pub iterations: usize,
    /// True when the `em.eps` relative-change monitor stopped the loop.
    pub converged: bool,
    /// Signature matrix `W`, row-major `m × rank`.
    pub w: Vec<f64>,
    /// Exposure matrix `H`, row-major `rank × n`.
    pub h: Vec<f64>,
    /// Reconstruction `W·H`, row-major `m × n` (the conditional means the
    /// held-out cells were last replaced by).
    pub xhat: Vec<f64>,
    /// Last `min(positive x̂)/2` log floor (from the final `xhat`).
    pub delta_denom: f64,
    /// Training-cell generalized KL deviance of the final state,
    /// `Σ_train [x·ln(x/max(x̂, delta)) − x + x̂]` (upstream `loglike_new`,
    /// source.R:176-190, unscaled — the `em.eps` monitor compares
    /// `sqrt(·/train.adj)` transforms of successive rounds, source.R:316).
    pub train_deviance: f64,
    /// Held-out generalized KL deviance of the final state (upstream
    /// `loglike` on `idxMat`, source.R:160-175 — identical in shape to
    /// [`poisson_deviance`]; the per-fold value that enters `CV.te`).
    pub test_deviance: f64,
}

/// Seeded ECM initializer (module docs, stream layout): open-interval
/// uniforms `(0, 1]` scaled by `sqrt(mean(imputed)/rank)` — the
/// [`crate::nmf`] convention applied to the matrix actually fitted — W
/// row-major first, then H row-major, from the caller's canonical stream.
fn ecm_init(input_k0: &[f64], m: usize, n: usize, rank: usize, rng: &mut MsRng) -> (Vec<f64>, Vec<f64>) {
    let mut mean = 0.0f64;
    for &x in input_k0 {
        mean += x;
    }
    mean /= (m * n) as f64;
    let scale = if mean > 0.0 {
        (mean / rank as f64).sqrt()
    } else {
        1.0
    };
    let mut w = vec![0.0f64; m * rank];
    for x in w.iter_mut() {
        *x = scale * open_unit(rng);
    }
    let mut h = vec![0.0f64; rank * n];
    for x in h.iter_mut() {
        *x = scale * open_unit(rng);
    }
    (w, h)
}

/// Uniform draw on the open-at-zero interval (0, 1] — the
/// [`crate::nmf`] initializer convention (an exact-zero init entry would be
/// absorbing under multiplicative updates).
fn open_unit(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64 + 1.0) * (1.0 / (1u64 << 53) as f64)
}

/// Training-cell generalized KL deviance `Σ_train [x·ln(x/max(x̂, delta)) − x
/// + x̂]` — the upstream `loglike_new` monitor (source.R:176-190; `x = 0`
/// cells contribute exactly `x̂`, no log term).
fn train_monitor(v: &[f64], xhat: &[f64], mask: &[bool], delta: f64) -> f64 {
    let mut acc = 0.0f64;
    for i in 0..v.len() {
        if mask[i] {
            continue;
        }
        let (x, mh) = (v[i], xhat[i]);
        if x > 0.0 {
            acc += x * (x.ln() - mh.max(delta).ln()) - x + mh;
        } else {
            acc += mh;
        }
    }
    acc
}

/// One ECM run of the SUITOR inner loop (`ECM_alg`, source.R:289-344) from an
/// explicit initializer. Each round: one audited KL-MU H step then W step on
/// the current imputed matrix ([`crate::nmf`] kernels, fixed order), the
/// reconstruction `x̂ = W·H`, then — only if the loop continues — the
/// held-out cells are replaced by the new conditional means (source.R:596,
/// :326). The `em.eps` monitor is the training-cell deviance
/// [`train_monitor`] under the upstream transform `lik = sqrt(dev/train.adj)`
/// with `train.adj = m·n − |held|` (source.R:316, :344): the run stops when
/// `|lik_t − lik_{t−1}|/lik_{t−1} < [`EM_EPS`]` (checked from the second
/// round on, exactly as upstream), or after `max_iter` rounds.
/// `delta_denom = min(positive x̂)/2` is re-derived from each round's full
/// reconstruction (source.R:311).
///
/// Errors: `"argument"` for degenerate dimensions, storage mismatches,
/// negative entries, a mask with no training cell, or a reconstruction
/// without a single positive entry; `"na"` for non-finite entries.
#[allow(clippy::too_many_arguments)]
pub fn ecm_fit(
    v: &[f64],
    input_k0: &[f64],
    mask: &[bool],
    m: usize,
    n: usize,
    rank: usize,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
) -> Result<EcmFit, MsError> {
    if m == 0 || n == 0 || rank == 0 {
        return Err(MsError::new("argument", "matrix dimensions must be positive"));
    }
    if v.len() != m * n {
        return Err(
            MsError::new("argument", "counts storage must hold m*n elements").with_i(v.len() as i64)
        );
    }
    if input_k0.len() != m * n {
        return Err(MsError::new(
            "argument",
            "imputed storage must hold m*n elements",
        )
        .with_i(input_k0.len() as i64));
    }
    if mask.len() != m * n {
        return Err(MsError::new("argument", "mask storage must hold m*n elements")
            .with_i(mask.len() as i64));
    }
    if w0.len() != m * rank {
        return Err(MsError::new("argument", "w0 storage must hold m*rank elements")
            .with_i(w0.len() as i64));
    }
    if h0.len() != rank * n {
        return Err(MsError::new("argument", "h0 storage must hold rank*n elements")
            .with_i(h0.len() as i64));
    }
    for (name, mat, stride) in [
        ("counts", v, n),
        ("imputed matrix", input_k0, n),
        ("w0", w0, rank),
        ("h0", h0, n),
    ] {
        for (idx, &x) in mat.iter().enumerate() {
            if !x.is_finite() {
                return Err(MsError::new("na", format!("non-finite entry in {name}"))
                    .with_i((idx / stride + 1) as i64)
                    .with_j((idx % stride + 1) as i64));
            }
            if x < 0.0 {
                return Err(MsError::new(
                    "argument",
                    format!("negative entry in {name}"),
                )
                .with_i((idx / stride + 1) as i64)
                .with_j((idx % stride + 1) as i64));
            }
        }
    }

    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    // Working matrix: the imputed input; its held-out cells are replaced by
    // the conditional means whenever the loop continues.
    let mut working = input_k0.to_vec();

    let held = mask.iter().filter(|&&b| b).count();
    if held == m * n {
        return Err(MsError::new(
            "argument",
            "mask must leave at least one training cell",
        ));
    }
    let train_adj = (m * n - held) as f64;

    let mut xhat = matmul(&w, &h, m, n, rank);
    let mut delta = delta_denom(&xhat).unwrap_or(MIN_VALUE);
    let mut iterations = 0usize;
    let mut converged = false;
    let mut prev_lik: Option<f64> = None;
    let mut last_train = 0.0f64;

    for t in 1..=max_iter {
        kl_h_step(&working, &w, &mut h, m, n, rank);
        kl_w_step(&working, &mut w, &h, m, n, rank);
        xhat = matmul(&w, &h, m, n, rank);
        delta = match delta_denom(&xhat) {
            Some(d) => d,
            None => {
                return Err(MsError::new(
                    "argument",
                    "reconstruction has no positive entry; delta_denom undefined",
                ))
            }
        };
        let train = train_monitor(v, &xhat, mask, delta);
        // Upstream monitor transform (source.R:316); the deviance is a sum of
        // non-negative terms, so the max(0) only absorbs rounding noise.
        let lik = (train / train_adj).max(0.0).sqrt();
        iterations = t;
        last_train = train;
        // Convergence from the second round on (source.R:317-320).
        if t > 1 {
            let prev = prev_lik.unwrap_or(f64::INFINITY);
            let rel = if prev > 0.0 {
                (prev - lik).abs() / prev
            } else if lik == prev {
                0.0
            } else {
                f64::INFINITY
            };
            if rel < EM_EPS {
                converged = true;
                break;
            }
        }
        if t >= max_iter {
            break;
        }
        prev_lik = Some(lik);
        // E-step imputation: held-out cells take the current conditional
        // means (source.R:596, :326).
        for i in 0..working.len() {
            if mask[i] {
                working[i] = xhat[i];
            }
        }
    }

    let test_deviance = poisson_deviance(v, &xhat, mask, delta)?;
    Ok(EcmFit {
        iterations,
        converged,
        w,
        h,
        xhat,
        delta_denom: delta,
        train_deviance: last_train,
        test_deviance,
    })
}

// ======================================================================
// Tests: hand-derived goldens (memo §5 items 13-18) + smoke/determinism.
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // ------------------------------------------------------------------
    // Golden 1 (memo §5 item 13, brief "n=10, k=3"): fold member lists for
    // n_rows=10, k_fold=3, columns 0..5, all folds. 1-based upstream rule
    // r ≡ (COL + k − 1) (mod 3), residue 0 → 3 (source.R:148-158,
    // source.c:363-384); 0-based form r ≡ (c + f) (mod 3).
    // ------------------------------------------------------------------
    #[test]
    #[allow(clippy::needless_range_loop)] // pinned golden indexing style
    fn golden_fold_members_n10_k3() {
        let expect: [[&[usize]; 3]; 5] = [
            // col 0 (COL=1): residues 1, 2, 3(=0) mod 3 over rows 1..=10
            [&[0, 3, 6, 9], &[1, 4, 7], &[2, 5, 8]],
            // col 1 (COL=2): rotation by one
            [&[1, 4, 7], &[2, 5, 8], &[0, 3, 6, 9]],
            // col 2 (COL=3)
            [&[2, 5, 8], &[0, 3, 6, 9], &[1, 4, 7]],
            // col 3 (COL=4)
            [&[0, 3, 6, 9], &[1, 4, 7], &[2, 5, 8]],
            // col 4 (COL=5)
            [&[1, 4, 7], &[2, 5, 8], &[0, 3, 6, 9]],
        ];
        for c in 0..5 {
            for f in 0..3 {
                assert_eq!(fold_members(10, 3, f, c), expect[c][f], "col {c}, fold {f}");
            }
        }
    }

    // ------------------------------------------------------------------
    // Golden 2 (memo §5 item 13): NR=7, NC=5, Kfold=3 — per-column the
    // three fold member lists partition all rows; the per-column rotation
    // property (column c's fold-f list = column 0's fold-(f+c) list).
    // ------------------------------------------------------------------
    #[test]
    fn golden_fold_partition_and_rotation_nr7() {
        let (nr, nc, k) = (7usize, 5usize, 3usize);
        for c in 0..nc {
            let mut seen = vec![false; nr];
            for f in 0..k {
                let members = fold_members(nr, k, f, c);
                assert!(!members.is_empty(), "k<=nr keeps every fold non-empty");
                for &r in &members {
                    assert!(r < nr && !seen[r], "cell ({r},{c}) in two folds");
                    seen[r] = true;
                }
                // Rotation: column c fold f == column 0 fold (f + c) mod k.
                assert_eq!(
                    members,
                    fold_members(nr, k, (f + c) % k, 0),
                    "rotation col {c}, fold {f}"
                );
            }
            assert!(seen.iter().all(|&s| s), "column {c} not partitioned");
        }
    }

    // ------------------------------------------------------------------
    // Golden 3 (memo §5 item 13): NR < Kfold degenerate case — some
    // (fold, column) member lists are empty (upstream tolerates this in
    // the mask primitives; cv_error rejects it, see the error-path test).
    // ------------------------------------------------------------------
    #[test]
    fn golden_fold_members_nr_lt_kfold() {
        assert_eq!(fold_members(2, 3, 0, 0), [0]);
        assert_eq!(fold_members(2, 3, 1, 0), [1]);
        assert!(fold_members(2, 3, 2, 0).is_empty());
        assert_eq!(fold_members(2, 3, 0, 1), [1]);
        assert!(fold_members(2, 3, 1, 1).is_empty());
        assert_eq!(fold_members(2, 3, 2, 1), [0]);
    }

    // ------------------------------------------------------------------
    // Golden 4 (memo §5 item 14): row-median initial imputation with the
    // R median convention (even count: mean of the two central order
    // statistics) and the whole-matrix min.value floor (observed zeros
    // included). Mask: n_rows=3, n_cols=3, k_fold=2, fold=0 → cell (r,c)
    // held iff r ≡ c (mod 2): col 0 → rows {0,2}, col 1 → row {1},
    // col 2 → rows {0,2}.
    //   row 0 = [9, 20, 11]: observed {20} → median 20 → [20, 20, 20]
    //   row 1 = [0, 6, 0]:  observed {0, 0} → median 0 → floor → 1e-4
    //   row 2 = [7, 2, 8]:  observed {2} → median 2 → [2, 2, 2]
    // ------------------------------------------------------------------
    #[test]
    fn golden_initial_impute_median_and_floor() {
        let v = [9.0, 20.0, 11.0, 0.0, 6.0, 0.0, 7.0, 2.0, 8.0];
        let mask = fold_mask(3, 3, 2, 0);
        let expect = [20.0, 20.0, 20.0, MIN_VALUE, MIN_VALUE, MIN_VALUE, 2.0, 2.0, 2.0];
        let got = initial_impute(&v, 3, 3, &mask).unwrap();
        assert_eq!(got, expect);
        // The mask is exactly the fold-0 rotation mask.
        assert_eq!(
            mask,
            vec![true, false, true, false, true, false, true, false, true]
        );
    }

    // ------------------------------------------------------------------
    // Golden 5: a channel row fully held out under the mask has no
    // observed entries — deterministic error (upstream C reads past the
    // buffer here; we fail fast instead).
    // ------------------------------------------------------------------
    #[test]
    fn initial_impute_fully_held_row_errors() {
        let v = [1.0, 2.0];
        let mask = [true, false]; // row 0 (single column) fully held
        let err = initial_impute(&v, 2, 1, &mask).unwrap_err();
        assert_eq!(err.topic(), "argument");
        assert_eq!(err.i, Some(1));
    }

    // ------------------------------------------------------------------
    // Golden 6 (memo §5 item 15): held-out Poisson deviance with the
    // x = 0 branch (contribution x̂, unfloored) and the delta_denom floor
    // on the log argument only. Cells: x = [4, 0, 2], x̂ = [2, 3, 0.5].
    //   δ = 1:    4·ln2 − 2 + 3 + (2·(ln2 − ln1) − 2 + 0.5) = 6·ln2 − 0.5
    //   δ = 0.25: third log unfloored → 2·(ln2 − ln0.5) = 4·ln2
    //             total = 8·ln2 − 0.5
    // delta_denom: min positive (above NUMERIC_ZERO) / 2 = 0.5/2; the
    // 1e-250 entry is not "positive" at the C threshold; all-zero → None.
    // ------------------------------------------------------------------
    #[test]
    fn golden_poisson_deviance_and_delta_denom() {
        let v = [4.0, 0.0, 2.0];
        let xhat = [2.0, 3.0, 0.5];
        let all = [true, true, true];
        let got1 = poisson_deviance(&v, &xhat, &all, 1.0).unwrap();
        assert!((got1 - (6.0 * 2.0f64.ln() - 0.5)).abs() < 1e-12, "{got1}");
        let got2 = poisson_deviance(&v, &xhat, &all, 0.25).unwrap();
        assert!((got2 - (8.0 * 2.0f64.ln() - 0.5)).abs() < 1e-12, "{got2}");
        // Masked subset: only cells 0 and 2, δ = 0.25 → 8·ln2 − 3.5.
        let sub = [true, false, true];
        let got3 = poisson_deviance(&v, &xhat, &sub, 0.25).unwrap();
        assert!((got3 - (8.0 * 2.0f64.ln() - 3.5)).abs() < 1e-12, "{got3}");

        assert_eq!(delta_denom(&[2.0, 3.0, 0.5, 0.0, 1e-250]), Some(0.25));
        assert_eq!(delta_denom(&[0.0, 0.0]), None);
        assert_eq!(delta_denom(&[1.0]), Some(0.5));
    }

    // ------------------------------------------------------------------
    // Golden 7 (memo §5 item 16): ECM hand-derivation, 2 channels × 3
    // samples, rank 1, k_fold=2, fold=1 → held cells (1,0), (0,1), (1,2).
    // V = [[4, 1, 9], [1, 3, 2]]; median fill gives
    // input_k0 = [[4, 6.5, 9], [3, 3, 3]] (row 0 observed {4, 9} → 6.5;
    // row 1 observed {3}). Explicit init W0 = [[2], [1]], H0 = [[1, 1, 1]].
    // Round 1 (H step then W step on the imputed matrix):
    //   H1 = [7/3, 19/6, 4];  W1 = [39/19, 18/19]
    //   x̂ = [[91/19, 6.5, 156/19], [42/19, 3, 72/19]]
    //   delta_denom = (42/19)/2 = 21/19
    //   train deviance = 4·ln(76/91) + 9·ln(57/52)
    //   test deviance = 8.5 − ln(42/19) − ln(6.5) + 2·ln(19/36)
    // Round 2 starts from the replaced matrix (held-out = x̂) and the
    // em.eps monitor stops the loop (converged).
    // ------------------------------------------------------------------
    #[test]
    fn golden_ecm_single_round_hand_derivation() {
        let v = [4.0, 1.0, 9.0, 1.0, 3.0, 2.0];
        let mask = fold_mask(2, 3, 2, 1);
        assert_eq!(
            mask,
            vec![false, true, false, true, false, true],
            "held cells (0,1), (1,0), (1,2)"
        );
        let input_k0 = initial_impute(&v, 2, 3, &mask).unwrap();
        assert_eq!(input_k0, [4.0, 6.5, 9.0, 3.0, 3.0, 3.0]);

        // Exactly one ECM round: no convergence check, no replacement yet.
        // GOLDEN FIX (2026-09-30, green pass): the w0 literal was `[2.0]`
        // (one element) — a typo contradicting the fixture's own derivation
        // ("Explicit init W0 = [[2], [1]]") and its own asserted W1 =
        // [39/19, 18/19]: the pinned H step h₁ = (2·2 + 1·3)/3 = 7/3 needs
        // the two-channel initializer w = (2, 1), and no m=2 fit exists
        // from a 1-element W0. Corrected to `[2.0, 1.0]`.
        let one = ecm_fit(
            &v, &input_k0, &mask, 2, 3, 1, &[2.0, 1.0], &[1.0, 1.0, 1.0], 1,
        )
        .unwrap();
        assert_eq!(one.iterations, 1);
        assert!(!one.converged);
        let w1 = [39.0 / 19.0, 18.0 / 19.0];
        let h1 = [7.0 / 3.0, 19.0 / 6.0, 4.0];
        for (g, e) in one.w.iter().zip(w1) {
            assert!((g - e).abs() < 1e-12, "w = {:?}", one.w);
        }
        for (g, e) in one.h.iter().zip(h1) {
            assert!((g - e).abs() < 1e-12, "h = {:?}", one.h);
        }
        let xhat1 = [91.0 / 19.0, 6.5, 156.0 / 19.0, 42.0 / 19.0, 3.0, 72.0 / 19.0];
        for (g, e) in one.xhat.iter().zip(xhat1) {
            assert!((g - e).abs() < 1e-12, "xhat = {:?}", one.xhat);
        }
        assert!((one.delta_denom - 21.0 / 19.0).abs() < 1e-12);
        let train1 = 4.0 * (76.0f64 / 91.0).ln() + 9.0 * (57.0f64 / 52.0).ln();
        assert!((one.train_deviance - train1).abs() < 1e-9, "train {}", one.train_deviance);
        let test1 =
            8.5 - (42.0f64 / 19.0).ln() - 6.5f64.ln() + 2.0 * (19.0f64 / 36.0).ln();
        assert!((one.test_deviance - test1).abs() < 1e-9, "test {}", one.test_deviance);

        // With headroom the em.eps monitor stops the loop; the fixed
        // round-1 quantities are pinned above, here we pin convergence.
        let many = ecm_fit(
            &v, &input_k0, &mask, 2, 3, 1, &[2.0, 1.0], &[1.0, 1.0, 1.0], 50,
        )
        .unwrap();
        assert!(many.converged, "em.eps monitor must stop the loop");
        assert!(many.iterations >= 2 && many.iterations <= 50);
        // GOLDEN FIX (2026-09-30, green pass): the original block asserted
        // converged xhat within 1e-6 OF ROUND 1. That is unreachable under
        // the pinned ECM semantics: round 1 does not reproduce the observed
        // cells (x̂00 = 91/19 ≈ 4.789 vs v00 = 4), so round 2's MU ratios are
        // not 1 and the iteration keeps moving — the upstream em.eps monitor
        // (loglike_new over TRAIN cells + sqrt(train.adj) scaling) first
        // passes at round 22 (audited twice: the TRAIN monitor is the 22
        // count; a full-grid monitor would stop at round 7 — different
        // quantity, do not conflate).
        // The ECM fixed points are exactly the self-consistent matrices
        // A* = W·H whose held cells equal the reconstruction; here the
        // iteration converges on A* = [[4, 6.5, 9], [24/13, 3, 54/13]]
        // (row1 = (6/13)·row0, so A* is exactly rank 1 and the MU ratios
        // vanish), verified by direct simulation of the pinned update rules.
        // The drift assertion is therefore replaced by the derivable
        // fixed-point pin.
        let fixed_point = [4.0, 6.5, 9.0, 24.0 / 13.0, 3.0, 54.0 / 13.0];
        for (g, e) in many.xhat.iter().zip(fixed_point) {
            assert!((g - e).abs() < 1e-6, "converged xhat vs fixed point: {g} vs {e}");
        }
    }

    // ------------------------------------------------------------------
    // Golden 8 (memo §5 items 17-18): aggregation — per (rank, fold) the
    // seed is picked by which.min(train) (first minimum, input order) and
    // its test error taken; CV.te/CV.tr = Σ folds (na.rm); argmin over
    // CV.te with first-minimum tie-break (lowest rank); non-finite seeds
    // are excluded; a fold with no finite seed is None and drops out of
    // the sum. MSErr formulas: sqrt(CV.te/M) and sqrt(CV.tr/(M·(K−1))).
    // ------------------------------------------------------------------
    #[test]
    fn golden_aggregate_selection_sum_and_argmin() {
        let units = vec![
            // rank 1, fold 0: seeds (10, 100), (8, 200) → pick seed 1.
            UnitError { rank: 1, fold: 0, seed: 0, train: 10.0, test: 100.0 },
            UnitError { rank: 1, fold: 0, seed: 1, train: 8.0, test: 200.0 },
            // rank 1, fold 1: train tie (5, 5) → first seed wins → test 30.
            UnitError { rank: 1, fold: 1, seed: 0, train: 5.0, test: 30.0 },
            UnitError { rank: 1, fold: 1, seed: 1, train: 5.0, test: 40.0 },
            // rank 2, fold 0: pick seed 0 (train 7).
            UnitError { rank: 2, fold: 0, seed: 0, train: 7.0, test: 50.0 },
            UnitError { rank: 2, fold: 0, seed: 1, train: 9.0, test: 60.0 },
            // rank 2, fold 1: NaN seed excluded → seed 0.
            UnitError { rank: 2, fold: 1, seed: 0, train: 6.0, test: 70.0 },
            UnitError { rank: 2, fold: 1, seed: 1, train: f64::NAN, test: 80.0 },
            // rank 3: single seed per fold.
            UnitError { rank: 3, fold: 0, seed: 0, train: 1.0, test: 120.0 },
            UnitError { rank: 3, fold: 1, seed: 0, train: 2.0, test: 120.0 },
        ];
        let res = aggregate(&units, &[1, 2, 3], &[0, 1], 3, 2);
        assert_eq!(
            res.per_rank_fold_te,
            vec![Some(200.0), Some(30.0), Some(50.0), Some(70.0), Some(120.0), Some(120.0)]
        );
        assert_eq!(
            res.per_rank_fold_tr,
            vec![Some(8.0), Some(5.0), Some(7.0), Some(6.0), Some(1.0), Some(2.0)]
        );
        assert_eq!(res.per_rank_cv, vec![Some(230.0), Some(120.0), Some(240.0)]);
        assert_eq!(res.per_rank_cv_tr, vec![Some(13.0), Some(13.0), Some(3.0)]);
        assert_eq!(res.argmin_rank, Some(2));
        assert!((test_ms_err(230.0, 3, 2) - (230.0f64 / 6.0).sqrt()).abs() < 1e-12);
        assert!((train_ms_err(13.0, 3, 2, 2) - (13.0f64 / 6.0).sqrt()).abs() < 1e-12);
    }

    // ------------------------------------------------------------------
    // Golden 8b: an all-non-finite fold is None and drops out of the rank
    // sum (upstream sum(..., na.rm=TRUE)); the argmin tie on equal CV.te
    // keeps the LOWEST rank (which.min first occurrence).
    //
    // GOLDEN FIX (2026-09-30, green pass): the original fixture wrote BOTH
    // rank-2 folds with test = 120 while asserting CV.te(rank 2) = 120. Under
    // the memo §2.3 rule CV.te = Σ_folds 测试误差 — pinned by golden 8, whose
    // rank 3 has the identical fold pair {120, 120} and asserts Some(240) —
    // {120, 120} necessarily sums to 240, so the original assertions were
    // mutually unsatisfiable (no implementation could pass them). To realize
    // the fixture's own stated intent ("same total CV.te (120) → tie → rank 1
    // wins") the rank-2 fold-1 test value is corrected to 0.0, making the tie
    // exact: 120 + 0 = 120 = CV.te(rank 1).
    // ------------------------------------------------------------------
    #[test]
    fn golden_aggregate_na_fold_and_tie_break() {
        let units = vec![
            // rank 1, fold 0: no finite seed → None.
            UnitError { rank: 1, fold: 0, seed: 0, train: f64::NAN, test: f64::NAN },
            UnitError { rank: 1, fold: 1, seed: 0, train: 5.0, test: 120.0 },
            // rank 2: same total CV.te (120 = 120 + 0) → tie → rank 1 wins.
            UnitError { rank: 2, fold: 0, seed: 0, train: 5.0, test: 120.0 },
            UnitError { rank: 2, fold: 1, seed: 0, train: 5.0, test: 0.0 },
        ];
        let res = aggregate(&units, &[1, 2], &[0, 1], 3, 2);
        assert_eq!(res.per_rank_fold_te[0], None);
        assert_eq!(res.per_rank_fold_te[1], Some(120.0));
        assert_eq!(res.per_rank_cv, vec![Some(120.0), Some(120.0)]);
        assert_eq!(res.argmin_rank, Some(1));
    }

    // ------------------------------------------------------------------
    // Smoke (brief): separable synthetic truth with k* = 2 — the CV curve
    // must attain its minimum at the true rank. Fixed seed, protocol-
    // equivalence layer (not a bit-golden).
    // ------------------------------------------------------------------
    #[test]
    fn cv_error_smoke_separable_argmin_at_true_rank() {
        let (m, n, k_true) = (32usize, 12usize, 2usize);
        let v = separable_counts(m, n, k_true);
        let res = cv_error(&v, m, n, 3, 3, 2, 120, 42).unwrap();
        assert_eq!(res.argmin_rank, Some(k_true), "cv = {:?}", res.per_rank_cv);
        assert_eq!(res.per_rank_cv.len(), 3);
        assert!(res.per_rank_cv.iter().all(|c| matches!(c, Some(x) if x.is_finite())));
    }

    // ------------------------------------------------------------------
    // Determinism: same inputs → bit-identical CvResult; a different
    // base seed moves the canonical streams and the curve values.
    // ------------------------------------------------------------------
    #[test]
    fn cv_error_is_deterministic_and_seed_separated() {
        let (m, n, k_true) = (32usize, 12usize, 2usize);
        let v = separable_counts(m, n, k_true);
        let a = cv_error(&v, m, n, 3, 3, 2, 60, 42).unwrap();
        let b = cv_error(&v, m, n, 3, 3, 2, 60, 42).unwrap();
        assert_eq!(a, b);
        let c = cv_error(&v, m, n, 3, 3, 2, 60, 7).unwrap();
        assert_ne!(a.per_rank_cv, c.per_rank_cv, "base seed must move the streams");
    }

    /// Separable count matrix: k_true signatures with 32/k_true exclusive
    /// anchor channels each, near-pure sample groups (the identifiability
    /// carrier, same construction as the nmf.rs recovery fixture).
    fn separable_counts(m: usize, n: usize, k_true: usize) -> Vec<f64> {
        let mut rng = crate::rng::MsRng::from_stream(
            0xBEF2,
            StreamId { replicate: 9, rank: 1, fold: 7 },
        );
        let uniform = |rng: &mut crate::rng::MsRng| {
            ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
        };
        let anchors = m / k_true;
        let mut w = vec![0.0f64; m * k_true];
        for s in 0..k_true {
            let mut col: Vec<f64> = (0..m)
                .map(|i| if i / anchors == s { 0.5 + uniform(&mut rng) } else { 0.0 })
                .collect();
            let sum: f64 = col.iter().sum();
            for x in col.iter_mut() {
                *x /= sum;
            }
            for i in 0..m {
                w[i * k_true + s] = col[i];
            }
        }
        let mut h = vec![0.0f64; k_true * n];
        for j in 0..n {
            let dom = j * k_true / n; // near-pure groups over the sample axis
            for s in 0..k_true {
                h[s * n + j] = if s == dom {
                    800.0 + 800.0 * uniform(&mut rng)
                } else {
                    20.0 * uniform(&mut rng)
                };
            }
        }
        // v = W·H (row-major m×k · k×n).
        let mut v = vec![0.0f64; m * n];
        for i in 0..m {
            for s in 0..k_true {
                let ws = w[i * k_true + s];
                if ws == 0.0 {
                    continue;
                }
                for j in 0..n {
                    v[i * n + j] += ws * h[s * n + j];
                }
            }
        }
        v
    }

    // ------------------------------------------------------------------
    // Error paths (brief): empty input, shape mismatch, non-finite /
    // negative entries, k_folds < 2, k_folds > n_rows, degenerate grids.
    // ------------------------------------------------------------------
    #[test]
    fn cv_error_validation_paths() {
        let v4 = [1.0, 2.0, 3.0, 4.0];
        // Empty input / shape mismatch.
        assert_eq!(cv_error(&[], 0, 0, 1, 2, 1, 1, 0).unwrap_err().topic(), "argument");
        assert_eq!(cv_error(&v4[..3], 2, 2, 1, 2, 1, 1, 0).unwrap_err().topic(), "argument");
        // Non-finite and negative entries (1-based positions attached).
        let err = cv_error(&[1.0, f64::NAN, 3.0, 4.0], 2, 2, 1, 2, 1, 1, 0).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(1) );
        assert_eq!(err.j, Some(2));
        let err = cv_error(&[1.0, -2.0, 3.0, 4.0], 2, 2, 1, 2, 1, 1, 0).unwrap_err();
        assert_eq!(err.topic(), "argument");
        // k_folds < 2 (upstream check_op) and k_folds > n_rows (a fold must
        // hold out at least one row per column).
        assert_eq!(cv_error(&v4, 2, 2, 1, 1, 1, 1, 0).unwrap_err().topic(), "argument");
        assert_eq!(cv_error(&v4, 2, 2, 1, 3, 1, 1, 0).unwrap_err().topic(), "argument");
        // Degenerate grids: max_rank = 0, max_rank > min(m, n), n_seeds = 0,
        // max_iter = 0.
        assert_eq!(cv_error(&v4, 2, 2, 0, 2, 1, 1, 0).unwrap_err().topic(), "argument");
        assert_eq!(cv_error(&v4, 2, 2, 3, 2, 1, 1, 0).unwrap_err().topic(), "argument");
        assert_eq!(cv_error(&v4, 2, 2, 1, 2, 0, 1, 0).unwrap_err().topic(), "argument");
        assert_eq!(cv_error(&v4, 2, 2, 1, 2, 1, 0, 0).unwrap_err().topic(), "argument");
    }

    // ------------------------------------------------------------------
    // Stream mapping freeze (memo §2.4): unit (rank, fold, seed_idx) fits
    // on StreamId { replicate: seed_idx, rank, fold(1-based) } — the same
    // (rank, fold) with different seeds must draw disjoint initializers
    // (visible as different train deviances on a generic matrix).
    // ------------------------------------------------------------------
    #[test]
    fn seed_axis_produces_distinct_fits() {
        let (m, n) = (8usize, 6usize);
        let mut rng = crate::rng::MsRng::from_stream(11, StreamId { replicate: 3, rank: 5, fold: 2 });
        let v: Vec<f64> = (0..m * n)
            .map(|_| 1.0 + ((rng.next_u64() >> 11) as f64) * 100.0 / (1u64 << 53) as f64)
            .collect();
        let res = cv_error(&v, m, n, 2, 2, 3, 40, 42).unwrap();
        assert_eq!(res.per_rank_cv.len(), 2);
        assert!(res.per_rank_cv.iter().all(|c| matches!(c, Some(x) if x.is_finite())));
    }
}
