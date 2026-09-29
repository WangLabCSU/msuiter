//! Catalog assembly core: variant routing + reference-context fetch +
//! SBS96/192/384/1536 & DBS78 counting (U-M1s-09).
//!
//! This module is the pure (R-type-free) heart of `ms_tally_rust`: it
//! borrows an already-parsed [`TwoBitGenome`] and a batch of
//! [`TallyVariant`]s, and produces the count matrices plus the provenance
//! ledger. File I/O and mmap ownership stay in the FFI shell
//! (`lib.rs`, the only `unsafe` site, FFI contract 1 / D12: the mapping is
//! built per call and dropped with it).
//!
//! # Pipeline (per call)
//!
//! 1. **Sort** records stably by `(chrom_idx, pos0)` — routing adjacency
//!    (`mnv::route_variants`) is defined per chromosome over
//!    coordinate-sorted records, so the caller's input order is free.
//! 2. **Partition** into per-chromosome runs and route each with
//!    `msuiter_catalog::mnv::route_variants` (split-VCF reconnection, DBS
//!    candidacy, skip ledger — ARCHITECTURE §7 entry 2).
//! 3. **Fetch contexts** from the genome for SBS events (+/-2 pentanucleotide
//!    window) and DBS candidates (2x2 dinucleotide) and validate:
//!    * a non-ACGT byte anywhere in the +/-2 window (SPMG parity, `sbs.rs`
//!      module docs: an N at +/-2 is invisible to a trinucleotide yet drops
//!      the mutation from every SPMG SBS matrix) => skip `n_context`;
//!    * an N in the DBS dinucleotide (SPMG's only per-mutation N guard)
//!      => skip `n_dinuc`;
//!    * REF-vs-genome mismatch (SPMG checks the reference allele,
//!      `MutationMatrixGenerator.py:778-808`; sbs.rs/mnv.rs assign the
//!      check to this assembly layer) => skip `ref_mismatch`;
//!    * a context window crossing the chromosome edge (windows are never
//!      clamped, `genome.rs`) => skip `context_bounds`.
//!      The fetch + checks run for every SBS/DBS record REGARDLESS of the
//!      table switches, so the ledger is a pure function of
//!      (genome, variants) — provenance does not depend on which matrices
//!      the caller asked for.
//! 4. **Count** enabled matrices. Rows are channels in canonical
//!    `channels.rs` order; columns are samples in FIRST-APPEARANCE order of
//!    `sample_idx` in the CALLER's input order (not the sorted order). The
//!    flat layout is column-major with `nrow = table length` (contract 2):
//!    `index = sample_column * table_len + channel_row`.
//!    * DBS pairs are excluded from every SBS matrix (SPMG separates
//!      `dinuc_sub == 1` doublets from the substitution matrices).
//!    * MNV / long-MNV / complex-indel events are ledgered but counted
//!      nowhere (their ID83 / complex destination lands in U-M1c).
//!    * SBS192 has no B/N strand block (`sbs.rs`): B/N-strand records are
//!      dropped from SBS192 ONLY (they still count in SBS384's B/N blocks
//!      and in SBS96/1536). This per-matrix drop is NOT a ledger skip — the
//!      ledger is per-record and the record's SBS destination stands.
//!
//! # Ledger
//!
//! One outcome per INPUT record, rendered in the caller's input order with
//! the exact [`SkipLedger`-style] line format of `mnv.rs`
//! (`1-based-index TAB destination-or-skipped:reason`, one trailing newline
//! per line). Assembly-layer reasons extend the router's vocabulary:
//! `unknown_chrom`, `ref_mismatch`, `n_context`, `n_dinuc`, `context_bounds`.
//!
//! # Chromosome policy (M1s, deliberately simple)
//!
//! Chromosome matching is EXACT string equality against the 2bit index
//! names — no `chr`-prefix normalization (documented deviation shim until a
//! later unit standardizes aliasing). An unmatched name is a per-record
//! `skipped:unknown_chrom` ledger entry, never an error.
//!
//! # Concurrency (M1s scope)
//!
//! Single-threaded on purpose: per-variant independence WOULD allow
//! parallelization, but the decision is deferred until the tally wiring
//! (U-M1s-11) profiles real variant densities (same reasoning as the
//! deferred batched-context API in `genome.rs`). Contract 7 is honored in
//! the single-thread shape: the caller-injected `check_user_interrupt`
//! hook runs once per chromosome run and at fixed event chunks on the
//! calling (main) thread; there are no workers and no cancellation flag.

use std::collections::HashMap;

use msuiter_catalog::dbs::assign_dbs78;
use msuiter_catalog::genome::TwoBitGenome;
use msuiter_catalog::mnv::{route_variants, LedgerEntry, RoutedEvent, SkipReason, VarRecord};
use msuiter_catalog::sbs::{
    assign_sbs1536_slice, assign_sbs192_slice, assign_sbs384_slice, assign_sbs96_slice, Strand,
};
use msuiter_engine::error::MsError;

