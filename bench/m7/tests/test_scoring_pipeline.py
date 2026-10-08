"""⑧ End-to-end scoring over committed cell artifacts (synthetic fixtures).

Drives scoring.run_products.score_cachedir over a hand-built cachedir whose
truth-vs-prediction tables are closed-form, so every expectation below is
arithmetic, not measurement:

  main@N=1000 (primary):      r0 perfect | r1 misses SBS40, SBS5 over-called
                              | r2 perfect + SBS4 + an uncatalogued NOPE99 call
  nb@N=1000   (sensitivity):  all reps call only SBS40 (SBS5 -> miss, the
                              one-to-one gate claims SBS40 at cos 1.0)
  main@N=100  (broken cell):  manifest.json never committed -> skipped
  bogus arm cell:              not in the frozen grid      -> skipped

The four-file guard files decide scorability; the estimand filter keeps the
absolute main estimand only; duplicate/crossed rows are contract violations
that must fail loudly instead of skewing a mean.
"""

from __future__ import annotations

import csv
import math
import re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from scoring import run_products                     # noqa: E402 (RED seam)
from scoring.cells import CellContractError          # noqa: E402 (RED seam)
from tests import scoring_fixtures as fx

MAIN_TRUTH = {"SBS1": 150.0, "SBS2": 150.0, "SBS13": 150.0,
              "SBS5": 300.0, "SBS40": 250.0}


def _build_fixture() -> Path:
    root = fx.tmp_cachedir()
    perfect = dict(MAIN_TRUTH)
    fx.write_cell(root, fx.TOOL, "main", 1000, {
        0: perfect,
        1: {"SBS1": 150.0, "SBS2": 150.0, "SBS13": 150.0, "SBS5": 550.0},
        2: {**perfect, "SBS4": 40.0, "NOPE99": 30.0},
    })
    fx.write_cell(root, fx.TOOL, "nb", 1000, {r: {"SBS40": 250.0}
                                               for r in range(3)})
    fx.write_cell(root, fx.TOOL, "main", 100, {0: {"SBS1": 15.0}},
                  drop={"manifest.json"})
    fx.write_cell(root, "rogue", "bogusarm", 1000, {0: {"SBS1": 1.0}})
    return root


def _scored(root: Path):
    return run_products.score_cachedir(root, profile="smoke",
                                       provider_name="synthetic",
                                       provider_seed=0)


def test_cell_tally_and_skip_reporting_are_honest():
    """skip-not-skip discipline on the read side too: an unscorable cell is
    reported as a skipped row, never silently dropped from the table."""
    rep = _scored(_build_fixture())
    assert rep.cells_scored == 2, rep.cells_scored
    assert rep.samples_scored == 6 and rep.matches == 17, \
        f"samples={rep.samples_scored} matches={rep.matches}"
    skipped = dict(rep.skipped)
    assert skipped.get(f"{fx.TOOL}__main__N100") == "skipped:no-artifacts", skipped
    assert skipped.get("rogue__bogusarm__N1000") == "skipped:unknown-arm", skipped


def test_main_cell_metrics_are_the_closed_form_consequence_of_the_fixture():
    rep = _scored(_build_fixture())
    row = rep.row("cell", tool=fx.TOOL, arm="main", N=1000)
    assert row["tp"] == 14 and row["fp"] == 2 and row["fn"] == 1, row
    assert row["truth_calls"] == 15 and row["pred_calls"] == 16, row
    # per-sample means: r0 (1,1,1); r1 (1,4/5,F1(.8)); r2 (5/7,1,F1(5/7))
    f1_r1 = 2.0 * 0.8 / 1.8
    p_r2, f1_r2 = 5.0 / 7.0, 2.0 * (5.0 / 7.0) / (5.0 / 7.0 + 1.0)
    assert abs(row["precision"] - (1.0 + 1.0 + p_r2) / 3.0) < 1e-12, row["precision"]
    assert abs(row["recall"] - (1.0 + 0.8 + 1.0) / 3.0) < 1e-12, row["recall"]
    assert abs(row["f1"] - (1.0 + f1_r1 + f1_r2) / 3.0) < 1e-12, row["f1"]
    assert row["status"] == "scored" and row["judge_class"] == "primary"
    assert row["match_tolerance"] == 0.85


def test_exposure_error_rows_carry_errors_only_on_matched_bounds():
    rep = _scored(_build_fixture())
    sbs5 = rep.row("signature", tool=fx.TOOL, arm="main", N=1000, signature="SBS5")
    assert sbs5["status"] == "matched" and sbs5["tp"] == 3
    assert abs(sbs5["mean_abs_exposure_error"] - 250.0 / 3.0) < 1e-12
    assert abs(sbs5["mean_rel_exposure_error"] - (250.0 / 300.0) / 3.0) < 1e-12
    assert sbs5["layer"] == "flat", sbs5
    sbs40 = rep.row("signature", tool=fx.TOOL, arm="main", N=1000, signature="SBS40")
    assert (sbs40["tp"], sbs40["fn"]) == (2, 1) and sbs40["status"] == "matched"
    assert sbs40["mean_abs_exposure_error"] == 0.0
    # uncatalogued prediction: FP by definition, never matched, errors absent
    nope = rep.row("signature", tool=fx.TOOL, arm="main", N=1000, signature="NOPE99")
    assert nope["status"] == "false_called" and nope["tp"] == 0
    assert nope["mean_abs_exposure_error"] is None            # -> "na" in CSV
    assert "uncatalogued" in (nope["notes"] or "")
    sbs4 = rep.row("signature", tool=fx.TOOL, arm="main", N=1000, signature="SBS4")
    assert sbs4["status"] == "false_called" and sbs4["fp"] == 1


