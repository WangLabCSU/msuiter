//! `msuiter-kernel` — the stable batch entry of the isolated-process
//! boundary (P1 kernel-extension face (d); parity plan
//! `docs/research/09-sigminer-v3-parity-plan.md` §5 row P1 and §7
//! P1-kickoff resolution, controller ruling 2026-10-14 / PR #23).
//!
//! The sigminer side will consume the certified in-house Apache-2.0 KL-MU
//! kernel through a Suggests-gated isolated process (`system(cmds)` +
//! reticulate precedent `R/sigprofiler.R:96,199` in the sigminer tree).
//! This binary is the msuiter-side half of that boundary: a frozen,
//! version-stamped CSV protocol around the UNMODIFIED engine kernels —
//! `nmf::fit_kl_with_init` / `nmf::fit_kl_on_stream` for the fit and
//! `nndsvd::nndsvda_init`/`nndsvd_init` for the optional initializers —
//! so the future consumer can never diverge into a second implementation.
//!
//! # Protocol (v1 — frozen; breaking changes bump PROTOCOL)
//!
//! ```text
//! msuiter-kernel --version
//!   -> stdout: "msuiter-kernel protocol=1 engine=\"<CRATE_ROLE>\" kl_eps=1e-12"
//!
//! msuiter-kernel fit-kl --in DIR --out DIR --m M --n N --k K --iters T
//!                       [--init external|seeded|nndsvd|nndsvda]
//!                       [--seed S] [--replicate R] [--dump-at t1,t2,...]
//!                       [--full-trace]
//!   reads  IN/V.csv, IN/W0.csv, IN/H0.csv          (init=external)
//!   writes OUT/{W.csv, H.csv, trace.csv, meta.csv}  (+ ckXXXX/{W,H,obj}.csv)
//!
//! msuiter-kernel fit-kl --cases FILE --root INROOT --out-root OUTROOT
//!                       [--full-trace]
//!   FILE header:  case,init,seed,replicate,iters,m,n,k  (empty seed/replicate = default)
//!   per row:      reads INROOT/<case>/..., writes OUTROOT/<case>/out/...
//! ```
//!
//! * Matrices are headerless numeric CSVs, row-major, one row per line;
//!   outputs print every entry with `{:.17e}` — the bit-exact
//!   double round-trip convention established by `tools/kl-crosscheck`.
//! * `trace.csv` has the header `t,objective`; row t is the objective
//!   after t full (H step + W step) iterations, row 0 at the initializer
//!   (nmf.rs "Trace semantics"). The production default records only the
//!   two endpoints -- the row at t = 0 and, for T > 0, the row at
//!   t = max_iter -- because the MM observer never feeds the updates;
//!   `--full-trace` (legal on both surfaces) opts into the full
//!   0..=max_iter walk, the protocol-1 ceremony. The face is
//!   self-describing via the meta `trace_len` line, and both faces are
//!   byte-identical in W/H and in the endpoint witnesses (pinned by
//!   `tests/kernel_cli_protocol.rs`).
//! * `meta.csv` is `key,value` lines, self-describing and timestamp-free:
//!   two runs over equal inputs are BYTE-identical (the boundary's
//!   reproducibility contract; pinned by the protocol test suite).
//! * Exit 0 = success. Exit 2 = every argument / input / I/O / kernel
//!   fault, reported as a single `error: ...` line on stderr (the
//!   `tools/kl-crosscheck/driver` convention). Exit 1 is reserved for
//!   future gate-style verdict reporting and must not be produced here.
//! * Thread policy: the process is SINGLE-THREADED by construction (the
//!   engine kernel is sequential — ARCH §2.6 thread-invariance contract);
//!   parallel replicate sweeps are the caller's process-level job, one
//!   `--replicate R` per case row. No thread-count input exists precisely
//!   so no thread count can influence a result.
//!
//! The binary is pure std (engine crate's zero-dependency discipline),
//! carries no FFI and no `unsafe`, and is NOT part of the R package build
//! (`src/Makevars.in` builds `--lib` only); it compiles with the rest of
//! the workspace under `cargo build`/`cargo test` and the MSRV gate.

