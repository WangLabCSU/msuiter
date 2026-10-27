"""Launch governance for the U-M7-03 matrix driver (controller rulings
RB-07/RB-08).

Two instrumentation classes burned the Phase-B pass-1 postmortem and are
sealed here as pure, injected, CI-testable functions (the live docker
probes are injectable seams; the test suite never shells out):

  (1) SUBSTRING LABEL CLASSIFICATION — every cell label is parsed through
      one exact grammar, never matched by `in`. See parse_stamp.
  (2) NON-UNIFORM LAUNCH — fan-out=1 is enforced, not wished: the driver
      asks `docker ps` how many measurement-image containers are live and
      refuses to launch a cell while any is; the outcome is logged per
      cell. During the run, `docker top` is sampled so the worker census
      (max sibling procs — the self-sized process pools the frozen thread
      caps cannot reach) is OBSERVED, not assumed, and lands OUTSIDE the
      four-file guard and the BYTE_EQUAL set.

The 3x-floor gate encodes RB-08(7): a cell that takes more than three
times its pre-registered uncontended floor is a DEFECT candidate, and the
judgment writer refuses to claim fairness attestation over rows that are
not all pass (write_judgment consults nonpass_rows).
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

# -- (1) exact stamp grammar ------------------------------------------------------
# The ONLY admissible label shape. `[0-9]` is deliberately ASCII-class:
# int("١٠٠") == 100, so a unicode-digit label would silently resolve.
# Tool names may carry SINGLE underscores (the six P6 arms: sigminer_pre_v3
# ... sigminer_post_v3_rust) exactly as arms do -- the delimiter is `__`, so
# a single `_` inside tool/arm stays unambiguous under fullmatch. Death #10:
# the tool class was narrower than the arm class only because every
# historical measured tool was underscore-free; the campaign's first
# underscored cell completion walked parse_stamp for the first time and
# killed the main shard (test section (1b) seals both faces).
_STAMP_RE = re.compile(
    r"([a-z0-9]+(?:_[a-z0-9]+)*)__((?:[a-z0-9]+)(?:_[a-z0-9]+)*)__N(0|[1-9][0-9]*)$")


def parse_stamp(label: str) -> tuple[str, str, int]:
    """Parse `tool__arm__N<int>` exactly. Raises ValueError on anything the
    grammar does not cover — classification by substring is illegal law."""
    m = _STAMP_RE.fullmatch(label)
    if not m:
        raise ValueError(f"not a well-formed cell stamp: {label!r}")
    tool, arm, digits = m.groups()
    n = int(digits)
    if n < 1:
        raise ValueError(f"cell stamp N must be >= 1: {label!r}")
    return tool, arm, n


def class_by_n(stamps, n: int) -> list[str]:
    """Class membership by PARSED int equality — the `__N100`-substring bug
    (which swept N10000/N100000/N1000000) cannot occur through this door."""
    return [s for s in stamps if parse_stamp(s)[2] == n]


# -- (2) pre-flight co-tenant refusal ---------------------------------------------
def measurement_images() -> tuple[str, ...]:
    """Image refs that count as OURS: every READY competitor image in the
    registry (P6 arms join the census the moment their digests flip — a
    pending row has no attested image to census). A non-measurement container
    (test scaffolding) must never trip the assert."""
    from competitors import registry
    refs = []
    for spec in registry.load().values():
        if getattr(spec, "status", None) == "ready" and spec.image_ref:
            refs.append(spec.image_ref)
    return tuple(sorted(set(refs)))


def measurement_process_count(ps_rows) -> int:
    """Count live containers whose image is a measurement image.
    ps_rows: iterable of dicts with an "Image" key (injected `docker ps` table)."""
    ours = set(measurement_images())
    return sum(1 for r in ps_rows if r.get("Image") in ours)


def co_tenant_violation(live_count: int):
    """RB-08(3): ANY live measurement container vetoes a launch (fan-out=1
    by construction). Returns None (GO) or the refusal line."""
    if live_count == 0:
        return None
    unit = "container" if live_count == 1 else "containers"
    return f"refuse: {live_count} measurement {unit} live"


def log_preflight(log_path, *, cell: str, live: int, decision: str) -> None:
    """The assert outcome is auditable per cell: one JSONL line, appended."""
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    rec = {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "cell": cell, "live_measurement_containers": live,
           "decision": decision}
    with log_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, sort_keys=True) + "\n")


# live probes (injected in tests; used by the driver) -----------------------------
def docker_ps_rows() -> list[dict]:
    """Host-side `docker ps` census as [{Image: ...}] rows. --format
    {{json .Image}} emits one JSON *string* per line (quoting-safe); the
    string is wrapped into the dict shape the tested counter consumes."""
    out = subprocess.run(["docker", "ps", "--format", "{{json .Image}}"],
                         capture_output=True, text=True, check=True).stdout
    return [{"Image": json.loads(line)} for line in out.splitlines()
            if line.strip()]


def docker_top_rows(image: str) -> list[dict]:
    """`docker top` on the one container running `image`, parsed to
    [{PID, PPID}] via the UID/PID/PPID header (never by column index)."""
    cid = subprocess.run(
        ["docker", "ps", "--filter", f"ancestor={image}", "--format",
         "{{.ID}}"], capture_output=True, text=True, check=True
    ).stdout.split()
    if not cid:
        return []
    out = subprocess.run(["docker", "top", cid[0]],
                         capture_output=True, text=True, check=True).stdout
    lines = out.splitlines()
    if len(lines) < 2:
        return []
    header = lines[0].split()
    pid_i, ppid_i = header.index("PID"), header.index("PPID")
    return [{"PID": int(c[pid_i]), "PPID": int(c[ppid_i])}
            for c in (l.split() for l in lines[1:]) if len(c) > max(pid_i, ppid_i)]


def pre_flight_assert(cell: str, log_path, *, probe=docker_ps_rows):
    """RB-08(3) as a call: GO logs and returns True; any co-tenant logs and
    returns False (the caller must not launch)."""
    live = measurement_process_count(probe())
    violation = co_tenant_violation(live)
    log_preflight(log_path, cell=cell, live=live,
                  decision="REFUSE" if violation else "GO")
    return violation is None


# -- (3) worker census (observe, never assume) ------------------------------------
def max_sibling_procs(top_rows) -> int:
    """Largest set of processes sharing a parent — the process-pool width
    the frozen BLAS/OpenMP caps cannot reach. An empty table counts 0."""
    if not top_rows:
        return 0
    by_ppid: dict[int, int] = {}
    for r in top_rows:
        by_ppid[r["PPID"]] = by_ppid.get(r["PPID"], 0) + 1
    return max(by_ppid.values())


def worker_census(samples, *, tool: str, cell: str) -> dict:
    """Fold N `docker top` samples taken DURING the run into the sidecar
    record: the max sibling-proc census observed across all samples."""
    return {"cell": cell, "tool": tool,
            "max_worker_procs": max((max_sibling_procs(s) for s in samples),
                                   default=0),
            "samples": len(samples)}


def sample_worker_census(cell: str, tool: str, log_dir, *, interval: float = 5.0,
                         sampler=None):
    """Context manager: while the cell container runs, sample `docker top`
    every `interval` seconds; on exit write the folded census to
    log_dir/census.json (sidecar: OUTSIDE the four-file guard, OUTSIDE the
    BYTE_EQUAL set — it never participates in cache-hit comparisons)."""
    sampler = sampler or docker_top_rows
    samples: list[list[dict]] = []
    stop = threading.Event()

    def _tool_ref() -> str:
        from competitors import registry
        return registry.lookup(tool).image_ref

    image = _tool_ref()

    def _pump():
        while not stop.wait(interval):
            try:
                rows = sampler(image)
            except Exception:                                      # noqa: BLE001
                continue                                           # container already gone
            if rows:
                samples.append(rows)

    # The pump thread is created at factory time (not at __enter__): the
    # exit path joins it, so both entry and exit must see the same object.
    thread = threading.Thread(target=_pump, daemon=True)

    def _finish(ctx: Path):
        stop.set()
        thread.join(timeout=2 * interval + 5)
        ctx.mkdir(parents=True, exist_ok=True)
        (ctx / "census.json").write_text(
            json.dumps(worker_census(samples, tool=tool, cell=cell),
                       sort_keys=True) + "\n", encoding="utf-8")

    class _Ctx:
        def __enter__(self):
            thread.start()
            return self

        def __exit__(self, *exc):
            _finish(Path(log_dir) / cell)
            return False

    return _Ctx()


# -- (4) the 3x-floor gate: measured protocol-scale anchors (RB-09) --------------
# One law, zero model degrees of freedom: the floor of a cell class is that
# class's OWN committed REP-100 uncontended witness cost,
#
#     floor(tool, arm, n) := max(witness wall_seconds, witness cpu_seconds)
#
# measured fresh (--floor-gate off, freshness law: a cached replay is a
# DEFECT witness, never a floor). FLOOR_RATIO below is the untouched
# RB-08(7) sentinel — the ratio gates the witness, the witness never gates
# the ratio. The reps-sweep {1,5,10} x n {100,1e3,1e4} (main arm, both
# tools) is committed as _SWEEP_RAW with its least-squares _SWEEP_FIT:
# probe-scale reps-linearity and the BOOT intercepts are DATA pinned by the
# (R) units. Short-probe magnitudes may never seed floors (RB-09
# superlinearity: rep-100 per-rep cost >= the probe-scale projection —
# recorded, and the (R) units stop a regression to sweep-extrapolated
# floors). An unanchored class is a hard error: an ungated cell is
# forbidden.
_SWEEP_FIT = {
 "sigminer|N100": {
  "boot": 367.6,
  "max_linear_resid": 0.031,
  "per_rep": 1.546
 },
 "sigminer|N1000": {
  "boot": 363.6,
  "max_linear_resid": 0.0347,
  "per_rep": 5.223
 },
 "sigminer|N10000": {
  "boot": 661.8,
  "max_linear_resid": 0.0041,
  "per_rep": 8.253
 },
 "sigprofiler|N100": {
  "boot": 11.4,
  "max_linear_resid": 0.0341,
  "per_rep": 2.294
 },
 "sigprofiler|N1000": {
  "boot": 11.7,
  "max_linear_resid": 0.0771,
  "per_rep": 2.017
 },
 "sigprofiler|N10000": {
  "boot": 11.9,
  "max_linear_resid": 0.0389,
  "per_rep": 2.005
 }
}
_SWEEP_RAW = {
 "sigminer|N100": {
  "1": 362.43,
  "10": 377.676,
  "5": 387.283
 },
 "sigminer|N1000": {
  "1": 360.995,
  "10": 409.559,
  "5": 403.67
 },
 "sigminer|N10000": {
  "1": 668.446,
  "10": 743.038,
  "5": 705.919
 },
 "sigprofiler|N100": {
  "1": 14.139,
  "10": 34.703,
  "5": 22.142
 },
 "sigprofiler|N1000": {
  "1": 14.583,
  "10": 32.562,
  "5": 20.226
 },
 "sigprofiler|N10000": {
  "1": 14.349,
  "10": 32.304,
  "5": 21.093
 }
}
_FLOOR_ANCHORS = {
    ('sigminer', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1786.2061079999999, 'wall_seconds': 1787.16,
    },
    ('sigminer', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1265.724519, 'wall_seconds': 1266.618,
    },
    ('sigminer', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1758.51518, 'wall_seconds': 1759.269,
    },
    ('sigminer', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1576.334032, 'wall_seconds': 1577.077,
    },
    ('sigminer', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1259.627353, 'wall_seconds': 1260.391,
    },
    ('sigminer', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1766.576845, 'wall_seconds': 1767.442,
    },
    ('sigminer', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1608.168423, 'wall_seconds': 1608.971,
    },
    ('sigminer', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1227.598643, 'wall_seconds': 1228.271,
    },
    ('sigminer', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1836.095571, 'wall_seconds': 1836.949,
    },
    ('sigminer', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1668.7922999999998, 'wall_seconds': 1669.58,
    },
    ('sigminer', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 997.500041, 'wall_seconds': 998.344,
    },
    ('sigminer', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 934.1876120000001, 'wall_seconds': 934.842,
    },
    ('sigminer', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 765.509964, 'wall_seconds': 766.211,
    },
    ('sigminer', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1200.548715, 'wall_seconds': 1201.339,
    },
    ('sigminer', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1816.989283, 'wall_seconds': 1817.917,
    },
    ('sigminer', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1609.961622, 'wall_seconds': 1610.775,
    },
    ('sigminer', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1332.528113, 'wall_seconds': 1333.282,
    },
    ('sigminer', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1788.579242, 'wall_seconds': 1789.539,
    },
    ('sigminer', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1710.349412, 'wall_seconds': 1711.104,
    },
    ('sigminer', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 979.369876, 'wall_seconds': 979.857,
    },
    ('sigminer', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigminer__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1798.705021, 'wall_seconds': 1799.423,
    },
    ('sigminer_post_p1', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1831.587613, 'wall_seconds': 1832.477,
    },
    ('sigminer_post_p1', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1190.4567749999999, 'wall_seconds': 1191.189,
    },
    ('sigminer_post_p1', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1772.902083, 'wall_seconds': 1773.74,
    },
    ('sigminer_post_p1', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1595.6796069999998, 'wall_seconds': 1596.474,
    },
    ('sigminer_post_p1', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1258.8414539999999, 'wall_seconds': 1259.537,
    },
    ('sigminer_post_p1', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1735.303979, 'wall_seconds': 1736.069,
    },
    ('sigminer_post_p1', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1675.4521570000002, 'wall_seconds': 1676.242,
    },
    ('sigminer_post_p1', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1155.366036, 'wall_seconds': 1156.023,
    },
    ('sigminer_post_p1', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1820.1484409999998, 'wall_seconds': 1820.897,
    },
    ('sigminer_post_p1', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1644.2214909999998, 'wall_seconds': 1645.046,
    },
    ('sigminer_post_p1', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1092.914612, 'wall_seconds': 1093.84,
    },
    ('sigminer_post_p1', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 869.824778, 'wall_seconds': 870.505,
    },
    ('sigminer_post_p1', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 818.587221, 'wall_seconds': 819.233,
    },
    ('sigminer_post_p1', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1260.752959, 'wall_seconds': 1261.466,
    },
    ('sigminer_post_p1', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1731.1395750000001, 'wall_seconds': 1731.916,
    },
    ('sigminer_post_p1', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1616.835724, 'wall_seconds': 1617.625,
    },
    ('sigminer_post_p1', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1270.9276419999999, 'wall_seconds': 1271.581,
    },
    ('sigminer_post_p1', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1810.076683, 'wall_seconds': 1810.864,
    },
    ('sigminer_post_p1', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1794.501884, 'wall_seconds': 1795.295,
    },
    ('sigminer_post_p1', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1065.2811319999998, 'wall_seconds': 1065.899,
    },
    ('sigminer_post_p1', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1816.7648640000002, 'wall_seconds': 1817.568,
    },
    ('sigminer_post_p1_rust', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 563.5072319999999, 'wall_seconds': 564.086,
    },
    ('sigminer_post_p1_rust', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 590.471825, 'wall_seconds': 590.98,
    },
    ('sigminer_post_p1_rust', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 570.375126, 'wall_seconds': 570.928,
    },
    ('sigminer_post_p1_rust', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 574.425717, 'wall_seconds': 574.969,
    },
    ('sigminer_post_p1_rust', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 581.751365, 'wall_seconds': 582.254,
    },
    ('sigminer_post_p1_rust', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 569.292465, 'wall_seconds': 569.814,
    },
    ('sigminer_post_p1_rust', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 589.610093, 'wall_seconds': 590.118,
    },
    ('sigminer_post_p1_rust', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 644.380204, 'wall_seconds': 645.472,
    },
    ('sigminer_post_p1_rust', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1126.325828, 'wall_seconds': 1127.308,
    },
    ('sigminer_post_p1_rust', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1124.165829, 'wall_seconds': 1125.191,
    },
    ('sigminer_post_p1_rust', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 985.4669389999999, 'wall_seconds': 986.506,
    },
    ('sigminer_post_p1_rust', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 613.8316629999999, 'wall_seconds': 614.347,
    },
    ('sigminer_post_p1_rust', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 679.795879, 'wall_seconds': 680.377,
    },
    ('sigminer_post_p1_rust', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 595.168086, 'wall_seconds': 595.759,
    },
    ('sigminer_post_p1_rust', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 595.288215, 'wall_seconds': 595.866,
    },
    ('sigminer_post_p1_rust', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 604.047553, 'wall_seconds': 604.594,
    },
    ('sigminer_post_p1_rust', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 591.5007629999999, 'wall_seconds': 592.085,
    },
    ('sigminer_post_p1_rust', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 588.0658999999999, 'wall_seconds': 588.671,
    },
    ('sigminer_post_p1_rust', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 579.834365, 'wall_seconds': 580.39,
    },
    ('sigminer_post_p1_rust', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 591.32685, 'wall_seconds': 591.838,
    },
    ('sigminer_post_p1_rust', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p1_rust__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 577.612168, 'wall_seconds': 578.113,
    },
    ('sigminer_post_p2', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1824.660824, 'wall_seconds': 1825.448,
    },
    ('sigminer_post_p2', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1246.698915, 'wall_seconds': 1247.409,
    },
    ('sigminer_post_p2', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1779.522482, 'wall_seconds': 1780.334,
    },
    ('sigminer_post_p2', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1573.4002540000001, 'wall_seconds': 1574.162,
    },
    ('sigminer_post_p2', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1285.093987, 'wall_seconds': 1285.849,
    },
    ('sigminer_post_p2', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1750.070031, 'wall_seconds': 1750.958,
    },
    ('sigminer_post_p2', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1556.960963, 'wall_seconds': 1557.765,
    },
    ('sigminer_post_p2', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1203.167567, 'wall_seconds': 1203.846,
    },
    ('sigminer_post_p2', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1826.1474070000002, 'wall_seconds': 1826.923,
    },
    ('sigminer_post_p2', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1671.923615, 'wall_seconds': 1672.704,
    },
    ('sigminer_post_p2', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 969.4694979999999, 'wall_seconds': 970.147,
    },
    ('sigminer_post_p2', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1744.059229, 'wall_seconds': 1745.431,
    },
    ('sigminer_post_p2', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1032.446702, 'wall_seconds': 1033.279,
    },
    ('sigminer_post_p2', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 2386.866424, 'wall_seconds': 2388.297,
    },
    ('sigminer_post_p2', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 2591.3247699999997, 'wall_seconds': 2592.953,
    },
    ('sigminer_post_p2', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1557.8625310000002, 'wall_seconds': 1558.642,
    },
    ('sigminer_post_p2', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1341.223622, 'wall_seconds': 1341.982,
    },
    ('sigminer_post_p2', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1869.128516, 'wall_seconds': 1870.016,
    },
    ('sigminer_post_p2', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1654.3183259999998, 'wall_seconds': 1655.283,
    },
    ('sigminer_post_p2', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 976.349091, 'wall_seconds': 976.805,
    },
    ('sigminer_post_p2', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_p2__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1777.4768419999998, 'wall_seconds': 1778.28,
    },
    ('sigminer_post_v3', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1827.436292, 'wall_seconds': 1828.31,
    },
    ('sigminer_post_v3', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1272.112806, 'wall_seconds': 1272.876,
    },
    ('sigminer_post_v3', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1923.165712, 'wall_seconds': 1924.078,
    },
    ('sigminer_post_v3', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1640.1124360000001, 'wall_seconds': 1640.985,
    },
    ('sigminer_post_v3', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1385.7411949999998, 'wall_seconds': 1386.536,
    },
    ('sigminer_post_v3', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1965.201748, 'wall_seconds': 1966.222,
    },
    ('sigminer_post_v3', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1839.649269, 'wall_seconds': 1840.611,
    },
    ('sigminer_post_v3', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1344.4998420000002, 'wall_seconds': 1345.367,
    },
    ('sigminer_post_v3', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1894.224578, 'wall_seconds': 1895.131,
    },
    ('sigminer_post_v3', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1839.4848029999998, 'wall_seconds': 1840.444,
    },
    ('sigminer_post_v3', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1106.076033, 'wall_seconds': 1106.895,
    },
    ('sigminer_post_v3', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 954.1314600000001, 'wall_seconds': 954.878,
    },
    ('sigminer_post_v3', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 854.326053, 'wall_seconds': 855.048,
    },
    ('sigminer_post_v3', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1375.320182, 'wall_seconds': 1376.219,
    },
    ('sigminer_post_v3', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1973.9063569999998, 'wall_seconds': 1974.833,
    },
    ('sigminer_post_v3', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1743.6540260000002, 'wall_seconds': 1744.553,
    },
    ('sigminer_post_v3', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1461.308072, 'wall_seconds': 1462.131,
    },
    ('sigminer_post_v3', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1967.115137, 'wall_seconds': 1967.997,
    },
    ('sigminer_post_v3', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1755.435881, 'wall_seconds': 1756.257,
    },
    ('sigminer_post_v3', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1031.3401979999999, 'wall_seconds': 1031.892,
    },
    ('sigminer_post_v3', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1837.69906, 'wall_seconds': 1838.535,
    },
    ('sigminer_post_v3_rust', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 568.237174, 'wall_seconds': 568.865,
    },
    ('sigminer_post_v3_rust', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 592.847943, 'wall_seconds': 593.358,
    },
    ('sigminer_post_v3_rust', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 577.149625, 'wall_seconds': 577.678,
    },
    ('sigminer_post_v3_rust', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 576.2023119999999, 'wall_seconds': 576.687,
    },
    ('sigminer_post_v3_rust', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 574.0247810000001, 'wall_seconds': 574.537,
    },
    ('sigminer_post_v3_rust', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 571.8331810000001, 'wall_seconds': 572.339,
    },
    ('sigminer_post_v3_rust', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 572.330447, 'wall_seconds': 572.836,
    },
    ('sigminer_post_v3_rust', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 589.461241, 'wall_seconds': 589.987,
    },
    ('sigminer_post_v3_rust', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 593.7339659999999, 'wall_seconds': 594.254,
    },
    ('sigminer_post_v3_rust', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 586.2679069999999, 'wall_seconds': 586.822,
    },
    ('sigminer_post_v3_rust', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 592.1194360000001, 'wall_seconds': 592.669,
    },
    ('sigminer_post_v3_rust', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 608.216449, 'wall_seconds': 608.728,
    },
    ('sigminer_post_v3_rust', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 679.5136050000001, 'wall_seconds': 680.121,
    },
    ('sigminer_post_v3_rust', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 589.8809970000001, 'wall_seconds': 590.397,
    },
    ('sigminer_post_v3_rust', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 585.971283, 'wall_seconds': 586.478,
    },
    ('sigminer_post_v3_rust', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 587.574907, 'wall_seconds': 588.096,
    },
    ('sigminer_post_v3_rust', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 583.07695, 'wall_seconds': 583.555,
    },
    ('sigminer_post_v3_rust', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 570.9118400000001, 'wall_seconds': 571.398,
    },
    ('sigminer_post_v3_rust', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 574.1609960000001, 'wall_seconds': 574.625,
    },
    ('sigminer_post_v3_rust', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 569.232159, 'wall_seconds': 569.742,
    },
    ('sigminer_post_v3_rust', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_post_v3_rust__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 573.133317, 'wall_seconds': 573.618,
    },
    ('sigminer_pre_v3', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1842.9869270000002, 'wall_seconds': 1843.82,
    },
    ('sigminer_pre_v3', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1298.417393, 'wall_seconds': 1299.103,
    },
    ('sigminer_pre_v3', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1812.738687, 'wall_seconds': 1813.539,
    },
    ('sigminer_pre_v3', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 2842.14734, 'wall_seconds': 2843.275,
    },
    ('sigminer_pre_v3', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1290.0394390000001, 'wall_seconds': 1291.486,
    },
    ('sigminer_pre_v3', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1776.28006, 'wall_seconds': 1777.247,
    },
    ('sigminer_pre_v3', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1536.282134, 'wall_seconds': 1537.017,
    },
    ('sigminer_pre_v3', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1166.7853129999999, 'wall_seconds': 1167.529,
    },
    ('sigminer_pre_v3', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1782.6103440000002, 'wall_seconds': 1783.381,
    },
    ('sigminer_pre_v3', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1594.428181, 'wall_seconds': 1595.271,
    },
    ('sigminer_pre_v3', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 984.512642, 'wall_seconds': 985.295,
    },
    ('sigminer_pre_v3', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 858.064711, 'wall_seconds': 858.769,
    },
    ('sigminer_pre_v3', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 706.864924, 'wall_seconds': 707.512,
    },
    ('sigminer_pre_v3', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1159.782978, 'wall_seconds': 1160.52,
    },
    ('sigminer_pre_v3', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1775.8345020000002, 'wall_seconds': 1776.786,
    },
    ('sigminer_pre_v3', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1533.239047, 'wall_seconds': 1534.03,
    },
    ('sigminer_pre_v3', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1257.844579, 'wall_seconds': 1258.554,
    },
    ('sigminer_pre_v3', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1789.860698, 'wall_seconds': 1790.639,
    },
    ('sigminer_pre_v3', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1694.785998, 'wall_seconds': 1695.566,
    },
    ('sigminer_pre_v3', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 981.615262, 'wall_seconds': 982.083,
    },
    ('sigminer_pre_v3', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_20261025-125823', 'witnesses', 'sigminer_pre_v3__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1770.8772270000002, 'wall_seconds': 1771.66,
    },
    ('sigprofiler', 'clock', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 39.490489000000004, 'wall_seconds': 18.28,
    },
    ('sigprofiler', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.57612, 'wall_seconds': 17.551,
    },
    ('sigprofiler', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 38.625461, 'wall_seconds': 17.392,
    },
    ('sigprofiler', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 38.995673, 'wall_seconds': 17.777,
    },
    ('sigprofiler', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 41.929871999999996, 'wall_seconds': 18.889,
    },
    ('sigprofiler', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 41.82128, 'wall_seconds': 18.886,
    },
    ('sigprofiler', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.633528, 'wall_seconds': 17.297,
    },
    ('sigprofiler', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.855014, 'wall_seconds': 17.814,
    },
    ('sigprofiler', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.595345, 'wall_seconds': 17.429,
    },
    ('sigprofiler', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 36.992503, 'wall_seconds': 16.999,
    },
    ('sigprofiler', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 36.73339, 'wall_seconds': 17.453,
    },
    ('sigprofiler', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.106901, 'wall_seconds': 17.306,
    },
    ('sigprofiler', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 36.888292, 'wall_seconds': 17.345,
    },
    ('sigprofiler', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.018357, 'wall_seconds': 17.294,
    },
    ('sigprofiler', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.833979, 'wall_seconds': 17.536,
    },
    ('sigprofiler', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 39.672067999999996, 'wall_seconds': 17.58,
    },
    ('sigprofiler', 'main', 100): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.6464, 'wall_seconds': 17.815,
    },
    ('sigprofiler', 'main', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 42.502179000000005, 'wall_seconds': 18.494,
    },
    ('sigprofiler', 'main', 10000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 42.833358000000004, 'wall_seconds': 17.345,
    },
    ('sigprofiler', 'nb', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 40.961841, 'wall_seconds': 18.712,
    },
    ('sigprofiler', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_p7cap_legacy_20261027-083955', 'witnesses', 'sigprofiler__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 41.832211, 'wall_seconds': 18.692,
    },
}
FLOOR_RATIO = 3.0
PASS_STATUSES = ("ok", "cached")

# -- RB-10 post-cap authority law (perf/p7) ---------------------------------------
# The table's anchors re-anchor onto witnesses minted after the fork-axis caps
# went live (main@2e689cd). Post-cap containers ride the serial chain, so wall
# tracks cpu: the A/B legs spoke wall 578.651 / cpu 577.969 (deviation 0.0012)
# where every pre-cap R-face witness deviates by at least 0.218 -- the bar below
# sits at 0.10, a 2.2x bite margin against pre-cap bytes. Authority dirs speak
# the prefix; the legacy-domain re-mint (60 classes) speaks the legacy prefix.
# Pre-cap bytes (fan-live, wall != cpu) may never satisfy either half.
POST_CAP_AUTHORITY_PREFIX = "m7_floor_calibration_p7cap_"
POST_CAP_LEGACY_PREFIX = "m7_floor_calibration_p7cap_legacy_"
POST_CAP_WALL_CPU_TOL = 0.10

# -- floor anchor provenance (RB-09(3)(i)/(v)) ------------------------------------
# The anchors ARE the law and the provenance: every floor class descends from
# a committed witness JSON whose own ``--reps`` equals the frozen protocol reps.
# RB-09's root cause was exactly the absence of this law: the r5 anchor was a
# REP-1 probe (cpu 360.252302) and the sigprofiler anchor a REP-1 pilot row
# (pilot Seeds.txt: one rep row per class), while the matrix runs REP-100
# cells — floor(sigminer,main,N100)=310 sat below the rep-1 witness itself,
# so the fresh serial matrix could only ever self-halt on its own gate.
PROTOCOL_REPS = 100                                   # gated protocol scale
_RESULTS_DIR = Path(__file__).resolve().parents[2] / "results"   # bench/results



def anchor_witness_path(anchor: dict) -> Path:
    """Absolute path of a floor anchor's committed witness file."""
    return _RESULTS_DIR.joinpath(*anchor["witness"])


