//! ID83 golden + property tests (U-M1c-01).
//!
//! Semantic source of truth: `docs/devlog/2026-09-30-ID83-design-memo.md`
//! (the adjudicated spec), itself pinned line-by-line to SPMG
//! `MutationMatrixGenerator.py` (MMG) / `SigProfilerMatrixGeneratorFunc.py`
//! (Func) at upstream master `edccbea6`. The ID classification function is
//! byte-identical between master and tag v1.3.6 (memo §1.1), so every
//! golden here simultaneously pins both versions (D11, memo §6).
//!
//! Golden convention: the memo lists 1-based genome FRAGMENTS; each test
//! embeds its fragment between 8×`N` pads (prefix/suffix). `N` never
//! matches an ACGT unit byte, so pad flanks are provably
//! non-extensions and every derivation is fragment-local. POS is the
//! 1-based VCF anchor position inside the fragment (`pos0 = 8 + POS - 1`).
//! Wraparound goldens (G31) build explicit contigs with the anchor at a
//! real contig edge instead.
//!
//! Line references in comments are SPMG master MMG unless marked Func.

#[path = "genome/fixture.rs"]
#[allow(dead_code)] // shared fixture matrix; this suite uses a subset
mod fixture;

use msuiter_catalog::genome::TwoBitGenome;
use msuiter_catalog::indel83::{
    assign_indel83_genome, assign_indel83_slice, indel83_label, q_predicate, ID83_CHANNELS,
    Indel83Outcome,
};
use msuiter_catalog::mnv::{
    route_variants, Destination, LedgerEntry, RoutedEvent, SkipReason, VarRecord,
};
use msuiter_catalog::sbs::Strand;
use msuiter_engine::MsError;

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

/// 8×`N` prefix/suffix: neutral pads around a memo fragment.
const PAD: usize = 8;

/// Embed `frag` between neutral `N` pads.
fn padded(frag: &str) -> Vec<u8> {
    let mut c = vec![b'N'; PAD];
    c.extend_from_slice(frag.as_bytes());
    c.extend_from_slice(&[b'N'; PAD]);
    c
}

/// 0-based anchor for 1-based fragment POS inside a padded fragment.
fn pos0_of(pos1: usize) -> u64 {
    (PAD + pos1 - 1) as u64
}

/// Assign on a padded fragment (the golden workhorse).
fn assign(frag: &str, pos1: usize, ref_: &[u8], alt: &[u8]) -> Result<Indel83Outcome, MsError> {
    assign_indel83_slice(&padded(frag), pos0_of(pos1), ref_, alt)
}

/// Unwrap a golden to its channel index.
fn chan(out: Result<Indel83Outcome, MsError>) -> usize {
    match out.expect("golden must classify") {
        Indel83Outcome::Channel(i) => i,
        other => panic!("expected a channel, got {other:?}"),
    }
}

/// Channel index AND canonical label must agree (table is the anchor).
fn chan_label(frag: &str, pos1: usize, ref_: &[u8], alt: &[u8]) -> (usize, &'static str) {
    let i = chan(assign(frag, pos1, ref_, alt));
    (i, indel83_label(i).unwrap())
}

fn rec<'a>(pos: u64, ref_: &'a [u8], alt: &'a [u8]) -> VarRecord<'a> {
    VarRecord::new(pos, ref_, alt)
}

fn mark_hit(hit: &mut [bool], tag: &str, out: Result<Indel83Outcome, MsError>) {
    match out.expect("sweep case must classify") {
        Indel83Outcome::Channel(i) => hit[i] = true,
        other => panic!("sweep case {tag}: unexpected outcome {other:?}"),
    }
}

// ---------------------------------------------------------------------------
// Channel-table structural contract (Func:1054-1138, iloc[:83] MMG:3738).
// ---------------------------------------------------------------------------

/// The full canonical 83-label table, transcribed from SPMG
/// `SigProfilerMatrixGeneratorFunc.py:1054-1138` (rows 0..83 of
/// `indel_types`; rows 83-95 are the Ins:M extension rows plus the
/// complex/non_matching bookkeeping rows and are NOT ID83).
fn expected_table() -> Vec<&'static str> {
    let mut t: Vec<&'static str> = Vec::new();
    for k4 in 0..6 {
        t.push(Box::leak(format!("1:Del:C:{k4}").into_boxed_str()));
    }
    for k4 in 0..6 {
        t.push(Box::leak(format!("1:Del:T:{k4}").into_boxed_str()));
    }
    for k4 in 0..6 {
        t.push(Box::leak(format!("1:Ins:C:{k4}").into_boxed_str()));
    }
    for k4 in 0..6 {
        t.push(Box::leak(format!("1:Ins:T:{k4}").into_boxed_str()));
    }
    for k1 in 2..=5 {
        for k4 in 0..6 {
            t.push(Box::leak(format!("{k1}:Del:R:{k4}").into_boxed_str()));
        }
    }
    for k1 in 2..=5 {
        for k4 in 0..6 {
            t.push(Box::leak(format!("{k1}:Ins:R:{k4}").into_boxed_str()));
        }
    }
    // Microhomology blocks (Func:1122-1138 Del half): key4 upper bound is
    // key1-1 (MH homology length <= L-1), except key1=5 which also carries
    // L>5 events with key4 capped at 5.
    t.extend_from_slice(&["2:Del:M:1"]);
    t.extend_from_slice(&["3:Del:M:1", "3:Del:M:2"]);
    t.extend_from_slice(&["4:Del:M:1", "4:Del:M:2", "4:Del:M:3"]);
    t.extend_from_slice(&[
        "5:Del:M:1",
        "5:Del:M:2",
        "5:Del:M:3",
        "5:Del:M:4",
        "5:Del:M:5",
    ]);
    t
}

#[test]
fn table_is_exactly_the_spmg_iloc83_order() {
    let expected = expected_table();
    assert_eq!(ID83_CHANNELS.len(), 83);
    assert_eq!(&ID83_CHANNELS, expected.as_slice());
}

