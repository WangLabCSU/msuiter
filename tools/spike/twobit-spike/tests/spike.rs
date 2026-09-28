//! U-M0-02 spike tests: fixture (LE + BE layouts) x {twobit crate, own
//! reader} — every output must match ground truth bit-for-bit, and both
//! readers must agree with each other on both layouts.

use std::io::Write as _;
use std::ops::Range;

use twobit::TwoBitFile;

use twobit_spike::fixture::{build, Endian};
use twobit_spike::{own, specs, windows};

fn blocks(v: &[(usize, usize)]) -> Vec<Range<usize>> {
    v.iter().map(|&(s, l)| s..s + l).collect()
}

/// Full truth assertion for one reader arm over one fixture layout.
macro_rules! truth_suite {
    ($open:expr, $layouts:expr) => {{
        let fixture = $open;
        for chrom in &fixture.chroms {
            // chrom sizes and names
            assert!($layouts.chrom_names().contains(&chrom.name));
            let idx = $layouts
                .chrom_names()
                .iter()
                .position(|n| n == &chrom.name)
                .unwrap();
            assert_eq!($layouts.chrom_sizes()[idx], chrom.size, "{}", chrom.name);

            // full sequence (soft-mask off)
            let seq = $layouts.read_sequence(&chrom.name, ..).unwrap();
            assert_eq!(seq.len(), chrom.size);
            assert_eq!(seq, chrom.sequence, "{} full sequence", chrom.name);

            // full sequence with soft masks enabled
            let seq_soft = $layouts
                .clone_soft()
                .read_sequence(&chrom.name, ..)
                .unwrap();
            assert_eq!(seq_soft, chrom.sequence_soft, "{} soft sequence", chrom.name);

            // windows
            for &(s, e) in &windows(chrom.size) {
                let w = $layouts.read_sequence(&chrom.name, s..e).unwrap();
                assert_eq!(w, fixture.seq_range(&chrom.name, s, e), "{} window {s}..{e}", chrom.name);
            }

            // N blocks (hard masked)
            let got_n = $layouts.hard_masked_blocks(&chrom.name, ..).unwrap();
            assert_eq!(got_n, blocks(&chrom.n_blocks), "{} N blocks", chrom.name);

            // soft blocks
            let got_soft = $layouts.soft_masked_blocks(&chrom.name, ..).unwrap();
            assert_eq!(got_soft, blocks(&chrom.soft_blocks), "{} soft blocks", chrom.name);
        }
    }};
}

/// Helper wrapper giving the macro a uniform interface over the crate
/// reader (which needs &mut for reads and a clone for the soft-mask
/// variant) — the own reader is handled by an adapter below.
struct CrateArm<'a> {
    file: TwoBitFile<std::io::Cursor<Vec<u8>>>,
    soft: TwoBitFile<std::io::Cursor<Vec<u8>>>,
    _marker: std::marker::PhantomData<&'a ()>,
}

impl CrateArm<'_> {
    fn chrom_names(&self) -> Vec<String> {
        self.file.chrom_names()
    }
    fn chrom_sizes(&self) -> Vec<usize> {
        self.file.chrom_sizes()
    }
    fn read_sequence(
        &mut self,
        chr: &str,
        r: impl std::ops::RangeBounds<usize>,
    ) -> twobit::Result<String> {
        self.file.read_sequence(chr, r)
    }
    fn clone_soft(&mut self) -> SoftArm<'_> {
        SoftArm { file: &mut self.soft }
    }
    fn hard_masked_blocks(
        &mut self,
        chr: &str,
        r: impl std::ops::RangeBounds<usize>,
    ) -> twobit::Result<Vec<Range<usize>>> {
        self.file.hard_masked_blocks(chr, r)
    }
    fn soft_masked_blocks(
        &mut self,
        chr: &str,
        r: impl std::ops::RangeBounds<usize>,
    ) -> twobit::Result<Vec<Range<usize>>> {
        self.file.soft_masked_blocks(chr, r)
    }
}

struct SoftArm<'a> {
    file: &'a mut TwoBitFile<std::io::Cursor<Vec<u8>>>,
}

