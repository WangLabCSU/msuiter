//! Variant classification router, split-VCF reconnection and skip ledger
//! (U-M1s-07; A11 catalog-completeness contract, `docs/ARCHITECTURE.md`
//! §7 entry 2).
//!
//! Input is a slice of coordinate-sorted variant records (same chromosome;
//! sortedness is the caller's contract). Routing is TOTAL: every record
//! ends in exactly one destination, and every failure mode is an explicit
//! ledger entry — the router never aborts and never drops a record
//! silently. The ledger is the provenance carrier (`SkipLedger`, with a
//! deterministic text rendering); R-side provenance wiring is the
//! assembly unit's job.
//!
//! # Routing table (SPMG semantics, `docs/research/04` section 1)
//!
//! | input event                                          | destination        |
//! |------------------------------------------------------|--------------------|
//! | one single-base record (len(ref) == len(alt) == 1)    | `Sbs`              |
//! | two adjacent single-base records, `pos2 == pos1 + 1`  | `Dbs` candidate    |
//! | 2..=5 bp equal-length block substitution              | `Mnv`              |
//! | >5 bp equal-length block substitution                 | `LongMnv`          |
//! | both alleles >1 base, unequal lengths                 | `ComplexIndel`     |
//! | one-side-single-base indel                            | `Indel` event -> `Id83` (U-M1c-01; classify with `crate::indel83::assign_indel83` after the assembly layer's anchor-vs-genome check) |
//! | two adjacent one-side-single-base indels              | `Indel` events each — indels are NEVER merged (SPMG pairing only touches SNV streams, memo §4) |
//! | identical adjacent indel quadruple (SPMG `line == prev_line`, :1376-1386) | second record `Skipped(duplicate_record)` (SNV-stream dedup awaits the M1s-13 P0-2 adjudication) |
//! | non-ACGT byte / zero-length allele                    | `Skipped(invalid_base / empty_allele)` |
//! | `ref == alt` (no change)                              | `Skipped(ref_equals_alt)` |
//!
//! SPMG detects DBS events as SNVs at distance exactly 1 (`dinuc_sub ==
//! 1`) and separates further-clustered mutations from the substitution
//! matrices. The DBS destination is a CANDIDATE: REF-vs-reference-genome
//! validation is the assembly layer's job; the event carries the
//! concatenated dinucleotides for `crate::dbs::assign_dbs78`. The Indel
//! event carries `pos/ref/alt` for `crate::indel83::assign_indel83`; its
//! per-event outcomes (channel / Ins:M-no-channel / anchor mismatch /
//! bounds skip) are the tally wiring unit's ledgering job.
//!
//! # Split-VCF reconnection (pairwise, "adjacent + concatenation")
//!
//! Two consecutive VALID records reconnect into one block event iff
//!   1. they are contiguous: `pos2 == pos1 + len(ref1)` (no gap, no
//!      overlap), and
//!   2. the concatenation is equal-length: `len(ref1) + len(ref2) ==
//!      len(alt1) + len(alt2)` — a block substitution.
//!
//! Two adjacent single-base records satisfy both and are DBS candidates
//! (SPMG priority over the 2 bp MNV reading). An unequal-length
//! concatenation (e.g. a SNV next to a 1 bp insertion) is NEVER merged —
//! that would manufacture an indel event SPMG does not create; the records
//! are classified independently. The same holds for ANY simple-indel
//! participant, including the equal-length del+ins case (an insertion
//! adjacent to a deletion): SPMG's pairing only touches SNV record streams
//! (memo §4), so indels always stand alone. Gapped or overlapping records
//! likewise stand alone. Reconnection is pairwise: chains of >2 pieces are
//! not extended (documented msuiter extension of SPMG's seqinfo MNV
//! handling, kept minimal per ARCHITECTURE §7 entry 2). Pairing is greedy
//! left-to-right and non-overlapping (SPMG convention): the first record
//! of a run pairs with its immediate successor, which is then consumed.
//! An invalid record is never a reconnection partner; its neighbours are
//! classified as if it were absent.

use crate::dbs::adjacent_snv_pair;

/// One coordinate-sorted variant record (already split out of VCF/CSV).
///
/// Alleles are uppercase ACGT byte strings of length >= 1; anything else
/// is routed to an explicit ledger skip by [`route_variants`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VarRecord<'a> {
    /// 0-based reference position of `ref_` (1-based VCF POS minus one).
    pub pos: u64,
    /// Reference allele.
    pub ref_: &'a [u8],
    /// Alternate allele.
    pub alt: &'a [u8],
}

impl<'a> VarRecord<'a> {
    /// Build a record from position and allele byte strings.
    #[inline]
    pub fn new(pos: u64, ref_: &'a [u8], alt: &'a [u8]) -> Self {
        Self { pos, ref_, alt }
    }
}