/// Block boundaries of the canonical order (memo §2.1): the 1bp C/T blocks,
/// then Del R, Ins R, then Del M. NOT one global ASCII sort (memo §2.2's
/// "ASCII" remark is loose; the authoritative index is Func:1054-1138 where
/// M blocks follow R blocks).
#[test]
fn table_block_boundaries() {
    assert_eq!(ID83_CHANNELS[0], "1:Del:C:0");
    assert_eq!(ID83_CHANNELS[5], "1:Del:C:5");
    assert_eq!(ID83_CHANNELS[6], "1:Del:T:0");
    assert_eq!(ID83_CHANNELS[11], "1:Del:T:5");
    assert_eq!(ID83_CHANNELS[12], "1:Ins:C:0");
    assert_eq!(ID83_CHANNELS[17], "1:Ins:C:5");
    assert_eq!(ID83_CHANNELS[18], "1:Ins:T:0");
    assert_eq!(ID83_CHANNELS[23], "1:Ins:T:5");
    assert_eq!(ID83_CHANNELS[24], "2:Del:R:0");
    assert_eq!(ID83_CHANNELS[47], "5:Del:R:5");
    assert_eq!(ID83_CHANNELS[48], "2:Ins:R:0");
    assert_eq!(ID83_CHANNELS[71], "5:Ins:R:5");
    assert_eq!(ID83_CHANNELS[72], "2:Del:M:1");
    assert_eq!(ID83_CHANNELS[82], "5:Del:M:5");
}

/// `indel83_label` bounds discipline (FFI contract 4): i = 1-based index,
/// j = table length.
#[test]
fn label_bounds_error() {
    for (i, &label) in ID83_CHANNELS.iter().enumerate() {
        assert_eq!(indel83_label(i).unwrap(), label);
    }
    let err = indel83_label(83).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(84));
    assert_eq!(err.j, Some(83));
}

// ---------------------------------------------------------------------------
// Goldens G1-G8: 1 bp deletions (walk MMG:1451-1482, keys MMG:1673-1685).
// ---------------------------------------------------------------------------

/// G1 | `C A T G` | 2/AT/A | 1:Del:T:0
/// left window = anchor A != T (:1462); right window = G != T (:1471);
/// ref[1] = T -> T (:1684).
#[test]
fn g1_del_1bp_t_zero_extension() {
    let (i, l) = chan_label("CATG", 2, b"AT", b"A");
    assert_eq!((i, l), (6, "1:Del:T:0"));
}

/// G2 | `G A C A` | 2/AC/A | 1:Del:C:0 — zero extension both ways;
/// ref[1] = C -> C (:1682).
#[test]
fn g2_del_1bp_c_zero_extension() {
    let (i, l) = chan_label("GACA", 2, b"AC", b"A");
    assert_eq!((i, l), (0, "1:Del:C:0"));
}

/// G3 | `A C C A` | 1/AC/A | 1:Del:C:1 — right window pos3 = C, one
/// extension -> key4 = 1.
#[test]
fn g3_del_1bp_c_one_extension() {
    let (i, l) = chan_label("ACCA", 1, b"AC", b"A");
    assert_eq!((i, l), (1, "1:Del:C:1"));
}

/// G4 | `A T T T T G` | 1/AT/A | 1:Del:T:3 — right chain 3xT (:1474-1482);
/// left window = anchor A, stop.
#[test]
fn g4_del_1bp_t_three_extensions() {
    let (i, l) = chan_label("ATTTTG", 1, b"AT", b"A");
    assert_eq!((i, l), (9, "1:Del:T:3"));
}

/// G5 | `A T^7 G` | 1/AT/A | 1:Del:T:5 — 6 extensions, key4 capped at 5
/// (:1676-1677).
#[test]
fn g5_del_1bp_t_cap_at_5() {
    let (i, l) = chan_label("ATTTTTTTG", 1, b"AT", b"A");
    assert_eq!((i, l), (11, "1:Del:T:5"));
}

/// G6 | `A G G A` | 1/AG/A | 1:Del:C:1 — PURINE deletion maps to C:
/// ref[1] = G in {C,G} -> "C" (:1682).
#[test]
fn g6_del_1bp_purine_maps_c() {
    let (i, l) = chan_label("AGGA", 1, b"AG", b"A");
    assert_eq!((i, l), (1, "1:Del:C:1"));
}

/// G7 | `T C A` | 1/TC/T | 1:Del:C:0 — zero extension (anchor-invariance
/// counterpart of G1). Coordinate note: the anchor is T@1, so the VCF POS
/// is 1 (the memo row's "2" would put the anchor on the deleted base).
#[test]
fn g7_del_1bp_c_anchor_t() {
    let (i, l) = chan_label("TCA", 1, b"TC", b"T");
    assert_eq!((i, l), (0, "1:Del:C:0"));
}

/// G8 | `A T T T T G` | 3/TT/T | 1:Del:T:3 — ANCHOR INVARIANCE (F1): the
/// same physical event as G4 with a mid-run anchor lands on the same
/// channel. Left windows run T,T then hit A; right gives one T.
#[test]
fn g8_del_1bp_anchor_invariance() {
    let (i, l) = chan_label("ATTTTG", 3, b"TT", b"T");
    assert_eq!((i, l), (9, "1:Del:T:3"));
}

// ---------------------------------------------------------------------------
// Goldens G9-G13: 1 bp insertions (walk MMG:1543-1571, keys MMG:1718-1730).
// ---------------------------------------------------------------------------

/// G9 | `C A` | 1/C/CT | 1:Ins:T:0 — left window = anchor C != T, right
/// window A != T; mut[1] = T -> T (:1729).
#[test]
fn g9_ins_1bp_t_zero_extension() {
    let (i, l) = chan_label("CA", 1, b"C", b"CT");
    assert_eq!((i, l), (18, "1:Ins:T:0"));
}

/// G10 | `A A A G` | 2/A/AA | 1:Ins:T:3 — left windows hold the anchor
/// (2xA) plus one right A (left guard `pos_rev - 1 > 0` stops at pos1,
/// :1553) -> 4xA.
#[test]
fn g10_ins_1bp_t_three_extensions() {
    let (i, l) = chan_label("AAAG", 2, b"A", b"AA");
    assert_eq!((i, l), (21, "1:Ins:T:3"));
}

/// G11 | `C A` | 1/C/CG | 1:Ins:C:0 — mut[1] = G in {C,G} -> C (:1727).
#[test]
fn g11_ins_1bp_purine_maps_c() {
    let (i, l) = chan_label("CA", 1, b"C", b"CG");
    assert_eq!((i, l), (12, "1:Ins:C:0"));
}

