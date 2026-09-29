//! U-M1s-14 scratch driver (one-off platform experiment, NOT part of the
//! package or CI; `docs/ARCHITECTURE.md` §7.1 / D11 / A8).
//!
//! Contract:
//! - reads `V.csv` (m×n), `W0.csv` (m×k), `H0.csv` (k×n) from `--in`
//! - runs the UNMODIFIED engine kernel `msuiter_engine::nmf::fit_kl_with_init`
//! - writes to `--out`: `W.csv`, `H.csv`, `trace.csv` (T+1 objective values),
//!   plus state checkpoints `W_t<k>.csv` / `H_t<k>.csv` at `--dump-at` steps.
//!
//! Numbers round-trip as 17-significant-digit decimal strings (exact for
//! IEEE-754 doubles, matching what run_experiment.R writes/reads).

use std::fmt::Write as _;
use std::path::PathBuf;

use msuiter_engine::nmf::fit_kl_with_init;

struct Args {
    input_dir: PathBuf,
    output_dir: PathBuf,
    m: usize,
    n: usize,
    k: usize,
    max_iter: usize,
    dump_at: Vec<usize>,
}

fn parse_args() -> Result<Args, String> {
    let mut input_dir = None;
    let mut output_dir = None;
    let mut m = None;
    let mut n = None;
    let mut k = None;
    let mut max_iter = None;
    let mut dump_at = Vec::new();

    let mut it = std::env::args().skip(1);
    while let Some(flag) = it.next() {
        let value = it
            .next()
            .ok_or_else(|| format!("missing value for {flag}"))?;
        match flag.as_str() {
            "--in" => input_dir = Some(PathBuf::from(value)),
            "--out" => output_dir = Some(PathBuf::from(value)),
            "--m" => m = Some(value.parse().map_err(|_| "bad --m")?),
            "--n" => n = Some(value.parse().map_err(|_| "bad --n")?),
            "--k" => k = Some(value.parse().map_err(|_| "bad --k")?),
            "--iters" => max_iter = Some(value.parse().map_err(|_| "bad --iters")?),
            "--dump-at" => {
                for tok in value.split(',') {
                    let t: usize = tok.trim().parse().map_err(|_| "bad --dump-at entry")?;
                    dump_at.push(t);
                }
            }
            other => return Err(format!("unknown flag {other}")),
        }
    }
    Ok(Args {
        input_dir: input_dir.ok_or("missing --in")?,
        output_dir: output_dir.ok_or("missing --out")?,
        m: m.ok_or("missing --m")?,
        n: n.ok_or("missing --n")?,
        k: k.ok_or("missing --k")?,
        max_iter: max_iter.ok_or("missing --iters")?,
        dump_at,
    })
}

/// Parse a numeric CSV without headers into a row-major Vec<f64>.
fn read_csv(path: &std::path::Path, expect_len: usize, label: &str) -> Result<Vec<f64>, String> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("cannot read {label} at {}: {e}", path.display()))?;
    let mut out = Vec::new();
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

/// 17-significant-digit round-trip format for one row of a row-major matrix.
fn csv_row(xs: &[f64]) -> String {
    let mut s = String::new();
    for (i, x) in xs.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        let _ = write!(s, "{x:.17e}");
    }
    s.push('\n');
    s
}

fn write_csv(path: &std::path::Path, mat: &[f64], rows: usize, cols: usize) -> std::io::Result<()> {
    let mut s = String::with_capacity(mat.len() * 26);
    for r in 0..rows {
        s.push_str(&csv_row(&mat[r * cols..(r + 1) * cols]));
    }
    std::fs::write(path, s)
}

