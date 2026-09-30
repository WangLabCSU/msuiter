//! ID83 indel channel arithmetic (U-M1c-01).
//!
//! Semantic source of truth: SigProfilerMatrixGenerator (SPMG),
//! `catalogue_generator_INDEL_single`, audited line-by-line at
//! `docs/devlog/2026-09-30-ID83-design-memo.md` against upstream master
//! `edccbea6` (PR #256 merge). The whole ID function is byte-identical in
//! tag v1.3.6 (memo §1.1), so the D11 claim "bit-faithful to SPMG master
//! AND v1.3.6" holds for every behaviour here. Line references below are
//! master `MutationMatrixGenerator.py` (MMG) unless marked Func.
//!
//! # Channel table
//!
//! `ID83_CHANNELS` is rows 0..83 of SPMG's `indel_types`
//! (Func:1054-1138), the rows SPMG actually writes (`iloc[:83]`,
//! MMG:3738). The canonical order — 1bp C/T blocks, then Del R, Ins R,
//! then Del M — is the upstream index order, NOT one global ASCII sort
//! (memo §2.1 is the authority; its §2.2 "ASCII" remark is loose). Rows
//! 83-95 of `indel_types` (`{2..5}:Ins:M:*`, `complex`, `non_matching`)
//! are SPMG extension/bookkeeping rows with no ID83 channel; this module
//! surfaces the Ins:M case as [`Indel83Outcome::InsMicrohomologyNoChannel`]
//! so the assembly layer can ledger it explicitly. The table lives here as
//! a static constant (memo §2: generation rationale in this header); a
//! later unit may migrate it to the generated `channels.rs` +
//! `build_channels.R` / `R/sysdata.rda` pipeline alongside SBS96/DBS78.
//!
//! # Geometry (the F1 fork, memo §3.1/§3.4)
//!
//! `pos0` is the 0-based ANCHOR position (`pos0 + 1` = the 1-based VCF
//! POS SPMG uses as `start`); a deletion is `REF = anchor + deleted`,
//! an insertion `ALT = anchor + inserted`. Walk windows therefore END at
//! the anchor on the left (left window `[start-L, start)` 0-based,
//! INCLUDES the anchor) and start after the affected segment on the right
//! (deletion) / after the anchor (insertion). Implementing "from the
//! deleted segment directly" shifts every R/M key4 by one base — the
//! memo's F1 trap.
//!
//! # Exactness guards (the F3 fork, memo §3.4/§3.8)
//!
//! * Initial window reads are UNGUARDED in SPMG (:1462/:1471/:1551/:1560):
//!   a window past the chromosome end is an uncaught IndexError there and
//!   a structured `bounds` [`MsError`] here (hardening, D13 — the assembly
//!   layer routes it to the skip ledger, sbs.rs N-window precedent).
//! * Extension guards are replicated verbatim, including the strict-by-one
//!   edges: left `pos_rev - L > 0` (:1464/:1553) rejects a window that
//!   touches index 0; right `pos + L < len` (:1474-1477/:1563-1566)
//!   rejects a window whose last base is the chromosome's final base.
//! * Python negative indices WRAP to the chromosome tail. The PI ruling
//!   (memo §3.8/G31) is to replicate. Consequence verified at source: the
//!   left-walk guard short-circuits before ever comparing a wrapped
//!   window (`pos_rev - L > 0` is false exactly when the window start
//!   would be negative), so wrapped left-walk reads are fetched-then-
//!   discarded — replicated for fetch fidelity (a wrapped fetch whose
//!   tail offset exceeds the chromosome errors, like SPMG's IndexError).
//!   The MH reverse search has NO guard (:1523-1532/:1612-1621), so its
//!   wrapped windows ARE compared and observable (golden G31c).
//!
//! # R before M, forward ties (the F2 fork, memo §3.5)
//!
//! Microhomology is consulted only when the repeat walk zero-extended
//! (:1485/:1574) — one extension copy beats any MH; MH key4 >= 1 (there
//! is no M:0 row); forward wins ties (:1535). Ins:M events exist upstream
//! but have no ID83 channel (see above).
//!
//! # Transcription independence
//!
//! ID83 is completely independent of transcription-strand annotation
//! (memo §2.2): no `Strand` input anywhere. The SPMG TSB ambiguity
//! predicate ("Q") is provided as the pure function [`q_predicate`] for
//! the future ID415 family; ID83 never consumes it.
//!
//! # Input contract and error discipline
//!
//! Allele bytes must be uppercase ACGT and `ref_ != alt` (the router's
//! `validate` guarantees this; violations are defensive `argument`
//! errors, sbs.rs precedent). The anchor-vs-genome comparison
//! (:1408-1421, including a literal N anchor) is this layer's job per the
//! memo §4.5 verification split and surfaces as
//! [`Indel83Outcome::AnchorMismatch`]. Window reads go through the
//! caller-supplied fetch closure (D12: stateless, everything closes over
//! within the call); the closure must honour the `genome::range` bounds
//! discipline — `assign_indel83_slice` and [`assign_indel83_genome`]
//! provide conforming implementations.

