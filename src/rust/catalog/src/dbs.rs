//! DBS78 doublet-substitution channel arithmetic (U-M1s-07).
//!
//! Semantic source of truth: SigProfilerMatrixGenerator (SPMG), audited at
//! `docs/research/04` section 1 and pinned label-for-label by
//! `data-raw/build_channels.R` (`.dbs_refs` / `.dbs_fold_keep`) into the
//! generated `DBS78_CHANNELS` table:
//!
//!   * a doublet substitution is two SNVs at distance exactly 1 (SPMG
//!     `dinuc_sub == 1`); candidacy is decided by [`adjacent_snv_pair`],
//!     the REF-vs-genome check staying with the assembly layer;
//!   * the reference dinucleotide is canonicalized against SPMG's pinned
//!     10-ref set {AC, AT, CC, CG, CT, GC, TA, TC, TG, TT}; a ref outside
//!     the set flips the whole pair (revcompl of ref and alt, SPMG
//!     `:673-694`). This is a source constant, not a derivable rule: the
//!     mixed revcompl pairs canonicalize to AC (not GT) and TG (not CA),
//!     although CA is pyrimidine-start (U-M0-05 devlog conclusion);
//!   * Q-type refs (self-revcompl AT/CG/GC/TA) fold each revcompl-equivalent
//!     alt pair {NZ, revcompl(NZ)} onto the SPMG-pinned kept member
//!     (keep sets below); self-revcompl alts are kept verbatim. There is no
//!     consistent algorithmic fold rule (min/max tie-breaks both fail
//!     upstream; U-M0-05 devlog) — the keep sets are constants, anchored by
//!     the table-bijection and pair-coverage properties in `tests/dbs.rs`;
//!   * canonical order is ASCII lexicographic of the `XY>NZ` label.
//!
//! Index layout: ten ref blocks in ASCII order with sizes 9 (non-Q refs:
//! AC, CC, CT, TC, TG, TT) and 6 (Q refs: AT, CG, GC, TA); the channel
//! within a block is the ASCII rank of the (folded) alt in the ref's alt
//! set. Every input is validated: a non-ACGT byte or an unchanged doublet
//! position (`ref[k] == alt[k]`) is a structured
//! [`MsError`](msuiter_engine::MsError) with topic `"argument"`, never a
//! panic. Error `i` conventions (1-based): non-ACGT bytes carry the
//! offending 4-byte input position (ref2[0]=1, ref2[1]=2, alt2[0]=3,
//! alt2[1]=4); unchanged positions carry the 1-based doublet site (1 or 2).

use msuiter_engine::MsError;

use crate::channels::DBS78_CHANNELS;
use crate::sbs::channel_label;

/// Canonical reference dinucleotides in DBS78 ASCII order (documentation
/// mirror of the `canonical_ref` arms and the `DBS_OFFSETS` blocks; the
/// label itself lives in the generated `DBS78_CHANNELS` table).
static DBS_REFS: [&[u8; 2]; 10] = [
    b"AC", b"AT", b"CC", b"CG", b"CT", b"GC", b"TA", b"TC", b"TG", b"TT",
];

/// Block offsets of `DBS_REFS` in `DBS78_CHANNELS` (ASCII order; sizes 9
/// for the non-Q refs, 6 for the Q refs).
static DBS_OFFSETS: [usize; 10] = [0, 9, 15, 24, 30, 39, 45, 51, 60, 69];

/// Alt sets per canonical ref, ASCII-sorted: all nine changed alts for the
/// non-Q refs; the six SPMG-pinned folded alts for the Q refs (keep set
/// plus self-revcompl alts; `build_channels.R` `.dbs_fold_keep`).
static DBS_ALTS: [&[&[u8; 2]]; 10] = [
    // AC
    &[b"CA", b"CG", b"CT", b"GA", b"GG", b"GT", b"TA", b"TG", b"TT"],
    // AT (Q)
    &[b"CA", b"CC", b"CG", b"GA", b"GC", b"TA"],
    // CC
    &[b"AA", b"AG", b"AT", b"GA", b"GG", b"GT", b"TA", b"TG", b"TT"],
    // CG (Q)
    &[b"AT", b"GC", b"GT", b"TA", b"TC", b"TT"],
    // CT
    &[b"AA", b"AC", b"AG", b"GA", b"GC", b"GG", b"TA", b"TC", b"TG"],
    // GC (Q)
    &[b"AA", b"AG", b"AT", b"CA", b"CG", b"TA"],
    // TA (Q)
    &[b"AT", b"CG", b"CT", b"GC", b"GG", b"GT"],
    // TC
    &[b"AA", b"AG", b"AT", b"CA", b"CG", b"CT", b"GA", b"GG", b"GT"],
    // TG
    &[b"AA", b"AC", b"AT", b"CA", b"CC", b"CT", b"GA", b"GC", b"GT"],
    // TT
    &[b"AA", b"AC", b"AG", b"CA", b"CC", b"CG", b"GA", b"GC", b"GG"],
];

/// base4 code of an allele byte: A:0, C:1, G:2, T:3.
#[inline]
fn base4(b: u8) -> Option<usize> {
    match b {
        b'A' => Some(0),
        b'C' => Some(1),
        b'G' => Some(2),
        b'T' => Some(3),
        _ => None,
    }
}

