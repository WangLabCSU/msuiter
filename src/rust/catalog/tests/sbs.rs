//! Golden and property tests for the SBS channel-family arithmetic
//! (U-M1s-06; D11 "semantic bit" acceptance: integer + label goldens).
//!
//! Golden vectors below are hand-derived from the SPMG rules audited in
//! `docs/research/04` section 1 and re-verified against the upstream source:
//!   * pyrimidine orientation: REF in {A,G} => complement REF/ALT, reverse-
//!     complement the context window, flip the strand bias T<->U (B and N
//!     unchanged) -- `MutationMatrixGenerator.py:815-824` with `revcompl` /
//!     `revbias` at `:420-445`;
//!   * channel key `bias:XY[R>M]ZW` over the five-base +/-2 window
//!     (`:778-791`, `:907-917`);
//!   * SPMG `bias_sort` {T:0, U:1, B:2, N:3} and the `tsb_ref` strand
//!     encoding (`SigProfilerMatrixGeneratorFunc.py:173-199`);
//!   * the 6144 index enumerates pyrimidine-centered ACGT 5-mers only
//!     (`SigProfilerMatrixGeneratorFunc.py:1004-1034`), so an N anywhere in
//!     the window has no channel: SPMG drops such a mutation from every SBS
//!     matrix (skip log), and SBS192 (a msuiter table; SPMG itself folds
//!     only 96/384/1536 out of 6144) has no B/N block at all.
//!
//! Expected labels are cross-pinned against the generated canonical tables
//! in `channels.rs` (single source of truth, `data-raw/build_channels.R`).
//!
//! Index arithmetic addressed by the implementation (re-derived by hand for
//! every golden below):
//!   idx96   = f5*24 + class*4 + f3
//!   idx1536 = (f5a*4 + f5b)*96 + class*16 + (f3a*4 + f3b)
//!   idx192  = strand_block(T=0, U=1) * 96 + idx96
//!   idx384  = strand_block(T=0, U=1, B=2, N=3) * 96 + idx96
//! with base4 = {A:0, C:1, G:2, T:3} and
//! class = {C>A:0, C>G:1, C>T:2, T>A:3, T>C:4, T>G:5} (ASCII order).

use std::collections::HashMap;

use msuiter_catalog::channels::{
    SBS1536_CHANNELS, SBS192_CHANNELS, SBS384_CHANNELS, SBS96_CHANNELS,
};
use msuiter_catalog::sbs::{
    assign_sbs1536, assign_sbs1536_slice, assign_sbs192, assign_sbs192_slice, assign_sbs384,
    assign_sbs384_slice, assign_sbs96, assign_sbs96_slice, channel_label, sbs1536_label,
    sbs192_label, sbs384_label, sbs96_label, Strand,
};

const BASES: [u8; 4] = *b"ACGT";

/// Complement of a validated ACGT byte (test helper).
fn comp(b: u8) -> u8 {
    match b {
        b'A' => b'T',
        b'C' => b'G',
        b'G' => b'C',
        _ => b'A', // b'T'
    }
}

/// SPMG re-orientation of a whole window: reverse-complement bytes.
fn revcomp(ctx: &[u8]) -> Vec<u8> {
    ctx.iter().rev().map(|&b| comp(b)).collect()
}

// ---------------------------------------------------------------------------
// Golden vectors (hand-derived index + label; the labels double as the
// channel-table fixtures for the tally layer).
// ---------------------------------------------------------------------------

