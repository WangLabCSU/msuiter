"""Shared synthetic bytes for the co-tenancy producer law groups ((QE)/(QE2)).

Phase-D stage A (controller ruling 2026-11-04, tools/coex-producer). Two faces
live here, both single-sourced:

  handwritten_record  -- the FORGER's input: the shape-only inversion-probe
      record that passed the pre-teeth gate (the banked state C of the
      Phase-C adjudication). Kept verbatim as the negative fixture every
      refusal unit drives; it must never pass again.
  rig_record          -- the honest face: it DRIVES
      tools/coex_inversion_probe.build_record over synthetic legs, obeying
      the byte-true-fixtures law (a fixture mirrors the tool's captured
      bytes, never an idealization beside them). The rig import is lazy so
      a missing rig reddens the units that need it, not the whole module.
"""

from __future__ import annotations

import hashlib
import json
import importlib
from pathlib import Path

# Deterministic synthetic measurement face (the Phase-6 O2 ratio: cohort legs
# ~12-13.5 % over the solo mean, cpu pinned alongside -- memory-bandwidth
# contention class). Values are data, computed constants where they bind.
IMAGE_REF = "msuiter-sigminer:p6-coex-fixture-r1"
IMAGE_DIGEST = "sha256:" + hashlib.sha256(b"coex-fixture-image").hexdigest()
CAMPAIGN = "m7_floor_calibration_p7cap_coex_fixture"
CELL = "tool__arm__N100"
MEASURED_UTC = "2026-10-28T00:00:00Z"
SOLO_WALLS = (969.9, 970.5, 969.3)
COHORT_WALLS = (1101.0, 1096.0, 1089.0)
LEG_SPAN_S = 1100.0
BASE_MONO_NS = 5_000_000_000_000
BASE_REAL_NS = 1_761_603_200_000_000_000
_BOOT_HEX = hashlib.sha256(b"coex-fixture-boot").hexdigest()
HOST = {"boot_id": (f"{_BOOT_HEX[0:8]}-{_BOOT_HEX[8:12]}-4{_BOOT_HEX[13:16]}"
                    f"-8{_BOOT_HEX[17:20]}-{_BOOT_HEX[20:32]}"),
        "kernel_release": "6.8.0-coex-fixture",
        "cgroup": "0::/system.slice/docker-coex-fixture.scope"}
CELL_ARGV = ["--counts", "/work/in/counts.csv", "--catalog", "/work/in/catalog.csv",
             "--params", "/work/in/params.json", "--outdir", "/work/out"]


def _rig():
    """Lazy rig seam: absent rig == red-by-absence at the calling unit."""
    return importlib.import_module("tools.coex_inversion_probe")


def container_id(i: int) -> str:
    return hashlib.sha256(f"coex-fixture-ctr-{i}".encode()).hexdigest()[:64]


def leg(i: int, wall_s: float, *, stagger_s: float = 0.0) -> dict:
    """One well-formed leg: positive numerics, strictly ordered mono/real
    clock pair; cohort legs stagger inside each other's windows so the
    overlap law is genuinely satisfied."""
    start = BASE_MONO_NS + int(stagger_s * 1e9)
    return {"probe": f"r{i}", "wall_s": wall_s, "cpu_s": wall_s + 0.5,
            "container_id": container_id(i),
            "clock": {"start_mono_ns": start,
                      "stop_mono_ns": start + int(LEG_SPAN_S * 1e9),
                      "start_real_ns": BASE_REAL_NS + int(stagger_s * 1e9),
                      "stop_real_ns": BASE_REAL_NS
                                         + int((stagger_s + LEG_SPAN_S) * 1e9)},
            "rss_peak_kb": 4_000_000 + i}


def solo_legs():
    return [leg(i, w) for i, w in enumerate(SOLO_WALLS)]


def cohort_legs():
    # 10 s stagger: every pair's window (1100 s) strictly overlaps.
    return [leg(10 + i, w, stagger_s=10.0 * i)
            for i, w in enumerate(COHORT_WALLS)]


def handwritten_record() -> dict:
    """The banked state-C bytes: self-reported shape, no digest, no host
    binding, no run linkage. This is what the teeth exist to refuse."""
    return {"schema": 1, "shape": "coex-inversion/N=3",
            "legs": [{"probe": "r1", "wall_s": 1101.0, "cpu_s": 1101.5},
                     {"probe": "r2", "wall_s": 1096.0, "cpu_s": 1096.2},
                     {"probe": "r3", "wall_s": 1089.0, "cpu_s": 1089.9}],
            "solo_mean_s": 969.9, "deltas_pct": [13.5, 13.0, 12.3],
            "bar_pct": 5.0, "verdict": "NOT-FLAT",
            "measured_utc": MEASURED_UTC}


def rig_record(**kw):
    """Drive the rig's honest emit path over the synthetic legs. Every kwarg
    forwards to tools.coex_inversion_probe.build_record."""
    rig = _rig()
    kw.setdefault("tool", "sigminer")
    kw.setdefault("arm", "main")
    kw.setdefault("n", 1000)
    kw.setdefault("reps", 100)
    kw.setdefault("campaign", CAMPAIGN)
    kw.setdefault("measured_utc", MEASURED_UTC)
    kw.setdefault("image", {"ref": IMAGE_REF, "digest": IMAGE_DIGEST})
    kw.setdefault("host", dict(HOST))
    kw.setdefault("cell_argv", list(CELL_ARGV))
    # An explicitly staged empty face must survive the defaulting: [] is a
    # defect the law must see, not an absent kwarg.
    if kw.get("solo_legs") is None:
        kw["solo_legs"] = solo_legs()
    if kw.get("cohort_legs") is None:
        kw["cohort_legs"] = cohort_legs()
    return rig.build_record(**kw)


def stage(tmp: Path, *, name: str = "coex.json", book: bool = True,
          **kw):
    """Write a rig record beside its rig ledger under tmp (the mint-side
    double-entry posture); book=False withholds the ledger line."""
    rig = _rig()
    rec = rig_record(**kw)
    out = tmp / name
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
    if book:
        rig.book_ledger(tmp, rec)
    return out, rec


def reseal(rec: dict, **updates) -> dict:
    """Mutate then re-digest -- isolates the derived-face teeth from the
    seal's own consistency teeth."""
    return _rig().reseal({**rec, **updates})


def preflight_log(tmp: Path, *, decision: str = "GO", cell: str = CELL) -> Path:
    log = tmp / "preflight_log.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": MEASURED_UTC, "cell": cell,
                            "live_measurement_containers": 0,
                            "decision": decision}) + "\n")
    return log


def fake_live_probe(*, unknown=(), wrong_image=None, broken=False):
    """Injectable replay face (the gov.pre_flight_assert probe= idiom):
    answers the daemon with well-formed inspect data for every id unless
    commanded otherwise; broken=True simulates a daemon that will not
    answer -- which the law must read as refusal, never as a pass."""
    if broken:
        def _broken(container_ids, image):
            raise OSError("injected: daemon not answering")
        return _broken

    def _probe(container_ids, image):
        out = {}
        for cid in container_ids:
            if cid in unknown:
                out[cid] = {"known": False}
                continue
            out[cid] = {"known": True,
                        "config_image": wrong_image if wrong_image else image["ref"],
                        "started": "2026-10-28T00:00:00+00:00",
                        "finished": "2026-10-28T00:20:00+00:00"}
        return out
    return _probe