/// Destination of a routed record (ledger view; skip reasons qualify the
/// `Skipped` bucket).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedgerEntry {
    /// Single-base substitution (SBS layer).
    Sbs,
    /// Half of an adjacent double-SNV DBS candidate pair.
    Dbs,
    /// Part of a 2..=5 bp block substitution (possibly reconnected).
    Mnv,
    /// Part of a >5 bp block substitution (possibly reconnected).
    LongMnv,
    /// Complex indel: both alleles >1 base, unequal lengths (SPMG complex
    /// class; no ID83 channel — counted in provenance only).
    ComplexIndel,
    /// Simple indel routed to the ID83 layer (U-M1c-01): classify with
    /// `crate::indel83::assign_indel83`.
    Id83,
    /// Explicit skip with a machine-readable reason.
    Skipped(SkipReason),
}

impl LedgerEntry {
    /// The coarse destination bucket of this entry.
    #[inline]
    pub fn destination(self) -> Destination {
        match self {
            LedgerEntry::Sbs => Destination::Sbs,
            LedgerEntry::Dbs => Destination::Dbs,
            LedgerEntry::Mnv => Destination::Mnv,
            LedgerEntry::LongMnv => Destination::LongMnv,
            LedgerEntry::ComplexIndel => Destination::ComplexIndel,
            LedgerEntry::Id83 => Destination::Id83,
            LedgerEntry::Skipped(_) => Destination::Skipped,
        }
    }
}

/// Coarse destination buckets of the routing table (ledger join key for
/// downstream provenance).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Destination {
    /// Single-base substitution.
    Sbs,
    /// Adjacent double-SNV DBS candidate.
    Dbs,
    /// 2..=5 bp block substitution.
    Mnv,
    /// >5 bp block substitution.
    LongMnv,
    /// Complex indel (both alleles >1 base, unequal lengths).
    ComplexIndel,
    /// Simple indel bound for the ID83 channel layer.
    Id83,
    /// Explicit skip (see the qualifying reason in the ledger entry).
    Skipped,
}

impl Destination {
    /// Stable snake_case bucket code (ledger rendering vocabulary).
    #[inline]
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Destination::Sbs => "sbs",
            Destination::Dbs => "dbs",
            Destination::Mnv => "mnv",
            Destination::LongMnv => "long_mnv",
            Destination::ComplexIndel => "complex_indel",
            Destination::Id83 => "id83",
            Destination::Skipped => "skipped",
        }
    }
}

/// Machine-readable reason codes for skipped records (stable strings; the
/// skip ledger is a provenance artifact).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkipReason {
    /// A non-ACGT byte in `ref_` or `alt` (SPMG: no channel key exists;
    /// such mutations are skipped per-mutation).
    InvalidBase,
    /// A zero-length allele (malformed record).
    EmptyAllele,
    /// `ref == alt`: no substitution.
    RefEqualsAlt,
    /// RETIRED at U-M1c-01: simple indels route to
    /// [`LedgerEntry::Id83`] instead. The variant stays (never emitted by
    /// this router) so downstream vocabularies that predate the ID83
    /// layer keep compiling until the tally wiring unit retires them.
    SimpleIndel,
    /// An identical adjacent record (same pos/ref/alt; SPMG
    /// `line == prev_line`, :1376-1386) — the repeat occurrence is
    /// dropped. Implemented here for the indel path; the SNV-stream
    /// policy is the pending M1s-13 P0-2 adjudication.
    DuplicateRecord,
}

impl SkipReason {
    /// Stable snake_case code used by [`SkipLedger::render`].
    #[inline]
    pub fn code(self) -> &'static str {
        match self {
            SkipReason::InvalidBase => "invalid_base",
            SkipReason::EmptyAllele => "empty_allele",
            SkipReason::RefEqualsAlt => "ref_equals_alt",
            SkipReason::SimpleIndel => "simple_indel",
            SkipReason::DuplicateRecord => "duplicate_record",
        }
    }
}