/// G12 | `A T^6 G` | 2/T/TT | 1:Ins:T:5 — post-insertion run of 7 ->
/// 6 extensions -> capped 5 (:1722-1723).
#[test]
fn g12_ins_1bp_t_cap_at_5() {
    let (i, l) = chan_label("ATTTTTTG", 2, b"T", b"TT");
    assert_eq!((i, l), (23, "1:Ins:T:5"));
}

/// G13 | `A T C` | 1/A/AT | 1:Ins:T:1 — left window = anchor A != T;
/// right window T -> run-of-2 semantics.
#[test]
fn g13_ins_1bp_t_one_extension() {
    let (i, l) = chan_label("ATC", 1, b"A", b"AT");
    assert_eq!((i, l), (19, "1:Ins:T:1"));
}

// ---------------------------------------------------------------------------
// Goldens G14-G20: tandem-repeat deletions (key4 = copies - 1,
// normalization on the UNCAPPED L, MMG:1645-1659).
// ---------------------------------------------------------------------------

/// G14 | `T A CG CG A` | 2/ACG/A | 2:Del:R:1 — right window = "CG" -> 2
/// copies -> int(4/2 - 1) = 1; left window "AC" != "CG".
#[test]
fn g14_del_2bp_r_one() {
    let (i, l) = chan_label("TACGCGA", 2, b"ACG", b"A");
    assert_eq!((i, l), (25, "2:Del:R:1"));
}

/// G15 | `T A C G A A` | 2/ACG/A | 2:Del:R:0 — right window "AA" != "CG".
#[test]
fn g15_del_2bp_r_zero() {
    let (i, l) = chan_label("TACGAA", 2, b"ACG", b"A");
    assert_eq!((i, l), (24, "2:Del:R:0"));
}

/// G16 | `C A A (CAG)^2 T` | 3/ACAG/A | 3:Del:R:1 — right window "CAG" ->
/// 6/3 - 1 = 1.
#[test]
fn g16_del_3bp_r_one() {
    let (i, l) = chan_label("CAACAGCAGT", 3, b"ACAG", b"A");
    assert_eq!((i, l), (31, "3:Del:R:1"));
}

/// G17 | `(CAG)^4` | 3/GCAG/G | 3:Del:R:3 — 4 copies -> 12/3 - 1 = 3.
/// (Anchor correction vs the memo row, source rule :1408-1421: the anchor
/// byte must equal the genome, so deleting the second "CAG" copy anchors
/// on the preceding G — "ACAG" would be an anchor mismatch on `(CAG)^4`.
/// Same physical event, unchanged expected channel.)
#[test]
fn g17_del_3bp_r_three() {
    let (i, l) = chan_label("CAGCAGCAGCAG", 3, b"GCAG", b"G");
    assert_eq!((i, l), (33, "3:Del:R:3"));
}

/// G18 | `(ACGT)^4` (memo fragment `(ACGT)^3` plus the continuation its
/// `ACGT…` REF anticipates) | 1/ACGTA/A | 4:Del:R:2 — deleted "CGTA",
/// two right matches -> 12/4 - 1 = 2.
#[test]
fn g18_del_4bp_r_two() {
    let (i, l) = chan_label("ACGTACGTACGTACGT", 1, b"ACGTA", b"A");
    assert_eq!((i, l), (38, "4:Del:R:2"));
}

/// G19 | `(ACGTA)^4` (memo `(ACGTA)^3` + continuation) | 1/ACGTAA/A |
/// 5:Del:R:2 — key1 capped 5; 15/5 - 1 = 2.
#[test]
fn g19_del_5bp_r_two() {
    let (i, l) = chan_label("ACGTAACGTAACGTAACGTA", 1, b"ACGTAA", b"A");
    assert_eq!((i, l), (44, "5:Del:R:2"));
}

/// G20 | `(CGTACGA)^2 C` (7 bp unit) | 1/CGTACGAC/C | 5:Del:R:1 — key4 is
/// normalized by the UNCAPPED L = 7: int(14/7 - 1) = 1; key1 alone caps
/// to 5 (:1646-1650 vs :1655). The trailing C completes the second copy;
/// everything after is `N`.
#[test]
fn g20_del_7bp_key4_uses_uncapped_l() {
    let mut chrom = vec![b'N'; PAD];
    chrom.extend_from_slice(b"CGTACGACGTACGAC");
    chrom.extend_from_slice(&[b'N'; PAD]);
    let out = assign_indel83_slice(&chrom, PAD as u64, b"CGTACGAC", b"C").unwrap();
    let i = chan(Ok(out));
    assert_eq!((i, indel83_label(i).unwrap()), (43, "5:Del:R:1"));
}

// ---------------------------------------------------------------------------
// Goldens G21-G27: microhomology deletions (R before M priority MMG:1484;
// longest-first MMG:1512-1532; forward wins ties MMG:1534-1540).
// ---------------------------------------------------------------------------

/// G21 | `G A A C A G` | 2/AAC/A | 2:Del:M:1 — walk zero-extends;
/// fwd_hom "A" hits pos5 = A (:1512-1521) -> key4 = 3 - 2 = 1 (:1664).
#[test]
fn g21_del_mh_forward_hit() {
    let (i, l) = chan_label("GAACAG", 2, b"AAC", b"A");
    assert_eq!((i, l), (72, "2:Del:M:1"));
}

/// G22 | `A T G T A` | 2/TGT/T | 2:Del:M:1 — fwd "G" misses (pos5 = A);
/// rev_hom "T" hits the anchor (:1523-1532) -> reverse path; the ID83
/// channel is direction-blind (M).
#[test]
fn g22_del_mh_reverse_hit() {
    let (i, l) = chan_label("ATGTA", 2, b"TGT", b"T");
    assert_eq!((i, l), (72, "2:Del:M:1"));
}

/// G23 (memo text version) | `T T C C A G C A G A T` | 4/CAGC/C |
/// 3:Del:M:2 — fwd(2) > rev(1) -> forward (:1534-1537);
/// sequence = "AGCAG" -> key4 = 5 - 3 = 2.
#[test]
fn g23_del_mh_forward_longest() {
    let (i, l) = chan_label("TTCCAGCAGAT", 4, b"CAGC", b"C");
    assert_eq!((i, l), (74, "3:Del:M:2"));
}

