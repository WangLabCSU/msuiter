//! U-M1s-08 formal tests for `catalog/genome.rs`, ported from the U-M0-02
//! spike matrix (ADR 0001): fixture (LE + BE byte-swapped layouts) must be
//! read back bit-identically against ground truth; real-mmap path over a
//! tempfile; MsError paths (bad magic, non-zero version, truncation,
//! unknown chromosome, out-of-bounds context) must fail without panicking.
//!
//! This test crate is a separate compilation unit: the single `unsafe`
//! (`Mmap::map`) for the real-file path lives here, NOT in the catalog
//! library, which is `#![forbid(unsafe_code)]` (ARCHITECTURE §2).

mod fixture;

use std::fs::{self, File};
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use memmap2::Mmap;
use msuiter_catalog::genome::TwoBitGenome;

use fixture::{build, specs, windows, Endian, Fixture};

/// Process-unique temp directory (`std::env::temp_dir` + pid + counter;
/// zero new dependencies), removed on drop — no residue between runs.
struct TempDir(PathBuf);

static TEMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

impl TempDir {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "msuiter-genome-test-{}-{}-{}",
            std::process::id(),
            TEMP_COUNTER.fetch_add(1, Ordering::Relaxed),
            tag
        ));
        fs::create_dir_all(&dir).expect("create temp dir");
        TempDir(dir)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Write `bytes` to a fresh file inside `dir` and return the path.
fn write_temp_2bit(dir: &TempDir, name: &str, bytes: &[u8]) -> PathBuf {
    let path = dir.path().join(name);
    let mut f = File::create(&path).expect("create temp file");
    f.write_all(bytes).expect("write temp file");
    f.flush().expect("flush temp file");
    path
}

/// Full truth assertion: names/sizes in index order, whole chromosome and
/// all spike windows read back via `context` match ground truth exactly
/// (N bytes at hard-mask positions, uppercase elsewhere).
fn assert_full_truth(genome: &mut TwoBitGenome<'_>, fixture: &Fixture) {
    let names: Vec<String> = fixture.chroms.iter().map(|c| c.name.clone()).collect();
    assert_eq!(
        genome.chrom_names(),
        names,
        "{:?} index order",
        fixture.endian
    );
    for chrom in &fixture.chroms {
        assert_eq!(
            genome.chrom_size(&chrom.name).unwrap(),
            chrom.size,
            "{:?} {} size",
            fixture.endian,
            chrom.name
        );
        // Whole chromosome == context with maximal flanks.
        let full = genome.context(&chrom.name, 0, 0, chrom.size - 1).unwrap();
        assert_eq!(
            full,
            chrom.sequence.as_bytes(),
            "{:?} {} full sequence",
            fixture.endian,
            chrom.name
        );
        for &(s, e) in &windows(chrom.size) {
            let w = genome.context(&chrom.name, s, 0, e - s - 1).unwrap();
            assert_eq!(
                w,
                fixture.seq_range(&chrom.name, s, e).as_bytes(),
                "{:?} {} window {s}..{e}",
                fixture.endian,
                chrom.name
            );
        }
    }
}

#[test]
fn reads_little_endian_fixture_against_truth() {
    let fixture = build(&specs(), Endian::Little);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();
    assert_full_truth(&mut genome, &fixture);
}

#[test]
fn reads_big_endian_fixture_against_truth() {
    let fixture = build(&specs(), Endian::Big);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();
    assert_full_truth(&mut genome, &fixture);
}

/// The byte-swap / big-endian validation: both layouts of the same logical
/// content must produce bit-identical output (names, sizes, sequences).
#[test]
fn le_and_be_layouts_are_bit_identical() {
    let le = build(&specs(), Endian::Little);
    let be = build(&specs(), Endian::Big);
    assert_ne!(le.bytes, be.bytes, "layouts must differ on disk");
    let mut g_le = TwoBitGenome::from_bytes(&le.bytes).unwrap();
    let mut g_be = TwoBitGenome::from_bytes(&be.bytes).unwrap();

    assert_eq!(g_le.chrom_names(), g_be.chrom_names());
    for chrom in &le.chroms {
        assert_eq!(g_le.chrom_size(&chrom.name), g_be.chrom_size(&chrom.name));
        assert_eq!(
            g_le.context(&chrom.name, 0, 0, chrom.size - 1).unwrap(),
            g_be.context(&chrom.name, 0, 0, chrom.size - 1).unwrap(),
            "{} full sequence across layouts",
            chrom.name
        );
        for &(s, e) in &windows(chrom.size) {
            assert_eq!(
                g_le.context(&chrom.name, s, 0, e - s - 1).unwrap(),
                g_be.context(&chrom.name, s, 0, e - s - 1).unwrap(),
                "{} window {s}..{e} across layouts",
                chrom.name
            );
        }
    }
}