/// A routed event (destination view). `record` is the 0-based index of the
/// first input record; a block event spanning two reconnected records sets
/// `merged == 2` (the second record index is then `record + 1`); DBS
/// events name both records explicitly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoutedEvent<'a> {
    /// Single-base substitution at `records[record]`.
    Sbs {
        record: usize,
        pos: u64,
        ref_: u8,
        alt: u8,
    },
    /// Adjacent double-SNV DBS candidate over `records[a], records[a + 1]`:
    /// concatenated dinucleotides for `crate::dbs::assign_dbs78`, after the
    /// upstream REF-vs-genome check.
    Dbs {
        records: [usize; 2],
        pos: u64,
        ref2: [u8; 2],
        alt2: [u8; 2],
    },
    /// 2..=5 bp equal-length block substitution; alleles concatenate in
    /// record order (`records[record].ref_ ++ records[record + 1].ref_`
    /// when `merged == 2`).
    Mnv {
        record: usize,
        merged: usize,
        pos: u64,
        len: usize,
    },
    /// >5 bp equal-length block substitution (same layout as [`RoutedEvent::Mnv`]).
    LongMnv {
        record: usize,
        merged: usize,
        pos: u64,
        len: usize,
    },
    /// Complex indel: both alleles >1 base, unequal lengths (SPMG complex
    /// class; provenance-only destination, no ID83 channel).
    ComplexIndel {
        record: usize,
        pos: u64,
        ref_len: usize,
        alt_len: usize,
    },
    /// Simple (one-side-single-base) indel: the fields
    /// `crate::indel83::assign_indel83` consumes, after the assembly
    /// layer's anchor-vs-genome check.
    Indel {
        record: usize,
        pos: u64,
        ref_: &'a [u8],
        alt: &'a [u8],
    },
}

/// Routing result: the events and the per-record skip ledger (one entry
/// per input record, same order).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Routing<'a> {
    /// Routed events in input order.
    pub events: Vec<RoutedEvent<'a>>,
    /// Per-record ledger (provenance carrier).
    pub ledger: SkipLedger,
}

/// Per-record destination vector for a batch of sorted variant records.
///
/// The ledger is the provenance carrier required by the
/// catalog-completeness contract (ARCHITECTURE §7 entry 2): every input
/// record has exactly one entry, so skips are auditable end to end.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkipLedger {
    entries: Vec<LedgerEntry>,
}

impl SkipLedger {
    /// The per-record entries, in input order.
    #[inline]
    pub fn entries(&self) -> &[LedgerEntry] {
        &self.entries
    }

    /// Deterministic text rendering, one line per record:
    /// `1-based-index TAB destination`, with skipped entries qualified by
    /// their reason code (`skipped:<code>`). Trailing newline per line.
    pub fn render(&self) -> String {
        let mut out = String::with_capacity(self.entries.len() * 12);
        for (k, entry) in self.entries.iter().enumerate() {
            let code = match entry {
                LedgerEntry::Sbs => "sbs",
                LedgerEntry::Dbs => "dbs",
                LedgerEntry::Mnv => "mnv",
                LedgerEntry::LongMnv => "long_mnv",
                LedgerEntry::ComplexIndel => "complex_indel",
                LedgerEntry::Id83 => "id83",
                LedgerEntry::Skipped(reason) => {
                    out.push_str(&format!("{}\tskipped:{}\n", k + 1, reason.code()));
                    continue;
                }
            };
            out.push_str(&format!("{}\t{}\n", k + 1, code));
        }
        out
    }
}

/// Per-record validation: `Some(reason)` iff the record must be skipped.
fn validate(rec: &VarRecord<'_>) -> Option<SkipReason> {
    if rec.ref_.is_empty() || rec.alt.is_empty() {
        return Some(SkipReason::EmptyAllele);
    }
    for &b in rec.ref_.iter().chain(rec.alt.iter()) {
        if !matches!(b, b'A' | b'C' | b'G' | b'T') {
            return Some(SkipReason::InvalidBase);
        }
    }
    if rec.ref_ == rec.alt {
        return Some(SkipReason::RefEqualsAlt);
    }
    None
}

/// Classify one standalone (not reconnected, not paired) record.
fn classify_single<'a>(rec: &VarRecord<'a>, record: usize) -> (Option<RoutedEvent<'a>>, LedgerEntry) {
    let (r, a) = (rec.ref_.len(), rec.alt.len());
    if r == 1 && a == 1 {
        (
            Some(RoutedEvent::Sbs {
                record,
                pos: rec.pos,
                ref_: rec.ref_[0],
                alt: rec.alt[0],
            }),
            LedgerEntry::Sbs,
        )
    } else if r == a {
        // Equal length >1: block substitution, sized by the MNV rule.
        if r <= 5 {
            (
                Some(RoutedEvent::Mnv { record, merged: 1, pos: rec.pos, len: r }),
                LedgerEntry::Mnv,
            )
        } else {
            (
                Some(RoutedEvent::LongMnv { record, merged: 1, pos: rec.pos, len: r }),
                LedgerEntry::LongMnv,
            )
        }
    } else if r > 1 && a > 1 {
        (
            Some(RoutedEvent::ComplexIndel { record, pos: rec.pos, ref_len: r, alt_len: a }),
            LedgerEntry::ComplexIndel,
        )
    } else {
        // One side is a single anchor base: simple indel -> ID83 layer
        // (U-M1c-01). Indels are never merged or paired; each lands as
        // its own Indel event.
        (
            Some(RoutedEvent::Indel { record, pos: rec.pos, ref_: rec.ref_, alt: rec.alt }),
            LedgerEntry::Id83,
        )
    }
}

