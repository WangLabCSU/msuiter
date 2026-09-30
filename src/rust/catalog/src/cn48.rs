//! CN48 copy-number channel arithmetic (U-M1c-03).
//!
//! Semantic source of truth: SigProfilerMatrixGenerator (SPMG)
//! `CNVMatrixGenerator.py`, function `annotateSegFile`, audited
//! line-by-line at upstream master `edccbea6` (tag v1.3.6 `4923d61`).
//! Every behaviour consumed here — the feature list (:20-69 with
//! `assert len(features) == 48` at :71), the total-copy-number class
//! mapping (:76-183), the LOH status rule (:193-295), the segment
//! length (:306-337), the size binning (:339-373) and the channel
//! construction with its per-segment increment (:376-383) — is
//! byte-identical between the two revisions. The only differing hunk
//! (master :268, which also removes two v1.3.6 debug-print lines at
//! :272-273) touches the FACETS-input-only LOH branch (`t == 1
//! or ...` added for `lcn.em` semantics), which this module does not
//! consume: the typed input below follows the allele-based zero-test
//! rule (:196-204) shared verbatim by the ASCAT/ABSOLUTE/BATTENBERG/
//! PURPLE branches in both revisions. Line references are master.
//!
//! # Channel table
//!
//! `CN48_CHANNELS` is the upstream `features` list (:20-69) verbatim:
//! 48 = 3 homdel size bins (:17) + 5 LOH total-CN classes x 5 size
//! bins + 4 het classes x 5 size bins. The canonical order is the
//! upstream list order, NOT a global ASCII sort (lexicographically
//! `1:LOH:10Mb-40Mb` sorts before `1:LOH:1Mb-10Mb`, yet holds index 6
//! AFTER index 5 in the upstream list). The
//! order is double-pinned to the COSMIC v3.6 reference matrix
//! `COSMIC_v3.6_CN_GRCh37.txt` (SigProfilerAssignment mirror, BSD-2;
//! rows 1..48 verified against the SPMG list 2026-09-28, byte-equal).
//! Syntax: `<totalCN>:<LOH|het|homdel>:<segment-size>`.
//!
//! The table lives here as a static constant and is deliberately NOT
//! wired into the generated `channels.rs` / `data-raw/build_channels.R`
//! pipeline: the CN48/SV32 label tables are build-INDEPENDENT (the
//! arithmetic below never reads a genome), whereas the COSMIC CN/SV
//! reference-signature matrices are build-dependent (research/05 §2:
//! CN exists for GRCh37 only). Keeping the two concerns separate lets a
//! later reference-matrix unit declare per-build availability without
//! touching channel semantics; `build_channels.R` must not grow a CN/SV
//! section until that unit decides otherwise (memo note, U-M1c-03).
//!
//! # Literature lineage and the variant-space decision
//!
//! CN48 operationalises the COSMIC copy-number signature space derived
//! from the PCAWG/TCGA copy-number signature work (Steele et al.,
//! Nature 606:984-991, 2022, doi:10.1038/s41586-022-04738-6; per
//! docs/research/08 fact-check row 7). Alternative CN feature spaces
//! exist — CN40 (Wang), the Macintyre 36-component space with BoZp/BoZd
//! breakage (breakend) features, Drews features, CN176 (Tao);
//! CAPABILITY-MATRIX L-B pins msuiter v0.2 to CN48. Consequence: the
//! Macintyre-style breakend machinery is OUT OF SCOPE — a verified CN48
//! channel is a pure function of (zygosity, total CN, segment size),
//! so the segment input needs NO prev/next adjacency or
//! chromosome-edge flags. The U-M1c-03 brief's BoZ/adjacency design
//! question is resolved as "not part of CN48".
//!
//! # Upstream arithmetic, replicated exactly
//!
//! * Total-copy-number class (:76-90; the :76 comment names the bands
//!   `{del=0-1; neut=2; gain=3-4; amp=5-8; amp+=9+}`): `tcn == 2` →
//!   `"2"`, `tcn in {0,1}` → `"1"`, `tcn in {3,4}` → `"3-4"`,
//!   `5 <= tcn <= 8` → `"5-8"`, else `"9+"`. TCN 0 classes as `"1"`
//!   upstream, but the homdel branch overrides the channel prefix with
//!   the literal `"0"` (:379-382), so `"1:homdel:*"` is never
//!   constructed. The mapping is identical in all eight input formats
//!   (:79-183); this module takes it as the canonical rule.
//! * Zygosity (:196-204, ASCAT branch; ABSOLUTE :234-242, BATTENBERG
//!   :273-281 and PURPLE :282-295 are the same zero-test): `t == 0` →
//!   `homdel`, `acn == 0 or bcn == 0` → `LOH`, else `het`. Upstream is
//!   order-insensitive (it only sums and zero-tests the allele pair),
//!   so the typed pair carries the smaller allele first; the contract
//!   `minor_cn <= major_cn` is a hardening that never changes the
//!   classification of any contract-abiding input. Under that
//!   convention the rule collapses to: both zero → homdel, `minor_cn
//!   == 0` → LOH, else het.
//! * Segment length (:306-337): `(end - start) / 1000000` megabases —
//!   the raw difference, NOT the closed-interval `end - start + 1`.
//!   A zero length is admissible upstream (the bin lower edge is
//!   `-0.01` Mb, :347/:357, admitting `end == start` and tiny negative
//!   data slop); `u64` lengths reproduce every admissible
//!   non-negative case, so [`CnSegment::seg_len_bp`] of 0 is VALID and
//!   counts into `0-100kb` (deliberate: the brief's suggested
//!   non-zero validation would deviate from upstream).
//! * Size bins (:343-373), in Mb, lower-exclusive / upper-INCLUSIVE:
//!   homdel `(-0.01, 0.1]` → `0-100kb`, `(0.1, 1]` → `100kb-1Mb`,
//!   else `>1Mb`; non-homdel additionally `(1, 10]` → `1Mb-10Mb` and
//!   `(10, 40]` → `10Mb-40Mb`, else `>40Mb`. For integer bp lengths
//!   the float comparisons are exactly the integer comparisons at
//!   100_000 / 1_000_000 / 10_000_000 / 40_000_000: each boundary
//!   divided by 1e6 is an exact decimal whose IEEE-754 nearest double
//!   equals the corresponding literal's double (`100_000/1e6` → the
//!   `0.1` double; `1e6/1e6` = 1.0; `1e7/1e6` = 10.0; `4e7/1e6` =
//!   40.0), while any neighbouring integer sits ≥ 1e-6 from the
//!   boundary value — far beyond double resolution near these
//!   magnitudes — so it rounds strictly to one side. `assign_cn48`
//!   therefore compares `seg_len_bp` against integer edges and is
//!   float-free (D11: bit-identical, not approximately equal).
//! * Tally (:376-383): each segment counts 1 into its channel — no
//!   length weighting.
//!
//! # Totality and the unreachable `1:het` row
//!
//! Every (total-CN class, zygosity, size bin) triple reachable from a
//! validated [`CnSegment`] exists in the table: het requires
//! `minor_cn >= 1`, hence `tcn >= 2`, hence one of the four het classes;
//! `tcn == 1` forces `minor_cn == 0` (the pair is ordered), which is
//! LOH — so the `1:het` row the combinatorics would predict does not
//! exist upstream and is never constructed here. [`assign_cn48`] is
//! therefore total over its validated domain (no skip outcomes; the
//! ID83 [`Indel83Outcome`] precedent does not recur).