def anchor_measured(anchor: dict) -> float:
    """The witness's honest uncontended cost for its class — the same
    max(wall, cpu) metric the gate itself measures against."""
    return max(float(anchor.get("wall_seconds", 0.0)),
               float(anchor.get("cpu_seconds", 0.0)))


_MEASURED_TOOLS = tuple(sorted({t for (t, _, _) in _FLOOR_ANCHORS}))


def floor_for(tool: str, arm: str, n: int) -> float:
    """The measured protocol-scale uncontended floor for one cell class —
    that class's own committed REP-100 witness cost (RB-09(3)(iii)). An
    unanchored class is a hard error: silence here would mean an ungated
    cell."""
    if n < 1:
        raise ValueError(f"floor needs n >= 1, got {n!r}")
    key = (tool, arm, n)
    if key not in _FLOOR_ANCHORS:
        raise KeyError(f"no measured floor anchor for class {key!r} — the "
                       f"gate refuses to invent one")
    return anchor_measured(_FLOOR_ANCHORS[key])


def floor_gate(row: dict):
    """RB-08(7): None (pass) or a DEFECT-candidate flag row. Silent on
    non-pass rows — a dead cell is diagnosed by its own death text — and on
    non-measurement tools (mock/signal are plumbing with no uncontended
    floor). An unknown ARM of a measured tool is a hard error: silence
    there would mean an ungated cell."""
    if row["status"] not in PASS_STATUSES:
        return None
    tool, arm, n = parse_stamp(row["cell"])
    if tool not in _MEASURED_TOOLS:
        return None
    floor = floor_for(tool, arm, n)
    observed = max(float(row["seconds"]), float(row.get("cpu_seconds", 0.0)))
    if observed <= FLOOR_RATIO * floor:
        return None
    return {**row,
            "status": (f"defect-floor: wall/cpu {observed:.1f}s > "
                       f"{FLOOR_RATIO}x measured uncontended floor {floor:.1f}s "
                       f"(tool={tool} arm={arm} n={n})")}