#![forbid(unsafe_code)]

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use msuiter_engine::vcache::VCache;

/// Frozen protocol version (module docs). Every `meta.csv` echoes it;
/// `--version` is the handshake.
const PROTOCOL: u64 = 1;

/// The manifest header the `--cases` file must carry, verbatim.
const BATCH_HEADER: &str = "case,init,seed,replicate,iters,m,n,k";
const BATCH_COLUMNS: usize = 8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Init {
    /// Caller-provided `W0.csv`/`H0.csv` (scheme A of the cross-checks).
    External,
    /// Engine seeded uniform init (`fit_kl_on_stream`, U-M1s-05 streams).
    Seeded,
    /// Plain NNDSVD init (zero-keeping; the zero-lock probe face).
    Nndsvd,
    /// NNDSVDa init (zeros filled with mean(V) — the zero-lock release).
    Nndsvda,
}

impl Init {
    fn parse(s: &str) -> Result<Self, String> {
        match s {
            "external" => Ok(Self::External),
            "seeded" => Ok(Self::Seeded),
            "nndsvd" => Ok(Self::Nndsvd),
            "nndsvda" => Ok(Self::Nndsvda),
            other => Err(format!(
                "invalid --init value `{other}` (supported: external|seeded|nndsvd|nndsvda)"
            )),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::External => "external",
            Self::Seeded => "seeded",
            Self::Nndsvd => "nndsvd",
            Self::Nndsvda => "nndsvda",
        }
    }
}

fn main() {
    let mut argv = std::env::args().skip(1);
    let result = match argv.next().as_deref() {        Some("--version") => {
            println!(
                "msuiter-kernel protocol={PROTOCOL} engine=\"{}\" kl_eps={:e}",
                msuiter_engine::CRATE_ROLE,
                msuiter_engine::nmf::KL_EPS
            );
            Ok(())
        }
        Some("fit-kl") => dispatch_fit_kl(&mut argv),
        Some(other) => Err(format!(
            "unknown verb `{other}` (supported: fit-kl; version handshake: --version)"
        )),
        None => {
            Err("no verb given (supported: fit-kl; version handshake: --version)".to_string())
        }
    };
    if let Err(e) = result {
        eprintln!("error: {e}");
        std::process::exit(2);
    }
}

/// One case of either the single-case or the batch surface.
#[derive(Debug, Clone)]
struct Case {
    in_dir: PathBuf,
    out_dir: PathBuf,
    m: usize,
    n: usize,
    k: usize,
    iters: usize,
    init: Init,
    seed: Option<u64>,
    /// Only meaningful for `Init::Seeded` (canonical replicate stream).
    replicate: u64,
    dump_at: Vec<usize>,
    /// True on the opted-in `--full-trace` face (one witness per iteration,
    /// the protocol-1 ceremony); false is the production default -- the
    /// terminals face, `t = 0` and `t = max_iter` only (nmf `TraceMode`).
    full_trace: bool,
}

/// Required-value helper (MSRV-safe stand-in for the 1.82 `ok_or` family).
fn need<T>(o: Option<T>, what: &str) -> Result<T, String> {
    match o {
        Some(v) => Ok(v),
        None => Err(format!("missing {what}")),
    }
}

