//! GMM hypermutant stratification core (M2 pipeline plan slot, FFI wiring of
//! U-M1c-02): the pure (R-type-free) heart of `ms_stratify_rust` behind the
//! user-facing `ms_stratify_hypermutants()` (`R/stratify.R`).
//!
//! The unit is deliberately thin plumbing over `engine::stats`: the frozen
//! cutoff rule ([`msuiter_engine::stats::normalization_cutoff`]) and the
//! classification predicate
//! ([`msuiter_engine::stats::classify_hypermutants`]) are called with ZERO
//! semantic change — the FFI face adds only the counts-domain validation and
//! the result shape. The pure-R protocol twin (`msuiter_stratify_twin`,
//! `R/stratify.R`) stays in the package as the reference implementation; the
//! test battery pins twin and FFI to identical integer outcomes.
//!
//! # Layout contract (the column-sum trap)
//!
//! `counts` arrives as the column-major flat buffer of the R `m×n` matrix
//! (m channels × n samples) — NO transposition on either side (unlike
//! `extract.rs`): channel `i` of sample `j` is `data[j*m + i]`, so the
//! per-sample totals are the sums `sum_i data[j*m + i]`. A transposed
//! handoff would sum samples per channel instead; the layout guard is the
//! asymmetric-golden discipline — the same cohort is run through a 1×n
//! reference matrix and an m×n matrix (m ≠ 1 ≠ n) that must agree bit for
//! bit, which a transposed read cannot.
//!
//! # Counts domain (contract 4)
//!
//! Mutation counts are non-negative integers. The R wrapper validates the
//! first layer (matrix-ness, REALSXP, anyNA); this core is the second:
//! every cell must be finite (topic `na`, 1-based i/j) and a non-negative
//! integer-valued double (topic `argument`, 1-based i/j). Integer-valued
//! inputs make the column sums exact in any accumulation order, so the
//! kernel totals match R's `colSums` bit for bit.
//!
//! # Threads and interrupt (contracts 6/7, declared decision)
//!
//! One cutoff rule run is a fixed-order sequential computation over n
//! scalars (EM capped at 200 iterations, prune loop bounded by n): there is
//! nothing to parallelize (A7, trivially thread-invariant) and no chunk
//! structure to poll — the export is declared bounded-duration and
//! non-interruptible, same decision as `ms_extract_rust`. `n_threads` is
//! validated (≥ 0) for surface stability and otherwise unused.
//!
//! # Wire shape (0-based decision, documented)
//!
//! The result reports `hypermutant_idx` as **0-based** ascending sample
//! indices (`Vec<i32>`, the Rust-native convention): the R wrapper adds 1
//! to index sample names. `cutoff` crosses as a double holding an integer
//! value (u64 domain, R doubles are exact to 2^53).

use msuiter_engine::error::MsError;
use msuiter_engine::stats;

/// The stratification decision: the frozen cutoff, the 0-based indices of
/// the hypermutated samples (`total > cutoff`, strict), and the cutoff
/// diagnostics of the retained bulk.
#[derive(Debug, Clone, PartialEq)]
pub struct StratifyDecision {
    /// The cutoff in mutations per sample (integer, `manual_cutoff` floor
    /// applied) — as returned by the engine's `normalization_cutoff`.
    pub cutoff: u64,
    /// 0-based ascending indices of the hypermutated samples, from
    /// `engine::stats::classify_hypermutants` (strictly-greater predicate).
    pub hypermutant_idx: Vec<i32>,
    /// The retained-bulk diagnostics (mean, sd, retained_n, n_fits,
    /// converged) — the "cluster stats" of the rule run.
    pub cluster: stats::CutoffFit,
}

/// Validate one count cell: finite, non-negative, integer-valued. `i`/`j`
/// are the 1-based (row, column) coordinates of the cell in the incoming
/// column-major matrix.
fn validate_cell(v: f64, i: usize, j: usize) -> Result<(), MsError> {
    if !v.is_finite() {
        // Contract 3, second layer: the R anyNA validator is the first; Inf
        // passes anyNA and is caught here.
        return Err(MsError::new(
            "na",
            format!(
                "counts must be finite (no NA/NaN/Inf); offender at 1-based position ({i}, {j})"
            ),
        )
        .with_i(i as i64)
        .with_j(j as i64));
    }
    if v < 0.0 {
        return Err(MsError::new(
            "argument",
            format!("counts must be non-negative; offender at 1-based position ({i}, {j})"),
        )
        .with_i(i as i64)
        .with_j(j as i64));
    }
    if v.fract() != 0.0 {
        return Err(MsError::new(
            "argument",
            format!("counts must be integer-valued; offender at 1-based position ({i}, {j})"),
        )
        .with_i(i as i64)
        .with_j(j as i64));
    }
    Ok(())
}