def nonpass_rows(rows) -> list[dict]:
    """The judgment writer's refuse-to-claim predicate: any row that is not
    an outright pass (ok/cached) voids the fairness attestation header."""
    return [r for r in rows if r["status"] not in PASS_STATUSES]


# -- (4a) hardware-pin completeness (U-M7-04 GO-05, ROADMAP:100 hardware-pinned full table) --------
# B1a made the pins possible ("unset → present-but-empty"); a table with empty
# pin columns still does not attest its machine, and the ROADMAP's full-table
# clause is only true of a table where EVERY row carries the pin of the
# measured environment. This is the machine-checkable face of the EVIDENCE-
# ADDENDUM §4 forward path: the table alone (plus the two expectations a reader
# can re-measure) answers "which machine produced these numbers". The pure
# verdict names offenders by cell; the authoring gate in run_bench.main turns
# an unattested authoritative table into a refusal, never a file.
def hardware_pin_verdict(rows, *, host: str, hw_profile: str) -> dict:
    """Adjudicate a timings table's hardware pins against the measured
    environment: every row's ``host``/``hw_profile`` must be present AND equal
    to the expectation. Offenders are named per cell (diagnosed, never
    averaged away); a zero-row table attests nothing and is not ok."""
    host, hw_profile = (host or "").strip(), (hw_profile or "").strip()
    missing_host, missing_profile = [], []
    mismatched_host, mismatched_profile = [], []
    for r in rows:
        cell = r["cell"]
        row_host = (r.get("host") or "").strip()
        row_profile = (r.get("hw_profile") or "").strip()
        if not row_host:
            missing_host.append(cell)
        elif row_host != host:
            mismatched_host.append(cell)
        if not row_profile:
            missing_profile.append(cell)
        elif row_profile != hw_profile:
            mismatched_profile.append(cell)
    complete = not (missing_host or missing_profile
                    or mismatched_host or mismatched_profile)
    return {"rows": len(rows),
            "missing_host": missing_host,
            "missing_hw_profile": missing_profile,
            "mismatched_host": mismatched_host,
            "mismatched_hw_profile": mismatched_profile,
            "ok": bool(rows) and complete and bool(host) and bool(hw_profile)}