impl SoftArm<'_> {
    fn read_sequence(&mut self, chr: &str, r: impl std::ops::RangeBounds<usize>) -> twobit::Result<String> {
        self.file.read_sequence(chr, r)
    }
}

/// Adapter over the own reader with the same method shape.
struct OwnArm<'a> {
    file: own::OwnTwoBit<'a>,
    softmask: bool,
}

impl OwnArm<'_> {
    fn chrom_names(&self) -> Vec<String> {
        self.file.chrom_names()
    }
    fn chrom_sizes(&self) -> Vec<usize> {
        self.file.chrom_sizes()
    }
    fn read_sequence(
        &mut self,
        chr: &str,
        r: impl std::ops::RangeBounds<usize>,
    ) -> own::OwnResult<String> {
        let (s, e) = bounds(r);
        self.file.read_sequence(chr, s, e, self.softmask)
    }
    fn clone_soft(&mut self) -> OwnSoftArm<'_> {
        OwnSoftArm { file: &self.file }
    }
    fn hard_masked_blocks(
        &mut self,
        chr: &str,
        _r: impl std::ops::RangeBounds<usize>,
    ) -> own::OwnResult<Vec<Range<usize>>> {
        self.file.n_blocks(chr, 0, usize::MAX)
    }
    fn soft_masked_blocks(
        &mut self,
        chr: &str,
        _r: impl std::ops::RangeBounds<usize>,
    ) -> own::OwnResult<Vec<Range<usize>>> {
        self.file.soft_blocks(chr, 0, usize::MAX)
    }
}

struct OwnSoftArm<'a> {
    file: &'a own::OwnTwoBit<'a>,
}

impl OwnSoftArm<'_> {
    fn read_sequence(&mut self, chr: &str, r: impl std::ops::RangeBounds<usize>) -> own::OwnResult<String> {
        let (s, e) = bounds(r);
        self.file.read_sequence(chr, s, e, true)
    }
}

fn bounds(r: impl std::ops::RangeBounds<usize>) -> (usize, usize) {
    use std::ops::Bound::*;
    let s = match r.start_bound() {
        Included(&v) => v,
        Excluded(&v) => v + 1,
        Unbounded => 0,
    };
    let e = match r.end_bound() {
        Included(&v) => v + 1,
        Excluded(&v) => v,
        Unbounded => usize::MAX,
    };
    (s, e)
}

#[test]
fn crate_reads_little_endian_fixture() {
    let fixture = build(&specs(), Endian::Little);
    let file = TwoBitFile::from_buf(fixture.bytes.clone()).unwrap();
    let soft = TwoBitFile::from_buf(fixture.bytes.clone()).unwrap().enable_softmask(true);
    let mut arm = CrateArm { file, soft, _marker: std::marker::PhantomData };
    truth_suite!(&fixture, arm);
}

#[test]
fn crate_reads_big_endian_fixture() {
    let fixture = build(&specs(), Endian::Big);
    let file = TwoBitFile::from_buf(fixture.bytes.clone()).unwrap();
    let soft = TwoBitFile::from_buf(fixture.bytes.clone()).unwrap().enable_softmask(true);
    let mut arm = CrateArm { file, soft, _marker: std::marker::PhantomData };
    truth_suite!(&fixture, arm);
}

#[test]
fn own_reads_little_endian_fixture() {
    let fixture = build(&specs(), Endian::Little);
    let reader = own::OwnTwoBit::from_slice(&fixture.bytes).unwrap();
    assert!(!reader.endian_swapped());
    let mut arm = OwnArm { file: reader, softmask: false };
    truth_suite!(&fixture, arm);
}

#[test]
fn own_reads_big_endian_fixture() {
    let fixture = build(&specs(), Endian::Big);
    let reader = own::OwnTwoBit::from_slice(&fixture.bytes).unwrap();
    assert!(reader.endian_swapped(), "BE layout must be detected");
    let mut arm = OwnArm { file: reader, softmask: false };
    truth_suite!(&fixture, arm);
}

