//! P1 kernel-extension face (d): stable batch entry `msuiter-kernel`.
//!
//! The isolated-process boundary contract this binary freezes:
//!   * ONE stable, version-stamped protocol (`protocol=1`, announced by
//!     `--version` and echoed in every `meta.csv`);
//!   * CSV in / CSV out, numbers in 17-significant-digit `%.17e` — the
//!     same bit-exact double round-trip convention established by
//!     tools/kl-crosscheck (input quantization notes in its README);
//!   * the fit is the UNMODIFIED certified kernel (`fit_kl_with_init` /
//!     `fit_kl_on_stream` via the engine's public API): the boundary must
//!     never become a second implementation;
//!   * exit 0 = success, exit 2 = any argument/input/I/O/kernel fault
//!     with a single `error: ...` line on stderr (driver convention,
//!     tools/kl-crosscheck/driver/src/main.rs).
//!
//! These tests execute the built binary (cargo builds bin targets before
//! integration tests of the same crate) and pin: the version handshake,
//! bit agreement of the external-init path with the in-process kernel,
//! byte-identical reruns, the batch manifest mode against single-case runs
//! and the seeded/stream path against the in-process `fit_kl_on_stream`,
//! the strict-positivity of the NNDSVDa arm, and clean structured failures.
//!
//! P1 context: docs/research/09-sigminer-v3-parity-plan.md §5 row P1 and
//! §7 P1-kickoff resolution; the sigminer-side Suggests-gated consumption
//! is the follow-on PR and must speak exactly this protocol.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use msuiter_engine::nmf::{fit_kl_on_stream, fit_kl_with_init};
use msuiter_engine::rng::StreamId;

/// Locate the binary cargo built for this suite. The test binary itself may
/// run from `target/debug/deps/` or, on newer cargo, from
/// `target/debug/build/<pkg>/<metadata>/out/` (the issue #32 nightly layout);
/// the kernel binary lands in the profile root either way, so resolve by
/// walking the executable's ancestors -- one rule that holds under every
/// cargo layout instead of a fixed-up walk that silently pins one.
fn kernel_bin() -> PathBuf {
    let exe = std::env::current_exe().expect("current_exe");
    let exe_name = if cfg!(windows) { "msuiter-kernel.exe" } else { "msuiter-kernel" };
    let mut dir = exe.parent();
    for _ in 0..6 {
        let Some(d) = dir else { break };
        let p = d.join(exe_name);
        if p.exists() {
            return p;
        }
        dir = d.parent();
    }
    panic!(
        "stable batch entry not built: {exe_name} missing above {} — the boundary \
         contract file src/rust/engine/src/bin/msuiter-kernel.rs must exist",
        exe.display()
    );
}

struct Out {
    status: i32,
    stdout: String,
    stderr: String,
}

fn run(args: &[&str]) -> Out {
    let out = Command::new(kernel_bin())
        .args(args)
        .output()
        .expect("spawn msuiter-kernel");
    Out {
        status: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8(out.stdout).expect("CLI stdout is ascii"),
        stderr: String::from_utf8(out.stderr).expect("CLI stderr is ascii"),
    }
}

// Small, self-contained scratch area per test (pid + label keeps parallel
// tests disjoint; removed at drop).
struct Scratch(PathBuf);