/// The literal ADR 0001 integration shape: real file on disk, read-only
/// mmap, genome view over the mapped bytes — both layouts, full truth.
/// Object lifetime == test scope: mapping and view drop together (D12).
#[test]
fn real_mmap_over_tempfile_matches_truth_both_layouts() {
    for endian in [Endian::Little, Endian::Big] {
        let fixture = build(&specs(), endian);
        let dir = TempDir::new("mmap");
        let path = write_temp_2bit(&dir, "genome.2bit", &fixture.bytes);

        let file = File::open(&path).expect("reopen temp file");
        // Safety: the mapping is read-only over a file this test alone
        // owns and never truncates while mapped (memmap2 contract).
        let mmap = unsafe { Mmap::map(&file).expect("mmap temp file") };
        let mut genome = TwoBitGenome::from_bytes(&mmap).expect("parse mapped 2bit");
        assert_full_truth(&mut genome, &fixture);
    }
}

/// N bytes pass through verbatim: every position inside every hard-masked
/// block (including block start, block end, and the tail-crossing block)
/// reads back as `N` — N handling policy belongs to the SBS layer.
#[test]
fn context_passes_n_bytes_through_inside_hard_blocks() {
    let fixture = build(&specs(), Endian::Little);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();
    for chrom in &fixture.chroms {
        for &(start, len) in &chrom.n_blocks {
            for pos in [start, start + len / 2, start + len - 1] {
                let got = genome.context(&chrom.name, pos, 0, 0).unwrap();
                assert_eq!(got[0], b'N', "{} pos {pos} inside N block", chrom.name);
            }
        }
    }
}

/// Soft-mask output contract: soft-masked (lowercase) blocks are NOT
/// lowercased — context returns uppercase ACGT (`enable_softmask(false)`
/// semantics). Where a soft block overlaps an N block, N wins (chr2 pos
/// 2000 is inside both).
#[test]
fn context_keeps_soft_blocks_uppercase_and_n_wins_on_overlap() {
    let fixture = build(&specs(), Endian::Little);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();
    for chrom in &fixture.chroms {
        for &(start, len) in &chrom.soft_blocks {
            for pos in [start, start + len / 2, start + len - 1] {
                let got = genome.context(&chrom.name, pos, 0, 0).unwrap();
                assert_eq!(
                    got[0],
                    chrom.sequence.as_bytes()[pos],
                    "{} pos {pos} soft block must surface as uppercase truth",
                    chrom.name
                );
                assert!(
                    got[0].is_ascii_uppercase(),
                    "{} pos {pos} byte {pos:#x} not uppercase",
                    chrom.name
                );
            }
        }
    }
    // chr2: N block (2000, 1) inside soft block (2000, 10) — N wins.
    // Truth bases around it: C T N A C (pattern TCAG[(i*7+3) % 4]).
    let got = genome.context("chr2", 2000, 2, 2).unwrap();
    assert_eq!(&got, b"CTNAC");
}

/// Context window length is exactly flank5 + flank3 + 1, centred on the
/// 0-based position, and slices match ground truth.
#[test]
fn context_window_is_centered_with_exact_length() {
    let fixture = build(&specs(), Endian::Little);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();
    for chrom in &fixture.chroms {
        // Interior positions only: the boundary-crossing cases are covered
        // by `context_bounds_errors_carry_1_based_indices`.
        for pos in [3, chrom.size / 3, chrom.size / 2, chrom.size - 5] {
            let (f5, f3) = (3usize, 4usize);
            let got = genome
                .context(&chrom.name, pos, f5, f3)
                .unwrap_or_else(|_| panic!("{} pos {pos} must be interior enough", chrom.name));
            assert_eq!(got.len(), f5 + f3 + 1);
            assert_eq!(&got[f5], &fixture.base(&chrom.name, pos));
            assert_eq!(
                got,
                &chrom.sequence.as_bytes()[pos - f5..pos + f3 + 1],
                "{} pos {pos} window bytes",
                chrom.name
            );
        }
    }
}

#[test]
fn rejects_bad_magic_without_panicking() {
    let mut bytes = build(&specs(), Endian::Little).bytes;
    bytes[0] ^= 0xff;
    let err = TwoBitGenome::from_bytes(&bytes).unwrap_err();
    assert_eq!(err.topic, "format");
    // The reversed magic is a valid big-endian file, so flip enough to be
    // neither signature: sanity-check the plain reversed magic still parses.
    let be = build(&specs(), Endian::Big);
    assert!(TwoBitGenome::from_bytes(&be.bytes).is_ok());
}

