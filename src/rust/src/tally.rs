//! Catalog assembly core: variant routing + reference-context fetch +
//! SBS96/192/384/1536 & DBS78 counting (U-M1s-09).
//!
//! This module is the pure (R-type-free) heart of `ms_tally_rust`: it
//! borrows an already-mapped 2bit reference byte buffer and a batch of
//! [`TallyVariant`]s, and produces the count matrices plus the provenance
//! ledger. File I/O and mmap ownership stay in the FFI shell
//! (`lib.rs`, the only `unsafe` site, FFI contract 1 / D12: the mapping is
//! built per call and dropped with it).
//!
//! # Pipeline (per call)
//!
//! 1. **Sort** records stably by `(chrom_idx, sample_idx, pos0)` — routing
//!    adjacency (`mnv::route_variants`) is defined over coordinate-sorted
//!    records, so the caller's input order is free.
//! 2. **Partition** into per-`(chrom_idx, sample_idx)` segments and route
//!    each with `msuiter_catalog::mnv::route_variants` (split-VCF
//!    reconnection, DBS candidacy, skip ledger — ARCHITECTURE §7 entry 2).
//!    The sample dimension is load-bearing: SPMG's `dinuc_sub == 1` DBS
//!    detection is a WITHIN-SAMPLE criterion, so two records that are
//!    adjacent on a chromosome but belong to different samples must never
//!    pair into a DBS (each stays an SBS).
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
//! # Concurrency (partition-parallel, contract 6 + 7)
//!
//! The independent units of contract 6 are the `(chrom_idx, sample_idx)`
//! partitions: routing adjacency is a within-partition criterion, so
//! partitions share nothing — no router state, no context-fetch cursor, no
//! output slot. Every partition runs single-threaded with the pipeline's
//! own fixed record order (in-unit reduction order is part of the output
//! contract).
//!
//! * Per-call ThreadPool (`probes::build_call_pool`, `n_threads` / 0 =
//!   rayon-default sentinel; the R side resolves `msuiter.threads` and the
//!   `_R_CHECK_LIMIT_CORES_` cap). The global rayon pool is never used.
//! * Each pool worker owns its own [`TwoBitGenome`] handle over the shared
//!   read-only byte buffer (`context` seeks a cursor, so it needs `&mut`;
//!   handles cannot be shared). The bytes are parsed/validated once on the
//!   main thread, so the per-worker re-parse is infallible.
//! * Per-partition counters are single-column (one partition touches one
//!   sample column) and are merged into the full buffers in partition
//!   order — a fixed reduction of exact integer adds, never an
//!   order-sensitive float accumulation. Outcomes are placed by the
//!   record's input index. Together: `threads ∈ {1, N}` give bit-identical
//!   output (synthesis A7, pinned by tests on both sides of the FFI).
//! * Degenerate shapes stay sequential ON THE MAIN THREAD with the
//!   pre-parallel polling granularity: a single partition (nothing to
//!   parallelize) or `n_threads == 1` (single-core caller, e.g. the
//!   pinned-hardware bench) never build a pool.
//!
//! # Interrupt protocol (contract 7)
//!
//! * Sequential path: the caller-injected `check_user_interrupt` hook runs
//!   once per partition boundary and every [`POLL_EVERY_EVENTS`] events on
//!   the calling (main) thread — exactly the pre-parallel shape.
//! * Parallel path: the main thread polls the hook at CHUNK boundaries
//!   (partitions are scheduled ~4 per worker, capped); workers see ONLY the
//!   `cancelled` `AtomicBool` — at partition start and every
//!   [`POLL_EVERY_EVENTS`] events — never R state. Any cancellation fails
//!   the whole call with the `interrupted` topic: stateless FFI (D12)
//!   means there is nothing to clean up and no partial results to
//!   suppress downstream.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

use rayon::prelude::*;

use msuiter_catalog::dbs::assign_dbs78;
use msuiter_catalog::genome::TwoBitGenome;
use msuiter_catalog::mnv::{route_variants, LedgerEntry, RoutedEvent, SkipReason, VarRecord};
use msuiter_catalog::sbs::{
    assign_sbs1536_slice, assign_sbs192_slice, assign_sbs384_slice, assign_sbs96_slice, Strand,
};
use msuiter_engine::error::MsError;

use super::probes::build_call_pool;

/// Sentinel chromosome index for records whose chromosome name does not
/// occur in the reference genome; such records are ledgered
/// `skipped:unknown_chrom` (never an error, never routed).
pub const UNKNOWN_CHROM: usize = usize::MAX;

