//! Golden and property tests for DBS78 doublet-substitution arithmetic
//! (U-M1s-07; D11 "semantic bit" acceptance: integer + label goldens).
//!
//! Semantics (SPMG, audited at `docs/research/04` section 1 and pinned by
//! `data-raw/build_channels.R` / `channels.rs`):
//!   * a doublet substitution is two SNVs at distance exactly 1
//!     (`dinuc_sub == 1`);
//!   * the reference dinucleotide is canonicalized against SPMG's pinned
//!     10-ref set {AC, AT, CC, CG, CT, GC, TA, TC, TG, TT}: a ref outside
//!     the set is reverse-complemented together with its alt (the whole
//!     5-mer flips; SPMG `:673-694`). The set membership rule is a source
//!     constant, not pure "pyrimidine start": the mixed pairs canonicalize
//!     to AC (not GT) and TG (not CA), and the self-revcompl refs
//!     AT/CG/GC/TA are canonical as-is (U-M0-05 devlog: no consistent
//!     algorithmic rule — pinned to the SPMG constant lists);
//!   * Q-type refs (self-revcompl AT/CG/GC/TA) fold each revcompl-alt pair
//!     {NZ, revcompl(NZ)} to the SPMG-pinned member (keep sets of
//!     `build_channels.R` `.dbs_fold_keep`); self-revcompl alts are kept
//!     as-is;
//!   * canonical order is ASCII lexicographic of the `XY>NZ` label.
//!
//! Every golden index below is hand-derived from the block layout
//! (offsets: AC:0, AT:9, CC:15, CG:24, CT:30, GC:39, TA:45, TC:51, TG:60,
//! TT:69; alts ASCII-sorted within each ref) and cross-checked against the
//! generated `DBS78_CHANNELS` table.

use std::collections::HashSet;

use msuiter_catalog::channels::DBS78_CHANNELS;
use msuiter_catalog::dbs::{adjacent_snv_pair, assign_dbs78, dbs78_label};

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

fn revcompl(d: &[u8; 2]) -> [u8; 2] {
    [comp(d[1]), comp(d[0])]
}

// ---------------------------------------------------------------------------
// Golden vectors (hand-derived index + label).
// ---------------------------------------------------------------------------