/// Both readers must agree bit-for-bit on both layouts, full sequences
/// and all windows.
#[test]
fn crate_and_own_readers_agree_on_both_layouts() {
    for endian in [Endian::Little, Endian::Big] {
        let fixture = build(&specs(), endian);
        let mut cfile = TwoBitFile::from_buf(fixture.bytes.clone()).unwrap();
        let mut csoft = TwoBitFile::from_buf(fixture.bytes.clone()).unwrap().enable_softmask(true);
        let oreader = own::OwnTwoBit::from_slice(&fixture.bytes).unwrap();

        for chrom in &fixture.chroms {
            assert_eq!(
                cfile.read_sequence(&chrom.name, ..).unwrap(),
                oreader.read_sequence(&chrom.name, 0, usize::MAX, false).unwrap(),
                "{endian:?} {} full", chrom.name
            );
            for &(s, e) in &windows(chrom.size) {
                assert_eq!(
                    cfile.read_sequence(&chrom.name, s..e).unwrap(),
                    oreader.read_sequence(&chrom.name, s, e, false).unwrap(),
                    "{endian:?} {} window {s}..{e}", chrom.name
                );
            }
            assert_eq!(
                cfile.hard_masked_blocks(&chrom.name, ..).unwrap(),
                oreader.n_blocks(&chrom.name, 0, usize::MAX).unwrap(),
                "{endian:?} {} N blocks", chrom.name
            );
            assert_eq!(
                cfile.soft_masked_blocks(&chrom.name, ..).unwrap(),
                oreader.soft_blocks(&chrom.name, 0, usize::MAX).unwrap(),
                "{endian:?} {} soft blocks", chrom.name
            );

            // soft-mask-enabled agreement
            assert_eq!(
                csoft.read_sequence(&chrom.name, ..).unwrap(),
                oreader.read_sequence(&chrom.name, 0, usize::MAX, true).unwrap(),
                "{endian:?} {} soft full", chrom.name
            );
        }
    }
}

/// The exact D7 integration shape: `TwoBitFile` over `Cursor<Mmap>` of a
/// real file on disk, both layouts.
#[test]
fn crate_over_cursor_mmap_both_layouts() {
    for endian in [Endian::Little, Endian::Big] {
        let fixture = build(&specs(), endian);
        let path = std::env::temp_dir().join(format!(
            "msuiter-spike-{:?}.2bit",
            std::process::id()
        ));
        {
            let mut f = std::fs::File::create(&path).unwrap();
            f.write_all(&fixture.bytes).unwrap();
            f.flush().unwrap();
        }
        let mmap = unsafe { memmap2::Mmap::map(&std::fs::File::open(&path).unwrap()).unwrap() };
        // `Cursor<&Mmap>: Read + Seek` via `&Mmap: AsRef<[u8]>` — the
        // literal D7 shape "twobit crate over Cursor<Mmap>", zero-copy.
        let mut file = TwoBitFile::from_buf(&mmap).unwrap();
        assert_eq!(file.chrom_names(), fixture.chroms.iter().map(|c| c.name.clone()).collect::<Vec<_>>());
        assert_eq!(file.chrom_sizes(), fixture.chroms.iter().map(|c| c.size).collect::<Vec<_>>());
        for chrom in &fixture.chroms {
            let seq = file.read_sequence(&chrom.name, ..).unwrap();
            assert_eq!(seq, chrom.sequence, "{endian:?} mmap {}", chrom.name);
        }
        // Own reader over the same mmap slice (in-house mmap shape).
        let oreader = own::OwnTwoBit::from_slice(&mmap[..]).unwrap();
        for chrom in &fixture.chroms {
            assert_eq!(
                oreader.read_sequence(&chrom.name, 0, usize::MAX, false).unwrap(),
                chrom.sequence
            );
        }
        std::fs::remove_file(&path).unwrap();
    }
}

/// Refusal of garbage input on both arms (magic check).
#[test]
fn both_readers_reject_bad_magic() {
    let mut bytes = build(&specs(), Endian::Little).bytes;
    bytes[0] ^= 0xff;
    assert!(TwoBitFile::from_buf(bytes.clone()).is_err());
    assert!(own::OwnTwoBit::from_slice(&bytes).is_err());
}