/// Interrupt-poll granularity within one (chromosome, sample) partition
/// (contract 7): the main-thread hook runs at this many events on the
/// sequential path, and workers re-check the cancellation flag at the same
/// cadence on the parallel path.
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
    /// Repeat of the identical adjacent record (SPMG :1376-1386; the
    /// U-M1c-01 indel-path dedup).
    SkippedDuplicateRecord,
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
            TallyOutcome::SkippedDuplicateRecord => "skipped:duplicate_record",
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
                | TallyOutcome::SkippedDuplicateRecord
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
            // INTERIM (U-M1c-01): the router now emits Id83 for simple
            // indels; counting them into an ID83 matrix is the tally
            // wiring unit's job. Until that lands, keep the frozen
            // "skipped:simple_indel" provenance so existing fixtures and
            // the R suite stay byte-stable.
            LedgerEntry::Id83 => TallyOutcome::SkippedSimpleIndel,
            LedgerEntry::Skipped(reason) => match reason {
                SkipReason::InvalidBase => TallyOutcome::SkippedInvalidBase,
                SkipReason::EmptyAllele => TallyOutcome::SkippedEmptyAllele,
                SkipReason::RefEqualsAlt => TallyOutcome::SkippedRefEqualsAlt,
                // Retired at U-M1c-01 (no longer emitted by the router);
                // kept for vocabulary stability until the wiring unit.
                SkipReason::SimpleIndel => TallyOutcome::SkippedSimpleIndel,
                SkipReason::DuplicateRecord => TallyOutcome::SkippedDuplicateRecord,
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

/// Flat column-major count buffers (contract 2: explicit layout), assembled
/// from the per-partition single columns in partition order.
struct Counters {
    sbs96: Vec<u32>,
    sbs192: Vec<u32>,
    sbs384: Vec<u32>,
    sbs1536: Vec<u32>,
    dbs78: Vec<u32>,
}

/// Per-partition counters: a `(chrom, sample)` partition touches exactly
/// ONE sample column, so each enabled table is a single channel-length
/// vector (channel-major, disabled tables empty). Merging is a fixed-order
/// scatter of exact integer adds (module docs: thread-count invariance).
struct ColumnCounters {
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

    /// Add one partition's single column into sample column `col`.
    ///
    /// u32 addition is exact and associative, and the per-event
    /// `saturating_add` semantics are preserved by merging saturated
    /// partition sums (any path reaching u32::MAX saturates to u32::MAX
    /// again), so the merge order cannot change a single bit of the
    /// result — the explicit partition order just makes the reduction
    /// order fixed by construction (contract 6).
    fn merge_column(&mut self, col: usize, part: ColumnCounters) {
        let merge = |dst: &mut [u32], src: Vec<u32>, nrow: usize| {
            if dst.is_empty() {
                debug_assert!(src.is_empty(), "disabled table produced counts");
                return;
            }
            let off = col * nrow;
            for (d, s) in dst[off..off + nrow].iter_mut().zip(src) {
                *d = d.saturating_add(s);
            }
        };
        merge(&mut self.sbs96, part.sbs96, 96);
        merge(&mut self.sbs192, part.sbs192, 192);
        merge(&mut self.sbs384, part.sbs384, 384);
        merge(&mut self.sbs1536, part.sbs1536, 1536);
        merge(&mut self.dbs78, part.dbs78, 78);
    }
}

impl ColumnCounters {
    fn new(tables: TallyTables) -> Self {
        let len = |wanted: bool, channels: usize| {
            if wanted {
                vec![0u32; channels]
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

    /// Bump channel `row` of this partition's single sample column.
    ///
    /// Index arithmetic is bounds-checked implicitly by the panic on a
    /// bug; every row reaching this point is table-derived and therefore
    /// in range (row < table_len by construction).
    fn bump(buf: &mut [u32], row: usize) {
        buf[row] = buf[row].saturating_add(1);
    }
}

/// One `(chrom_idx, sample_idx)` partition of the sorted record order: the
/// independent unit of the parallel driver (contract 6). `run` holds
/// indices into the caller's `variants` slice in stable-sorted order.
struct PartitionJob<'a> {
    chrom_idx: usize,
    run: &'a [usize],
    /// Sample column of every record in `run` (first-appearance order of
    /// the caller's input; decided on the main thread before workers run).
    col: usize,
}

/// Everything one partition produced: the per-record outcomes aligned with
/// [`PartitionJob::run`], and the single-column counters to merge at the
/// partition's sample column.
struct PartitionOutput {
    outcomes: Vec<TallyOutcome>,
    counters: ColumnCounters,
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
/// `genome_bytes` is the raw 2bit buffer (the FFI shell's read-only mmap):
/// it is parsed once here for validation and chromosome names, and once
/// per pool worker on the parallel path (module docs, Concurrency).
///
/// `n_threads` is the per-call pool size; `0` means "rayon default" (the
/// R side resolves the `msuiter.threads` option and the
/// `_R_CHECK_LIMIT_CORES_` cap and passes the effective value). A single
/// partition or `n_threads == 1` degenerates to the sequential main-thread
/// path (module docs).
///
/// `check_user_interrupt` is called on the calling thread at partition /
/// chunk boundaries and — on the sequential path — every
/// [`POLL_EVERY_EVENTS`] events (under R: `R_CheckUserInterrupt`,
/// contract 7). Workers only ever read `cancelled`.
pub fn tally(
    genome_bytes: &[u8],
    variants: &[TallyVariant],
    tables: TallyTables,
    n_threads: usize,
    cancelled: &AtomicBool,
    check_user_interrupt: &mut dyn FnMut(),
) -> Result<TallyResult, MsError> {
    // Main-thread parse: format/io validation happens exactly once here
    // (a per-worker re-parse of the same immutable bytes is therefore
    // infallible), and the names drive chrom-index validation and the
    // partition labels.
    let mut genome = TwoBitGenome::from_bytes(genome_bytes)?;
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

    // Stable sort by (chrom, sample, position); ties keep caller order.
    let mut order: Vec<usize> = (0..variants.len()).collect();
    order.sort_by_key(|&k| {
        (
            variants[k].chrom_idx,
            variants[k].sample_idx,
            variants[k].pos0,
        )
    });

    // Partition the sorted order into per-(chrom, sample) jobs: the
    // router's adjacency is a within-sample criterion (module docs).
    let mut jobs: Vec<PartitionJob<'_>> = Vec::new();
    let mut start = 0usize;
    while start < order.len() {
        let chrom_idx = variants[order[start]].chrom_idx;
        let sample_idx = variants[order[start]].sample_idx;
        let mut end = start + 1;
        while end < order.len()
            && variants[order[end]].chrom_idx == chrom_idx
            && variants[order[end]].sample_idx == sample_idx
        {
            end += 1;
        }
        let col = sample_col[&sample_idx];
        jobs.push(PartitionJob {
            chrom_idx,
            run: &order[start..end],
            col,
        });
        start = end;
    }

    // One outcome per input record, reported in caller order.
    let mut resolved: Vec<Option<TallyOutcome>> = vec![None; variants.len()];

    if n_threads != 1 && jobs.len() > 1 {
        // ---- Parallel path (contract 6): partitions scheduled in whole
        // waves. A partition is a COARSE unit (up to whole chromosomes), so
        // unlike the fine-grained replicate driver (4x oversubscription per
        // worker), each chunk here must hold at least one full pool wave --
        // otherwise a small batch (few partitions) would be serialized into
        // one-partition chunks. Wave count = ceil(jobs / workers), capped
        // at 16 to bound the boundary-poll interval; the main thread merges
        // in partition order between waves.
        let pool = build_call_pool(n_threads)?;
        // Size the wave grid by the REAL pool width for the 0 sentinel too:
        // `workers = jobs.len()` collapsed waves to 1 and degraded the
        // effective interrupt granularity to one poll per whole call
        // (audited P1) — worst-case Ctrl-C latency must stay bounded by the
        // longest single partition, not the whole call.
        let workers = match n_threads {
            0 => pool.current_num_threads().max(1),
            t => t.clamp(2, 16),
        };
        let waves = ((jobs.len() + workers - 1) / workers).clamp(1, 16);
        let chunk_len = ((jobs.len() + waves - 1) / waves).max(1);
        let n_chunks = (jobs.len() + chunk_len - 1) / chunk_len;

        for c in 0..n_chunks {
            // Worker-side view (contract 7): the flag is the only
            // cross-thread signal; a tripped flag fails the whole call
            // with no partial results (contract 5).
            if cancelled.load(Ordering::Relaxed) {
                return Err(MsError::new(
                    "interrupted",
                    format!(
                        "call interrupted before chunk {}; no partial results are returned",
                        c + 1
                    ),
                )
                .with_i(c as i64 + 1));
            }
            // Main-thread boundary poll (under R: R_CheckUserInterrupt).
            check_user_interrupt();
            let first = c * chunk_len;
            let last = (first + chunk_len).min(jobs.len());
            let per_partition: Vec<Result<PartitionOutput, MsError>> = pool.install(|| {
                (first..last)
                    .into_par_iter()
                    .map_init(
                        // One genome handle per pool worker over the shared
                        // read-only bytes: `context` seeks a cursor, so
                        // handles cannot be shared across threads. The bytes
                        // were validated above; this parse is infallible.
                        || {
                            TwoBitGenome::from_bytes(genome_bytes)
                                .expect("genome bytes were validated on the main thread")
                        },
                        |genome, p| {
                            let job = &jobs[p];
                            process_partition(
                                genome,
                                &chrom_names,
                                variants,
                                job,
                                p,
                                tables,
                                cancelled,
                                None,
                            )
                        },
                    )
                    .collect()
            });
            // Fixed reduction in partition order: the first error in order
            // is exactly what the sequential path would have raised, and
            // the counter merge order is fixed by construction.
            for (offset, out) in per_partition.into_iter().enumerate() {
                let out = out?;
                absorb(out, &jobs[first + offset], &mut resolved, &mut counters);
            }
        }
    } else {
        // ---- Sequential path: single partition or single-core caller.
        // No pool is built; the pre-parallel polling granularity is kept
        // (boundary per run + every POLL_EVERY_EVENTS events, main thread).
        for (p, job) in jobs.iter().enumerate() {
            check_user_interrupt();
            let out = process_partition(
                &mut genome,
                &chrom_names,
                variants,
                job,
                p,
                tables,
                cancelled,
                Some(&mut *check_user_interrupt),
            )?;
            absorb(out, job, &mut resolved, &mut counters);
        }
    }

    let resolved: Vec<TallyOutcome> = resolved
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

/// Place one partition's output: outcomes by the records' input indices,
/// counters scattered into the partition's sample column. The reduction is
/// index-ordered by construction (module docs).
fn absorb(
    out: PartitionOutput,
    job: &PartitionJob<'_>,
    resolved: &mut [Option<TallyOutcome>],
    counters: &mut Counters,
) {
    for (k, o) in out.outcomes.into_iter().enumerate() {
        resolved[job.run[k]] = Some(o);
    }
    counters.merge_column(job.col, out.counters);
}

/// Process one `(chrom, sample)` partition: routing, context fetch +
/// validation + counting. Single-threaded by construction (the partition
/// is the sequential unit of contract 6); `main_poll` is `Some` only on
/// the main-thread sequential path, where the R interrupt hook runs at
/// [`POLL_EVERY_EVENTS`] cadence — workers instead re-check the
/// cancellation flag at the same cadence (contract 7: workers never see R
/// state).
#[allow(clippy::too_many_arguments)]
fn process_partition(
    genome: &mut TwoBitGenome<'_>,
    chrom_names: &[String],
    variants: &[TallyVariant],
    job: &PartitionJob<'_>,
    part_no: usize,
    tables: TallyTables,
    cancelled: &AtomicBool,
    mut main_poll: Option<&mut dyn FnMut()>,
) -> Result<PartitionOutput, MsError> {
    // Worker-side view (contract 7): the flag is the only cross-thread
    // signal a unit ever sees; a tripped flag fails the whole call with
    // no partial results (contract 5).
    if cancelled.load(Ordering::Relaxed) {
        return Err(MsError::new(
            "interrupted",
            format!(
                "worker observed cancellation at partition {}; no partial results are returned",
                part_no + 1
            ),
        )
        .with_i(part_no as i64 + 1));
    }

    // Partition-local outcomes, indexed by the position within the run.
    let mut outcomes: Vec<Option<TallyOutcome>> = vec![None; job.run.len()];
    let mut counters = ColumnCounters::new(tables);

    if job.chrom_idx == UNKNOWN_CHROM {
        for slot in outcomes.iter_mut() {
            *slot = Some(TallyOutcome::SkippedUnknownChrom);
        }
    } else {
        let chrom = chrom_names[job.chrom_idx].as_str();
        let recs: Vec<VarRecord<'_>> = job
            .run
            .iter()
            .map(|&k| VarRecord::new(variants[k].pos0, &variants[k].ref_, &variants[k].alt))
            .collect();
        let routing = route_variants(&recs);
        // Baseline outcomes: the router's per-record ledger, verbatim.
        for (run_k, entry) in routing.ledger.entries().iter().enumerate() {
            outcomes[run_k] = Some(TallyOutcome::of_entry(*entry));
        }
        let mut events_since_poll = 0usize;
        for event in &routing.events {
            events_since_poll += 1;
            if events_since_poll % POLL_EVERY_EVENTS == 0 {
                match main_poll.as_deref_mut() {
                    // Sequential path: the R hook at the pre-parallel
                    // cadence (under R: R_CheckUserInterrupt).
                    Some(poll) => poll(),
                    // Parallel path: workers re-check ONLY the flag.
                    None => {
                        if cancelled.load(Ordering::Relaxed) {
                            return Err(MsError::new(
                                "interrupted",
                                format!(
                                    "worker observed cancellation at partition {}",
                                    part_no + 1
                                ),
                            )
                            .with_i(part_no as i64 + 1));
                        }
                    }
                }
            }
            tally_event(
                genome,
                chrom,
                variants,
                job.run,
                event,
                tables,
                &mut counters,
                &mut outcomes,
            )?;
        }
    }

    let outcomes = outcomes
        .into_iter()
        .map(|o| o.expect("every record receives exactly one outcome"))
        .collect();
    Ok(PartitionOutput { outcomes, counters })
}

/// Process one routed event: context fetch + validation + counting.
/// Assembly-layer failures overwrite the baseline (router) outcomes of the
/// event's records with the qualifying skip. `outcomes` is the partition's
/// local slot vector (indexed by position within the run) and `counters`
/// the partition's single sample column.
#[allow(clippy::too_many_lines)] // one flat match per event kind reads best
#[allow(clippy::too_many_arguments)]
fn tally_event(
    genome: &mut TwoBitGenome<'_>,
    chrom: &str,
    variants: &[TallyVariant],
    run: &[usize],
    event: &RoutedEvent,
    tables: TallyTables,
    counters: &mut ColumnCounters,
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
                    outcomes[record] = Some(TallyOutcome::SkippedContextBounds);
                    return Ok(());
                }
                Err(e) => return Err(e), // io/format: corrupt file fails the call
            };
            if !all_acgt(&ctx5) {
                outcomes[record] = Some(TallyOutcome::SkippedNContext);
                return Ok(());
            }
            if ctx5[2] != ref_byte {
                outcomes[record] = Some(TallyOutcome::SkippedRefMismatch);
                return Ok(());
            }
            let v = &variants[orig];
            let ctx3 = &ctx5[1..4];
            if tables.sbs96 {
                let row = assign_sbs96_slice(ctx3, alt)?;
                ColumnCounters::bump(&mut counters.sbs96, row);
            }
            if tables.sbs192 && !matches!(v.strand, Strand::Bidirectional | Strand::None) {
                // B/N strands have no SBS192 channel: dropped from THIS
                // matrix only (module docs) — not a ledger skip.
                let row = assign_sbs192_slice(ctx3, alt, v.strand)?;
                ColumnCounters::bump(&mut counters.sbs192, row);
            }
            if tables.sbs384 {
                let row = assign_sbs384_slice(ctx3, alt, v.strand)?;
                ColumnCounters::bump(&mut counters.sbs384, row);
            }
            if tables.sbs1536 {
                let row = assign_sbs1536_slice(&ctx5, alt)?;
                ColumnCounters::bump(&mut counters.sbs1536, row);
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
                        outcomes[run_k] = Some(TallyOutcome::SkippedContextBounds);
                    }
                    return Ok(());
                }
                Err(e) => return Err(e),
            };
            if !all_acgt(&dinuc) {
                for &run_k in &records {
                    outcomes[run_k] = Some(TallyOutcome::SkippedNDinuc);
                }
                return Ok(());
            }
            if dinuc[0] != ref2[0] || dinuc[1] != ref2[1] {
                for &run_k in &records {
                    outcomes[run_k] = Some(TallyOutcome::SkippedRefMismatch);
                }
                return Ok(());
            }
            if tables.dbs78 {
                let row = assign_dbs78(&ref2, &alt2)?;
                ColumnCounters::bump(&mut counters.dbs78, row);
            }
            Ok(())
        }
        // Mnv / LongMnv / ComplexIndel are ledger-only until the ID83 and
        // complex layers land (U-M1c); the baseline outcome stands. Same
        // for RoutedEvent::Indel: its ID83 counting is the tally wiring
        // unit (the router already carried the fields for it, U-M1c-01).
        RoutedEvent::Mnv { .. }
        | RoutedEvent::LongMnv { .. }
        | RoutedEvent::ComplexIndel { .. }
        | RoutedEvent::Indel { .. } => Ok(()),
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

    /// A clean flag for tests that never trip cancellation.
    fn no_cancel() -> AtomicBool {
        AtomicBool::new(false)
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
            v(0, 32, "AC", "G", 1, Strand::None),           // simple deletion: independent indel event (SPMG never merges
            v(0, 31, "C", "TA", 1, Strand::None),           // it with the adjacent insertion, memo §4)
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
            "9\tskipped:simple_indel",
            "10\tskipped:simple_indel",
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
        let variants = golden_variants();
        let mut polls = 0usize;
        let res = tally(
            &bytes,
            &variants,
            all_tables(),
            1,
            &no_cancel(),
            &mut || polls += 1,
        )
        .unwrap();

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
        assert_eq!(res.n_skipped, 11);

        // Contract 7 on the sequential path (single core, the pre-parallel
        // granularity): one poll per (chrom, sample) run — chr1 splits into
        // sample-0 and sample-1 segments, chr2 is one sample-1 segment,
        // chrZ one unknown-chrom segment; 17 events < POLL_EVERY_EVENTS.
        assert_eq!(polls, 4);

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
        let variants = golden_variants();
        let res = tally(&bytes, &variants, TallyTables::default(), 1, &no_cancel(), &mut || {}).unwrap();
        assert!(res.sbs96.is_empty() && res.sbs192.is_empty() && res.sbs384.is_empty());
        assert!(res.sbs1536.is_empty() && res.dbs78.is_empty());
        assert_eq!(res.ledger_tsv, golden_ledger());
        assert_eq!(res.n_skipped, 11);
    }

    #[test]
    fn empty_input_is_all_empty() {
        let bytes = fixture_bytes();
        let mut polls = 0usize;
        let res = tally(&bytes, &[], all_tables(), 1, &no_cancel(), &mut || polls += 1).unwrap();
        assert!(res.sbs96.is_empty() && res.dbs78.is_empty());
        assert_eq!(res.ledger_tsv, "");
        assert_eq!(res.n_skipped, 0);
        assert_eq!(polls, 0); // no runs: no boundary polls
    }

    /// U-M1s-09 audit regression (P1): routing adjacency is a
    /// WITHIN-SAMPLE criterion (SPMG `dinuc_sub == 1`). Two records
    /// adjacent on a chromosome but attributed to different samples must
    /// each stay an Sbs — never pair into a Dbs (which would also evict
    /// both from the SBS matrices).
    #[test]
    fn cross_sample_adjacent_snvs_are_never_a_dbs_pair() {
        let bytes = fixture_bytes();
        // chr1 is ACAC...: 0-based 11 is C, 12 is A — the pair is
        // coordinate-adjacent, the samples differ.
        let variants = vec![
            v(0, 11, "C", "A", 0, Strand::None),
            v(0, 12, "A", "T", 1, Strand::None),
        ];
        let res = tally(&bytes, &variants, all_tables(), 1, &no_cancel(), &mut || {}).unwrap();

        assert_eq!(res.ledger_tsv, "1\tsbs\n2\tsbs\n");
        assert_eq!(res.n_skipped, 0);
        // No DBS78 count anywhere; each sample column holds one SBS96 cell.
        // (The A>T purine center mirrors to the pyrimidine label G[T>A]G.)
        assert!(res.dbs78.iter().all(|&c| c == 0));
        assert_eq!(res.sbs96.iter().sum::<u32>(), 2);
        let row_of = |label: &str| {
            (0..96)
                .find(|&r| msuiter_catalog::sbs::sbs96_label(r) == Ok(label))
                .unwrap()
        };
        assert_eq!(cell(&res.sbs96, row_of("A[C>A]A"), 0, 96), 1); // sample 0
        assert_eq!(cell(&res.sbs96, row_of("G[T>A]G"), 1, 96), 1); // sample 1

        // Mirrored input order (the later-position record first) must not
        // change the outcome: sorting keeps the pairing within-sample.
        let reversed = variants.iter().rev().cloned().collect::<Vec<_>>();
        let res = tally(&bytes, &reversed, all_tables(), 1, &no_cancel(), &mut || {}).unwrap();
        assert_eq!(res.ledger_tsv, "1\tsbs\n2\tsbs\n");
        assert!(res.dbs78.iter().all(|&c| c == 0));
    }

    /// Contract 4: a chromosome index that is neither a real index nor the
    /// UNKNOWN_CHROM sentinel is a structured bounds error, never a panic.
    #[test]
    fn out_of_range_chrom_index_is_a_bounds_error() {
        let bytes = fixture_bytes();
        let variants = vec![v(2, 10, "A", "T", 0, Strand::None)];
        let err = tally(&bytes, &variants, all_tables(), 1, &no_cancel(), &mut || {}).unwrap_err();
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
        let err = tally(
            &bytes[..cut],
            &golden_variants(),
            all_tables(),
            1,
            &no_cancel(),
            &mut || {},
        )
        .unwrap_err();
        assert_eq!(err.topic, "io");
    }

    // -----------------------------------------------------------------
    // Partition-parallel driver (contract 6 + 7): thread-count invariance,
    // sequential-reference parity, chunk-boundary interrupts.
    // -----------------------------------------------------------------

    /// A larger fixture for the driver tests: 2 x 8192 bp alternating DNA,
    /// chr2 carrying an N block (n_context / n_dinuc territory at scale).
    fn big_fixture_bytes() -> Vec<u8> {
        fixture::build(&[
            fixture::ChromSpec {
                name: "chr1",
                size: 8192,
                pattern: seq_ac,
                n_blocks: vec![],
            },
            fixture::ChromSpec {
                name: "chr2",
                size: 8192,
                pattern: seq_gc,
                n_blocks: vec![(4000, 16)],
            },
        ])
    }

    /// Reference base of the big fixture at `pos0` (chrom index 0 = ACAC...,
    /// chrom index 1 = GCGC...).
    fn big_ref(chrom: usize, pos0: u64) -> (&'static str, &'static str) {
        match (chrom, pos0 % 2) {
            (0, 0) => ("A", "G"),
            (0, _) => ("C", "T"),
            (_, 0) => ("G", "T"),
            (_, _) => ("C", "A"),
        }
    }

    /// A deterministic multi-chromosome, multi-sample batch (~2k events):
    /// SNVs in stride, periodic same-sample adjacent pairs (DBS pairing at
    /// scale), periodic indels, N-window records on chr2, unknown-chrom
    /// records, fed in a non-sorted order.
    fn big_batch() -> Vec<TallyVariant> {
        let mut out = Vec::new();
        for chrom in 0..2usize {
            for sample in 0..3usize {
                for k in 0..300usize {
                    let pos0 = 64 + (k * 13) as u64;
                    let (r, a) = big_ref(chrom, pos0);
                    out.push(v(chrom, pos0, r, a, sample, Strand::None));
                    if k % 25 == 0 {
                        // adjacent same-sample SNV: DBS-candidate territory
                        let (r1, a1) = big_ref(chrom, pos0 + 1);
                        out.push(v(chrom, pos0 + 1, r1, a1, sample, Strand::Transcribed));
                    }
                    if k % 40 == 0 {
                        out.push(v(chrom, pos0, "CA", "C", sample, Strand::None)); // simple indel
                    }
                }
            }
        }
        for sample in 0..3usize {
            out.push(v(UNKNOWN_CHROM, 10, "A", "T", sample, Strand::None));
            // +/-2 window of chr2 position 3999 reaches the N block at 4000.
            out.push(v(1, 3999, "C", "A", sample, Strand::None));
        }
        out.reverse(); // deterministic non-sorted input order
        out
    }

    /// Number of (chrom, sample) partitions a batch splits into (mirrors
    /// the driver's partitioning for the poll-count assertions below).
    fn partition_count(variants: &[TallyVariant]) -> usize {
        let mut parts: Vec<(usize, usize)> = variants
            .iter()
            .map(|v| (v.chrom_idx, v.sample_idx))
            .collect();
        parts.sort_unstable();
        parts.dedup();
        parts.len()
    }

    /// A7 / contract 6 on the real assembly pipeline: threads ∈ {1, 4, 16}
    /// → bit-identical [`TallyResult`] (`assert_eq!` on the whole struct,
    /// not tolerance), and the parallel output equals the sequential
    /// reference (the n_threads == 1 main-thread path).
    #[test]
    fn parallel_output_matches_sequential_reference_for_every_thread_count() {
        let bytes = big_fixture_bytes();
        let variants = big_batch();
        let run = |threads: usize| {
            let mut polls = 0usize;
            let res =
                tally(&bytes, &variants, all_tables(), threads, &no_cancel(), &mut || polls += 1)
                    .unwrap();
            (res, polls)
        };
        let (one, p1) = run(1);
        let (four, p4) = run(4);
        let (sixteen, _p16) = run(16);
        assert_eq!(one, four);
        assert_eq!(one, sixteen);

        // Pipeline invariants on the batch: every sbs ledger line has
        // exactly one SBS96 count, and the DBS-pair records land in DBS78
        // (12 periodic adjacent pairs per (chromosome, sample)).
        let n_sbs = one
            .ledger_tsv
            .lines()
            .filter(|l| l.ends_with("\tsbs"))
            .count();
        assert_eq!(one.sbs96.iter().sum::<u32>(), n_sbs as u32);
        assert_eq!(one.dbs78.iter().sum::<u32>(), 72);

        // Polling protocols differ by path (both counts deterministic):
        // sequential = one boundary poll per partition; threads=4 fans 9
        // partitions over whole waves (ceil(9/4) = 3 waves, capped).
        let jobs = partition_count(&variants);
        assert_eq!(p1, jobs);
        let waves = ((jobs + 4 - 1) / 4).clamp(1, 16);
        let chunk_len = ((jobs + waves - 1) / waves).max(1);
        assert_eq!(p4, (jobs + chunk_len - 1) / chunk_len);
    }

    /// Audited P1 regression guard: the 0 sentinel (rayon default) must size
    /// the wave grid by the REAL pool width, so the wave count stays > 1 on
    /// multi-partition batches and boundary polling keeps the worst-case
    /// Ctrl-C latency bounded by the longest partition (not the whole call).
    #[test]
    fn default_threads_poll_between_waves_on_multi_partition_batch() {
        let bytes = big_fixture_bytes();
        let variants = big_batch();
        let jobs = partition_count(&variants);
        let pool = crate::probes::build_call_pool(0).unwrap();
        let workers = pool.current_num_threads().max(1);
        let waves = ((jobs + workers - 1) / workers).clamp(1, 16);
        let chunk_len = ((jobs + waves - 1) / waves).max(1);
        let expected_polls = (jobs + chunk_len - 1) / chunk_len;

        let mut polls = 0usize;
        let res = tally(&bytes, &variants, all_tables(), 0, &no_cancel(), &mut || {
            polls += 1
        })
        .unwrap();
        assert_eq!(polls, expected_polls, "0-sentinel waves must track the real pool width");
        if jobs > workers {
            assert!(polls > 1, "multi-partition batch beyond one wave must poll between waves");
        }
        // Same result as the sequential path.
        let seq = tally(&bytes, &variants, all_tables(), 1, &no_cancel(), &mut || {}).unwrap();
        assert_eq!(res, seq);
    }

    /// A single (chrom, sample) partition has nothing to parallelize: the
    /// call degenerates to the sequential main-thread path for every
    /// thread count, keeping the fine-grained intra-run polling (boundary
    /// + every POLL_EVERY_EVENTS events).
    #[test]
    fn single_partition_degenerates_to_sequential_with_intra_run_polls() {
        let bytes = fixture::build(&[fixture::ChromSpec {
            name: "chr1",
            size: 100_000,
            pattern: seq_ac,
            n_blocks: vec![],
        }]);
        // 9000 SNVs in stride 11 on one chromosome, one sample: 9000 SBS
        // events → intra polls at events 4096 and 8192.
        let variants: Vec<TallyVariant> = (0..9000)
            .map(|k| {
                let pos0 = 50 + (k * 11) as u64;
                let (r, a) = big_ref(0, pos0);
                v(0, pos0, r, a, 0, Strand::None)
            })
            .collect();

        let mut polls1 = 0usize;
        let one = tally(&bytes, &variants, all_tables(), 1, &no_cancel(), &mut || polls1 += 1).unwrap();
        assert_eq!(polls1, 3); // 1 boundary + events 4096, 8192
        assert_eq!(one.sbs96.iter().sum::<u32>(), 9000);

        let mut polls16 = 0usize;
        let sixteen = tally(&bytes, &variants, all_tables(), 16, &no_cancel(), &mut || polls16 += 1).unwrap();
        assert_eq!(polls16, 3); // still the sequential path: one partition
        assert_eq!(one, sixteen);
    }

    #[test]
    fn pre_cancelled_parallel_call_fails_without_partial_results() {
        let bytes = big_fixture_bytes();
        let variants = big_batch();
        let cancelled = AtomicBool::new(true);
        let err = tally(&bytes, &variants, all_tables(), 2, &cancelled, &mut || {}).unwrap_err();
        assert_eq!(err.topic, "interrupted");
        assert_eq!(err.i, Some(1));
    }

    /// The flag tripped in the first boundary poll is observed by the
    /// chunk's workers (the worker-side contract-7 view: workers never see
    /// R state, only the flag), failing the whole call (contract 5).
    #[test]
    fn flag_tripped_at_first_boundary_fails_with_worker_error() {
        let bytes = big_fixture_bytes();
        let variants = big_batch();
        let cancelled = AtomicBool::new(false);
        let mut polls = 0usize;
        let err = tally(&bytes, &variants, all_tables(), 2, &cancelled, &mut || {
            polls += 1;
            if polls == 1 {
                cancelled.store(true, Ordering::Relaxed);
            }
        })
        .unwrap_err();
        assert_eq!(polls, 1);
        assert_eq!(err.topic, "interrupted");
        assert!(err.to_string().contains("worker observed"));
    }
}