fn dispatch_fit_kl(argv: &mut impl Iterator<Item = String>) -> Result<(), String> {
    // -- flags (single-case face)
    let mut in_dir: Option<PathBuf> = None;
    let mut out_dir: Option<PathBuf> = None;
    let mut m: Option<usize> = None;
    let mut n: Option<usize> = None;
    let mut k: Option<usize> = None;
    let mut iters: Option<usize> = None;
    let mut init = Init::External;
    let mut seed: Option<u64> = None;
    let mut replicate: Option<u64> = None;
    let mut dump_at: Vec<usize> = Vec::new();
    let mut full_trace = false;
    // -- flags (batch face)
    let mut cases: Option<PathBuf> = None;
    let mut root: Option<PathBuf> = None;
    let mut out_root: Option<PathBuf> = None;

    while let Some(flag) = argv.next() {
        match &*flag {
            "--in" => in_dir = Some(PathBuf::from(take_value(argv, &flag)?)),
            "--out" => out_dir = Some(PathBuf::from(take_value(argv, &flag)?)),
            "--m" => m = Some(parse_usize("--m", &take_value(argv, &flag)?)?),
            "--n" => n = Some(parse_usize("--n", &take_value(argv, &flag)?)?),
            "--k" => k = Some(parse_usize("--k", &take_value(argv, &flag)?)?),
            "--iters" => iters = Some(parse_usize("--iters", &take_value(argv, &flag)?)?),
            "--init" => init = Init::parse(&take_value(argv, &flag)?)?,
            "--seed" => seed = Some(parse_u64("--seed", &take_value(argv, &flag)?)?),
            "--replicate" => {
                replicate = Some(parse_u64("--replicate", &take_value(argv, &flag)?)?)
            }
            "--dump-at" => {
                let spec = take_value(argv, &flag)?;
                for tok in spec.split(',') {
                    dump_at.push(parse_usize("--dump-at entry", tok.trim())?);
                }
            }
            // Valueless face selector, legal on both surfaces (module docs:
            // the two faces differ only in observer density).
            "--full-trace" => full_trace = true,
            "--cases" => cases = Some(PathBuf::from(take_value(argv, &flag)?)),
            "--root" => root = Some(PathBuf::from(take_value(argv, &flag)?)),
            "--out-root" => out_root = Some(PathBuf::from(take_value(argv, &flag)?)),
            other => return Err(format!("unknown flag {other}")),
        }
    }

    match (cases.clone(), root.clone(), out_root.clone()) {
        (None, None, None) => {
            // Single-case face: everything the Case needs must be present
            // and coherent.
            let case = Case {
                in_dir: need(in_dir, "--in")?,
                out_dir: need(out_dir, "--out")?,
                m: need(m, "--m")?,
                n: need(n, "--n")?,
                k: need(k, "--k")?,
                iters: need(iters, "--iters")?,
                init,
                seed,
                replicate: check_replicate(init, replicate)?,
                dump_at,
                full_trace,
            };
            validate_init_args(init, case.seed)?;
            run_case(&case, &mut VCache::new())
        }
        (Some(cases), Some(root), Some(out_root)) => {
            // Batch mode: dimensions and per-case settings come from the
            // manifest; the single-case flags are meaningless there.
            if in_dir.is_some()
                || out_dir.is_some()
                || m.is_some()
                || n.is_some()
                || k.is_some()
                || iters.is_some()
                || seed.is_some()
                || replicate.is_some()
                || !dump_at.is_empty()
            {
                return Err(
                    "--cases mode takes only --cases/--root/--out-root \
                     (per-case settings live in the manifest)"
                        .to_string(),
                );
            }
            run_batch(&cases, &root, &out_root, full_trace)
        }
        _ => Err("--cases mode requires all of --cases, --root and --out-root".to_string()),
    }
}

fn take_value(argv: &mut impl Iterator<Item = String>, flag: &str) -> Result<String, String> {
    match argv.next() {
        Some(v) => Ok(v),
        None => Err(format!("missing value for {flag}")),
    }
}

// Concrete parsers (no generic FromStr bound: the trait is newer than the
// workspace MSRV).
fn parse_usize(what: &str, s: &str) -> Result<usize, String> {
    s.parse::<usize>().map_err(|e| format!("bad {what} `{s}`: {e}"))
}