use msuiter_engine::MsError;

use crate::genome::TwoBitGenome;
use crate::sbs::{Strand, channel_label};

/// The canonical ID83 channel table: SPMG `indel_types` rows 0..83
/// (Func:1054-1138, write path `iloc[:83]` MMG:3738). See the module docs
/// for the generation rationale and the block-boundary index map.
#[rustfmt::skip]
pub static ID83_CHANNELS: [&str; 83] = [
    // 1 bp deletions, C class (deleted base in {C, G}), key4 = run extensions 0..=5
    "1:Del:C:0", "1:Del:C:1", "1:Del:C:2", "1:Del:C:3", "1:Del:C:4", "1:Del:C:5",
    // 1 bp deletions, T class (deleted base in {A, T})
    "1:Del:T:0", "1:Del:T:1", "1:Del:T:2", "1:Del:T:3", "1:Del:T:4", "1:Del:T:5",
    // 1 bp insertions, C class (inserted base in {C, G})
    "1:Ins:C:0", "1:Ins:C:1", "1:Ins:C:2", "1:Ins:C:3", "1:Ins:C:4", "1:Ins:C:5",
    // 1 bp insertions, T class (inserted base in {A, T})
    "1:Ins:T:0", "1:Ins:T:1", "1:Ins:T:2", "1:Ins:T:3", "1:Ins:T:4", "1:Ins:T:5",
    // >1 bp tandem-repeat deletions: key1 = unit length (capped 5), key4 = copies - 1
    "2:Del:R:0", "2:Del:R:1", "2:Del:R:2", "2:Del:R:3", "2:Del:R:4", "2:Del:R:5",
    "3:Del:R:0", "3:Del:R:1", "3:Del:R:2", "3:Del:R:3", "3:Del:R:4", "3:Del:R:5",
    "4:Del:R:0", "4:Del:R:1", "4:Del:R:2", "4:Del:R:3", "4:Del:R:4", "4:Del:R:5",
    "5:Del:R:0", "5:Del:R:1", "5:Del:R:2", "5:Del:R:3", "5:Del:R:4", "5:Del:R:5",
    // >1 bp tandem-repeat insertions
    "2:Ins:R:0", "2:Ins:R:1", "2:Ins:R:2", "2:Ins:R:3", "2:Ins:R:4", "2:Ins:R:5",
    "3:Ins:R:0", "3:Ins:R:1", "3:Ins:R:2", "3:Ins:R:3", "3:Ins:R:4", "3:Ins:R:5",
    "4:Ins:R:0", "4:Ins:R:1", "4:Ins:R:2", "4:Ins:R:3", "4:Ins:R:4", "4:Ins:R:5",
    "5:Ins:R:0", "5:Ins:R:1", "5:Ins:R:2", "5:Ins:R:3", "5:Ins:R:4", "5:Ins:R:5",
    // Microhomology-mediated deletions: key4 = MH bases (1..=key1-1; the
    // key1=5 row also carries L>5 events capped at 5)
    "2:Del:M:1",
    "3:Del:M:1", "3:Del:M:2",
    "4:Del:M:1", "4:Del:M:2", "4:Del:M:3",
    "5:Del:M:1", "5:Del:M:2", "5:Del:M:3", "5:Del:M:4", "5:Del:M:5",
];

