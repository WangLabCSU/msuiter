//! SV32 structural-variant channel arithmetic (U-M1c-04).
//!
//! Semantic source of truth: SigProfilerMatrixGenerator (SPMG)
//! `SVMatrixGenerator.py` — `processBEDPE` (:1037-1191) and
//! `tsv2matrix` (:1193-1257) — audited line-by-line at upstream master
//! `edccbea6` (tag v1.3.6 `4923d61`). Every behaviour consumed here —
//! the svclass short-name mapping (:1228-1233), the size binning
//! (:1138-1161), the <1 kb drop (:1183-1189), the clustered prefix
//! (:1246-1250), the 32-feature list (:1194-1226) and the per-event
//! increment (:1255) — is byte-identical between the two revisions.
//! The only file diff is the deprecated `np.in1d` → `np.isin` rename
//! in the kat-region clustered propagation (:923/:925), whose
//! semantics numpy documents as equivalent. Line references are
//! master.
//!
//! # Channel table
//!
//! `SV32_CHANNELS` is the upstream `features` list (:1194-1226)
//! verbatim: 32 = {clustered, non-clustered} x {del, tds, inv} x 5 size
//! bins (30) + one `clustered_trans` and one `non-clustered_trans`
//! channel. The canonical order is the upstream list order — clustered
//! block (del, tds, inv, trans) first, then the non-clustered mirror.
//! (Here the upstream order happens to coincide with a global ASCII
//! sort; that coincidence must not be relied on — CN48's does not, and
//! the sync tests pin the list positions, not string order.) The order
//! is double-pinned to
//! the COSMIC v3.6 reference matrix `COSMIC_v3.6_SV_GRCh38.txt`
//! (SigProfilerAssignment mirror, BSD-2; rows 1..32 verified against
//! the SPMG list 2026-09-28, byte-equal).
//!
//! As with CN48 (see `crate::cn48`), the table lives here as a static
//! constant and is deliberately NOT wired into the generated
//! `channels.rs` / `data-raw/build_channels.R` pipeline: the SV32
//! labels are build-INDEPENDENT (no genome arithmetic below) while the
//! COSMIC SV reference-signature matrices are build-dependent
//! (research/05 §2: SV exists for GRCh38 only). `build_channels.R`
//! must not grow an SV section until the reference-matrix unit decides
//! otherwise (memo note, U-M1c-04).
//!
//! # Literature lineage
//!
//! SV32 operationalises the PCAWG structural-variation signature
//! channel convention (PCAWG Structural Variation Working Group, Li et
//! al., Nature 578:112-121, 2020, doi:10.1038/s41586-019-1913-9) as
//! encoded by the SigProfiler SV32 matrix and COSMIC v3.4+ reference
//! signatures. The task brief's guess "Li 2020 Nature Communications"
//! resolves to this Nature 2020 paper.
//!
//! # Scope split (what this module deliberately does NOT do)
//!
//! Upstream derives `svclass` from breakpoint strands (:1101-1124:
//! different chromosomes → `translocation`; mixed strands →
//! `inversion`; `(+,+)` → `deletion`; `(-,-)` → `tandem-duplication`)
//! and the clustered flag from kat-region breakpoint clustering
//! (`annotateBedpe` :797-930: sort breakpoints per chromosome, run
//! `exactPcf` on log neighbour distances with `kmin = 10` (:864), flag
//! segments below `thresh_dist`, propagate flags to every breakpoint
//! inside a flagged region, :918-926). Both derivations belong to the
//! future BEDPE/R wiring unit; this module consumes their RESULTS as a
//! typed record — the same split as CN48 consuming caller-side
//! ASCAT/PURPLE segmentation output instead of parsing segment files.
//! That is why [`SvRecord`] carries a `clustered: bool` beyond the
//! brief's three-field sketch: without it only 2 of the 32 channels
//! would be addressable.
//!
//! # Size bins: exact integer reproduction of the float arithmetic
//!
//! Upstream bins `l = |start1 - start2| / 1000000` Mb against the
//! literals 0.01, 0.1, 1 and 10 (:1142-1157): `l <= 0.010` →
//! `1-10Kb`; `(0.01, 0.1]` → `10-100Kb`; `(0.1, 1]` → `100Kb-1Mb`;
//! `(1, 10]` → `1Mb-10Mb`; else `>10Mb` — lower-exclusive,
//! upper-INCLUSIVE. For integer bp sizes the float comparisons are
//! exactly the integer comparisons at 10_000 / 100_000 / 1_000_000 /
//! 10_000_000: each boundary divided by 1e6 is an exact decimal whose
//! IEEE-754 nearest double equals the corresponding literal's double
//! (`10_000/1e6` → the `0.01` double; `100_000/1e6` → `0.1`;
//! `1e6/1e6` = 1.0; `1e7/1e6` = 10.0), while any neighbouring integer
//! sits ≥ 1e-6 from the boundary value — far beyond double resolution
//! near these magnitudes — so it rounds strictly to one side.
//! [`assign_sv32`] therefore compares `size_bp` against integer edges
//! and is float-free (D11: bit-identical, not approximately equal).
//!
//! The first bin's nominal lower edge ("1-10Kb") is NOT the bin
//! predicate: upstream tallies a separate drop rule
//! `svclass != "translocation" and length < 1000` (STRICT comparison,
//! :1184-1189), so an exactly-1000 bp event is counted in `1-10Kb`
//! while a 999 bp event is dropped before tallying. Here the dropped
//! case surfaces explicitly as [`Sv32Outcome::TooShortNoChannel`]
//! (structured ledger skip, A11 — the assembly layer must be able to
//! account for every record; the ID83 `InsMicrohomologyNoChannel`
//! precedent). Translocations are exempt from both the drop and the
//! bins: upstream still records their length but pins `size_bin` to
//! the constant `"0"` (:1158-1161) and the channel string for
//! translocations never contains a bin (:1251-1254), so
//! [`SvRecord::size_bp`] is ignored for
//! [`SvType::Translocation`].

