//! SV32 golden + property tests (U-M1c-04).
//!
//! Semantic source of truth: SPMG `SVMatrixGenerator.py`
//! (`processBEDPE` :1037-1191, `tsv2matrix` :1193-1257), upstream
//! master `edccbea6` (tag v1.3.6 `4923d61`; every consumed behaviour
//! byte-identical — the sole file diff is the `np.in1d` → `np.isin`
//! rename, see the `sv32` module docs). Labels double-pinned to
//! `COSMIC_v3.6_SV_GRCh38.txt` rows 1..32.
//!
//! Golden convention: every golden is HAND-DERIVED from the upstream
//! rules (size binning :1142-1157, strict <1000 drop :1184-1189,
//! clustered prefix :1246-1250, svclass_mapping :1228-1233) and asserts
//! BOTH the table index and the label string. Boundary goldens sit
//! exactly on every bin edge — the bins are lower-exclusive /
//! upper-INCLUSIVE in Mb (:1142-1157), so each edge value belongs to
//! the LOWER bin — plus the strict 1000 bp drop edge (:1185: `< 1000`,
//! so 1000 counts and 999 does not).

use msuiter_catalog::sv32::{assign_sv32, sv32_label, Sv32Outcome, SvRecord, SvType, SV32_CHANNELS};

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

/// Build a record from (type, size bp, clustered).
fn sv(t: SvType, size_bp: u64, clustered: bool) -> SvRecord {
    SvRecord {
        sv_type: t,
        size_bp,
        clustered,
    }
}

/// Golden workhorse for counted records.
fn chan(rec: &SvRecord) -> usize {
    match assign_sv32(rec) {
        Sv32Outcome::Channel(i) => i,
        other => panic!("expected a channel, got {other:?} for {rec:?}"),
    }
}

/// Assert a counted golden: index AND canonical label.
fn assert_channel(rec: &SvRecord, idx: usize, label: &str) {
    assert_eq!(chan(rec), idx, "index for {rec:?}");
    assert_eq!(sv32_label(idx), Ok(label), "label for {rec:?}");
    assert_eq!(SV32_CHANNELS[idx], label);
}

/// Assert a dropped golden (the strict <1000 bp rule, :1185).
fn assert_too_short(rec: &SvRecord) {
    assert_eq!(assign_sv32(rec), Sv32Outcome::TooShortNoChannel);
}

// ---------------------------------------------------------------------------
// Golden: deletion x all five bins with every edge (nc = indices 16-20).
// ---------------------------------------------------------------------------

#[test]
fn golden_deletion_all_bins_and_edges() {
    // Exactly 1000 bp SURVIVES the strict drop and lands in 1-10Kb.
    assert_channel(&sv(SvType::Deletion, 1_000, false), 16, "non-clustered_del_1-10Kb");
    // Top of the first bin (l <= 0.010 Mb, :1142-1144).
    assert_channel(&sv(SvType::Deletion, 10_000, false), 16, "non-clustered_del_1-10Kb");
    assert_channel(&sv(SvType::Deletion, 10_001, false), 17, "non-clustered_del_10-100Kb");
    assert_channel(&sv(SvType::Deletion, 100_000, false), 17, "non-clustered_del_10-100Kb");
    assert_channel(&sv(SvType::Deletion, 100_001, false), 18, "non-clustered_del_100Kb-1Mb");
    assert_channel(&sv(SvType::Deletion, 1_000_000, false), 18, "non-clustered_del_100Kb-1Mb");
    assert_channel(&sv(SvType::Deletion, 1_000_001, false), 19, "non-clustered_del_1Mb-10Mb");
    assert_channel(&sv(SvType::Deletion, 10_000_000, false), 19, "non-clustered_del_1Mb-10Mb");
    assert_channel(&sv(SvType::Deletion, 10_000_001, false), 20, "non-clustered_del_>10Mb");
    assert_channel(&sv(SvType::Deletion, u64::MAX, false), 20, "non-clustered_del_>10Mb");
}

// ---------------------------------------------------------------------------
// Golden: the strict <1000 bp drop (:1184-1189) — del/tds/inv only.
// ---------------------------------------------------------------------------