use msuiter_engine::MsError;

use crate::sbs::channel_label;

/// The canonical CN48 channel table: SPMG `features` verbatim
/// (CNVMatrixGenerator.py:20-69, `assert` :71), byte-equal to
/// `COSMIC_v3.6_CN_GRCh37.txt` rows 1..48. See the module docs for the
/// generation rationale and the block-boundary index map.
#[rustfmt::skip]
pub static CN48_CHANNELS: [&str; 48] = [
    // Homdel: 3 size bins only (:20-23; `hom_del_class` :17)
    "0:homdel:0-100kb", "0:homdel:100kb-1Mb", "0:homdel:>1Mb",
    // LOH: total-CN classes {1, 2, 3-4, 5-8, 9+} x 5 size bins (:24-48;
    // the :76-77 comment names the bands {del=0-1; neut=2; gain=3-4;
    // amp=5-8; amp+=9+})
    "1:LOH:0-100kb", "1:LOH:100kb-1Mb", "1:LOH:1Mb-10Mb", "1:LOH:10Mb-40Mb", "1:LOH:>40Mb",
    "2:LOH:0-100kb", "2:LOH:100kb-1Mb", "2:LOH:1Mb-10Mb", "2:LOH:10Mb-40Mb", "2:LOH:>40Mb",
    "3-4:LOH:0-100kb", "3-4:LOH:100kb-1Mb", "3-4:LOH:1Mb-10Mb", "3-4:LOH:10Mb-40Mb", "3-4:LOH:>40Mb",
    "5-8:LOH:0-100kb", "5-8:LOH:100kb-1Mb", "5-8:LOH:1Mb-10Mb", "5-8:LOH:10Mb-40Mb", "5-8:LOH:>40Mb",
    "9+:LOH:0-100kb", "9+:LOH:100kb-1Mb", "9+:LOH:1Mb-10Mb", "9+:LOH:10Mb-40Mb", "9+:LOH:>40Mb",
    // Het: total-CN classes {2, 3-4, 5-8, 9+} x 5 size bins (:49-68).
    // No "1:het" row exists — unreachably so (module docs, totality).
    "2:het:0-100kb", "2:het:100kb-1Mb", "2:het:1Mb-10Mb", "2:het:10Mb-40Mb", "2:het:>40Mb",
    "3-4:het:0-100kb", "3-4:het:100kb-1Mb", "3-4:het:1Mb-10Mb", "3-4:het:10Mb-40Mb", "3-4:het:>40Mb",
    "5-8:het:0-100kb", "5-8:het:100kb-1Mb", "5-8:het:1Mb-10Mb", "5-8:het:10Mb-40Mb", "5-8:het:>40Mb",
    "9+:het:0-100kb", "9+:het:100kb-1Mb", "9+:het:1Mb-10Mb", "9+:het:10Mb-40Mb", "9+:het:>40Mb",
];

