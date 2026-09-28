//! In-house PCG64 random number generator with a frozen master-seed → stream
//! layout (U-M0-06; `docs/ARCHITECTURE.md` §2 `engine/rng.rs`, decision A6 in
//! `docs/reviews/00-synthesis.md`).
//!
//! # Why in-house?
//!
//! The `rand` ecosystem does not guarantee bit-identical streams across
//! versions (D6 note / A6). msuiter publishes seeds and stream layouts in
//! paper Methods sections, so both the generator and its seeding layout are
//! frozen here and guarded by golden tests that must stay bit-identical from
//! the MSRV toolchain (1.71) to current stable.
//!
//! # Generator core: PCG64
//!
//! O'Neill's Permuted Congruential Generator, 128-bit LCG state, 64-bit
//! output (the pcg-cpp `pcg64` configuration):
//!
//! ```text
//! step: state ← state * M + inc        (mod 2^128, wrapping arithmetic)
//! out:  rot  = state[127:122]          (top 6 bits of the POST-step state)
//!       xsl  = state[127:64] XOR state[63:0]
//!       out  = rotr64(xsl, rot)
//! ```
//!
//! where `M = 0x2360ED051FC65DA44385DF649FCCF645` (the PCG 128-bit default
//! multiplier). Output is taken from the **post-step** state — the canonical
//! `pcg64` convention (`pcg-cpp` takes pre-step output only for ≤64-bit
//! states; `output_previous = (sizeof(itype) <= 8)`), matching numpy's PCG64
//! bit-for-bit for equal `(state, inc)`. `inc` is always odd, so each `inc`
//! selects a distinct full-period (2^128) LCG subsequence.
//!
//! # SplitMix64 seed expander
//!
//! SplitMix64 (Steele & Lea 2014) expands one 64-bit word into a stream of
//! well-mixed 64-bit words: `state += 0x9E3779B97F4A7C15` (the golden-ratio
//! gamma), then the published finalizer mix. It is used to expand the
//! absorbed stream entropy into the two PCG seed words.
//!
//! # Canonical stream layout v1
//!
//! `LAYOUT_ID = 0x4D53_5552_4E47_5631` ("MSURNGV1"). Given
//! `master_seed: u64` and `stream = StreamId { replicate, rank, fold }` (the
//! per-replicate / per-rank / per-fold counter axes of
//! `docs/ARCHITECTURE.md` §2), the PCG64 state is derived as follows:
//!
//! ```text
//! h0 = mix64(LAYOUT_ID)
//! h1 = mix64(h0 XOR master_seed)
//! h2 = mix64(h1 XOR replicate)
//! h3 = mix64(h2 XOR rank)
//! h4 = mix64(h3 XOR fold)
//!
//! expander  = SplitMix64 seeded with h4
//! initstate = expander.next()          // first expander word
//! initseq   = expander.next()          // second expander word
//! inc       = (initseq << 1) | 1       // odd → distinct LCG subsequence
//!
//! state  = 0
//! state  = state * M + inc             // pcg_basic seeding step 1
//! state += initstate
//! state  = state * M + inc             // pcg_basic seeding step 2
//! ```
//!
//! The first `next_u64()` output is produced from this post-seed state.
//!
//! # Separation argument (Methods-grade sketch)
//!
//! 1. *Field positioning.* The four input words are absorbed at fixed,
//!    ordered chain positions. Two stream keys differing in any single field
//!    differ in the word entering that step, so word commutations (e.g.
//!    `{replicate: 1, rank: 2}` vs `{replicate: 2, rank: 1}`) cannot collide.
//! 2. *Full-avalanche mixing.* `mix64` is a bijection on `u64` (a
//!    composition of xor-shifts and odd multiplications) with documented
//!    full avalanche (Steele & Lea 2014): every output bit depends on every
//!    input bit. The only many-to-one operation in the chain is the XOR
//!    fold, which is immediately followed by a `mix64`; a collision
//!    therefore requires an exact 64-bit coincidence of intermediate states.
//!    No structured collision family exists, in contrast to a plain XOR of
//!    all fields. (Known cosmetic fixed point: `mix64(0) = 0`, reachable
//!    only when a chain state equals an absorbed word exactly — a 2^-64
//!    coincidence — and the chain recovers at the next absorb step; the
//!    double PCG seeding step re-mixes regardless.)
//! 3. *Domain separation.* Absorbing `LAYOUT_ID` first pins the layout
//!    version: any future change to the field set, order, or constants must
//!    mint a new `LAYOUT_ID`, keeping v1 streams and later streams on
//!    disjoint derivation paths (v1 goldens stay frozen).
//! 4. *PCG seeding.* `inc = initseq << 1 | 1` is a bijection onto odd
//!    128-bit values, and each odd `inc` selects a distinct full-period LCG
//!    subsequence. The two forced LCG steps of the `pcg_basic` protocol mix
//!    `initstate` and `inc` before the first output, so even the degenerate
//!    input `(master_seed = 0, stream = 0)` yields a well-mixed state.
//! 5. *Empirical guard.* The tests in this module pin (a) golden bit
//!    patterns, (b) pairwise-disjoint prefixes across a stream grid and
//!    across master seeds, and (c) determinism; the golden set must hold
//!    identically on stable and on the 1.71 MSRV toolchain (D6/A6).
//!
//! # Contract notes (`docs/ARCHITECTURE.md` §2)
//!
//! * No dependencies, no `rand` face (banned in `deny.toml`), and no
//!   `unsafe` (crate-level `#![forbid(unsafe_code)]`).
//! * `MsRng` is a plain value type: generator state lives in the caller.
//!   This matches the stateless-FFI contract (D12) and the thread-invariance
//!   contract (§2.6): parallel replicates/ranks/folds never share generator
//!   state, and equal seeds produce identical output regardless of thread
//!   count.
//! * Distribution sampling (multinomial/Dirichlet) is deliberately out of
//!   scope here (U-M1s-04, `engine/resample.rs`).