/// Outcome of ID83 assignment for one anchor-style indel record. The three
/// ways are mutually exclusive and total (A11: every classified record
/// lands somewhere explicit).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Indel83Outcome {
    /// Counted: the ID83 table index.
    Channel(usize),
    /// SPMG classifies the event as `N:Ins:M:x` (microhomology-mediated
    /// insertion), which has no ID83 channel: SPMG itself computes the key
    /// but writes only `iloc[:83]` (MMG:3738; Func rows 83-93 are its
    /// extension rows). An explicit ledger skip, not an error (golden
    /// G28/G29).
    InsMicrohomologyNoChannel,
    /// The anchor byte disagrees with the reference genome, including a
    /// literal N anchor (:1408-1421) — SPMG's per-mutation skip.
    AnchorMismatch,
}

impl Indel83Outcome {
    /// The table index, if the event has an ID83 channel.
    #[inline]
    #[must_use]
    pub fn channel(self) -> Option<usize> {
        match self {
            Indel83Outcome::Channel(i) => Some(i),
            Indel83Outcome::InsMicrohomologyNoChannel | Indel83Outcome::AnchorMismatch => None,
        }
    }
}

/// Validate the record-level input contract (uppercase ACGT alleles, both
/// present, actual indel shape). Splits the error positions: `slot` 0 =
/// ref, 1 = alt (1-based allele-byte reporting, dbs.rs convention).
fn validate_alleles(ref_: &[u8], alt: &[u8]) -> Result<(), MsError> {
    if ref_.is_empty() || alt.is_empty() {
        return Err(MsError::new(
            "argument",
            "ref and alt alleles must both be non-empty (anchor-style indel record)",
        ));
    }
    for (slot, allele) in [(0usize, ref_), (1, alt)] {
        for (k, &byte) in allele.iter().enumerate() {
            if !matches!(byte, b'A' | b'C' | b'G' | b'T') {
                return Err(MsError::new(
                    "argument",
                    format!(
                        "invalid allele byte 0x{byte:02X} at {}[{}] (expected uppercase A, C, G or T)",
                        if slot == 0 { "ref" } else { "alt" },
                        k
                    ),
                )
                .with_i(k as i64 + 1)
                .with_j(slot as i64 + 1));
            }
        }
    }
    let (del_len, ins_len) = indel_shape(ref_, alt);
    if del_len >= 1 && ins_len >= 1 {
        return Err(MsError::new(
            "argument",
            "both alleles longer than one base: complex indel, routed separately (SPMG :1445-1449)",
        ));
    }
    if del_len == 0 && ins_len == 0 {
        return Err(MsError::new(
            "argument",
            if ref_ == alt {
                "ref and alt alleles are identical; not an indel (SPMG :1361-1374)"
            } else {
                "equal-length alleles are a block substitution (MNV routing), not an indel (SPMG :1445-1449)"
            },
        ));
    }
    Ok(())
}

/// SPMG's classification split (:1427-1449): `(del_len, ins_len)` with the
/// anchor occupying one base on each side.
#[inline]
fn indel_shape(ref_: &[u8], alt: &[u8]) -> (usize, usize) {
    (ref_.len().saturating_sub(1), alt.len().saturating_sub(1))
}