fn main() {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(2);
        }
    };
    let Args { input_dir, output_dir, m, n, k, max_iter, dump_at } = args;

    let v = read_csv(&input_dir.join("V.csv"), m * n, "V.csv").unwrap_or_else(|e| {
        eprintln!("error: {e}");
        std::process::exit(2)
    });
    let w0 = read_csv(&input_dir.join("W0.csv"), m * k, "W0.csv").unwrap_or_else(|e| {
        eprintln!("error: {e}");
        std::process::exit(2)
    });
    let h0 = read_csv(&input_dir.join("H0.csv"), k * n, "H0.csv").unwrap_or_else(|e| {
        eprintln!("error: {e}");
        std::process::exit(2)
    });

    let fit = fit_kl_with_init(&v, m, n, k, &w0, &h0, max_iter).unwrap_or_else(|e| {
        eprintln!("error: fit_kl_with_init failed: {e}");
        std::process::exit(2)
    });

    std::fs::create_dir_all(&output_dir).unwrap_or_else(|e| {
        eprintln!("error: cannot create {}: {e}", output_dir.display());
        std::process::exit(2)
    });

    // Final state + full objective trace (objective[t] = after t iterations).
    write_csv(&output_dir.join("W.csv"), &fit.w, m, k).unwrap_or_else(|e| die(e));
    write_csv(&output_dir.join("H.csv"), &fit.h, k, n).unwrap_or_else(|e| die(e));
    let mut trace = String::with_capacity((max_iter + 1) * 26);
    trace.push_str("t,objective\n");
    for (t, obj) in fit.objective.iter().enumerate() {
        let _ = writeln!(trace, "{t},{obj:.17e}");
    }
    std::fs::write(output_dir.join("trace.csv"), trace).unwrap_or_else(|e| die(e));

    // Prefix-property self-check: a driver run with the same inputs must
    // produce identical checkpoints whether requested here or via a second
    // run with larger --iters (fit_kl_with_init is a pure fixed-count loop).
    // Re-deriving intermediate states would require touching the kernel
    // (forbidden); instead we assert the *documented* trace semantics:
    // objective[0] is the initializer, objective[t] after t iterations —
    // recorded here as run metadata for the R side to cross-check.
    let mut meta = String::new();
    let _ = writeln!(meta, "max_iter,{}", max_iter);
    let _ = writeln!(meta, "iterations,{}", fit.iterations);
    let _ = writeln!(meta, "trace_len,{}", fit.objective.len());
    let _ = writeln!(meta, "obj_init,{:.17e}", fit.objective[0]);
    let _ = writeln!(meta, "obj_final,{:.17e}", fit.objective[max_iter]);
    let _ = writeln!(meta, "eps,{}", msuiter_engine::nmf::KL_EPS);
    let _ = writeln!(meta, "engine_crate,{}", msuiter_engine::CRATE_ROLE);
    std::fs::write(output_dir.join("meta.csv"), meta).unwrap_or_else(|e| die(e));

    // Checkpoints are produced only from the returned end state, so we run
    // the kernel once per requested checkpoint depth (cheap: 96×20, k=3).
    // `--dump-at 0,10,20,...` therefore re-runs the identical pure loop to
    // those depths; determinism makes this exact (same bits as a prefix).
    for &t in &dump_at {
        if t > max_iter {
            continue;
        }
        let ck = fit_kl_with_init(&v, m, n, k, &w0, &h0, t).unwrap_or_else(|e| {
            eprintln!("error: checkpoint at {t}: {e}");
            std::process::exit(2)
        });
        let dir = output_dir.join(format!("ck{t:04}"));
        std::fs::create_dir_all(&dir).unwrap_or_else(|e| die(e));
        write_csv(&dir.join("W.csv"), &ck.w, m, k).unwrap_or_else(|e| die(e));
        write_csv(&dir.join("H.csv"), &ck.h, k, n).unwrap_or_else(|e| die(e));
        let _ = std::fs::write(dir.join("obj.csv"), format!("{:.17e}\n", ck.objective[t]));
    }

    eprintln!(
        "driver: ok (m={m}, n={n}, k={k}, iters={max_iter}, checkpoints={})",
        dump_at.len()
    );
}

fn die(e: std::io::Error) {
    eprintln!("error: {e}");
    std::process::exit(2);
}
