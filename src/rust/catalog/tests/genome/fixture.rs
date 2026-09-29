//! Deterministic 2bit fixture generator for the `catalog/genome.rs` tests
//! (U-M1s-08), ported from the U-M0-02 spike crate
//! (`tools/spike/twobit-spike/src/fixture.rs`, the ADR 0001 evidence).
//!
//! Builds syntactically valid `.2bit` files in two field layouts from the
//! same logical content:
//!
//! * [`Endian::Little`] — all u32 fields little-endian (files written on
//!   x86/ARM64, the universal case),
//! * [`Endian::Big`] — all u32 fields big-endian (files written on a
//!   big-endian host; every u32 is byte-swapped relative to the LE file).
//!
//! The byte-swap / big-endian validation is the checkable proxy for
//! big-endian host correctness: a conforming reader must detect the layout
//! via the magic number and produce bit-identical output for both files.
//!
//! Format reference: UCSC 2bit spec (magic 0x1A412743, version 0),
//! <https://genome.ucsc.edu/FAQ/FAQformat.html#question7>. Index record
//! `nameSize` is **1 byte** (UCSC spec; verified against the `twobit`
//! crate in the spike).

/// 2bit signature magic number.
pub const MAGIC: u32 = 0x1A41_2743;

/// Field layout of the generated file.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Endian {
    Little,
    Big,
}

fn put_u32(buf: &mut Vec<u8>, v: u32, e: Endian) {
    match e {
        Endian::Little => buf.extend_from_slice(&v.to_le_bytes()),
        Endian::Big => buf.extend_from_slice(&v.to_be_bytes()),
    }
}

/// 2-bit base codes (UCSC packing): T=0, C=1, A=2, G=3.
const BASES: &[u8; 4] = b"TCAG";

fn encode_base(b: u8) -> u32 {
    match b {
        b'T' => 0,
        b'C' => 1,
        b'A' => 2,
        b'G' => 3,
        _ => panic!("fixture bases must be T/C/A/G"),
    }
}

/// Logical content of one chromosome.
pub struct ChromSpec {
    pub name: &'static str,
    pub size: usize,
    /// Sequence pattern: `pattern(i)` gives the (unmasked) base at position i.
    pub pattern: fn(usize) -> u8,
    /// Hard-masked (N) blocks as (start, len); the packed DNA underneath is
    /// written as zeros, which readers must ignore in favour of the blocks.
    pub n_blocks: Vec<(usize, usize)>,
    /// Soft-masked (lowercase) blocks as (start, len). May overlap N blocks
    /// (N wins in the sequence output, per post-mask order).
    pub soft_blocks: Vec<(usize, usize)>,
}

/// Ground truth for one chromosome.
pub struct ChromTruth {
    pub name: String,
    pub size: usize,
    /// Uppercase sequence with `N` substituted at N-block positions
    /// (soft-mask disabled).
    pub sequence: String,
    /// Sequence with soft-mask blocks lowercased as well (never produced by
    /// `genome.rs`, which keeps soft masks disabled — kept for parity with
    /// the spike truth matrix).
    #[allow(dead_code)]
    pub sequence_soft: String,
    pub n_blocks: Vec<(usize, usize)>,
    #[allow(dead_code)]
    pub soft_blocks: Vec<(usize, usize)>,
}

/// A generated fixture: bytes in one layout plus ground truth.
pub struct Fixture {
    pub bytes: Vec<u8>,
    pub endian: Endian,
    pub chroms: Vec<ChromTruth>,
}

impl Fixture {
    /// Subsequence (soft-mask disabled) from ground truth.
    pub fn seq_range(&self, name: &str, start: usize, end: usize) -> String {
        let c = self
            .chroms
            .iter()
            .find(|c| c.name == name)
            .expect("unknown chrom in fixture");
        c.sequence[start..end].to_string()
    }

    /// Ground-truth base at one position (soft-mask disabled).
    pub fn base(&self, name: &str, pos: usize) -> u8 {
        self.seq_range(name, pos, pos + 1).as_bytes()[0]
    }
}