use msuiter_engine::MsError;

use crate::sbs::channel_label;

/// The canonical SV32 channel table: SPMG `features` verbatim
/// (SVMatrixGenerator.py:1194-1226), byte-equal to
/// `COSMIC_v3.6_SV_GRCh38.txt` rows 1..32. Index map: clustered del
/// 0-4, clustered tds 5-9, clustered inv 10-14, clustered trans 15;
/// the non-clustered mirror at +16 (del 16-20, tds 21-25, inv 26-30,
/// trans 31).
#[rustfmt::skip]
pub static SV32_CHANNELS: [&str; 32] = [
    // Clustered del x 5 size bins (:1194-1199)
    "clustered_del_1-10Kb", "clustered_del_10-100Kb", "clustered_del_100Kb-1Mb",
    "clustered_del_1Mb-10Mb", "clustered_del_>10Mb",
    // Clustered tds x 5 (:1200-1205); "tds" = tandem duplication
    "clustered_tds_1-10Kb", "clustered_tds_10-100Kb", "clustered_tds_100Kb-1Mb",
    "clustered_tds_1Mb-10Mb", "clustered_tds_>10Mb",
    // Clustered inv x 5 (:1206-1211)
    "clustered_inv_1-10Kb", "clustered_inv_10-100Kb", "clustered_inv_100Kb-1Mb",
    "clustered_inv_1Mb-10Mb", "clustered_inv_>10Mb",
    // Clustered translocation: no size bin (:1212-1213, :1253-1254)
    "clustered_trans",
    // Non-clustered mirror (:1214-1231), the same 15 channels + trans
    // under the "non-clustered" prefix.
    "non-clustered_del_1-10Kb", "non-clustered_del_10-100Kb", "non-clustered_del_100Kb-1Mb",
    "non-clustered_del_1Mb-10Mb", "non-clustered_del_>10Mb",
    "non-clustered_tds_1-10Kb", "non-clustered_tds_10-100Kb", "non-clustered_tds_100Kb-1Mb",
    "non-clustered_tds_1Mb-10Mb", "non-clustered_tds_>10Mb",
    "non-clustered_inv_1-10Kb", "non-clustered_inv_10-100Kb", "non-clustered_inv_100Kb-1Mb",
    "non-clustered_inv_1Mb-10Mb", "non-clustered_inv_>10Mb",
    "non-clustered_trans",
];

/// Structural-variant class of one rearrangement record.
///
/// Upstream svclass strings and their short channel names
/// (SVMatrixGenerator.py:1228-1233, `svclass_mapping`): the strand-pair
/// derivation :1101-1124 belongs to the BEDPE wiring unit; this enum
/// receives the already-classified result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SvType {
    /// `deletion` → `"del"` — breakpoint strands `(+,+)` (:1117-1119).
    Deletion,
    /// `tandem-duplication` → `"tds"` — strands `(-,-)` (:1120-1122).
    TandemDup,
    /// `inversion` → `"inv"` — mixed strands (:1112-1116).
    Inversion,
    /// `translocation` → `"trans"` — different chromosomes
    /// (:1108-1110); no size bin.
    Translocation,
}

impl SvType {
    /// The `svclass_mapping` short name (:1228-1233).
    #[inline]
    fn short(self) -> &'static str {
        match self {
            SvType::Deletion => "del",
            SvType::TandemDup => "tds",
            SvType::Inversion => "inv",
            SvType::Translocation => "trans",
        }
    }

    /// Block offset within a clustered/non-clustered half (module docs
    /// index map): del 0, tds 5, inv 10; the trans slot sits at 15.
    #[inline]
    fn block(self) -> usize {
        match self {
            SvType::Deletion => 0,
            SvType::TandemDup => 5,
            SvType::Inversion => 10,
            SvType::Translocation => 15,
        }
    }
}