fn parse_u64(what: &str, s: &str) -> Result<u64, String> {
    s.parse::<u64>().map_err(|e| format!("bad {what} `{s}`: {e}"))
}

fn check_replicate(init: Init, replicate: Option<u64>) -> Result<u64, String> {
    match (init, replicate) {
        (Init::Seeded, r) => Ok(r.unwrap_or(0)),
        (_, None) => Ok(0),
        (_, Some(_)) => {
            Err("--replicate requires --init seeded (stream addressing)".to_string())
        }
    }
}

fn validate_init_args(init: Init, seed: Option<u64>) -> Result<(), String> {
    match (init, seed) {
        (Init::External, None) => Ok(()),
        (Init::External, Some(_)) => {
            Err("--seed is meaningless with --init external".to_string())
        }
        (_, Some(_)) => Ok(()),
        (_, None) => Err(format!("--init {} requires --seed", init.as_str())),
    }
}

/// The initializers + fixed-count fit for one case, dispatched on `init`.
/// The main path and the checkpoint path share one code route (exactness
/// by the kernel's documented prefix property, not by fit-state reuse).
/// `V` is served through the batch [`VCache`]: under the serving bridge's
/// layout every restart of a unit hard-links one inode, so the shared,
/// already-validated bytes are decoded once per distinct file per batch
/// (engine `vcache` module law: identity key, fail-closed faults that are
/// never cached, any move of the bytes under a name forces a fresh
/// decode). `W0`/`H0` stay re-read from disk on every call.
fn fit_case(case: &Case, vc: &mut VCache) -> Result<msuiter_engine::nmf::NmfFit, String> {
    let label = case.init.as_str();
    let v = vc.decode(&case.in_dir.join("V.csv"), case.m, case.n, case.k)?;
    match case.init {
        Init::External => {
            let w0 = read_csv(&case.in_dir.join("W0.csv"), case.m * case.k, "W0.csv")?;
            let h0 = read_csv(&case.in_dir.join("H0.csv"), case.k * case.n, "H0.csv")?;
            kl_face(case, &v, &w0, &h0)
        }
        Init::Seeded => {
            let seed = need(case.seed, "--seed (with --init seeded)")?;
            // Frozen per-replicate stream layout of the parallel drivers
            // (U-M1s-05): replicate R on {replicate: R, rank: 0, fold: 0}.
            let stream =
                msuiter_engine::rng::StreamId { replicate: case.replicate, rank: 0, fold: 0 };
            if case.full_trace {
                msuiter_engine::nmf::fit_kl_on_stream(
                    &v, case.m, case.n, case.k, case.iters, seed, stream,
                )
                .map_err(|e| format!("fit_kl_on_stream: {e}"))
            } else {
                msuiter_engine::nmf::fit_kl_on_stream_terminals(
                    &v, case.m, case.n, case.k, case.iters, seed, stream,
                )
                .map_err(|e| format!("fit_kl_on_stream_terminals: {e}"))
            }
        }
        Init::Nndsvd | Init::Nndsvda => {
            let seed = need(case.seed, &format!("--seed (with --init {label})"))?;
            let (w0, h0) = match case.init {
                Init::Nndsvd => {
                    msuiter_engine::nndsvd::nndsvd_init(&v, case.m, case.n, case.k, seed)
                }
                _ => msuiter_engine::nndsvd::nndsvda_init(&v, case.m, case.n, case.k, seed),
            }
            .map_err(|e| format!("{label}: {e}"))?;
            kl_face(case, &v, &w0, &h0)
        }
    }
}