/// G24 | `A A A T CGT C A A` | 4/TCGT/T | 3:Del:M:1 — TIE -> forward
/// (:1535): rev_hom "T" hits the anchor (1); fwd_hom "CG" falls through
/// to "C" (1); equal lengths -> forward. (The ID83 label is identical
/// either way — the golden pins the rule, memo §3.5.)
#[test]
fn g24_del_mh_tie_goes_forward() {
    let (i, l) = chan_label("AAATCGTCAA", 4, b"TCGT", b"T");
    assert_eq!((i, l), (73, "3:Del:M:1"));
}

/// G25 | 6 bp deletion `CGTACG` with `CGTAC` (6th base != G) immediately
/// after | 1/ACGTACG/A fragment `ACGTACGCGTACT` | 5:Del:M:5 — fwd 5 hits
/// -> key4 = 11 - 6 = 5, NOT capped (exactly at cap, :1665-1666); key1
/// capped to 5. The right walk refuses the rotation (G36 semantics).
#[test]
fn g25_del_mh_key4_exactly_five() {
    let (i, l) = chan_label("ACGTACGCGTACT", 1, b"ACGTACG", b"A");
    assert_eq!((i, l), (82, "5:Del:M:5"));
}

/// G26 | deleted `TGCC`, `TG X` (X != C) after, no left tail match |
/// 1/ATGCC/A fragment `ATGCCTGAA` | 4:Del:M:2 — fwd i=3 fails, i=2 "TG"
/// hits (longest-first, :1514).
#[test]
fn g26_del_mh_longest_first() {
    let (i, l) = chan_label("ATGCCTGAA", 1, b"ATGCC", b"A");
    assert_eq!((i, l), (76, "4:Del:M:2"));
}

/// G27 | leading tandem + trailing MH | 4/AATA/A fragment `GATAAATAATC` |
/// 3:Del:R:1 — REPEAT BEATS MH: the left walk extends one copy first, so
/// the MH branch is never entered (:1485) even though a 2 bp forward MH
/// ("AT") is available.
#[test]
fn g27_del_repeat_beats_mh() {
    let (i, l) = chan_label("GATAAATAATC", 4, b"AATA", b"A");
    assert_eq!((i, l), (31, "3:Del:R:1"));
}

// ---------------------------------------------------------------------------
// Goldens G28-G30: Ins:M has no ID83 channel; complex stays complex.
// ---------------------------------------------------------------------------

/// G28 | insertion `CT` with `C` at the insertion point | no ID83 channel.
/// SPMG computes key "2:Ins:M:1" (Func:1128-1138) but writes only
/// `iloc[:83]` (MMG:3738) -> explicit structured skip (memo §5 G28).
#[test]
fn g28_ins_mh_no_channel() {
    let out = assign("AC", 1, b"A", b"ACT").unwrap();
    assert_eq!(out, Indel83Outcome::InsMicrohomologyNoChannel);
}

/// G29 | insertion `ACA` with `AC` after the point | "3:Ins:M:2" excluded
/// exactly like G28.
#[test]
fn g29_ins_mh_no_channel() {
    let out = assign("AAC", 1, b"A", b"AACA").unwrap();
    assert_eq!(out, Indel83Outcome::InsMicrohomologyNoChannel);
}

/// G30 | 2/ACGT/AG | complex indel: both alleles > 1 base, unequal lengths
/// (:1445-1449) -> the router keeps it on the ComplexIndel destination,
/// never inside the 83 vector.
#[test]
fn g30_complex_stays_complex() {
    let records = [rec(1, b"ACGT", b"AG")];
    let out = route_variants(&records);
    assert_eq!(out.ledger.entries()[0], LedgerEntry::ComplexIndel);
    assert_eq!(
        out.events[0],
        RoutedEvent::ComplexIndel { record: 0, pos: 1, ref_len: 4, alt_len: 2 }
    );
}

// ---------------------------------------------------------------------------
// Goldens G31-G33: chromosome-edge behaviour (F3 trio).
// ---------------------------------------------------------------------------

/// G31a | 2 bp deletion anchored at the contig HEAD, wrapped initial left
/// window (chrom tail + head) != unit | 2:Del:R:0. Python reads
/// `range(-1, 1)` = chrom[-1], chrom[0] (:1462) but the extension guard
/// `pos_rev - L > 0` short-circuits FIRST (:1464), so the wrapped window
/// is fetched (replicated — including its tail read) and discarded.
#[test]
fn g31a_head_wraparound_fetch_is_inert() {
    // anchor C@0, deleted "GT"@1-2, wrapped read = tail A + head C = "AC".
    let chrom = b"CGTCATTTTTTTTTTTTA";
    let out = assign_indel83_slice(chrom, 0, b"CGT", b"C").unwrap();
    match out {
        Indel83Outcome::Channel(i) => {
            assert_eq!((i, indel83_label(i).unwrap()), (24, "2:Del:R:0"));
        }
        other => panic!("expected a channel, got {other:?}"),
    }
}

/// G31b | same shape, wrapped initial window == unit | still no left
/// extension (the guard short-circuit resolves the memo's G31 variant B
/// at source: the fetched-and-discarded window cannot extend); the
/// reverse MH search then hits the anchor -> 2:Del:M:1.
#[test]
fn g31b_head_wraparound_match_does_not_extend() {
    // unit "TC" (anchor C, deleted TC); wrapped read = tail T + head C =
    // "TC" == unit, yet R stays at one copy.
    let chrom = b"CTCCATTTTTTTTTTTTT";
    let out = assign_indel83_slice(chrom, 0, b"CTC", b"C").unwrap();
    match out {
        Indel83Outcome::Channel(i) => {
            assert_eq!((i, indel83_label(i).unwrap()), (72, "2:Del:M:1"));
        }
        other => panic!("expected a channel, got {other:?}"),
    }
}

/// G31c (observable wraparound, source-derived completion of the memo
/// trio): 3 bp deletion at the contig head; the MH reverse search has NO
/// guard (:1523-1532) and its i=2 window `[-1, 1)` = chrom tail + head IS
/// compared and hits -> 3:Del:M:2. An implementation that skips wrapped
/// reads lands on R:0 here — this golden makes D11 wraparound-faithful.
#[test]
fn g31c_mh_reverse_search_reads_wrapped_and_hits() {
    // unit "ACA" (anchor A, deleted ACA); rev_hom = "CA"; wrapped i=2
    // window = tail C + head A = "CA" == rev_hom[-2:] -> reverse MH of 2.
    let chrom = b"AACATTTTTTTTTTTTC";
    let out = assign_indel83_slice(chrom, 0, b"AACA", b"A").unwrap();
    match out {
        Indel83Outcome::Channel(i) => {
            assert_eq!((i, indel83_label(i).unwrap()), (74, "3:Del:M:2"));
        }
        other => panic!("expected a channel, got {other:?}"),
    }
}

