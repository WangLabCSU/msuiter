//! M1s bench driver: KL-NMF timing over the unmodified engine kernel.
//!
//! Contract (matches tools/kl-crosscheck's driver pattern):
//! - reads `V.csv` (m x n), `W0.csv` (m x k), `H0.csv` (k x n) from `--in`
//!   (shape-inferred: m/n from V, k from W0; no headers, plain decimal CSVs
//!   with exact representations — integer counts and k/1024-grid decimals)
//! - runs `msuiter_engine::nmf::fit_kl_with_init` with `--iters` iterations
//! - timing: 1 warmup run (not timed) + 3 timed runs; prints per-run
//!   milliseconds and the median; writes `meta.csv` (objective trace ends,
//!   engine role) and `trace.csv` of the timed run for cross-checks.

use std::fmt::Write as _;
use std::path::PathBuf;
use std::time::Instant;

use msuiter_engine::nmf::fit_kl_with_init;

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
            let v: f64 = tok
                .trim()
                .parse()
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
    let mut iters = 100usize;
    while let Some(flag) = args.next() {
        let value = args.next().unwrap_or_else(|| panic!("missing value for {flag}"));
        match flag.as_str() {
            "--in" => input_dir = Some(PathBuf::from(value)),
            "--out" => output_dir = Some(PathBuf::from(value)),
            "--iters" => iters = value.parse().expect("bad --iters"),
            other => panic!("unknown flag {other}"),
        }
    }
    let input_dir = input_dir.expect("missing --in");
    let output_dir = output_dir.expect("missing --out");

    let v_rows = read_csv_rows(&input_dir.join("V.csv")).unwrap();
    let w0_rows = read_csv_rows(&input_dir.join("W0.csv")).unwrap();
    let h0_rows = read_csv_rows(&input_dir.join("H0.csv")).unwrap();
    let m = v_rows.len();
    let n = v_rows[0].len();
    let k = w0_rows[0].len();
    assert_eq!(w0_rows.len(), m, "W0 rows must equal V rows");
    assert_eq!(h0_rows.len(), k, "H0 rows must equal k");
    assert_eq!(h0_rows[0].len(), n, "H0 cols must equal V cols");

    let mut v = Vec::with_capacity(m * n);
    for row in &v_rows {
        v.extend_from_slice(row);
    }
    let mut w0 = Vec::with_capacity(m * k);
    for row in &w0_rows {
        w0.extend_from_slice(row);
    }
    let mut h0 = Vec::with_capacity(k * n);
    for row in &h0_rows {
        h0.extend_from_slice(row);
    }

    // Protocol: 1 untimed warmup (page cache, allocator, branch predictors),
    // then 3 timed runs; median of the 3 is the reported figure.
    let warm = fit_kl_with_init(&v, m, n, k, &w0, &h0, iters)
        .unwrap_or_else(|e| panic!("warmup fit failed: {e}"));
    let mut runs_ms = [0.0f64; 3];
    let mut last = None;
    for r in 0..3 {
        let t0 = Instant::now();
        let fit = fit_kl_with_init(&v, m, n, k, &w0, &h0, iters)
            .unwrap_or_else(|e| panic!("timed fit {r} failed: {e}"));
        runs_ms[r] = t0.elapsed().as_secs_f64() * 1e3;
        last = Some(fit);
    }
    let _ = warm;
    let fit = last.unwrap();
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
    let _ = writeln!(meta, "n,{n}");
    let _ = writeln!(meta, "k,{k}");
    let _ = writeln!(meta, "iters,{iters}");
    let _ = writeln!(meta, "iterations,{}", fit.iterations);
    let _ = writeln!(meta, "obj_init,{:.17e}", fit.objective[0]);
    let _ = writeln!(meta, "obj_final,{:.17e}", fit.objective[iters]);
    let _ = writeln!(meta, "run1_ms,{:.3}", runs_ms[0]);
    let _ = writeln!(meta, "run2_ms,{:.3}", runs_ms[1]);
    let _ = writeln!(meta, "run3_ms,{:.3}", runs_ms[2]);
    let _ = writeln!(meta, "median_ms,{median:.3}");
    let _ = writeln!(meta, "engine_crate,{}", msuiter_engine::CRATE_ROLE);
    let _ = writeln!(meta, "kl_eps,{}", msuiter_engine::nmf::KL_EPS);
    std::fs::write(output_dir.join("meta.csv"), meta).unwrap();

    let mut trace = String::with_capacity((iters + 1) * 26);
    trace.push_str("t,objective\n");
    for (t, obj) in fit.objective.iter().enumerate() {
        let _ = writeln!(trace, "{t},{obj:.17e}");
    }
    std::fs::write(output_dir.join("trace.csv"), trace).unwrap();
}