/// 62 hand-derived variants: pyrimidine-start refs (CC/CT/TC/TT), the two
/// mixed refs (AC/TG), all six alts of each Q-type ref (AT/CG/GC/TA), the
/// Q-type alt folding (mirror alt -> pinned kept alt), and purine-first
/// inputs that flip the whole pair.
#[test]
fn golden_dbs78() {
    // (ref dinuc, alt dinuc, expected index, expected label)
    let golden: &[(&[u8; 2], &[u8; 2], usize, &str)] = &[
        // Pyrimidine-start refs: used as-is, 9-alt blocks.
        (b"CC", b"TT", 23, "CC>TT"),
        (b"CC", b"GA", 18, "CC>GA"),
        (b"CC", b"GG", 19, "CC>GG"),
        (b"CT", b"AC", 31, "CT>AC"),
        (b"CT", b"TG", 38, "CT>TG"),
        (b"CT", b"GC", 34, "CT>GC"),
        (b"TC", b"GT", 59, "TC>GT"),
        (b"TC", b"CA", 54, "TC>CA"),
        (b"TC", b"AG", 52, "TC>AG"),
        (b"TT", b"GG", 77, "TT>GG"),
        (b"TT", b"CA", 72, "TT>CA"),
        (b"TT", b"AG", 71, "TT>AG"),
        // Mixed refs (SPMG-pinned pair choices AC over GT, TG over CA).
        (b"AC", b"TG", 7, "AC>TG"),
        (b"AC", b"CA", 0, "AC>CA"),
        (b"AC", b"TT", 8, "AC>TT"),
        (b"TG", b"GT", 68, "TG>GT"),
        (b"TG", b"AC", 61, "TG>AC"),
        (b"TG", b"AT", 62, "TG>AT"),
        // Q-type refs: all six pinned alts of each.
        (b"AT", b"CA", 9, "AT>CA"),
        (b"AT", b"CC", 10, "AT>CC"),
        (b"AT", b"CG", 11, "AT>CG"),
        (b"AT", b"GA", 12, "AT>GA"),
        (b"AT", b"GC", 13, "AT>GC"),
        (b"AT", b"TA", 14, "AT>TA"),
        (b"CG", b"AT", 24, "CG>AT"),
        (b"CG", b"GC", 25, "CG>GC"),
        (b"CG", b"GT", 26, "CG>GT"),
        (b"CG", b"TA", 27, "CG>TA"),
        (b"CG", b"TC", 28, "CG>TC"),
        (b"CG", b"TT", 29, "CG>TT"),
        (b"GC", b"AA", 39, "GC>AA"),
        (b"GC", b"AG", 40, "GC>AG"),
        (b"GC", b"AT", 41, "GC>AT"),
        (b"GC", b"CA", 42, "GC>CA"),
        (b"GC", b"CG", 43, "GC>CG"),
        (b"GC", b"TA", 44, "GC>TA"),
        (b"TA", b"AT", 45, "TA>AT"),
        (b"TA", b"CG", 46, "TA>CG"),
        (b"TA", b"CT", 47, "TA>CT"),
        (b"TA", b"GC", 48, "TA>GC"),
        (b"TA", b"GG", 49, "TA>GG"),
        (b"TA", b"GT", 50, "TA>GT"),
        // Q-type alt folding: the revcompl mirror of a dropped alt lands on
        // the SPMG-pinned kept member of its pair.
        (b"AT", b"GG", 10, "AT>CC"), // revcompl(GG) = CC
        (b"AT", b"TG", 9, "AT>CA"),  // revcompl(TG) = CA
        (b"AT", b"TC", 12, "AT>GA"), // revcompl(TC) = GA
        (b"CG", b"AA", 29, "CG>TT"), // revcompl(AA) = TT
        (b"CG", b"AC", 26, "CG>GT"), // revcompl(AC) = GT
        (b"CG", b"GA", 28, "CG>TC"), // revcompl(GA) = TC
        (b"GC", b"TT", 39, "GC>AA"), // revcompl(TT) = AA
        (b"GC", b"CT", 40, "GC>AG"), // revcompl(CT) = AG
        (b"GC", b"TG", 42, "GC>CA"), // revcompl(TG) = CA
        (b"TA", b"AC", 50, "TA>GT"), // revcompl(AC) = GT
        (b"TA", b"CC", 49, "TA>GG"), // revcompl(CC) = GG
        (b"TA", b"AG", 47, "TA>CT"), // revcompl(AG) = CT
        // Purine-first inputs: ref outside the canonical set flips the whole
        // pair (revcompl of ref and alt).
        (b"AA", b"TT", 69, "TT>AA"), // -> TT>AA
        (b"GG", b"CC", 19, "CC>GG"), // -> CC>GG
        (b"AG", b"TC", 33, "CT>GA"), // -> CT>GA (revcompl(AG) = CT)
        (b"GA", b"CT", 52, "TC>AG"), // -> TC>AG (revcompl(GA) = TC)
        (b"GT", b"CA", 7, "AC>TG"),  // -> AC>TG
        (b"CA", b"TG", 63, "TG>CA"), // -> TG>CA
        (b"AA", b"GG", 73, "TT>CC"), // -> TT>CC
        (b"GT", b"AA", 8, "AC>TT"),  // -> AC>TT
    ];
    for &(ref2, alt2, idx, label) in golden {
        assert_eq!(
            assign_dbs78(ref2, alt2).unwrap(),
            idx,
            "ref={:?} alt={:?}",
            String::from_utf8_lossy(ref2),
            String::from_utf8_lossy(alt2)
        );
        assert_eq!(dbs78_label(idx).unwrap(), label);
        // The label must also sit at that position in the canonical table.
        assert_eq!(DBS78_CHANNELS[idx], label);
    }
}

