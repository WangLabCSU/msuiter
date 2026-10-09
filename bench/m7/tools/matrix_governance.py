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
_STAMP_RE = re.compile(r"([a-z0-9]+)__((?:[a-z0-9]+)(?:_[a-z0-9]+)*)__N(0|[1-9][0-9]*)$")


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
    registry. A non-measurement container (test scaffolding) must never
    trip the assert."""
    from competitors import registry
    refs = []
    for name in ("sigminer", "sigprofiler"):
        try:
            ref = registry.lookup(name).image_ref
        except ValueError:
            continue
        if ref:
            refs.append(ref)
    return tuple(refs)


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
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1079.517548, 'wall_seconds': 820.965,
    },
    ('sigminer', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1987.9280860000001, 'wall_seconds': 1506.929,
    },
    ('sigminer', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1473.853008, 'wall_seconds': 1028.773,
    },
    ('sigminer', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1074.911007, 'wall_seconds': 802.948,
    },
    ('sigminer', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 992.969009, 'wall_seconds': 740.132,
    },
    ('sigminer', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1073.205358, 'wall_seconds': 808.615,
    },
    ('sigminer', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1092.265774, 'wall_seconds': 813.111,
    },
    ('sigminer', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 994.2634899999999, 'wall_seconds': 752.927,
    },
    ('sigminer', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1078.1636099999998, 'wall_seconds': 816.187,
    },
    ('sigminer', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1091.936985, 'wall_seconds': 809.114,
    },
    ('sigminer', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1028.535546, 'wall_seconds': 558.21,
    },
    ('sigminer', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 919.758643, 'wall_seconds': 513.429,
    },
    ('sigminer', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 808.148956, 'wall_seconds': 498.576,
    },
    ('sigminer', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 988.060477, 'wall_seconds': 692.085,
    },
    ('sigminer', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1085.672869, 'wall_seconds': 818.52,
    },
    ('sigminer', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1110.405228, 'wall_seconds': 828.443,
    },
    ('sigminer', 'main', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 1330.222873, 'wall_seconds': 940.066,
    },
    ('sigminer', 'main', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1062.816926, 'wall_seconds': 812.905,
    },
    ('sigminer', 'main', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1877.874399, 'wall_seconds': 1467.65,
    },
    ('sigminer', 'nb', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1006.058547, 'wall_seconds': 562.568,
    },
    ('sigminer', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigminer__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 1096.5625750000002, 'wall_seconds': 838.544,
    },
    ('sigprofiler', 'clock', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__clock__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 39.244772999999995, 'wall_seconds': 18.449,
    },
    ('sigprofiler', 'comp_clock_only', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_clock_only__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 34.820338, 'wall_seconds': 16.98,
    },
    ('sigprofiler', 'comp_clock_only', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_clock_only__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 34.806035, 'wall_seconds': 16.399,
    },
    ('sigprofiler', 'comp_clock_only', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_clock_only__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 35.652210999999994, 'wall_seconds': 16.759,
    },
    ('sigprofiler', 'comp_flat_triple', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_flat_triple__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 40.549361, 'wall_seconds': 18.38,
    },
    ('sigprofiler', 'comp_flat_triple', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_flat_triple__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 39.274159999999995, 'wall_seconds': 18.277,
    },
    ('sigprofiler', 'comp_flat_triple', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_flat_triple__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.464264, 'wall_seconds': 17.207,
    },
    ('sigprofiler', 'comp_mmr', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_mmr__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 36.290394, 'wall_seconds': 17.569,
    },
    ('sigprofiler', 'comp_mmr', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_mmr__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.709974, 'wall_seconds': 17.003,
    },
    ('sigprofiler', 'comp_mmr', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_mmr__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.273843, 'wall_seconds': 17.139,
    },
    ('sigprofiler', 'comp_pole', 100000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_pole__N100000__rep100.json'),
        'reps': 100, 'cpu_seconds': 36.79912, 'wall_seconds': 17.304,
    },
    ('sigprofiler', 'comp_pole', 300000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_pole__N300000__rep100.json'),
        'reps': 100, 'cpu_seconds': 37.579026999999996, 'wall_seconds': 17.521,
    },
    ('sigprofiler', 'comp_pole', 1000000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_pole__N1000000__rep100.json'),
        'reps': 100, 'cpu_seconds': 38.160320999999996, 'wall_seconds': 17.361,
    },
    ('sigprofiler', 'comp_strong_flat', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_strong_flat__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 35.86489, 'wall_seconds': 16.877,
    },
    ('sigprofiler', 'comp_strong_flat', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_strong_flat__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 36.740424000000004, 'wall_seconds': 16.918,
    },
    ('sigprofiler', 'comp_strong_flat', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__comp_strong_flat__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 35.797524, 'wall_seconds': 16.811,
    },
    ('sigprofiler', 'main', 100): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__main__N100__rep100.json'),
        'reps': 100, 'cpu_seconds': 41.832933, 'wall_seconds': 18.637,
    },
    ('sigprofiler', 'main', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__main__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 39.971613000000005, 'wall_seconds': 17.563,
    },
    ('sigprofiler', 'main', 10000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__main__N10000__rep100.json'),
        'reps': 100, 'cpu_seconds': 40.177937, 'wall_seconds': 16.936,
    },
    ('sigprofiler', 'nb', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__nb__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 39.859497, 'wall_seconds': 18.441,
    },
    ('sigprofiler', 'sparse', 1000): {
        'witness': ('m7_floor_calibration_20261009', 'witnesses',
                    'sigprofiler__sparse__N1000__rep100.json'),
        'reps': 100, 'cpu_seconds': 40.213161, 'wall_seconds': 18.265,
    },
}
FLOOR_RATIO = 3.0
PASS_STATUSES = ("ok", "cached")

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