/// 28 hand-derived SBS96 variants: refs A/C/G/T, all six substitution
/// classes, purine mirrors of pyrimidine-centered contexts.
#[test]
fn golden_sbs96() {
    // (context [5', ref, 3'], alt, expected index, expected label)
    let golden: &[(&[u8; 3], u8, usize, &str)] = &[
        // Pyrimidine centers: used as-is.
        (b"ACA", b'A', 0, "A[C>A]A"),
        (b"ACA", b'G', 4, "A[C>G]A"),
        (b"ACA", b'T', 8, "A[C>T]A"),
        (b"ACC", b'G', 5, "A[C>G]C"),
        (b"ACG", b'T', 10, "A[C>T]G"),
        (b"ACT", b'A', 3, "A[C>A]T"),
        (b"CCC", b'A', 25, "C[C>A]C"),
        (b"GCG", b'A', 50, "G[C>A]G"),
        (b"TTT", b'G', 95, "T[T>G]T"),
        (b"TTT", b'C', 91, "T[T>C]T"),
        (b"CTA", b'A', 36, "C[T>A]A"),
        (b"GTC", b'G', 69, "G[T>G]C"),
        (b"ATA", b'G', 20, "A[T>G]A"),
        (b"AGA", b'C', 79, "T[C>G]T"),  // revcomp(TCT), C>G
        // Purine centers: complement ref/alt, reverse-complement the window.
        (b"AAA", b'G', 91, "T[T>C]T"),  // revcomp(TTT), T>C
        (b"CTA", b'C', 40, "C[T>C]A"),
        (b"GAG", b'T', 37, "C[T>A]C"),  // revcomp(CTC), T>A
        (b"TAT", b'C', 20, "A[T>G]A"),  // revcomp(ATA), T>G
        (b"GGG", b'A', 33, "C[C>T]C"),  // revcomp(CCC), C>T
        (b"CGT", b'A', 10, "A[C>T]G"),  // revcomp(ACG), C>T
        (b"TGC", b'A', 56, "G[C>T]A"),  // revcomp(GCA), C>T
        (b"ATG", b'G', 22, "A[T>G]G"),
        (b"TAA", b'T', 84, "T[T>A]A"),  // revcomp(TTA), T>A
        (b"CAG", b'G', 42, "C[T>C]G"),  // revcomp(CTG), T>C
        (b"TTA", b'A', 84, "T[T>A]A"),  // mirror of (TAA, T)
        (b"GAA", b'T', 85, "T[T>A]C"),  // revcomp(TTC), T>A
        (b"GTA", b'A', 60, "G[T>A]A"),
        (b"CCT", b'A', 27, "C[C>A]T"),
    ];
    for (ctx, alt, idx, label) in golden {
        assert_eq!(assign_sbs96(ctx, *alt).unwrap(), *idx, "ctx={:?} alt={}", ctx, *alt as char);
        assert_eq!(sbs96_label(*idx).unwrap(), *label, "ctx={:?}", ctx);
        // The label must also sit at that position in the canonical table.
        assert_eq!(SBS96_CHANNELS[*idx], *label);
    }
}