/// Sentinel chromosome index for records whose chromosome name does not
/// occur in the reference genome; such records are ledgered
/// `skipped:unknown_chrom` (never an error, never routed).
pub const UNKNOWN_CHROM: usize = usize::MAX;

/// Interrupt-poll granularity within one chromosome run (contract 7: the
/// main-thread hook runs at run boundaries and every this-many events).
const POLL_EVERY_EVENTS: usize = 4096;

/// One input variant record (owned alleles; the FFI shell builds these
/// from the R columns).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TallyVariant {
    /// Reference-genome chromosome index (position in the 2bit index), or
    /// [`UNKNOWN_CHROM`] when the name did not match.
    pub chrom_idx: usize,
    /// 0-based reference position (1-based VCF/MAF POS minus one).
    pub pos0: u64,
    /// Reference allele (uppercase ACGT; anything else is ledgered by the
    /// router).
    pub ref_: Vec<u8>,
    /// Alternate allele (uppercase ACGT).
    pub alt: Vec<u8>,
    /// Sample group id; distinct ids become matrix columns in
    /// first-appearance order of the CALLER's input.
    pub sample_idx: usize,
    /// Transcription-strand annotation for SBS192/SBS384 (N = unannotated).
    pub strand: Strand,
}

/// Which count matrices to produce (disabled tables come back empty).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct TallyTables {
    pub sbs96: bool,
    pub sbs192: bool,
    pub sbs384: bool,
    pub sbs1536: bool,
    pub dbs78: bool,
}

/// Per-record tally outcome: the router destinations plus the
/// assembly-layer skips. Codes are stable provenance strings rendered in
/// the exact `mnv.rs` ledger line format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TallyOutcome {
    /// Single-base substitution (counted in the enabled SBS matrices).
    Sbs,
    /// Half of an adjacent double-SNV DBS pair (excluded from SBS matrices).
    Dbs,
    /// 2..=5 bp block substitution (possibly reconnected; counted nowhere).
    Mnv,
    /// >5 bp block substitution (counted nowhere; ID/complex lands U-M1c).
    LongMnv,
    /// Complex indel: both alleles >1 base, unequal lengths (U-M1c).
    ComplexIndel,
    /// Chromosome name not found in the genome (exact-match policy).
    SkippedUnknownChrom,
    /// REF allele disagrees with the reference-genome bases.
    SkippedRefMismatch,
    /// Non-ACGT byte in the SBS +/-2 context window (SPMG parity).
    SkippedNContext,
    /// Non-ACGT byte in the DBS dinucleotide.
    SkippedNDinuc,
    /// Context window crosses a chromosome edge (windows are never clamped).
    SkippedContextBounds,
    /// Router skips, verbatim from `mnv::route_variants`.
    SkippedInvalidBase,
    SkippedEmptyAllele,
    SkippedRefEqualsAlt,
    SkippedSimpleIndel,
}

impl TallyOutcome {
    /// Stable snake_case provenance code (ledger rendering).
    pub fn code(self) -> &'static str {
        match self {
            TallyOutcome::Sbs => "sbs",
            TallyOutcome::Dbs => "dbs",
            TallyOutcome::Mnv => "mnv",
            TallyOutcome::LongMnv => "long_mnv",
            TallyOutcome::ComplexIndel => "complex_indel",
            TallyOutcome::SkippedUnknownChrom => "skipped:unknown_chrom",
            TallyOutcome::SkippedRefMismatch => "skipped:ref_mismatch",
            TallyOutcome::SkippedNContext => "skipped:n_context",
            TallyOutcome::SkippedNDinuc => "skipped:n_dinuc",
            TallyOutcome::SkippedContextBounds => "skipped:context_bounds",
            TallyOutcome::SkippedInvalidBase => "skipped:invalid_base",
            TallyOutcome::SkippedEmptyAllele => "skipped:empty_allele",
            TallyOutcome::SkippedRefEqualsAlt => "skipped:ref_equals_alt",
            TallyOutcome::SkippedSimpleIndel => "skipped:simple_indel",
        }
    }

    /// True iff the record landed nowhere countable.
    pub fn is_skip(self) -> bool {
        matches!(
            self,
            TallyOutcome::SkippedUnknownChrom
                | TallyOutcome::SkippedRefMismatch
                | TallyOutcome::SkippedNContext
                | TallyOutcome::SkippedNDinuc
                | TallyOutcome::SkippedContextBounds
                | TallyOutcome::SkippedInvalidBase
                | TallyOutcome::SkippedEmptyAllele
                | TallyOutcome::SkippedRefEqualsAlt
                | TallyOutcome::SkippedSimpleIndel
        )
    }

    /// Map the router's per-record ledger entry onto the tally vocabulary.
    fn of_entry(entry: LedgerEntry) -> Self {
        match entry {
            LedgerEntry::Sbs => TallyOutcome::Sbs,
            LedgerEntry::Dbs => TallyOutcome::Dbs,
            LedgerEntry::Mnv => TallyOutcome::Mnv,
            LedgerEntry::LongMnv => TallyOutcome::LongMnv,
            LedgerEntry::ComplexIndel => TallyOutcome::ComplexIndel,
            LedgerEntry::Skipped(reason) => match reason {
                SkipReason::InvalidBase => TallyOutcome::SkippedInvalidBase,
                SkipReason::EmptyAllele => TallyOutcome::SkippedEmptyAllele,
                SkipReason::RefEqualsAlt => TallyOutcome::SkippedRefEqualsAlt,
                SkipReason::SimpleIndel => TallyOutcome::SkippedSimpleIndel,
            },
        }
    }
}