/// G32 | 1 bp deletion anchored at POS=1 | normal channel — the left
/// window is the anchor itself, `range(0, 1)` never wraps (:1462).
#[test]
fn g32_head_1bp_deletion_is_normal() {
    let chrom = b"ATTTTGGGGGG";
    let out = assign_indel83_slice(chrom, 0, b"AT", b"A").unwrap();
    match out {
        Indel83Outcome::Channel(i) => {
            assert_eq!((i, indel83_label(i).unwrap()), (9, "1:Del:T:3"));
        }
        other => panic!("expected a channel, got {other:?}"),
    }
}

/// G33 | deleted segment flush against the contig END (start+2L-1 > last)
/// | structured `bounds` error -> ledger skip upstream. SPMG's unguarded
/// initial right-window read (:1471) is an uncaught IndexError there; our
/// hardening turns the crash into a structured error (memo §6, D13).
#[test]
fn g33_tail_initial_window_is_structured_bounds_error() {
    let chrom = b"NNNNNNNNCAT";
    let err = assign_indel83_slice(chrom, 8, b"CAT", b"C").unwrap_err();
    assert_eq!(err.topic, "bounds");
}

// ---------------------------------------------------------------------------
// Goldens G34-G36: N handling and EXACT rotation semantics.
// ---------------------------------------------------------------------------

/// G34 | anchor reference base = N | AnchorMismatch -> ledger skip
/// (:1408-1421 anchor-vs-genome compare; tsb_ref[16] base "N").
#[test]
fn g34_anchor_n_is_a_mismatch_skip() {
    let chrom = b"NNNNNNNNNANTTTTTT";
    let out = assign_indel83_slice(chrom, 8, b"AT", b"A").unwrap();
    assert_eq!(out, Indel83Outcome::AnchorMismatch);
}

/// G35 | anchor ACGT but the flank after the deleted segment is N |
/// normal channel; N is an ordinary byte mismatch that truncates the walk
/// (byte comparison at :1463/:1476), never a skip.
#[test]
fn g35_flank_n_truncates_not_skips() {
    // frag "CA": the right window lands in the N pad behind the fragment.
    let (i, l) = chan_label("CA", 1, b"CA", b"C");
    assert_eq!((i, l), (6, "1:Del:T:0"));
}

/// G36 | 2 bp deletion `CG` with `GC` (a ROTATION) after | 1/ACG/A
/// fragment `ACGGCA` | 2:Del:R:0 — the walk compares windows EXACTLY to
/// the unit (`new_seq == type_sequence`, :1476); rotations never extend.
#[test]
fn g36_rotation_does_not_extend() {
    let (i, l) = chan_label("ACGGCA", 1, b"ACG", b"A");
    assert_eq!((i, l), (24, "2:Del:R:0"));
}

// ---------------------------------------------------------------------------
// Golden G37: identical adjacent records (SPMG :1376-1386; M1s-13 P0-2).
// ---------------------------------------------------------------------------

/// G37 | the same indel quadruple twice in a row | the second record is a
/// ledger skip (`duplicate_record`), no second event. Scope note: SPMG
/// applies `line == prev_line` to the whole stream; this unit implements
/// it on the indel path (the ID side the memo mandates) and the
/// SNV-stream policy stays with the pending M1s-13 P0-2 adjudication.
#[test]
fn g37_identical_adjacent_indel_dedup() {
    let records = [rec(9, b"AT", b"A"), rec(9, b"AT", b"A")];
    let out = route_variants(&records);
    assert_eq!(out.events.len(), 1);
    assert_eq!(
        out.events[0],
        RoutedEvent::Indel { record: 0, pos: 9, ref_: b"AT", alt: b"A" }
    );
    assert_eq!(
        out.ledger.entries(),
        &[LedgerEntry::Id83, LedgerEntry::Skipped(SkipReason::DuplicateRecord)]
    );
    assert!(out.ledger.render().contains("2\tskipped:duplicate_record"));
}

// ---------------------------------------------------------------------------
// Golden G38: Q predicate direction (MMG:1789-1798; audit-04 erratum
// memo §1.4-1 — the memo/source direction is authoritative).
// ---------------------------------------------------------------------------

/// G38 | del `CG` (mixed Pur/Pyr) -> q = true; del `CT` (all pyrimidine)
/// -> q = false. All-{C,T} or all-{G,A} or bias N -> real bias; mixed
/// -> "Q:".
#[test]
fn g38_q_predicate_direction() {
    assert!(q_predicate(b"CG", Strand::Transcribed));
    assert!(!q_predicate(b"CT", Strand::Transcribed));
    assert!(!q_predicate(b"GA", Strand::Untranscribed));
    // bias "N" is resolvable by definition — even mixed sequences take
    // the real-bias branch (:1789-1798 short-circuits on bias == "N").
    assert!(!q_predicate(b"CG", Strand::None));
    // single-base sequences are trivially homogeneous.
    assert!(!q_predicate(b"C", Strand::None));
    assert!(!q_predicate(b"ACGTACGT", Strand::None));
}

// ---------------------------------------------------------------------------
// Properties: exhaustive channel coverage, anchor invariance, EXACT walk.
// ---------------------------------------------------------------------------

