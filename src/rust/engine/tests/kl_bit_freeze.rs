//! P11 bit-freeze law for the engine-internal KL kernel restructure.
//!
//! The P11 design memo (vignettes/articles/devlog-2026-11-09-p11-engine-kl-design.qmd)
//! authorizes restructuring the certified-loop hot path — fused ratio
//! epilogues (L1), column blocking (L2), `num` layout transpose (L3),
//! cv-wrapper scratch reuse (L4), EU allocation hoisting (L5) — under one
//! predicate: every produced digit stays bit-for-bit. This file is that
//! predicate, committed before the first lever lands.
//!
//! Method, mirroring the P3 law (`tests/kl_scratch_bit_exact.rs`): a frozen
//! reference twin — a verbatim copy of the committed scalar path — run
//! beside the live faces at the memo's shapes (production n, block-boundary
//! n, single-iteration T, zero-column and zero-row count grids), equality
//! `assert_eq!` on the f64 vectors, no tolerance. On top of the twin, the
//! objective/W/H endpoint f64s captured from the PRE-change kernel are
//! pinned as literal bit patterns (`f64::from_bits`), so the twin and the
//! live path cannot co-drift in a later change.
//!
//! The twin is frozen text: if the certified scalar path is ever
//! re-derived, this file must be re-derived with it in the same change.

use msuiter_engine::detmath::det_ln;
use msuiter_engine::nmf::{fit_kl_with_init, fit_kl_with_init_scratch, KlScratch, NmfFit, KL_EPS};
use msuiter_engine::rng::{MsRng, StreamId};

// ======================================================================
// Frozen reference twin: carried verbatim from
// tests/kl_scratch_bit_exact.rs @ d04929b (pre-P11), where the same five
// bodies are proven bit-identical to the live certified faces. Do not edit
// these bodies; they are the law's fixed side.
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
        acc += vv * (det_ln(KL_EPS + vv) - det_ln(KL_EPS + mm)) - vv + mm;
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
// Synthetic fixtures: production and block-boundary shapes, in-house
// streams, count grids (synthetic provider only, no external data).
// ======================================================================

fn uniform(rng: &mut MsRng) -> f64 {
    ((rng.next_u64() >> 11) as f64) * (1.0 / (1u64 << 53) as f64)
}

/// Integer-valued counts in {0, ..., 39} — both loop branches (zero and
/// nonzero ratios) are on the table — then punched per the case: a whole
/// column or a whole row zeroed (the absorbing-zero regimes).
#[derive(Clone, Copy)]
enum ZeroPunch {
    None,
    Col(usize),
    Row(usize),
}

fn counts(rng: &mut MsRng, m: usize, n: usize, punch: ZeroPunch) -> Vec<f64> {
    let mut v: Vec<f64> = (0..m * n).map(|_| (uniform(rng) * 40.0).floor()).collect();
    match punch {
        ZeroPunch::None => {}
        ZeroPunch::Col(j) => {
            for i in 0..m {
                v[i * n + j] = 0.0;
            }
        }
        ZeroPunch::Row(i) => {
            for x in &mut v[i * n..i * n + n] {
                *x = 0.0;
            }
        }
    }
    v
}

/// Strictly positive deterministic initializer (manual, so the freeze pins
/// the LOOP bytes, not an initializer's behavior).
fn positive_init(rng: &mut MsRng, m: usize, n: usize, k: usize) -> (Vec<f64>, Vec<f64>) {
    let w0: Vec<f64> = (0..m * k).map(|_| 0.25 + 0.75 * uniform(rng)).collect();
    let h0: Vec<f64> = (0..k * n).map(|_| 0.25 + 0.75 * uniform(rng)).collect();
    (w0, h0)
}

struct FreezeCase {
    m: usize,
    n: usize,
    k: usize,
    iters: usize,
    punch: ZeroPunch,
    seed: u64,
    tag: &'static str,
}