/// Minimal copy-number segment record, exactly the quantities the
/// verified CN48 channel reads off a segmentation file (module docs,
/// "Minimal input representation").
///
/// This is the structured input the future R segmentation layer
/// (`cnv_features.R` typed IR, CAPABILITY-MATRIX L-B) will build from
/// caller-specific formats (ASCAT/Battenberg/PURPLE/... columns,
/// CNVMatrixGenerator.py:75-232); those per-caller column dialects are
/// the wiring unit's scope, not this module's.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CnSegment {
    /// Segment length in bp: `end - start`, NOT `end - start + 1`
    /// (upstream divides the raw difference by 1e6, :310-329). Zero is
    /// admissible and counts into `0-100kb`, like upstream's `-0.01` Mb
    /// lower bin edge (:347/:357).
    pub seg_len_bp: u64,
    /// Minor-allele copy number. Contract: `minor_cn <= major_cn`
    /// (violations are structured `argument` errors). Under the
    /// ordering the upstream zero-test (:196-204) collapses to
    /// `minor_cn == 0` ⇒ LOH.
    pub minor_cn: u8,
    /// Major-allele copy number.
    pub major_cn: u8,
}

/// Total-copy-number band, :76-90 (`{del=0-1; neut=2; gain=3-4;
/// amp=5-8; amp+=9+}` at :76-77; identical mapping :79-183 in all
/// eight input formats).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TcnClass {
    /// tcn in {0, 1} — labelled "1" upstream; tcn = 0 is overridden by
    /// the homdel prefix at :379-382.
    Cn1,
    /// tcn == 2 (copy-neutral).
    Cn2,
    /// tcn in {3, 4}.
    Cn34,
    /// tcn in 5..=8.
    Cn58,
    /// tcn >= 9.
    Cn9Plus,
}

#[inline]
fn tcn_class(tcn: u16) -> TcnClass {
    match tcn {
        2 => TcnClass::Cn2,
        0 | 1 => TcnClass::Cn1,
        3 | 4 => TcnClass::Cn34,
        5..=8 => TcnClass::Cn58,
        _ => TcnClass::Cn9Plus,
    }
}

impl TcnClass {
    /// The canonical label fragment (:76-90 channel strings).
    #[inline]
    fn label(self) -> &'static str {
        match self {
            TcnClass::Cn1 => "1",
            TcnClass::Cn2 => "2",
            TcnClass::Cn34 => "3-4",
            TcnClass::Cn58 => "5-8",
            TcnClass::Cn9Plus => "9+",
        }
    }

    /// Row index within the five LOH blocks (0-based); the het blocks
    /// use `row() - 1` (their first class is tcn = 2).
    #[inline]
    fn row(self) -> usize {
        match self {
            TcnClass::Cn1 => 0,
            TcnClass::Cn2 => 1,
            TcnClass::Cn34 => 2,
            TcnClass::Cn58 => 3,
            TcnClass::Cn9Plus => 4,
        }
    }
}

/// Size-bin labels, exactly the `size` strings upstream writes
/// (:348-371 for the 5-bin non-homdel variant).
///
/// Deliberately NOT `#[rustfmt::skip]`-padded one-per-line: these are
/// 5/3-item lookup fragments, and the channel table above carries the
/// canonical layout. The homdel variant (:346-355) shares its first two
/// labels but tops out at `>1Mb` — a third generic label `1Mb-10Mb`
/// would be wrong there, so the arrays are separate.
const SIZE_LABELS: [&str; 5] = ["0-100kb", "100kb-1Mb", "1Mb-10Mb", "10Mb-40Mb", ">40Mb"];
const SIZE_LABELS_HOMDEL: [&str; 3] = ["0-100kb", "100kb-1Mb", ">1Mb"];

