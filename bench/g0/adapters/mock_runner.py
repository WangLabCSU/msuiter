#!/usr/bin/env python3
"""The mock adapter runner — the pipeline self-check placeholder, not a competitor measurement (see adapter_protocol.md §4).

The behaviour: reads counts.csv + catalog.csv; the parametric bootstrap (multinomial resampling →
EM refit → the 2.5/97.5 percentiles) produces the absolute intervals. Reproducible under the same seed.
params.coverage_scale (the default 1.0): the interval-width scaling factor, a test hook —
at 1.0 it should give ≈95% nominal coverage on the multinomial truth (validated by the tests); <1 constructs under-coverage
to drive the judgment's three-way fork.

Usage: mock_runner.py --counts IN --catalog IN --params IN --outdir OUT
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # bench/g0
from g0.lrt import fit_exposures  # noqa: E402


def read_csv_matrix(path: Path):
    with path.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.reader(fh))
    header = [c.strip() for c in rows[0]]
    data = np.array([[float(x) for x in r[1:1 + (len(header) - 1)]] for r in rows[1:]],
                    dtype=float)
    keys = [r[0].strip() for r in rows[1:]]
    return header, keys, data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--counts", required=True)
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--params", required=True)
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()

    params = json.loads(Path(args.params).read_text(encoding="utf-8"))
    seed = int(params.get("seed", 0))
    scale = float(params.get("coverage_scale", 1.0))

    _, chan_labels, counts = read_csv_matrix(Path(args.counts))
    hdr, _chan_keys, catalog = read_csv_matrix(Path(args.catalog))
    # catalog.csv: rows = channels (the first column channel), columns = signatures → W (96, K) (the lrt convention);
    # the signature names are taken from the header columns
    if hdr[0].strip().lower() != "channel" or catalog.shape[0] != 96:
        raise SystemExit("catalog.csv must be channel-major: header 'channel', 96 rows")
    sig_names = [h.strip() for h in hdr[1:1 + catalog.shape[1]]]
    W = catalog
    W = W / W.sum(axis=0, keepdims=True)

    rng = np.random.default_rng(seed)
    out_rows = []
    nboot = 200
    # re-read the sample_id (read_csv_matrix returns only the numeric part)
    with Path(args.counts).open(newline="", encoding="utf-8") as fh:
        sample_ids = [r[0].strip() for r in list(csv.reader(fh))[1:]]

    for sid, x in zip(sample_ids, counts):
        x = x.astype(float)
        total = x.sum()
        if total <= 0:
            for s in sig_names:
                out_rows.append([sid, s, "nan", "nan", "nan", "absolute", 0])
            continue
        h_hat = fit_exposures(x[None, :], W, size=None, max_iter=500)[0]
        mu_hat = h_hat @ W.T
        # the parametric bootstrap: ~Multinomial(N, Wh/ΣWh), refit, the percentile interval
        p_hat = mu_hat / mu_hat.sum()
        boots = rng.multinomial(int(round(total)), p_hat, size=nboot).astype(float)
        h_boot = fit_exposures(boots, W, size=None, max_iter=300)
        lo = np.percentile(h_boot, 2.5, axis=0)
        hi = np.percentile(h_boot, 97.5, axis=0)
        mid = (hi + lo) / 2.0
        lo = np.maximum(mid - scale * (mid - lo), 0.0)
        hi = np.maximum(mid + scale * (hi - mid), lo)
        for j, s in enumerate(sig_names):
            out_rows.append([sid, s, f"{h_hat[j]:.4f}", f"{lo[j]:.4f}",
                             f"{hi[j]:.4f}", "absolute", 0])

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    with (outdir / "intervals.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["sample_id", "signature", "estimate", "lo95", "hi95",
                    "estimand", "zeroed"])
        w.writerows(out_rows)
    (outdir / "errors.log").write_text("", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
