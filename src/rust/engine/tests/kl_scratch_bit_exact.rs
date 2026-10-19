//! P3 lane bit-exactness law for the optimized certified KL loop.
//!
//! The parity-plan P3 charter (docs/research/09-sigminer-v3-parity-plan.md,
//! lane 3) authorizes engineering the certified-loop hot path — hoisting
//! loop-invariant statistics, reusing buffers, restructuring the element
//! passes — under one predicate: the certified loop's BYTES may not move.
//! This file is that predicate, committed before the optimization itself
//! (red-by-absence against `KlScratch` / `fit_kl_with_init_scratch`).
//!
//! Method: a frozen reference twin — a verbatim copy of the committed
//! scalar path (`matmul`, `kl_h_step`, `kl_w_step`, `kl_objective`, and the
//! `fit_kl_with_init` loop body) — run beside the live faces over the real
//! cell shape (96x100) at every certified rank, on synthetic count grids
//! (synthetic provider only: in-house PCG64 streams, no external data).
//! Equality is `assert_eq!` on the f64 vectors: bit-for-bit, no tolerance,
//! for the public certified face AND the new scratch-passing face, and for
//! a REUSED scratch serving a second fit (buffer reuse must carry no state).
//!
//! The twin is frozen text: if the certified scalar path is ever
//! re-derived, this file must be re-derived with it in the same change.

use msuiter_engine::nmf::{fit_kl_with_init, fit_kl_with_init_scratch, KlScratch, NmfFit, KL_EPS};
use msuiter_engine::nndsvd::nndsvd_init;
use msuiter_engine::rng::{MsRng, StreamId};

// ======================================================================
// Frozen reference twin: verbatim from engine/src/nmf.rs @ main@1673a7f.
// Do not edit these five bodies; they are the law's fixed side.
// ======================================================================