/// Every one of the 83 channels is reachable by a systematic input sweep
/// (catalog-completeness property: the table has no dead rows).
#[test]
fn property_all_83_channels_reachable() {
    let mut hit = vec![false; 83];

    // 1 bp deletions: key4 = run extensions, key3 from the deleted base
    // (both revcompl members of each class).
    for k in 0..6usize {
        let frag = format!("A{}G", "C".repeat(k + 1));
        mark_hit(&mut hit, "delC", assign(&frag, 1, b"AC", b"A")); // 1:Del:C:k
        let frag = format!("T{}A", "G".repeat(k + 1));
        mark_hit(&mut hit, "delG", assign(&frag, 1, b"TG", b"T")); // G -> C class
        let frag = format!("A{}G", "T".repeat(k + 1));
        mark_hit(&mut hit, "delT", assign(&frag, 1, b"AT", b"A")); // 1:Del:T:k
        let frag = format!("C{}G", "A".repeat(k + 1));
        mark_hit(&mut hit, "delA", assign(&frag, 1, b"CA", b"C")); // A -> T class
    }
    // 1 bp insertions: key4 = matched flanks, inserted base picks C/T.
    for k in 0..6usize {
        let frag = format!("A{}G", "C".repeat(k));
        mark_hit(&mut hit, "insC", assign(&frag, 1, b"A", b"AC"));
        let frag = format!("A{}G", "T".repeat(k));
        mark_hit(&mut hit, "insT", assign(&frag, 1, b"A", b"AT"));
        let frag = format!("T{}A", "G".repeat(k));
        mark_hit(&mut hit, "insG", assign(&frag, 1, b"T", b"TG"));
        let frag = format!("C{}G", "A".repeat(k));
        mark_hit(&mut hit, "insA", assign(&frag, 1, b"C", b"CA"));
    }
    // Tandem-repeat deletions: tandem of k+1 unit copies; deleting the
    // first copy leaves k matched copies (key4 = k). Sentinels are picked
    // per unit so the k=0 flanks cannot accidentally satisfy an MH hit
    // (fwd needs unit[0] == right flank; rev needs unit[-1] == anchor).
    for (unit, anchor) in [("AC", 'T'), ("ACG", 'T'), ("ACGT", 'A'), ("ACGTA", 'C')] {
        let mut rf = vec![anchor as u8];
        rf.extend_from_slice(unit.as_bytes());
        for k in 0..6usize {
            let frag = format!("{anchor}{}T", unit.repeat(k + 1));
            mark_hit(&mut hit, &format!("delR{unit}x{k}"), assign(&frag, 1, &rf, &[anchor as u8]));
        }
    }
    // Tandem-repeat insertions: insert the unit before k existing copies
    // (same sentinel discipline; k=0 swaps the 5 bp unit so the inserted
    // sequence does not end on its own anchor).
    for (unit, unit0, anchor) in [
        ("AC", "AC", 'T'),
        ("ACG", "ACG", 'T'),
        ("ACGT", "ACGT", 'A'),
        ("ACGTA", "ACGTT", 'C'),
    ] {
        for k in 0..6usize {
            let u = if k == 0 { unit0 } else { unit };
            let mut alt = vec![anchor as u8];
            alt.extend_from_slice(u.as_bytes());
            let frag = format!("{anchor}{}T", u.repeat(k));
            mark_hit(&mut hit, &format!("insR{unit}x{k}"), assign(&frag, 1, &[anchor as u8], &alt));
        }
    }
    // MH deletions over the whole Del:M block: (key1, key4). fwd_hom is
    // ref[1..-1]; the fragment provides exactly key4 matching bases after
    // the deleted segment (key1=5/key4=5 is the G25 L=6 pattern).
    let mh_cases: [(&str, &[u8], usize); 11] = [
        ("ACGC", b"ACG", 1),       // 2:Del:M:1
        ("AACGA", b"AACG", 1),     // 3:Del:M:1
        ("AACGAC", b"AACG", 2),     // 3:Del:M:2
        ("ACGTACA", b"ACGTA", 1),  // 4:Del:M:1
        ("ACGTACG", b"ACGTA", 2),  // 4:Del:M:2
        ("ACGTACGT", b"ACGTA", 3), // 4:Del:M:3
        ("ACGTAACA", b"ACGTAA", 1), // 5:Del:M:1
        ("ACGTAACGA", b"ACGTAA", 2), // 5:Del:M:2
        ("ACGTAACGTC", b"ACGTAA", 3), // 5:Del:M:3
        ("ACGTAACGTA", b"ACGTAA", 4), // 5:Del:M:4
        ("ACGTACGCGTACT", b"ACGTACG", 5), // 5:Del:M:5 (G25)
    ];
    for (frag, rf, key4) in mh_cases {
        let out = assign(frag, 1, rf, b"A").unwrap();
        match out {
            Indel83Outcome::Channel(i) => {
                let label = ID83_CHANNELS[i];
                let expect = format!("{}:Del:M:{key4}", &label[0..1]);
                assert_eq!(label, expect, "case {frag}");
                hit[i] = true;
            }
            other => panic!("case {frag}: unexpected {other:?}"),
        }
    }

    let missing: Vec<usize> = hit
        .iter()
        .enumerate()
        .filter(|(_, &h)| !h)
        .map(|(i, _)| i)
        .collect();
    assert!(missing.is_empty(), "unreachable channels {missing:?}");
}

/// F1 anchor invariance, systematic form of G4/G8: the same homopolymer
/// deletion expressed with the anchor at every T position of the run
/// lands on one channel (the walk is anchored at POS but counts the
/// whole run). POS = anchor position; anchor must be a T (ref[0]).
#[test]
fn property_anchor_invariance_on_homopolymer_run() {
    // frag = A T^5 G: delete one T, anchor on its T predecessor.
    let mut seen = Vec::new();
    for pos in 2..=5usize {
        let (i, _) = chan_label("ATTTTTG", pos, b"TT", b"T");
        seen.push(i);
    }
    assert!(seen.iter().all(|&i| i == seen[0]), "anchors diverge: {seen:?}");
    assert_eq!(seen[0], 10, "1:Del:T:4");
}