/// Stratify a catalog's samples with the frozen SigProfiler hypermutant
/// rule (M2 FFI wiring of U-M1c-02).
///
/// `counts` is the column-major `m×n` count matrix (m channels × n samples)
/// as marshalled by the FFI adapter from R. The per-sample totals are the
/// column sums (exact for integer-valued counts), the cutoff comes from
/// [`stats::normalization_cutoff`] and the flags from
/// [`stats::classify_hypermutants`] — both engine calls with zero semantic
/// change.
///
/// Errors: no sample columns, a buffer/dimension mismatch, or a count cell
/// outside the counts domain (see the module docs) — all structured
/// `MsError`s, no panics (contract 4).
pub fn stratify(
    counts: &[f64],
    m: usize,
    n: usize,
    manual_cutoff: u64,
    master_seed: u64,
) -> Result<StratifyDecision, MsError> {
    if n == 0 {
        return Err(MsError::new(
            "argument",
            "the counts matrix has no samples to stratify (n = 0 columns)",
        ));
    }
    if counts.len() != m * n {
        return Err(MsError::new(
            "bounds",
            format!(
                "counts buffer has {} entries, expected m*n = {m}*{n} = {}",
                counts.len(),
                m * n
            ),
        ));
    }
    // Counts-domain scan (column-major: flat position k -> row k % m,
    // column k / m), before any summation so a NaN/Inf can never reach the
    // totals.
    for (k, &v) in counts.iter().enumerate() {
        validate_cell(v, k % m + 1, k / m + 1)?;
    }

    // Per-sample totals: sequential ascending-channel sums of each column.
    // Integer-valued cells make these exact, matching R's colSums bit for
    // bit.
    let mut totals = vec![0.0_f64; n];
    for (j, total) in totals.iter_mut().enumerate() {
        let mut acc = 0.0_f64;
        for i in 0..m {
            acc += counts[j * m + i];
        }
        *total = acc;
    }

    // The frozen rule, zero semantic change: one MsRng stream
    // (StreamId::ZERO from the master seed) threaded through every prune
    // iteration, then the strictly-greater classification.
    let cluster = stats::normalization_cutoff(&totals, manual_cutoff, master_seed)?;
    let flags = stats::classify_hypermutants(&totals, cluster.cutoff);
    let hypermutant_idx = flags
        .iter()
        .enumerate()
        .filter(|(_, &f)| f)
        .map(|(i, _)| {
            i32::try_from(i)
                .map_err(|_| MsError::new("bounds", "a sample index exceeds the i32 range"))
        })
        .collect::<Result<Vec<_>, _>>()?;

    Ok(StratifyDecision {
        cutoff: cluster.cutoff,
        hypermutant_idx,
        cluster,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The engine golden's bimodal cohort (44 bulk + 6 hypermutants), as a
    /// 1×n counts matrix (each sample's total in the single channel).
    fn bimodal_1row() -> Vec<f64> {
        let mut v = Vec::with_capacity(50);
        for i in 0..44u64 {
            let t = 4200 + 700 * (i % 13) + 130 * (i % 7) + 40 * (i % 3);
            v.push(t as f64);
        }
        v.extend([81_000.0, 96_000.0, 120_000.0, 133_000.0, 145_000.0, 158_000.0]);
        v
    }

    /// The same cohort spread over 4 channels with all mass in channel 0:
    /// the m > 1 shape of the R catalog fixture (column sums unchanged).
    fn bimodal_4rows() -> Vec<f64> {
        let totals = bimodal_1row();
        let (m, n) = (4usize, totals.len());
        let mut cells = vec![0.0_f64; m * n];
        for (j, &t) in totals.iter().enumerate() {
            cells[j * m] = t;
        }
        cells
    }

    #[test]
    fn golden_bimodal_matches_engine_golden_bit_for_bit() {
        // Engine golden (stats.rs): cutoff 13 804, the 6 injected
        // hypermutants flagged (0-based 44..=49), retained bulk 44.
        let d = stratify(&bimodal_1row(), 1, 50, 0, 1).unwrap();
        assert_eq!(d.cutoff, 13_804);
        assert_eq!(d.hypermutant_idx, vec![44, 45, 46, 47, 48, 49]);
        assert_eq!(d.cluster.retained_n, 44);
        assert_eq!(d.cluster.n_fits, 2);
        assert!(d.cluster.converged);
        assert!((d.cluster.retained_mean - 8_496.129_238).abs() < 1e-6 * 8_496.0);
    }

    #[test]
    fn column_major_layout_guard_multichannel_matches_1row() {
        // The 4×50 matrix (all mass in row 0) must produce the IDENTICAL
        // decision to the 1×50 reference — a transposed handoff sums the
        // wrong axis and cannot pass on this asymmetric shape (m ≠ 1 ≠ n).
        let reference = stratify(&bimodal_1row(), 1, 50, 0, 1).unwrap();
        let matrix = stratify(&bimodal_4rows(), 4, 50, 0, 1).unwrap();
        assert_eq!(matrix, reference);
    }

    #[test]
    fn golden_lone_outlier_is_flagged() {
        // Engine golden: the 500 000 sample (0-based index 40) is pruned
        // from the bulk and flagged; cutoff 6 375.
        let mut v: Vec<f64> = (0..40u64).map(|i| (4800 + 37 * i) as f64).collect();
        v.push(500_000.0);
        let d = stratify(&v, 1, 41, 0, 1).unwrap();
        assert_eq!(d.cutoff, 6_375);
        assert_eq!(d.hypermutant_idx, vec![40]);
        assert_eq!(d.cluster.retained_n, 40);
    }

    #[test]
    fn manual_cutoff_floors_the_derived_value() {
        let d = stratify(&bimodal_1row(), 1, 50, 20_000, 1).unwrap();
        assert_eq!(d.cutoff, 20_000);
        // The floor raises the cutoff, but the injected hypermutants
        // (81 000+) stay strictly above it — still flagged.
        assert_eq!(d.hypermutant_idx, vec![44, 45, 46, 47, 48, 49]);
        let inert = stratify(&bimodal_1row(), 1, 50, 9_600, 1).unwrap();
        assert_eq!(inert.cutoff, 13_804);
    }

    #[test]
    fn degenerate_all_identical_and_single_sample() {
        let same = vec![7_000.0; 30];
        let d = stratify(&same, 1, 30, 0, 1).unwrap();
        assert_eq!(d.cutoff, 7_000);
        assert!(d.hypermutant_idx.is_empty());
        assert_eq!(d.cluster.n_fits, 1);

        let solo = stratify(&[12_345.0], 1, 1, 0, 1).unwrap();
        assert_eq!(solo.cutoff, 12_345, "single sample: cutoff is its own total");
        assert_eq!(solo.hypermutant_idx, Vec::<i32>::new());
        assert_eq!(solo.cluster.n_fits, 0);
    }

    #[test]
    fn determinism_same_seed_is_bit_identical() {
        let a = stratify(&bimodal_4rows(), 4, 50, 9_600, 42).unwrap();
        let b = stratify(&bimodal_4rows(), 4, 50, 9_600, 42).unwrap();
        assert_eq!(a, b);
    }

    // ------------------------------------------------------------------
    // Counts-domain validation (contract 4): structured i/j payloads,
    // 1-based (row, column) of the offending cell.
    // ------------------------------------------------------------------

    #[test]
    fn empty_and_mismatched_inputs_are_structured_errors() {
        let err = stratify(&[], 1, 0, 0, 1).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert!(err.to_string().contains("no samples"));

        let err = stratify(&[1.0, 2.0], 3, 1, 0, 1).unwrap_err();
        assert_eq!(err.topic, "bounds");
    }

    #[test]
    fn non_finite_negative_and_fractional_cells_carry_ij() {
        // NaN at (row 2, col 3) of a 3×4 matrix: flat position 2*3 + 1 = 7.
        let mut cells = vec![1.0_f64; 12];
        cells[7] = f64::NAN;
        let err = stratify(&cells, 3, 4, 0, 1).unwrap_err();
        assert_eq!(err.topic, "na");
        assert_eq!(err.i, Some(2));
        assert_eq!(err.j, Some(3));

        // Inf passes anyNA on the R side and is caught here as `na`.
        let mut cells = vec![1.0_f64; 12];
        cells[7] = f64::INFINITY;
        let err = stratify(&cells, 3, 4, 0, 1).unwrap_err();
        assert_eq!(err.topic, "na");

        // Negative at 1-based (row 1, col 2) of 3×4: flat position 3.
        let mut cells = vec![1.0_f64; 12];
        cells[3] = -5.0;
        let err = stratify(&cells, 3, 4, 0, 1).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));

        // Fractional (out of the counts domain) at 1-based (row 4, col 3)
        // of 4×5: flat position 2*4 + 3 = 11.
        let mut cells = vec![1.0_f64; 20];
        cells[2 * 4 + 3] = 1.5;
        let err = stratify(&cells, 4, 5, 0, 1).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert_eq!(err.i, Some(4));
        assert_eq!(err.j, Some(3));
    }
}
