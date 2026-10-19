//! P3 lane batch memoization law: one decoded V per distinct file, per batch.
//!
//! The serving bridge (R/kernel-bridge.R, `kp_serve_unit`) renders each
//! unit's V grid ONCE and hard-links it into the fifty case directories, so
//! a fifty-case batch asks the kernel to decode and validate byte-identical
//! inputs fifty times. The parity-plan P3 charter (lane 3, "intra-batch
//! memory sharing") authorizes sharing that decoded read — red-by-absence
//! here against `msuiter_engine::vcache::VCache`, the engine face the batch
//! entry will use.
//!
//! The law this file pins, in order:
//!   1. two requests for the SAME path hand back the SAME Rc (zero-copy
//!      sharing, the point of the exercise) with the naive-parse bytes
//!      bit-for-bit (`assert_eq!` on the Vec);
//!   2. a hard-linked alias of that path shares the same Rc (that is the
//!      bridge's layout, so it is the contract that must work);
//!   3. a distinct file with equal bytes does NOT share (identity is the
//!      key, not content hashing — no false aliasing across cases);
//!   4. any move of the bytes under a name (length or mtime moved) forces
//!      a fresh decode of the NEW bytes;
//!   5. faults are fail-closed and never cached: a bad file errors now and
//!      errors again later, and fixing the file then decodes clean;
//!   6. decode enforces the certified shape law (`validate_shape`) before
//!      anything is handed out.

use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};

use msuiter_engine::vcache::VCache;

static COUNTER: AtomicUsize = AtomicUsize::new(0);

/// A temp directory removed on drop (same idiom as kernel_cli_protocol.rs).
struct Tmp(PathBuf);

impl Tmp {
    fn new(tag: &str) -> Tmp {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let mut cand = std::env::temp_dir();
        cand.push(format!("msuiter-vcache-{}-{tag}-{n}", std::process::id()));
        fs::create_dir_all(&cand).expect("create tmpdir");
        assert!(cand.is_dir(), "tmp path collides with a non-directory");
        Tmp(cand)
    }
    fn join(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for Tmp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// The naive reader: the CLI's own CSV law, verbatim (comma-separated
/// tokens, trimmed, blank lines skipped, strict length), parsed straight
/// into f64 — the byte-standard the cache must reproduce exactly.
fn naive_read(path: &Path, want: usize) -> Vec<f64> {
    let text = fs::read_to_string(path).expect("read");
    let mut out = Vec::with_capacity(want);
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        for tok in line.split(',') {
            out.push(tok.trim().parse::<f64>().expect("token"));
        }
    }
    assert_eq!(out.len(), want, "fixture length");
    out
}

/// Write a matrix as the kernel's bit-exact %.17e CSV face.
fn write_grid(path: &Path, m: usize, n: usize, mut i: usize) {
    let mut s = String::new();
    for _r in 0..m {
        for c in 0..n {
            if c > 0 {
                s.push(',');
            }
            // Positive, finite, distinct per position; `i` advances per cell.
            let x = 1.0 + (i as f64) * 0.037_531_517;
            s.push_str(&format!("{x:.17e}"));
            i += 1;
        }
        s.push('\n');
    }
    fs::write(path, s).expect("write");
}

const M: usize = 9;
const N: usize = 7;
const K: usize = 2;
const MN: usize = M * N;

#[test]
fn same_path_shares_one_decoding_bit_exactly() {
    let t = Tmp::new("same");
    let p = t.join("V.csv");
    write_grid(&p, M, N, 0);
    let want = naive_read(&p, MN);
    let mut c = VCache::new();
    let a = c.decode(&p, M, N, K).expect("decode a");
    let b = c.decode(&p, M, N, K).expect("decode b");
    assert!(Rc::ptr_eq(&a, &b), "same path must hand back one shared decoding");
    assert_eq!(*a, want, "shared decoding must be the naive bytes exactly");
}

#[test]
fn hardlinked_alias_shares_the_decoding() {
    // The bridge's layout itself: fifty names, one inode, one decoding.
    let t = Tmp::new("link");
    let p = t.join("shared.csv");
    write_grid(&p, M, N, 0);
    let mut c = VCache::new();
    let a = c.decode(&p, M, N, K).expect("decode base");
    for i in 0..3 {
        let alias = t.join(&format!("case{i}.csv"));
        fs::hard_link(&p, &alias).expect("hard_link");
        let got = c.decode(&alias, M, N, K).expect("decode alias");
        assert!(Rc::ptr_eq(&a, &got), "hard-linked name {i} must share the base decoding");
        assert_eq!(*got, *a, "alias bytes");
    }
}

#[test]
fn equal_bytes_under_different_names_do_not_share() {
    // Keyed on file identity, never content: two distinct files holding
    // equal bytes are two entries. (No cross-case false aliasing if a
    // campaign ever writes distinct grids of equal value.)
    let t = Tmp::new("distinct");
    let a_p = t.join("a.csv");
    let b_p = t.join("b.csv");
    write_grid(&a_p, M, N, 0);
    fs::copy(&a_p, &b_p).expect("copy");
    let mut c = VCache::new();
    let a = c.decode(&a_p, M, N, K).expect("decode a");
    let b = c.decode(&b_p, M, N, K).expect("decode b");
    assert_eq!(*a, *b, "contents equal by construction");
    assert!(!Rc::ptr_eq(&a, &b), "distinct files must not be folded into one entry");
}

#[test]
fn bytes_moved_under_a_name_force_a_fresh_decode() {
    let t = Tmp::new("move");
    let p = t.join("V.csv");
    write_grid(&p, M, N, 0);
    let mut c = VCache::new();
    let a = c.decode(&p, M, N, K).expect("decode before");
    std::thread::sleep(std::time::Duration::from_millis(1_100)); // second-granularity clock key: the move must cross a tick
    write_grid(&p, M, N, 500); // same length, different bytes, clock moves
    let b = c.decode(&p, M, N, K).expect("decode after");
    assert!(!Rc::ptr_eq(&a, &b), "a moved file must not serve stale bytes");
    assert_eq!(*b, naive_read(&p, MN), "fresh decode must see the new bytes");
    let c2 = c.decode(&p, M, N, K).expect("decode after again");
    assert!(Rc::ptr_eq(&b, &c2), "the fresh bytes are now the shared entry");
}

#[test]
fn shape_and_parse_faults_are_fail_closed_and_never_cached() {
    let t = Tmp::new("fault");
    let p = t.join("V.csv");
    fs::write(&p, "1.0,2.0,3.0\n").expect("short file");
    let mut c = VCache::new();
    assert!(c.decode(&p, M, N, K).is_err(), "a short grid must fault");
    assert!(c.decode(&p, M, N, K).is_err(), "the fault must not have been cached as a value");
    fs::write(&p, "1.0,-2.0\n").expect("neg file");
    assert!(c.decode(&p, 1, 2, K).is_err(), "a negative entry must fault (validate_shape law)");
    write_grid(&p, M, N, 90);
    let ok = c.decode(&p, M, N, K).expect("a repaired file must decode clean");
    assert_eq!(*ok, naive_read(&p, MN), "repaired decode bytes");
}
