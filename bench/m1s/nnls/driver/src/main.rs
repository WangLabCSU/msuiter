//! M1s bench driver: batch NNLS over the unmodified engine kernel
//! `msuiter_engine::nnls::nnls_gram` (shared Gram + per-sample solves).
//!
//! Timing scope: the whole batch (Gram assembly + n right-hand sides),
//! which is exactly the user-facing batch problem; the shared-Gram reuse is
//! the algorithmic advantage under test, mirroring how the FFI fit layer
//! uses the kernel. Dumps sample-0 exposures as `x0.csv` (17-digit
//! round-trip) for the scipy cross-check.

use std::fmt::Write as _;
use std::path::PathBuf;
use std::time::Instant;

use msuiter_engine::nnls::{nnls_gram, NnlsOptions};

fn read_csv_rows(path: &std::path::Path) -> Result<Vec<Vec<f64>>, String> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let mut rows: Vec<Vec<f64>> = Vec::new();
    for (line_no, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let mut row = Vec::new();
        for tok in line.split(',') {
            let v: f64 = tok.trim().parse()
                .map_err(|e| format!("{} line {}: parse error: {e}", path.display(), line_no + 1))?;
            row.push(v);
        }
        if let Some(first) = rows.first() {
            if first.len() != row.len() {
                return Err(format!("{}: ragged rows", path.display()));
            }
        }
        rows.push(row);
    }
    Ok(rows)
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut input_dir = None;
    let mut output_dir = None;
    while let Some(flag) = args.next() {
        let value = args.next().unwrap_or_else(|| panic!("missing value for {flag}"));
        match flag.as_str() {
            "--in" => input_dir = Some(PathBuf::from(value)),
            "--out" => output_dir = Some(PathBuf::from(value)),
            other => panic!("unknown flag {other}"),
        }
    }
    let input_dir = input_dir.expect("missing --in");
    let output_dir = output_dir.expect("missing --out");

    let w_rows = read_csv_rows(&input_dir.join("W.csv")).unwrap();
    let v_rows = read_csv_rows(&input_dir.join("V.csv")).unwrap();
    let m = w_rows.len();
    let k = w_rows[0].len();
    let n = v_rows[0].len();
    assert_eq!(v_rows.len(), m, "V rows must equal W rows");

    let mut w = Vec::with_capacity(m * k);
    for row in &w_rows {
        w.extend_from_slice(row);
    }
    let mut v = Vec::with_capacity(m * n);
    for row in &v_rows {
        v.extend_from_slice(row);
    }

    let opts = NnlsOptions::default();
    // Timed batch = the whole user-facing batch problem: shared Gram
    // G = W^T W, right-hand sides b_j = W^T v_j, then one nnls_gram solve
    // per sample. (The scipy baseline pays its normal-equations cost inside
    // every per-sample call; keeping assembly inside ours is conservative.)
    let solve_all = |w: &[f64], v: &[f64]| -> Vec<Vec<f64>> {
        let mut g = vec![0.0f64; k * k];
        for i in 0..k {
            for j in 0..k {
                let mut acc = 0.0f64;
                for t in 0..m {
                    acc += w[t * k + i] * w[t * k + j];
                }
                g[i * k + j] = acc;
            }
        }
        let mut b = vec![0.0f64; k * n]; // sample-major: b[j*k + s]
        for j in 0..n {
            for t in 0..m {
                let vt = v[t * n + j];
                if vt != 0.0 {
                    for s in 0..k {
                        b[j * k + s] += w[t * k + s] * vt;
                    }
                }
            }
        }
        (0..n)
            .map(|j| {
                nnls_gram(&g, &b[j * k..(j + 1) * k], k, &opts)
                    .unwrap_or_else(|e| panic!("nnls_gram failed at sample {j}: {e}"))
                    .x
            })
            .collect()
    };

    // Protocol: 1 untimed warmup + 3 timed full-batch runs, median.
    let _warm = solve_all(&w, &v);
    let mut runs_ms = [0.0f64; 3];
    let mut last = None;
    for r in 0..3 {
        let t0 = Instant::now();
        let xs = solve_all(&w, &v);
        runs_ms[r] = t0.elapsed().as_secs_f64() * 1e3;
        last = Some(xs);
    }
    let xs = last.unwrap();
    let mut sorted = runs_ms;
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let median = sorted[1];

    std::fs::create_dir_all(&output_dir).unwrap();
    println!("run0,{:.3}", runs_ms[0]);
    println!("run1,{:.3}", runs_ms[1]);
    println!("run2,{:.3}", runs_ms[2]);
    println!("median_ms,{median:.3}");

    let mut meta = String::new();
    let _ = writeln!(meta, "m,{m}");
    let _ = writeln!(meta, "k,{k}");
    let _ = writeln!(meta, "n,{n}");
    let _ = writeln!(meta, "run1_ms,{:.3}", runs_ms[0]);
    let _ = writeln!(meta, "run2_ms,{:.3}", runs_ms[1]);
    let _ = writeln!(meta, "run3_ms,{:.3}", runs_ms[2]);
    let _ = writeln!(meta, "median_ms,{median:.3}");
    let _ = writeln!(meta, "engine_crate,{}", msuiter_engine::CRATE_ROLE);
    std::fs::write(output_dir.join("meta.csv"), meta).unwrap();

    // Sample-0 exposures for the scipy cross-check.
    let mut x0 = String::new();
    let _ = writeln!(x0, "{}", xs[0].iter().map(|x| format!("{x:.17e}")).collect::<Vec<_>>().join(","));
    std::fs::write(output_dir.join("x0.csv"), x0).unwrap();
}