/// ID83 channel of one anchor-style indel record.
///
/// `fetch(start0, len)` reads an arbitrary 0-based window of the record's
/// chromosome and must honour the `genome::range` error discipline (topic
/// `"bounds"`, never clamping); `chrom_len` is that chromosome's length,
/// needed to replicate Python's negative-index wraparound (module docs,
/// F3). `pos0` is the 0-based anchor (`pos0 + 1` = 1-based VCF POS).
///
/// Errors are structured skip candidates: `bounds` (window past the
/// chromosome — SPMG's uncaught IndexError, hardened per D13) or
/// `argument` (contract violation). Every `Ok` outcome is either a
/// channel, the channel-less Ins:M class, or an anchor mismatch.
pub fn assign_indel83<F>(
    mut fetch: F,
    chrom_len: usize,
    pos0: u64,
    ref_: &[u8],
    alt: &[u8],
) -> Result<Indel83Outcome, MsError>
where
    F: FnMut(usize, usize) -> Result<Vec<u8>, MsError>,
{
    validate_alleles(ref_, alt)?;
    let pos0 = usize::try_from(pos0)
        .map_err(|_| MsError::new("argument", "position exceeds addressable range"))?;

    // Anchor-vs-genome comparison, :1408-1421 (one byte only — the
    // deleted segment's correctness is implied by the walk's matching).
    // An out-of-chromosome anchor fails the fetch as a bounds error
    // (:1391-1406's skip, structured).
    let anchor = fetch(pos0, 1)?;
    if anchor.first() != Some(&ref_[0]) {
        return Ok(Indel83Outcome::AnchorMismatch);
    }
    // SPMG's `start` is the 1-based POS; everything below uses its
    // 0-based-flavoured cursor arithmetic verbatim.
    let start = pos0 + 1;

    let (del_len, ins_len) = indel_shape(ref_, alt);
    debug_assert!(del_len >= 1 || ins_len >= 1, "validated above");
    let is_del = del_len >= 1;
    let unit: &[u8] = if is_del { &ref_[1..] } else { &alt[1..] };
    let l = unit.len();

    // Wrapped left-window read, replicating Python's `chrom_string[i]`
    // negative indexing: window `[end - w, end)` with `end >= 1`; when
    // `end < w` the leading `w - end` indices are negative and wrap to
    // the chromosome tail (tail bytes first, in ascending-index order).
    // A tail offset past the chromosome start errors, like SPMG's
    // IndexError on `chrom_string[-k]` with k > len.
    let read_left_window =
        |fetch: &mut F, end: usize, w: usize| -> Result<Vec<u8>, MsError> {
            if end >= w {
                return fetch(end - w, w);
            }
            let tail_k = w - end;
            if chrom_len < tail_k {
                return Err(MsError::new(
                    "bounds",
                    format!(
                        "wrapped window needs {tail_k} tail bases, chromosome has {chrom_len}"
                    ),
                )
                .with_i(1)
                .with_j(chrom_len as i64));
            }
            let mut out = fetch(chrom_len - tail_k, tail_k)?;
            out.extend_from_slice(&fetch(0, end)?);
            Ok(out)
        };

    // --- Tandem-repeat walk (Del :1451-1482 / Ins :1543-1571) ------------
    // `sequence` accumulates the deleted/inserted unit plus every matched
    // flank copy (SPMG's `sequence`).
    let mut sequence = unit.to_vec();

    // Left walk: initial window ends at the anchor (unguarded read,
    // :1462/:1551); guard + EXACT compare (:1464/:1553); step L.
    let mut pos_rev = start;
    let mut actual_seq = read_left_window(&mut fetch, pos_rev, l)?;
    while pos_rev > l && actual_seq == unit {
        let mut prepended = actual_seq;
        prepended.extend_from_slice(&sequence);
        sequence = prepended;
        pos_rev -= l;
        actual_seq = read_left_window(&mut fetch, pos_rev, l)?;
    }

    // Right walk: window starts after the affected segment (Del,
    // :1471-1473) / at the insertion point right after the anchor (Ins,
    // :1560-1562, `pos = start`); unguarded initial read; guard + EXACT
    // compare (:1474-1477/:1563-1566); step L.
    let mut pos = if is_del { start + l } else { start };
    let mut new_seq = fetch(pos, l)?;
    while pos + l < chrom_len && new_seq == unit {
        sequence.extend_from_slice(&new_seq);
        pos += l;
        new_seq = fetch(pos, l)?;
    }

    // --- Microhomology (only when the walk zero-extended), F2 -----------
    // Del :1484-1540 / Ins :1573-1629. `sequence == unit` iff no copy
    // was added on either side.
    let mut for_hom: usize = 0;
    let mut for_seq: Option<Vec<u8>> = None;
    let mut rev_hom: usize = 0;
    let mut rev_seq: Option<Vec<u8>> = None;
    let mut is_mh = false;
    if l > 1 && sequence.len() == l {
        // forward_homology = ref/mut minus its last base; reverse_homology
        // = minus its first (:1486-1487/:1575-1576).
        let fwd = &unit[..l - 1];
        let rev = &unit[1..];
        // Forward search: longest first, window immediately after the
        // affected segment for Del (pos = start + L) / at the insertion
        // point for Ins (pos = start). No bounds guard upstream: a window
        // past the chromosome end errors (structured here).
        let pos_f = if is_del { start + l } else { start };
        for i in (1..=l - 1).rev() {
            let win = fetch(pos_f, i)?;
            if win.as_slice() == &fwd[..i] {
                for_hom = i;
                for_seq = Some(win);
                break;
            }
        }
        // Reverse search: window immediately before, ENDING at the anchor
        // (pos = start). Unguarded upstream AND unguarded negative
        // indexing: wrapped windows are compared (golden G31c).
        for i in (1..=l - 1).rev() {
            let win = read_left_window(&mut fetch, start, i)?;
            if win.as_slice() == &rev[rev.len() - i..] {
                rev_hom = i;
                rev_seq = Some(win);
                break;
            }
        }
        // Adjudication (:1534-1540): forward wins ties; reverse only on a
        // strictly longer reverse hit.
        if for_hom > 0 || rev_hom > 0 {
            is_mh = true;
            if for_hom >= rev_hom {
                sequence.extend_from_slice(for_seq.as_deref().unwrap_or(&[]));
            } else {
                let mut prepended = rev_seq.unwrap_or_default();
                prepended.extend_from_slice(&sequence);
                sequence = prepended;
            }
        }
    }

    // --- Key construction and caps (:1641-1730) --------------------------
    // key4 arithmetic uses the UNCAPPED L (`key_1` local, :1655/:1702).
    let key1 = l.min(5);
    if !is_del && is_mh {
        // SPMG computes {key1}:Ins:M:{key4} but never writes it into the
        // ID83 matrix (iloc[:83], MMG:3738) — explicit structured skip.
        return Ok(Indel83Outcome::InsMicrohomologyNoChannel);
    }
    let key4 = if l == 1 {
        // :1673-1679 (Del) / :1718-1725 (Ins): len(sequence) - 1, cap 5.
        (sequence.len() - 1).min(5)
    } else if !is_mh {
        // Repeat class (:1653-1659 / :1699-1705): copies - 1 on the raw
        // L, floored, cap 5. Del R:0 = "no tandem context"; Ins R:0 is
        // additionally the DEFAULT for non-repetitive insertions (F1
        // asymmetry note, memo §3.6d).
        sequence.len() / l - 1
    } else {
        // Microhomology class (:1662-1670 / :1707-1716): MH bases, cap 5.
        // >= 1 by branch entry (no M:0 row exists).
        (sequence.len() - l).min(5)
    };
    let key3: u8 = if l == 1 {
        // 1 bp classes key off the deleted/inserted base itself: {C,G} ->
        // "C", {A,T} -> "T" (:1681-1685 / :1726-1730).
        let b = unit[0];
        if b == b'C' || b == b'G' { b'C' } else { b'T' }
    } else if !is_mh {
        b'R'
    } else {
        b'M'
    };

    // --- Table index ------------------------------------------------------
    let idx = if l == 1 {
        // Blocks: 1:Del:{C,T} at 0/6; 1:Ins:{C,T} at 12/18.
        let base = if is_del { 0 } else { 12 };
        let class = if key3 == b'C' { 0 } else { 6 };
        base + class + key4
    } else if !is_mh {
        // R blocks: Del at 24, Ins at 48, (key1 - 2) * 6 within.
        let base = if is_del { 24 } else { 48 };
        base + (key1 - 2) * 6 + key4
    } else {
        // Del M rows are the triangular tail: key1 k owns k-1 rows.
        72 + (key1 - 2) * (key1 - 1) / 2 + (key4 - 1)
    };
    debug_assert_eq!(
        ID83_CHANNELS
            .iter()
            .position(|&s| s == label_of(key1, is_del, key3, key4).as_str())
            .expect("constructed label must exist in ID83_CHANNELS"),
        idx,
        "index arithmetic desynchronised from the table"
    );
    Ok(Indel83Outcome::Channel(idx))
}