/// Explicit failure modes: a non-ACGT byte anywhere, or an unchanged
/// doublet position (ref[k] == alt[k]), is a structured `argument` error.
#[test]
fn error_paths() {
    // Unchanged doublet position: i = 1-based site within the doublet.
    let err = assign_dbs78(b"CC", b"GC").unwrap_err(); // site 2 unchanged
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(2));
    let err = assign_dbs78(b"CC", b"CT").unwrap_err(); // site 1 unchanged
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(1));
    let err = assign_dbs78(b"CC", b"CA").unwrap_err(); // site 1 unchanged
    assert_eq!(err.topic, "argument");
    assert_eq!(err.i, Some(1));
    // Non-ACGT bytes: i = 1-based base position over the 4 input bytes
    // (ref2[0]=1, ref2[1]=2, alt2[0]=3, alt2[1]=4).
    for (ref2, alt2, pos) in [
        (b"CN" as &[u8; 2], b"AT" as &[u8; 2], 2),
        (b"NC", b"AT", 1),
        (b"CC", b"AN", 4),
        (b"CC", b"TN", 4),
        (b"cc", b"gt", 1), // lowercase is not an allele byte
    ] {
        let err = assign_dbs78(ref2, alt2).unwrap_err();
        assert_eq!(err.topic, "argument", "{:?} {:?}", ref2, alt2);
        assert_eq!(err.i, Some(pos), "{:?} {:?}", ref2, alt2);
    }
    // Label accessor bounds error (FFI contract 4: i = 1-based, j = len).
    let err = dbs78_label(78).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(79));
    assert_eq!(err.j, Some(78));
}

// ---------------------------------------------------------------------------
// Properties.
// ---------------------------------------------------------------------------

/// Exhaustive bijection with the generated table: for every canonical
/// label, parsing `XY>NZ` and assigning returns exactly its table position.
#[test]
fn exhaustive_table_bijection() {
    for (idx, label) in DBS78_CHANNELS.iter().enumerate() {
        let b = label.as_bytes();
        assert_eq!(b[2], b'>');
        let ref2: [u8; 2] = [b[0], b[1]];
        let alt2: [u8; 2] = [b[3], b[4]];
        assert_eq!(assign_dbs78(&ref2, &alt2).unwrap(), idx, "label={}", label);
    }
}

/// The 144 doublet mutations where both positions change (16 refs x 9
/// changed alts) all assign, and their image is exactly the 78 channels.
#[test]
fn image_of_144_doublets_is_78_channels() {
    let mut hits = [0usize; 78];
    let mut total = 0usize;
    for &x in &BASES {
        for &y in &BASES {
            for &n in &BASES {
                for &z in &BASES {
                    if n == x || z == y {
                        continue; // both positions must change
                    }
                    let ref2 = [x, y];
                    let alt2 = [n, z];
                    let idx = assign_dbs78(&ref2, &alt2).expect("valid doublet assigns");
                    hits[idx] += 1;
                    total += 1;
                }
            }
        }
    }
    assert_eq!(total, 144);
    assert!(hits.iter().all(|&c| c > 0), "every channel is reachable");
}

/// Pyrimidine-start invariant: complement-flipping a whole valid input
/// (revcompl of ref and alt) lands on the same channel.
#[test]
fn revcompl_invariant() {
    for &x in &BASES {
        for &y in &BASES {
            for &n in &BASES {
                for &z in &BASES {
                    if n == x || z == y {
                        continue;
                    }
                    let ref2 = [x, y];
                    let alt2 = [n, z];
                    let flipped_ref = revcompl(&ref2);
                    let flipped_alt = revcompl(&alt2);
                    assert_eq!(
                        assign_dbs78(&ref2, &alt2).unwrap(),
                        assign_dbs78(&flipped_ref, &flipped_alt).unwrap(),
                        "{:?}>{:?}",
                        String::from_utf8_lossy(&ref2),
                        String::from_utf8_lossy(&alt2)
                    );
                }
            }
        }
    }
}

