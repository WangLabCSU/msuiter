"""Scoring entry point: committed cells -> benchmark CSV -> judgment verdicts.

Two products, one pure pass over the cachedir (``score_cachedir``):

* ``benchmark_m7_<ts>.csv`` — one long table with four row classes:
  ``cell`` (per tool/arm/N P/R/F1), ``signature`` (per-signature
  exposure-error rows, ``na`` for absent bounds), ``arm_rollup`` and
  ``n_rollup`` (count-pooled aggregations; rollups pool TP/FP/FN **then**
  derive, so a long tail of low-N cells cannot outvote volume by averaging).
* the scoring-verdict sections appended to the fairness attestation document
  (the fairness half's bytes are preserved; the append adds the frozen
  "harness output; adjudication only via the frozen protocol" framing and the
  honest authoritative-classes footer, G0 judgment-document precedent).

Determinism is a hard rule: the row list is canonically sorted, numbers are
rendered with fixed 6-decimal formatting, NaN renders as ``na``, and the
timestamp is file-name metadata only. Same cachedir => byte-identical CSV.

Match attribution convention: a matched (prediction, truth) pair counts as
one TP on **both** signature rows it names, while the exposure error is
carried on the TRUTH signature's row (the error is a deviation of that
truth exposure). Below-tolerance pairs are rejected by the matcher, so they
fall out as FP/FN — never as weak matches.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, field
from pathlib import Path

from . import cells, match, metrics, truth
from .judgment import append_verdict_sections      # noqa: F401 — test seam

BENCHMARK_COLUMNS: tuple = (
    "row_type", "tool", "version", "profile", "adapter", "arm",
    "judge_class", "N", "signature", "layer", "n_samples", "truth_calls",
    "pred_calls", "tp", "fp", "fn", "precision", "recall", "f1",
    "mean_match_cosine", "mean_abs_exposure_error",
    "mean_rel_exposure_error", "match_tolerance", "status", "notes",
)
_INT_COLS = frozenset({"N", "n_samples", "truth_calls", "pred_calls",
                       "tp", "fp", "fn"})
_FLOAT_COLS = frozenset({"precision", "recall", "f1", "mean_match_cosine",
                         "mean_abs_exposure_error", "mean_rel_exposure_error",
                         "match_tolerance"})
_ROW_RANK = {"cell": 0, "signature": 1, "arm_rollup": 2, "n_rollup": 3}

_SKIP_BAD_KEY = "skipped:bad-cell-key"
_SKIP_NO_ARTIFACTS = "skipped:no-artifacts"
_SKIP_UNKNOWN_ARM = "skipped:unknown-arm"


@dataclass
class BenchmarkReport:
    """Rows + tallies of one score pass (rows carry pre-format values; the
    CSV layer owns textual representation)."""

    rows: list = field(default_factory=list)
    skipped: list = field(default_factory=list)      # [(cell_name, reason)]
    cells_scored: int = 0
    samples_scored: int = 0
    matches: int = 0

    def row(self, row_type: str, *, tool=None, arm=None, N=None,
            signature=None, judge_class=None) -> dict:
        """Unique-row selector — asserts exactly one match, so a test can
        never pass against an ambiguous or missing row."""
        want = {"row_type": row_type, "tool": tool, "arm": arm, "N": N,
                "signature": signature, "judge_class": judge_class}
        got = [r for r in self.rows
               if all(r[k] == v for k, v in want.items() if v is not None)]
        if len(got) != 1:
            key = lambda r: (r["row_type"], r["tool"], r["arm"], r["N"],
                            r["signature"])
            raise AssertionError(
                f"expected exactly one {row_type!r} row for "
                f"{ {k: v for k, v in want.items() if v is not None} }, "
                f"found {len(got)}: {[key(r) for r in got]}")
        return got[0]


def _empty_row(row_type: str) -> dict:
    return {col: None for col in BENCHMARK_COLUMNS} | {"row_type": row_type}


def _new_sig_acc() -> dict:
    return {"tp": 0, "fp": 0, "fn": 0, "truth_n": 0, "pred_n": 0,
            "cos": [], "abs_err": [], "rel_err": []}


def _sample_prf(tp: int, fp: int, fn: int) -> tuple:
    return metrics.precision_recall_f1(tp, fp, fn)


def _score_cell(cell_dir: Path, profile: str, provider) -> dict:
    """Score one cell into ``{"cell_row": ..., "sig_rows": ..., ...}``. An
    unscorable cell yields a ``cell_row`` with a ``skipped:*`` status (never
    a silent drop). Raises CellContractError on corruption — see the
    skip/score/error split in ``scoring.cells``."""
    name = cell_dir.name
    key = cells.parse_cell_key(name)
    if key is None:
        return {"cell_row": _skip_row(name, name, _SKIP_BAD_KEY)}
    tool, arm, n = key
    if cells.missing_guard_files(cell_dir):
        return {"cell_row": _skip_row(name, tool, _SKIP_NO_ARTIFACTS)}
    try:
        jclass = truth.judge_class(profile, arm)
    except ValueError:
        return {"cell_row": _skip_row(name, tool, _SKIP_UNKNOWN_ARM,
                                       arm=arm, N=n)}

    truth_map = truth.cell_truth(profile, arm, n)
    if not truth_map:
        raise cells.CellContractError(
            f"{name}: frozen composition yields no present truth signature")
    version = cells.read_cell_version(cell_dir)
    per_sample, dropped = cells.load_cell_predictions(cell_dir / "out",
                                                     arm=arm, n=n)
    t_sigs = sorted(truth_map)
    called_union = sorted({rec_sig for calls in per_sample.values()
                           for rec_sig in calls})
    cos_rows = {sig: [0.0 if truth.catalog_vector(provider, sig) is None else
                      match.cosine(truth.catalog_vector(provider, sig),
                                   truth.truth_vector(provider, t))
                      for t in t_sigs] for sig in called_union}

    acc: dict = {}
    cell_prf, cell_cos = [], []
    tp = fp = fn = truth_calls = pred_calls = 0
    for sid in sorted(per_sample):
        calls = {sig: rec for sig, rec in per_sample[sid].items()
                 if metrics.is_countable_call(rec["estimate"], rec["zeroed"])}
        called = sorted(calls)
        s_tp, s_fp, s_fn = 0, len(called), len(t_sigs)
        for t in t_sigs:
            acc.setdefault(t, _new_sig_acc())["truth_n"] += 1
        for sig in called:
            acc.setdefault(sig, _new_sig_acc())["pred_n"] += 1
        pairs = match.hungarian_assign([cos_rows[sig] for sig in called],
                                       min_cosine=match.MATCH_MIN_COSINE) \
            if called else []
        matched_p, matched_t = set(), set()
        for pi, ti, cos in pairs:
            p_sig, t_sig = called[pi], t_sigs[ti]
            acc[p_sig]["tp"] += 1
            if t_sig != p_sig:
                acc[t_sig]["tp"] += 1
            est = calls[p_sig]["estimate"]
            a, r = metrics.exposure_errors(est, truth_map[t_sig])
            acc[t_sig]["cos"].append(cos)
            acc[t_sig]["abs_err"].append(a)
            acc[t_sig]["rel_err"].append(r)
            cell_cos.append(cos)
            matched_p.add(p_sig)
            matched_t.add(t_sig)
            s_tp += 1
        s_fp = len(called) - s_tp
        s_fn = len(t_sigs) - s_tp
        for sig in set(called) - matched_p:
            acc[sig]["fp"] += 1
        for t in set(t_sigs) - matched_t:
            acc[t]["fn"] += 1
        cell_prf.append(_sample_prf(s_tp, s_fp, s_fn))
        tp += s_tp
        fp += s_fp
        fn += s_fn
        truth_calls += len(t_sigs)
        pred_calls += len(called)

    uncatalogued = {sig for sig in acc
                    if truth.catalog_vector(provider, sig) is None}
    notes = []
    if dropped:
        notes.append(f"estimand-rows-dropped={dropped}")
    cell_row = _empty_row("cell") | {
        "tool": tool, "version": version, "arm": arm, "judge_class": jclass,
        "N": n, "n_samples": len(per_sample), "truth_calls": truth_calls,
        "pred_calls": pred_calls, "tp": tp, "fp": fp, "fn": fn,
        "precision": _mean3(cell_prf, 0), "recall": _mean3(cell_prf, 1),
        "f1": _mean3(cell_prf, 2),
        "mean_match_cosine": metrics.mean_or_none(cell_cos),
        "match_tolerance": match.MATCH_MIN_COSINE,
        "status": "scored", "notes": ";".join(notes)}
    sig_rows = []
    for sig in sorted(set(acc) | set(t_sigs)):
        a = acc.setdefault(sig, _new_sig_acc())
        status = ("matched" if a["tp"] else
                  "missed" if a["truth_n"] else
                  "false_called" if a["pred_n"] else "empty")
        sig_rows.append(_empty_row("signature") | {
            "tool": tool, "version": version, "arm": arm,
            "judge_class": jclass, "N": n, "signature": sig,
            "layer": truth.signature_layer(sig) or None,
            "n_samples": len(per_sample), "truth_calls": a["truth_n"],
            "pred_calls": a["pred_n"], "tp": a["tp"], "fp": a["fp"],
            "fn": a["fn"],
            "mean_match_cosine": metrics.mean_or_none(a["cos"]),
            "mean_abs_exposure_error": metrics.mean_or_none(a["abs_err"]),
            "mean_rel_exposure_error": metrics.mean_or_none(a["rel_err"]),
            "match_tolerance": match.MATCH_MIN_COSINE, "status": status,
            "notes": "uncatalogued" if sig in uncatalogued else ""})
    return {"cell_row": cell_row, "sig_rows": sig_rows, "version": version,
            "sample_count": len(per_sample), "counts": (tp, fp, fn, truth_calls,
                                                       pred_calls), "jclass": jclass}


def _skip_row(name: str, tool, reason: str, *, arm=None, N=None) -> dict:
    return _empty_row("cell") | {"tool": tool, "arm": arm, "N": N,
                                 "status": reason,
                                 "n_samples": 0, "truth_calls": 0,
                                 "pred_calls": 0, "tp": 0, "fp": 0, "fn": 0}


def _mean3(prf_list, idx):
    return metrics.mean_or_none([t[idx] for t in prf_list])


def score_cachedir(cachedir: Path | str, *, profile: str,
                   provider_name: str = "synthetic",
                   provider_seed: int = 0) -> BenchmarkReport:
    """One deterministic scoring pass over every committed cell of the
    cachedir (pure read; see module docstring)."""
    provider = truth.load_provider(provider_name, provider_seed)
    report = BenchmarkReport()
    pools: dict = {}
    tool_versions: dict = {}
    for cell_dir in cells.discover_cells(cachedir):
        outcome = _score_cell(cell_dir, profile, provider)
        if outcome["cell_row"]["status"] != "scored":
            report.skipped.append((cell_dir.name, outcome["cell_row"]["status"]))
            report.rows.append(outcome["cell_row"])
            continue
        report.rows.append(outcome["cell_row"])
        report.rows.extend(outcome["sig_rows"])
        report.cells_scored += 1
        report.samples_scored += outcome["sample_count"]
        report.matches += outcome["counts"][0]
        tool_versions.setdefault(outcome["cell_row"]["tool"], outcome["version"])
        _pool(pools, ("arm", outcome["cell_row"]["tool"],
                      outcome["cell_row"]["arm"], outcome["cell_row"]["judge_class"]),
              outcome)
        _pool(pools, ("N", outcome["cell_row"]["tool"], None,
                      outcome["cell_row"]["judge_class"],
                      outcome["cell_row"]["N"]), outcome)
    report.rows.extend(_rollup_rows(pools, tool_versions))
    report.rows.sort(key=_row_order)
    return report


def _pool(pools: dict, key: tuple, outcome: dict) -> None:
    tp, fp, fn, truth_calls, pred_calls = outcome["counts"]
    p = pools.setdefault(key, {"tp": 0, "fp": 0, "fn": 0, "truth_calls": 0,
                               "pred_calls": 0, "n_samples": 0})
    p["tp"] += tp
    p["fp"] += fp
    p["fn"] += fn
    p["truth_calls"] += truth_calls
    p["pred_calls"] += pred_calls
    p["n_samples"] += outcome["sample_count"]


def _rollup_rows(pools: dict, tool_versions: dict) -> list:
    """Count-pooled rollups (documented convention): pool TP/FP/FN across the
    stratum, derive P/R/F1 from the pooled counts, once. Exposure/cosine
    means are cell-level facts and stay ``na`` on rollup rows on purpose —
    averaging averages is not defined here."""
    rows = []
    for key, p in pools.items():
        kind = key[0]
        tool = key[1]
        arm, jclass = (key[2], key[3]) if kind == "arm" else (None, key[3])
        n = key[4] if kind == "N" else None
        pr, rc, f1 = metrics.precision_recall_f1(p["tp"], p["fp"], p["fn"])
        rows.append(_empty_row("arm_rollup" if kind == "arm" else "n_rollup") | {
            "tool": tool, "version": tool_versions.get(tool, "unknown"),
            "arm": arm, "judge_class": jclass, "N": n,
            "n_samples": p["n_samples"], "truth_calls": p["truth_calls"],
            "pred_calls": p["pred_calls"], "tp": p["tp"], "fp": p["fp"],
            "fn": p["fn"], "precision": pr, "recall": rc, "f1": f1,
            "match_tolerance": match.MATCH_MIN_COSINE, "status": "pooled"})
    return rows


def _row_order(row: dict) -> tuple:
    return (_ROW_RANK[row["row_type"]], row["tool"] or "", row["arm"] or "",
             -1 if row["N"] is None else row["N"], row["signature"] or "")


def _fmt(col: str, value) -> str:
    if value is None:
        return "na" if col in _FLOAT_COLS else ""
    if col in _FLOAT_COLS:
        v = float(value)
        return "na" if v != v else f"{v:.6f}"
    if col in _INT_COLS:
        return str(int(value))
    return str(value)


def write_benchmark_csv(report: BenchmarkReport, path: Path | str, *,
                        meta: dict) -> Path:
    """Render the frozen header + canonically sorted rows; ``meta`` supplies
    the two provenance columns (profile/adapter) so table bytes stay a pure
    function of cachedir + meta."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(list(BENCHMARK_COLUMNS))
        for row in report.rows:
            w.writerow([_fmt(col, meta.get(col) if col in ("profile", "adapter")
                                   else row.get(col))
                        for col in BENCHMARK_COLUMNS])
    return path


def emit(*, cachedir, outdir, profile: str, adapter: str, provider: str,
         provider_seed: int, ts: str, judgment_path) -> tuple:
    """Final-pass entry called by the orchestrator: one pure score pass over
    the cachedir -> ``benchmark_m7_<ts>.csv`` in the authoritative outdir ->
    verdict sections appended to the judgment document. Returns
    ``(csv_path, report)``."""
    report = score_cachedir(cachedir, profile=profile,
                            provider_name=provider, provider_seed=provider_seed)
    meta = {"profile": profile, "adapter": adapter}
    bench = write_benchmark_csv(report,
                                Path(outdir) / f"benchmark_m7_{ts}.csv", meta=meta)
    append_verdict_sections(judgment_path, report, meta)
    return bench, report