/// Stream identity for the canonical layout: per-replicate / per-rank /
/// per-fold counter axes (see the module docs for the exact derivation).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StreamId {
    /// Replicate counter (restart / bootstrap / consensus replicate index).
    pub replicate: u64,
    /// Rank counter (worker rank or rank axis of the analysis).
    pub rank: u64,
    /// Fold counter (cross-validation fold index).
    pub fold: u64,
}

impl StreamId {
    /// The all-zero stream, used for single-stream (non-parallel) call sites.
    pub const ZERO: Self = Self { replicate: 0, rank: 0, fold: 0 };
}

/// SplitMix64 seed expander (Steele & Lea 2014): turns one 64-bit seed into
/// a sequence of well-mixed 64-bit words. See the module docs.
#[derive(Debug, Clone, Copy)]
pub struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    /// Create an expander from a 64-bit seed.
    pub const fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    /// Produce the next 64-bit word of the expansion.
    pub fn next_word(&mut self) -> u64 {
        self.state = self.state.wrapping_add(GOLDEN_GAMMA);
        mix64(self.state)
    }
}

/// In-house PCG64 generator (128-bit LCG state, 64-bit XSL-RR output) with
/// the canonical stream layout v1. See the module docs.
#[derive(Debug, Clone, Copy)]
pub struct MsRng {
    state: u128,
    inc: u128,
}

impl MsRng {
    /// Derive a generator from `master_seed` for the given `stream`, per the
    /// canonical stream layout v1 documented in this module.
    pub fn from_stream(master_seed: u64, stream: StreamId) -> Self {
        // Canonical layout v1: absorb the layout id (domain separation),
        // then the four input words in fixed order, then expand the 64-bit
        // chain state into the two PCG seed words via SplitMix64.
        let mut h = mix64(LAYOUT_ID);
        h = mix64(h ^ master_seed);
        h = mix64(h ^ stream.replicate);
        h = mix64(h ^ stream.rank);
        h = mix64(h ^ stream.fold);

        let mut expander = SplitMix64::new(h);
        let initstate = expander.next_word() as u128;
        let initseq = expander.next_word();
        let inc = ((initseq as u128) << 1) | 1;

        // pcg_basic seeding protocol: two forced LCG steps mix `initstate`
        // and `inc` before the first output.
        let mut rng = Self { state: 0, inc };
        rng.lcg_step();
        rng.state = rng.state.wrapping_add(initstate);
        rng.lcg_step();
        rng
    }

    /// Produce the next 64-bit output word (XSL-RR applied to the post-step
    /// state — canonical pcg64 convention; see the module docs).
    pub fn next_u64(&mut self) -> u64 {
        self.lcg_step();
        xsl_rr_output(self.state)
    }

    #[inline]
    fn lcg_step(&mut self) {
        self.state = self.state.wrapping_mul(PCG_MULT).wrapping_add(self.inc);
    }
}

