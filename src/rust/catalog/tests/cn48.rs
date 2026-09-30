//! CN48 golden + property tests (U-M1c-03).
//!
//! Semantic source of truth: SPMG `CNVMatrixGenerator.py`
//! (`annotateSegFile`), upstream master `edccbea6` (tag v1.3.6
//! `4923d61`; every consumed behaviour byte-identical — the sole file
//! diff is a FACETS-input-only LOH branch this module never executes,
//! see the `cn48` module docs). Labels double-pinned to
//! `COSMIC_v3.6_CN_GRCh37.txt` rows 1..48.
//!
//! Golden convention: every golden is HAND-DERIVED from the upstream
//! rules (TCN bands CNVMatrixGenerator.py:76-90, LOH zero-test
//! :196-204, length :306-337, size bins :343-373, homdel prefix
//! :379-382) and asserts BOTH the table index and the label string, so
//! index arithmetic and table content are pinned together. Boundary
//! goldens sit exactly on every bin edge (lower-inclusive side and the
//! first bp past it), because the bins are lower-exclusive /
//! upper-inclusive in Mb (:347-371).

use msuiter_catalog::cn48::{assign_cn48, cn48_label, CnSegment, CN48_CHANNELS};

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

/// Build a segment from (length bp, minor CN, major CN).
fn seg(len_bp: u64, minor: u8, major: u8) -> CnSegment {
    CnSegment {
        seg_len_bp: len_bp,
        minor_cn: minor,
        major_cn: major,
    }
}

/// Golden workhorse: assign and expect a valid channel.
fn chan(s: &CnSegment) -> usize {
    assign_cn48(s).expect("valid segment")
}

/// Assert a golden: index AND canonical label.
fn assert_channel(s: &CnSegment, idx: usize, label: &str) {
    assert_eq!(chan(s), idx, "index for {s:?}");
    assert_eq!(cn48_label(idx), Ok(label), "label for {s:?}");
    // The table must agree with itself: the index's slot holds the label.
    assert_eq!(CN48_CHANNELS[idx], label);
}

// ---------------------------------------------------------------------------
// Golden: homdel block (0:homdel, indices 0-2, 3 bins only :346-355).
// ---------------------------------------------------------------------------

#[test]
fn golden_homdel() {
    // (0,0): tcn = 0 -> homdel prefix "0" (:379-380), whatever the TCN
    // class arithmetic would say.
    assert_channel(&seg(50_000, 0, 0), 0, "0:homdel:0-100kb");
    // Zero-length segment is ADMITTED upstream (lower bin edge -0.01 Mb,
    // :347/:357); the brief's non-zero validation is deliberately NOT
    // implemented (D11: upstream counts end==start into 0-100kb).
    assert_channel(&seg(0, 0, 0), 0, "0:homdel:0-100kb");
    // Upper-inclusive edge: 100_000 bp = 0.1 Mb exactly -> still bin 0.
    assert_channel(&seg(100_000, 0, 0), 0, "0:homdel:0-100kb");
    // First bp past the edge opens bin 1.
    assert_channel(&seg(100_001, 0, 0), 1, "0:homdel:100kb-1Mb");
    // 1 Mb exactly is the top of bin 1 (:350-352: l > 0.1 and l <= 1).
    assert_channel(&seg(1_000_000, 0, 0), 1, "0:homdel:100kb-1Mb");
    assert_channel(&seg(1_000_001, 0, 0), 2, "0:homdel:>1Mb");
    // The homdel bins never split 1-10/10-40 Mb (:17: three bins only).
    assert_channel(&seg(5_000_000, 0, 0), 2, "0:homdel:>1Mb");
    assert_channel(&seg(40_000_000, 0, 0), 2, "0:homdel:>1Mb");
}

// ---------------------------------------------------------------------------
// Golden: 1:LOH block (indices 3-7) with all four non-trivial bin edges.
// ---------------------------------------------------------------------------

