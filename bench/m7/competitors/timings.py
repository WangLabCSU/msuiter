"""Timings table schema — G0-compatible prefix + ``cpu_seconds`` (memo §4.3).

The M7 tables must concatenate with the G0 tables, so the six G0 columns
``cell,tool,arm,n,seconds,status`` keep their names and order **verbatim**
(pinned against the byte-copied header of the authoritative G0 artifact
``bench/results/docker_degraded_pi_20261007-212438/timings_sharded_master.csv``,
committed as tests/fixtures/g0_timings_header.csv), and M7 appends exactly
one measurement column ``cpu_seconds``.

Wall seconds = subprocess measurement around the competitor invocation
(recorded by the orchestrator). CPU seconds = the container-side child's
``ru_utime + ru_stime`` reported by ``adapters/m7_entry.py`` via the
``out/timing.json`` sidecar (resource.getrusage(RUSAGE_CHILDREN) around the
in-container entrypoint) — parsed back through
:func:`read_timing_sidecar` / :func:`cpu_seconds_of`.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

G0_TIMINGS_COLUMNS: tuple[str, ...] = ("cell", "tool", "arm", "n", "seconds",
                                       "status")
TIMINGS_COLUMNS: tuple[str, ...] = G0_TIMINGS_COLUMNS + ("cpu_seconds",)

#: Governance metadata may ride the row dict for the judgment writer
#: (RB-09(3)(iv) re-adjudication lineage attaches per row in run_bench) but
#: is NEVER written: the table is the frozen G0 prefix + cpu_seconds, full
#: stop. Projection is explicit and audited below — an unlisted extra key
#: still raises, so governance data can neither widen the schema nor be
#: smuggled silently.
GOVERNANCE_METADATA_KEYS: frozenset[str] = frozenset({"re_adjudication"})


def write_timings(path: Path, rows: list[dict],
                  columns: tuple[str, ...] = TIMINGS_COLUMNS) -> Path:
    """Write the timings table: the G0 six-column prefix verbatim, then the
    M7 ``cpu_seconds`` column. Row dicts carry exactly the column keys plus
    any registered :data:`GOVERNANCE_METADATA_KEYS` (projected out here)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    cols = list(columns)
    slim = []
    for r in rows:
        unknown = set(r) - set(cols) - GOVERNANCE_METADATA_KEYS
        if unknown:
            raise ValueError(f"row keys outside the frozen timings schema: "
                             f"{sorted(unknown)}")
        slim.append({k: r[k] for k in cols})
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="raise")
        w.writeheader()
        w.writerows(slim)
    return path


def read_timing_sidecar(path: Path) -> dict | None:
    """Parse the runner-written ``out/timing.json``; ``None`` when absent
    or malformed (a missing sidecar demotes the cell via the four-file
    guard — the parse layer never invents numbers for it)."""
    path = Path(path)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def cpu_seconds_of(sidecar: dict | None, default: float = 0.0) -> float:
    """CPU seconds from the sidecar record (sum of the child rusage), or
    ``default`` when the sidecar is missing/unmeasured."""
    if sidecar is None:
        return default
    try:
        return float(sidecar["cpu_seconds"])
    except (KeyError, TypeError, ValueError):
        return default