/// The observer-density face selector (nmf `TraceMode`): the production
/// default rides the terminals face, the opted-in `--full-trace` the
/// protocol-1 full walk. Same procedure, same certified bytes -- the
/// observer never feeds the updates (nmf module docs).
fn kl_face(
    case: &Case,
    v: &[f64],
    w0: &[f64],
    h0: &[f64],
) -> Result<msuiter_engine::nmf::NmfFit, String> {
    if case.full_trace {
        msuiter_engine::nmf::fit_kl_with_init(v, case.m, case.n, case.k, w0, h0, case.iters)
            .map_err(|e| format!("fit_kl_with_init: {e}"))
    } else {
        msuiter_engine::nmf::fit_kl_with_init_terminals(v, case.m, case.n, case.k, w0, h0, case.iters)
            .map_err(|e| format!("fit_kl_with_init_terminals: {e}"))
    }
}

fn run_case(case: &Case, vc: &mut VCache) -> Result<(), String> {
    let fit = fit_case(case, vc)?;
    emit_fit(&fit, case, vc)
}

/// Byte-stable emission: W/H as `{:.17e}` grids, the full objective trace,
/// the timestamp-free meta record, and optional state checkpoints (each a
/// re-run of the same pure fixed-count loop — same technique as the
/// kl-crosscheck driver).
fn emit_fit(fit: &msuiter_engine::nmf::NmfFit, case: &Case, vc: &mut VCache) -> Result<(), String> {
    std::fs::create_dir_all(&case.out_dir)
        .map_err(|e| format!("cannot create {}: {e}", case.out_dir.display()))?;

    write_csv(&case.out_dir.join("W.csv"), &fit.w, case.m, case.k)?;
    write_csv(&case.out_dir.join("H.csv"), &fit.h, case.k, case.n)?;

    let mut trace = String::with_capacity(fit.objective.len() * 26);
    trace.push_str("t,objective\n");
    // Row labels name iterations, never array indices: the full face walks
    // 0..=max_iter, the terminals face carries the witnesses at t = 0 and
    // t = max_iter (nmf TraceMode::Endpoints -- the second witness IS the
    // objective after the last iteration).
    if case.full_trace {
        for (t, obj) in fit.objective.iter().enumerate() {
            writeln!(trace, "{t},{obj:.17e}").map_err(|e| format!("trace fmt: {e}"))?;
        }
    } else {
        writeln!(trace, "0,{:.17e}", fit.objective[0])
            .map_err(|e| format!("trace fmt: {e}"))?;
        if let Some(&obj) = fit.objective.get(1) {
            writeln!(trace, "{},{:.17e}", case.iters, obj)
                .map_err(|e| format!("trace fmt: {e}"))?;
        }
    }
    write_str(&case.out_dir.join("trace.csv"), &trace)?;

    let mut meta = String::new();
    let final_obj = fit.objective[fit.objective.len() - 1];
    for (key, val) in [
        ("protocol", format!("{PROTOCOL}")),
        ("command", "fit-kl".to_string()),
        ("init", case.init.as_str().to_string()),
        ("seed", match case.seed { Some(s) => s.to_string(), None => "na".to_string() }),
        (
            "replicate",
            if case.init == Init::Seeded { case.replicate.to_string() } else { "na".to_string() },
        ),
        ("m", case.m.to_string()),
        ("n", case.n.to_string()),
        ("k", case.k.to_string()),
        ("iters", case.iters.to_string()),
        ("iterations", fit.iterations.to_string()),
        ("trace_len", fit.objective.len().to_string()),
        ("obj_init", format!("{:.17e}", fit.objective[0])),
        ("obj_final", format!("{:.17e}", final_obj)),
        ("eps", format!("{:e}", msuiter_engine::nmf::KL_EPS)),
        ("engine_crate", msuiter_engine::CRATE_ROLE.to_string()),
    ] {
        writeln!(meta, "{key},{val}").map_err(|e| format!("meta fmt: {e}"))?;
    }
    write_str(&case.out_dir.join("meta.csv"), &meta)?;

    let mut dump: Vec<usize> = case.dump_at.clone();
    dump.sort_unstable();
    dump.dedup();
    for &t in &dump {
        if t > case.iters {
            return Err(format!("--dump-at {t}: beyond --iters {}", case.iters));
        }
        let ck = Case { iters: t, dump_at: Vec::new(), ..case.clone() };
        let ck_fit = fit_case(&ck, vc)?;
        if ck_fit.iterations != t {
            return Err(format!("checkpoint {t}: kernel stopped at {}", ck_fit.iterations));
        }
        let dir = case.out_dir.join(format!("ck{t:04}"));
        std::fs::create_dir_all(&dir)
            .map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
        write_csv(&dir.join("W.csv"), &ck_fit.w, case.m, case.k)?;
        write_csv(&dir.join("H.csv"), &ck_fit.h, case.k, case.n)?;
        // The checkpoint re-run stopped at t, so its last recorded witness
        // IS the objective at t on either face (nmf terminals law, pinned by
        // endpoints_trace_is_the_terminals_of_the_full_trace).
        let ck_obj = ck_fit.objective[ck_fit.objective.len() - 1];
        write_str(&dir.join("obj.csv"), &format!("{:.17e}\n", ck_obj))?;
    }
    Ok(())
}