/// 26 hand-derived SBS192 variants: T/U blocks, including purine centers
/// whose orientation flips the strand block (SPMG `revbias`).
#[test]
fn golden_sbs192() {
    // (context, alt, strand, expected index, expected label)
    let golden: &[(&[u8; 3], u8, Strand, usize, &str)] = &[
        (b"ACA", b'A', Strand::Transcribed, 0, "T:A[C>A]A"),
        (b"ACA", b'A', Strand::Untranscribed, 96, "U:A[C>A]A"),
        (b"ACA", b'G', Strand::Untranscribed, 100, "U:A[C>G]A"),
        (b"TTT", b'G', Strand::Transcribed, 95, "T:T[T>G]T"),
        (b"TTT", b'G', Strand::Untranscribed, 191, "U:T[T>G]T"),
        (b"AAA", b'G', Strand::Transcribed, 187, "U:T[T>C]T"),  // flip T->U
        (b"AAA", b'G', Strand::Untranscribed, 91, "T:T[T>C]T"), // flip U->T
        (b"GAG", b'T', Strand::Transcribed, 133, "U:C[T>A]C"),  // flip T->U
        (b"GAG", b'T', Strand::Untranscribed, 37, "T:C[T>A]C"), // flip U->T
        (b"CTA", b'A', Strand::Transcribed, 36, "T:C[T>A]A"),
        (b"CTA", b'A', Strand::Untranscribed, 132, "U:C[T>A]A"),
        (b"TAA", b'T', Strand::Transcribed, 180, "U:T[T>A]A"),  // flip T->U
        (b"GAA", b'T', Strand::Untranscribed, 85, "T:T[T>A]C"), // flip U->T
        (b"GGG", b'A', Strand::Transcribed, 129, "U:C[C>T]C"),  // flip T->U
        (b"CGT", b'A', Strand::Transcribed, 106, "U:A[C>T]G"),  // flip T->U
        (b"TGC", b'A', Strand::Untranscribed, 56, "T:G[C>T]A"), // flip U->T
        (b"CAG", b'G', Strand::Transcribed, 138, "U:C[T>C]G"),  // flip T->U
        (b"ATA", b'G', Strand::Transcribed, 20, "T:A[T>G]A"),
        (b"TTT", b'C', Strand::Untranscribed, 187, "U:T[T>C]T"),
        (b"CCC", b'A', Strand::Transcribed, 25, "T:C[C>A]C"),
        (b"ACC", b'G', Strand::Transcribed, 5, "T:A[C>G]C"),
        (b"GTC", b'G', Strand::Transcribed, 69, "T:G[T>G]C"),
        (b"ATG", b'G', Strand::Untranscribed, 118, "U:A[T>G]G"),
        (b"GTA", b'A', Strand::Transcribed, 60, "T:G[T>A]A"),
        (b"ATT", b'G', Strand::Untranscribed, 119, "U:A[T>G]T"),
        (b"AGA", b'C', Strand::Transcribed, 175, "U:T[C>G]T"), // flip T->U
    ];
    for (ctx, alt, strand, idx, label) in golden {
        assert_eq!(
            assign_sbs192(ctx, *alt, *strand).unwrap(),
            *idx,
            "ctx={:?} alt={} strand={}",
            ctx,
            *alt as char,
            (*strand).bias_label()
        );
        assert_eq!(sbs192_label(*idx).unwrap(), *label);
        assert_eq!(SBS192_CHANNELS[*idx], *label);
    }
}

/// 26 hand-derived SBS384 variants covering all four bias blocks T/U/B/N.
#[test]
fn golden_sbs384() {
    let golden: &[(&[u8; 3], u8, Strand, usize, &str)] = &[
        (b"ACA", b'G', Strand::Transcribed, 4, "T:A[C>G]A"),
        (b"ACA", b'G', Strand::Untranscribed, 100, "U:A[C>G]A"),
        (b"ACA", b'G', Strand::Bidirectional, 196, "B:A[C>G]A"),
        (b"ACA", b'G', Strand::None, 292, "N:A[C>G]A"),
        (b"TTT", b'G', Strand::Bidirectional, 287, "B:T[T>G]T"),
        (b"TTT", b'G', Strand::None, 383, "N:T[T>G]T"),
        (b"AAA", b'G', Strand::Bidirectional, 283, "B:T[T>C]T"),
        (b"AAA", b'G', Strand::None, 379, "N:T[T>C]T"),
        (b"GAG", b'T', Strand::Bidirectional, 229, "B:C[T>A]C"),
        (b"GAG", b'T', Strand::None, 325, "N:C[T>A]C"),
        (b"TAA", b'T', Strand::Bidirectional, 276, "B:T[T>A]A"),
        (b"GAA", b'T', Strand::None, 373, "N:T[T>A]C"),
        (b"GGG", b'A', Strand::Bidirectional, 225, "B:C[C>T]C"),
        (b"CGT", b'A', Strand::Bidirectional, 202, "B:A[C>T]G"),
        (b"TGC", b'A', Strand::None, 344, "N:G[C>T]A"),
        (b"CAG", b'G', Strand::None, 330, "N:C[T>C]G"),
        (b"ATA", b'G', Strand::Transcribed, 20, "T:A[T>G]A"),
        (b"TTT", b'C', Strand::Untranscribed, 187, "U:T[T>C]T"),
        (b"CCC", b'A', Strand::Bidirectional, 217, "B:C[C>A]C"),
        (b"ACC", b'G', Strand::None, 293, "N:A[C>G]C"),
        (b"GTC", b'G', Strand::Bidirectional, 261, "B:G[T>G]C"),
        (b"ATG", b'G', Strand::None, 310, "N:A[T>G]G"),
        (b"GTA", b'A', Strand::Bidirectional, 252, "B:G[T>A]A"),
        (b"ATT", b'G', Strand::None, 311, "N:A[T>G]T"),
        (b"CTA", b'A', Strand::Bidirectional, 228, "B:C[T>A]A"),
        (b"TTA", b'A', Strand::None, 372, "N:T[T>A]A"),
    ];
    for (ctx, alt, strand, idx, label) in golden {
        assert_eq!(
            assign_sbs384(ctx, *alt, *strand).unwrap(),
            *idx,
            "ctx={:?} alt={} strand={}",
            ctx,
            *alt as char,
            (*strand).bias_label()
        );
        assert_eq!(sbs384_label(*idx).unwrap(), *label);
        assert_eq!(SBS384_CHANNELS[*idx], *label);
    }
}

