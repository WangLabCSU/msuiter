//! 2bit reference-genome fast path (U-M1s-08; ADR 0001).
//!
//! A read-only, random-access view over a memory-resident UCSC 2bit file,
//! wrapping `twobit::TwoBitFile` in the shape adjudicated by
//! `docs/adr/0001-twobit-reader-choice.md`: the buffer is mapped or loaded
//! by the CALLER and handed over as a byte slice (ADR 0001 §6: input is an
//! `AsRef<[u8]>` buffer). The production shape is a read-only
//! `memmap2::Mmap` built per top-level call and dropped with it (FFI
//! contract 1, D12: stateless, "map, use, release" — no handle outlives
//! the call; the object lifetime equals the call lifetime). Constructing
//! the mapping itself lives outside this crate because `Mmap::map` is
//! `unsafe` and catalog is `#![forbid(unsafe_code)]` (ARCHITECTURE §2);
//! the mapping belongs to the FFI shell, upstream of catalog in the
//! ffi → catalog → engine direction.
//!
//! Layout handling is delegated to the `twobit` crate and pinned by the
//! test suite (`tests/genome/`, ported from the U-M0-02 spike): the magic
//! number and its byte-reversed value select little- vs big-endian field
//! decoding (all u32 fields swapped on big-endian files; index `nameSize`
//! is 1 byte), 2 bit/base packing is first-base-in-high-bits with
//! T=0/C=1/A=2/G=3, and version != 0 is rejected.
//!
//! Base semantics handed to the SBS channel arithmetic:
//!
//! * bytes are uppercase `ACGT`, or `N` at hard-masked (gap) blocks —
//!   passed through verbatim; what to do with `N` is the channel layer's
//!   policy, not this module's;
//! * soft-masked (lowercase repeat) blocks are NOT applied — output stays
//!   uppercase (`enable_softmask(false)`, the crate default, is never
//!   switched on here), so reference bytes are layout-stable across
//!   mask annotation differences.
//!
//! Batching: a batched `contexts(same-chrom, sorted positions)` API is
//! deliberately deferred. `TwoBitFile` seeks per range read, so a sorted
//! same-chromosome sweep would only save index lookups (a linear scan over
//! ~dozens of names) and per-call branch setup — measurable only once the
//! tally wiring (U-M1s-09+) profiles real variant densities. The single
//! `context` call is the contract the channel layer codes against.

use std::io::Cursor;

use msuiter_engine::MsError;
use twobit::TwoBitFile;

/// A read-only 2bit genome parsed from an in-memory buffer.
///
/// Borrow-based: the buffer (`&mmap[..]` of a read-only mapping in
/// production) must outlive the genome object, and both drop together at
/// the end of the top-level call — catalog holds no file handle and no
/// mapping of its own (D12 statelessness).
pub struct TwoBitGenome<'a> {
    /// Zero-copy view: `Cursor<&[u8]>` implements `Read + Seek` directly
    /// over the caller's bytes; the header/index is parsed once here and
    /// sequence reads seek to `(offset, i/4)` per request.
    file: TwoBitFile<Cursor<&'a [u8]>>,
}

impl std::fmt::Debug for TwoBitGenome<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Manual impl: the wrapped reader type is not `Debug`.
        f.debug_struct("TwoBitGenome")
            .field("chroms", &self.file.chrom_names())
            .finish()
    }
}

impl<'a> TwoBitGenome<'a> {
    /// Parse a 2bit genome from a byte buffer (the caller-mapped reference).
    ///
    /// Malformed input (bad magic, non-zero version, truncated header or
    /// index) is a structured [`MsError`] with topic `"format"` or `"io"`,
    /// never a panic.
    pub fn from_bytes(buf: &'a [u8]) -> Result<Self, MsError> {
        let file = TwoBitFile::from_buf(buf).map_err(map_twobit_error)?;
        Ok(Self { file })
    }

    /// Chromosome names in file (index) order.
    #[must_use]
    pub fn chrom_names(&self) -> Vec<String> {
        self.file.chrom_names()
    }

    /// Length of one chromosome in bases.
    ///
    /// Errors with topic `"argument"` if `chrom` is not in the file.
    pub fn chrom_size(&self, chrom: &str) -> Result<usize, MsError> {
        self.file
            .sequence_info()
            .into_iter()
            .find(|seq| seq.chr == chrom)
            .map(|seq| seq.length)
            .ok_or_else(|| unknown_chromosome(chrom))
    }

