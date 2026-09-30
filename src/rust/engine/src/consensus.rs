//! Consensus clustering core and evaluation matching layer (U-M2-01;
//! `docs/ARCHITECTURE.md` §2 `engine/consensus.rs`, design memo
//! `docs/devlog/2026-09-30-M2-pipeline-design-memo.md` §1/§1.5/§5).
//!
//! # Upstream semantics (pinned to source, D11/D13)
//!
//! SigProfilerExtractor master `cc6bf5ef` (= v1.5.0). Line numbers below
//! refer to `SigProfilerExtractor/subroutines.py` (Sub) as anchored in the
//! design memo. The consensus path has **no 0.9 threshold** (PI ruling
//! 2026-09-30: 0.9 exists only in the Islam-style evaluation function,
//! Sub:2022); the consensus is the *iterative Hungarian reassignment* of
//! Sub:885-1123:
//!
//! 1. **Ensemble stacking** — each replicate contributes `k` column-normalized
//!    signature vectors; the stacked matrix has `k_total = R·k` columns
//!    (Sub:710-727). This kernel receives the already-stacked matrix; the
//!    replicate axis owns blocks `[r·k, (r+1)·k)`.
//! 2. **Restarts** — `n_restarts = 50` random restarts
//!    (`parallel_clustering(iterations=50)`, Sub:1075/1014). Each restart
//!    starts from uniform-random centroids over `[0, 1)` (Sub:976-978,
//!    `Generator(PCG64DXSM(...)).random((channels, k))`). Here the stream is
//!    [`MsRng::from_stream`] with `StreamId { replicate: restart, rank: k,
//!    fold: 0 }`, drawing in (channel, cluster) row-major order — the same
//!    fill order as the upstream `(channels, k)` array. (Upstream also draws
//!    an exposure block from the same generator *after* the centroid block;
//!    exposure consensus is out of scope for this unit, and the exposure draw
//!    happens after the centroid draw upstream, so W-side streams are
//!    unaffected.)
//! 3. **Reassignment round** (`reclustering`, Sub:885-965) — for each
//!    replicate: cosine-distance cost matrix between the current `k` centroid
//!    columns and the replicate's `k` signature columns
//!    (`cdist(centroidsᵀ, replicateᵀ, "cosine")`), minimum-cost one-to-one
//!    assignment (`linear_sum_assignment`, Sub:885-889), so every replicate
//!    contributes exactly one signature to every cluster; new centroids =
//!    within-cluster means over replicates in replicate order (Sub:952).
//! 4. **Convergence** (`cluster_converge_innerloop`, Sub:967-1007) — after
//!    each round the average silhouette (cosine metric, Sub:940) is compared
//!    to the previous round with **exact floating-point equality**
//!    (`result == avgSilhouetteCoefficients`), or the round counter hits 10
//!    (`elif convergence_count == 10`), whichever comes first. The previous
//!    average is initialized to `0` upstream (`result = 0`), so a first-round
//!    average of exactly 0.0 stops after one round; at most 11 rounds run.
//!    The reported (centroids, labels, silhouettes) always come from the last
//!    executed round and are mutually consistent.
//! 5. **Best restart** (`cluster_converge_outerloop`, Sub:1099) — strictly
//!    greater average silhouette replaces the incumbent; ties keep the
//!    earliest restart.
//! 6. **Stability** (Sub:940-1062) — per-signature silhouette over all
//!    `k_total` stacked signatures with the cluster labels; per-cluster
//!    stability = mean of the member silhouettes; `avg_stability` = mean over
//!    all signatures (Sub:942). Rank `k = 1` is special-cased upstream
//!    (Sub:1050-1051): the silhouette is undefined and every signature is
//!    given 1.0 by convention.
//!
//! # Cosine convention (PI ruling, memo §5 item 4 / fork 6)
//!
//! Similarity between two vectors is `dot/(‖a‖‖b‖)`; a **zero vector has
//! similarity 0 with everything** (including another zero vector), hence
//! cosine distance 1. Upstream is internally inconsistent here (`cos_sim`
//! returns 0, the `cdist` path yields NaN); we unify on 0/1. Similarity is
//! clamped to `[-1, 1]`, so distances lie in `[0, 2]` and are never negative.
//!
//! # Silhouette kernel (sklearn `silhouette_samples(metric="cosine")` parity)
//!
//! For sample `i` in cluster `C`: `a = mean distance to the *other* members
//! of `C`` (self excluded explicitly — sklearn achieves the same by summing
//! the full cluster row, whose self-distance is ~0, and dividing by
//! `|C| − 1`; the explicit exclusion removes that ≈1-ulp self-distance noise
//! and is a declared micro-divergence within the numeric-protocol tolerance),
//! `b = min over other clusters of the mean distance to that cluster`,
//! `s = (b − a) / max(a, b)`, with `s = 0` when the denominator is 0 and
//! `s = 0` for singleton clusters (sklearn's NaN-to-zero rule). Following
//! sklearn, the label count must satisfy `2 ≤ n_labels ≤ n_samples − 1`
//! (single-label and all-singleton labelings are rejected); the rank-1
//! all-ones convention is applied by the consensus driver *before* the
//! kernel is ever called, mirroring upstream.
//!
//! # Hungarian assignment (self-implemented, no dependencies)
//!
//! Minimum-cost bipartite assignment by shortest augmenting paths with dual
//! potentials — the simplified Jonker-Volgenant formulation (a.k.a. the
//! classic e-maxx Laplacian): rows are processed in ascending order, each
//! augmentation runs a Dijkstra-like scan over column potentials
//! (`O(rows² · cols)` total, exact — no approximation). Rectangular problems
//! with `rows > cols` are solved on the transpose and mapped back. Output
//! convention (mirrors `scipy.optimize.linear_sum_assignment`): exactly
//! `min(rows, cols)` pairs; the smaller dimension is enumerated in ascending
//! order in its index array. Tie-breaking is *our* documented convention
//! (scipy's is implementation-defined): among equal-reduced-cost choices the
//! smallest column index wins, so the all-zero and all-equal matrices yield
//! the identity assignment, and the pinned tie goldens coincide with the
//! lexicographically smallest optimal assignment.
//!
//! # Split/merge classification (evaluation matching layer, memo §1.5)
//!
//! Independent of the consensus layer; both share the same Hungarian kernel.
//! Input: estimated signatures (p columns) × reference signatures (q columns)
//! over the same channels, one cosine similarity matrix `C ∈ R^{p×q}`, and a
//! threshold τ (sweepable, Islam-compatible `seq(0.80, 0.90)`). The
//! Hungarian assignment on `1 − C` is τ-independent and computed once:
//!
//! * **TP** = assigned pairs with `C ≥ τ`; `fp = p − |TP|`, `fn = q − |TP|`.
//! * Every estimated signature **not** in a TP pair is classified from its
//!   own similarity row (row-vector logic only; the assignment is never
//!   modified):
//!   * **merge** — top-2 similarities both ≥ τ (two *distinct* reference
//!     indices, so `q ≥ 2`): an under-split blend of `t1 ∪ t2`;
//!   * **split** — otherwise top-1 ≥ τ: an over-split fragment of `t1`
//!     (the memo's "already assigned to another estimated signature" clause
//!     is automatically satisfied — any reference reaching a non-TP
//!     signature at ≥ τ is always claimed by the optimal assignment, proved
//!     by the standard swap argument in the test module);
//!   * **novel** — top-1 < τ.
//!
//!   Merge is checked before split: both rules fire iff top-1 ≥ τ, and the
//!   split reading would make the memo's merge golden (#11) unreachable;
//!   merge-first is the only self-consistent precedence and is pinned by
//!   goldens.
//! * Per reference: TP partner, fragments (split signatures pointing at it),
//!   merges (whose top-2 includes it), and a `covered_fn` diagnostic (FN
//!   reference that is the argmax of some non-TP estimated signature —
//!   diagnostic only, never changes TP/FN).
//!
//! # Determinism contract
//!
//! Single-threaded, fixed reduction order, no library calls beyond IEEE
//! arithmetic and `sqrt` (exact per IEEE 754): identical inputs and seeds
//! give bit-identical results on every toolchain from 1.71 to current
//! stable, so thread-count invariance is inherited for free by the future
//! parallel driver (U-M1s-05 pattern). Golden tests pin integer/label
//! outcomes (semantic bit-exactness, D11) and float outcomes under a 1e-12
//! tolerance (numeric-protocol equivalence, D11).
//!
//! # Contract notes
//!
//! Pure engine kernel: no FFI face, no `unsafe`, no dependencies
//! (FFI contract 5: `Result<_, MsError>` everywhere, never panic across a
//! boundary).

use crate::error::MsError;
use crate::rng::{MsRng, StreamId};

// ======================================================================
// Cosine kernels (columns of a row-major `dim × n` matrix)
// ======================================================================

/// Similarity between column `ca` of `a` (row-major `dim × stride_a`) and
/// column `cb` of `b`. Zero vector → 0 (PI ruling); result clamped to
/// `[-1, 1]`. Overflow-safe: two successive divisions instead of a product
/// of norms.
fn cosine_similarity_cols(
    a: &[f64],
    stride_a: usize,
    ca: usize,
    b: &[f64],
    stride_b: usize,
    cb: usize,
    dim: usize,
) -> f64 {
    let mut dot = 0.0f64;
    for r in 0..dim {
        dot += a[r * stride_a + ca] * b[r * stride_b + cb];
    }
    let mut na = 0.0f64;
    for r in 0..dim {
        na += a[r * stride_a + ca] * a[r * stride_a + ca];
    }
    if na == 0.0 {
        return 0.0;
    }
    let mut nb = 0.0f64;
    for r in 0..dim {
        nb += b[r * stride_b + cb] * b[r * stride_b + cb];
    }
    if nb == 0.0 {
        return 0.0;
    }
    (dot / na.sqrt() / nb.sqrt()).clamp(-1.0, 1.0)
}