fn truth_for(spec: &ChromSpec) -> ChromTruth {
    let mut sequence = Vec::with_capacity(spec.size);
    for i in 0..spec.size {
        sequence.push((spec.pattern)(i));
    }
    // N blocks first (hard), as conforming readers apply them.
    for &(s, l) in &spec.n_blocks {
        for b in &mut sequence[s..s + l] {
            *b = b'N';
        }
    }
    let mut sequence_soft = sequence.clone();
    for &(s, l) in &spec.soft_blocks {
        for b in &mut sequence_soft[s..s + l] {
            *b = b.to_ascii_lowercase();
        }
    }
    ChromTruth {
        name: spec.name.to_string(),
        size: spec.size,
        sequence: String::from_utf8(sequence).unwrap(),
        sequence_soft: String::from_utf8(sequence_soft).unwrap(),
        n_blocks: spec.n_blocks.clone(),
        soft_blocks: spec.soft_blocks.clone(),
    }
}

fn packed_dna(spec: &ChromSpec, out: &mut Vec<u8>) {
    let in_n = |i: usize| spec.n_blocks.iter().any(|&(s, l)| i >= s && i < s + l);
    let mut acc: u32 = 0;
    let mut filled = 0usize;
    for i in 0..spec.size {
        // N-block packed bits are don't-care; write zeros like UCSC does.
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
        // Pad the trailing partial byte with zeros (first base in high bits).
        acc <<= 2 * (4 - filled);
        out.push(acc as u8);
    }
}

fn record_size(spec: &ChromSpec) -> usize {
    4 + 4 + 8 * spec.n_blocks.len() + 4 + 8 * spec.soft_blocks.len() + 4 + (spec.size + 3) / 4
}

/// Build a complete 2bit file in the requested layout.
pub fn build(specs: &[ChromSpec], endian: Endian) -> Fixture {
    let truths: Vec<ChromTruth> = specs.iter().map(truth_for).collect();

    // Layout: header (16 bytes), then the sequence records in index order.
    // Index record: 1-byte nameSize (per UCSC spec), name, 4-byte offset.
    let mut offsets = Vec::with_capacity(specs.len());
    let mut off = 16usize;
    for s in specs {
        off += 1 + s.name.len() + 4;
    }
    for s in specs {
        offsets.push(off as u32);
        off += record_size(s);
    }

    let mut b = Vec::with_capacity(off);
    put_u32(&mut b, MAGIC, endian); // signature
    put_u32(&mut b, 0, endian); // version
    put_u32(&mut b, specs.len() as u32, endian); // sequenceCount
    put_u32(&mut b, 0, endian); // reserved

    // Sequence index.
    for (s, &o) in specs.iter().zip(&offsets) {
        b.push(s.name.len() as u8);
        b.extend_from_slice(s.name.as_bytes());
        put_u32(&mut b, o, endian);
    }

    // Sequence records.
    for s in specs {
        put_u32(&mut b, s.size as u32, endian); // dnaSize
        put_u32(&mut b, s.n_blocks.len() as u32, endian);
        for &(st, _l) in &s.n_blocks {
            put_u32(&mut b, st as u32, endian);
        }
        for &(_st, l) in &s.n_blocks {
            put_u32(&mut b, l as u32, endian);
        }
        put_u32(&mut b, s.soft_blocks.len() as u32, endian);
        for &(st, _l) in &s.soft_blocks {
            put_u32(&mut b, st as u32, endian);
        }
        for &(_st, l) in &s.soft_blocks {
            put_u32(&mut b, l as u32, endian);
        }
        put_u32(&mut b, 0, endian); // reserved
        packed_dna(s, &mut b);
    }
    debug_assert_eq!(b.len(), off, "fixture layout arithmetic drifted");

    Fixture {
        bytes: b,
        endian,
        chroms: truths,
    }
}

/// Deterministic fixture specs shared by all genome tests (ported from the
/// spike's `specs()`).
///
/// Coverage: multiple chromosomes; sizes not multiples of 4 (partial last
/// byte: chr1 = 1003, chrM = 17, chr2 = 4000); N blocks at position 0, mid,
/// and crossing the end; adjacent N blocks; soft blocks; a soft block
/// overlapping an N block (N wins).
pub fn specs() -> Vec<ChromSpec> {
    vec![
        ChromSpec {
            name: "chr1",
            size: 1003,
            pattern: |i| BASES[i % 4],
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
            pattern: |i| BASES[(i * 7 + 3) % 4],
            n_blocks: vec![(2000, 1), (3000, 5), (3005, 5)],
            soft_blocks: vec![(100, 150), (2000, 10), (3900, 100)],
        },
    ]
}

/// Interesting windows per chromosome: byte-crossing subranges, edges,
/// single bases, block boundaries — all clamped inside `0..size` (ported
/// from the spike's `windows()`).
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