#[test]
fn golden_too_short_drop() {
    for t in [SvType::Deletion, SvType::TandemDup, SvType::Inversion] {
        assert_too_short(&sv(t, 0, false));
        assert_too_short(&sv(t, 999, false));
        assert_too_short(&sv(t, 999, true));
    }
    // Translocations are exempt (:1185 guards on svclass).
    assert_channel(&sv(SvType::Translocation, 999, false), 31, "non-clustered_trans");
    assert_channel(&sv(SvType::Translocation, 999, true), 15, "clustered_trans");
}

// ---------------------------------------------------------------------------
// Golden: tds and inv blocks, clustered and non-clustered.
// ---------------------------------------------------------------------------

#[test]
fn golden_tds_inv_blocks() {
    // Clustered del block (indices 0-4).
    assert_channel(&sv(SvType::Deletion, 50_000, true), 1, "clustered_del_10-100Kb");
    assert_channel(&sv(SvType::Deletion, 50_000_000, true), 4, "clustered_del_>10Mb");
    // Clustered tds (5-9).
    assert_channel(&sv(SvType::TandemDup, 5_000, true), 5, "clustered_tds_1-10Kb");
    assert_channel(&sv(SvType::TandemDup, 500_000, true), 7, "clustered_tds_100Kb-1Mb");
    // Non-clustered tds (21-25).
    assert_channel(&sv(SvType::TandemDup, 50_000, false), 22, "non-clustered_tds_10-100Kb");
    assert_channel(&sv(SvType::TandemDup, 50_000_000, false), 25, "non-clustered_tds_>10Mb");
    // Clustered inv (10-14).
    assert_channel(&sv(SvType::Inversion, 500_000, true), 12, "clustered_inv_100Kb-1Mb");
    // Non-clustered inv (26-30).
    assert_channel(&sv(SvType::Inversion, 1_000, false), 26, "non-clustered_inv_1-10Kb");
    assert_channel(&sv(SvType::Inversion, 5_000_000, false), 29, "non-clustered_inv_1Mb-10Mb");
    assert_channel(&sv(SvType::Inversion, 50_000_000, false), 30, "non-clustered_inv_>10Mb");
}

// ---------------------------------------------------------------------------
// Golden: translocation channels — no bin, size ignored (:1158-1161,
// :1251-1254).
// ---------------------------------------------------------------------------

#[test]
fn golden_translocation_size_irrelevant() {
    assert_channel(&sv(SvType::Translocation, 0, true), 15, "clustered_trans");
    assert_channel(&sv(SvType::Translocation, u64::MAX, true), 15, "clustered_trans");
    assert_channel(&sv(SvType::Translocation, 0, false), 31, "non-clustered_trans");
    assert_channel(&sv(SvType::Translocation, u64::MAX, false), 31, "non-clustered_trans");
}

// ---------------------------------------------------------------------------
// Property: 32-channel reachability bijection.
// ---------------------------------------------------------------------------

#[test]
fn property_all_32_channels_reachable() {
    let sizes = [1_000, 5_000, 10_000, 10_001, 50_000, 100_000, 100_001, 500_000, 1_000_000, 1_000_001, 5_000_000, 10_000_000, 10_000_001, 50_000_000];
    let types = [SvType::Deletion, SvType::TandemDup, SvType::Inversion, SvType::Translocation];
    let mut hit = [false; 32];
    for &t in &types {
        for clustered in [false, true] {
            for &size in &sizes {
                if let Sv32Outcome::Channel(idx) = assign_sv32(&sv(t, size, clustered)) {
                    assert!(idx < 32, "index {idx} out of table");
                    hit[idx] = true;
                }
            }
        }
    }
    let missing: Vec<usize> = (0..32).filter(|&i| !hit[i]).collect();
    assert!(missing.is_empty(), "unreachable channels: {missing:?}");
}