/// Reverse complement of a validated dinucleotide.
#[inline]
fn revcompl2(d: &[u8; 2]) -> [u8; 2] {
    [comp(d[1]), comp(d[0])]
}

/// Complement of a validated ACGT byte.
#[inline]
fn comp(b: u8) -> u8 {
    match b {
        b'A' => b'T',
        b'C' => b'G',
        b'G' => b'C',
        _ => b'A', // b'T'
    }
}

/// Canonical form of a reference dinucleotide: `(block index, flipped)`.
///
/// `flipped` is set iff the input ref is outside the canonical set (then
/// the alt must be reverse-complemented too). All 16 ACGT dinucleotides
/// are covered: the 10 canonical refs and the 6 mirrors AA/AG/CA/GA/GG/GT,
/// whose revcompl is always the canonical member of their pair.
#[inline]
fn canonical_ref(ref2: &[u8; 2]) -> Option<(usize, bool)> {
    if let Some(i) = DBS_REFS.iter().position(|&r| r == ref2) {
        return Some((i, false));
    }
    let rc = revcompl2(ref2);
    let i = DBS_REFS.iter().position(|&r| *r == rc)?;
    Some((i, true))
}

/// Validate both dinucleotide bytes; `slot` 0 selects the ref (positions
/// 1-2), 1 the alt (positions 3-4) of the 1-based error convention.
fn validate_dinuc(d: &[u8; 2], slot: usize) -> Result<(), MsError> {
    for (k, &byte) in d.iter().enumerate() {
        if base4(byte).is_none() {
            return Err(MsError::new(
                "argument",
                format!(
                    "invalid allele byte 0x{byte:02X} at 1-based dinucleotide position {}/4 (expected A, C, G or T)",
                    slot * 2 + k + 1
                ),
            )
            .with_i((slot * 2 + k + 1) as i64));
        }
    }
    Ok(())
}

/// DBS78 channel index of a doublet substitution.
///
/// `ref2`/`alt2` are the two adjacent reference/alternate bases. Both
/// positions must change (`ref2[k] != alt2[k]` for k = 0, 1) and every
/// byte must be uppercase ACGT; violations are structured `argument`
/// errors. The channel is the canonical (pyrimidine/SPMG-pinned oriented)
/// label's position in `DBS78_CHANNELS`: purine-mirrored inputs and Q-type
/// (self-revcompl ref) alt pairs fold onto one channel each, so both
/// strands of the same doublet mutation land together.
#[inline]
pub fn assign_dbs78(ref2: &[u8; 2], alt2: &[u8; 2]) -> Result<usize, MsError> {
    validate_dinuc(ref2, 0)?;
    validate_dinuc(alt2, 1)?;
    for k in 0..2 {
        if ref2[k] == alt2[k] {
            return Err(MsError::new(
                "argument",
                format!(
                    "doublet position {} is unchanged (ref and alt both {}); not a doublet substitution",
                    k + 1,
                    ref2[k] as char
                ),
            )
            .with_i(k as i64 + 1));
        }
    }
    let (block, flipped) = canonical_ref(ref2)
        .ok_or_else(|| MsError::new("argument", "unreachable: canonical_ref covers all ACGT (internal)"))?;
    let mut alt = if flipped { revcompl2(alt2) } else { *alt2 };
    // Q-type refs (blocks 1/3/5/6 = AT/CG/GC/TA) fold the alt: a dropped
    // member of a revcompl pair maps onto the pinned kept member.
    if matches!(block, 1 | 3 | 5 | 6) {
        let kept = DBS_ALTS[block].iter().any(|&a| *a == alt);
        if !kept {
            alt = revcompl2(&alt);
        }
    }
    let rank = DBS_ALTS[block]
        .iter()
        .position(|&a| *a == alt)
        .ok_or_else(|| {
            MsError::new(
                "argument",
                format!(
                    "alt {}{} has no DBS78 channel for ref {}{}",
                    alt[0] as char,
                    alt[1] as char,
                    ref2[0] as char,
                    ref2[1] as char
                ),
            )
        })?;
    Ok(DBS_OFFSETS[block] + rank)
}

/// Label of a DBS78 channel in canonical order.
///
/// Bounds-checked per FFI contract 4 (structured `"bounds"` error with
/// `i` = 1-based index and `j` = table length, never a panic).
#[inline]
pub fn dbs78_label(idx: usize) -> Result<&'static str, MsError> {
    channel_label(&DBS78_CHANNELS, idx)
}

/// DBS candidacy of two single-base records: `pos2 == pos1 + 1` (SPMG
/// `dinuc_sub == 1`) and all four allele bytes uppercase ACGT. Returns the
/// concatenated `(ref2, alt2)` dinucleotides feeding [`assign_dbs78`];
/// `None` means "not a DBS candidate" (wrong distance or invalid allele —
/// callers route the record(s) explicitly). The REF-vs-reference-genome
/// check is the assembly layer's job and stays upstream.
#[inline]
pub fn adjacent_snv_pair(
    pos1: u64,
    ref1: u8,
    alt1: u8,
    pos2: u64,
    ref2b: u8,
    alt2b: u8,
) -> Option<([u8; 2], [u8; 2])> {
    if pos2 != pos1 + 1 {
        return None;
    }
    for &b in [&ref1, &alt1, &ref2b, &alt2b] {
        base4(b)?;
    }
    Some(([ref1, ref2b], [alt1, alt2b]))
}