fn matmul(w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> Vec<f64> {
    let mut out = vec![0.0f64; m * n];
    for i in 0..m {
        let wrow = &w[i * k..i * k + k];
        for (s, &ws) in wrow.iter().enumerate() {
            if ws == 0.0 {
                continue;
            }
            let hrow = &h[s * n..s * n + n];
            for (j, &hvj) in hrow.iter().enumerate() {
                out[i * n + j] += ws * hvj;
            }
        }
    }
    out
}

fn kl_h_step(v: &[f64], w: &[f64], h: &mut [f64], m: usize, n: usize, k: usize) {
    let wh = matmul(w, h, m, n, k);
    // num[s][j] = Σ_i W[i][s] · V[i][j]/max(WH[i][j], ε)
    let mut num = vec![0.0f64; k * n];
    for i in 0..m {
        let wrow = &w[i * k..i * k + k];
        for j in 0..n {
            let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
            if r != 0.0 {
                for (s, &ws) in wrow.iter().enumerate() {
                    num[s * n + j] += ws * r;
                }
            }
        }
    }
    // den[s][j] = Σ_i W[i][s]  (W column sums — independent of j)
    for s in 0..k {
        let mut col = 0.0f64;
        for i in 0..m {
            col += w[i * k + s];
        }
        let den = col.max(KL_EPS);
        for j in 0..n {
            h[s * n + j] *= num[s * n + j] / den;
        }
    }
}

fn kl_w_step(v: &[f64], w: &mut [f64], h: &[f64], m: usize, n: usize, k: usize) {
    let wh = matmul(w, h, m, n, k);
    for i in 0..m {
        for s in 0..k {
            let mut num = 0.0f64;
            for j in 0..n {
                let r = v[i * n + j] / wh[i * n + j].max(KL_EPS);
                num += r * h[s * n + j];
            }
            // den[s] = Σ_j H[s][j] (H row sums — independent of i)
            let mut den = 0.0f64;
            for j in 0..n {
                den += h[s * n + j];
            }
            w[i * k + s] *= num / den.max(KL_EPS);
        }
    }
}

fn kl_objective(v: &[f64], w: &[f64], h: &[f64], m: usize, n: usize, k: usize) -> f64 {
    let wh = matmul(w, h, m, n, k);
    let mut acc = 0.0f64;
    for (&vv, &mm) in v.iter().zip(wh.iter()) {
        acc += vv * ((KL_EPS + vv).ln() - (KL_EPS + mm).ln()) - vv + mm;
    }
    acc
}


fn ref_fit(
    v: &[f64],
    m: usize,
    n: usize,
    k: usize,
    w0: &[f64],
    h0: &[f64],
    max_iter: usize,
) -> NmfFit {
    // The loop body of the committed `fit_kl_with_init`, verbatim.
    let mut w = w0.to_vec();
    let mut h = h0.to_vec();
    let mut objective = Vec::with_capacity(max_iter + 1);
    objective.push(kl_objective(v, &w, &h, m, n, k));
    for _ in 0..max_iter {
        kl_h_step(v, &w, &mut h, m, n, k);
        kl_w_step(v, &mut w, &h, m, n, k);
        objective.push(kl_objective(v, &w, &h, m, n, k));
    }
    NmfFit { w, h, objective, iterations: max_iter }
}

// ======================================================================
// Synthetic fixtures: real cell shape, in-house streams, count grids.
// ======================================================================

fn uniform(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
}

/// Integer-valued counts in {0, ..., 39}; `positive` drops the structural
/// zeros (the real cell grids are fully dense, banked P3-PROF-1 sparsity
/// census), so both regimes the loop branches on are on the table.
fn counts(rng: &mut MsRng, m: usize, n: usize, positive: bool) -> Vec<f64> {
    (0..m * n)
        .map(|_| {
            let x = (uniform(rng) * 40.0).floor();
            if positive && x == 0.0 {
                1.0
            } else {
                x
            }
        })
        .collect()
}

const M: usize = 96;
const N: usize = 100;
const ITERS: usize = 2000; // the certified length: the law pins IT, not a proxy

fn assert_fit_eq(got: &NmfFit, want: &NmfFit, face: &str, tag: &str) {
    assert_eq!(got.w, want.w, "{face} W differs [{tag}]");
    assert_eq!(got.h, want.h, "{face} H differs [{tag}]");
    assert_eq!(got.objective, want.objective, "{face} objective differs [{tag}]");
    assert_eq!(got.iterations, want.iterations, "{face} iterations drifted [{tag}]");
}

#[test]
fn kl_certified_loop_is_bit_identical_over_the_rank_lattice() {
    for &positive in &[true, false] {
        for &k in &[2usize, 3, 4, 5] {
            let mut rng = MsRng::from_stream(20261019, StreamId { replicate: 3, rank: k as u64, fold: 0 });
            let v = counts(&mut rng, M, N, positive);
            let (w0, h0) = nndsvd_init(&v, M, N, k, 20261019).expect("init");
            let tag = format!("k={k} positive={positive}");
            let want = ref_fit(&v, M, N, k, &w0, &h0, ITERS);

            // (a) the public certified face
            let public = fit_kl_with_init(&v, M, N, k, &w0, &h0, ITERS).expect("public fit");
            assert_fit_eq(&public, &want, "public", &tag);

            // (b) the scratch face, first use of a fresh scratch
            let mut scr = KlScratch::new(M, N, k);
            let first = fit_kl_with_init_scratch(&v, M, N, k, &w0, &h0, ITERS, &mut scr)
                .expect("scratch fit");
            assert_fit_eq(&first, &want, "scratch", &tag);

            // (c) the SAME scratch reused for a second, independent fit:
            // buffer reuse is the lane's promise, state leakage is its bug.
            let second = fit_kl_with_init_scratch(&v, M, N, k, &w0, &h0, ITERS, &mut scr)
                .expect("scratch re-fit");
            assert_fit_eq(&second, &want, "scratch-reuse", &tag);
        }
    }
}

#[test]
fn scratch_retargeted_to_another_rank_serves_bit_exactly() {
    // A scratch born for one rank lattice point and pressed into another
    // (what a batch face walking k = 2..5 across one scratch would do)
    // must still reproduce the reference bytes.
    let mut rng = MsRng::from_stream(20261020, StreamId { replicate: 9, rank: 0, fold: 0 });
    let v = counts(&mut rng, M, N, true);
    let (w0, h0) = nndsvd_init(&v, M, N, 3, 20261020).expect("init");
    let want = ref_fit(&v, M, N, 3, &w0, &h0, 400);
    let mut scr = KlScratch::new(M, N, 2);
    let got = fit_kl_with_init_scratch(&v, M, N, 3, &w0, &h0, 400, &mut scr)
        .expect("retargeted scratch fit");
    assert_fit_eq(&got, &want, "scratch-retarget", "2->3");
    // and once more, now that the scratch has grown to this shape
    let again = fit_kl_with_init_scratch(&v, M, N, 3, &w0, &h0, 400, &mut scr)
        .expect("retargeted re-fit");
    assert_fit_eq(&again, &want, "scratch-retarget-reuse", "3x3");
}

#[test]
fn scratch_rejects_mismatched_lengths_fail_closed() {
    // A scratch sized right but fed wrong-size v/w0/h0 must return the
    // same validation faults as the certified face, never corrupt silence.
    let mut rng = MsRng::from_stream(20261021, StreamId { replicate: 1, rank: 0, fold: 0 });
    let v = counts(&mut rng, 8, 6, true);
    let (w0, mut h0) = nndsvd_init(&v, 8, 6, 2, 20261021).expect("init");
    h0.pop(); // now the wrong length: the validation law must fire
    let mut scr = KlScratch::new(8, 6, 2);
    assert!(
        fit_kl_with_init_scratch(&v, 8, 6, 2, &w0, &h0, 4, &mut scr).is_err(),
        "a right scratch fed wrong-size storage must fault, never pass silently"
    );
}