impl Scratch {
    fn new(label: &str) -> Self {
        let mut n: u32 = 0;
        let dir = loop {
            n += 1;
            let cand = std::env::temp_dir()
                .join(format!("msuiter-kernel-it-{}-{label}-{n}", std::process::id()));
            if fs::create_dir_all(&cand).is_ok() {
                break cand;
            }
            assert!(n < 100, "scratch allocation failed");
        };
        Self(dir)
    }
    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Write a row-major matrix as one-number-per-line CSV (values printed with
/// full precision so the driver-side parser sees exactly these doubles).
fn write_matrix(dir: &Path, name: &str, xs: &[f64], cols: usize) {
    let mut s = String::new();
    for chunk in xs.chunks(cols) {
        for (i, x) in chunk.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            s.push_str(&format!("{x:.17e}"));
        }
        s.push('\n');
    }
    fs::write(dir.join(name), s).expect("write fixture");
}

fn read_matrix(dir: &Path, name: &str) -> Vec<f64> {
    let text = fs::read_to_string(dir.join(name)).expect("read output");
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .flat_map(|l| l.split(','))
        .map(|t| t.trim().parse::<f64>().expect("parse output value"))
        .collect()
}

fn read_text(dir: &Path, name: &str) -> String {
    fs::read_to_string(dir.join(name)).expect("read output")
}

// The shared small problem: 6×5, k=2, 12 iterations. Values avoid any
// accidental structure (not multiples, mixed magnitudes, one zero row is
// deliberately absent — the R-side comparison history is kl-crosscheck's
// job; here the reference is the in-process kernel).
fn problem() -> (usize, usize, usize, Vec<f64>, Vec<f64>, Vec<f64>) {
    let (m, n, k) = (6usize, 5usize, 2usize);
    let v: Vec<f64> = (0..m * n)
        .map(|i| ((i as f64 * 7.31 + 1.7) * 10.0).floor() / 10.0 % 9.0 + (i % 3) as f64 * 0.13)
        .collect();
    let w0: Vec<f64> = (0..m * k).map(|i| 0.5 + (i as f64) * 0.073 % 1.0).collect();
    let h0: Vec<f64> = (0..k * n).map(|i| 1.5 - (i as f64) * 0.121 % 1.0).collect();
    assert!(v.iter().all(|x| *x >= 0.0) && w0.iter().all(|x| *x > 0.0) && h0.iter().all(|x| *x > 0.0));
    (m, n, k, v, w0, h0)
}

#[test]
fn version_handshake_announces_the_frozen_protocol() {
    let out = run(&["--version"]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    assert!(out.stdout.contains("protocol=1"), "stdout: {}", out.stdout);
    assert!(out.stdout.contains("msuiter-kernel"), "stdout: {}", out.stdout);
    assert!(out.stdout.contains("kl_eps=1e-12"), "stdout: {}", out.stdout);
}

/// Read `key,value` lines of meta.csv into owned lines matching a key.
fn meta_line(dir: &Path, name: &str, key: &str) -> String {
    read_text(dir, name)
        .lines()
        .find(|l| l.starts_with(&format!("{key},")))
        .unwrap_or_else(|| panic!("meta.csv has no `{key}` line"))
        .to_string()
}

/// The production default of protocol 2: the per-iteration KL objective is
/// the observer it always was (nmf.rs module docs: it never feeds the
/// updates), so production computes it at the two endpoints only.
/// trace.csv is the header plus the rows t = 0 and t = max_iter, meta.csv
/// stamps trace_len,2, and both rows and the factors are bit-identical to
/// the in-process reference. The full 0..max_iter walk is the opted-in
/// ceremony of `--full-trace` (pinned by the two tests below).
#[test]
fn external_init_matches_the_in_process_kernel_bit_for_bit() {
    let (m, n, k, v, w0, h0) = problem();
    let scratch = Scratch::new("external");
    write_matrix(scratch.path(), "V.csv", &v, n);
    write_matrix(scratch.path(), "W0.csv", &w0, k);
    write_matrix(scratch.path(), "H0.csv", &h0, n);
    let out_dir = scratch.path().join("out");

    let out = run(&[
        "fit-kl",
        "--in", scratch.path().to_str().unwrap(),
        "--out", out_dir.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);

    let reference = fit_kl_with_init(&v, m, n, k, &w0, &h0, 12).expect("kernel");
    let w = read_matrix(&out_dir, "W.csv");
    let h = read_matrix(&out_dir, "H.csv");
    assert_eq!(w, reference.w, "CLI W diverged from the in-process kernel");
    assert_eq!(h, reference.h, "CLI H diverged from the in-process kernel");

    let trace = read_text(&out_dir, "trace.csv");
    let rows: Vec<String> = trace.lines().skip(1).map(str::to_string).collect();
    assert_eq!(rows.len(), 2, "protocol-2 trace.csv is the header + the two endpoints");
    let (t0, t1) = (
        rows[0].split(',').next().unwrap().parse::<usize>().unwrap(),
        rows[1].split(',').next().unwrap().parse::<usize>().unwrap(),
    );
    assert_eq!((t0, t1), (0, 12), "endpoints must ride t = 0 and t = max_iter");
    let obj_init: f64 = rows[0].split(',').nth(1).unwrap().parse().unwrap();
    let obj_final: f64 = rows[1].split(',').nth(1).unwrap().parse().unwrap();
    assert_eq!(obj_init, reference.objective[0]);
    assert_eq!(obj_final, reference.objective[12]);

    let meta = read_text(&out_dir, "meta.csv");
    for key in ["protocol,1", "init,external", "iterations,12", "trace_len,2"] {
        assert!(meta.lines().any(|l| l == key), "meta.csv missing the line `{key}`:\n{meta}");
    }
    assert!(meta.lines().any(|l| l.starts_with("engine_crate,")),
            "meta.csv has no engine_crate line:\n{meta}");
}

/// Cross-mode bit identity (the protocol-2 contract): the opted-in
/// `--full-trace` face -- the protocol-1 ceremony, header + max_iter + 1
/// rows -- and the production endpoints face are the same procedure at the
/// same bytes: W/H files byte-identical, the meta obj_init/obj_final lines
/// byte-identical strings, and the two production trace rows byte-identical
/// to the corresponding full-trace rows.
#[test]
fn full_trace_flag_is_bit_identical_to_the_production_face() {
    let (m, n, k, v, w0, h0) = problem();
    let _ = (m, n, k);
    let scratch = Scratch::new("cross-mode");
    write_matrix(scratch.path(), "V.csv", &v, 5);
    write_matrix(scratch.path(), "W0.csv", &w0, 2);
    write_matrix(scratch.path(), "H0.csv", &h0, 5);
    let prod = scratch.path().join("out-prod");
    let full = scratch.path().join("out-full");
    let in_arg = scratch.path().to_str().unwrap();
    let out = run(&[
        "fit-kl", "--in", in_arg,
        "--out", prod.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    let out = run(&[
        "fit-kl", "--in", in_arg,
        "--out", full.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12", "--full-trace",
    ]);
    assert_eq!(out.status, 0, "--full-trace must be a legal face selector; stderr: {}", out.stderr);

    for name in ["W.csv", "H.csv"] {
        assert_eq!(
            fs::read(prod.join(name)).expect("prod factor"),
            fs::read(full.join(name)).expect("full factor"),
            "{name}: --full-trace moved the certified bytes"
        );
    }
    for key in ["obj_init", "obj_final"] {
        assert_eq!(
            meta_line(&prod, "meta.csv", key),
            meta_line(&full, "meta.csv", key),
            "the observer at an endpoint moved its text"
        );
    }
    assert_eq!(meta_line(&prod, "meta.csv", "trace_len"), "trace_len,2");
    assert_eq!(meta_line(&full, "meta.csv", "trace_len"), "trace_len,13");
    let prod_rows: Vec<String> = read_text(&prod, "trace.csv").lines().skip(1).map(str::to_string).collect();
    let full_rows: Vec<String> = read_text(&full, "trace.csv").lines().skip(1).map(str::to_string).collect();
    assert_eq!(full_rows.len(), 13, "the opted-in face must still walk 0..=max_iter");
    assert_eq!(prod_rows[0], full_rows[0], "endpoint row 0 moved against the full walk");
    assert_eq!(prod_rows[1], full_rows[12], "endpoint row max_iter moved against the full walk");
}

/// The full-trace face still carries the MM monotonicity property that the
/// committed in-crate convention asserts (direction and tolerance are not
/// invented here: `assert_monotone` in nmf.rs tests and the twin at
/// tests/g2_zero_lock.rs:143-148 -- non-increase within a relative slack of
/// 1e-9 * (1 + |previous|)).
#[test]
fn full_trace_satisfies_the_committed_monotonicity_convention() {
    let (m, n, k, v, w0, h0) = problem();
    let _ = (m, n, k);
    let scratch = Scratch::new("monotone");
    write_matrix(scratch.path(), "V.csv", &v, 5);
    write_matrix(scratch.path(), "W0.csv", &w0, 2);
    write_matrix(scratch.path(), "H0.csv", &h0, 5);
    let out_dir = scratch.path().join("out");
    let in_arg = scratch.path().to_str().unwrap();
    let out = run(&[
        "fit-kl", "--in", in_arg,
        "--out", out_dir.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12", "--full-trace",
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    let trace: Vec<f64> = read_text(&out_dir, "trace.csv")
        .lines()
        .skip(1)
        .map(|l| l.split(',').nth(1).unwrap().parse().unwrap())
        .collect();
    assert_eq!(trace.len(), 13);
    for t in 1..trace.len() {
        let slack = 1e-9 * (1.0 + trace[t - 1].abs());
        assert!(trace[t] <= trace[t - 1] + slack,
                "MM monotonicity broken at t = {t}: {} > {} + {slack}", trace[t], trace[t - 1]);
    }
}

#[test]
fn rerun_is_byte_identical() {
    let (m, n, _k, v, w0, h0) = problem();
    let _ = m;
    let scratch = Scratch::new("determinism");
    write_matrix(scratch.path(), "V.csv", &v, n);
    write_matrix(scratch.path(), "W0.csv", &w0, 2);
    write_matrix(scratch.path(), "H0.csv", &h0, n);

    let mut bytes = Vec::new();
    for run_no in 0..2 {
        let out_dir = scratch.path().join(format!("out{run_no}"));
        let out = run(&[
            "fit-kl",
            "--in", scratch.path().to_str().unwrap(),
            "--out", out_dir.to_str().unwrap(),
            "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
        ]);
        assert_eq!(out.status, 0, "stderr: {}", out.stderr);
        let mut one = Vec::new();
        for name in ["W.csv", "H.csv", "trace.csv", "meta.csv"] {
            one.push(fs::read(out_dir.join(name)).expect("read artifact"));
        }
        bytes.push(one);
    }
    assert_eq!(bytes[0], bytes[1], "byte-identical rerun contract broken");
}

#[test]
fn seeded_stream_and_nndsvda_arms_are_exposed_and_pinned() {
    let (m, n, k, v, _w0, _h0) = problem();
    let scratch = Scratch::new("inits");
    write_matrix(scratch.path(), "V.csv", &v, n);

    // init=seeded --replicate R == in-process fit_kl_on_stream on the
    // frozen per-replicate stream layout (U-M1s-05).
    for (tag, replicate, seed) in [("r0", "0", "42"), ("r3", "3", "42")] {
        let out_dir = scratch.path().join(format!("seeded_{tag}"));
        let out = run(&[
            "fit-kl",
            "--in", scratch.path().to_str().unwrap(),
            "--out", out_dir.to_str().unwrap(),
            "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
            "--init", "seeded", "--seed", seed, "--replicate", replicate,
        ]);
        assert_eq!(out.status, 0, "stderr: {}", out.stderr);
        let reference = fit_kl_on_stream(
            &v,
            m,
            n,
            k,
            12,
            seed.parse().unwrap(),
            StreamId { replicate: replicate.parse().unwrap(), rank: 0, fold: 0 },
        )
        .expect("kernel");
        assert_eq!(read_matrix(&out_dir, "W.csv"), reference.w);
        assert_eq!(read_matrix(&out_dir, "H.csv"), reference.h);
        assert!(read_text(&out_dir, "meta.csv").contains("init,seeded"));
    }

    // The two replicate arms must differ (symmetry broken independently).
    let a = fs::read(scratch.path().join("seeded_r0/W.csv")).expect("r0");
    let b = fs::read(scratch.path().join("seeded_r3/W.csv")).expect("r3");
    assert_ne!(a, b, "replicate arms collapsed onto the same fit");

    // init=nndsvda: strictly positive factors (the zero-lock release face).
    let out_dir = scratch.path().join("nndsvda");
    let out = run(&[
        "fit-kl",
        "--in", scratch.path().to_str().unwrap(),
        "--out", out_dir.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
        "--init", "nndsvda", "--seed", "7",
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    let w = read_matrix(&out_dir, "W.csv");
    let h = read_matrix(&out_dir, "H.csv");
    assert!(w.iter().all(|&x| x > 0.0), "nndsvda arm produced a zero/negative w entry");
    assert!(h.iter().all(|&x| x > 0.0), "nndsvda arm produced a zero/negative h entry");
    assert!(read_text(&out_dir, "meta.csv").contains("init,nndsvda"));

    // init=nndsvd (plain, zero-keeping) must also run and stay finite.
    let out_dir = scratch.path().join("nndsvd");
    let out = run(&[
        "fit-kl",
        "--in", scratch.path().to_str().unwrap(),
        "--out", out_dir.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
        "--init", "nndsvd", "--seed", "7",
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    let w = read_matrix(&out_dir, "W.csv");
    assert!(w.iter().all(|&x| x.is_finite()), "plain nndsvd arm produced non-finite");
}

#[test]
fn batch_mode_equals_single_case_runs() {
    let (m, n, k, v, w0, h0) = problem();
    let _ = (m, n, k);
    let root = Scratch::new("batch");
    let case_a = root.path().join("caseA");
    fs::create_dir_all(&case_a).expect("caseA dir");
    write_matrix(&case_a, "V.csv", &v, 5);
    write_matrix(&case_a, "W0.csv", &w0, 2);
    write_matrix(&case_a, "H0.csv", &h0, 5);
    let case_b = root.path().join("caseB");
    fs::create_dir_all(&case_b).expect("caseB dir");
    write_matrix(&case_b, "V.csv", &v, 5);

    fs::write(
        root.path().join("cases.csv"),
        "case,init,seed,replicate,iters,m,n,k\n\
         caseA,external,,,12,6,5,2\n\
         caseB,seeded,42,1,12,6,5,2\n",
    )
    .expect("manifest");

    let out = run(&[
        "fit-kl",
        "--cases", root.path().join("cases.csv").to_str().unwrap(),
        "--root", root.path().to_str().unwrap(),
        "--out-root", root.path().to_str().unwrap(),
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);

    // caseA output must equal the single-case invocation byte for byte.
    let single = root.path().join("single");
    let out = run(&[
        "fit-kl",
        "--in", case_a.to_str().unwrap(),
        "--out", single.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    for name in ["W.csv", "H.csv", "trace.csv"] {
        let batch_bytes = fs::read(root.path().join("caseA/out").join(name)).expect("batch artifact");
        let single_bytes = fs::read(single.join(name)).expect("single artifact");
        assert_eq!(batch_bytes, single_bytes, "{name}: batch drift from single-case run");
    }

    // caseB seeded arm matches the in-process stream face.
    let reference = fit_kl_on_stream(
        &v, 6, 5, 2, 12, 42,
        StreamId { replicate: 1, rank: 0, fold: 0 },
    )
    .expect("kernel");
    assert_eq!(read_matrix(&root.path().join("caseB/out"), "W.csv"), reference.w);
    assert!(read_text(&root.path().join("caseB/out"), "meta.csv").contains("protocol,1"));
}

/// The batch face carries the per-case seed law the 50-run unit rides: the
/// seed is a manifest column, so init=nndsvd runs at seed, seed+1, ... may
/// ride one batch invocation (the replicate column stays gated to
/// init=seeded -- that law is the kernel's and stays enforced). Two rows on
/// the same bytes with the same seed are byte-identical; the neighbour seed
/// moves the factors; every meta echoes its own row's seed. The completed
/// batch names its case count on stderr (the census column the serving
/// bridge reads) and a faulty row kills the batch without that line.
#[test]
fn batch_mode_carries_per_case_seeds_and_serves_the_full_trace_face() {
    let (m, n, k, v, _w0, _h0) = problem();
    let _ = (m, n, k);
    let root = Scratch::new("seeds");
    for case in ["sA0", "sA1"] {
        let dir = root.path().join(case);
        fs::create_dir_all(&dir).expect("case dir");
        write_matrix(&dir, "V.csv", &v, 5);
    }
    fs::write(
        root.path().join("seeds.csv"),
        "case,init,seed,replicate,iters,m,n,k\n\
         sA0,nndsvd,42,,12,6,5,2\n\
         sA1,nndsvd,42,,12,6,5,2\n",
    )
    .expect("manifest");
    let out = run(&[
        "fit-kl",
        "--cases", root.path().join("seeds.csv").to_str().unwrap(),
        "--root", root.path().to_str().unwrap(),
        "--out-root", root.path().to_str().unwrap(),
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    assert!(out.stderr.contains("batch ok (2 cases)"),
            "the census line must name the served case count; stderr: {}", out.stderr);
    let a = fs::read(root.path().join("sA0/out/W.csv")).expect("sA0");
    assert_eq!(a, fs::read(root.path().join("sA1/out/W.csv")).expect("sA1"),
               "same seed, same bytes -- the batch collapsed two independent fits");
    assert_eq!(meta_line(&root.path().join("sA0/out"), "meta.csv", "seed"), "seed,42");
    assert_eq!(meta_line(&root.path().join("sA1/out"), "meta.csv", "seed"), "seed,42");
    assert_eq!(meta_line(&root.path().join("sA0/out"), "meta.csv", "trace_len"),
               "trace_len,2", "the batch default is the protocol-2 face");

    // Neighbour seed moves the factors (the seed column is not decorative).
    fs::write(
        root.path().join("moves.csv"),
        "case,init,seed,replicate,iters,m,n,k\n\
         sA0,nndsvd,43,,12,6,5,2\n",
    )
    .expect("manifest");
    let out = run(&[
        "fit-kl",
        "--cases", root.path().join("moves.csv").to_str().unwrap(),
        "--root", root.path().to_str().unwrap(),
        "--out-root", root.path().join("moves-out").to_str().unwrap(),
    ]);
    assert_eq!(out.status, 0, "stderr: {}", out.stderr);
    let moved = fs::read(root.path().join("moves-out/sA0/out/W.csv")).expect("moved");
    assert_ne!(moved, a, "seed 42 vs 43 collapsed -- the per-case seed law is inert");

    // --full-trace is legal on the batch face and is the protocol-1 ceremony.
    let out = run(&[
        "fit-kl",
        "--cases", root.path().join("seeds.csv").to_str().unwrap(),
        "--root", root.path().to_str().unwrap(),
        "--out-root", root.path().join("full-out").to_str().unwrap(),
        "--full-trace",
    ]);
    assert_eq!(out.status, 0, "--full-trace must be legal in batch mode; stderr: {}", out.stderr);
    assert_eq!(
        meta_line(&root.path().join("full-out/sA0/out"), "meta.csv", "trace_len"),
        "trace_len,13", "the opted-in face is the protocol-1 ceremony"
    );
    let w_full = fs::read(root.path().join("full-out/sA0/out/W.csv")).expect("full W");
    assert_eq!(w_full, a, "--full-trace moved the certified bytes on the batch face");

    // Firing control for the census column: a faulty row kills the batch and
    // the completion line never prints.
    fs::write(
        root.path().join("broken.csv"),
        "case,init,seed,replicate,iters,m,n,k\n\
         sA0,nndsvd,42,,12,6,5,2\n\
         sAx,bogus,1,,12,6,5,2\n",
    )
    .expect("manifest");
    let out = run(&[
        "fit-kl",
        "--cases", root.path().join("broken.csv").to_str().unwrap(),
        "--root", root.path().to_str().unwrap(),
        "--out-root", root.path().join("broken-out").to_str().unwrap(),
    ]);
    assert_eq!(out.status, 2, "a faulty manifest row must exit 2");
    assert!(!out.stderr.contains("batch ok"), "census line fired on a dead batch: {}", out.stderr);

    // The replicate law stays the kernel's: a non-seeded row may not carry one.
    fs::write(
        root.path().join("illegal.csv"),
        "case,init,seed,replicate,iters,m,n,k\n\
         sA0,nndsvd,42,3,12,6,5,2\n",
    )
    .expect("manifest");
    let out = run(&[
        "fit-kl",
        "--cases", root.path().join("illegal.csv").to_str().unwrap(),
        "--root", root.path().to_str().unwrap(),
        "--out-root", root.path().join("illegal-out").to_str().unwrap(),
    ]);
    assert_eq!(out.status, 2, "replicate off init=seeded must exit 2");
    assert!(out.stderr.contains("replicate requires init=seeded"), "{}", out.stderr);
}

#[test]
fn structured_failures_use_the_driver_exit_convention() {
    let (m, n, _k, v, _w0, _h0) = problem();
    let _ = m;
    let scratch = Scratch::new("errors");

    // Missing initializer file for the external arm.
    write_matrix(scratch.path(), "V.csv", &v, n);
    let out_dir = scratch.path().join("out_missing");
    let out = run(&[
        "fit-kl",
        "--in", scratch.path().to_str().unwrap(),
        "--out", out_dir.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
    ]);
    assert_eq!(out.status, 2, "missing W0.csv must exit 2 (stderr: {})", out.stderr);
    assert!(out.stderr.starts_with("error:"), "stderr: {}", out.stderr);
    assert!(out.stderr.contains("W0.csv"), "stderr: {}", out.stderr);

    // Unknown init selector.
    let out = run(&[
        "fit-kl",
        "--in", scratch.path().to_str().unwrap(),
        "--out", out_dir.to_str().unwrap(),
        "--m", "6", "--n", "5", "--k", "2", "--iters", "12",
        "--init", "gpl-kernel",
    ]);
    assert_eq!(out.status, 2, "stderr: {}", out.stderr);
    assert!(out.stderr.contains("--init"), "stderr: {}", out.stderr);

    // Dimension/storage inconsistency surfaces the kernel validator.
    let out = run(&[
        "fit-kl",
        "--in", scratch.path().to_str().unwrap(),
        "--out", out_dir.to_str().unwrap(),
        "--m", "9", "--n", "5", "--k", "2", "--iters", "12",
        "--init", "seeded", "--seed", "1",
    ]);
    assert_eq!(out.status, 2, "stderr: {}", out.stderr);

    // Unknown subcommand.
    let out = run(&["fit-eu"]);
    assert_eq!(out.status, 2, "stderr: {}", out.stderr);
    assert!(out.stderr.contains("fit-kl"), "stderr should name the supported verb: {}", out.stderr);
}
