//! Spike prototype of the in-house 2bit reader (the "self-made" arm of
//! the U-M0-02 ADR experiment; U-M1s-08 would finalize it into
//! `catalog/genome.rs`).
//!
//! Contract mirrored from the `twobit` crate API surface so the two arms
//! are directly comparable:
//!
//! * endian auto-detection via the magic number (0x1A412743) and its
//!   byte-reversed twin, with all u32 index fields swapped when needed;
//! * zero-copy parsing over an immutable byte slice (`AsRef<[u8]>`),
//!   i.e. the `Cursor<Mmap>` shape: header/index parsed once, sequence
//!   bytes read on demand by offset arithmetic (random access per
//!   chromosome, no full-file copy);
//! * sequence decode: 2 bits per base, first base of each byte in the
//!   high bits, codes T=0 C=1 A=2 G=3; N blocks applied post-decode,
//!   then soft-mask lowercasing (matching the crate's mask order).

use std::ops::Range;

pub const MAGIC: u32 = 0x1A41_2743;

const BASES: &[u8; 4] = b"TCAG";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OwnError(pub String);

pub type OwnResult<T> = Result<T, OwnError>;

fn err<T>(msg: impl Into<String>) -> OwnResult<T> {
    Err(OwnError(msg.into()))
}

struct ChromEntry {
    name: String,
    offset: usize,
    size: usize,
    packed_offset: usize,
    n_blocks: Vec<Range<usize>>,
    soft_blocks: Vec<Range<usize>>,
}

/// Reader over an immutable byte buffer (`Cursor<Mmap>` semantics: parse
/// the header/index up front, seek into the buffer per query).
pub struct OwnTwoBit<'a> {
    buf: &'a [u8],
    swap: bool,
    chroms: Vec<ChromEntry>,
}

impl<'a> OwnTwoBit<'a> {
    pub fn from_slice(buf: &'a [u8]) -> OwnResult<Self> {
        if buf.len() < 16 {
            return err("file too short for 2bit header");
        }
        let sig = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
        let swap = if sig == MAGIC {
            false
        } else if sig == MAGIC.swap_bytes() {
            true
        } else {
            return err("file does not start with 2bit signature");
        };
        let u32le = |b: &[u8]| u32::from_le_bytes([b[0], b[1], b[2], b[3]]);
        let field = |pos: usize| -> OwnResult<u32> {
            let raw = u32le(
                buf.get(pos..pos + 4)
                    .ok_or_else(|| OwnError("truncated u32 field".into()))?,
            );
            Ok(if swap { raw.swap_bytes() } else { raw })
        };

        let _version = field(4)?;
        if _version != 0 {
            return err("only 2bit version 0 is supported");
        }
        let count = field(8)? as usize;
        let _reserved = field(12)?;

        // Sequence index: (1-byte nameSize, name, offset) per record,
        // exactly as the UCSC 2bit spec defines it.
        let mut cursor = 16usize;
        let mut index = Vec::with_capacity(count);
        for _ in 0..count {
            let name_size = *buf
                .get(cursor)
                .ok_or_else(|| OwnError("truncated name size".into()))? as usize;
            cursor += 1;
            let name_bytes = buf
                .get(cursor..cursor + name_size)
                .ok_or_else(|| OwnError("truncated sequence name".into()))?;
            let name = String::from_utf8(name_bytes.to_vec())
                .map_err(|_| OwnError("sequence name is not UTF-8".into()))?;
            cursor += name_size;
            let offset = field(cursor)? as usize;
            cursor += 4;
            index.push((name, offset));
        }

        // Sequence records: dnaSize, N blocks, soft blocks, reserved,
        // packed DNA. Record the packed-DNA start for random access.
        let mut chroms = Vec::with_capacity(count);
        for (name, offset) in index {
            let mut p = offset;
            let size = field(p)? as usize;
            p += 4;
            let n_count = field(p)? as usize;
            p += 4;
            let mut n_blocks = Vec::with_capacity(n_count);
            for _ in 0..n_count {
                let start = field(p)? as usize;
                p += 4;
                n_blocks.push(start..start); // end patched after length read
            }
            for b in &mut n_blocks {
                let len = field(p)? as usize;
                p += 4;
                b.end = b.start.checked_add(len).ok_or_else(|| OwnError("block overflow".into()))?;
            }
            let soft_count = field(p)? as usize;
            p += 4;
            let mut soft_blocks = Vec::with_capacity(soft_count);
            for _ in 0..soft_count {
                let start = field(p)? as usize;
                p += 4;
                soft_blocks.push(start..start); // end patched after length read
            }
            for b in &mut soft_blocks {
                let len = field(p)? as usize;
                p += 4;
                b.end = b.start.checked_add(len).ok_or_else(|| OwnError("block overflow".into()))?;
            }
            let _reserved = field(p)?;
            p += 4;
            chroms.push(ChromEntry {
                name,
                offset,
                size,
                packed_offset: p,
                n_blocks,
                soft_blocks,
            });
        }

        Ok(Self { buf, swap, chroms })
    }