#[test]
fn golden_1loh_all_bins() {
    // (0,1): tcn = 1, minor = 0 -> "1" + LOH (:109-110: tcn 0 or 1 ->
    // "1"; :201: an allele at 0 -> LOH).
    assert_channel(&seg(1_000, 0, 1), 3, "1:LOH:0-100kb");
    assert_channel(&seg(100_000, 0, 1), 3, "1:LOH:0-100kb");
    assert_channel(&seg(100_001, 0, 1), 4, "1:LOH:100kb-1Mb");
    // (1, 10] Mb.
    assert_channel(&seg(5_000_000, 0, 1), 5, "1:LOH:1Mb-10Mb");
    // 40 Mb exactly is the TOP of 10Mb-40Mb (:366-368: l > 10 and
    // l <= 40).
    assert_channel(&seg(40_000_000, 0, 1), 6, "1:LOH:10Mb-40Mb");
    assert_channel(&seg(40_000_001, 0, 1), 7, "1:LOH:>40Mb");
}

// ---------------------------------------------------------------------------
// Golden: the remaining LOH classes (2 / 3-4 / 5-8 / 9+).
// ---------------------------------------------------------------------------

#[test]
fn golden_loh_classes() {
    // (0,2): tcn = 2, LOH (minor 0) -> 2:LOH block, indices 8-12.
    assert_channel(&seg(500_000, 0, 2), 9, "2:LOH:100kb-1Mb");
    // (0,3): tcn = 3 -> "3-4"; block at 13-17.
    assert_channel(&seg(5_000_000, 0, 3), 15, "3-4:LOH:1Mb-10Mb");
    // (0,7): tcn = 7 -> "5-8"; block at 18-22.
    assert_channel(&seg(5_000_000, 0, 7), 20, "5-8:LOH:1Mb-10Mb");
    // (0,9): tcn = 9 -> "9+" (else branch, :89-90); block at 23-27.
    assert_channel(&seg(5_000_000, 0, 9), 25, "9+:LOH:1Mb-10Mb");
    // (0,10): tcn = 10 stays "9+" (no upper cap; :87-90 chain).
    assert_channel(&seg(500_000, 0, 10), 24, "9+:LOH:100kb-1Mb");
}

// ---------------------------------------------------------------------------
// Golden: het classes (2 / 3-4 / 5-8 / 9+; indices 28-47).
// ---------------------------------------------------------------------------

#[test]
fn golden_het_classes() {
    // (1,1): tcn = 2, both alleles present -> het (:203-204); the het
    // body starts at index 28 ("2:het:0-100kb"), so 100kb-1Mb is 29.
    assert_channel(&seg(500_000, 1, 1), 29, "2:het:100kb-1Mb");
    // (2,2): tcn = 4 -> "3-4" het; 1Mb-10Mb at 35.
    assert_channel(&seg(5_000_000, 2, 2), 35, "3-4:het:1Mb-10Mb");
    // (4,4): tcn = 8, the TOP of the 5-8 band (:87-88).
    assert_channel(&seg(5_000_000, 4, 4), 40, "5-8:het:1Mb-10Mb");
    // (5,5): tcn = 10 -> "9+" het.
    assert_channel(&seg(5_000_000, 5, 5), 45, "9+:het:1Mb-10Mb");
    // u8 maxima: tcn = 509 -> still "9+" (u16 sum, no cap in :89-90).
    assert_channel(&seg(100_000_000, 254, 255), 47, "9+:het:>40Mb");
    // (0,255) is LOH at tcn 255 -> "9+:LOH:>40Mb" (index 27).
    assert_channel(&seg(100_000_000, 0, 255), 27, "9+:LOH:>40Mb");
}

// ---------------------------------------------------------------------------
// Golden: the "1:het" impossibility (no such row may ever be produced).
// ---------------------------------------------------------------------------

#[test]
fn tcn1_is_always_loh() {
    // tcn = 1 forces minor = 0 (ordered pair), which the zero-test
    // classes as LOH (:201) — the combinatorially implied "1:het" row
    // does not exist upstream and must be unreachable here.
    assert_channel(&seg(500_000, 0, 1), 4, "1:LOH:100kb-1Mb");
    for bin_edge in [0, 1, 99_999, 100_000, 100_001, 999_999, 1_000_000] {
        let idx = chan(&seg(bin_edge, 0, 1));
        assert!(
            (3..=7).contains(&idx),
            "tcn=1 landed outside the 1:LOH block: {idx}"
        );
        assert_ne!(CN48_CHANNELS[idx], "1:het:0-100kb");
    }
}