# -- (4b) defect ledger + re-adjudication lineage (RB-09(3)(iv)) --------------------
# A defect-floor flag is law for the floor-table epoch that raised it. When a
# cell flagged under an OLD epoch later passes under a NEW one (the RB-09
# calibration repair), the pass is a RE-ADJUDICATION and must carry its
# mechanism citation — never a silent re-status. The ledger lives under
# cachedir/governance/, outside the four-file guard and the BYTE_EQUAL set.
GOVERNANCE_SUBDIR = "governance"
FLOOR_TABLE_FIELDS = ("_FLOOR_ANCHORS", "FLOOR_RATIO",
                      "_SWEEP_FIT", "_SWEEP_RAW")
RE_ADJUDICATION_MECHANISM = (
    "RB-09 (controller ruling 2026-10-09): the pre-registered floor table was "
    "calibrated from REP-1 witnesses (probe_sigminer_cell_argv --reps default; "
    "pilot Seeds.txt one rep row per class) while the protocol runs REP-100 "
    "cells — the defect-floor halt was an anchor-miscalibration artifact, the "
    "cell content itself intact. See the committed witness addendum and "
    "docs/devlog/2026-10-09-m7-benchmark-matrix.md.")


def _canonical(value):
    """JSON-canonical view of a floor-table constant: tuple keys become
    '|'-joined strings, tuples become lists — the epoch hash must see every
    byte of the table, including its (tool, arm, n) anchor keys."""
    if isinstance(value, dict):
        return {("|".join(map(str, k)) if isinstance(k, tuple) else str(k)):
                _canonical(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [_canonical(v) for v in value]
    return value


def floor_table_epoch() -> str:
    """Explicit-algorithm epoch of the floor table (RB-06 hash doctrine):
    sha256 over the canonical JSON of every floor-affecting constant, pins
    included. Any re-calibration flips it by construction."""
    blob = json.dumps({name: _canonical(globals()[name])
                       for name in FLOOR_TABLE_FIELDS},
                      sort_keys=True, default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def defect_ledger_path(cachedir) -> Path:
    return Path(cachedir) / GOVERNANCE_SUBDIR / "defect_ledger.jsonl"


def append_defect_record(cachedir, row: dict) -> None:
    """Ledger one DEFECT-candidate flag verbatim with its table epoch."""
    path = defect_ledger_path(cachedir)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": _utc_iso(), "epoch": floor_table_epoch(),
                             "cell": row["cell"], "status": row["status"]},
                            sort_keys=True) + "\n")


def _utc_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def latest_defect_records(cachedir) -> dict[str, dict]:
    """Last ledger record per cell (absent/empty ledger reads as empty)."""
    path = defect_ledger_path(cachedir)
    latest: dict[str, dict] = {}
    if not path.exists():
        return latest
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            record = json.loads(line)
            latest[record["cell"]] = record
    return latest


def re_adjudication(row: dict, prior: dict | None) -> dict | None:
    """Lineage annotation for a passing row whose cell was defect-flagged
    under a DIFFERENT floor-table epoch; None keeps the pass silent."""
    if prior is None or not str(prior.get("status", "")).startswith("defect-"):
        return None
    if prior.get("epoch") == floor_table_epoch():
        return None                      # same law still in force
    return {"prior_status": prior["status"], "prior_epoch": prior["epoch"],
            "epoch": floor_table_epoch(),
            "mechanism": RE_ADJUDICATION_MECHANISM}
