#!/usr/bin/env python3
"""U-M7-02 SigProfilerAssignment v1.1.5 cell runner (memo §2b/§3).

Run inside m7-sigprofiler:spa-1.1.5, launched by adapters/m7_entry.py:
  python3 run_sigprofiler.py --counts <csv> --catalog <csv> --params <json> --outdir <dir>

Assignment executes through the tool's documented entry point
``Analyzer.cosmic_fit`` at documented defaults — COSMIC v3.6 default
reference semantics, ``input_type="matrix"``, ``context_type="96"``
(the README Quick Start invocation) — with **zero** parameter overrides
(memo §3). The result is normalized into the adapter-protocol long table.

Status honesty: this slice never executes the container (digest PENDING-VERIFY
→ adapter refuses). The image build selftest asserts the documented
``SigProfilerAssignment.Analyzer.cosmic_fit`` surface, so API drift fails at
build time, not silently at run time. Where the tool reports no interval it
emits NaN bounds (an absent bound must never masquerade as zero); the tool
documents no seed parameter, so the run is explicitly marked non-seedable in
manifest notes rather than silently assumed reproducible (§3).
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path


def read_counts(path: Path):
    """counts.csv (sample_id × 96 channel columns) → {sample: {channel: n}}."""
    with path.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.reader(fh))
    channels = rows[0][1:]
    return channels, {r[0]: dict(zip(channels, (float(x) for x in r[1:])))
                      for r in rows[1:]}


def write_matrix_input(path: Path, channels, samples):
    """The pinned commit's matrix contract (decomposition.spa_analyze at
    ff61b0f5: read_csv(sep='\t', index_col=0); getProcessAvg dispatches on
    samples.shape[0] == 96): a TSV whose ROWS are the 96 SBS96 channels —
    the canonical A[C>A]A-style labels, the same channel-reference
    vocabulary the G0 simulator emits — and whose COLUMNS are the samples.
    Emitting any other shape makes the tool die inside its positional
    pandas indexing (observed live 2026-10-08 as "single positional
    indexer is out-of-bounds" on the first real cell)."""
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["MutationType", *samples])
        for ch in channels:
            w.writerow([ch, *(int(samples[sid].get(ch, 0)) for sid in samples)])


def normalize_outputs(outdir: Path, intervals_path: Path) -> int:
    """Fold cosmic_fit's assignment outputs into the long table. The primary
    shape is the pinned commit's Activities table
    (output/Assignment_Solution/Activities/Assignment_Solution_Activities.txt:
    header first cell "Samples", ROW labels = the input sample ids, COLUMN
    labels = COSMIC signature identities, values = NNLS assigned counts —
    observed live 2026-10-08). A long Sample/Signature/counts table is
    accepted as a fallback shape; the header sniff is the accept gate. The
    tool's sibling Signatures (MutationType row labels = 96 channels) and
    Decomposed_MutationType_Probabilities (per-mutation) matrices are
    tool-internal, not per-sample exposures: accepting them would relabel
    signature/profile values as samples, so they are deliberately refused and
    an absent Activities table fails the cell loudly. The tool reports no
    interval — absent bounds are emitted as NaN, never masquerading as
    zero-width ones."""
    emitted = 0
    with intervals_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["sample_id", "signature", "estimate", "lo95", "hi95",
                    "estimand", "zeroed"])

        def emit(sid: str, sig: str, est: float) -> None:
            nonlocal emitted
            s = f"{est:.4f}"
            w.writerow([sid, sig, s, "nan", "nan", "absolute",
                        "1" if est == 0.0 else "0"])
            emitted += 1

        # The suite's exposure artefacts land under output/Assignment_Solution
        # (decomposition.spa_analyze, pinned commit); scan the whole tree and
        # let the header sniff be the accept gate. Files we own (underscore
        # prefix, our own intervals table) are never candidates.
        cands = sorted(p for p in {*outdir.rglob("*.csv"), *outdir.rglob("*.txt")}
                       if p.name != intervals_path.name
                       and not p.name.startswith("_"))
        for cand in cands:
            with cand.open(newline="", encoding="utf-8") as src:
                head = src.readline()
                src.seek(0)
                delim = "\t" if head.count("\t") > head.count(",") else ","
                reader = csv.DictReader(src, delimiter=delim)
                fields = [f or "" for f in (reader.fieldnames or [])]
                lowered = {f.strip().lower() for f in fields}
                if {"sample", "signature"} <= lowered and "counts" in lowered:
                    by_lower = {f.strip().lower(): f for f in fields}
                    for row in reader:
                        emit(row[by_lower["sample"]], row[by_lower["signature"]],
                             float(row.get(by_lower["counts"]) or 0.0))
                elif len(fields) > 1 and fields[0].strip().lower() in (
                        "", "sample", "samples", "sample_id"):
                    # exposure table: sample-id row labels, signature columns
                    for row in reader:
                        sid = (row.get(fields[0]) or "").strip()
                        if not sid:
                            continue
                        for sig in fields[1:]:
                            v = (row.get(sig) or "").strip()
                            try:
                                emit(sid, sig, float(v))
                            except ValueError:      # blanks/nan/labels: skip
                                continue
            if emitted:
                break
    return emitted


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--counts", required=True)
    ap.add_argument("--catalog", required=True)      # mounted ref; defaults own it
    ap.add_argument("--params", required=True)
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    errors = outdir / "errors.log"
    errors.write_text("", encoding="utf-8")

    try:
        from SigProfilerAssignment import Analyzer as Analyze
    except ImportError as e:
        errors.write_text(f"FATAL SigProfilerAssignment import failed: {e}\n",
                          encoding="utf-8")
        print(f"run_sigprofiler: import failed: {e}", file=sys.stderr)
        return 1

    channels, samples = read_counts(Path(args.counts))
    matrix_in = outdir / "_input_matrix.csv"
    write_matrix_input(matrix_in, channels, samples)
    fit_out = outdir / "_spa_out"
    fit_out.mkdir(exist_ok=True)

    # Documented defaults (README Quick Start), zero overrides (§3).
    Analyze.cosmic_fit(str(matrix_in), str(fit_out),
                       input_type="matrix", context_type="96")

    emitted = normalize_outputs(fit_out, outdir / "intervals.csv")
    if not emitted:
        errors.write_text("FATAL no assignment rows parsed from cosmic_fit output\n",
                          encoding="utf-8")
        print("run_sigprofiler: no assignment rows parsed", file=sys.stderr)
        return 1
    params = json.loads(Path(args.params).read_text(encoding="utf-8"))
    (outdir / "runner_notes.json").write_text(json.dumps(
        {"competitor": "sigprofiler", "version": params.get("version"),
         "seed": params.get("seed"),
         "non_seedable": "tool documents no seed parameter (memo §3)"},
        sort_keys=True, indent=1), encoding="utf-8")
    print(f"[run_sigprofiler] {emitted} assignment rows -> intervals.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