    /// Whether the file was byte-swapped (big-endian field layout).
    pub fn endian_swapped(&self) -> bool {
        self.swap
    }

    fn entry(&self, name: &str) -> OwnResult<&ChromEntry> {
        self.chroms
            .iter()
            .find(|c| c.name == name)
            .ok_or_else(|| OwnError(format!("missing sequence: {name}")))
    }

    pub fn chrom_names(&self) -> Vec<String> {
        self.chroms.iter().map(|c| c.name.clone()).collect()
    }

    pub fn chrom_sizes(&self) -> Vec<usize> {
        self.chroms.iter().map(|c| c.size).collect()
    }

    /// Hard-masked (N) blocks intersecting `[start, end)`.
    pub fn n_blocks(&self, name: &str, start: usize, end: usize) -> OwnResult<Vec<Range<usize>>> {
        let e = self.entry(name)?;
        Ok(e.n_blocks
            .iter()
            .filter(|b| b.start < end && start < b.end)
            .cloned()
            .collect())
    }

    /// Soft-masked blocks intersecting `[start, end)`.
    pub fn soft_blocks(
        &self,
        name: &str,
        start: usize,
        end: usize,
    ) -> OwnResult<Vec<Range<usize>>> {
        let e = self.entry(name)?;
        Ok(e.soft_blocks
            .iter()
            .filter(|b| b.start < end && start < b.end)
            .cloned()
            .collect())
    }

    /// Decode bases `[start, end)` of a chromosome. `softmask` enables
    /// lowercase output inside soft-mask blocks (N always upper).
    pub fn read_sequence(
        &self,
        name: &str,
        start: usize,
        end: usize,
        softmask: bool,
    ) -> OwnResult<String> {
        let e = self.entry(name)?;
        let start = start.min(e.size);
        let end = end.min(e.size);
        if start >= end {
            return Ok(String::new());
        }
        if end > e.size {
            return err("range beyond chromosome end");
        }

        let mut out = vec![0u8; end - start];
        for (k, slot) in out.iter_mut().enumerate() {
            let i = start + k;
            let byte = self.buf[e.packed_offset + i / 4];
            let shift = 6 - 2 * (i % 4);
            *slot = BASES[((byte >> shift) & 3) as usize];
        }
        apply_blocks(&mut out, start, &e.n_blocks, b'N');
        if softmask {
            apply_blocks(&mut out, start, &e.soft_blocks, 0);
        }
        String::from_utf8(out).map_err(|_| OwnError("decoded sequence not ASCII".into()))
    }
}

/// Overwrite `out` (window starting at genomic `start`) inside `blocks`.
/// `repl = b'N'` hard-masks; `repl = 0` lowercases in place.
fn apply_blocks(out: &mut [u8], start: usize, blocks: &[Range<usize>], repl: u8) {
    let window = start..start + out.len();
    for b in blocks {
        if b.start >= window.end || b.end <= window.start {
            continue;
        }
        let s = b.start.max(window.start) - window.start;
        let t = b.end.min(window.end) - window.start;
        for c in &mut out[s..t] {
            if repl == 0 {
                *c = c.to_ascii_lowercase();
            } else {
                *c = repl;
            }
        }
    }
}