/// Revcompl-pair coverage contract (same spirit as `build_channels.R`'s
/// 144-doublet assertion): over the 144 doublet mutations, exactly one of
/// each revcompl pair is a DBS78 channel, and every self-revcompl mutation
/// is a channel.
#[test]
fn revcompl_pair_coverage() {
    let table: HashSet<&str> = DBS78_CHANNELS.iter().copied().collect();
    for &x in &BASES {
        for &y in &BASES {
            for &n in &BASES {
                for &z in &BASES {
                    if n == x || z == y {
                        continue;
                    }
                    let m = format!("{}{}>{}{}", x as char, y as char, n as char, z as char);
                    let r = revcompl(&[x, y]);
                    let a = revcompl(&[n, z]);
                    let mirror = format!(
                        "{}{}>{}{}",
                        r[0] as char, r[1] as char, a[0] as char, a[1] as char
                    );
                    if m == mirror {
                        assert!(
                            table.contains(m.as_str()),
                            "self-revcompl mutation {} missing from the channel set",
                            m
                        );
                    } else {
                        assert_ne!(
                            table.contains(m.as_str()),
                            table.contains(mirror.as_str()),
                            "revcompl-pair coverage violated for {} / {}",
                            m,
                            mirror
                        );
                    }
                }
            }
        }
    }
}

/// Q-type refs keep their self-revcompl alts verbatim: the assigned channel
/// label equals the raw input label (no fold).
#[test]
fn q_type_self_revcompl_alts_are_kept() {
    let golden: &[(&[u8; 2], &[u8; 2])] = &[
        (b"AT", b"CG"),
        (b"AT", b"GC"),
        (b"AT", b"TA"),
        (b"CG", b"AT"),
        (b"CG", b"GC"),
        (b"CG", b"TA"),
        (b"GC", b"AT"),
        (b"GC", b"CG"),
        (b"GC", b"TA"),
        (b"TA", b"AT"),
        (b"TA", b"CG"),
        (b"TA", b"GC"),
    ];
    for (ref2, alt2) in golden {
        let idx = assign_dbs78(ref2, alt2).unwrap();
        let label = format!(
            "{}{}>{}{}",
            ref2[0] as char, ref2[1] as char, alt2[0] as char, alt2[1] as char
        );
        assert_eq!(DBS78_CHANNELS[idx], label);
    }
}

// ---------------------------------------------------------------------------
// Adjacency (DBS candidacy of two single-base records).
// ---------------------------------------------------------------------------

/// Two SNVs at distance exactly 1 form a DBS candidate; the concatenated
/// dinucleotides feed `assign_dbs78` directly.
#[test]
fn adjacent_snv_pair_golden() {
    let (ref2, alt2) = adjacent_snv_pair(5, b'C', b'A', 6, b'T', b'G').expect("adjacent");
    assert_eq!(ref2, *b"CT");
    assert_eq!(alt2, *b"AG");
    let idx = assign_dbs78(&ref2, &alt2).unwrap();
    assert_eq!(idx, 32);
    assert_eq!(dbs78_label(idx).unwrap(), "CT>AG");

    // Purine-first pair flips onto the canonical channel: revcompl(AG) = CT,
    // revcompl(TC) = GA, so the input lands on "CT>GA".
    let (ref2, alt2) = adjacent_snv_pair(0, b'A', b'T', 1, b'G', b'C').expect("adjacent");
    assert_eq!(ref2, *b"AG");
    let idx = assign_dbs78(&ref2, &alt2).unwrap();
    assert_eq!(dbs78_label(idx).unwrap(), "CT>GA");
}

/// Non-candidates: wrong distance (gap, same position, reversed order) and
/// non-ACGT alleles all return `None`; REF-vs-genome validation stays
/// upstream with the assembly layer.
#[test]
fn adjacent_snv_pair_rejects() {
    // Gap of 2.
    assert!(adjacent_snv_pair(5, b'C', b'A', 7, b'T', b'G').is_none());
    // Same position.
    assert!(adjacent_snv_pair(5, b'C', b'A', 5, b'T', b'G').is_none());
    // Reversed order (pos2 must be pos1 + 1 exactly).
    assert!(adjacent_snv_pair(6, b'C', b'A', 5, b'T', b'G').is_none());
    // Non-ACGT allele bytes.
    assert!(adjacent_snv_pair(5, b'N', b'A', 6, b'T', b'G').is_none());
    assert!(adjacent_snv_pair(5, b'C', b'a', 6, b'T', b'G').is_none());
    assert!(adjacent_snv_pair(5, b'C', b'A', 6, b'T', b'N').is_none());
}