/// EXACT walk + MH interplay: a unit followed by a NEAR-match (last byte
/// off) must not extend R (:1476 EXACT compare) but the walk's failure
/// opens the MH branch, whose forward search then captures the L-1
/// prefix (longest-first) -> key4 = L-1. Pins F2's R-refusal / M-fallback
/// boundary systematically.
#[test]
fn property_near_match_refuses_r_then_mh_captures() {
    // (ref allele, expected key1, expected key4)
    let cases: [(&[u8], &str, usize); 4] = [
        (b"ACG", "2", 1),
        (b"ACGT", "3", 2),
        (b"ACGTA", "4", 3),
        (b"ACGTAA", "5", 4),
    ];
    for (rf, key1, key4) in cases {
        let mut unit = rf[1..].to_vec();
        // near-match: same unit with the last byte swapped to A-free 'G'?
        // swap the last byte to something != its current value.
        let last = unit.len() - 1;
        unit[last] = if unit[last] == b'A' { b'G' } else { b'A' };
        // frag: anchor (= ref[0], SPMG :1408-1421) + unit + near-match +
        // sentinel.
        let mut frag = vec![rf[0]];
        frag.extend_from_slice(&rf[1..]);
        frag.extend_from_slice(&unit);
        frag.push(b'T');
        let frag = String::from_utf8(frag).unwrap();
        let out = assign(&frag, 1, rf, &[rf[0]]).unwrap();
        match out {
            Indel83Outcome::Channel(i) => {
                let expect = format!("{key1}:Del:M:{key4}");
                assert_eq!(ID83_CHANNELS[i], expect, "case {frag}");
            }
            other => panic!("case {frag}: unexpected {other:?}"),
        }
    }
}

// ---------------------------------------------------------------------------
// Error paths: validation and bounds discipline.
// ---------------------------------------------------------------------------

/// Anchor beyond the chromosome end: structured bounds error (SPMG
/// :1391-1406 skips; our carrier is the bounds error).
#[test]
fn error_anchor_out_of_chromosome() {
    let chrom = b"ACGT";
    let err = assign_indel83_slice(chrom, 4, b"TC", b"T").unwrap_err();
    assert_eq!(err.topic, "bounds");
}

/// Non-ACGT allele bytes are argument errors (the router normally catches
/// them first; the semantic layer is defensive per sbs.rs precedent).
#[test]
fn error_invalid_allele_bytes() {
    let chrom = padded("ACGT");
    let err = assign_indel83_slice(&chrom, PAD as u64, b"ACN", b"A").unwrap_err();
    assert_eq!(err.topic, "argument");
    let err = assign_indel83_slice(&chrom, PAD as u64, b"acg", b"a").unwrap_err();
    assert_eq!(err.topic, "argument");
}

/// ref == alt and empty alleles: argument errors (SPMG :1361-1374 skips).
#[test]
fn error_degenerate_alleles() {
    let chrom = padded("ACGT");
    let err = assign_indel83_slice(&chrom, PAD as u64, b"A", b"A").unwrap_err();
    assert_eq!(err.topic, "argument");
    let err = assign_indel83_slice(&chrom, PAD as u64, b"", b"A").unwrap_err();
    assert_eq!(err.topic, "argument");
}

/// Equal-length block substitutions are MNV territory, not ID83 (memo
/// §3.3): the semantic layer rejects them as argument errors.
#[test]
fn error_equal_length_block_is_not_an_indel() {
    let chrom = padded("ACGT");
    let err = assign_indel83_slice(&chrom, PAD as u64, b"AC", b"GT").unwrap_err();
    assert_eq!(err.topic, "argument");
}

// ---------------------------------------------------------------------------
// mnv routing integration: simple indels are Id83 events now.
// ---------------------------------------------------------------------------

/// A 1 bp deletion and a 1 bp insertion route to Indel events carrying the
/// fields assign_indel83 needs; ledger destination Id83 (vocabulary "id83").
#[test]
fn routing_simple_indels_land_on_id83() {
    let records = [rec(60, b"AT", b"A"), rec(70, b"C", b"CT")];
    let out = route_variants(&records);
    assert_eq!(
        out.events,
        vec![
            RoutedEvent::Indel { record: 0, pos: 60, ref_: b"AT", alt: b"A" },
            RoutedEvent::Indel { record: 1, pos: 70, ref_: b"C", alt: b"CT" },
        ]
    );
    assert_eq!(out.ledger.entries(), &[LedgerEntry::Id83, LedgerEntry::Id83]);
    assert_eq!(out.ledger.render(), "1\tid83\n2\tid83\n");
    assert_eq!(out.ledger.entries()[0].destination(), Destination::Id83);
}

/// Adjacent indels are NEVER merged (SPMG pairing only touches SNV
/// streams, memo §4 point 2): a deletion followed by an insertion stays
/// two independent Id83 events.
#[test]
fn routing_adjacent_indels_never_merge() {
    let records = [rec(10, b"AT", b"A"), rec(12, b"G", b"GT")];
    let out = route_variants(&records);
    assert_eq!(out.events.len(), 2);
    assert_eq!(
        out.events,
        vec![
            RoutedEvent::Indel { record: 0, pos: 10, ref_: b"AT", alt: b"A" },
            RoutedEvent::Indel { record: 1, pos: 12, ref_: b"G", alt: b"GT" },
        ]
    );
    assert_eq!(out.ledger.entries(), &[LedgerEntry::Id83, LedgerEntry::Id83]);
}

/// An indel next to a SNV does not reconnect and does not pair: both stay
/// independent.
#[test]
fn routing_indel_and_snv_stay_independent() {
    let records = [rec(0, b"A", b"AT"), rec(2, b"C", b"G")];
    let out = route_variants(&records);
    assert_eq!(
        out.events,
        vec![
            RoutedEvent::Indel { record: 0, pos: 0, ref_: b"A", alt: b"AT" },
            RoutedEvent::Sbs { record: 1, pos: 2, ref_: b'C', alt: b'G' },
        ]
    );
}

/// The dedup compares full quadruples: two DIFFERENT indels at the same
/// position are both routed (only field-identical repeats collapse).
#[test]
fn routing_dedup_requires_full_equality() {
    let records = [rec(9, b"AT", b"A"), rec(9, b"AG", b"A")];
    let out = route_variants(&records);
    assert_eq!(out.events.len(), 2);
    assert_eq!(out.ledger.entries(), &[LedgerEntry::Id83, LedgerEntry::Id83]);
}

/// A duplicate is judged against the raw previous record: three identical
/// records keep the first and ledger both successors (SPMG
/// `line == prev_line` updates every line, :1376-1386).
#[test]
fn routing_dedup_triples() {
    let records = [rec(5, b"AT", b"A"), rec(5, b"AT", b"A"), rec(5, b"AT", b"A")];
    let out = route_variants(&records);
    assert_eq!(out.events.len(), 1);
    assert_eq!(
        out.ledger.entries(),
        &[
            LedgerEntry::Id83,
            LedgerEntry::Skipped(SkipReason::DuplicateRecord),
            LedgerEntry::Skipped(SkipReason::DuplicateRecord),
        ]
    );
}