def test_sensitivity_arms_roll_up_under_their_own_judge_class():
    """nb cells score (report-only columns) but the frozen grid marks them
    judge=False, so they never mix into the primary verdict aggregation."""
    rep = _scored(_build_fixture())
    row = rep.row("cell", tool=fx.TOOL, arm="nb", N=1000)
    assert row["judge_class"] == "sensitivity"
    assert row["tp"] == 3 and row["fp"] == 0 and row["fn"] == 12, row
    assert abs(row["recall"] - 3.0 / 15.0) < 1e-12
    n_row = rep.row("n_rollup", tool=fx.TOOL, judge_class="sensitivity", N=1000)
    assert (n_row["tp"], n_row["fp"], n_row["fn"]) == (3, 0, 12)
    assert n_row["precision"] == 1.0 and abs(n_row["recall"] - 0.2) < 1e-12
    prim = rep.row("n_rollup", tool=fx.TOOL, judge_class="primary", N=1000)
    assert prim["tp"] == 14


def test_arm_rollup_pools_counts_then_derives_prf():
    """The documented rollup convention: pooled TP/FP/FN -> P/R/F1 (not a
    mean of means), so arms with many low-N cells cannot outvote volume."""
    rep = _scored(_build_fixture())
    row = rep.row("arm_rollup", tool=fx.TOOL, arm="main")
    assert (row["tp"], row["fp"], row["fn"]) == (14, 2, 1) and row["n_samples"] == 3
    p, r = 14.0 / 16.0, 14.0 / 15.0
    assert abs(row["precision"] - p) < 1e-12 and abs(row["recall"] - r) < 1e-12
    assert abs(row["f1"] - 2.0 * p * r / (p + r)) < 1e-12


def test_benchmark_csv_is_a_frozen_header_with_stable_number_format():
    root = _build_fixture()
    out = root / "benchmark_m7_test_ts.csv"
    rep = _scored(root)
    run_products.write_benchmark_csv(rep, out,
                                     meta={"profile": "smoke", "adapter": "mock"})
    with out.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.reader(fh))
    assert rows[0] == list(run_products.BENCHMARK_COLUMNS)
    body = [dict(zip(rows[0], r)) for r in rows[1:]]
    assert body, "fixture run must emit scored rows"
    num_re = re.compile(r"^(\d+\.\d{6}|na|)$")
    for col in ("precision", "recall", "f1", "mean_match_cosine",
                "mean_abs_exposure_error", "mean_rel_exposure_error"):
        for r in body:
            assert num_re.match(r[col]), f"{col}={r[col]!r} not 6dp/na form"
    nope = [r for r in body
            if r["row_type"] == "signature" and r["signature"] == "NOPE99"][0]
    assert nope["mean_abs_exposure_error"] == "na"


def test_estimand_filter_keeps_the_absolute_main_estimand_only():
    """A stray raw-estimand duplicate row must be dropped (counted in notes),
    never double-counted against precision."""
    root = _build_fixture()
    path = fx.cell_dir(root, fx.TOOL, "main", 1000) / "out" / "intervals.csv"
    with path.open("a", newline="", encoding="utf-8") as fh:
        csv.writer(fh, lineterminator="\n").writerow(
            ["main__N1000__r0", "SBS40", "250.0000", "250.0000", "250.0000",
             "raw", "0"])
    rep = _scored(root)
    row = rep.row("cell", tool=fx.TOOL, arm="main", N=1000)
    assert row["pred_calls"] == 16, "raw row leaked into the call set"
    assert "estimand-rows-dropped=1" in row["notes"], row["notes"]


def test_corrupted_cell_artifacts_fail_loudly_not_quietly():
    """Cell-contract violations (sample id crossed out of the cell, or a
    duplicated (sample, signature) call row) are hard errors: silent skew
    of a benchmark table is the failure mode this slice exists to prevent."""
    root = fx.tmp_cachedir()
    try:
        cd = fx.write_cell(root, fx.TOOL, "main", 100, {0: {"SBS1": 15.0}})
        header = "sample_id,signature,estimate,lo95,hi95,estimand,zeroed\n"
        (cd / "out" / "intervals.csv").write_text(
            header + "main__N1000__r0,SBS1,15,15,15,absolute,0\n",
            encoding="utf-8")           # N=1000 inside a N=100 cell key
        try:
            run_products.score_cachedir(root, profile="smoke",
                                        provider_name="synthetic", provider_seed=0)
        except CellContractError:
            pass
        else:
            raise AssertionError("crossed sample_id must raise CellContractError")
        (cd / "out" / "intervals.csv").write_text(
            header + "main__N100__r0,SBS1,15,15,15,absolute,0\n"
                     "main__N100__r0,SBS1,16,16,16,absolute,0\n",
            encoding="utf-8")           # duplicated call for the same sample
        try:
            run_products.score_cachedir(root, profile="smoke",
                                        provider_name="synthetic", provider_seed=0)
        except CellContractError:
            pass
        else:
            raise AssertionError("duplicate call row must raise CellContractError")
    finally:
        fx.cleanup(root)


def test_scoring_an_empty_cachedir_is_well_defined():
    """No cells at all => an empty-but-valid table, not an exception (the
    final pass runs over caches that legitimately start empty)."""
    root = fx.tmp_cachedir(prefix="m7sc_empty_")
    try:
        rep = _scored(root)
        assert rep.cells_scored == 0 and rep.rows == []
        out = root / "benchmark_m7_empty.csv"
        run_products.write_benchmark_csv(rep, out, meta={"profile": "smoke",
                                                         "adapter": "mock"})
        assert out.read_text(encoding="utf-8").splitlines() \
            == [",".join(run_products.BENCHMARK_COLUMNS)]
    finally:
        fx.cleanup(root)