/// Minimal structural-variant record: the quantities the verified SV32
/// channel reads off an annotated BEDPE row (`processBEDPE` +
/// `tsv2matrix`). The BEDPE parsing, strand→svclass derivation and
/// kat-region clustering are the wiring unit's scope (module docs).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SvRecord {
    /// Rearrangement class (upstream `svclass`).
    pub sv_type: SvType,
    /// Intrachromosomal size `|start1 - start2|` in bp (:1139-1141).
    /// IGNORED for [`SvType::Translocation`] (upstream pins that
    /// `size_bin` to `"0"`, :1158-1161, and never bins a
    /// translocation, :1251-1254).
    pub size_bp: u64,
    /// Kat-region clustered flag — the OUTPUT of upstream
    /// `annotateBedpe` (:918-926), consumed at :1246-1250. Computing it
    /// (exactPcf breakpoint clustering) is the wiring unit's scope.
    pub clustered: bool,
}

/// Outcome of SV32 assignment for one record. Mutually exclusive and
/// total (A11: every classified record lands somewhere explicit).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Sv32Outcome {
    /// Counted: the [`SV32_CHANNELS`] table index.
    Channel(usize),
    /// Non-translocation event with `size_bp < 1000`: upstream drops
    /// the row before tallying (:1184-1189). An explicit ledger skip,
    /// not an error — the caller must still be able to account for the
    /// record (translocations of any size are exempt upstream and
    /// never produce this outcome here).
    TooShortNoChannel,
}

/// Integer size-bin upper edges in bp, the exact integer reproductions
/// of the upstream float binning (:1142-1157; module docs proof).
/// Bins are lower-exclusive / upper-inclusive: `size <= edge` keeps the
/// event in the lower bin, so 10_000 bp is the top of `1-10Kb` and
/// 10_001 bp opens `10-100Kb`.
const BIN_EDGES: [u64; 4] = [10_000, 100_000, 1_000_000, 10_000_000];

/// Size-bin labels, exactly the `size` strings upstream writes
/// (:1143-1156). Note the first bin is spelled `1-10Kb` but its
/// predicate upper edge is 10_000 bp INCLUSIVE (and its counted lower
/// edge comes from the strict `< 1000` drop, :1185).
const SIZE_LABELS: [&str; 5] = ["1-10Kb", "10-100Kb", "100Kb-1Mb", "1Mb-10Mb", ">10Mb"];

/// SV32 outcome of one structural-variant record.
///
/// Total over all [`SvRecord`] values — the typed enum erases every
/// upstream error path (unclassifiable strands raise :1125-1131, a
/// foreign `svclass` string would KeyError at :1251; both are
/// unrepresentable here) — so, unlike the `Result`-returning assign
/// functions in this crate, this returns the bare outcome. Clustered
/// and non-clustered rows share the binning and the 1000 bp drop
/// verbatim (:1246-1250 only prefixes the channel name).
pub fn assign_sv32(rec: &SvRecord) -> Sv32Outcome {
    if rec.sv_type == SvType::Translocation {
        // No bin, no drop (:1158-1161, :1184-1189); the clustered flag
        // picks the half (:1246-1250).
        return Sv32Outcome::Channel(if rec.clustered { 15 } else { 31 });
    }
    if rec.size_bp < 1000 {
        // Strict drop rule (:1185: `row.length < 1000`).
        return Sv32Outcome::TooShortNoChannel;
    }
    // ">10Mb" is the upstream else branch (:1154-1156).
    let bin = BIN_EDGES.iter().position(|&e| rec.size_bp <= e).unwrap_or(4);
    let half = if rec.clustered { 0 } else { 16 };
    let idx = half + rec.sv_type.block() + bin;
    debug_assert_eq!(
        SV32_CHANNELS
            .iter()
            .position(|&s| s
                == format!(
                    "{}_{}_{}",
                    if rec.clustered { "clustered" } else { "non-clustered" },
                    rec.sv_type.short(),
                    SIZE_LABELS[bin]
                ))
            .expect("constructed label must exist in SV32_CHANNELS"),
        idx,
        "index arithmetic desynchronised from the table"
    );
    Sv32Outcome::Channel(idx)
}

/// Canonical label of an SV32 channel index.
///
/// Bounds-checked per FFI contract 4 (structured `"bounds"` error with
/// `i` = 1-based index and `j` = table length, never a panic).
#[inline]
pub fn sv32_label(idx: usize) -> Result<&'static str, MsError> {
    channel_label(&SV32_CHANNELS, idx)
}