/// 26 hand-derived SBS1536 variants: pentanucleotide contexts, purine and
/// pyrimidine centers, corner blocks and inner offsets.
#[test]
fn golden_sbs1536() {
    // (context [5'2, ref, 3'2], alt, expected index, expected label)
    let golden: &[(&[u8; 5], u8, usize, &str)] = &[
        (b"AAAAA", b'G', 1519, "TT[T>C]TT"), // revcomp(TTTTT), T>C
        (b"AAAAA", b'T', 1503, "TT[T>A]TT"), // revcomp(TTTTT), T>A
        (b"AAAAA", b'C', 1535, "TT[T>G]TT"), // revcomp(TTTTT), T>G
        (b"CCCCC", b'A', 485, "CC[C>A]CC"),
        (b"CCCCC", b'G', 501, "CC[C>G]CC"),
        (b"CCCCC", b'T', 517, "CC[C>T]CC"),
        (b"TTTTT", b'A', 1503, "TT[T>A]TT"), // mirror of (AAAAA, T)
        (b"TTTTT", b'C', 1519, "TT[T>C]TT"), // mirror of (AAAAA, G)
        (b"TTTTT", b'G', 1535, "TT[T>G]TT"),
        (b"ACATA", b'G', 1227, "TA[T>C]GT"), // revcomp(TATGT), T>C
        (b"ACGTA", b'A', 1195, "TA[C>T]GT"), // revcomp(TACGT), C>T
        (b"GATCA", b'G', 852, "GA[T>G]CA"),
        (b"CAGAT", b'C', 318, "AT[C>G]TG"),  // revcomp(ATCTG), C>G
        (b"GGGGG", b'A', 517, "CC[C>T]CC"),  // revcomp(CCCCC), C>T
        (b"AGGCT", b'A', 231, "AG[C>T]CT"),  // revcomp(AGCCT), C>T
        (b"TTGAA", b'C', 1456, "TT[C>G]AA"), // revcomp(TTCAA), C>G
        (b"CATGG", b'G', 474, "CA[T>G]GG"),
        (b"GCATT", b'G', 73, "AA[T>C]GC"),   // revcomp(AATGC), T>C
        (b"TCTCT", b'A', 1303, "TC[T>A]CT"),
        (b"GAGAG", b'C', 701, "CT[C>G]TC"),  // revcomp(CTCTC), C>G
        (b"ATATA", b'G', 1219, "TA[T>C]AT"), // revcomp(TATAT), T>C
        (b"TATAT", b'A', 1203, "TA[T>A]AT"),
        (b"CGCGC", b'A', 585, "CG[C>A]GC"),
        (b"TTTCG", b'A', 1494, "TT[T>A]CG"),
        (b"CTGCA", b'T', 1346, "TG[C>A]AG"), // revcomp(TGCAG), C>A
        (b"GACGT", b'A', 779, "GA[C>A]GT"),
    ];
    for (ctx, alt, idx, label) in golden {
        assert_eq!(assign_sbs1536(ctx, *alt).unwrap(), *idx, "ctx={:?} alt={}", ctx, *alt as char);
        assert_eq!(sbs1536_label(*idx).unwrap(), *label);
        assert_eq!(SBS1536_CHANNELS[*idx], *label);
    }
}

// ---------------------------------------------------------------------------
// Properties: exhaustiveness / bijection against the canonical tables.
// ---------------------------------------------------------------------------

