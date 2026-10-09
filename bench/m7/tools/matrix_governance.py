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

import json
import math
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


# -- (4) the 3x-floor gate: pre-registered uncontended floors ---------------------
# Floors are PRE-REGISTERED model projections fixed BEFORE the fresh serial
# pass (RB-08(7)); they are never re-fit to the data they gate. Form:
#
#     floor(tool, arm, n) = BOOT(tool) + REPS x MULT(arm) x WORK(tool)
#                                     x sqrt(max(n, 100) / 100)
#
# The sqrt-in-n growth is the §5 complexity projection: per-rep cost is
# dominated by scanning the 100k-segment genome, so work per mutation
# collapses as the mutated fraction saturates (measured plateaus: sigminer
# ~3.6 s/rep at N100 [r5 GREEN probe, cpu_seconds 360.25] rising to
# ~25 s/rep at the N1e4 class [committed sharded survivors], then only
# 27-34 s/rep across N1e5..N1e6); linear scaling would mispredict the
# 1e4-class survivors by an order of magnitude and leave the heavy cells
# without teeth. Growth saturates at N_SAT: beyond it the genome is
# mutation-covered.
#   anchors: BOOT+WORK(sigminer)  fixed by the r5 GREEN probe (single
#            uncontended main/N100 cell, cpu_seconds 360.25);
#            BOOT+WORK(sigprofiler) fixed by pilot §2 uncontended N100
#            main wall 13.4 s (docs/devlog pilot table).
#   MULT(arm) from the §5 pass-count projections (MINT triage = 3 passes).
# Overshoot is the SAFE direction (a too-low floor false-halts the matrix);
# the 3x margin absorbs boot noise on top.
_BOOT = {"sigminer": 60.0, "sigprofiler": 8.0}
_WORK = {"sigminer": 2.5, "sigprofiler": 0.054}
_REPS = 100          # frozen degraded-profile repetitions
_N_REF = 100         # calibration point of BOOT+WORK
_N_SAT = 10_000      # mutation-saturation ceiling of the sqrt regime
_ARM_MULT = {"main": 1.0, "comp_clock_only": 1.2, "comp_mmr": 1.8,
             "comp_pole": 3.5, "comp_flat_triple": 1.6,
             "comp_strong_flat": 2.0, "nb": 1.1, "clock": 1.2,
             "sparse": 1.0}
FLOOR_RATIO = 3.0
PASS_STATUSES = ("ok", "cached")


def floor_for(tool: str, arm: str, n: int) -> float:
    """Pre-registered uncontended floor for one cell (units: the tool's
    anchor units — cpu_seconds-style work-seconds for sigminer, wall for
    sigprofiler; the gate measures max(wall, cpu) against it). Unknown
    tool/arm is a hard error — silence here would mean an ungated cell."""
    if tool not in _BOOT:
        raise KeyError(f"no pre-registered floor for tool {tool!r}")
    if arm not in _ARM_MULT:
        raise KeyError(f"no pre-registered floor for arm {arm!r}")
    if n < 1:
        raise ValueError(f"floor needs n >= 1, got {n!r}")
    growth = math.sqrt(max(n, _N_REF) / _N_REF)
    growth = min(growth, math.sqrt(_N_SAT / _N_REF))
    return _BOOT[tool] + _REPS * _ARM_MULT[arm] * _WORK[tool] * growth


def floor_gate(row: dict):
    """RB-08(7): None (pass) or a DEFECT-candidate flag row. Silent on
    non-pass rows — a dead cell is diagnosed by its own death text — and on
    non-measurement tools (mock/signal are plumbing with no uncontended
    floor). An unknown ARM of a measured tool is a hard error: silence
    there would mean an ungated cell."""
    if row["status"] not in PASS_STATUSES:
        return None
    tool, arm, n = parse_stamp(row["cell"])
    if tool not in _BOOT:
        return None
    floor = floor_for(tool, arm, n)
    observed = max(float(row["seconds"]), float(row.get("cpu_seconds", 0.0)))
    if observed <= FLOOR_RATIO * floor:
        return None
    return {**row,
            "status": (f"defect-floor: wall/cpu {observed:.1f}s > "
                       f"{FLOOR_RATIO}x pre-registered floor {floor:.1f}s "
                       f"(tool={tool} arm={arm} n={n})")}


def nonpass_rows(rows) -> list[dict]:
    """The judgment writer's refuse-to-claim predicate: any row that is not
    an outright pass (ok/cached) voids the fairness attestation header."""
    return [r for r in rows if r["status"] not in PASS_STATUSES]
