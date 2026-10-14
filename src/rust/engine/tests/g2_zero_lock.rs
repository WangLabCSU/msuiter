//! P1 kernel-extension face (b): G2 zero-lock hardening.
//!
//! The epsilon policy contract (docs/ARCHITECTURE.md:303 — "no +ε at the
//! catalog layer; the numerical protection enters only the division", and
//! the kernel-side placement in src/rust/engine/src/nmf.rs module docs
//! "ε policy"): `KL_EPS` floors DIVISION DENOMINATORS and log arguments
//! only; it is never added to a factor, never used to floor a factor
//! entry after an update. The distinction is the 1.5.0-class landmine the
//! parity plan names (docs/research/09 §5 row P1: "zero-lock hardening
//! incl. NNDSVD-init regression (G2)"): an implementation that resurrects
//! or clamps dead entries with `max(x, ε)` after each update silently
//! changes the MLE path, reports "converged" while components are frozen
//! onto the floor, and stops at a worse solution.
//!
//! MU semantics make the two sides of the contract observable (nmf.rs:
//! exact zeros in an initializer are absorbing — a zero entry can never
//! become positive again). The plain NNDSVD init is documented zero-keeping
//! (nndsvd.rs `nndsvd_init`: "zeros kept"), so it is the natural probe:
//!   * every init zero must still be an exact 0.0 in the fit (a
//!     resurrection floor would have un-frozen it);
//!   * no factor entry may land exactly on a historical floor constant
//!     (`KL_EPS` itself, or the 2.220446049250313e-16 `pmax.inplace`
//!     bottom the R NMF brunet kernel stamps every 10 steps — documented
//!     protocol difference #1 in tools/kl-crosscheck/README.md: a
//!     floor-clamped implementation cannot avoid the fingerprint);
//!   * the a-variant fill (nndsvda: zeros replaced by mean(V), the
//!     Boutsidis–Gallopoulos zero-lock release) must reach a strictly
//!     better objective at equal iteration count — if someone reintroduced
//!     an epsilon resurrection, plain and a-variant would converge to the
//!     same place and this pin would break.
//!
//! All construction is through the public API surface only.

use msuiter_engine::nmf::{fit_kl_with_init, KL_EPS};
use msuiter_engine::nndsvd::{nndsvda_init, nndsvd_init};
use msuiter_engine::rng::{MsRng, StreamId};

// Historical floor constants whose appearance inside a factor is the
// fingerprint of a resurrection clamp (module docs above).
const FINGERPRINTS: [f64; 2] = [KL_EPS, 2.220446049250313e-16];

/// Separable truth in the catalog geometry (96 channels × 20 samples,
/// k = 3): three anchor-block signatures, near-pure sample groups, at the
/// reduced exposure scale the nndsvd.rs end-to-end tests use — at this
/// scale mean(V) is comparable to the subleading factor entries, which is
/// the regime the NNDSVDa fill is defined in and where the zero-lock
/// difference is measurable rather than drowned by the init scale.
fn separable_truth(seed: u64) -> Vec<f64> {
    let (m, n, k) = (96usize, 20usize, 3usize);
    let mut rng = MsRng::from_stream(seed, StreamId { replicate: 5, rank: 11, fold: 2 });
    let open_unit = |rng: &mut MsRng| -> f64 { ((rng.next_u64() >> 11) as f64 + 1.0) * (1.0 / (1u64 << 53) as f64) };
    let mut w = vec![0.0f64; m * k];
    for s in 0..k {
        let mut col: Vec<f64> = (0..m)
            .map(|i| if i / 32 == s { 0.5 + open_unit(&mut rng) } else { 0.0 })
            .collect();
        let sum: f64 = col.iter().sum();
        for x in col.iter_mut() {
            *x /= sum;
        }
        for i in 0..m {
            w[i * k + s] = col[i];
        }
    }
    let mut h = vec![0.0f64; k * n];
    for j in 0..n {
        let dom = j / 5;
        for s in 0..k {
            h[s * n + j] = if dom == 3 || s == dom {
                5.0 + 10.0 * open_unit(&mut rng)
            } else {
                0.5 * open_unit(&mut rng)
            };
        }
    }
    let mut v = vec![0.0f64; m * n];
    for i in 0..m {
        for j in 0..n {
            let mut acc = 0.0f64;
            for s in 0..k {
                acc += w[i * k + s] * h[s * n + j];
            }
            v[i * n + j] = acc;
        }
    }
    v
}

const M: usize = 96;
const N: usize = 20;
const K: usize = 3;
const ITERS: usize = 60;
/// Frozen init seed for this suite (recorded, never changed silently).
const SEED: u64 = 7;