/// Enumerate the oriented input space (pyrimidine centers, all 16 flank
/// pairs, alt != ref): 4*2*3*4 = 96 inputs must hit each SBS96 channel
/// exactly once, with the label equal to the hand-spelled oriented key.
#[test]
fn sbs96_is_bijective_with_canonical_table() {
    let mut seen: HashMap<&str, usize> = HashMap::new();
    for &l in &BASES {
        for &r in &BASES {
            for &center in b"CT" {
                for &alt in &BASES {
                    if alt == center {
                        continue;
                    }
                    let ctx = [l, center, r];
                    let idx = assign_sbs96(&ctx, alt).unwrap();
                    let spelled = [
                        l, b'[', center, b'>', alt, b']', r,
                    ];
                    assert_eq!(SBS96_CHANNELS[idx], std::str::from_utf8(&spelled).unwrap());
                    *seen.entry(SBS96_CHANNELS[idx]).or_default() += 1;
                }
            }
        }
    }
    assert_eq!(seen.len(), 96, "every channel reachable");
    assert!(seen.values().all(|&n| n == 1), "each channel exactly once");
}

/// Same enumeration over SBS192 (x {T,U} = 192 channels) and SBS384
/// (x {T,U,B,N} = 384 channels); block labels are the strand prefix over
/// the SBS96 label, at strand_block*96 + idx96.
#[test]
fn stranded_tables_are_bijective_and_block_aligned() {
    let strands = [
        (Strand::Transcribed, 'T'),
        (Strand::Untranscribed, 'U'),
    ];
    for (strand, ch) in strands {
        let mut seen: HashMap<&str, usize> = HashMap::new();
        for &l in &BASES {
            for &r in &BASES {
                for &center in b"CT" {
                    for &alt in &BASES {
                        if alt == center {
                            continue;
                        }
                        let ctx = [l, center, r];
                        let i96 = assign_sbs96(&ctx, alt).unwrap();
                        let idx = assign_sbs192(&ctx, alt, strand).unwrap();
                        assert_eq!(idx, i96 + 96 * (if ch == 'T' { 0 } else { 1 }));
                        let mut spelled = String::from(ch);
                        spelled.push(':');
                        spelled.push_str(SBS96_CHANNELS[i96]);
                        assert_eq!(SBS192_CHANNELS[idx], spelled);
                        *seen.entry(SBS192_CHANNELS[idx]).or_default() += 1;
                    }
                }
            }
        }
        assert_eq!(seen.len(), 96);
        assert!(seen.values().all(|&n| n == 1));
    }

    let strands384 = [
        (Strand::Transcribed, 0usize),
        (Strand::Untranscribed, 1),
        (Strand::Bidirectional, 2),
        (Strand::None, 3),
    ];
    for (strand, block) in strands384 {
        let mut seen: HashMap<&str, usize> = HashMap::new();
        for &l in &BASES {
            for &r in &BASES {
                for &center in b"CT" {
                    for &alt in &BASES {
                        if alt == center {
                            continue;
                        }
                        let ctx = [l, center, r];
                        let i96 = assign_sbs96(&ctx, alt).unwrap();
                        let idx = assign_sbs384(&ctx, alt, strand).unwrap();
                        assert_eq!(idx, i96 + 96 * block);
                        let mut spelled = String::from(strand.bias_label());
                        spelled.push(':');
                        spelled.push_str(SBS96_CHANNELS[i96]);
                        assert_eq!(SBS384_CHANNELS[idx], spelled);
                        *seen.entry(SBS384_CHANNELS[idx]).or_default() += 1;
                    }
                }
            }
        }
        assert_eq!(seen.len(), 96);
        assert!(seen.values().all(|&n| n == 1));
    }
}

