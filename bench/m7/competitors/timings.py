"""Timings table schema — G0-compatible prefix + ``cpu_seconds`` (memo §4.3).

The M7 tables must concatenate with the G0 tables, so the six G0 columns
``cell,tool,arm,n,seconds,status`` keep their names and order **verbatim**
(pinned against the byte-copied header of the authoritative G0 artifact
``bench/results/docker_degraded_pi_20261007-212438/timings_sharded_master.csv``,
committed as tests/fixtures/g0_timings_header.csv), and M7 appends exactly
one measurement column ``cpu_seconds``. U-M7-04 B1a appends two more,
behind the seven: the optional hardware pins ``host``/``hw_profile``, so a
table alone attests the machine its numbers were measured on. Committed
pre-B1a artifacts keep the 7-col schema (:data:`LEGACY_TIMINGS_COLUMNS`)
and keep reading via :func:`read_timings`.

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
TIMINGS_COLUMNS: tuple[str, ...] = (G0_TIMINGS_COLUMNS + ("cpu_seconds",
                                                          "host",
                                                          "hw_profile"))
#: Committed pre-U-M7-04 tables — the authoritative 42-cell artifact and the
#: G0-derived helpers included — carry exactly this 7-col header. Readers
#: accept it; writers only ever emit the current 9-col schema.
LEGACY_TIMINGS_COLUMNS: tuple[str, ...] = G0_TIMINGS_COLUMNS + ("cpu_seconds",)
#: Machine-class pin channel: run_bench stamps ``host`` from the runner's
#: hostname and ``hw_profile`` from this environment variable (operator-set,
#: e.g. "10 vCPU / 8 GB class"). Unset → column present but empty.
HW_PROFILE_ENV = "M7_HW_PROFILE"

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
    M7 ``cpu_seconds`` column, then the optional U-M7-04 hardware pins
    ``host``/``hw_profile``. Row dicts carry the column keys — the pin
    columns may be omitted (written empty) — plus any registered
    :data:`GOVERNANCE_METADATA_KEYS` (projected out here)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    cols = list(columns)
    optional = [c for c in cols if c in ("host", "hw_profile")]
    required = [c for c in cols if c not in optional]
    slim = []
    for r in rows:
        unknown = set(r) - set(cols) - GOVERNANCE_METADATA_KEYS
        if unknown:
            raise ValueError(f"row keys outside the frozen timings schema: "
                             f"{sorted(unknown)}")
        missing = [c for c in required if c not in r]
        if missing:
            raise ValueError(f"row is missing required timings columns: "
                             f"{missing}")
        slim.append({k: r.get(k, "") for k in cols})
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="raise")
        w.writeheader()
        w.writerows(slim)
    return path


def read_timings(path: Path) -> list[dict]:
    """Read a timings table — current 9-col, or the committed pre-U-M7-04
    7-col legacy schema, whose rows arrive with empty pin columns. The
    back-compat branch is pinned to :data:`LEGACY_TIMINGS_COLUMNS` exactly:
    any other header raises, so schema drift can never masquerade as
    history."""
    path = Path(path)
    with path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        header = list(reader.fieldnames or [])
        if header == list(TIMINGS_COLUMNS):
            return [dict(row) for row in reader]
        if header == list(LEGACY_TIMINGS_COLUMNS):
            return [dict(row, host="", hw_profile="") for row in reader]
        raise ValueError(f"unrecognised timings header in {path.name}: "
                         f"{header}")


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