const CASES: &[FreezeCase] = &[
    FreezeCase { m: 96, n: 1000, k: 10, iters: 100, punch: ZeroPunch::None, seed: 20261101, tag: "prod-96x1000-k10" },
    FreezeCase { m: 96, n: 1001, k: 10, iters: 64, punch: ZeroPunch::None, seed: 20261102, tag: "prod-96x1001-k10" },
    FreezeCase { m: 96, n: 63, k: 3, iters: 50, punch: ZeroPunch::None, seed: 20261103, tag: "blockedge-96x63-k3" },
    FreezeCase { m: 96, n: 64, k: 3, iters: 50, punch: ZeroPunch::None, seed: 20261104, tag: "blockedge-96x64-k3" },
    FreezeCase { m: 96, n: 65, k: 3, iters: 50, punch: ZeroPunch::None, seed: 20261105, tag: "blockedge-96x65-k3" },
    FreezeCase { m: 50, n: 200, k: 5, iters: 1, punch: ZeroPunch::None, seed: 20261106, tag: "single-iter-50x200-k5" },
    FreezeCase { m: 96, n: 1000, k: 10, iters: 100, punch: ZeroPunch::Col(777), seed: 20261105, tag: "zero-col-96x1000-k10" },
    FreezeCase { m: 96, n: 1000, k: 10, iters: 100, punch: ZeroPunch::Row(0), seed: 20261106, tag: "zero-row-96x1000-k10" },
];

/// Deterministic fixture for one case: the count grid, the initializer,
/// and the twin's fit — all three derived from the one stream so a rebuild
/// is exactly reproducible.
struct CaseFixture {
    v: Vec<f64>,
    w0: Vec<f64>,
    h0: Vec<f64>,
    want: NmfFit,
}

fn build_fixture(c: &FreezeCase) -> CaseFixture {
    let mut rng = MsRng::from_stream(c.seed, StreamId { replicate: 11, rank: c.k as u64, fold: 0 });
    let v = counts(&mut rng, c.m, c.n, c.punch);
    let (w0, h0) = positive_init(&mut rng, c.m, c.n, c.k);
    let want = ref_fit(&v, c.m, c.n, c.k, &w0, &h0, c.iters);
    CaseFixture { v, w0, h0, want }
}

fn assert_fit_eq(got: &NmfFit, want: &NmfFit, face: &str, tag: &str) {
    assert_eq!(got.w, want.w, "{face} W differs [{tag}]");
    assert_eq!(got.h, want.h, "{face} H differs [{tag}]");
    assert_eq!(got.objective, want.objective, "{face} objective differs [{tag}]");
    assert_eq!(got.iterations, want.iterations, "{face} iterations drifted [{tag}]");
}

#[test]
fn p11_freeze_lattice_is_bit_identical_to_the_pre_change_twin() {
    for c in CASES {
        let f = build_fixture(c);

        // (a) the public certified face
        let public = fit_kl_with_init(&f.v, c.m, c.n, c.k, &f.w0, &f.h0, c.iters)
            .unwrap_or_else(|e| panic!("public fit failed [{tag}]: {e}", tag = c.tag));
        assert_fit_eq(&public, &f.want, "public", c.tag);

        // (b) the scratch face, first use of a fresh scratch
        let mut scr = KlScratch::new(c.m, c.n, c.k);
        let first = fit_kl_with_init_scratch(&f.v, c.m, c.n, c.k, &f.w0, &f.h0, c.iters, &mut scr)
            .expect("scratch fit");
        assert_fit_eq(&first, &f.want, "scratch", c.tag);

        // (c) the SAME scratch reused: buffer reuse must carry no state.
        let second = fit_kl_with_init_scratch(&f.v, c.m, c.n, c.k, &f.w0, &f.h0, c.iters, &mut scr)
            .expect("scratch re-fit");
        assert_fit_eq(&second, &f.want, "scratch-reuse", c.tag);
    }
}

// ======================================================================
// Captured endpoint pins: literal bit patterns of objective[0] /
// objective[end] / w[0..4] / h[0..4] per case, captured from the
// PRE-change kernel @ d04929b (public face), where the twin above and the
// live face are provably the same bytes (the P3 law ran them side by side).
// The twin guards the walk; these literals guard the twin and the live
// path together against any co-drift in a later change. Regenerate only
// with a change that re-derives both sides deliberately.
// ======================================================================

/// One captured endpoint record: (case tag, objective[0], objective[end],
/// w[0..4], h[0..4]) as raw bits.
struct Pin {
    tag: &'static str,
    obj0: u64,
    obj_n: u64,
    w: [u64; 4],
    h: [u64; 4],
}

