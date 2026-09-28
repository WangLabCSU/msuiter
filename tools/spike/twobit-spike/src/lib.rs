//! U-M0-02 spike scratch crate (lives outside the msuiter workspace).
//!
//! Two reader arms over identical fixtures:
//! * `twobit` crate 0.2.2 (over `Cursor<Mmap>` / `Cursor<Vec<u8>>`),
//! * `own::OwnTwoBit` — the in-house prototype (244 lines (own.rs)).
//!
//! Fixtures are generated in both little-endian and big-endian (byte
//! swapped) field layouts; a conforming reader must produce bit-identical
//! output for both.

pub mod fixture;
pub mod own;

use fixture::ChromSpec;

/// Deterministic fixture specs shared by all spike tests.
///
/// Coverage: multiple chromosomes; sizes not multiples of 4 (partial last
/// byte); N blocks at position 0, mid, and crossing the end; adjacent N
/// blocks; soft blocks; a soft block overlapping an N block (N wins).
pub fn specs() -> Vec<ChromSpec> {
    vec![
        ChromSpec {
            name: "chr1",
            size: 1003,
            pattern: |i| b"TCAG"[i % 4],
            n_blocks: vec![(0, 10), (500, 5), (1000, 3)],
            soft_blocks: vec![(200, 50)],
        },
        ChromSpec {
            name: "chrM",
            size: 17,
            pattern: |i| b"GA"[i % 2],
            n_blocks: vec![(3, 3)],
            soft_blocks: vec![(10, 4)],
        },
        ChromSpec {
            name: "chr2",
            size: 4000,
            pattern: |i| b"TCAG"[(i * 7 + 3) % 4],
            n_blocks: vec![(2000, 1), (3000, 5), (3005, 5)],
            soft_blocks: vec![(100, 150), (2000, 10), (3900, 100)],
        },
    ]
}

/// Interesting windows per chromosome: byte-crossing subranges, edges,
/// single bases, block boundaries — all clamped inside `0..size`.
pub fn windows(size: usize) -> Vec<(usize, usize)> {
    let raw = [
        (0, 1),
        (0, 4),
        (0, 7),
        (3, 9),
        (5, 5 + 13),
        (size - 4, size),
        (size - 1, size),
        (size / 2, size / 2 + 33),
    ];
    raw.iter()
        .map(|&(s, e)| (s.min(size), e.min(size)))
        .filter(|&(s, e)| s < e)
        .collect()
}
