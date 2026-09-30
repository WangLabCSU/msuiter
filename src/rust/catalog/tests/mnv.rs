//! Golden tests for the variant classification router, split-VCF
//! reconnection and skip ledger (U-M1s-07; A11 catalog-completeness
//! contract, `docs/ARCHITECTURE.md` §7 entry 2).
//!
//! Routing rules pinned here (each golden hand-derived):
//!   * single-base SNV -> `Sbs`;
//!   * two adjacent single-base records at distance exactly 1 (SPMG
//!     `dinuc_sub == 1`) -> `Dbs` candidate pair (REF-vs-genome validation
//!     stays upstream; the event carries the concatenated dinucleotides);
//!   * 2..=5 bp equal-length block substitution -> `Mnv`; >5 bp -> `LongMnv`;
//!   * unequal-length alleles with both sides >1 base -> `ComplexIndel`
//!     (SPMG complex-indel class);
//!   * one-side-single-base indels -> `Indel` events on the `Id83`
//!     destination (U-M1c-01; classify with
//!     `indel83::assign_indel83`), never merged with neighbours;
//!   * an INDEL-stream record identical to its raw stream predecessor ->
//!     `Skipped(duplicate_record)` (SPMG :1376-1386; the stream is every
//!     non-SNV record, converter :94, so simple indels, complex indels
//!     and block substitutions all dedup; SNV-stream dedup awaits
//!     M1s-13 P0-2);
//!   * a non-ACGT byte or a zero-length allele -> `Skipped(invalid_base /
//!     empty_allele)`; identical alleles -> `Skipped(ref_equals_alt)`;
//!   * split-VCF reconnection (pairwise only): two consecutive valid
//!     records reconnect iff they are contiguous (`pos2 == pos1 +
//!     len(ref1)`) AND the concatenation is equal-length (a block
//!     substitution). Adjacent double SNVs are DBS candidates first; an
//!     unequal-length concatenation (which would manufacture an indel
//!     event) is never reconnected; gapped or overlapping records are
//!     classified independently. Pairing is greedy left-to-right and
//!     non-overlapping (SPMG convention); chains of >2 pieces are not
//!     extended.
//!   * routing is total: every failure mode is a ledger entry, never an
//!     abort.

use msuiter_catalog::dbs::assign_dbs78;
use msuiter_catalog::mnv::{
    route_variants, LedgerEntry, RoutedEvent, SkipReason, VarRecord,
};

/// Shorthand record constructor.
fn rec<'a>(pos: u64, ref_: &'a [u8], alt: &'a [u8]) -> VarRecord<'a> {
    VarRecord::new(pos, ref_, alt)
}

