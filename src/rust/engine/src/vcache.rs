//! P3 lane batch V memoization (parity plan P3, "intra-batch memory
//! sharing").
//!
//! The serving bridge (R/kernel-bridge.R, `kp_serve_unit`) renders each
//! unit's V grid ONCE and hard-links it into the fifty case directories, so
//! a fifty-case batch otherwise asks the kernel to decode and validate
//! byte-identical inputs fifty times. This module shares the decoded read
//! inside one batch process: cache identity is the FILE identity (device,
//! inode, byte length, and the kernel-reported mtime/ctime seconds --
//! `std::os::unix`, no content hashing), and a hit hands back a clone of
//! the same `Rc`.
//!
//! The laws, pinned by `tests/batch_v_cache.rs`:
//!   * the decoded bytes are exactly the certified CSV route's output --
//!     this module holds the single implementation of that route and the
//!     CLI's reader is a thin delegate to it, so fault TEXT cannot drift;
//!   * faults are fail-closed and never cached;
//!   * any move of the bytes under a name (length, or the kernel's
//!     mtime/ctime seconds, moved) forces a fresh decode. The same-inode,
//!     same-length, same-clock-second rewrite is the one theoretical stale
//!     window: unreachable under the serving law that case bytes are
//!     written once and then read-only (campaign law, attested input
//!     hashes), and every emitted byte is gated downstream by the P2
//!     bit-identity family regardless;
//!   * two distinct files never fold together, even when their bytes are
//!     equal (content hashing would fold them -- identity must not).

use std::collections::hash_map::HashMap;
use std::fs;
use std::path::Path;
use std::rc::Rc;

use crate::error::MsError;
use crate::nmf::validate_shape;

#[cfg(unix)]
use std::os::unix::fs::MetadataExt;

/// Entries a single batch cache may hold before it self-clears. A batch
/// serves one unit (fifty cases); the bound only bounds pathological
/// long-lived reuse and keeps the cache from becoming unbounded state.
const CAP: usize = 4096;

/// The certified CSV reader, moved VERBATIM from the batch entry's
/// `read_csv` (same text, same faults) so the cache and the CLI share one
/// route: a reader fork is a second implementation, and second
/// implementations are how byte laws die.
pub fn read_certified_csv(path: &Path, expect_len: usize, label: &str) -> Result<Vec<f64>, String> {
    let text = fs::read_to_string(path)
        .map_err(|e| format!("cannot read {label} at {}: {e}", path.display()))?;
    let mut out = Vec::with_capacity(expect_len);
    for (line_no, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        for tok in line.split(',') {
            let tok = tok.trim();
            if tok.is_empty() {
                return Err(format!("{label}: empty field on line {}", line_no + 1));
            }
            let v: f64 = tok
                .parse()
                .map_err(|e| format!("{label} line {}: parse `{tok}`: {e}", line_no + 1))?;
            out.push(v);
        }
    }
    if out.len() != expect_len {
        return Err(format!(
            "{label}: expected {expect_len} values, got {}",
            out.len()
        ));
    }
    Ok(out)
}

#[cfg(unix)]
#[derive(Hash, PartialEq, Eq, Clone, Copy, Debug)]
struct Key {
    dev: u64,
    ino: u64,
    len: u64,
    mtime: i64,
    ctime: i64,
}

/// The per-process V memo. One instance per batch (the batch entry builds
/// it before the case loop); nothing about a fit's RESULT is ever held --
/// only the shared, already validated input bytes.
#[derive(Debug, Default)]
pub struct VCache {
    #[cfg(unix)]
    entries: HashMap<Key, Rc<Vec<f64>>>,
}

impl VCache {
    /// A fresh (empty) cache. Batch-scoped by convention.
    pub fn new() -> VCache {
        #[cfg(unix)]
        {
            VCache {
                entries: HashMap::new(),
            }
        }
        #[cfg(not(unix))]
        {
            VCache {}
        }
    }

    /// Decode and validate one case's V storage, sharing bytes inside this
    /// cache on file identity. Errors arrive as the certified reader's own
    /// strings (and the certified shape law's text), so the CLI's
    /// structured-failure surface does not move under the memoization.
    pub fn decode(
        &mut self,
        path: &Path,
        m: usize,
        n: usize,
        k: usize,
    ) -> Result<Rc<Vec<f64>>, String> {
        let want = m.saturating_mul(n);
        #[cfg(unix)]
        {
            // A stat failure falls through to the fresh read: the reader
            // then reports the true fault in its certified words (e.g. the
            // missing-file text the CLI has always printed).
            if let Ok(md) = fs::metadata(path) {
                let key = Key {
                    dev: md.dev(),
                    ino: md.ino(),
                    len: md.len(),
                    mtime: md.mtime(),
                    ctime: md.ctime(),
                };
                if let Some(hit) = self.entries.get(&key) {
                    return Ok(hit.clone());
                }
                let fresh = Rc::new(decode_fresh(path, want, m, n, k)?);
                if self.entries.len() >= CAP {
                    self.entries.clear();
                }
                self.entries.insert(key, fresh.clone());
                return Ok(fresh);
            }
        }
        decode_fresh(path, want, m, n, k).map(Rc::new)
    }
}

/// Read + shape law for one V file (the shape law runs here exactly once
/// per miss; fits keep validating as they always did -- depth, not doubt).
fn decode_fresh(
    path: &Path,
    want: usize,
    m: usize,
    n: usize,
    k: usize,
) -> Result<Vec<f64>, String> {
    let v = read_certified_csv(path, want, "V.csv")?;
    let (): () = validate_shape(&v, m, n, k).map_err(|e: MsError| format!("{e}"))?;
    Ok(v)
}
