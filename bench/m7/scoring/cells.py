"""Cell-artifact discovery and prediction-table loading (read side).

The scoring slice consumes exactly what the run path committed:
``<cachedir>/cells/<tool>__<arm>__N<n>/out/{intervals.csv,errors.log,
manifest.json,timing.json}``. The four-file set is the run path's own
``GUARD_FILES`` (imported, never restated) — the same sidecars the fairness
table attests, so a cell that could not be attested cannot be scored either.
A cell missing any guard file is *reported* skipped (skip-not-skip on the
read side), never silently dropped from the table.

Two artifacts corruptions are contract violations and must fail loudly
(``CellContractError``) instead of quietly skewing a mean:

* a ``sample_id`` that parses but points outside the cell's own
  ``(arm, N)`` — crossed cells would attribute samples to the wrong strata;
* a duplicated ``(sample_id, signature)`` call row — double counting.

The estimand filter is applied before the duplicate check and keeps the
``absolute`` main estimand only (G0 judgment precedent); dropped rows are
counted into the cell's ``notes`` so the filter is auditable, not invisible.

One *optional* sidecar is additionally consumed: ``out/spectra.csv`` (long
form ``signature,channel,value``) — the witness by which a de novo
prediction's committed spectrum can be observed by the scoring side. Its
absence is legal (catalog-name regimes commit none); its corruption is not.
"""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path

from competitors.intervals import parse as parse_intervals
from run_bench import GUARD_FILES                       # single source of truth

CELL_KEY_SEPARATOR = "__"
CELL_N_PREFIX = "N"
SAMPLE_ID_RE = re.compile(r"^(?P<arm>.+)__N(?P<n>\d+)__r(?P<rep>\d+)$")
MAIN_ESTIMAND = "absolute"
SPECTRA_FILE = "spectra.csv"
_SPECTRA_KEYS = frozenset({"signature", "channel", "value"})


class CellContractError(RuntimeError):
    """A committed cell artifact violates the adapter/cell contract."""


def parse_cell_key(name: str):
    """``<tool>__<arm>__N<n>`` -> ``(tool, arm, n)``; ``None`` when the
    directory name is not a cell key (reported, not scored)."""
    parts = name.rsplit(CELL_KEY_SEPARATOR, 2)
    if len(parts) != 3:
        return None
    tool, arm, tail = parts
    if not tail.startswith(CELL_N_PREFIX) or not tail[len(CELL_N_PREFIX):].isdigit():
        return None
    return tool, arm, int(tail[len(CELL_N_PREFIX):])


def discover_cells(cachedir: Path | str) -> list:
    """Deterministic (name-sorted) cell directory enumeration."""
    root = Path(cachedir) / "cells"
    if not root.is_dir():
        return []
    return sorted((p for p in root.iterdir() if p.is_dir()),
                  key=lambda p: p.name)


def missing_guard_files(cell_dir: Path | str) -> list:
    """Guard files absent from ``out/`` (empty list == scorable)."""
    out = Path(cell_dir) / "out"
    return [n for n in GUARD_FILES if not (out / n).exists()]


def read_cell_version(cell_dir: Path | str) -> str:
    """The committed competitor version from ``manifest.json`` — part of the
    table's provenance, never inferred. Malformed manifest is a violation."""
    manifest = Path(cell_dir) / "out" / "manifest.json"
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
        version = str(data["version"])
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise CellContractError(
            f"{cell_dir}: manifest.json unreadable/incomplete ({e!r})") from None
    return version


def load_cell_predictions(out_dir: Path | str, arm: str, n: int):
    """``({sample_id: {signature: interval-record}}, dropped_estimand_rows)``.

    Validates against the cell's own ``(arm, N)`` and raises
    ``CellContractError`` on crossed sample ids or duplicated call rows
    (module docstring). Only the ``absolute`` main estimand survives."""
    recs = parse_intervals(Path(out_dir) / "intervals.csv")
    per_sample: dict = {}
    seen: set = set()
    dropped = 0
    for rec in recs:
        if rec["estimand"] != MAIN_ESTIMAND:
            dropped += 1
            continue
        sid = rec["sample_id"]
        m = SAMPLE_ID_RE.match(sid)
        if m is None or m["arm"] != arm or int(m["n"]) != int(n):
            raise CellContractError(
                f"{out_dir}: sample_id {sid!r} does not belong to cell "
                f"(arm={arm!r}, N={n})")
        key = (sid, rec["signature"])
        if key in seen:
            raise CellContractError(
                f"{out_dir}: duplicated call row for {key!r} — refusing to "
                f"double-count a signature in one sample")
        seen.add(key)
        per_sample.setdefault(sid, {})[rec["signature"]] = rec
    return per_sample, dropped


def load_cell_spectra(out_dir: Path | str) -> dict:
    """Optional witness sidecar ``out/spectra.csv`` -> ``{signature: {channel:
    value}}``; ``{}`` when the cell committed no witness (the legal catalog-
    name regime). The witness is long form ``signature,channel,value`` and is
    read under the same fail-loud contract as the prediction table: a missing
    column, a duplicated ``(signature, channel)`` claim, or a non-numeric
    value is a ``CellContractError`` — a half-believed witness is worse than
    none, it manufactures a cosine out of partial evidence."""
    path = Path(out_dir) / SPECTRA_FILE
    if not path.exists():
        return {}
    spectra: dict = {}
    seen: set = set()
    with path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None or not _SPECTRA_KEYS <= set(reader.fieldnames):
            raise CellContractError(
                f"{path}: spectra witness must be long form "
                f"signature,channel,value (got {reader.fieldnames!r})")
        for row in reader:
            sig, ch = row["signature"], row["channel"]
            if not sig or not ch:
                raise CellContractError(
                    f"{path}: spectra witness row with empty "
                    f"signature/channel: {row!r}")
            if (sig, ch) in seen:
                raise CellContractError(
                    f"{path}: duplicated witness claim for {(sig, ch)!r} — "
                    f"refusing to arbitrate two values of one channel")
            seen.add((sig, ch))
            try:
                val = float(row["value"])
            except (TypeError, ValueError) as e:
                raise CellContractError(
                    f"{path}: non-numeric witness value {row['value']!r} "
                    f"for {(sig, ch)!r}") from None
            spectra.setdefault(sig, {})[ch] = val
    return spectra
