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

/// Locate the binary cargo just built for this test binary:
/// `target/debug/deps/<test>` → `target/debug/msuiter-kernel[.exe]`.
fn kernel_bin() -> PathBuf {
    let exe = std::env::current_exe().expect("current_exe");
    let deps = exe.parent().expect("deps dir");
    let profile = deps.parent().expect("target profile dir");
    let mut p = profile.join("msuiter-kernel");
    if cfg!(windows) {
        p.set_extension("exe");
    }
    assert!(
        p.exists(),
        "stable batch entry not built: {} missing — the boundary contract file \
         src/rust/engine/src/bin/msuiter-kernel.rs must exist",
        p.display()
    );
    p
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
    let text = fs::read_to_string(&dir.join(name)).expect("read output");
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .flat_map(|l| l.split(','))
        .map(|t| t.trim().parse::<f64>().expect("parse output value"))
        .collect()
}

fn read_text(dir: &Path, name: &str) -> String {
    fs::read_to_string(&dir.join(name)).expect("read output")
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
    let rows: Vec<&str> = trace.lines().skip(1).collect();
    assert_eq!(rows.len(), 13, "trace.csv header + 13 rows expected");
    let obj_final: f64 = rows[12].split(',').nth(1).unwrap().parse().unwrap();
    assert_eq!(obj_final, reference.objective[12]);

    let meta = read_text(&out_dir, "meta.csv");
    for key in ["protocol,1", "init,external", "iterations,12", "engine_crate,"] {
        assert!(meta.contains(key), "meta.csv missing `{key}`:\n{meta}");
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
            one.push(fs::read(&out_dir.join(name)).expect("read artifact"));
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
        "case,init,seed,replicate,iters\ncaseA,external,,,12\ncaseB,seeded,42,1,12\n",
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