#[test]
fn rejects_nonzero_version() {
    let mut bytes = build(&specs(), Endian::Little).bytes;
    bytes[7] = 1; // version field (LE u32 at offset 4)
    let err = TwoBitGenome::from_bytes(&bytes).unwrap_err();
    assert_eq!(err.topic, "format");
    assert!(err.message.contains("version"), "{}", err.message);
}

#[test]
fn rejects_truncated_header_and_index() {
    let bytes = build(&specs(), Endian::Little).bytes;
    // Header is 16 bytes, index 3 x 9 bytes; anything shorter than the
    // full header+index must fail the initial parse, never panic.
    for cut in [0usize, 4, 15, 20, 16 + 27 - 1] {
        let err = TwoBitGenome::from_bytes(&bytes[..cut]).unwrap_err();
        assert!(
            err.topic == "format" || err.topic == "io",
            "cut {cut}: unexpected topic {}",
            err.topic
        );
    }
}

/// A file whose packed-DNA tail is missing parses (index and record
/// headers are intact) but the affected sequence read fails cleanly with
/// an `io` error. Earlier chromosomes stay fully readable.
#[test]
fn truncated_dna_tail_errors_at_read_time() {
    let bytes = build(&specs(), Endian::Little).bytes;
    let cut = bytes.len() - 50; // tail of the last chromosome (chr2)
    let mut genome = TwoBitGenome::from_bytes(&bytes[..cut]).unwrap();
    assert_eq!(genome.chrom_size("chr2").unwrap(), 4000);
    let err = genome.context("chr2", 0, 0, 3999).unwrap_err();
    assert_eq!(err.topic, "io");
    // A chromosome whose record is fully inside the kept prefix is fine.
    assert_eq!(genome.context("chr1", 0, 0, 1002).unwrap().len(), 1003);
}

#[test]
fn unknown_chromosome_is_an_argument_error() {
    let fixture = build(&specs(), Endian::Little);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();
    let err = genome.context("chrZ", 0, 1, 1).unwrap_err();
    assert_eq!(err.topic, "argument");
    assert!(err.message.contains("chrZ"));
    let err = genome.chrom_size("chrZ").unwrap_err();
    assert_eq!(err.topic, "argument");
}

/// Boundary contract: flanks crossing the chromosome head or tail produce
/// `MsError` (topic `bounds`) with 1-based i/j — never a panic and never a
/// silently clamped window.
#[test]
fn context_bounds_errors_carry_1_based_indices() {
    let fixture = build(&specs(), Endian::Little);
    let mut genome = TwoBitGenome::from_bytes(&fixture.bytes).unwrap();

    // Position itself beyond the chromosome: i = 1-based position, j = size.
    let err = genome.context("chrM", 17, 1, 1).unwrap_err(); // chrM size 17
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(18));
    assert_eq!(err.j, Some(17));

    // Window crossing the head: j = requested first 1-based coordinate (0).
    let err = genome.context("chrM", 0, 1, 1).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(1));
    assert_eq!(err.j, Some(0));

    // Window crossing the tail: j = requested last 1-based coordinate (18).
    let err = genome.context("chrM", 16, 1, 1).unwrap_err();
    assert_eq!(err.topic, "bounds");
    assert_eq!(err.i, Some(17));
    assert_eq!(err.j, Some(18));

    // Extreme flank must fail via the bounds path, not overflow-panic.
    let err = genome.context("chrM", 0, 0, usize::MAX).unwrap_err();
    assert_eq!(err.topic, "bounds");
    let err = genome.context("chrM", 0, usize::MAX, 0).unwrap_err();
    assert_eq!(err.topic, "bounds");

    // Exact-fit windows are fine: first and last base with one-sided flanks.
    assert!(genome.context("chrM", 0, 0, 1).is_ok());
    assert!(genome.context("chrM", 16, 1, 0).is_ok());
}

/// Missing-file behaviour lives at the layer that owns the path (the FFI
/// shell maps the file); here we pin the contract that a buffer shorter
/// than the 4-byte magic is an `io`-topic error, not a panic.
#[test]
fn empty_and_tiny_buffers_error_cleanly() {
    for len in [0usize, 1, 3] {
        let bytes = vec![0x1a_u8; len];
        let err = TwoBitGenome::from_bytes(&bytes).unwrap_err();
        assert_eq!(err.topic, "io", "len {len}");
    }
}