/// Full raw pentanucleotide space (4^5 contexts x 3 alts = 3072 inputs):
/// each of the 1536 channels is hit exactly twice (purine mirror pair), the
/// label equals the oriented key spelled independently, and the 1536 table
/// projects losslessly onto SBS96 (same variant, inner trinucleotide).
#[test]
fn sbs1536_is_bijective_and_projects_onto_sbs96() {
    let mut seen: HashMap<&str, usize> = HashMap::new();
    for &l2 in &BASES {
        for &l in &BASES {
            for &center in &BASES {
                for &alt in &BASES {
                    if alt == center {
                        continue;
                    }
                    for &r in &BASES {
                        for &r2 in &BASES {
                            let ctx = [l2, l, center, r, r2];
                            let idx = assign_sbs1536(&ctx, alt).unwrap();
                            // Independently spelled oriented label.
                            let oriented = if matches!(center, b'A' | b'G') {
                                let o = revcomp(&ctx);
                                (o[0], o[1], comp(center), comp(alt), o[3], o[4])
                            } else {
                                (l2, l, center, alt, r, r2)
                            };
                            let spelled = [
                                oriented.0, oriented.1, b'[', oriented.2, b'>', oriented.3, b']',
                                oriented.4, oriented.5,
                            ];
                            assert_eq!(
                                SBS1536_CHANNELS[idx],
                                std::str::from_utf8(&spelled).unwrap(),
                                "ctx={:?} alt={}",
                                ctx,
                                alt as char
                            );
                            *seen.entry(SBS1536_CHANNELS[idx]).or_default() += 1;
                            // Lossless projection: inner trinucleotide of the
                            // 1536 label (5' flank #2, class, 3' flank #1)
                            // == SBS96 label of the same variant.
                            let inner = &SBS1536_CHANNELS[idx][1..8];
                            let i96 = assign_sbs96(&[l, center, r], alt).unwrap();
                            assert_eq!(SBS96_CHANNELS[i96], inner);
                        }
                    }
                }
            }
        }
    }
    assert_eq!(seen.len(), 1536, "every channel reachable");
    assert!(seen.values().all(|&n| n == 2), "each channel exactly twice (mirror pair)");
}