/// Rebuild the canonical label for a classified event (debug cross-check
/// of the index arithmetic against the static table).
#[cfg(debug_assertions)]
fn label_of(key1: usize, is_del: bool, key3: u8, key4: usize) -> String {
    format!(
        "{key1}:{}:{}:{key4}",
        if is_del { "Del" } else { "Ins" },
        key3 as char
    )
}

/// Slice-backed convenience: `seq` is the whole chromosome (any bytes;
/// uppercase ACGT or N in production). Fetch errors follow the
/// `genome::range` bounds conventions (i = 1-based start, j = size when
/// the start is out of range, else the requested 1-based last base).
pub fn assign_indel83_slice(
    seq: &[u8],
    pos0: u64,
    ref_: &[u8],
    alt: &[u8],
) -> Result<Indel83Outcome, MsError> {
    let chrom_len = seq.len();
    assign_indel83(
        |start0, len| {
            if start0 >= chrom_len {
                return Err(MsError::new(
                    "bounds",
                    format!(
                        "position {} outside chromosome slice of length {chrom_len}",
                        start0 + 1
                    ),
                )
                .with_i(start0 as i64 + 1)
                .with_j(chrom_len as i64));
            }
            let end = start0.checked_add(len).ok_or_else(|| {
                MsError::new("bounds", "window end overflows the addressable range")
                    .with_i(start0 as i64 + 1)
                    .with_j(i64::MAX)
            })?;
            if end > chrom_len {
                return Err(MsError::new(
                    "bounds",
                    format!(
                        "window ends at {end}, past chromosome slice of length {chrom_len}"
                    ),
                )
                .with_i(start0 as i64 + 1)
                .with_j(end as i64));
            }
            Ok(seq[start0..end].to_vec())
        },
        chrom_len,
        pos0,
        ref_,
        alt,
    )
}