// ---------------------------------------------------------------------------
// Property: bin-edge continuity (the brief's 9999-vs-10001 style
// assertion, generalised to all four edges): the edge value stays in
// the lower bin, edge+1 opens the next one, edge-1 shares the lower
// bin. Indices must step by exactly one across each boundary.
// ---------------------------------------------------------------------------

#[test]
fn property_bin_edge_continuity() {
    let edges = [10_000u64, 100_000, 1_000_000, 10_000_000];
    for &t in [SvType::Deletion, SvType::TandemDup, SvType::Inversion].iter() {
        for clustered in [false, true] {
            for &edge in &edges {
                let below = chan(&sv(t, edge - 1, clustered));
                let at = chan(&sv(t, edge, clustered));
                let past = chan(&sv(t, edge + 1, clustered));
                assert_eq!(below, at, "edge {edge} must stay in the lower bin");
                assert_eq!(past, at + 1, "edge {edge}+1 must open the adjacent bin");
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Property: the non-clustered half mirrors the clustered half at +16
// (index map of the upstream `features` order, :1194-1231).
// ---------------------------------------------------------------------------

#[test]
fn property_nonclustered_mirrors_clustered_at_plus_16() {
    let sizes = [1_000, 10_000, 50_000, 100_001, 1_000_000, 10_000_001];
    for &t in [SvType::Deletion, SvType::TandemDup, SvType::Inversion].iter() {
        for &size in &sizes {
            assert_eq!(
                chan(&sv(t, size, false)),
                chan(&sv(t, size, true)) + 16,
                "mirror offset for {t:?}@{size}"
            );
        }
        // ... including the trans slot.
        assert_eq!(
            chan(&sv(SvType::Translocation, 0, false)),
            chan(&sv(SvType::Translocation, 0, true)) + 16,
        );
    }
}

// ---------------------------------------------------------------------------
// Property: monotone in size within a fixed (type, clustered) class.
// ---------------------------------------------------------------------------

#[test]
fn property_index_monotone_in_size() {
    for &t in [SvType::Deletion, SvType::TandemDup, SvType::Inversion].iter() {
        for clustered in [false, true] {
            let mut prev = 0usize;
            for &size in [1_000u64, 10_000, 100_000, 1_000_000, 10_000_000, u64::MAX].iter() {
                let idx = chan(&sv(t, size, clustered));
                assert!(idx >= prev, "non-monotone at {t:?}@{size}");
                prev = idx;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Property: table shape (32 unique labels; order is the upstream list
// order :1194-1231 — pinned by position, not by string sort; for SV32
// the upstream order happens to coincide with ASCII, unlike CN48).
// ---------------------------------------------------------------------------

#[test]
fn property_table_shape() {
    assert_eq!(SV32_CHANNELS.len(), 32);
    let unique: std::collections::HashSet<_> = SV32_CHANNELS.iter().collect();
    assert_eq!(unique.len(), 32, "duplicate labels");
    // Block layout at its four anchors.
    assert_eq!(SV32_CHANNELS[0], "clustered_del_1-10Kb");
    assert_eq!(SV32_CHANNELS[15], "clustered_trans");
    assert_eq!(SV32_CHANNELS[16], "non-clustered_del_1-10Kb");
    assert_eq!(SV32_CHANNELS[31], "non-clustered_trans");
    // Every clustered channel is followed by its non-clustered mirror
    // exactly 16 slots later (already proven by
    // property_nonclustered_mirrors_clustered_at_plus_16; here the
    // LABEL pairs are checked).
    for i in 0..16 {
        let clustered = SV32_CHANNELS[i].replacen("clustered", "non-clustered", 1);
        assert_eq!(SV32_CHANNELS[i + 16], clustered, "mirror of slot {i}");
    }
}

// ---------------------------------------------------------------------------
// Label bounds.
// ---------------------------------------------------------------------------

#[test]
fn label_bounds() {
    assert_eq!(sv32_label(0), Ok("clustered_del_1-10Kb"));
    assert_eq!(sv32_label(31), Ok("non-clustered_trans"));
    let err = sv32_label(32).expect_err("32 out of bounds");
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(33), "1-based index in i");
    assert_eq!(err.j, Some(32), "table length in j");
}