/// Pyrimidine-orientation invariants: reverse-complementing the window,
/// complementing the alleles and flipping the strand bias must not move the
/// channel (SPMG `revcompl` + `revbias` semantics), for every raw input.
#[test]
fn purine_mirror_invariants() {
    for &l in &BASES {
        for &r in &BASES {
            for &center in &BASES {
                for &alt in &BASES {
                    if alt == center {
                        continue;
                    }
                    let ctx = [l, center, r];
                    let mirror: Vec<u8> = revcomp(&ctx);
                    let malt = comp(alt);
                    let mctx: [u8; 3] = [mirror[0], mirror[1], mirror[2]];
                    let i = assign_sbs96(&ctx, alt).unwrap();
                    assert_eq!(assign_sbs96(&mctx, malt).unwrap(), i);
                    for strand in [
                        Strand::Transcribed,
                        Strand::Untranscribed,
                        Strand::Bidirectional,
                        Strand::None,
                    ] {
                        if matches!(strand, Strand::Transcribed | Strand::Untranscribed) {
                            assert_eq!(
                                assign_sbs192(&ctx, alt, strand).unwrap(),
                                assign_sbs192(&mctx, malt, strand.flipped()).unwrap()
                            );
                        }
                        assert_eq!(
                            assign_sbs384(&ctx, alt, strand).unwrap(),
                            assign_sbs384(&mctx, malt, strand.flipped()).unwrap()
                        );
                    }
                    // Same invariant for the pentanucleotide window.
                    for &l2 in &BASES {
                        for &r2 in &BASES {
                            let ctx5 = [l2, l, center, r, r2];
                            let m5: Vec<u8> = revcomp(&ctx5);
                            let mctx5: [u8; 5] =
                                [m5[0], m5[1], m5[2], m5[3], m5[4]];
                            assert_eq!(
                                assign_sbs1536(&ctx5, alt).unwrap(),
                                assign_sbs1536(&mctx5, malt).unwrap()
                            );
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Error paths (structured MsError, 1-based window positions).
// ---------------------------------------------------------------------------

#[test]
fn invalid_context_base_is_an_argument_error_at_1based_position() {
    for (ctx, pos) in [
        (b"NCA" as &[u8; 3], 1i64),
        (b"ANA", 2),
        (b"ACN", 3),
        (b"aCA", 1), // lowercase is not an allele byte
        (b"AC ", 3),
    ] {
        let err = assign_sbs96(ctx, b'G').unwrap_err();
        assert_eq!(err.topic, "argument", "ctx={:?}", ctx);
        assert_eq!(err.i, Some(pos), "ctx={:?}", ctx);
    }
    let err = assign_sbs1536(b"NCCCC", b'G').unwrap_err();
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(1));
    let err = assign_sbs1536(b"CCCCN", b'G').unwrap_err();
    assert_eq!(err.i, Some(5));
    let err = assign_sbs1536(b"CCNCC", b'G').unwrap_err();
    assert_eq!(err.i, Some(3));
}

#[test]
fn invalid_alt_is_an_argument_error_at_center_slot() {
    let err = assign_sbs96(b"ACA", b'N').unwrap_err();
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(2));
    let err = assign_sbs1536(b"ACACA", b'N').unwrap_err();
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(3));
}

#[test]
fn ref_equal_alt_is_an_argument_error() {
    let err = assign_sbs96(b"ACA", b'C').unwrap_err();
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(2));
    let err = assign_sbs192(b"ACA", b'C', Strand::Transcribed).unwrap_err();
    assert_eq!(err.topic, "argument");
    let err = assign_sbs1536(b"ACACA", b'A').unwrap_err();
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(3));
}

/// SBS192 has only T/U blocks (msuiter convention; SPMG folds 96/384/1536
/// out of 6144 and has no 192). B/N have no channel there: structured
/// error, to be routed to the skip ledger by the assembly layer.
#[test]
fn sbs192_rejects_bidirectional_and_no_strand() {
    for strand in [Strand::Bidirectional, Strand::None] {
        let err = assign_sbs192(b"ACA", b'G', strand).unwrap_err();
        assert_eq!(err.topic, "argument");
        assert!(err.message.contains("SBS192"));
    }
}

#[test]
fn slice_variants_check_window_length() {
    let err = assign_sbs96_slice(b"AC", b'G').unwrap_err();
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(2));
    let err = assign_sbs96_slice(b"ACAA", b'G').unwrap_err();
    assert_eq!(err.i, Some(4));
    assert_eq!(assign_sbs96_slice(b"ACA", b'G').unwrap(), 4);
    let err = assign_sbs1536_slice(b"ACAC", b'G').unwrap_err();
    assert_eq!(err.i, Some(4));
    let err = assign_sbs1536_slice(b"ACACAC", b'G').unwrap_err();
    assert_eq!(err.i, Some(6));
    assert_eq!(assign_sbs1536_slice(b"ACACA", b'G').unwrap(), 1419);
    let _ = assign_sbs192_slice(b"ACA", b'G', Strand::Transcribed).unwrap();
    let _ = assign_sbs384_slice(b"ACA", b'G', Strand::None).unwrap();
    // Wrong lengths on the stranded slice variants too.
    assert_eq!(assign_sbs192_slice(b"AC", b'G', Strand::Transcribed).unwrap_err().i, Some(2));
    assert_eq!(assign_sbs384_slice(b"ACAA", b'G', Strand::None).unwrap_err().i, Some(4));
}

#[test]
fn channel_label_bounds_error_is_structured() {
    let err = channel_label(&SBS96_CHANNELS, 96).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(97)); // 1-based
    assert_eq!(err.j, Some(96)); // table length
    let err = channel_label(&SBS1536_CHANNELS, 1536).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(1537));
    assert_eq!(err.j, Some(1536));
    assert_eq!(channel_label(&SBS96_CHANNELS, 0).unwrap(), "A[C>A]A");
    assert_eq!(channel_label(&SBS384_CHANNELS, 383).unwrap(), "N:T[T>G]T");
}

/// MsError payload round-trips as a std error with the 1-based context.
#[test]
fn errors_display_with_indices() {
    let err = channel_label(&SBS192_CHANNELS, 500).unwrap_err();
    let text = err.to_string();
    assert!(text.contains("i=501"), "display carries 1-based index: {text}");
}