/// Invalid indels keep their own reason codes ahead of dedup (memo §4
/// point 5 order); an invalid record is never a dedup partner.
#[test]
fn routing_invalid_indel_not_a_dedup_partner() {
    let records = [rec(5, b"AT", b"A"), rec(5, b"NT", b"A")];
    let out = route_variants(&records);
    assert_eq!(
        out.ledger.entries(),
        &[LedgerEntry::Id83, LedgerEntry::Skipped(SkipReason::InvalidBase)]
    );
}

/// Reason codes stay stable machine-readable strings; SimpleIndel is
/// retired but its code remains reserved for downstream vocabularies.
#[test]
fn skip_reason_codes_stable() {
    assert_eq!(SkipReason::InvalidBase.code(), "invalid_base");
    assert_eq!(SkipReason::EmptyAllele.code(), "empty_allele");
    assert_eq!(SkipReason::RefEqualsAlt.code(), "ref_equals_alt");
    assert_eq!(SkipReason::SimpleIndel.code(), "simple_indel");
    assert_eq!(SkipReason::DuplicateRecord.code(), "duplicate_record");
}

// ---------------------------------------------------------------------------
// genome.range(): window access + context() as its read-path wrapper.
// ---------------------------------------------------------------------------

/// range() returns exactly the requested window bytes (fixture chr1 =
/// "TCAG" repeated, N blocks at 0-10, 500-505, 1000-1003).
#[test]
fn range_returns_exact_window() {
    let fix = fixture::build(&fixture::specs(), fixture::Endian::Little);
    let mut g = TwoBitGenome::from_bytes(&fix.bytes).unwrap();
    let win = g.range("chr1", 12, 7).unwrap();
    assert_eq!(&win, b"TCAGTCA");
    assert_eq!(g.range("chr1", 0, 1).unwrap(), b"N");
    assert_eq!(g.range("chr1", 1002, 1).unwrap(), b"N");
    // Full-chromosome window is legal.
    assert_eq!(g.range("chrM", 0, 17).unwrap().len(), 17);
}

/// range() bounds discipline mirrors context(): unknown chromosome is an
/// argument error; start past the chromosome carries i = 1-based start,
/// j = size; a window past the tail carries i = 1-based start, j = the
/// requested 1-based last base. Windows are never clamped.
#[test]
fn range_bounds_discipline() {
    let fix = fixture::build(&fixture::specs(), fixture::Endian::Little);
    let mut g = TwoBitGenome::from_bytes(&fix.bytes).unwrap();

    let err = g.range("chrZ", 0, 1).unwrap_err();
    assert_eq!(err.topic, "argument");

    // chrM size 17: start 17 is past the end.
    let err = g.range("chrM", 17, 1).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(18));
    assert_eq!(err.j, Some(17));

    // Window crossing the tail: i = start, j = requested last base (18).
    let err = g.range("chrM", 16, 2).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(17));
    assert_eq!(err.j, Some(18));

    // Zero-length windows are a caller bug: argument error, never Ok.
    let err = g.range("chrM", 0, 0).unwrap_err();
    assert_eq!(err.topic, "argument");

    // Extreme lengths fail via bounds, never overflow-panic.
    let err = g.range("chrM", 0, usize::MAX).unwrap_err();
    assert_eq!(err.topic, "bounds");

    // Exact-fit window is fine.
    assert!(g.range("chrM", 16, 1).is_ok());
}

/// context() is the read-path wrapper of range(): identical bytes for the
/// same window, across every fixture chromosome and layout.
#[test]
fn context_is_range_thin_wrapper() {
    for endian in [fixture::Endian::Little, fixture::Endian::Big] {
        let fix = fixture::build(&fixture::specs(), endian);
        let mut g = TwoBitGenome::from_bytes(&fix.bytes).unwrap();
        for chrom in &fix.chroms {
            for pos in [12usize, chrom.size / 2, chrom.size - 9] {
                let (f5, f3) = (4usize, 5usize);
                if pos < f5 || pos + f3 >= chrom.size {
                    continue;
                }
                let ctx = g.context(&chrom.name, pos, f5, f3).unwrap();
                let rng = g.range(&chrom.name, pos - f5, f5 + f3 + 1).unwrap();
                assert_eq!(ctx, rng, "{} pos {pos}", chrom.name);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// End-to-end: assign_indel83 over a real 2bit fixture chromosome.
// ---------------------------------------------------------------------------

/// The genome-backed entry point (TwoBitGenome + range closure) classifies
/// identically to the slice entry point on fixture chr1 ("TCAG"^...):
/// deleting the C at 0-based 13 (anchor T at 12) zero-extends left (T) and
/// right (A) -> 1:Del:C:0; inserting that same C one-extends (next base C)
/// -> 1:Ins:C:1.
#[test]
fn genome_backed_assignment_matches_slice_path() {
    let fix = fixture::build(&fixture::specs(), fixture::Endian::Little);
    let mut g = TwoBitGenome::from_bytes(&fix.bytes).unwrap();

    let out = assign_indel83_genome(&mut g, "chr1", 12, b"TC", b"T").unwrap();
    match out {
        Indel83Outcome::Channel(i) => {
            assert_eq!((i, indel83_label(i).unwrap()), (0, "1:Del:C:0"))
        }
        other => panic!("unexpected {other:?}"),
    }
    let out = assign_indel83_genome(&mut g, "chr1", 12, b"T", b"TC").unwrap();
    match out {
        Indel83Outcome::Channel(i) => {
            assert_eq!((i, indel83_label(i).unwrap()), (13, "1:Ins:C:1"))
        }
        other => panic!("unexpected {other:?}"),
    }

    // Cross-check the slice path on the same region.
    let seq = fix.seq_range("chr1", 0, 40);
    let a = assign_indel83_slice(seq.as_bytes(), 12, b"TC", b"T").unwrap();
    let mut g2 = TwoBitGenome::from_bytes(&fix.bytes).unwrap();
    let b = assign_indel83_genome(&mut g2, "chr1", 12, b"TC", b"T").unwrap();
    assert_eq!(a, b);

    // Unknown chromosome propagates as an argument error.
    let err = assign_indel83_genome(&mut g2, "chrZ", 0, b"AC", b"A").unwrap_err();
    assert_eq!(err.topic, "argument");
}