/// Validate a row-major `dim × n` column-stacked matrix: non-empty, storage
/// size, and finiteness (FFI contract 3, `"na"` with 1-based indices).
fn validate_stacked(x: &[f64], dim: usize, n: usize, what: &str) -> Result<(), MsError> {
    if dim == 0 || n == 0 {
        return Err(MsError::new(
            "argument",
            format!("{what} dimensions must be positive"),
        ));
    }
    if x.len() != dim * n {
        return Err(MsError::new(
            "argument",
            format!("{what} storage must hold dim*n elements"),
        )
        .with_i(x.len() as i64));
    }
    for (idx, &v) in x.iter().enumerate() {
        if !v.is_finite() {
            return Err(MsError::new(
                "na",
                format!("non-finite entry in {what}"),
            )
            .with_i((idx / n + 1) as i64)
            .with_j((idx % n + 1) as i64));
        }
    }
    Ok(())
}

/// All-pairs cosine **similarity** matrix between the `n` columns of `x`
/// (row-major `dim × n`; each column is one vector). Row-major `n × n`
/// output, exactly symmetric by construction (the dot products are summed
/// in the same order in both directions). Zero vectors have similarity 0
/// with everything (PI ruling); the diagonal of a nonzero column is 1 up to
/// rounding (clamped from above at 1).
pub fn cosine_similarity_matrix(x: &[f64], dim: usize, n: usize) -> Result<Vec<f64>, MsError> {
    validate_stacked(x, dim, n, "similarity input")?;
    let mut sim = vec![0.0f64; n * n];
    for i in 0..n {
        for j in (i + 1)..n {
            let s = cosine_similarity_cols(x, n, i, x, n, j, dim);
            sim[i * n + j] = s;
            sim[j * n + i] = s;
        }
        sim[i * n + i] = cosine_similarity_cols(x, n, i, x, n, i, dim);
    }
    Ok(sim)
}

/// All-pairs cosine **distance** matrix (`1 − similarity`) between the
/// columns of `x`. Values lie in `[0, 2]`; zero vectors sit at distance 1
/// from everything, including each other (PI ruling — declared divergence
/// from the upstream `cdist` NaN).
pub fn cosine_distance_matrix(x: &[f64], dim: usize, n: usize) -> Result<Vec<f64>, MsError> {
    let sim = cosine_similarity_matrix(x, dim, n)?;
    Ok(sim.into_iter().map(|s| 1.0 - s).collect())
}

/// Cross cosine **similarity** matrix between the `p` columns of `a` and the
/// `q` columns of `b` (both row-major `dim × n_vec`). Row-major `p × q`
/// output: element `(i, j)` is the similarity of `a`'s column `i` with `b`'s
/// column `j`.
pub fn cross_cosine_similarity(
    a: &[f64],
    b: &[f64],
    dim: usize,
    p: usize,
    q: usize,
) -> Result<Vec<f64>, MsError> {
    validate_stacked(a, dim, p, "estimated matrix")?;
    validate_stacked(b, dim, q, "reference matrix")?;
    let mut sim = vec![0.0f64; p * q];
    for i in 0..p {
        for j in 0..q {
            sim[i * q + j] = cosine_similarity_cols(a, p, i, b, q, j, dim);
        }
    }
    Ok(sim)
}

// ======================================================================
// Hungarian assignment (rectangular, min-cost, self-implemented)
// ======================================================================

/// A minimum-cost assignment: `row_ind[t] ↔ col_ind[t]` for `t` in
/// `0..min(rows, cols)`. Mirrors the `scipy.optimize.linear_sum_assignment`
/// output convention: the smaller dimension is fully enumerated in ascending
/// order in its own index array (for `rows ≤ cols`: `row_ind = 0..rows` and
/// `col_ind[t]` is the column assigned to row `t`; for `rows > cols`:
/// `col_ind = 0..cols` and `row_ind` is the sorted subset of matched rows).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Assignment {
    /// Row side of the `t`-th assigned pair.
    pub row_ind: Vec<usize>,
    /// Column side of the `t`-th assigned pair.
    pub col_ind: Vec<usize>,
}

impl Assignment {
    /// Total cost of the assignment: `Σ cost[row_ind[t] * cols + col_ind[t]]`.
    pub fn total_cost(&self, cost: &[f64], cols: usize) -> f64 {
        self.row_ind
            .iter()
            .zip(self.col_ind.iter())
            .map(|(&r, &c)| cost[r * cols + c])
            .sum()
    }
}

/// Minimum-cost rectangular bipartite assignment (`rows × cols` cost matrix,
/// row-major) via shortest augmenting paths with dual potentials — the
/// simplified Jonker-Volgenant scheme documented in the module docs.
/// Deterministic: rows augment in ascending order; equal-reduced-cost
/// candidates resolve to the smallest column index (identity assignment on
/// all-zero/all-equal matrices).
///
/// Errors: `"argument"` for zero dimensions, a storage-size mismatch, or a
/// non-finite cost entry.
pub fn hungarian_min_cost(cost: &[f64], rows: usize, cols: usize) -> Result<Assignment, MsError> {
    if rows == 0 || cols == 0 {
        return Err(MsError::new(
            "argument",
            "assignment dimensions must be positive",
        ));
    }
    if cost.len() != rows * cols {
        return Err(MsError::new(
            "argument",
            "cost matrix storage must hold rows*cols elements",
        )
        .with_i(cost.len() as i64));
    }
    for (idx, &v) in cost.iter().enumerate() {
        if !v.is_finite() {
            return Err(
                MsError::new("na", "non-finite entry in cost matrix")
                    .with_i((idx / cols + 1) as i64)
                    .with_j((idx % cols + 1) as i64)
            );
        }
    }

    if rows <= cols {
        let col_of_row = solve_assignment(cost, rows, cols);
        Ok(Assignment {
            row_ind: (0..rows).collect(),
            col_ind: col_of_row,
        })
    } else {
        // Transpose: solve cols × rows (cols ≤ rows), then map back. Every
        // original column is matched; pairs are emitted with the row side
        // sorted ascending (scipy convention).
        let mut transposed = vec![0.0f64; rows * cols];
        for r in 0..rows {
            for c in 0..cols {
                transposed[c * rows + r] = cost[r * cols + c];
            }
        }
        let col_of_row = solve_assignment(&transposed, cols, rows);
        // col_of_row[c] = row assigned to original column c.
        let mut pairs: Vec<(usize, usize)> =
            col_of_row.iter().enumerate().map(|(c, &r)| (r, c)).collect();
        pairs.sort_unstable();
        let (row_ind, col_ind): (Vec<usize>, Vec<usize>) = pairs.into_iter().unzip();
        Ok(Assignment { row_ind, col_ind })
    }
}

/// Core shortest-augmenting-path solver for `rows ≤ cols`; returns the
/// assigned column of every row (a vector of length `rows` with distinct
/// entries in `0..cols`).
fn solve_assignment(cost: &[f64], rows: usize, cols: usize) -> Vec<usize> {
    // 1-based formulation with a scratch column 0 (classic e-maxx layout):
    // p[j] = row currently matched to column j; u/v are the dual potentials.
    let mut u = vec![0.0f64; rows + 1];
    let mut v = vec![0.0f64; cols + 1];
    let mut p = vec![0usize; cols + 1];
    let mut way = vec![0usize; cols + 1];

    for i in 1..=rows {
        p[0] = i;
        let mut j0 = 0usize;
        let mut minv = vec![f64::INFINITY; cols + 1];
        let mut used = vec![false; cols + 1];
        loop {
            used[j0] = true;
            let i0 = p[j0];
            let mut delta = f64::INFINITY;
            let mut j1 = 0usize;
            for j in 1..=cols {
                if used[j] {
                    continue;
                }
                let cur = cost[(i0 - 1) * cols + (j - 1)] - u[i0] - v[j];
                if cur < minv[j] {
                    minv[j] = cur;
                    way[j] = j0;
                }
                // Strict `<`: the first (smallest) column at the minimum wins
                // — the documented deterministic tie-break.
                if minv[j] < delta {
                    delta = minv[j];
                    j1 = j;
                }
            }
            if j1 == 0 {
                // Unreachable for finite costs (every augmentation ends at an
                // unmatched column before all columns are used); defensive
                // guard instead of a panic (FFI contract 5).
                return (0..rows).collect();
            }
            for j in 0..=cols {
                if used[j] {
                    u[p[j]] += delta;
                    v[j] -= delta;
                } else {
                    minv[j] -= delta;
                }
            }
            j0 = j1;
            if p[j0] == 0 {
                break;
            }
        }
        // Augment: flip the path back to column 0.
        while j0 != 0 {
            let j1 = way[j0];
            p[j0] = p[j1];
            j0 = j1;
        }
    }

    let mut col_of_row = vec![0usize; rows];
    for j in 1..=cols {
        if p[j] != 0 {
            col_of_row[p[j] - 1] = j - 1;
        }
    }
    col_of_row
}

// ======================================================================
// Silhouette (cosine metric; sklearn silhouette_samples parity)
// ======================================================================