#[test]
fn plain_nndsvd_init_actually_carries_zeros_on_the_frozen_fixture() {
    // Anti-vacuity pin for the zero-lock tests below: the probe fixture
    // must really exercise the absorbing-zero path.
    let v = separable_truth(0xBEEF);
    let (w0, h0) = nndsvd_init(&v, M, N, K, SEED).expect("nndsvd init");
    let zeros = w0.iter().chain(h0.iter()).filter(|&&x| x == 0.0).count();
    assert!(
        zeros > 0,
        "fixture lost its structural zeros: {zeros} exact 0.0 entries in the plain NNDSVD init"
    );
}

#[test]
fn nndsvd_init_zeros_stay_frozen_and_epsilon_never_floors_factors() {
    let v = separable_truth(0xBEEF);
    let (w0, h0) = nndsvd_init(&v, M, N, K, SEED).expect("nndsvd init");
    let fit = fit_kl_with_init(&v, M, N, K, &w0, &h0, ITERS).expect("kl fit");

    // (1) Zero-lock: an exact init zero is still an exact 0.0 — a
    // post-update resurrection floor would have lifted it.
    let mut frozen = 0usize;
    for (idx, (&init, &final_)) in w0.iter().zip(fit.w.iter()).enumerate() {
        if init == 0.0 {
            assert_eq!(final_, 0.0, "w[{idx}] was resurrected from the absorbing zero");
            frozen += 1;
        }
    }
    for (idx, (&init, &final_)) in h0.iter().zip(fit.h.iter()).enumerate() {
        if init == 0.0 {
            assert_eq!(final_, 0.0, "h[{idx}] was resurrected from the absorbing zero");
            frozen += 1;
        }
    }
    assert!(frozen > 0, "zero-lock probe never ran (no frozen entries)");

    // (2) Division-only epsilon: no factor entry may sit exactly on a
    // historical resurrection-floor constant. Genuine MU decay to tiny
    // values is legitimate (the kl-crosscheck observed 1e-113 free
    // decays); being *clamped* onto a floor is the bug being pinned out.
    for (idx, &x) in fit.w.iter().chain(fit.h.iter()).enumerate() {
        for fp in FINGERPRINTS {
            assert_ne!(x, fp, "factor entry {idx} sits on the floor constant {fp}");
        }
    }

    // (3) Numeric hygiene of the guarded divisions: finite everywhere and
    // the MM trace keeps descending (1e-9 relative slack, nmf.rs convention).
    assert!(fit.objective.iter().all(|x| x.is_finite()), "non-finite objective");
    for t in 1..fit.objective.len() {
        let slack = 1e-9 * (1.0 + fit.objective[t - 1].abs());
        assert!(
            fit.objective[t] <= fit.objective[t - 1] + slack,
            "objective increased at t={t}: {} -> {}",
            fit.objective[t - 1],
            fit.objective[t]
        );
    }
}

#[test]
fn nndsvda_fill_beats_the_frozen_plain_init_at_equal_iterations() {
    // The 1.5.0-class regression pin: releasing the zero-lock with the
    // documented mean(V) fill must buy a strictly better objective at the
    // same iteration count. Equality (within roundoff) would mean the
    // plain init is not actually locked — i.e. an epsilon resurrection
    // crept back into the kernel — and this pin fails.
    let v = separable_truth(0xBEEF);
    let (w0, h0) = nndsvd_init(&v, M, N, K, SEED).expect("plain init");
    let (wa, ha) = nndsvda_init(&v, M, N, K, SEED).expect("a-variant init");
    let plain = fit_kl_with_init(&v, M, N, K, &w0, &h0, ITERS).expect("plain fit");
    let filled = fit_kl_with_init(&v, M, N, K, &wa, &ha, ITERS).expect("filled fit");

    let (o_plain, o_filled) = (
        *plain.objective.last().expect("trace"),
        *filled.objective.last().expect("trace"),
    );
    assert!(
        o_filled < o_plain - 1e-9 * (1.0 + o_plain.abs()),
        "zero-lock release gained nothing: filled {o_filled} vs plain {o_plain} — \
         either the plain init is no longer freezing its zeros (resurrection clamp?) \
         or the a-variant fill broke"
    );
    // The a-variant factors are strictly positive by construction — the
    // property that unlocks the frozen cells.
    assert!(filled.w.iter().all(|&x| x > 0.0), "a-variant w lost strict positivity");
    assert!(filled.h.iter().all(|&x| x > 0.0), "a-variant h lost strict positivity");
}

#[test]
fn plain_and_a_variant_fits_are_deterministic_pure_functions() {
    // The kernel is a pure function of (V, k, init, max_iter) — the
    // boundary's protocol depends on it; rerun both arms and demand bits.
    let v = separable_truth(0xBEEF);
    for use_a in [false, true] {
        let (w0, h0) = (if use_a {
            nndsvda_init(&v, M, N, K, SEED)
        } else {
            nndsvd_init(&v, M, N, K, SEED)
        })
        .expect("init");
        let a = fit_kl_with_init(&v, M, N, K, &w0, &h0, ITERS).expect("fit a");
        let b = fit_kl_with_init(&v, M, N, K, &w0, &h0, ITERS).expect("fit b");
        assert_eq!(a, b);
    }
}
