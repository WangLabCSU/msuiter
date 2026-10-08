"""Synthetic truth-vs-prediction fixtures for the scoring pipeline tests.

Not a test module (no test_* names, absent from tests.run_all's MODULES):
it builds a *committed* cell layout under a scratch cachedir — the exact
shape the scoring slice consumes as read-only input. Cells are hand-built
(never run through a competitor) so the expected metrics are a closed-form
consequence of the fixture, independent of any adapter.
"""

from __future__ import annotations

import csv
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors.intervals import INTERVAL_COLUMNS   # the shared parse surface

GUARD_FILES = ("intervals.csv", "errors.log", "manifest.json", "timing.json")

TOOL = "fixturetool"
VERSION = "fixture-1"


def tmp_cachedir(prefix="m7sc_") -> Path:
    return Path(tempfile.mkdtemp(prefix=prefix))


def cleanup(root: Path) -> None:
    shutil.rmtree(root, ignore_errors=True)


def _write_intervals(path: Path, rows: list) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(list(INTERVAL_COLUMNS))
        w.writerows(rows)


def cell_dir(root: Path, tool: str, arm: str, n: int) -> Path:
    return root / "cells" / f"{tool}__{arm}__N{n}"


def write_cell(root: Path, tool: str, arm: str, n: int, samples: dict,
               *, drop: set | None = None, manifest_extra: dict | None = None,
               estimand: str = "absolute") -> Path:
    """Commit one cell. ``samples`` maps rep -> {signature: estimate};
    estimates of None emit NaN bound cells (the 'ran, found nothing' shape).

    ``drop`` removes named guard files afterwards (simulates a cell whose
    attestation sidecars never landed -> scoring must not score it).
    """
    cd = cell_dir(root, tool, arm, n)
    out = cd / "out"
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for rep in sorted(samples):
        sid = f"{arm}__N{n}__r{rep}"
        for sig, est in sorted(samples[rep].items()):
            value = "nan" if est is None else f"{est:.4f}"
            rows.append([sid, sig, value, value, value, estimand, "0"])
    _write_intervals(out / "intervals.csv", rows)
    (out / "errors.log").write_text("", encoding="utf-8")
    (out / "timing.json").write_text(json.dumps({"cpu_seconds": 1.0},
                                                sort_keys=True), encoding="utf-8")
    manifest = {"competitor": tool, "version": VERSION, "arm": arm, "n": n}
    manifest.update(manifest_extra or {})
    (out / "manifest.json").write_text(json.dumps(manifest, sort_keys=True,
                                                  indent=1), encoding="utf-8")
    for name in drop or ():
        (out / name).unlink()
    return cd