    /// Reference context bases around a 0-based position.
    ///
    /// Returns the `flank5 + flank3 + 1` bytes of
    /// `[pos0 - flank5, pos0 + flank3]` (both ends inclusive, so the
    /// substitution site sits at index `flank5`) — uppercase `ACGT` or
    /// `N`, soft-mask disabled (module docs).
    ///
    /// # Errors
    ///
    /// * topic `"argument"`: `chrom` not in the file;
    /// * topic `"bounds"` with 1-based `i`/`j` (R convention): `i` is the
    ///   1-based position (`pos0 + 1`); `j` is `chrom_size` when the
    ///   position itself is out of range, otherwise the offending 1-based
    ///   window coordinate (the requested first base `pos0 - flank5 + 1`
    ///   when it dips below 1, or the requested last base
    ///   `pos0 + flank3 + 1` when it exceeds the chromosome length).
    ///   Windows are never clamped: a clipped context would silently
    ///   mislabel channel flanks downstream.
    pub fn context(
        &mut self,
        chrom: &str,
        pos0: usize,
        flank5: usize,
        flank3: usize,
    ) -> Result<Vec<u8>, MsError> {
        let size = self.chrom_size(chrom)?;
        if pos0 >= size {
            let pos1 = coord1(pos0).saturating_add(1);
            return Err(bounds_error(
                pos1,
                coord1(size),
                format!("position {pos1} outside chromosome \"{chrom}\" of length {size}"),
            ));
        }
        // Position is interior from here on; `pos0 + 1` cannot overflow
        // until `size` approaches `usize::MAX` (saturated rendering below).
        let pos1 = coord1(pos0).saturating_add(1);
        // Head check first, then tail; both report the offending 1-based
        // window coordinate in `j` (documented above). i128 arithmetic in
        // the error paths keeps extreme flank values panic-free.
        let Some(start) = pos0.checked_sub(flank5) else {
            let first1 = (i128::from(coord1(pos0)) - i128::from(coord1(flank5)) + 1) as i64;
            return Err(bounds_error(
                pos1,
                first1,
                format!(
                    "context window starts at {first1}, before chromosome \"{chrom}\" (position {pos1}, flank5 {flank5})"
                ),
            ));
        };
        let Some(end0) = pos0.checked_add(flank3) else {
            return Err(bounds_error(
                pos1,
                i64::MAX,
                format!(
                    "context window end overflows for chromosome \"{chrom}\" (position {pos1}, flank3 {flank3})"
                ),
            ));
        };
        if end0 >= size {
            // `end0` may equal `usize::MAX` (e.g. `flank3 = usize::MAX` at
            // position 0), so the 1-based rendering saturates.
            let last1 = coord1(end0).saturating_add(1);
            return Err(bounds_error(
                pos1,
                last1,
                format!(
                    "context window ends at {last1}, past chromosome \"{chrom}\" of length {size} (position {pos1}, flank3 {flank3})"
                ),
            ));
        }
        // `twobit::read_sequence` clamps out-of-range bounds silently; the
        // checks above guarantee the window is fully interior, so the read
        // is exactly `flank5 + flank3 + 1` bases.
        let seq = self
            .file
            .read_sequence(chrom, start..end0 + 1)
            .map_err(map_twobit_error)?;
        debug_assert_eq!(seq.len(), flank5 + flank3 + 1);
        Ok(seq.into_bytes())
    }
}

/// 1-based rendering of a 0-based coordinate, saturating at `i64::MAX`
/// (error payloads must never panic on extreme flank values).
fn coord1(v: usize) -> i64 {
    i64::try_from(v).unwrap_or(i64::MAX)
}

fn unknown_chromosome(chrom: &str) -> MsError {
    MsError::new(
        "argument",
        format!("chromosome \"{chrom}\" not found in 2bit genome"),
    )
}

fn bounds_error(i: i64, j: i64, message: String) -> MsError {
    MsError::new("bounds", message).with_i(i).with_j(j)
}

/// Map a `twobit` error onto the workspace `MsError` topic vocabulary
/// (`docs/ARCHITECTURE.md` §3.5: `msuiter_error_<topic>` payloads).
fn map_twobit_error(err: twobit::Error) -> MsError {
    match err {
        twobit::Error::IO(e) => MsError::new("io", e.to_string()),
        twobit::Error::FileFormat(msg) => MsError::new("format", msg),
        twobit::Error::UnsupportedVersion(v) => MsError::new(
            "format",
            format!("2bit version {v} not supported (only version 0)"),
        ),
        twobit::Error::MissingName(name) => unknown_chromosome(&name),
        twobit::Error::BadNucleotide(c) => MsError::new(
            "format",
            format!("invalid nucleotide byte '{c}' in 2bit file"),
        ),
    }
}