const PINS: &[Pin] = &[
    Pin { tag: "prod-96x1000-k10", obj0: 0x413d64223be6ffc6, obj_n: 0x4114d25dbb9ec906,
        w: [0x3ff9d40128d52f30, 0x3fdec95b933ee671, 0x3feb888d835ffd2f, 0x3fc5b06aa596abe7],
        h: [0x401f748d8761339a, 0x4012d51deab961cd, 0x400d6988c34d1091, 0x400ec55ad03158f7] },
    Pin { tag: "prod-96x1001-k10", obj0: 0x413d8963168ca86b, obj_n: 0x4114fe033c805ac8,
        w: [0x3fc7e8f93ce17b5e, 0x3fdfe8a6588c79d1, 0x3fd08b4239a64302, 0x3fe8b92a4c0c9aa6],
        h: [0x4008da38d645465f, 0x40056864280baecd, 0x400da2fc9154a445, 0x40113c18f7c22196] },
    Pin { tag: "blockedge-96x63-k3", obj0: 0x410de18eeb0eb4fa, obj_n: 0x40d597483dc98cf5,
        w: [0x3fede110b0dedbea, 0x3fe0762a0df3256d, 0x3fddc29cf15ad266, 0x3fe8e5367f3811bd],
        h: [0x4012a1db3990b860, 0x40256748bb6adcea, 0x402741a5e6bded2c, 0x401f124c1fdc5f7a] },
    Pin { tag: "blockedge-96x64-k3", obj0: 0x410e6e2e180f16a6, obj_n: 0x40d618d3dbaeff42,
        w: [0x3fde0835b6ad159d, 0x3ff11692298fe77f, 0x3fd1548554294f53, 0x3fe634c3a4f566eb],
        h: [0x4023459548777c5c, 0x402855d2f63af4c5, 0x4025a7c19e6a2276, 0x402f3262ffe63a35] },
    Pin { tag: "blockedge-96x65-k3", obj0: 0x41105ca3c7deb533, obj_n: 0x40d6298fe1b6053a,
        w: [0x3fe9da6f76092c60, 0x3fe6354567e53b2d, 0x3fd0f7c3332cacf8, 0x3fd2f1982515c9ab],
        h: [0x4031f03641f9d7fe, 0x40249fc04232338f, 0x4026b486bf412c0a, 0x4025be6e9f7c9624] },
    Pin { tag: "single-iter-50x200-k5", obj0: 0x41135fbe5bd50010, obj_n: 0x40e397b0ee7fdb51,
        w: [0x3fe0fa973fb7c49a, 0x3fd86988ee7e3267, 0x3fed762c42d9cc3d, 0x3fee810d56c42b26],
        h: [0x401ff17d4c9ccc55, 0x401191f3db4f7518, 0x40134f175fd53b4f, 0x401356588bbc5c5d] },
    Pin { tag: "zero-col-96x1000-k10", obj0: 0x413d402e00d708c5, obj_n: 0x4114cbb6bd742b9c,
        w: [0x3fefa6543284e489, 0x3ff2c8e3e7f8b2dd, 0x3fee463980ef26c6, 0x3ff21324394b24e9],
        h: [0x3fcb597a4e5eb702, 0x4009422c99965a2c, 0x3ff5c3de6ef07d6b, 0x4002da84a9e54d49] },
    Pin { tag: "zero-row-96x1000-k10", obj0: 0x413dbbaf5708e08f, obj_n: 0x411494b3d522a227,
        w: [0x0000000000000000; 4],
        h: [0x400096703dbc29eb, 0x3ff9afae19de3870, 0x4018aeb945020c3f, 0x3fec61e328d20f85] },
];

#[test]
fn p11_pin_literals_match_the_pre_change_kernel_bits() {
    for (c, pin) in CASES.iter().zip(PINS.iter()) {
        assert_eq!(c.tag, pin.tag, "case/pin roster drift");
        let f = build_fixture(c);
        let got = fit_kl_with_init(&f.v, c.m, c.n, c.k, &f.w0, &f.h0, c.iters)
            .unwrap_or_else(|e| panic!("public fit failed [{tag}]: {e}", tag = c.tag));
        assert_eq!(got.objective[0].to_bits(), pin.obj0, "objective[0] bits differ [{}]", c.tag);
        assert_eq!(
            got.objective[got.objective.len() - 1].to_bits(),
            pin.obj_n,
            "objective[end] bits differ [{}]",
            c.tag
        );
        for (j, &bits) in pin.w.iter().enumerate() {
            assert_eq!(got.w[j].to_bits(), bits, "w[{j}] bits differ [{}]", c.tag);
        }
        for (j, &bits) in pin.h.iter().enumerate() {
            assert_eq!(got.h[j].to_bits(), bits, "h[{j}] bits differ [{}]", c.tag);
        }
    }
}