/// Domain-separation tag for stream layout v1 ("MSURNGV1"). Frozen: changing
/// it (or anything else in the layout) requires a new layout version and a
/// regenerated golden set.
const LAYOUT_ID: u64 = 0x4D53_5552_4E47_5631;

/// PCG 128-bit default multiplier (O'Neill, pcg_random.hpp).
const PCG_MULT: u128 = 0x2360_ED05_1FC6_5DA4_4385_DF64_9FCC_F645;

const GOLDEN_GAMMA: u64 = 0x9E37_79B9_7F4A_7C15;

#[inline]
const fn mix64(z: u64) -> u64 {
    let mut x = z;
    x = (x ^ (x >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    x ^ (x >> 31)
}

/// XSL-RR output function: 128-bit state → 64-bit output.
/// `rot` = top 6 bits of the state; `xsl` = high 64 bits XOR low 64 bits;
/// result = rotate-right of `xsl` by `rot`.
#[inline]
const fn xsl_rr_output(state: u128) -> u64 {
    let rot = (state >> 122) as u64;
    let xsl = ((state >> 64) as u64) ^ (state as u64);
    // rot < 64 by construction (state >> 122 keeps 6 bits).
    xsl.rotate_right(rot as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    const N_GOLDEN: usize = 16;

    fn first_words(master_seed: u64, stream: StreamId) -> [u64; N_GOLDEN] {
        let mut rng = MsRng::from_stream(master_seed, stream);
        core::array::from_fn(|_| rng.next_u64())
    }

    // ------------------------------------------------------------------
    // Golden vectors (frozen at U-M0-06; regenerated 2026-09-28 when the
    // output convention was corrected to canonical post-step pcg64 — see
    // the module docs). These bit patterns are generated by this
    // implementation and recorded verbatim; any future diff means the
    // generator or the stream layout drifted, which requires a new
    // LAYOUT_ID plus a regenerated golden set (D6/A6, paper Methods freeze).
    // They must hold identically on stable and on the 1.71 MSRV toolchain
    // (`cargo +1.71.0 test -p msuiter-engine`) and are independently
    // re-derived by tools/rng-kat.py.
    // ------------------------------------------------------------------

    #[test]
    fn golden_master_seed_42_zero_stream() {
        assert_eq!(
            first_words(42, StreamId::ZERO),
            [
                0x0ad9_17fb_f73d_a447,
                0xa98d_2e04_188c_8d56,
                0x7ba8_f275_b1e7_fcab,
                0xa976_a17a_87e6_7747,
                0xaa2e_e1fd_c42e_8ac6,
                0x56b7_0240_02ef_881a,
                0x34cc_f0d2_7cc0_1eac,
                0xd904_32f7_d733_b3a6,
                0x7b80_1371_dc0d_03dc,
                0x9f9e_b103_ae4d_f2b3,
                0xa68b_7ec8_c0b5_0251,
                0x7f88_aeda_9819_53cd,
                0xf191_db4e_31ff_0d69,
                0xb8df_718e_7b7f_6de2,
                0x4643_bfff_a7bc_1d94,
                0xbfe5_bdbd_2942_226f,
            ]
        );
    }

    #[test]
    fn golden_master_seed_42_offset_stream() {
        assert_eq!(
            first_words(42, StreamId { replicate: 7, rank: 3, fold: 5 }),
            [
                0x52bd_0376_edbe_a6a8,
                0xacc2_ee8c_5e2d_675e,
                0x945e_61ef_03a5_8bfe,
                0x68fd_3392_569e_6185,
                0x6e92_7e47_3f2d_a2e7,
                0xf3fa_8213_fdc3_6f32,
                0x0842_193f_abd8_cdae,
                0xbab4_055a_e86e_b11b,
                0x05b5_610d_e26b_bcb4,
                0x7e15_4ded_4fe1_3513,
                0x0a40_681a_17af_02ab,
                0x5d76_67c3_0e35_c9d2,
                0xe18a_96ba_cd0d_ee02,
                0xf38d_d772_50ab_71cf,
                0x0a4e_3b12_686c_fabd,
                0x5fa1_0060_cfdb_0c77,
            ]
        );
    }

    #[test]
    fn golden_zero_seed_offset_stream() {
        assert_eq!(
            first_words(0, StreamId { replicate: 1, rank: 2, fold: 3 }),
            [
                0xe519_7189_1d48_76f2,
                0x5c62_9903_3ff9_84fc,
                0x2794_0593_cff0_4c25,
                0x12e8_c4e3_9e43_8be3,
                0x364b_a9a8_97af_490a,
                0x8d7d_e2a2_62e7_40be,
                0x9109_bd9e_5f91_08d5,
                0x1e00_ccbb_3354_dcd1,
                0x2608_6694_2229_28b3,
                0x0ba1_f3b5_f2b7_c3b9,
                0x9161_d04e_f36a_3ef4,
                0x9e71_a03a_dcf3_f9b5,
                0xd747_62c9_e2c0_e22f,
                0xcf42_ff09_7fb3_e3d0,
                0x022c_0e05_fc3b_ec38,
                0xbd43_29d0_cecd_5f9d,
            ]
        );
    }

    // ------------------------------------------------------------------
    // Stream separation
    // ------------------------------------------------------------------

    #[test]
    fn stream_grid_yields_pairwise_distinct_sequences() {
        let mut streams = Vec::new();
        for replicate in 0..4u64 {
            for rank in 0..3u64 {
                for fold in 0..3u64 {
                    let s = StreamId { replicate, rank, fold };
                    streams.push((s, first_words(2026, s)));
                }
            }
        }
        for i in 0..streams.len() {
            for j in (i + 1)..streams.len() {
                assert_ne!(
                    streams[i].1, streams[j].1,
                    "streams {:#?} and {:#?} collide",
                    streams[i].0, streams[j].0
                );
            }
        }
    }

    #[test]
    fn master_seed_changes_sequence() {
        let stream = StreamId { replicate: 9, rank: 1, fold: 4 };
        let mut sequences = Vec::new();
        for seed in 0..8u64 {
            sequences.push(first_words(seed, stream));
        }
        for i in 0..sequences.len() {
            for j in (i + 1)..sequences.len() {
                assert_ne!(
                    sequences[i], sequences[j],
                    "master seeds {i} and {j} collide on stream {stream:?}"
                );
            }
        }
    }

    // ------------------------------------------------------------------
    // Properties (hand-written loops; no proptest dependency)
    // ------------------------------------------------------------------

    #[test]
    fn determinism_same_params_same_sequence() {
        let stream = StreamId { replicate: 11, rank: 7, fold: 2 };
        let mut a = MsRng::from_stream(0xDEAD_BEEF, stream);
        let mut b = MsRng::from_stream(0xDEAD_BEEF, stream);
        for _ in 0..512 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn output_covers_full_u64_domain_smoke() {
        let mut rng = MsRng::from_stream(7, StreamId { replicate: 2, rank: 2, fold: 2 });
        let draws = 20_000u64;
        let mut min = u64::MAX;
        let mut max = 0u64;
        let mut high_half = 0u64;
        for _ in 0..draws {
            let w = rng.next_u64();
            min = min.min(w);
            max = max.max(w);
            if w >> 63 == 1 {
                high_half += 1;
            }
        }
        // Both tails of the u64 domain are reached: for 2·10^4 uniform draws
        // the expected extremum is ~2^64/2·10^4 ≈ 2^48.8, so a 2^54 window
        // misses only with probability ~3e-9 for a healthy generator.
        assert!(min < (1u64 << 54), "min never reached the low tail: {min}");
        assert!(max > u64::MAX - (1u64 << 54), "max never reached the high tail: {max}");
        // No systematic half-domain bias.
        let hi_frac = high_half as f64 / draws as f64;
        assert!(
            (0.45..0.55).contains(&hi_frac),
            "high-half fraction {hi_frac} out of tolerance"
        );
    }

    #[test]
    fn splitmix64_matches_published_known_answer() {
        // Published SplitMix64 known-answer vector: seeding with 0, the first
        // expansion word is 0xe220a8397b1dcdaf (Steele & Lea 2014 reference
        // sequence, widely cross-checked). Later words are recorded from this
        // implementation under the same cross-version golden discipline.
        let mut sm = SplitMix64::new(0);
        let w0 = sm.next_word();
        let w1 = sm.next_word();
        assert_eq!(w0, 0xe220_a839_7b1d_cdaf);
        assert_eq!(w1, 0x6e78_9e6a_a1b9_65f4);
        // Determinism: same seed, same words.
        let mut sm_again = SplitMix64::new(0);
        assert_eq!(sm_again.next_word(), w0);
        assert_eq!(sm_again.next_word(), w1);
        // Different seed → different first word.
        let mut sm_other = SplitMix64::new(1);
        assert_ne!(sm_other.next_word(), w0);
    }
}