/// SPMG's identical-adjacent-record dedup (:1376-1386): full
/// quadruple equality (same chromosome is implicit — routing is
/// per-chromosome). Applied on the indel path; the SNV-stream policy is
/// the pending M1s-13 P0-2 adjudication.
fn duplicate_of_previous(prev: Option<&VarRecord<'_>>, rec: &VarRecord<'_>) -> bool {
    match prev {
        Some(p) => p.pos == rec.pos && p.ref_ == rec.ref_ && p.alt == rec.alt,
        None => false,
    }
}

/// Is this record a simple (one-side-single-base) indel?
fn is_simple_indel(rec: &VarRecord<'_>) -> bool {
    let (r, a) = (rec.ref_.len(), rec.alt.len());
    (r == 1) != (a == 1)
}

/// Route a coordinate-sorted batch of variant records.
///
/// Greedy left-to-right single pass (SPMG convention); see the module
/// docs for the routing table, the reconnection criteria and the explicit
/// failure modes. Never fails: per-record failures are ledger entries.
pub fn route_variants<'a>(records: &[VarRecord<'a>]) -> Routing<'a> {
    let mut events = Vec::new();
    let mut entries = Vec::with_capacity(records.len());
    let mut i = 0;
    while i < records.len() {
        let rec = &records[i];
        if let Some(reason) = validate(rec) {
            entries.push(LedgerEntry::Skipped(reason));
            i += 1;
            continue;
        }
        // Indel-path dedup (SPMG :1376-1386): a simple indel identical to
        // the raw previous record is dropped with an explicit reason. The
        // comparison uses the previous RECORD whether or not it was
        // routed/skipped (SPMG compares raw consecutive lines).
        if is_simple_indel(rec)
            && i > 0
            && duplicate_of_previous(Some(&records[i - 1]), rec)
        {
            entries.push(LedgerEntry::Skipped(SkipReason::DuplicateRecord));
            i += 1;
            continue;
        }
        // Lookahead: the immediate successor is a reconnection/pairing
        // candidate only if it is itself valid.
        let next = records.get(i + 1).filter(|n| validate(n).is_none());
        let mut consumed_two = false;
        if let Some(next) = next {
            let both_single_base = rec.ref_.len() == 1
                && rec.alt.len() == 1
                && next.ref_.len() == 1
                && next.alt.len() == 1;
            // Adjacent double SNV (SPMG dinuc_sub == 1): DBS candidate.
            if let Some((ref2, alt2)) = adjacent_snv_pair(
                rec.pos,
                rec.ref_[0],
                rec.alt[0],
                next.pos,
                next.ref_[0],
                next.alt[0],
            )
            .filter(|_| both_single_base)
            {
                events.push(RoutedEvent::Dbs {
                    records: [i, i + 1],
                    pos: rec.pos,
                    ref2,
                    alt2,
                });
                entries.push(LedgerEntry::Dbs);
                entries.push(LedgerEntry::Dbs);
                consumed_two = true;
            } else if !is_simple_indel(rec)
                && !is_simple_indel(next)
                && next.pos == rec.pos + rec.ref_.len() as u64
                && rec.ref_.len() + next.ref_.len() == rec.alt.len() + next.alt.len()
            {
                // Split-VCF reconnection: contiguous + equal-length
                // concatenation -> one block substitution. Indels are
                // NEVER merged (SPMG pairs SNV records only, memo §4):
                // an equal-length del+ins concatenation would manufacture
                // a block substitution SPMG does not create, so any
                // simple-indel participant stands alone.
                let len = rec.ref_.len() + next.ref_.len();
                let event = if len <= 5 {
                    RoutedEvent::Mnv { record: i, merged: 2, pos: rec.pos, len }
                } else {
                    RoutedEvent::LongMnv { record: i, merged: 2, pos: rec.pos, len }
                };
                events.push(event);
                let entry = if len <= 5 { LedgerEntry::Mnv } else { LedgerEntry::LongMnv };
                entries.push(entry);
                entries.push(entry);
                consumed_two = true;
            }
        }
        if consumed_two {
            i += 2;
            continue;
        }
        let (event, entry) = classify_single(rec, i);
        if let Some(event) = event {
            events.push(event);
        }
        entries.push(entry);
        i += 1;
    }
    Routing { events, ledger: SkipLedger { entries } }
}