/// Integer size-bin edges in bp, the exact integer reproductions of the
/// upstream float binning (module docs, "Upstream arithmetic"; bins are
/// lower-exclusive / upper-inclusive, :343-373).
const BIN_EDGES: [u64; 4] = [100_000, 1_000_000, 10_000_000, 40_000_000];

/// Size-bin index (0-based, ascending). `homdel` selects the 3-bin
/// variant (:346-355: `(−0.01,0.1]`, `(0.1,1]`, else `>1Mb` — no
/// 10/40 Mb splits); non-homdel is the 5-bin variant (:356-371).
#[inline]
fn size_bin(len_bp: u64, homdel: bool) -> usize {
    let edges: &[u64] = if homdel {
        &BIN_EDGES[..2]
    } else {
        &BIN_EDGES
    };
    // First edge strictly greater than len_bp wins; lower-exclusive /
    // upper-inclusive means `<=` (len == edge belongs to the lower bin).
    // Falling past every edge is the else branch (:353-355 homdel
    // ">1Mb" / :369-371 non-homdel ">40Mb").
    edges.iter().position(|&e| len_bp <= e).unwrap_or(edges.len())
}

/// Rebuild the canonical label for a classified segment (debug
/// cross-check of the index arithmetic against the static table).
///
/// Deliberately NOT `#[cfg(debug_assertions)]`: `debug_assert_eq!`
/// type-checks its body in release profiles too, so gating this helper
/// broke release builds in the ID83 audit (U-M1c-01 P0-2). It stays
/// resident as the construction-correctness sentinel; in release the
/// assert's branch is runtime-false and LLVM discards it.
fn label_of(tcn: u16, minor: u8, bin: usize) -> String {
    if tcn == 0 {
        format!("0:homdel:{}", SIZE_LABELS_HOMDEL[bin])
    } else if minor == 0 {
        format!("{}:LOH:{}", tcn_class(tcn).label(), SIZE_LABELS[bin])
    } else {
        format!("{}:het:{}", tcn_class(tcn).label(), SIZE_LABELS[bin])
    }
}

/// CN48 channel of one copy-number segment.
///
/// Input domain: [`CnSegment`] with `minor_cn <= major_cn` (violations
/// are structured `argument` errors; the record itself carries no
/// genomic position, so — unlike the sbs/indel83 context errors — no
/// `i`/`j` positional payload is attached; the assembly layer adds
/// record positions at ledger time). On success returns the 0-based
/// [`CN48_CHANNELS`] index; the function is total over the validated
/// domain (module docs, totality) and counts each segment as 1, like
/// upstream's `nmf_matrix.at[channel, sample] += 1` (:376-383).
///
/// # Errors
///
/// [`MsError`] topic `"argument"` when `minor_cn > major_cn`.
pub fn assign_cn48(seg: &CnSegment) -> Result<usize, MsError> {
    if seg.minor_cn > seg.major_cn {
        return Err(MsError::new(
            "argument",
            format!(
                "minor copy number {} exceeds major copy number {} (CnSegment must be ordered minor <= major; upstream's allele zero-test is order-insensitive, :196-204)",
                seg.minor_cn, seg.major_cn
            ),
        ));
    }
    // u16 sum: u8 + u8 <= 510, no overflow; upstream sums the allele
    // pair (e.g. ASCAT `tcn = acn + bcn`, :106).
    let tcn = u16::from(seg.minor_cn) + u16::from(seg.major_cn);
    let homdel = tcn == 0;
    let bin = size_bin(seg.seg_len_bp, homdel);
    let idx = if homdel {
        // "0:homdel:{size}" (:379-380): the homdel prefix is the literal
        // "0", overriding the TCN class.
        bin
    } else if seg.minor_cn == 0 {
        // LOH blocks: 5 rows x 5 bins starting at index 3 (:24-48).
        3 + tcn_class(tcn).row() * 5 + bin
    } else {
        // het blocks: 4 rows x 5 bins starting at index 28 (:49-68);
        // row >= 1 because het implies minor_cn >= 1 implies tcn >= 2.
        28 + (tcn_class(tcn).row() - 1) * 5 + bin
    };
    debug_assert_eq!(
        CN48_CHANNELS
            .iter()
            .position(|&s| s == label_of(tcn, seg.minor_cn, bin))
            .expect("constructed label must exist in CN48_CHANNELS"),
        idx,
        "index arithmetic desynchronised from the table"
    );
    Ok(idx)
}

/// Canonical label of a CN48 channel index.
///
/// Bounds-checked per FFI contract 4 (structured `"bounds"` error with
/// `i` = 1-based index and `j` = table length, never a panic).
#[inline]
pub fn cn48_label(idx: usize) -> Result<&'static str, MsError> {
    channel_label(&CN48_CHANNELS, idx)
}