/// Genome-backed convenience: classifies against a [`TwoBitGenome`]
/// chromosome through [`TwoBitGenome::range`]. This is the shape the
/// tally assembly layer calls per `RoutedEvent::Indel` (wiring unit
/// pending); unknown chromosomes surface as `argument` errors.
pub fn assign_indel83_genome(
    genome: &mut TwoBitGenome<'_>,
    chrom: &str,
    pos0: u64,
    ref_: &[u8],
    alt: &[u8],
) -> Result<Indel83Outcome, MsError> {
    let chrom_len = genome.chrom_size(chrom)?;
    assign_indel83(
        |start0, len| genome.range(chrom, start0, len),
        chrom_len,
        pos0,
        ref_,
        alt,
    )
}

/// Canonical label of an ID83 channel index.
///
/// Bounds-checked per FFI contract 4 (structured `"bounds"` error with
/// `i` = 1-based index and `j` = table length, never a panic).
#[inline]
pub fn indel83_label(idx: usize) -> Result<&'static str, MsError> {
    channel_label(&ID83_CHANNELS, idx)
}

/// SPMG's ID TSB ambiguity predicate (:1789-1798), provided for the future
/// ID415 family (memo §3.7); ID83 itself never consumes it.
///
/// Returns `true` iff the TSB key must be prefixed `"Q:"`: the accumulated
/// repeat/MH `sequence` is NEITHER all-pyrimidine (`^[CT]*$`) NOR
/// all-purine (`^[GA]*$`) AND the strand bias is known (`bias != "N"`).
/// Direction per the audit-04 erratum (memo §1.4-1): homogeneous sequences
/// resolve to the real (first-base-flipped) bias; mixed sequences cannot.
#[inline]
#[must_use]
pub fn q_predicate(sequence: &[u8], bias: Strand) -> bool {
    if bias == Strand::None {
        return false;
    }
    let all_ct = sequence.iter().all(|&b| b == b'C' || b == b'T');
    let all_ga = sequence.iter().all(|&b| b == b'G' || b == b'A');
    !(all_ct || all_ga)
}
