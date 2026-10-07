"""Long-table interval parsing — the shared adapter parse surface.

The adapter protocol's long-table schema
(``bench/g0/adapters/adapter_protocol.md`` §2, mirrored by
tests/fixtures/g0_intervals_header.csv)::

    sample_id,signature,estimate,lo95,hi95,estimand,zeroed

The M7 harness consumes it unchanged (test_timings_schema.py pins the
fixture); competitors translate their native outputs into exactly this
shape, so the fairness table and — in the later slice — the Hungarian
P/R/F1 scoring see one record type from every tool.
"""

from __future__ import annotations

import csv
from pathlib import Path

INTERVAL_COLUMNS: tuple[str, ...] = ("sample_id", "signature", "estimate",
                                     "lo95", "hi95", "estimand", "zeroed")


def _num(value: str) -> float:
    """Float coercion with an explicit NaN for missing/unparseable bounds —
    an absent bound must not masquerade as a zero."""
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def parse(path: Path) -> list[dict]:
    """Parse one ``intervals.csv`` into record dicts
    (numeric bounds coerced, ``zeroed`` booleanised). A header-only file
    yields ``[]`` — the empty-parse path is how the four-file guard
    distinguishes 'ran, found nothing' from 'never ran'."""
    records: list[dict] = []
    with Path(path).open(newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            records.append({
                "sample_id": row["sample_id"].strip(),
                "signature": row["signature"].strip(),
                "estimate": _num(row["estimate"]),
                "lo95": _num(row["lo95"]),
                "hi95": _num(row["hi95"]),
                "estimand": (row.get("estimand") or "absolute").strip(),
                "zeroed": str(row.get("zeroed", "0")).strip() in ("1", "True", "true"),
            })
    return records