/// `--cases FILE --root INROOT --out-root OUTROOT`: one fit per manifest
/// row, `INROOT/<case>/` in, `OUTROOT/<case>/out/` out. Aborts at the
/// first faulty row (exit 2 via main) — a batch is an all-or-nothing unit.
/// The `--full-trace` face selector is process-wide (per-row columns carry
/// the per-case settings only).
fn run_batch(cases: &Path, root: &Path, out_root: &Path, full_trace: bool) -> Result<(), String> {
    let text = std::fs::read_to_string(cases)
        .map_err(|e| format!("cannot read cases manifest {}: {e}", cases.display()))?;
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let header = match lines.next() {
        Some(h) => h.trim().to_string(),
        None => return Err("cases manifest is empty".to_string()),
    };
    if header != BATCH_HEADER {
        return Err(format!("cases manifest header must be `{BATCH_HEADER}`, got `{header}`"));
    }
    let mut ran = 0usize;
    // One decoded V per distinct file for the whole batch: the serving
    // bridge hard-links one unit's V into all fifty case dirs, so fifty
    // requests are one decode (engine vcache law, tests pinned).
    let mut vc = VCache::new();
    for (no, row) in lines.enumerate() {
        let line_no = no + 2; // 1-based, header counted
        let fields: Vec<&str> = row.split(',').map(str::trim).collect();
        if fields.len() != BATCH_COLUMNS {
            return Err(format!(
                "cases manifest row {line_no}: expected {BATCH_COLUMNS} columns, got {}",
                fields.len()
            ));
        }
        let (case, init, seed, replicate, iters_s, m_s, n_s, k_s) = (
            fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7],
        );
        let ctx = |e: String| format!("cases manifest row {line_no}: {e}");
        let init = Init::parse(init).map_err(ctx)?;
        let seed = if seed.is_empty() {
            None
        } else {
            Some(parse_u64("seed", seed).map_err(ctx)?)
        };
        let replicate = if replicate.is_empty() {
            0
        } else {
            parse_u64("replicate", replicate).map_err(ctx)?
        };
        if init != Init::Seeded && replicate != 0 {
            return Err(ctx("replicate requires init=seeded".to_string()));
        }
        validate_init_args(init, seed).map_err(ctx)?;
        let full = Case {
            in_dir: root.join(case),
            out_dir: out_root.join(case).join("out"),
            m: parse_usize("m", m_s).map_err(ctx)?,
            n: parse_usize("n", n_s).map_err(ctx)?,
            k: parse_usize("k", k_s).map_err(ctx)?,
            iters: parse_usize("iters", iters_s).map_err(ctx)?,
            init,
            seed,
            replicate,
            dump_at: Vec::new(),
            full_trace,
        };
        run_case(&full, &mut vc).map_err(|e| format!("case {case}: {e}"))?;
        ran += 1;
    }
    eprintln!("msuiter-kernel: batch ok ({ran} cases)");
    Ok(())
}

