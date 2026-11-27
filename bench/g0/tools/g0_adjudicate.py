#!/usr/bin/env python3
"""Post-campaign adjudication summarizer for the G0 primary run (T-7 lane).

Reads the ONE authoritative outdir (the campaign machine syncs it back) and
prints everything the manuscript backfill needs, in one command:

  python3 tools/g0_adjudicate.py --outdir results/docker_primary_pi_<ts>

Sources and authority:
  * the judgment markdown (judgment_primary_<stamp>.md) is AUTHORITATIVE for
    the verdict — it was computed by the frozen `g0.coverage.judge` at full
    precision inside the campaign's final serial pass;
  * the coverage table (coverage_primary_<stamp>.csv) is the number carrier
    for the backfill facts (per-tool x arm x N empirical coverage and CP
    bounds, at the table's own 4-dp rendering);
  * this tool RE-RUNS the frozen judge over the table's absolute-estimand
    cells as a corroboration pass and speaks the comparison honestly:
    CORROBORATED when the verdicts agree, ROUNDTRIP-DRIFT when the 4-dp
    rendering moves a threshold-adjacent cell (the md stays authoritative;
    a drift is an event to read, never silenced).

Fail-closed: a missing outdir, a missing product, an unreadable verdict line
or zero absolute cells exits rc 2 naming its cause. Read-only over its input;
writes nothing.
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # bench/g0/tools
if str(HERE.parent) not in sys.path:
    sys.path.insert(0, str(HERE.parent))

from g0 import coverage as cov                   # noqa: E402
from g0.coverage import CellCoverage             # noqa: E402

TIER1 = ("sigfit", "stl")
CSV_COLS = ("estimand", "tool", "arm", "n", "signature", "layer", "truth_h",
            "k", "n_reps", "coverage", "cp_lo", "cp_hi", "filtered_rate",
            "error_rate", "p1_mechanism_i")


def die2(msg: str) -> None:
    print(f"g0-adjudicate REFUSAL: {msg}", file=sys.stderr)
    sys.exit(2)


def _latest(outdir: Path, stem: str) -> Path:
    hits = sorted(outdir.glob(f"{stem}_primary_*.md" if stem == "judgment"
                              else f"{stem}_primary_*.csv"))
    if not hits:
        die2(f"no {stem}_primary_* product under {outdir} — is this the "
             f"authoritative outdir (PRIMARY-AUTHORITATIVE-RUN-COMPLETE)?")
    return hits[-1]


def _verdict_from_md(md_path: Path) -> tuple[str, str]:
    """(verdict, judged-arm list text) from the md; the verdict line is the
    first `verdict:` line of the embedded judgment.summary() fence."""
    text = md_path.read_text(encoding="utf-8")
    m = re.search(r"^verdict:\s*(\S+)\s*$", text, re.M)
    if not m:
        die2(f"no `verdict:` line in {md_path.name} — not a judgment product")
    arms = re.search(r"arm ∈ (\{[^}]*\})", text)
    return m.group(1), (arms.group(1) if arms else "")


def _cells_from_csv(csv_path: Path) -> list[CellCoverage]:
    cells: list[CellCoverage] = []
    with csv_path.open(newline="", encoding="utf-8") as fh:
        rd = csv.DictReader(fh)
        if tuple(rd.fieldnames or ()) != CSV_COLS:
            die2(f"{csv_path.name}: header drift — {rd.fieldnames}")
        for row in rd:
            if row["estimand"] != "absolute":
                continue          # judge consumes the absolute estimand only
            cells.append(CellCoverage(
                tool=row["tool"], arm=row["arm"], n=int(row["n"]),
                signature=row["signature"], layer=row["layer"],
                truth_h=float(row["truth_h"]), k=int(row["k"]),
                n_reps=int(row["n_reps"]), coverage=float(row["coverage"]),
                cp_lo=float(row["cp_lo"]), cp_hi=float(row["cp_hi"]),
                filtered_rate=float(row["filtered_rate"]),
                error_rate=float(row["error_rate"]),
                p1_mechanism_i=bool(int(row["p1_mechanism_i"]))))
    if not cells:
        die2(f"{csv_path.name}: zero absolute-estimand cells — vacuous table")
    return cells


def _arms_from_md_text(arms_text: str) -> set[str] | None:
    if not arms_text:
        return None
    names = re.findall(r"'([^']+)'", arms_text)
    return set(names) or None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--outdir", required=True,
                    help="the authoritative campaign outdir (synced back)")
    args = ap.parse_args()
    outdir = Path(args.outdir)
    if not outdir.is_dir():
        die2(f"outdir missing: {outdir}")

    md = _latest(outdir, "judgment")
    table = _latest(outdir, "coverage")
    md_verdict, arms_text = _verdict_from_md(md)
    judge_arms = _arms_from_md_text(arms_text)

    cells = _cells_from_csv(table)
    judged = cov.judge(cells, tier1_tools=TIER1, judge_arms=judge_arms)

    agree = "CORROBORATED" if judged.verdict == md_verdict else "ROUNDTRIP-DRIFT"

    js = [c for c in cells if judge_arms is None or c.arm in judge_arms]
    t1 = [c for c in js if c.tool in TIER1]

    print(f"g0-adjudicate: outdir={outdir}")
    print(f"  judgment product : {md.name} (authoritative)")
    print(f"  coverage product : {table.name}")
    print(f"  verdict          : {md_verdict}  [{agree}: table recompute -> {judged.verdict}]")
    print(f"  judged arms      : {sorted(judge_arms) if judge_arms else '(md carried no arm list)'}")
    print(f"  judged cells     : {len(js)} absolute ({len(t1)} tier-1 {TIER1})")
    print()
    print("--- judgment detail (md, verbatim block) ---")
    fence = re.search(r"```\n(.*?)\n```", md.read_text(encoding="utf-8"), re.S)
    print(fence.group(1) if fence else "(no summary fence found)")
    print()
    print("--- backfill facts (table-carried, 4-dp rendering) ---")
    if t1:
        lo = min(c.coverage for c in t1)
        hi = max(c.coverage for c in t1)
        hi_lo = min(c.cp_hi for c in t1)
        npts = sorted({c.n for c in t1})
        tools = sorted({c.tool for c in t1})
        print(f"  tier-1 tools          : {', '.join(tools)}")
        print(f"  grid N points         : {len(npts)} ({npts[0]}..{npts[-1]})")
        print(f"  empirical coverage (tier-1, judged arms): min {lo:.4f} / max {hi:.4f}")
        print(f"  min CP-95 upper bound : {hi_lo:.4f}")
    if md_verdict == "A":
        print("  framing               : A — the calibrated-inference headline HOLDS")
    elif md_verdict == "B":
        print("  framing               : B — the coverage headline is falsified; the ecosystem framing takes over")
    else:
        print("  framing               : GRAY — the borderline doubling flow applies first:")
        print("    python3 run_grid.py --profile primary --adapter docker --provider cosmic-file "
              "--reps 400 --outdir <gray outdir>")
        if judged.borderline_cells:
            print("    borderline cells: " + "; ".join(judged.borderline_cells))
    print()
    print("  manuscript gates to unblock: paper/paper-draft.qmd:25 (title slot),"
          " :65 (abstract), :160 (Fig. 1 data panel), :998 (fig-roster cell)")
    print("  procedure: paper/devlog-2026-11-28-g0-resume-runbook.qmd §3-§4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