/// Tally result: one flat count buffer per enabled table (column-major,
/// `index = sample_column * table_len + channel_row`; disabled tables are
/// empty), the rendered ledger and the skip total.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TallyResult {
    pub sbs96: Vec<u32>,
    pub sbs192: Vec<u32>,
    pub sbs384: Vec<u32>,
    pub sbs1536: Vec<u32>,
    pub dbs78: Vec<u32>,
    /// One line per input record, input order, `mnv.rs` rendering.
    pub ledger_tsv: String,
    /// Number of records whose outcome is a skip.
    pub n_skipped: u32,
}

/// Flat column-major count buffers (contract 2: explicit layout).
struct Counters {
    sbs96: Vec<u32>,
    sbs192: Vec<u32>,
    sbs384: Vec<u32>,
    sbs1536: Vec<u32>,
    dbs78: Vec<u32>,
}

impl Counters {
    fn new(tables: TallyTables, n_samples: usize) -> Self {
        let len = |wanted: bool, channels: usize| {
            if wanted {
                vec![0u32; channels * n_samples]
            } else {
                Vec::new()
            }
        };
        Self {
            sbs96: len(tables.sbs96, 96),
            sbs192: len(tables.sbs192, 192),
            sbs384: len(tables.sbs384, 384),
            sbs1536: len(tables.sbs1536, 1536),
            dbs78: len(tables.dbs78, 78),
        }
    }

    /// Bump channel `row` of sample column `col` in `buf`.
    ///
    /// Index arithmetic is bounds-checked implicitly by the panic on a
    /// bug; every row/col reaching this point is table-derived and
    /// therefore in range (row < table_len by construction, col <
    /// n_samples by the sample map).
    fn bump(buf: &mut [u32], row: usize, col: usize, nrow: usize) {
        let slot = col * nrow + row;
        buf[slot] = buf[slot].saturating_add(1);
    }
}

/// `true` iff every byte is uppercase ACGT.
fn all_acgt(bytes: &[u8]) -> bool {
    bytes
        .iter()
        .all(|&b| matches!(b, b'A' | b'C' | b'G' | b'T'))
}

/// `u64 -> usize` with a structured bounds error (contract 4: explicit
/// narrowing, never an `as` cast that could truncate).
fn position_usize(pos0: u64, chrom: &str) -> Result<usize, MsError> {
    usize::try_from(pos0).map_err(|_| {
        MsError::new(
            "bounds",
            format!(
                "position {} does not fit the addressable range of chromosome \"{chrom}\"",
                pos0
            ),
        )
        .with_i(i64::try_from(pos0).unwrap_or(i64::MAX))
    })
}