/// Class code of every routed event, for whole-sequence assertions.
fn event_codes(events: &[RoutedEvent<'_>]) -> Vec<&'static str> {
    events
        .iter()
        .map(|e| match e {
            RoutedEvent::Sbs { .. } => "sbs",
            RoutedEvent::Dbs { .. } => "dbs",
            RoutedEvent::Mnv { .. } => "mnv",
            RoutedEvent::LongMnv { .. } => "long_mnv",
            RoutedEvent::ComplexIndel { .. } => "complex_indel",
            RoutedEvent::Indel { .. } => "indel",
        })
        .collect()
}

/// Per-record destination vector, for whole-ledger assertions.
fn ledger_codes(ledger: &[LedgerEntry]) -> Vec<String> {
    ledger
        .iter()
        .map(|e| match e {
            LedgerEntry::Sbs => "sbs".to_string(),
            LedgerEntry::Dbs => "dbs".to_string(),
            LedgerEntry::Mnv => "mnv".to_string(),
            LedgerEntry::LongMnv => "long_mnv".to_string(),
            LedgerEntry::ComplexIndel => "complex_indel".to_string(),
            LedgerEntry::Id83 => "id83".to_string(),
            LedgerEntry::Skipped(r) => format!("skipped:{}", r.code()),
        })
        .collect()
}

fn ledger_of(records: &[VarRecord<'_>]) -> Vec<LedgerEntry> {
    route_variants(records).ledger.entries().to_vec()
}

// ---------------------------------------------------------------------------
// Golden sequences: events + ledger, hand-derived.
// ---------------------------------------------------------------------------

/// Plain, non-adjacent SNVs: two independent SBS events.
#[test]
fn golden_plain_snvs() {
    let records = [rec(10, b"A", b"T"), rec(20, b"C", b"G")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["sbs", "sbs"]);
    assert_eq!(
        out.events,
        vec![
            RoutedEvent::Sbs { record: 0, pos: 10, ref_: b'A', alt: b'T' },
            RoutedEvent::Sbs { record: 1, pos: 20, ref_: b'C', alt: b'G' },
        ]
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["sbs", "sbs"]);
}

/// Adjacent SNV pair: DBS candidate with concatenated dinucleotides; the
/// candidate feeds `assign_dbs78` onto "CT>AG".
#[test]
fn golden_adjacent_snv_pair_dbs() {
    let records = [rec(100, b"C", b"A"), rec(101, b"T", b"G")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["dbs"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Dbs { records: [0, 1], pos: 100, ref2: *b"CT", alt2: *b"AG" }
    );
    assert_eq!(assign_dbs78(b"CT", b"AG").unwrap(), 32);
    assert_eq!(ledger_codes(out.ledger.entries()), ["dbs", "dbs"]);
}

/// Three consecutive SNVs: greedy left-to-right pairing -> one DBS pair +
/// one lone SNV (SPMG convention; the middle record is consumed once).
#[test]
fn golden_three_consecutive_snvs() {
    let records = [rec(5, b"A", b"T"), rec(6, b"C", b"G"), rec(7, b"T", b"A")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["dbs", "sbs"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Dbs { records: [0, 1], pos: 5, ref2: *b"AC", alt2: *b"TG" }
    );
    // AC>TG is DBS78 channel 7 (hand-derived).
    assert_eq!(assign_dbs78(b"AC", b"TG").unwrap(), 7);
    assert_eq!(ledger_codes(out.ledger.entries()), ["dbs", "dbs", "sbs"]);
}

/// Four consecutive SNVs: two non-overlapping greedy pairs.
#[test]
fn golden_greedy_pairing_four_snvs() {
    let records = [
        rec(0, b"A", b"C"),
        rec(1, b"A", b"C"),
        rec(2, b"G", b"T"),
        rec(3, b"G", b"T"),
    ];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["dbs", "dbs"]);
    assert_eq!(out.events[0], RoutedEvent::Dbs { records: [0, 1], pos: 0, ref2: *b"AA", alt2: *b"CC" });
    assert_eq!(out.events[1], RoutedEvent::Dbs { records: [2, 3], pos: 2, ref2: *b"GG", alt2: *b"TT" });
}

/// SNVs at distance 2 are NOT a DBS pair.
#[test]
fn golden_distance_two_snvs_stay_sbs() {
    let records = [rec(10, b"A", b"T"), rec(12, b"C", b"G")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["sbs", "sbs"]);
    assert_eq!(ledger_codes(out.ledger.entries()), ["sbs", "sbs"]);
}

/// Single-record block substitutions: 2 bp and 5 bp -> Mnv.
#[test]
fn golden_mnv_block_lengths() {
    let records = [rec(30, b"CT", b"AG")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 1, pos: 30, len: 2 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["mnv"]);

    let records = [rec(40, b"ACGTA", b"TGCAT")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 1, pos: 40, len: 5 }
    );
}

/// 6 bp equal-length block -> LongMnv.
#[test]
fn golden_long_mnv() {
    let records = [rec(50, b"ACGTAC", b"TGCATG")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["long_mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::LongMnv { record: 0, merged: 1, pos: 50, len: 6 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["long_mnv"]);
}

/// Both alleles >1 base with unequal lengths -> ComplexIndel.
#[test]
fn golden_complex_indel() {
    let records = [rec(60, b"ACGT", b"AG")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["complex_indel"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::ComplexIndel { record: 0, pos: 60, ref_len: 4, alt_len: 2 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["complex_indel"]);
}

/// Split-VCF reconnection: two contiguous 2 bp pieces concatenate into one
/// 4 bp block substitution.
#[test]
fn golden_reconnect_into_mnv() {
    let records = [rec(70, b"AC", b"TG"), rec(72, b"GT", b"CA")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 2, pos: 70, len: 4 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["mnv", "mnv"]);
}

/// Reconnection into a >5 bp block: two contiguous 3 bp pieces -> LongMnv.
#[test]
fn golden_reconnect_into_long_mnv() {
    let records = [rec(80, b"AAA", b"TTT"), rec(83, b"CCC", b"GGG")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["long_mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::LongMnv { record: 0, merged: 2, pos: 80, len: 6 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["long_mnv", "long_mnv"]);
}

/// Not reconnectable (gap): adjacent records classified independently.
#[test]
fn golden_non_reconnectable_gap() {
    let records = [rec(90, b"AC", b"TG"), rec(94, b"GT", b"CA")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv", "mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 1, pos: 90, len: 2 }
    );
    assert_eq!(
        out.events[1],
        RoutedEvent::Mnv { record: 1, merged: 1, pos: 94, len: 2 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["mnv", "mnv"]);
}

/// Not reconnectable (contiguous but unequal-length concatenation would
/// manufacture an indel): explicit independent classification; the simple
/// deletion is an Indel event on the Id83 destination.
#[test]
fn golden_non_reconnectable_unequal_concat() {
    let records = [rec(100, b"ACG", b"TGC"), rec(103, b"TA", b"G")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv", "indel"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 1, pos: 100, len: 3 }
    );
    assert_eq!(
        out.events[1],
        RoutedEvent::Indel { record: 1, pos: 103, ref_: b"TA", alt: b"G" }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["mnv", "id83"]);
}

/// A SNV next to a 1 bp insertion: no reconnection (unequal concatenation);
/// the insertion routes to the Id83 destination.
#[test]
fn golden_snv_plus_insertion_not_reconnected() {
    let records = [rec(110, b"A", b"C"), rec(111, b"A", b"AG")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["sbs", "indel"]);
    assert_eq!(
        out.events[1],
        RoutedEvent::Indel { record: 1, pos: 111, ref_: b"A", alt: b"AG" }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["sbs", "id83"]);
}

/// Overlapping records are never reconnected: independent classification.
#[test]
fn golden_overlapping_records_independent() {
    let records = [rec(140, b"ACG", b"TGC"), rec(142, b"GTA", b"CAT")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv", "mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 1, pos: 140, len: 3 }
    );
    assert_eq!(
        out.events[1],
        RoutedEvent::Mnv { record: 1, merged: 1, pos: 142, len: 3 }
    );
}

/// Invalid alleles are explicit ledger entries, never panics: an N in the
/// reference side and lowercase (non-ACGT) bytes both skip with a reason.
#[test]
fn golden_invalid_records() {
    let records = [rec(120, b"ACN", b"TGC"), rec(121, b"ct", b"ag")];
    assert_eq!(
        ledger_codes(&ledger_of(&records)),
        ["skipped:invalid_base", "skipped:invalid_base"]
    );
    let out = route_variants(&records);
    assert!(out.events.is_empty());
}

/// Zero-length alleles are malformed records with their own reason code.
#[test]
fn golden_empty_allele() {
    let records = [rec(0, b"", b"A")];
    assert_eq!(
        ledger_codes(&ledger_of(&records)),
        ["skipped:empty_allele"]
    );
}

/// ref == alt carries no substitution: explicit skip.
#[test]
fn golden_ref_equals_alt() {
    let records = [rec(130, b"AC", b"AC")];
    assert_eq!(
        ledger_codes(&ledger_of(&records)),
        ["skipped:ref_equals_alt"]
    );
}

/// Identical adjacent 2..=5 bp block pair: block substitutions are
/// INDEL-stream rows upstream (converter :94), so SPMG's
/// `line == prev_line` dedup (:1376-1386) drops the repeat (audit
/// U-M1c-01 P2-1); the LongMnv/complex twins live in the indel83 suite
/// (G37c/G37b).
#[test]
fn golden_duplicate_mnv_block_dedup() {
    let records = [rec(30, b"CT", b"AG"), rec(30, b"CT", b"AG")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 1, pos: 30, len: 2 }
    );
    assert_eq!(
        ledger_codes(out.ledger.entries()),
        ["mnv", "skipped:duplicate_record"]
    );
}

/// Reconnection is pairwise: a chain of three contiguous 2 bp pieces is
/// NOT extended into one 6 bp block (documented convention; the first pair
/// reconnects, the third piece stands alone).
#[test]
fn golden_reconnection_is_pairwise_only() {
    let records = [rec(0, b"AC", b"TG"), rec(2, b"GT", b"CA"), rec(4, b"AA", b"TT")];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["mnv", "mnv"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Mnv { record: 0, merged: 2, pos: 0, len: 4 }
    );
    assert_eq!(
        out.events[1],
        RoutedEvent::Mnv { record: 2, merged: 1, pos: 4, len: 2 }
    );
    assert_eq!(ledger_codes(out.ledger.entries()), ["mnv", "mnv", "mnv"]);
}

/// Full mixed pipeline: ten sorted records covering every destination and
/// every skip reason, including a contiguous-but-unequal lookahead that
/// must NOT merge the complex indel with the following SNV.
#[test]
fn golden_mixed_pipeline() {
    let records = [
        rec(0, b"C", b"T"),         // 0-1: adjacent pair -> DBS (CT>TG)
        rec(1, b"T", b"G"),         //
        rec(2, b"A", b"C"),         // lone SNV
        rec(10, b"GGT", b"CCA"),    // 3 bp block -> MNV
        rec(20, b"ACGTAC", b"TGCATG"), // 6 bp block -> LongMNV
        rec(30, b"AAG", b"AG"),     // complex indel; contiguous with next
        rec(31, b"C", b"T"),        // SNV but unequal concat -> no merge
        rec(40, b"N", b"A"),        // invalid base
        rec(50, b"TT", b"TT"),      // no change
        rec(60, b"AT", b"A"),       // simple deletion -> Id83 event
    ];
    let out = route_variants(&records);
    assert_eq!(
        event_codes(&out.events),
        ["dbs", "sbs", "mnv", "long_mnv", "complex_indel", "sbs", "indel"]
    );
    assert_eq!(
        out.events[0],
        RoutedEvent::Dbs { records: [0, 1], pos: 0, ref2: *b"CT", alt2: *b"TG" }
    );
    // CT>TG is DBS78 channel 38 (hand-derived).
    assert_eq!(assign_dbs78(b"CT", b"TG").unwrap(), 38);
    assert_eq!(
        out.events[1],
        RoutedEvent::Sbs { record: 2, pos: 2, ref_: b'A', alt: b'C' }
    );
    assert_eq!(
        out.events[2],
        RoutedEvent::Mnv { record: 3, merged: 1, pos: 10, len: 3 }
    );
    assert_eq!(
        out.events[3],
        RoutedEvent::LongMnv { record: 4, merged: 1, pos: 20, len: 6 }
    );
    assert_eq!(
        out.events[4],
        RoutedEvent::ComplexIndel { record: 5, pos: 30, ref_len: 3, alt_len: 2 }
    );
    assert_eq!(
        out.events[5],
        RoutedEvent::Sbs { record: 6, pos: 31, ref_: b'C', alt: b'T' }
    );
    assert_eq!(
        out.events[6],
        RoutedEvent::Indel { record: 9, pos: 60, ref_: b"AT", alt: b"A" }
    );
    assert_eq!(
        ledger_codes(out.ledger.entries()),
        [
            "dbs",
            "dbs",
            "sbs",
            "mnv",
            "long_mnv",
            "complex_indel",
            "sbs",
            "skipped:invalid_base",
            "skipped:ref_equals_alt",
            "id83",
        ]
    );
}

/// Empty input: no events, empty ledger, empty rendering.
#[test]
fn golden_empty_input() {
    let records: [VarRecord<'static>; 0] = [];
    let out = route_variants(&records);
    assert!(out.events.is_empty());
    assert!(out.ledger.entries().is_empty());
    assert_eq!(out.ledger.render(), "");
}

// ---------------------------------------------------------------------------
// Skip ledger rendering (provenance carrier).
// ---------------------------------------------------------------------------

/// The text rendering is a deterministic 1-based TSV vector: one line per
/// input record, `index TAB destination`, skipped entries qualified by
/// their reason code.
#[test]
fn ledger_render_golden() {
    let records = [
        rec(0, b"C", b"T"),
        rec(1, b"T", b"G"),
        rec(2, b"A", b"C"),
        rec(10, b"GGT", b"CCA"),
        rec(20, b"ACGTAC", b"TGCATG"),
        rec(30, b"AAG", b"AG"),
        rec(31, b"C", b"T"),
        rec(40, b"N", b"A"),
        rec(50, b"TT", b"TT"),
        rec(60, b"AT", b"A"),
    ];
    let out = route_variants(&records);
    assert_eq!(
        out.ledger.render(),
        "1\tdbs\n\
         2\tdbs\n\
         3\tsbs\n\
         4\tmnv\n\
         5\tlong_mnv\n\
         6\tcomplex_indel\n\
         7\tsbs\n\
         8\tskipped:invalid_base\n\
         9\tskipped:ref_equals_alt\n\
         10\tid83\n"
    );
}

/// Reason codes are stable machine-readable strings. `SimpleIndel` is
/// retired (never emitted since U-M1c-01) but its code stays reserved.
#[test]
fn skip_reason_codes() {
    assert_eq!(SkipReason::InvalidBase.code(), "invalid_base");
    assert_eq!(SkipReason::EmptyAllele.code(), "empty_allele");
    assert_eq!(SkipReason::RefEqualsAlt.code(), "ref_equals_alt");
    assert_eq!(SkipReason::SimpleIndel.code(), "simple_indel");
    assert_eq!(SkipReason::DuplicateRecord.code(), "duplicate_record");
}

/// A skipped record does not disturb greedy pairing of its neighbours:
/// valid records on both sides still pair across the ledgered skip.
#[test]
fn skip_does_not_break_pairing() {
    let records = [
        rec(0, b"A", b"T"),
        rec(1, b"N", b"G"), // invalid: not a pair candidate
        rec(2, b"C", b"A"),
        rec(3, b"T", b"G"),
    ];
    let out = route_variants(&records);
    assert_eq!(event_codes(&out.events), ["sbs", "dbs"]);
    assert_eq!(
        out.events[0],
        RoutedEvent::Sbs { record: 0, pos: 0, ref_: b'A', alt: b'T' }
    );
    assert_eq!(
        out.events[1],
        RoutedEvent::Dbs { records: [2, 3], pos: 2, ref2: *b"CT", alt2: *b"AG" }
    );
    assert_eq!(
        ledger_codes(out.ledger.entries()),
        ["sbs", "skipped:invalid_base", "dbs", "dbs"]
    );
}