// ---------------------------------------------------------------------------
// CSV plumbing (kl-crosscheck driver conventions)
// ---------------------------------------------------------------------------

/// Parse a headerless numeric CSV (any mix of row/newline separators) into
/// exactly `expect_len` row-major values. The certified reader itself now
/// lives in the engine `vcache` module so the batch V cache and this CLI
/// share one implementation of the byte law (a forked reader is a second
/// implementation, and second implementations are how byte laws die);
/// this is a thin delegate and the fault texts are unchanged.
fn read_csv(path: &Path, expect_len: usize, label: &str) -> Result<Vec<f64>, String> {
    msuiter_engine::vcache::read_certified_csv(path, expect_len, label)
}

/// Write a row-major matrix as `{:.17e}` rows (bit-exact round trip).
fn write_csv(path: &Path, mat: &[f64], rows: usize, cols: usize) -> Result<(), String> {
    let mut s = String::with_capacity(mat.len() * 26);
    for r in 0..rows {
        for (c, x) in mat[r * cols..(r + 1) * cols].iter().enumerate() {
            if c > 0 {
                s.push(',');
            }
            write!(s, "{x:.17e}").map_err(|e| format!("fmt: {e}"))?;
        }
        s.push('\n');
    }
    write_str(path, &s)
}

fn write_str(path: &Path, s: &str) -> Result<(), String> {
    std::fs::write(path, s).map_err(|e| format!("cannot write {}: {e}", path.display()))
}