/// Tally a batch of variants against an in-memory 2bit genome.
///
/// See the module docs for the pipeline, the ledger semantics and the
/// single-thread scope. `check_user_interrupt` is called on the calling
/// thread at chromosome-run boundaries and every [`POLL_EVERY_EVENTS`]
/// events (under R: `R_CheckUserInterrupt`, contract 7).
pub fn tally(
    genome: &mut TwoBitGenome<'_>,
    variants: &[TallyVariant],
    tables: TallyTables,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<TallyResult, MsError> {
    let chrom_names = genome.chrom_names();

    // Contract 4: every chromosome index is validated up front — either a
    // real index or the UNKNOWN_CHROM sentinel, nothing else.
    for (k, v) in variants.iter().enumerate() {
        if v.chrom_idx != UNKNOWN_CHROM && v.chrom_idx >= chrom_names.len() {
            return Err(MsError::new(
                "bounds",
                format!(
                    "chrom index {} outside the genome's {} chromosomes (record {})",
                    v.chrom_idx,
                    chrom_names.len(),
                    k + 1
                ),
            )
            .with_i(k as i64 + 1)
            .with_j(chrom_names.len() as i64));
        }
    }

    // Sample columns: first appearance in the CALLER's input order.
    let mut sample_col: HashMap<usize, usize> = HashMap::new();
    for v in variants {
        let next = sample_col.len();
        sample_col.entry(v.sample_idx).or_insert(next);
    }
    let n_samples = sample_col.len();
    let mut counters = Counters::new(tables, n_samples);

    // Stable sort by (chrom, position); ties keep caller order.
    let mut order: Vec<usize> = (0..variants.len()).collect();
    order.sort_by_key(|&k| (variants[k].chrom_idx, variants[k].pos0));

    // One outcome per input record, reported in caller order.
    let mut outcomes: Vec<Option<TallyOutcome>> = vec![None; variants.len()];
    let mut polls: usize = 0;
    let mut poll = |polls: &mut usize| {
        *polls += 1;
        check_user_interrupt();
    };

    // Partition the sorted order into per-chromosome runs.
    let mut start = 0usize;
    while start < order.len() {
        poll(&mut polls);
        let mut events_since_poll = 0usize;
        let chrom_idx = variants[order[start]].chrom_idx;
        let mut end = start + 1;
        while end < order.len() && variants[order[end]].chrom_idx == chrom_idx {
            end += 1;
        }
        let run = &order[start..end];
        if chrom_idx == UNKNOWN_CHROM {
            for &k in run {
                outcomes[k] = Some(TallyOutcome::SkippedUnknownChrom);
            }
        } else {
            let chrom = chrom_names[chrom_idx].as_str();
            let recs: Vec<VarRecord<'_>> = run
                .iter()
                .map(|&k| VarRecord::new(variants[k].pos0, &variants[k].ref_, &variants[k].alt))
                .collect();
            let routing = route_variants(&recs);
            // Baseline outcomes: the router's per-record ledger, verbatim.
            for (run_k, entry) in routing.ledger.entries().iter().enumerate() {
                outcomes[run[run_k]] = Some(TallyOutcome::of_entry(*entry));
            }
            for event in &routing.events {
                events_since_poll += 1;
                if events_since_poll % POLL_EVERY_EVENTS == 0 {
                    poll(&mut polls);
                }
                tally_event(
                    genome,
                    chrom,
                    variants,
                    run,
                    event,
                    tables,
                    &sample_col,
                    &mut counters,
                    &mut outcomes,
                )?;
            }
        }
        start = end;
    }

    let resolved: Vec<TallyOutcome> = outcomes
        .into_iter()
        .map(|o| o.expect("every record receives exactly one outcome"))
        .collect();
    let n_skipped = resolved.iter().filter(|o| o.is_skip()).count() as u32;
    let mut ledger_tsv = String::with_capacity(resolved.len() * 16);
    for (k, o) in resolved.iter().enumerate() {
        // Exact mnv::SkipLedger rendering: `1-based-index TAB code\n`.
        ledger_tsv.push_str(&(k + 1).to_string());
        ledger_tsv.push('\t');
        ledger_tsv.push_str(o.code());
        ledger_tsv.push('\n');
    }

    Ok(TallyResult {
        sbs96: counters.sbs96,
        sbs192: counters.sbs192,
        sbs384: counters.sbs384,
        sbs1536: counters.sbs1536,
        dbs78: counters.dbs78,
        ledger_tsv,
        n_skipped,
    })
}

/// Process one routed event: context fetch + validation + counting.
/// Assembly-layer failures overwrite the baseline (router) outcomes of the
/// event's records with the qualifying skip. The parameter list mirrors the
/// call site's locals one-to-one (no context struct at this size).
#[allow(clippy::too_many_lines)] // one flat match per event kind reads best
#[allow(clippy::too_many_arguments)]
fn tally_event(
    genome: &mut TwoBitGenome<'_>,
    chrom: &str,
    variants: &[TallyVariant],
    run: &[usize],
    event: &RoutedEvent,
    tables: TallyTables,
    sample_col: &HashMap<usize, usize>,
    counters: &mut Counters,
    outcomes: &mut [Option<TallyOutcome>],
) -> Result<(), MsError> {
    match *event {
        RoutedEvent::Sbs {
            record,
            pos,
            ref_: ref_byte,
            alt,
        } => {
            let orig = run[record];
            let pos0 = position_usize(pos, chrom)?;
            // +/-2 window: SPMG parity for the whole 96-family (module
            // docs): an N at +/-2 drops the mutation from every SBS matrix.
            let ctx5 = match genome.context(chrom, pos0, 2, 2) {
                Ok(bytes) => bytes,
                Err(e) if e.topic == "bounds" => {
                    outcomes[orig] = Some(TallyOutcome::SkippedContextBounds);
                    return Ok(());
                }
                Err(e) => return Err(e), // io/format: corrupt file fails the call
            };
            if !all_acgt(&ctx5) {
                outcomes[orig] = Some(TallyOutcome::SkippedNContext);
                return Ok(());
            }
            if ctx5[2] != ref_byte {
                outcomes[orig] = Some(TallyOutcome::SkippedRefMismatch);
                return Ok(());
            }
            let v = &variants[orig];
            let col = sample_col[&v.sample_idx];
            let ctx3 = &ctx5[1..4];
            if tables.sbs96 {
                let row = assign_sbs96_slice(ctx3, alt)?;
                Counters::bump(&mut counters.sbs96, row, col, 96);
            }
            if tables.sbs192 && !matches!(v.strand, Strand::Bidirectional | Strand::None) {
                // B/N strands have no SBS192 channel: dropped from THIS
                // matrix only (module docs) — not a ledger skip.
                let row = assign_sbs192_slice(ctx3, alt, v.strand)?;
                Counters::bump(&mut counters.sbs192, row, col, 192);
            }
            if tables.sbs384 {
                let row = assign_sbs384_slice(ctx3, alt, v.strand)?;
                Counters::bump(&mut counters.sbs384, row, col, 384);
            }
            if tables.sbs1536 {
                let row = assign_sbs1536_slice(&ctx5, alt)?;
                Counters::bump(&mut counters.sbs1536, row, col, 1536);
            }
            Ok(())
        }
        RoutedEvent::Dbs {
            records,
            pos,
            ref2,
            alt2,
        } => {
            let pos0 = position_usize(pos, chrom)?;
            // The DBS candidate's 2x2 dinucleotide from the reference.
            let dinuc = match genome.context(chrom, pos0, 0, 1) {
                Ok(bytes) => bytes,
                Err(e) if e.topic == "bounds" => {
                    for &run_k in &records {
                        outcomes[run[run_k]] = Some(TallyOutcome::SkippedContextBounds);
                    }
                    return Ok(());
                }
                Err(e) => return Err(e),
            };
            if !all_acgt(&dinuc) {
                for &run_k in &records {
                    outcomes[run[run_k]] = Some(TallyOutcome::SkippedNDinuc);
                }
                return Ok(());
            }
            if dinuc[0] != ref2[0] || dinuc[1] != ref2[1] {
                for &run_k in &records {
                    outcomes[run[run_k]] = Some(TallyOutcome::SkippedRefMismatch);
                }
                return Ok(());
            }
            if tables.dbs78 {
                let row = assign_dbs78(&ref2, &alt2)?;
                let orig = run[records[0]];
                let col = sample_col[&variants[orig].sample_idx];
                Counters::bump(&mut counters.dbs78, row, col, 78);
            }
            Ok(())
        }
        // Mnv / LongMnv / ComplexIndel are ledger-only until the ID83 and
        // complex layers land (U-M1c); the baseline outcome stands.
        RoutedEvent::Mnv { .. } | RoutedEvent::LongMnv { .. } | RoutedEvent::ComplexIndel { .. } => {
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -----------------------------------------------------------------
    // Fixture generator, ported from catalog/tests/genome/fixture.rs
    // (U-M1s-08). Little-endian layout only: the byte-swap / big-endian
    // matrix is owned by the genome tests, which this module reads through
    // (tally goes via the same genome.rs layer for either layout).
    // -----------------------------------------------------------------
    mod fixture {
        /// UCSC 2bit magic.
        pub const MAGIC: u32 = 0x1A41_2743;

        /// Logical content of one chromosome (hard N blocks only; soft
        /// masks are never applied by `genome.rs`).
        pub struct ChromSpec {
            pub name: &'static str,
            pub size: usize,
            pub pattern: fn(usize) -> u8,
            pub n_blocks: Vec<(usize, usize)>,
        }

        fn put_u32(buf: &mut Vec<u8>, v: u32) {
            buf.extend_from_slice(&v.to_le_bytes());
        }

        /// 2-bit base codes (UCSC packing): T=0, C=1, A=2, G=3.
        fn encode_base(b: u8) -> u32 {
            match b {
                b'T' => 0,
                b'C' => 1,
                b'A' => 2,
                b'G' => 3,
                _ => panic!("fixture bases must be A/C/G/T"),
            }
        }

        /// Packed DNA: first base in the high bits; N-block bytes are
        /// zeros (don't-care, readers apply the N blocks).
        fn packed_dna(spec: &ChromSpec, out: &mut Vec<u8>) {
            let in_n = |i: usize| spec.n_blocks.iter().any(|&(s, l)| i >= s && i < s + l);
            let mut acc: u32 = 0;
            let mut filled = 0usize;
            for i in 0..spec.size {
                let base = if in_n(i) { b'T' } else { (spec.pattern)(i) };
                acc = (acc << 2) | encode_base(base);
                filled += 1;
                if filled == 4 {
                    out.push(acc as u8);
                    acc = 0;
                    filled = 0;
                }
            }
            if filled != 0 {
                acc <<= 2 * (4 - filled);
                out.push(acc as u8);
            }
        }

        /// Build a complete little-endian 2bit file.
        pub fn build(specs: &[ChromSpec]) -> Vec<u8> {
            let mut offsets = Vec::with_capacity(specs.len());
            let mut off = 16usize;
            for s in specs {
                off += 1 + s.name.len() + 4;
            }
            for s in specs {
                offsets.push(off as u32);
                off += 4 + 4 + 8 * s.n_blocks.len() + 4 + 4 + (s.size + 3) / 4;
            }
            let mut b = Vec::with_capacity(off);
            put_u32(&mut b, MAGIC);
            put_u32(&mut b, 0); // version
            put_u32(&mut b, specs.len() as u32);
            put_u32(&mut b, 0); // reserved
            for (s, &o) in specs.iter().zip(&offsets) {
                b.push(s.name.len() as u8);
                b.extend_from_slice(s.name.as_bytes());
                put_u32(&mut b, o);
            }
            for s in specs {
                put_u32(&mut b, s.size as u32);
                put_u32(&mut b, s.n_blocks.len() as u32);
                for &(st, _l) in &s.n_blocks {
                    put_u32(&mut b, st as u32);
                }
                for &(_st, l) in &s.n_blocks {
                    put_u32(&mut b, l as u32);
                }
                put_u32(&mut b, 0); // no soft blocks
                put_u32(&mut b, 0); // reserved
                packed_dna(s, &mut b);
            }
            debug_assert_eq!(b.len(), off, "fixture layout arithmetic drifted");
            b
        }
    }

    // chr1: ACAC... with an N block at 0-based positions 50..52.
    fn seq_ac(i: usize) -> u8 {
        if i % 2 == 0 { b'A' } else { b'C' }
    }

    // chr2: GCGC...
    fn seq_gc(i: usize) -> u8 {
        if i % 2 == 0 { b'G' } else { b'C' }
    }

    fn fixture_bytes() -> Vec<u8> {
        fixture::build(&[
            fixture::ChromSpec {
                name: "chr1",
                size: 64,
                pattern: seq_ac,
                n_blocks: vec![(50, 3)],
            },
            fixture::ChromSpec {
                name: "chr2",
                size: 40,
                pattern: seq_gc,
                n_blocks: vec![],
            },
        ])
    }

    /// Record shorthand.
    fn v(chrom: usize, pos0: u64, ref_: &str, alt: &str, sample: usize, strand: Strand) -> TallyVariant {
        TallyVariant {
            chrom_idx: chrom,
            pos0,
            ref_: ref_.as_bytes().to_vec(),
            alt: alt.as_bytes().to_vec(),
            sample_idx: sample,
            strand,
        }
    }

    /// Column-major cell read: `index = col * nrow + row` (contract 2).
    fn cell(buf: &[u32], row: usize, col: usize, nrow: usize) -> u32 {
        buf[col * nrow + row]
    }

    fn all_tables() -> TallyTables {
        TallyTables {
            sbs96: true,
            sbs192: true,
            sbs384: true,
            sbs1536: true,
            dbs78: true,
        }
    }

    /// The hand-derived golden batch (22 records; every outcome and count
    /// derived by hand from the SPMG rules pinned in catalog tests):
    /// plain SNVs across two samples, an adjacent double SNV on each
    /// chromosome (reversed input order), strand-N and strand-B records,
    /// a split 3 bp block substitution reconnected from two pieces, a 6 bp
    /// long MNV, +/-2-window N skips, an N dinucleotide DBS candidate,
    /// a REF-vs-genome mismatch, a head and a tail context-bounds skip, a
    /// simple indel, a complex indel and an unknown chromosome.
    fn golden_variants() -> Vec<TallyVariant> {
        vec![
            v(1, 33, "C", "A", 1, Strand::Transcribed),     // chr2 DBS half A
            v(1, 34, "G", "T", 1, Strand::Transcribed),     // chr2 DBS half B
            v(0, 11, "C", "A", 0, Strand::Transcribed),     // A[C>A]A
            v(0, 16, "A", "G", 1, Strand::Untranscribed),   // G[T>C]G (flip U->T)
            v(0, 22, "A", "G", 0, Strand::Transcribed),     // chr1 DBS half B
            v(0, 21, "C", "T", 0, Strand::Transcribed),     // chr1 DBS half A (input after B)
            v(0, 24, "A", "T", 1, Strand::None),            // N strand: no SBS192
            v(0, 27, "C", "G", 1, Strand::Bidirectional),   // B strand: no SBS192
            v(0, 32, "AC", "G", 1, Strand::None),           // reconnection piece 2
            v(0, 31, "C", "TA", 1, Strand::None),           // piece 1 -> 3bp MNV
            v(0, 43, "T", "G", 0, Strand::None),            // genome has A: ref mismatch
            v(0, 36, "ACACAC", "TTTTTT", 0, Strand::None),  // 6bp: long MNV
            v(0, 49, "C", "A", 0, Strand::None),            // +/-2 window hits N at 50
            v(0, 53, "C", "A", 0, Strand::None),            // +/-2 window inside N block
            v(0, 56, "CA", "C", 0, Strand::None),           // simple indel
            v(0, 60, "AC", "TTT", 0, Strand::None),         // complex indel
            v(0, 63, "C", "A", 0, Strand::None),            // 3' flank past chr1 end
            v(0, 1, "C", "A", 0, Strand::None),             // 5' flank before chr1 start
            v(UNKNOWN_CHROM, 10, "A", "T", 0, Strand::None),// chrZ: unknown chrom
            v(1, 25, "C", "A", 1, Strand::Transcribed),     // G[C>A]G on chr2
            v(0, 51, "C", "A", 0, Strand::None),            // DBS candidate, dinuc = NN
            v(0, 52, "C", "T", 0, Strand::None),            //   -> n_dinuc for both
        ]
    }

    /// Byte-exact golden ledger over the batch above (input order).
    fn golden_ledger() -> String {
        [
            "1\tdbs",
            "2\tdbs",
            "3\tsbs",
            "4\tsbs",
            "5\tdbs",
            "6\tdbs",
            "7\tsbs",
            "8\tsbs",
            "9\tmnv",
            "10\tmnv",
            "11\tskipped:ref_mismatch",
            "12\tlong_mnv",
            "13\tskipped:n_context",
            "14\tskipped:n_context",
            "15\tskipped:simple_indel",
            "16\tcomplex_indel",
            "17\tskipped:context_bounds",
            "18\tskipped:context_bounds",
            "19\tskipped:unknown_chrom",
            "20\tsbs",
            "21\tskipped:n_dinuc",
            "22\tskipped:n_dinuc",
        ]
        .join("\n")
            + "\n"
    }

    #[test]
    fn golden_multi_table_tally() {
        let bytes = fixture_bytes();
        let mut genome = TwoBitGenome::from_bytes(&bytes).unwrap();
        let variants = golden_variants();
        let mut polls = 0usize;
        let res =
            tally(&mut genome, &variants, all_tables(), &mut || polls += 1).unwrap();

        // Sample columns: sample_idx 1 first appears at input record 1,
        // sample_idx 0 at record 3 — col0 = sample 1, col1 = sample 0.
        // Count cells (channel row, sample col), all hand-derived:
        assert_eq!(cell(&res.sbs96, 0, 1, 96), 1);   // A[C>A]A
        assert_eq!(cell(&res.sbs96, 66, 0, 96), 1);  // G[T>C]G
        assert_eq!(cell(&res.sbs96, 62, 0, 96), 1);  // G[T>A]G (strand N)
        assert_eq!(cell(&res.sbs96, 4, 0, 96), 1);   // A[C>G]A (strand B)
        assert_eq!(cell(&res.sbs96, 50, 0, 96), 1);  // G[C>A]G (chr2)
        assert_eq!(res.sbs96.iter().sum::<u32>(), 5);
        // DBS partners (11, 16-context neighbours 15/17) never enter SBS.

        assert_eq!(cell(&res.sbs192, 0, 1, 192), 1);      // T:A[C>A]A
        assert_eq!(cell(&res.sbs192, 66, 0, 192), 1);     // T:G[T>C]G (U flipped)
        assert_eq!(cell(&res.sbs192, 50, 0, 192), 1);     // T:G[C>A]G
        assert_eq!(res.sbs192.iter().sum::<u32>(), 3);    // N/B strands: no 192

        assert_eq!(cell(&res.sbs384, 0, 1, 384), 1);      // T:A[C>A]A
        assert_eq!(cell(&res.sbs384, 66, 0, 384), 1);     // T:G[T>C]G
        assert_eq!(cell(&res.sbs384, 350, 0, 384), 1);    // N:G[T>A]G
        assert_eq!(cell(&res.sbs384, 196, 0, 384), 1);    // B:A[C>G]A
        assert_eq!(cell(&res.sbs384, 50, 0, 384), 1);     // T:G[C>A]G
        assert_eq!(res.sbs384.iter().sum::<u32>(), 5);

        assert_eq!(cell(&res.sbs1536, 385, 1, 1536), 1);  // CA[C>A]AC
        assert_eq!(cell(&res.sbs1536, 1419, 0, 1536), 1); // TG[T>C]GT
        assert_eq!(cell(&res.sbs1536, 1403, 0, 1536), 1); // TG[T>A]GT
        assert_eq!(cell(&res.sbs1536, 401, 0, 1536), 1);  // CA[C>G]AC
        assert_eq!(cell(&res.sbs1536, 585, 0, 1536), 1);  // CG[C>A]GC
        assert_eq!(res.sbs1536.iter().sum::<u32>(), 5);

        assert_eq!(cell(&res.dbs78, 63, 1, 78), 1);       // TG>CA (chr1 pair CA>TG)
        assert_eq!(cell(&res.dbs78, 24, 0, 78), 1);       // CG>AT (chr2 pair)
        assert_eq!(res.dbs78.iter().sum::<u32>(), 2);

        // Ledger: byte-exact, input order, mnv.rs rendering.
        assert_eq!(res.ledger_tsv, golden_ledger());
        assert_eq!(res.n_skipped, 9);

        // Contract 7 on the single-thread path: one poll per chromosome
        // run (chr1, chr2, chrZ); 17 events < POLL_EVERY_EVENTS.
        assert_eq!(polls, 3);

        // Cross-pin the derived rows against the canonical tables.
        use msuiter_catalog::dbs::dbs78_label;
        use msuiter_catalog::sbs::{sbs1536_label, sbs384_label, sbs96_label};
        assert_eq!(sbs96_label(66).unwrap(), "G[T>C]G");
        assert_eq!(sbs384_label(350).unwrap(), "N:G[T>A]G");
        assert_eq!(sbs384_label(196).unwrap(), "B:A[C>G]A");
        assert_eq!(sbs1536_label(385).unwrap(), "CA[C>A]AC");
        assert_eq!(dbs78_label(24).unwrap(), "CG>AT");
        assert_eq!(dbs78_label(63).unwrap(), "TG>CA");
    }

    /// The ledger is a pure function of (genome, variants): with every
    /// table disabled the buffers are empty but the ledger and the skip
    /// count are byte-identical (context fetches and checks still run).
    #[test]
    fn disabled_tables_yield_empty_buffers_and_identical_ledger() {
        let bytes = fixture_bytes();
        let mut genome = TwoBitGenome::from_bytes(&bytes).unwrap();
        let variants = golden_variants();
        let res = tally(&mut genome, &variants, TallyTables::default(), &mut || {}).unwrap();
        assert!(res.sbs96.is_empty() && res.sbs192.is_empty() && res.sbs384.is_empty());
        assert!(res.sbs1536.is_empty() && res.dbs78.is_empty());
        assert_eq!(res.ledger_tsv, golden_ledger());
        assert_eq!(res.n_skipped, 9);
    }

    #[test]
    fn empty_input_is_all_empty() {
        let bytes = fixture_bytes();
        let mut genome = TwoBitGenome::from_bytes(&bytes).unwrap();
        let mut polls = 0usize;
        let res = tally(&mut genome, &[], all_tables(), &mut || polls += 1).unwrap();
        assert!(res.sbs96.is_empty() && res.dbs78.is_empty());
        assert_eq!(res.ledger_tsv, "");
        assert_eq!(res.n_skipped, 0);
        assert_eq!(polls, 0); // no runs: no boundary polls
    }

    /// Contract 4: a chromosome index that is neither a real index nor the
    /// UNKNOWN_CHROM sentinel is a structured bounds error, never a panic.
    #[test]
    fn out_of_range_chrom_index_is_a_bounds_error() {
        let bytes = fixture_bytes();
        let mut genome = TwoBitGenome::from_bytes(&bytes).unwrap();
        let variants = vec![v(2, 10, "A", "T", 0, Strand::None)];
        let err = tally(&mut genome, &variants, all_tables(), &mut || {}).unwrap_err();
        assert_eq!(err.topic, "bounds");
        assert_eq!(err.i, Some(1));
        assert_eq!(err.j, Some(2));
    }

    /// A truncated DNA tail fails the whole call at the first affected
    /// context read (io topic) — no partial results (contract 5).
    #[test]
    fn truncated_genome_fails_the_whole_call() {
        let bytes = fixture_bytes();
        // chr2's record header ends 20 bytes before its packed DNA (its
        // 16-byte DNA covers 40 bases); cutting 8 bytes off the tail keeps
        // header + index parseable but breaks the first chr2 read.
        let cut = bytes.len() - 8;
        let mut genome = TwoBitGenome::from_bytes(&bytes[..cut]).unwrap();
        let variants = golden_variants();
        let err = tally(&mut genome, &variants, all_tables(), &mut || {}).unwrap_err();
        assert_eq!(err.topic, "io");
    }
}