/// Per-sample silhouette coefficients with the cosine metric for the `n`
/// columns of `x` (row-major `dim × n`) under `labels`. Matches
/// `sklearn.metrics.silhouette_samples(..., metric="cosine")` to within the
/// numeric-protocol tolerance: `a` = mean cosine distance to the other
/// members of the same cluster (self excluded explicitly — see the module
/// docs), `b` = smallest mean cosine distance to another cluster,
/// `s = (b − a)/max(a, b)`, `s = 0` for singleton clusters and when
/// `max(a, b) = 0`.
///
/// Errors: `"argument"` when the label count is outside
/// `2 ≤ n_labels ≤ n_samples − 1` (mirroring sklearn's ValueError — the
/// rank-1 all-ones convention is the *caller's* special case, Sub:1050) or a
/// label is out of range; `"na"` on non-finite input.
pub fn silhouette_samples_cosine(
    x: &[f64],
    dim: usize,
    n: usize,
    labels: &[usize],
) -> Result<Vec<f64>, MsError> {
    validate_stacked(x, dim, n, "silhouette input")?;
    if labels.len() != n {
        return Err(MsError::new(
            "argument",
            "one label per sample is required",
        )
        .with_i(labels.len() as i64));
    }
    let n_labels = labels.iter().copied().max().map_or(0, |m| m + 1);
    if n_labels < 2 || n_labels >= n {
        return Err(MsError::new(
            "argument",
            "number of labels must be between 2 and n_samples - 1 (inclusive)",
        )
        .with_i(n_labels as i64));
    }
    for (i, &l) in labels.iter().enumerate() {
        if l >= n_labels {
            return Err(MsError::new("argument", "label out of range").with_i(i as i64 + 1));
        }
    }

    // Pairwise cosine distances (full n×n; matches upstream memory profile).
    let dist = cosine_distance_matrix(x, dim, n)?;

    let mut sizes = vec![0usize; n_labels];
    for &l in labels {
        sizes[l] += 1;
    }

    let mut sil = vec![0.0f64; n];
    for i in 0..n {
        let li = labels[i];
        if sizes[li] == 1 {
            continue; // singleton cluster: s = 0 (sklearn NaN-to-zero rule)
        }
        // a: mean distance to the OTHER members of the own cluster.
        let mut a_sum = 0.0f64;
        for j in 0..n {
            if j != i && labels[j] == li {
                a_sum += dist[i * n + j];
            }
        }
        let a = a_sum / (sizes[li] - 1) as f64;
        // b: smallest mean distance over the other clusters.
        let mut b = f64::INFINITY;
        for (c, &size) in sizes.iter().enumerate() {
            if c == li {
                continue;
            }
            let mut sum = 0.0f64;
            for j in 0..n {
                if labels[j] == c {
                    sum += dist[i * n + j];
                }
            }
            let mean = sum / size as f64;
            if mean < b {
                b = mean;
            }
        }
        let m = a.max(b);
        sil[i] = if m > 0.0 { (b - a) / m } else { 0.0 };
    }
    Ok(sil)
}

// ======================================================================
// Consensus: iterative Hungarian reassignment (memo §1.2)
// ======================================================================

/// Tunables of [`consensus_cluster`]. Defaults mirror the upstream
/// hard-coded values (50 restarts, 10-round convergence counter cap).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConsensusConfig {
    /// Master seed of the restart streams (canonical layout v1).
    pub master_seed: u64,
    /// Number of random restarts (upstream: 50, Sub:1075/1014).
    pub n_restarts: usize,
    /// Upstream `convergence_count` cap (Sub:992-998): the loop stops when a
    /// round's average silhouette equals the previous one exactly, or after
    /// `max_rounds + 1` rounds. Upstream: 10.
    pub max_rounds: usize,
}

impl Default for ConsensusConfig {
    fn default() -> Self {
        Self {
            master_seed: 0,
            n_restarts: 50,
            max_rounds: 10,
        }
    }
}

/// One converged restart of the iterative Hungarian reassignment.
#[derive(Debug, Clone, PartialEq)]
pub struct RestartFit {
    /// Consensus centroids of this restart, row-major `dim × k` (columns are
    /// signatures) — the within-cluster means of the final assignment.
    pub centroids: Vec<f64>,
    /// Cluster of every stacked signature, in stacked order (`k_total`).
    pub labels: Vec<usize>,
    /// Per-signature silhouette of the final assignment (`k_total`).
    pub silhouette: Vec<f64>,
    /// Per-cluster stability: mean silhouette of the cluster's members.
    pub cluster_stability: Vec<f64>,
    /// Mean silhouette over all `k_total` signatures (upstream
    /// `avgSilhouetteCoefficients`, Sub:942).
    pub avg: f64,
    /// Reassignment rounds executed (1..=max_rounds + 1).
    pub n_rounds: usize,
    /// True when the loop stopped on exact average-silhouette equality.
    pub converged: bool,
}

/// Result of [`consensus_cluster`]: the best restart plus restart bookkeeping
/// (evidence-table transparency).
#[derive(Debug, Clone, PartialEq)]
pub struct ConsensusFit {
    /// Consensus signature matrix, row-major `dim × k` (columns = signatures).
    pub centroids: Vec<f64>,
    /// Cluster of every stacked signature, in stacked order (`k_total`).
    pub labels: Vec<usize>,
    /// Per-signature silhouette of the winning assignment (`k_total`).
    pub silhouette: Vec<f64>,
    /// Per-cluster stability of the winning assignment (`k`).
    pub cluster_stability: Vec<f64>,
    /// Mean silhouette over all stacked signatures of the winning assignment
    /// (upstream `avgSilhouetteCoefficients`; the stability mean).
    pub avg_stability: f64,
    /// Index of the winning restart (ties keep the earliest, Sub:1099).
    pub best_restart: usize,
    /// Average silhouette of every restart, in restart order.
    pub restart_avgs: Vec<f64>,
    /// Per-restart convergence flag (exact-equality stop), in restart order.
    pub restart_converged: Vec<bool>,
    /// Rounds executed by the winning restart.
    pub n_rounds: usize,
    /// Whether the winning restart stopped on exact-equality convergence.
    pub converged: bool,
}

/// Mean of a slice in given order (fixed reduction order — determinism).
fn mean(values: &[f64]) -> f64 {
    values.iter().sum::<f64>() / values.len() as f64
}