// ---------------------------------------------------------------------------
// Unit tests (protocol surface pieces that do not need a spawned process;
// the end-to-end contract lives in tests/kernel_cli_protocol.rs)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn args(s: &str) -> impl Iterator<Item = String> + '_ {
        s.split_whitespace().map(str::to_string)
    }

    #[test]
    fn init_parses_the_frozen_selector_set() {
        assert_eq!(Init::parse("external").unwrap(), Init::External);
        assert_eq!(Init::parse("seeded").unwrap(), Init::Seeded);
        assert_eq!(Init::parse("nndsvd").unwrap(), Init::Nndsvd);
        assert_eq!(Init::parse("nndsvda").unwrap(), Init::Nndsvda);
        let e = Init::parse("gpl-kernel").unwrap_err();
        assert!(e.contains("--init"), "{e}");
        assert!(e.contains("gpl-kernel"), "{e}");
    }

    #[test]
    fn arg_guards_enforce_the_init_contract() {
        assert!(validate_init_args(Init::External, None).is_ok());
        assert!(validate_init_args(Init::External, Some(7)).is_err());
        assert!(validate_init_args(Init::Seeded, None).is_err());
        assert!(validate_init_args(Init::Seeded, Some(7)).is_ok());
        assert_eq!(check_replicate(Init::Seeded, None).unwrap(), 0);
        assert_eq!(check_replicate(Init::Seeded, Some(3)).unwrap(), 3);
        assert!(check_replicate(Init::External, Some(3)).is_err());
    }

    #[test]
    fn flag_dispatch_rejects_incoherent_surfaces() {
        // Missing required flag (--in).
        assert!(dispatch_fit_kl(&mut args("--out out --m 6 --n 5 --k 2 --iters 12")).is_err());
        // --seed on the external arm.
        assert!(dispatch_fit_kl(&mut args(
            "--in in --out out --m 6 --n 5 --k 2 --iters 12 --seed 1"
        ))
        .is_err());
        // --replicate off the seeded arm.
        assert!(dispatch_fit_kl(&mut args(
            "--in in --out out --m 6 --n 5 --k 2 --iters 12 --replicate 2"
        ))
        .is_err());
        // Half a batch surface.
        assert!(dispatch_fit_kl(&mut args("--cases c --root r")).is_err());
        assert!(dispatch_fit_kl(&mut args("--cases c --out-root o")).is_err());
        // Batch mode smuggled alongside single-case flags.
        assert!(dispatch_fit_kl(&mut args("--cases c --root r --out-root o --m 6"))
            .is_err());
        // Unknown flag.
        assert!(dispatch_fit_kl(&mut args(
            "--in in --out out --m 6 --n 5 --k 2 --iters 12 --weird 1"
        ))
        .is_err());
    }

    /// Protocol 2: `--full-trace` is a valueless flag legal on BOTH CLI
    /// surfaces -- the dispatchers must classify it as part of the accepted
    /// surface (never `unknown flag`), on either surface.
    #[test]
    fn full_trace_flag_is_part_of_the_accepted_cli_surface() {
        let dir = scratch("fulltrace");
        let indir = dir.join("in");
        std::fs::create_dir_all(&indir).expect("in dir");
        let v: Vec<f64> = (0..30).map(|i| 1.0 + (i % 7) as f64).collect();
        write_csv(&indir.join("V.csv"), &v, 6, 5).unwrap();
        let single = dispatch_fit_kl(&mut args(&format!(
            "--in {} --out {} --m 6 --n 5 --k 2 --iters 3 --init nndsvd --seed 7 --full-trace",
            indir.display(), dir.join("out").display()
        )));
        assert!(!matches!(&single, Err(e) if e.starts_with("unknown flag")),
                "--full-trace rejected on the single-case surface: {single:?}");
        single.expect("the single face with --full-trace runs");
        std::fs::write(dir.join("cases.csv"),
            "case,init,seed,replicate,iters,m,n,k\nin,nndsvd,7,,3,6,5,2\n").unwrap();
        let batch = dispatch_fit_kl(&mut args(&format!(
            "--cases {} --root {} --out-root {} --full-trace",
            dir.join("cases.csv").display(), dir.display(), dir.join("bout").display()
        )));
        assert!(!matches!(&batch, Err(e) if e.starts_with("unknown flag")),
                "--full-trace rejected on the batch surface: {batch:?}");
        batch.expect("the batch face with --full-trace runs");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn csv_round_trip_is_bit_exact() {
        let dir = scratch("roundtrip");
        let vals: Vec<f64> = vec![0.1, 1.0 / 3.0, 1e-300, 2.5e17, 0.0, 1.0];
        write_csv(&dir.join("M.csv"), &vals, 3, 2).unwrap();
        let back = read_csv(&dir.join("M.csv"), vals.len(), "M.csv").unwrap();
        assert_eq!(back, vals, "{{:.17e}} grid lost bits");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn read_csv_reports_labelled_shape_faults() {
        let dir = scratch("shapefaults");
        std::fs::write(dir.join("V.csv"), "1.0,2.0\n3.0\n").unwrap();
        let e = read_csv(&dir.join("V.csv"), 6, "V.csv").unwrap_err();
        assert!(e.contains("V.csv") && e.contains("expected 6"), "{e}");
        std::fs::write(dir.join("B.csv"), "1.0,oops\n").unwrap();
        let e = read_csv(&dir.join("B.csv"), 2, "B.csv").unwrap_err();
        assert!(e.contains("B.csv") && e.contains("oops"), "{e}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn version_string_is_the_frozen_handshake() {
        // The exact shape testthat and the gate audit; keep in lockstep with
        // tests/kernel_cli_protocol.rs and tests/testthat/test-kernel-cli.R.
        let role = msuiter_engine::CRATE_ROLE;
        let eps = msuiter_engine::nmf::KL_EPS;
        let s = format!("msuiter-kernel protocol={PROTOCOL} engine=\"{role}\" kl_eps={eps:e}");
        assert!(s.contains("protocol=1"));
        assert!(s.contains("kl_eps=1e-12"));
        assert!(s.contains(role));
    }

    fn scratch(label: &str) -> PathBuf {
        let cand = std::env::temp_dir().join(format!(
            "msuiter-kernel-unit-{}-{label}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&cand).expect("scratch");
        cand
    }
}
