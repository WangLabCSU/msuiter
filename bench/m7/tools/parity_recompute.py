"""⑯ Post-cap parity recompute (Phase-7 O5): every R-family face of the sealed
floor table against the compiled sigprofiler yardstick, per class, cpu basis.

The perf-parity mandate (<=/2x sigprofiler) is a HARD requirement of the perf
program; this tool does not enforce it at gate time -- it MEASURES the
committed record. The cpu basis is the metric of record (wall rides host
contention); wall is reported alongside for the record only.

Law honoured here:
  MEASURED-then-STATED -- every figure is re-read from the witness bytes
    (wall from the witness, cpu from its sidecar) and must equal the value
    the floor table carries; any drift REFUSES the line, never rounds it.
  PATH-BINDING -- every printed ratio carries BOTH witness paths in the same
    line plus a string-equality attestation of class (arm, n) and reps
    re-read from the two witness documents.

A breach is a FINDING banked verbatim for the perf program -- this tool never
touches physics, the floor gate, or the committed witnesses. Exit 0 with a
BREACH census is an honest run; exit 2 is inadmissible input (missing yard,
witness drift, absent --reps echo).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]           # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import tools.matrix_governance as gov                # noqa: E402
from competitors.registry import REGISTRY             # noqa: E402

BAR_PARITY = 2.0                     # perf-parity mandate: hard <=2x ceiling
YARDSTICK = "sigprofiler"            # compiled benchmark, runtime != "R"


def _witness_face(anchor: dict) -> tuple[float, float, dict]:
    """(cpu, wall, doc) re-read from the witness bytes, verified against the
    table entry. Admissibility: verdict OK, run_rc 0, sidecar exit 0, the
    --reps 100 echo, and byte-equal re-measure against the table."""
    path = gov.anchor_witness_path(anchor)
    doc = json.loads(path.read_text(encoding="utf-8"))
    if doc.get("verdict") != "OK" or doc.get("run_rc") != 0:
        raise SystemExit(2, f"{path}: witness not admissible "
                           f"(verdict={doc.get('verdict')!r} run_rc={doc.get('run_rc')!r})")
    argv = list(doc.get("argv", []))
    idx = argv.index("--reps") if "--reps" in argv else -1
    echo = argv[idx + 1] if 0 <= idx and idx + 1 < len(argv) else None
    if echo != str(gov.PROTOCOL_REPS) or doc.get("reps") != gov.PROTOCOL_REPS:
        raise SystemExit(2, f"{path}: reps echo != {gov.PROTOCOL_REPS}")
    side = doc.get("sidecar") or {}
    if side.get("exit_status") != 0:
        raise SystemExit(2, f"{path}: sidecar exit {side.get('exit_status')!r}")
    cpu, wall = float(side.get("cpu_seconds", -1)), float(doc.get("wall_seconds", -1))
    if cpu <= 0 or wall <= 0:
        raise SystemExit(2, f"{path}: non-positive witness metrics")
    if cpu != float(anchor["cpu_seconds"]) or wall != float(anchor["wall_seconds"]):
        raise SystemExit(2, f"{path}: witness bytes {cpu}/{wall} drifted from "
                            f"table {anchor['cpu_seconds']}/{anchor['wall_seconds']}")
    return cpu, wall, doc


def _classes() -> list[tuple[str, int]]:
    pts = sorted({(arm, n) for (t, arm, n) in gov._FLOOR_ANCHORS if t == YARDSTICK})
    if not pts:
        raise SystemExit(2, f"no yardstick anchors for {YARDSTICK}")
    return pts


def main() -> int:
    r_faces = sorted(t for t in gov._MEASURED_TOOLS
                     if t != YARDSTICK and REGISTRY[t].runtime == "R")
    yards = {}
    for arm, n in _classes():
        yards[(arm, n)] = _witness_face(gov._FLOOR_ANCHORS[(YARDSTICK, arm, n)])
    breaches = 0
    for face in r_faces:
        for (arm, n) in sorted(yards):
            key_f, key_y = (face, arm, n), (YARDSTICK, arm, n)
            if key_f not in gov._FLOOR_ANCHORS:
                print(f"NO-ANCHOR {face} {arm} N{n} — the all-or-nothing law "
                      f"says this face is not admissible")
                return 2
            f_cpu, f_wall, f_doc = _witness_face(gov._FLOOR_ANCHORS[key_f])
            y_cpu, y_wall, y_doc = yards[(arm, n)]
            if str(f_doc["arm"]) != str(y_doc["arm"]) \
                    or str(f_doc["n"]) != str(y_doc["n"]) \
                    or str(f_doc["reps"]) != str(y_doc["reps"]):
                raise SystemExit(2, f"{face} {arm} N{n}: class/reps mismatch "
                                    f"between bound witnesses")
            ratio = f_cpu / y_cpu
            verdict = "PASS" if ratio <= BAR_PARITY else "BREACH"
            breaches += verdict == "BREACH"
            print(f"{face} {arm} N{n} reps={f_doc['reps']} cpu-basis "
                  f"ratio={ratio:.4f} {verdict} (bar {BAR_PARITY}) | "
                  f"face={f_cpu:.6f}s {gov.anchor_witness_path(gov._FLOOR_ANCHORS[key_f])} "
                  f"|| yard={y_cpu:.6f}s {gov.anchor_witness_path(gov._FLOOR_ANCHORS[key_y])}")
    faces_c = len(r_faces) * len(yards)
    print(f"[parity-recompute] faces={len(r_faces)} classes={len(yards)} "
          f"lines={faces_c} breaches={breaches} bar=<={BAR_PARITY}x cpu-basis "
          f"yard={YARDSTICK}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