/// Uniform on `[0, 1)` from the top 53 bits of one `next_u64` word — the
/// exact convention of `engine/resample.rs` (`unit_interval`), one word per
/// draw.
fn unit_interval(rng: &mut MsRng) -> f64 {
    (rng.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
}

/// One reassignment round (`reclustering`, Sub:885-965) against the given
/// centroids: per-replicate Hungarian reassignment, new centroids as
/// within-cluster means, silhouette statistics of the new assignment.
#[allow(clippy::needless_range_loop)]
#[allow(clippy::type_complexity)]
fn recluster_once(
    stacked: &[f64],
    dim: usize,
    k: usize,
    n_rep: usize,
    centroids: &[f64],
) -> Result<(Vec<f64>, Vec<usize>, Vec<f64>, Vec<f64>, f64), MsError> {
    let k_total = k * n_rep;

    // (a) per-replicate reassignment: cost[c][s] = 1 − cos(centroid c,
    //     signature s); column col_ind[c] of this replicate joins cluster c.
    let mut labels = vec![0usize; k_total];
    let mut members: Vec<Vec<usize>> = vec![Vec::with_capacity(n_rep); k];
    for r in 0..n_rep {
        let mut cost = vec![0.0f64; k * k];
        for c in 0..k {
            for s in 0..k {
                let sim = cosine_similarity_cols(centroids, k, c, stacked, k_total, r * k + s, dim);
                cost[c * k + s] = 1.0 - sim;
            }
        }
        let assignment = hungarian_min_cost(&cost, k, k)?;
        for c in 0..k {
            let sig = r * k + assignment.col_ind[c];
            labels[sig] = c;
            members[c].push(sig);
        }
    }

    // (b) new centroids: within-cluster means over replicates in order
    //     (Sub:952). Every cluster has exactly n_rep members by construction.
    let mut new_centroids = vec![0.0f64; dim * k];
    for (c, mem) in members.iter().enumerate() {
        for &sig in mem {
            for row in 0..dim {
                new_centroids[row * k + c] += stacked[row * k_total + sig];
            }
        }
        for row in 0..dim {
            new_centroids[row * k + c] /= n_rep as f64;
        }
    }

    // (c) silhouette statistics. Rank 1: the silhouette is undefined and
    //     every signature is given 1.0 by convention (Sub:1050-1051).
    let silhouette = if k == 1 {
        vec![1.0f64; k_total]
    } else {
        silhouette_samples_cosine(stacked, dim, k_total, &labels)?
    };
    let cluster_stability: Vec<f64> = members
        .iter()
        .map(|mem| {
            let vals: Vec<f64> = mem.iter().map(|&sig| silhouette[sig]).collect();
            mean(&vals)
        })
        .collect();
    let avg = mean(&silhouette);

    Ok((new_centroids, labels, silhouette, cluster_stability, avg))
}

/// One restart (`cluster_converge_innerloop`, Sub:967-1007) from an explicit
/// initial centroid matrix (row-major `dim × k`).
fn run_restart(
    stacked: &[f64],
    dim: usize,
    k: usize,
    n_rep: usize,
    initial_centroids: &[f64],
    max_rounds: usize,
) -> Result<RestartFit, MsError> {
    validate_stacked(initial_centroids, dim, k, "initial centroids")?;
    let mut centroids = initial_centroids.to_vec();
    // Upstream initializes the previous average to the literal 0
    // (`result = 0`, Sub:~990): a first-round average of exactly 0.0 stops
    // after one round; otherwise the loop runs until exact equality or the
    // round-cap branch (`convergence_count == 10`) — at most max_rounds + 1
    // rounds.
    let mut prev_avg = 0.0f64;
    let mut count = 0usize;
    loop {
        let (new_centroids, labels, silhouette, cluster_stability, avg) =
            recluster_once(stacked, dim, k, n_rep, &centroids)?;
        if avg == prev_avg {
            return Ok(RestartFit {
                centroids: new_centroids,
                labels,
                silhouette,
                cluster_stability,
                avg,
                n_rounds: count + 1,
                converged: true,
            });
        }
        if count == max_rounds {
            return Ok(RestartFit {
                centroids: new_centroids,
                labels,
                silhouette,
                cluster_stability,
                avg,
                n_rounds: count + 1,
                converged: false,
            });
        }
        prev_avg = avg;
        count += 1;
        centroids = new_centroids;
    }
}

/// Full consensus: `n_restarts` seeded random restarts, keep the one with the
/// highest average silhouette (strictly greater wins; ties keep the earliest
/// restart, Sub:1099).
///
/// `stacked_w` is the row-major `dim × k_total` matrix of stacked replicate
/// signatures (columns = signatures); replicate `r` owns columns
/// `[r·k, (r+1)·k)`. Restart `r` draws its uniform-random initial centroids
/// from `StreamId { replicate: r, rank: k, fold: 0 }` in (channel, cluster)
/// row-major order — the stream layout is frozen; any change requires
/// regenerating the golden set.
///
/// Errors: `"argument"` for `k = 0`, a stacked length not divisible into
/// `k`-sized replicate blocks, fewer than two replicates (the silhouette
/// needs ≥ 2 members per cluster; upstream would raise inside
/// `silhouette_samples`), a non-empty restart count, or non-finite entries.
pub fn consensus_cluster(
    stacked_w: &[f64],
    dim: usize,
    k: usize,
    config: ConsensusConfig,
) -> Result<ConsensusFit, MsError> {
    if k == 0 {
        return Err(MsError::new("argument", "k must be positive"));
    }
    if dim == 0 {
        return Err(MsError::new("argument", "channel count must be positive"));
    }
    if stacked_w.len() % dim != 0 {
        return Err(MsError::new(
            "argument",
            "stacked matrix length must be a multiple of the channel count",
        )
        .with_i(stacked_w.len() as i64));
    }
    let k_total = stacked_w.len() / dim;
    if k_total % k != 0 {
        return Err(MsError::new(
            "argument",
            "stacked signature count must be a multiple of k",
        )
        .with_i(k_total as i64));
    }
    let n_rep = k_total / k;
    if n_rep < 2 {
        return Err(MsError::new(
            "argument",
            "consensus needs at least two replicates",
        ));
    }
    if config.n_restarts == 0 {
        return Err(MsError::new(
            "argument",
            "at least one restart is required",
        ));
    }
    validate_stacked(stacked_w, dim, k_total, "stacked matrix")?;

    let mut restarts: Vec<RestartFit> = Vec::with_capacity(config.n_restarts);
    for r in 0..config.n_restarts {
        let mut rng = MsRng::from_stream(
            config.master_seed,
            StreamId {
                replicate: r as u64,
                rank: k as u64,
                fold: 0,
            },
        );
        let mut initial = vec![0.0f64; dim * k];
        for row in 0..dim {
            for c in 0..k {
                initial[row * k + c] = unit_interval(&mut rng);
            }
        }
        restarts.push(run_restart(stacked_w, dim, k, n_rep, &initial, config.max_rounds)?);
    }

    // Best restart: strictly greater average wins; ties keep the earliest
    // (Sub:1099).
    let mut best = 0usize;
    for r in 1..restarts.len() {
        if restarts[r].avg > restarts[best].avg {
            best = r;
        }
    }
    let win = &restarts[best];
    Ok(ConsensusFit {
        centroids: win.centroids.clone(),
        labels: win.labels.clone(),
        silhouette: win.silhouette.clone(),
        cluster_stability: win.cluster_stability.clone(),
        avg_stability: win.avg,
        best_restart: best,
        restart_avgs: restarts.iter().map(|f| f.avg).collect(),
        restart_converged: restarts.iter().map(|f| f.converged).collect(),
        n_rounds: win.n_rounds,
        converged: win.converged,
    })
}

/// One restart from an explicit initial centroid matrix — the deterministic
/// entry point used by the hand-traced goldens (memo §5 item 5). Restart
/// bookkeeping in the returned [`ConsensusFit`] describes this single run.
pub fn consensus_from_centroids(
    stacked_w: &[f64],
    dim: usize,
    k: usize,
    initial_centroids: &[f64],
    max_rounds: usize,
) -> Result<ConsensusFit, MsError> {
    if k == 0 {
        return Err(MsError::new("argument", "k must be positive"));
    }
    if dim == 0 {
        return Err(MsError::new("argument", "channel count must be positive"));
    }
    if stacked_w.len() % dim != 0 {
        return Err(MsError::new(
            "argument",
            "stacked matrix length must be a multiple of the channel count",
        )
        .with_i(stacked_w.len() as i64));
    }
    let k_total = stacked_w.len() / dim;
    if k_total % k != 0 {
        return Err(MsError::new(
            "argument",
            "stacked signature count must be a multiple of k",
        )
        .with_i(k_total as i64));
    }
    let n_rep = k_total / k;
    if n_rep < 2 {
        return Err(MsError::new(
            "argument",
            "consensus needs at least two replicates",
        ));
    }
    validate_stacked(stacked_w, dim, k_total, "stacked matrix")?;
    let fit = run_restart(stacked_w, dim, k, n_rep, initial_centroids, max_rounds)?;
    Ok(ConsensusFit {
        centroids: fit.centroids,
        labels: fit.labels,
        silhouette: fit.silhouette,
        cluster_stability: fit.cluster_stability,
        avg_stability: fit.avg,
        best_restart: 0,
        restart_avgs: vec![fit.avg],
        restart_converged: vec![fit.converged],
        n_rounds: fit.n_rounds,
        converged: fit.converged,
    })
}

// ======================================================================
// Split/merge classification (evaluation matching layer, memo §1.5)
// ======================================================================

/// Classification of one estimated signature against the reference set at a
/// given threshold (memo §1.5; applied only to signatures without a TP pair).
#[derive(Debug, Clone, PartialEq)]
pub enum EstimatedClass {
    /// Member of a TP pair (Hungarian-assigned with similarity ≥ τ).
    Matched {
        /// The paired reference signature.
        reference: usize,
    },
    /// Over-split fragment of the argmax reference (top-1 ≥ τ, top-2 < τ).
    Split {
        /// The reference this signature is a fragment of.
        reference: usize,
    },
    /// Under-split merge of the top-2 references (both ≥ τ, distinct).
    Merge {
        /// The two references blended, argmax first.
        references: [usize; 2],
    },
    /// No reference reaches τ (top-1 < τ).
    Novel,
}

/// Per-reference classification at one threshold.
#[derive(Debug, Clone, PartialEq)]
pub struct ReferenceMatch {
    /// TP partner (Hungarian pair with similarity ≥ τ), if any.
    pub matched_estimated: Option<usize>,
    /// Estimated signatures classified [`EstimatedClass::Split`] against this
    /// reference, in estimated order.
    pub fragments: Vec<usize>,
    /// Estimated signatures classified [`EstimatedClass::Merge`] whose top-2
    /// includes this reference, in estimated order.
    pub merges: Vec<usize>,
    /// Diagnostic only (memo §1.5): the reference is FN and is the argmax of
    /// some non-TP estimated signature ("FN covered by fragment/merge").
    /// Never changes TP/FN counts.
    pub covered_fn: bool,
}

/// Matching outcome at one threshold of the sweep.
#[derive(Debug, Clone, PartialEq)]
pub struct ThresholdMatch {
    /// The threshold this outcome was classified at.
    pub threshold: f64,
    /// Hungarian assignment pairs `(estimated, reference)` — τ-independent,
    /// identical across the sweep; the smaller side is enumerated ascending
    /// (see [`Assignment`]).
    pub pairs: Vec<(usize, usize)>,
    /// TP pairs (assignment pairs with similarity ≥ τ).
    pub tp: Vec<(usize, usize)>,
    /// Per-estimated classification (`p` entries, estimated order).
    pub estimated_classes: Vec<EstimatedClass>,
    /// Per-reference classification (`q` entries).
    pub references: Vec<ReferenceMatch>,
    /// Estimated signatures without a TP pair (`p − |tp|`).
    pub fp: usize,
    /// References without a TP pair (`q − |tp|`).
    pub fn_count: usize,
    /// Number of estimated signatures classified split.
    pub split_count: usize,
    /// Number of estimated signatures classified merge.
    pub merge_count: usize,
}

/// Evaluation matching layer (memo §1.5): match `p` estimated signatures
/// (columns of `estimated`, row-major `dim × p`) against `q` reference
/// signatures (columns of `reference`) over the same `dim` channels, for
/// every threshold in `thresholds` (Islam-compatible sweep; the memo's
/// default is `seq(0.80, 0.90, by = 0.01)` — pass it explicitly).
///
/// The cosine similarity matrix and the Hungarian assignment on `1 − C` are
/// computed once (the assignment is τ-independent); only the classification
/// repeats per threshold.
///
/// Errors: `"argument"` for empty inputs/dimension mismatches, non-finite
/// entries, or a non-finite threshold.
pub fn match_solutions(
    estimated: &[f64],
    reference: &[f64],
    dim: usize,
    thresholds: &[f64],
) -> Result<Vec<ThresholdMatch>, MsError> {
    for (t, &tau) in thresholds.iter().enumerate() {
        if !tau.is_finite() {
            return Err(MsError::new("argument", "thresholds must be finite")
                .with_i(t as i64 + 1));
        }
    }
    let p = p_of(estimated, dim)?;
    let q = q_of(reference, dim)?;
    let sim = cross_cosine_similarity(estimated, reference, dim, p, q)?;

    // The Hungarian assignment on 1 − C is τ-independent: computed once,
    // shared verbatim by every threshold of the sweep (memo §1.5).
    let cost: Vec<f64> = sim.iter().map(|&s| 1.0 - s).collect();
    let assignment = hungarian_min_cost(&cost, p, q)?;
    let pairs: Vec<(usize, usize)> = assignment
        .row_ind
        .iter()
        .copied()
        .zip(assignment.col_ind.iter().copied())
        .collect();

    let mut sweep = Vec::with_capacity(thresholds.len());
    for &tau in thresholds {
        // TP = assigned pairs with similarity ≥ τ (boundary inclusive, memo
        // §5 item 10); assignment pairs are never modified.
        let tp: Vec<(usize, usize)> = pairs
            .iter()
            .copied()
            .filter(|&(e, r)| sim[e * q + r] >= tau)
            .collect();
        let mut tp_of_est = vec![None; p];
        let mut tp_of_ref = vec![None; q];
        for &(e, r) in &tp {
            tp_of_est[e] = Some(r);
            tp_of_ref[r] = Some(e);
        }

        // Row-vector classification of every non-TP estimated signature
        // (top-1/top-2 of its similarity row; the assignment stays untouched).
        // Merge is checked before split (module docs): both rules require
        // top-1 ≥ τ, and split-first would make the merge golden unreachable.
        let mut estimated_classes = Vec::with_capacity(p);
        // argmax reference of each non-TP signature, for the covered_fn
        // diagnostic (memo §1.5: pure argmax, no τ condition).
        let mut argmax_of_est = vec![None; p];
        for e in 0..p {
            if let Some(r) = tp_of_est[e] {
                estimated_classes.push(EstimatedClass::Matched { reference: r });
                continue;
            }
            // Top-2 scan with distinct reference indices; equal values at
            // distinct indices qualify (the exact-tie merge golden).
            let mut top1 = (f64::NEG_INFINITY, usize::MAX);
            let mut top2 = (f64::NEG_INFINITY, usize::MAX);
            for j in 0..q {
                let v = sim[e * q + j];
                if v > top1.0 {
                    top2 = top1;
                    top1 = (v, j);
                } else if v >= top2.0 {
                    top2 = (v, j);
                }
            }
            argmax_of_est[e] = Some(top1.1);
            estimated_classes.push(if q >= 2 && top1.0 >= tau && top2.0 >= tau {
                EstimatedClass::Merge {
                    references: [top1.1, top2.1],
                }
            } else if top1.0 >= tau {
                EstimatedClass::Split {
                    reference: top1.1,
                }
            } else {
                EstimatedClass::Novel
            });
        }

        // Per-reference bookkeeping.
        let mut references = Vec::with_capacity(q);
        for (r, matched) in tp_of_ref.iter().enumerate() {
            let mut fragments = Vec::new();
            let mut merges = Vec::new();
            let mut covered = false;
            for e in 0..p {
                match &estimated_classes[e] {
                    EstimatedClass::Matched { .. } => {}
                    EstimatedClass::Split { reference } => {
                        if *reference == r {
                            fragments.push(e);
                        }
                    }
                    EstimatedClass::Merge { references: refs } => {
                        if refs.contains(&r) {
                            merges.push(e);
                        }
                    }
                    EstimatedClass::Novel => {}
                }
                if matched.is_none() && argmax_of_est[e] == Some(r) {
                    covered = true;
                }
            }
            references.push(ReferenceMatch {
                matched_estimated: *matched,
                fragments,
                merges,
                covered_fn: covered,
            });
        }

        let tp_count = tp.len();
        let split_count = estimated_classes
            .iter()
            .filter(|c| matches!(c, EstimatedClass::Split { .. }))
            .count();
        let merge_count = estimated_classes
            .iter()
            .filter(|c| matches!(c, EstimatedClass::Merge { .. }))
            .count();
        sweep.push(ThresholdMatch {
            threshold: tau,
            pairs: pairs.clone(),
            tp,
            estimated_classes,
            references,
            fp: p - tp_count,
            fn_count: q - tp_count,
            split_count,
            merge_count,
        });
    }
    Ok(sweep)
}

// Length derivation helpers for the match layer (p = estimated signatures,
// q = reference signatures over `dim` channels).
fn p_of(estimated: &[f64], dim: usize) -> Result<usize, MsError> {
    if dim == 0 || estimated.len() % dim != 0 {
        return Err(MsError::new("argument", "estimated storage must be dim*p"));
    }
    Ok(estimated.len() / dim)
}

fn q_of(reference: &[f64], dim: usize) -> Result<usize, MsError> {
    if dim == 0 || reference.len() % dim != 0 {
        return Err(MsError::new("argument", "reference storage must be dim*q"));
    }
    Ok(reference.len() / dim)
}

// ======================================================================
// Tests: goldens hand-derived from the memo (§5 items 1-8, 10-12), TDD
// suite for the U-M2-01 unit. Fixed seeds only (MsRng). Integer/label
// outcomes are asserted exactly (semantic bit-exactness, D11); float
// outcomes under a 1e-12 tolerance (numeric-protocol equivalence, D11).
// ======================================================================

#[cfg(test)]
mod tests {
    use super::*;

    const TOL: f64 = 1e-12;

    fn assert_close(actual: f64, expected: f64) {
        assert!(
            (actual - expected).abs() <= TOL * expected.abs().max(1.0),
            "actual {actual} vs expected {expected}"
        );
    }

    fn assert_slice_close(actual: &[f64], expected: &[f64]) {
        assert_eq!(actual.len(), expected.len(), "length mismatch");
        for (i, (a, e)) in actual.iter().zip(expected.iter()).enumerate() {
            assert!(
                (a - e).abs() <= TOL * e.abs().max(1.0),
                "element {i}: {a} vs {e}"
            );
        }
    }

    /// Column `j` of the fixture matrix: `cols[j] = (v[2j], v[2j+1])`.
    fn stack2(cols: &[(f64, f64)]) -> Vec<f64> {
        let n = cols.len();
        let mut m = vec![0.0f64; 2 * n];
        for (j, &(a, b)) in cols.iter().enumerate() {
            m[j] = a;
            m[n + j] = b;
        }
        m
    }

    // ------------------------------------------------------------------
    // Hungarian (memo §5 items 1-3)
    // ------------------------------------------------------------------

    #[test]
    fn golden_hungarian_square_3x3_tie_prefers_row_order() {
        // Two optimal assignments of cost 1: identity (0→0, 1→1, 2→2) and
        // the swap (0→1, 1→0, 2→2). scipy's linear_sum_assignment returns
        // the row-order-first one; our smallest-column tie-break coincides.
        // Memo §5 item 1 pins the assignment VECTOR, not just the cost.
        let cost = [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
        let a = hungarian_min_cost(&cost, 3, 3).unwrap();
        assert_eq!(a.row_ind, vec![0, 1, 2]);
        assert_eq!(a.col_ind, vec![0, 1, 2]);
        assert_close(a.total_cost(&cost, 3), 1.0);
    }

    #[test]
    fn hungarian_all_zero_matrix_is_identity() {
        let cost = [0.0f64; 9];
        let a = hungarian_min_cost(&cost, 3, 3).unwrap();
        assert_eq!(a.col_ind, vec![0, 1, 2]);
        assert_close(a.total_cost(&cost, 3), 0.0);
    }

    #[test]
    fn golden_hungarian_rectangular_2x3() {
        // Memo §5 item 2: min-dim semantics + unmatched column index.
        // Optimal unique: (0,1) + (1,0) = 1 + 2 = 3; column 2 unmatched.
        let cost = [4.0, 1.0, 3.0, 2.0, 0.0, 5.0];
        let a = hungarian_min_cost(&cost, 2, 3).unwrap();
        assert_eq!(a.row_ind, vec![0, 1]);
        assert_eq!(a.col_ind, vec![1, 0]);
        assert_close(a.total_cost(&cost, 3), 3.0);
        let matched: Vec<usize> = a.col_ind.clone();
        let unmatched: Vec<usize> = (0..3).filter(|c| !matched.contains(c)).collect();
        assert_eq!(unmatched, vec![2]);
    }

    #[test]
    fn golden_hungarian_rectangular_3x2() {
        // Memo §5 item 2, tall orientation: rows > cols; every column is
        // matched, pairs emitted with rows ascending; row 2 unmatched.
        // Optimal unique: (0,0) + (1,1) = 1 + 0 = 1.
        let cost = [1.0, 4.0, 2.0, 0.0, 5.0, 3.0];
        let a = hungarian_min_cost(&cost, 3, 2).unwrap();
        assert_eq!(a.row_ind, vec![0, 1]);
        assert_eq!(a.col_ind, vec![0, 1]);
        assert_close(a.total_cost(&cost, 2), 1.0);
        let unmatched: Vec<usize> = (0..3).filter(|r| !a.row_ind.contains(r)).collect();
        assert_eq!(unmatched, vec![2]);
    }

    /// Deterministic pseudorandom cost entry on a coarse grid (many exact
    /// ties — stresses the tie-break against the brute force minimum).
    fn grid_cost(rng: &mut MsRng, len: usize) -> Vec<f64> {
        (0..len)
            .map(|_| ((rng.next_u64() % 100) as f64) / 4.0)
            .collect()
    }

    fn brute_force_min(cost: &[f64], rows: usize, cols: usize) -> f64 {
        // Minimum over all injective row→column matchings (rows ≤ cols).
        let mut best = f64::INFINITY;
        let mut perm = vec![0usize; rows];
        let mut used = vec![false; cols];
        fn rec(
            cost: &[f64],
            cols: usize,
            i: usize,
            perm: &mut [usize],
            used: &mut [bool],
            acc: f64,
            best: &mut f64,
        ) {
            if i == perm.len() {
                if acc < *best {
                    *best = acc;
                }
                return;
            }
            for c in 0..cols {
                if used[c] {
                    continue;
                }
                used[c] = true;
                perm[i] = c;
                rec(
                    cost,
                    cols,
                    i + 1,
                    perm,
                    used,
                    acc + cost[i * cols + c],
                    best,
                );
                used[c] = false;
            }
        }
        rec(cost, cols, 0, &mut perm, &mut used, 0.0, &mut best);
        best
    }

    #[test]
    fn hungarian_matches_brute_force_squares() {
        // Memo §5 item 3 / ARCH §9 gate: k = 1..6, 50 random cases each,
        // tolerance 1e-12 (grid values make the permuted sums exact).
        let mut rng = MsRng::from_stream(
            2026,
            StreamId {
                replicate: 0,
                rank: 0,
                fold: 0,
            },
        );
        for n in 1..=6usize {
            for case in 0..50usize {
                let cost = grid_cost(&mut rng, n * n);
                let a = hungarian_min_cost(&cost, n, n).unwrap();
                // Valid bijection.
                let mut seen = vec![false; n];
                for &c in &a.col_ind {
                    assert!(c < n && !seen[c], "case {case} n {n}: bad bijection");
                    seen[c] = true;
                }
                assert_eq!(a.row_ind, (0..n).collect::<Vec<_>>());
                assert_close(a.total_cost(&cost, n), brute_force_min(&cost, n, n));
            }
        }
    }

    #[test]
    fn hungarian_matches_brute_force_rectangular() {
        let mut rng = MsRng::from_stream(
            77,
            StreamId {
                replicate: 1,
                rank: 0,
                fold: 0,
            },
        );
        for (rows, cols) in [(2usize, 5usize), (5, 2), (3, 5), (5, 3), (4, 6), (6, 4)] {
            for _case in 0..20usize {
                let cost = grid_cost(&mut rng, rows * cols);
                let a = hungarian_min_cost(&cost, rows, cols).unwrap();
                let (r, c, arr) = if rows <= cols {
                    (rows, cols, cost.clone())
                } else {
                    // Solve the transposed instance by brute force.
                    let mut t = vec![0.0f64; rows * cols];
                    for i in 0..rows {
                        for j in 0..cols {
                            t[j * rows + i] = cost[i * cols + j];
                        }
                    }
                    (cols, rows, t)
                };
                assert_eq!(a.row_ind.len(), a.col_ind.len());
                assert_eq!(a.row_ind.len(), r.min(c));
                assert_close(a.total_cost(&cost, cols), brute_force_min(&arr, r, c));
            }
        }
    }

    #[test]
    fn hungarian_rejects_bad_input() {
        assert_eq!(
            hungarian_min_cost(&[1.0, 2.0], 0, 2).unwrap_err().topic(),
            "argument"
        );
        assert_eq!(
            hungarian_min_cost(&[1.0, 2.0], 2, 2).unwrap_err().topic(),
            "argument"
        );
        let err = hungarian_min_cost(&[1.0, f64::NAN, 2.0, 1.0], 2, 2).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
    }

    // ------------------------------------------------------------------
    // Cosine matrices (memo §5 item 4, zero-vector PI ruling)
    // ------------------------------------------------------------------

    #[test]
    fn golden_cosine_matrices_with_zero_column() {
        // Columns: a=(1,0), b=(0,1), c=(1,1), z=(0,0).
        // sim: d(a,c) = 1/√2; every pair involving z is 0 (PI ruling — the
        // declared divergence from the upstream cdist NaN); d(a,b) = 0.
        let x = stack2(&[(1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (0.0, 0.0)]);
        let sim = cosine_similarity_matrix(&x, 2, 4).unwrap();
        let r2 = 1.0 / 2.0f64.sqrt();
        assert_slice_close(
            &sim,
            &[
                1.0, 0.0, r2, 0.0, //
                0.0, 1.0, r2, 0.0, //
                r2, r2, 1.0, 0.0, //
                0.0, 0.0, 0.0, 0.0,
            ],
        );
        let dist = cosine_distance_matrix(&x, 2, 4).unwrap();
        assert_slice_close(
            &dist,
            &[
                0.0, 1.0, 1.0 - r2, 1.0, //
                1.0, 0.0, 1.0 - r2, 1.0, //
                1.0 - r2, 1.0 - r2, 0.0, 1.0, //
                1.0, 1.0, 1.0, 1.0,
            ],
        );
        // Cross similarity: a-columns vs b-columns.
        let cross = cross_cosine_similarity(&x, &stack2(&[(1.0, 1.0), (0.0, 0.0)]), 2, 4, 2)
            .unwrap();
        assert_slice_close(
            &cross,
            &[
                r2, 0.0, //
                r2, 0.0, //
                1.0, 0.0, //
                0.0, 0.0,
            ],
        );
    }

    #[test]
    fn cosine_distance_matrix_is_symmetric_and_nonnegative_random() {
        // Task property items: distances non-negative (clamped similarity),
        // exactly symmetric, all finite, within [0, 2].
        let mut rng = MsRng::from_stream(
            9,
            StreamId {
                replicate: 2,
                rank: 0,
                fold: 0,
            },
        );
        for case in 0..8usize {
            let dim = 3 + case;
            let n = 5;
            let mut x = vec![0.0f64; dim * n];
            for v in x.iter_mut() {
                // Non-negative entries (signature domain), some zero rows.
                if rng.next_u64() % 4 != 0 {
                    *v = ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64) * 10.0;
                }
            }
            let d = cosine_distance_matrix(&x, dim, n).unwrap();
            for i in 0..n {
                for j in 0..n {
                    let v = d[i * n + j];
                    assert!(v.is_finite() && (0.0..=2.0).contains(&v));
                    assert_eq!(v, d[j * n + i], "case {case}: symmetry at ({i},{j})");
                }
            }
        }
    }

    #[test]
    fn cosine_rejects_bad_input() {
        assert_eq!(
            cosine_similarity_matrix(&[1.0, 2.0, 3.0], 2, 2)
                .unwrap_err()
                .topic(),
            "argument"
        );
        let err = cosine_similarity_matrix(&[1.0, f64::NAN], 1, 2).unwrap_err();
        assert_eq!(err.topic(), "na");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
        assert_eq!(cosine_similarity_matrix(&[], 1, 1).unwrap_err().topic(), "argument");
    }

    // ------------------------------------------------------------------
    // Silhouette (memo §5 item 6)
    // ------------------------------------------------------------------

    #[test]
    fn golden_silhouette_two_clusters_hand() {
        // dim = 3 columns: A1=(1,0,0), A2=(0.8,0.6,0) [cluster 0];
        // B1=(0,1,0), B2=(0,0,1) [cluster 1]. Hand-derived:
        // d(A1,A2) = 0.2, d(B1,B2) = 1, d(A2,B1) = 0.4, other cross = 1.
        // s(A1) = 0.8; s(A2) = (0.7 − 0.2)/0.7 = 5/7;
        // s(B1) = (0.7 − 1)/1 = −0.3; s(B2) = (1 − 1)/1 = 0.
        let x: Vec<f64> = vec![
            1.0, 0.8, 0.0, 0.0, // channel 1
            0.0, 0.6, 1.0, 0.0, // channel 2
            0.0, 0.0, 0.0, 1.0, // channel 3
        ];
        let labels = [0usize, 0, 1, 1];
        let sil = silhouette_samples_cosine(&x, 3, 4, &labels).unwrap();
        assert_slice_close(&sil, &[0.8, 5.0 / 7.0, -0.3, 0.0]);
        assert_close(sil.iter().sum::<f64>() / 4.0, 0.30357142857142855);
    }

    #[test]
    fn silhouette_singleton_cluster_is_zero() {
        // sklearn NaN-to-zero rule: a cluster with one member contributes 0.
        let x = stack2(&[(1.0, 0.0), (1.0, 0.0), (0.0, 1.0)]);
        let sil = silhouette_samples_cosine(&x, 2, 3, &[0, 0, 1]).unwrap();
        assert_slice_close(&sil, &[1.0, 1.0, 0.0]);
    }

    #[test]
    fn silhouette_zero_vectors_distance_one() {
        // Zero columns sit at distance 1 from everything (incl. each other).
        let x = stack2(&[(0.0, 0.0), (0.0, 0.0), (1.0, 0.0)]);
        let sil = silhouette_samples_cosine(&x, 2, 3, &[0, 0, 1]).unwrap();
        assert_slice_close(&sil, &[0.0, 0.0, 0.0]);
    }

    #[test]
    fn silhouette_rejects_degenerate_labelings() {
        let x = stack2(&[(1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]);
        // Single label (sklearn ValueError; upstream rank-1 never reaches the
        // kernel — the all-ones convention lives in the consensus driver).
        assert_eq!(
            silhouette_samples_cosine(&x, 2, 3, &[0, 0, 0])
                .unwrap_err()
                .topic(),
            "argument"
        );
        // All-singleton labeling (n_labels == n_samples): the upstream R = 1
        // pathology (silhouette raises → RuntimeError upstream).
        assert_eq!(
            silhouette_samples_cosine(&x, 2, 3, &[0, 1, 2])
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Label out of range.
        assert_eq!(
            silhouette_samples_cosine(&x, 2, 3, &[0, 1, 7])
                .unwrap_err()
                .topic(),
            "argument"
        );
        assert_eq!(
            silhouette_samples_cosine(&x, 2, 3, &[0, 1])
                .unwrap_err()
                .topic(),
            "argument"
        );
    }

    // ------------------------------------------------------------------
    // Consensus: hand-traced goldens (memo §5 items 5, 7, 8, rank-1 rule)
    // ------------------------------------------------------------------

    /// Two replicates × k = 2 of identical perfect structure: columns
    /// [(1,0), (0,1) | (1,0), (0,1)] over dim = 2.
    fn perfect_fixture() -> Vec<f64> {
        stack2(&[(1.0, 0.0), (0.0, 1.0), (1.0, 0.0), (0.0, 1.0)])
    }

    #[test]
    fn golden_consensus_two_replicates_k2_hand() {
        // Round 1: unique assignment (d = 0 against the matching centroid);
        // means stay (1,0)/(0,1); every silhouette 1 → round 2 average
        // equals round 1 exactly → stop. Memo §5 item 5 (iteration sequence,
        // equal-stop).
        let fit = consensus_from_centroids(
            &perfect_fixture(),
            2,
            2,
            &stack2(&[(1.0, 0.0), (0.0, 1.0)]),
            10,
        )
        .unwrap();
        assert_eq!(fit.labels, vec![0, 1, 0, 1]);
        assert_eq!(fit.centroids, stack2(&[(1.0, 0.0), (0.0, 1.0)]));
        assert_eq!(fit.silhouette, vec![1.0, 1.0, 1.0, 1.0]);
        assert_eq!(fit.cluster_stability, vec![1.0, 1.0]);
        assert_eq!(fit.avg_stability, 1.0);
        assert!(fit.converged);
        assert_eq!(fit.n_rounds, 2);
    }

    #[test]
    fn golden_consensus_crossed_start_relabels_clusters() {
        // Crossed initial centroids ((0,1),(1,0)): Hungarian re-maps every
        // replicate onto the swapped clusters; the labels follow the
        // assignment (members move with their centroid), proving the
        // reassignment relabels clusters rather than the data.
        let fit = consensus_from_centroids(
            &perfect_fixture(),
            2,
            2,
            &stack2(&[(0.0, 1.0), (1.0, 0.0)]),
            10,
        )
        .unwrap();
        assert_eq!(fit.labels, vec![1, 0, 1, 0]);
        assert_eq!(fit.centroids, stack2(&[(0.0, 1.0), (1.0, 0.0)]));
        assert_eq!(fit.silhouette, vec![1.0, 1.0, 1.0, 1.0]);
        assert!(fit.converged);
        assert_eq!(fit.n_rounds, 2);
    }

    #[test]
    fn golden_consensus_rank1_all_ones_convention() {
        // Rank 1: silhouette undefined → all 1.0 by convention (Sub:1050);
        // centroid = mean of the three replicate signatures. Restart-path
        // tie: every restart produces the identical trajectory, so the max
        // selection keeps the FIRST restart (memo §5 item 7 tie fixture).
        let x = stack2(&[(1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]);
        let fit = consensus_cluster(
            &x,
            2,
            1,
            ConsensusConfig {
                master_seed: 7,
                n_restarts: 3,
                max_rounds: 10,
            },
        )
        .unwrap();
        assert_eq!(fit.labels, vec![0, 0, 0]);
        assert_eq!(fit.silhouette, vec![1.0, 1.0, 1.0]);
        assert_eq!(fit.cluster_stability, vec![1.0]);
        assert_eq!(fit.avg_stability, 1.0);
        assert!(fit.converged);
        assert_eq!(fit.n_rounds, 2);
        assert_eq!(fit.best_restart, 0);
        assert_eq!(fit.restart_avgs, vec![1.0, 1.0, 1.0]);
        // Centroid = mean = (2/3, 2/3), computed in replicate order.
        assert_slice_close(&fit.centroids, &[2.0 / 3.0, 2.0 / 3.0]);
    }

    #[test]
    fn consensus_restarts_take_strict_maximum() {
        // Memo §5 item 7 (max side): with heterogeneous restarts the winner
        // is the first argmax of the restart averages; the bookkeeping is
        // self-consistent. Also pins the frozen stream-driven outcome of
        // this fixture (numeric-protocol golden).
        let mut x = vec![0.0f64; 3 * 6]; // dim = 3, k_total = 6 (k = 2, R = 3)
        let cols: [(usize, [f64; 3]); 6] = [
            (0, [1.0, 0.2, 0.0]),
            (1, [0.1, 1.0, 0.3]),
            (2, [0.9, 0.3, 0.05]),
            (3, [0.0, 0.9, 0.4]),
            (4, [1.0, 0.1, 0.2]),
            (5, [0.2, 1.0, 0.1]),
        ];
        for (j, v) in cols {
            for (r, &val) in v.iter().enumerate() {
                x[r * 6 + j] = val;
            }
        }
        let config = ConsensusConfig {
            master_seed: 42,
            n_restarts: 8,
            max_rounds: 10,
        };
        let fit = consensus_cluster(&x, 3, 2, config.clone()).unwrap();
        // Winner = first argmax of the restart averages (strict > rule).
        let mut argmax = 0usize;
        for r in 1..fit.restart_avgs.len() {
            if fit.restart_avgs[r] > fit.restart_avgs[argmax] {
                argmax = r;
            }
        }
        assert_eq!(fit.best_restart, argmax);
        assert_close(fit.avg_stability, fit.restart_avgs[fit.best_restart]);
        assert_eq!(fit.restart_avgs.len(), 8);
        assert!(fit.n_rounds <= 11, "round cap: {}", fit.n_rounds);
        // Each cluster holds exactly one signature per replicate.
        for c in 0..2 {
            assert_eq!(fit.cluster_stability.len(), 2);
            let members: Vec<usize> = fit
                .labels
                .iter()
                .enumerate()
                .filter(|(_, &l)| l == c)
                .map(|(i, _)| i)
                .collect();
            assert_eq!(members.len(), 3);
            // Members span distinct replicate blocks.
            let blocks: Vec<usize> = members.iter().map(|i| i / 2).collect();
            let mut sorted = blocks.clone();
            sorted.sort_unstable();
            sorted.dedup();
            assert_eq!(sorted, vec![0, 1, 2]);
        }
        // Centroids are the exact means of the returned labels (same
        // reduction order → bit-identical).
        for c in 0..2 {
            for row in 0..3 {
                let sum: f64 = (0..6)
                    .filter(|&j| fit.labels[j] == c)
                    .map(|j| x[row * 6 + j])
                    .sum();
                assert_eq!(fit.centroids[row * 2 + c], sum / 3.0);
            }
        }
        // Determinism: identical config → bit-identical fit.
        let again = consensus_cluster(&x, 3, 2, config).unwrap();
        assert_eq!(fit, again);
    }

    #[test]
    fn consensus_round_cap_stops_after_one_round_when_max_is_zero() {
        // Upstream counting: `convergence_count == 10` breaks AFTER a round
        // whose average differs from the previous — with max_rounds = 0 the
        // very first round trips the cap (deterministic cap pin, memo §5
        // item 5 "10 次上限").
        let fit = consensus_from_centroids(
            &perfect_fixture(),
            2,
            2,
            &stack2(&[(1.0, 0.0), (0.0, 1.0)]),
            0,
        )
        .unwrap();
        assert_eq!(fit.n_rounds, 1);
        assert!(!fit.converged);
        // The reported state is still the last round's consistent triple.
        assert_eq!(fit.labels, vec![0, 1, 0, 1]);
        assert_eq!(fit.avg_stability, 1.0);
    }

    #[test]
    fn consensus_validation_errors() {
        // k = 0 / dim = 0.
        assert_eq!(
            consensus_cluster(&[1.0], 1, 0, ConsensusConfig::default())
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Length not a multiple of dim.
        assert_eq!(
            consensus_cluster(&[1.0, 2.0, 3.0], 2, 1, ConsensusConfig::default())
                .unwrap_err()
                .topic(),
            "argument"
        );
        // k_total not divisible by k.
        assert_eq!(
            consensus_cluster(&[1.0, 2.0, 3.0, 4.0], 2, 3, ConsensusConfig::default())
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Fewer than two replicates (k_total == k): the upstream silhouette
        // raise, surfaced as a structured error.
        assert_eq!(
            consensus_cluster(
                &[1.0, 2.0, 3.0, 4.0],
                2,
                2,
                ConsensusConfig::default()
            )
            .unwrap_err()
            .topic(),
            "argument"
        );
        // Zero restarts.
        assert_eq!(
            consensus_cluster(
                &perfect_fixture(),
                2,
                2,
                ConsensusConfig {
                    master_seed: 1,
                    n_restarts: 0,
                    max_rounds: 10
                }
            )
            .unwrap_err()
            .topic(),
            "argument"
        );
        // Non-finite entry.
        let bad = vec![f64::NAN, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0];
        assert_eq!(
            consensus_cluster(&bad, 2, 2, ConsensusConfig::default())
                .unwrap_err()
                .topic(),
            "na"
        );
        // Explicit-start entry point: initial centroid length mismatch.
        assert_eq!(
            consensus_from_centroids(&perfect_fixture(), 2, 2, &[1.0, 0.0], 10)
                .unwrap_err()
                .topic(),
            "argument"
        );
    }

    // ------------------------------------------------------------------
    // Split/merge classification (memo §5 items 10-12, ≥ 6 goldens)
    // ------------------------------------------------------------------

    /// Classify a small fixture and return (classes, per-reference) for the
    /// single-threshold case.
    fn classify_once(
        estimated_cols: &[(f64, f64)],
        reference_cols: &[(f64, f64)],
        tau: f64,
    ) -> ThresholdMatch {
        let est = stack2(estimated_cols);
        let reff = stack2(reference_cols);
        let mut out =
            match_solutions(&est, &reff, 2, &[tau]).unwrap();
        assert_eq!(out.len(), 1);
        out.remove(0)
    }

    #[test]
    fn golden_split_two_fragments_one_truth() {
        // Memo §5 item 10: one truth (T0) with two over-split fragments.
        // T0=(1,0), T1=(0,1); e0=(2,0)→T0 TP, e3=(0,5)→T1 TP,
        // e1=(7,1) cos(T0)=7/√50≈0.990, e2=(6,1) cos(T0)=6/√37≈0.986 —
        // both non-TP, argmax T0, top-2 far below τ → Split{T0} twice.
        let m = classify_once(
            &[(2.0, 0.0), (7.0, 1.0), (6.0, 1.0), (0.0, 5.0)],
            &[(1.0, 0.0), (0.0, 1.0)],
            0.8,
        );
        assert_eq!(m.tp, vec![(0, 0), (3, 1)]);
        assert_eq!(m.fp, 2);
        assert_eq!(m.fn_count, 0);
        assert_eq!(m.split_count, 2);
        assert_eq!(m.merge_count, 0);
        assert_eq!(
            m.estimated_classes,
            vec![
                EstimatedClass::Matched { reference: 0 },
                EstimatedClass::Split { reference: 0 },
                EstimatedClass::Split { reference: 0 },
                EstimatedClass::Matched { reference: 1 },
            ]
        );
        assert_eq!(m.references[0].matched_estimated, Some(0));
        assert_eq!(m.references[0].fragments, vec![1, 2]);
        assert_eq!(m.references[1].matched_estimated, Some(3));
        assert!(m.references[1].fragments.is_empty());
    }

    #[test]
    fn golden_split_boundary_cos_equal_tau_counts() {
        // Memo §5 item 10 boundary pin: cos(e2, T0) = 4/5 = 0.8 exactly;
        // τ = 0.8 → ≥ semantics → Split; τ = 0.81 → Novel. (0.8 computed as
        // 4/5 is the same f64 as the literal 0.8, so the boundary is exact.)
        let est = stack2(&[(5.0, 0.0), (0.0, 3.0), (4.0, 3.0)]);
        let reff = stack2(&[(1.0, 0.0), (0.0, 1.0)]);
        let sweep = match_solutions(&est, &reff, 2, &[0.8, 0.81]).unwrap();
        assert_eq!(sweep.len(), 2);
        assert_eq!(
            sweep[0].estimated_classes[2],
            EstimatedClass::Split { reference: 0 }
        );
        assert_eq!(sweep[0].split_count, 1);
        assert_eq!(sweep[0].fp, 1);
        assert_eq!(sweep[0].fn_count, 0);
        assert_eq!(sweep[1].estimated_classes[2], EstimatedClass::Novel);
        assert_eq!(sweep[1].split_count, 0);
        assert_eq!(sweep[1].fp, 1);
        // TP pairs are threshold-stable here: both TP pairs have cos 1.0.
        assert_eq!(sweep[0].tp, sweep[1].tp);
        assert_eq!(sweep[0].pairs, sweep[1].pairs);
    }

    #[test]
    fn golden_merge_top2_both_above_tau() {
        // Memo §5 item 11: T0=(3,4), T1=(4,3) (cos 0.96 apart); the blend
        // s=(7,7) has cos 7/(5√2) ≈ 0.990 with BOTH truths → Merge.
        // The pure signatures e0=(6,8), e1=(8,6) win the Hungarian pairs
        // (cost 0 each), so s is non-TP and row-classified. The top-2 tie is
        // exact (49 = 21+28 = 28+21 in both orders) and resolves to
        // distinct indices: argmax first.
        let m = classify_once(
            &[(6.0, 8.0), (8.0, 6.0), (7.0, 7.0)],
            &[(3.0, 4.0), (4.0, 3.0)],
            0.9,
        );
        assert_eq!(m.tp, vec![(0, 0), (1, 1)]);
        assert_eq!(
            m.estimated_classes[2],
            EstimatedClass::Merge { references: [0, 1] }
        );
        assert_eq!(m.merge_count, 1);
        assert_eq!(m.split_count, 0);
        assert_eq!(m.fp, 1);
        assert_eq!(m.fn_count, 0);
        assert_eq!(m.references[0].merges, vec![2]);
        assert_eq!(m.references[1].merges, vec![2]);
    }

    #[test]
    fn merge_needs_two_truths_above_tau() {
        // Memo §5 item 11 negative: only ONE truth ≥ τ → not a merge; the
        // strong truth is claimed by a TP pair → Split. At τ = 0.85 the
        // single strong truth drops below τ → Novel.
        // s=(5,0): cos(T1)=0.8, cos(T0)=0.6 (T0=(3,4), T1=(4,3)).
        let m075 = classify_once(
            &[(6.0, 8.0), (8.0, 6.0), (5.0, 0.0)],
            &[(3.0, 4.0), (4.0, 3.0)],
            0.75,
        );
        assert_eq!(
            m075.estimated_classes[2],
            EstimatedClass::Split { reference: 1 }
        );
        assert_eq!(m075.merge_count, 0);
        let m085 = classify_once(
            &[(6.0, 8.0), (8.0, 6.0), (5.0, 0.0)],
            &[(3.0, 4.0), (4.0, 3.0)],
            0.85,
        );
        assert_eq!(m085.estimated_classes[2], EstimatedClass::Novel);
        assert_eq!(m085.fp, 1);
    }

    #[test]
    fn tp_member_is_never_row_classified() {
        // "只看行，不改指派" applies only to non-TP signatures: e0 has top-2
        // = (1.0, 0.96) both ≥ 0.9 and is STILL Matched, not Merge.
        let m = classify_once(
            &[(6.0, 8.0), (8.0, 6.0), (7.0, 7.0)],
            &[(3.0, 4.0), (4.0, 3.0)],
            0.9,
        );
        assert_eq!(m.estimated_classes[0], EstimatedClass::Matched { reference: 0 });
        assert_eq!(m.estimated_classes[1], EstimatedClass::Matched { reference: 1 });
    }

    #[test]
    fn golden_threshold_sweep_classification_vectors() {
        // Memo §5 item 12: τ ∈ {0.80, …, 0.90} step 0.01, per-τ
        // classification vector pinned (shared data plane with U-M2-07).
        // T0=(1,0), T1=(0.6,0.8); s=(1.6,1.2): cos(s,T1) = 0.96,
        // cos(s,T0) = 0.8 exactly; e0=(2,0)→T0 TP (1.0), e1=(6,8)→T1 TP (1.0).
        //
        // GOLDEN FIX (2026-09-30, green pass): the original e1 was (0, 5),
        // giving cos(e1, T1) = 4/5 (cost 0.2) while e2→T1 costs 1 − 0.96 =
        // 0.04 — the min-cost assignment (memo §1.5, pinned by goldens 1–3)
        // provably assigns T1 to e2, i.e. pairs = [(0,0), (2,1)], so the
        // pinned expectation pairs/tp = [(0,0), (1,1)] was not optimal and
        // unreachable by any correct implementation. e1 is corrected to
        // (6, 8) — exactly parallel to T1, cos = 1, cost 0 — which makes the
        // intended pure-pair assignment the unique optimum (total 0 is
        // unbeatable) and leaves e2's similarity row [0.8, 0.96], and hence
        // every pinned per-τ classification vector, exactly as derived.
        let est = stack2(&[(2.0, 0.0), (6.0, 8.0), (1.6, 1.2)]);
        let reff = stack2(&[(1.0, 0.0), (0.6, 0.8)]);
        let thresholds: Vec<f64> = (0..=10).map(|i| 0.80 + 0.01 * i as f64).collect();
        let sweep = match_solutions(&est, &reff, 2, &thresholds).unwrap();
        assert_eq!(sweep.len(), 11);
        for (i, m) in sweep.iter().enumerate() {
            let tau = &thresholds[i];
            // Assignment and TP are τ-independent on this fixture.
            assert_eq!(m.pairs, vec![(0, 0), (1, 1)]);
            assert_eq!(m.tp, vec![(0, 0), (1, 1)]);
            assert_eq!(m.fp, 1);
            assert_eq!(m.fn_count, 0);
            assert_eq!(m.estimated_classes[0], EstimatedClass::Matched { reference: 0 });
            assert_eq!(m.estimated_classes[1], EstimatedClass::Matched { reference: 1 });
            if *tau <= 0.80 {
                // 0.8 ≥ τ (boundary inclusive) AND 0.96 ≥ τ → merge.
                assert_eq!(
                    m.estimated_classes[2],
                    EstimatedClass::Merge { references: [1, 0] },
                    "τ = {tau}"
                );
                assert_eq!(m.merge_count, 1);
                assert_eq!(m.split_count, 0);
            } else {
                // top-2 < τ, top-1 = 0.96 ≥ τ (≤ 0.90) → split of T1.
                assert_eq!(
                    m.estimated_classes[2],
                    EstimatedClass::Split { reference: 1 },
                    "τ = {tau}"
                );
                assert_eq!(m.split_count, 1);
                assert_eq!(m.merge_count, 0);
            }
        }
    }

    #[test]
    fn single_reference_never_merges() {
        // q = 1: no second truth exists → merge is structurally impossible;
        // a strong non-TP signature is a Split fragment.
        let m = classify_once(&[(1.0, 0.0), (4.0, 3.0)], &[(1.0, 0.0)], 0.8);
        assert_eq!(m.tp, vec![(0, 0)]);
        assert_eq!(
            m.estimated_classes[1],
            EstimatedClass::Split { reference: 0 }
        );
        assert_eq!(m.references[0].fragments, vec![1]);
        assert_eq!(m.fn_count, 0);
    }

    #[test]
    fn fn_reference_covered_by_fragment_is_diagnostic_only() {
        // GOLDEN FIX (2026-09-30, green pass). The original fixture
        // (T2 = (−1, 0), s = (−5, 0), cos = +1) asserted tp = {(0,0),(1,1)}
        // while also asserting s ∉ TP as a Split fragment of T2 — mutually
        // unsatisfiable: tp = {(0,0),(1,1)} pins the 3×3 one-to-one
        // assignment to the identity (σ(2) = 2 by elimination), so the
        // assigned pair (2, 2) with cos(s, T2) = 1 ≥ τ is necessarily a TP
        // and fn would be 0, not 1. (More generally, a reference that is the
        // ≥τ argmax of a non-TP estimated signature in the *matched* sense
        // can only fail to be TP if the optimal assignment pairs it below τ
        // — the module-docs swap argument.) To realize the test's stated
        // intent — a FN reference that is the argmax of a non-TP signature,
        // with the diagnostic never touching TP/FN — T2 is rotated to
        // (−1, 1), giving cos(s, T2) = 1/√2 ≈ 0.707 < τ: the identity
        // assignment keeps (2,2) at cost 1 − 1/√2 (unique optimum), that pair
        // lands below τ, T2 is FN, s's row argmax is still T2 (0.707 > 0 =
        // cos(s, T1) > −1 = cos(s, T0)) → covered_fn set, class Novel.
        let est_cols: [(f64, f64); 3] = [(2.0, 0.0), (0.0, 3.0), (-5.0, 0.0)];
        let reff_cols: [(f64, f64); 3] = [(1.0, 0.0), (0.0, 1.0), (-1.0, 1.0)];
        let est = stack2(&est_cols);
        let reff = stack2(&reff_cols);
        let m = match_solutions(&est, &reff, 2, &[0.8]).unwrap().remove(0);
        assert_eq!(m.tp, vec![(0, 0), (1, 1)]);
        assert_eq!(m.fp, 1);
        assert_eq!(m.fn_count, 1);
        // argmax below τ → Novel (the "covered" diagnostic is argmax-based,
        // memo §1.5, and never changes TP/FN).
        assert_eq!(m.estimated_classes[2], EstimatedClass::Novel);
        assert_eq!(m.references[2].matched_estimated, None);
        assert!(m.references[2].fragments.is_empty());
        assert!(m.references[2].covered_fn);
        // The matched references are not FN and not covered.
        assert!(!m.references[0].covered_fn);
        assert!(!m.references[1].covered_fn);
    }

    #[test]
    fn match_solutions_rejects_bad_input() {
        let est = stack2(&[(1.0, 0.0)]);
        let reff = stack2(&[(1.0, 0.0)]);
        // Storage mismatch.
        assert_eq!(
            match_solutions(&[1.0, 2.0, 3.0], &reff, 2, &[0.8])
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Non-finite threshold.
        assert_eq!(
            match_solutions(&est, &reff, 2, &[f64::NAN])
                .unwrap_err()
                .topic(),
            "argument"
        );
        // Non-finite entry.
        let bad = stack2(&[(f64::NAN, 1.0)]);
        assert_eq!(
            match_solutions(&bad, &reff, 2, &[0.8]).unwrap_err().topic(),
            "na"
        );
        // Empty threshold sweep is allowed (no work).
        assert!(match_solutions(&est, &reff, 2, &[]).unwrap().is_empty());
    }
}