// ---------------------------------------------------------------------------
// Property: 48-channel reachability bijection.
// ---------------------------------------------------------------------------

#[test]
fn property_all_48_channels_reachable_and_total() {
    // A size grid sitting on and around every bin edge, swept over a
    // TCN grid covering {1, 2, 3-4, 5-8, 9+} in both zygosities.
    let sizes = [
        0,
        1,
        99_999,
        100_000,
        100_001,
        999_999,
        1_000_000,
        1_000_001,
        9_999_999,
        10_000_000,
        10_000_001,
        39_999_999,
        40_000_000,
        40_000_001,
        100_000_000,
    ];
    let mut hit = [false; 48];
    for minor in 0u8..=12 {
        for major in minor..=12 {
            for &len in &sizes {
                let idx = chan(&seg(len, minor, major));
                assert!(idx < 48, "index {idx} out of table for {minor}/{major}@{len}");
                hit[idx] = true;
            }
        }
    }
    let missing: Vec<usize> = (0..48).filter(|&i| !hit[i]).collect();
    assert!(missing.is_empty(), "unreachable channels: {missing:?}");
}

// ---------------------------------------------------------------------------
// Property: bin monotonicity (longer segment never lands in a lower bin
// within a fixed (minor, major) class).
// ---------------------------------------------------------------------------

#[test]
fn property_index_monotone_in_segment_length() {
    for minor in 0u8..=6 {
        for major in minor..=6 {
            let mut prev = chan(&seg(0, minor, major));
            for len in [1, 1_000, 100_000, 100_001, 1_000_000, 5_000_000, 40_000_000, u64::MAX] {
                let idx = chan(&seg(len, minor, major));
                assert!(idx >= prev, "non-monotone at {minor}/{major} len {len}");
                prev = idx;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Property: table shape (order is the upstream list order, not ASCII).
// ---------------------------------------------------------------------------

#[test]
fn property_table_shape() {
    assert_eq!(CN48_CHANNELS.len(), 48);
    // Upstream :71.
    let unique: std::collections::HashSet<_> = CN48_CHANNELS.iter().collect();
    assert_eq!(unique.len(), 48, "duplicate labels");
    // Block counts: 3 homdel + 25 LOH + 20 het.
    let homdel = CN48_CHANNELS.iter().filter(|s| s.contains("homdel")).count();
    let loh = CN48_CHANNELS.iter().filter(|s| s.contains(":LOH:")).count();
    let het = CN48_CHANNELS.iter().filter(|s| s.contains(":het:")).count();
    assert_eq!((homdel, loh, het), (3, 25, 20));
    // NOT a global ASCII sort: lexicographically "1:LOH:10Mb-40Mb" <
    // "1:LOH:1Mb-10Mb" ('0' < 'M' at the diverging byte), yet the
    // canonical order holds 1Mb-10Mb (index 5) BEFORE 10Mb-40Mb
    // (index 6), matching the upstream list :26-27.
    assert_eq!(CN48_CHANNELS[5], "1:LOH:1Mb-10Mb");
    assert_eq!(CN48_CHANNELS[6], "1:LOH:10Mb-40Mb");
    assert!(
        CN48_CHANNELS[5] > CN48_CHANNELS[6],
        "canonical order is upstream list order, which ASCII sorting would invert"
    );
}

// ---------------------------------------------------------------------------
// Errors: unordered allele pair; label bounds.
// ---------------------------------------------------------------------------

#[test]
fn error_unordered_allele_pair() {
    let err = assign_cn48(&seg(500_000, 2, 1)).expect_err("minor > major must error");
    assert_eq!(err.topic, "argument");
    assert!(err.message.contains("minor copy number 2"), "{err}");
    assert!(err.message.contains("major copy number 1"), "{err}");
}

#[test]
fn label_bounds() {
    assert_eq!(cn48_label(0), Ok("0:homdel:0-100kb"));
    assert_eq!(cn48_label(47), Ok("9+:het:>40Mb"));
    let err = cn48_label(48).expect_err("48 out of bounds");
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(49), "1-based index in i");
    assert_eq!(err.j, Some(48), "table length in j");
}
