"""Read-only pin verifier for the committed NM-factorization yardstick record.

Re-checks, without any re-measurement, that the authoritative yardstick
document and the fixture bytes it pins are mutually consistent at the exact
field values quoted by the manuscript:

  * bench/m7/adapters/yardstick_cell/matrix.csv hashes to the document's
    fixture_sha256;
  * ratio_r_over_rust, iterations_fixed, seed, rust_threads, k, shape and the
    two version fields equal their sealed values;
  * a planted-corruption control MUST be refused, proving the comparisons are
    live (DS-1 firing-control idiom; a control that cannot fire is a dead
    metric -- refused here as exit 2).

Exit 0 = all pins hold and the control fired. Exit 1 = a pin drifted (quote
the value nowhere). Exit 2 = inadmissible inputs or a non-firing control.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
DOC = HERE.parent / "results/p6_regen_20261016-011928/nmf_yardstick_authoritative.json"
FIXTURE = HERE / "adapters/yardstick_cell/matrix.csv"

SEALED = {
    "ratio_r_over_rust": 1.2323046734094532,
    "iterations_fixed": 400,
    "r_niter": 400,
    "rust_niter": 400,
    "seed": 1234,
    "rust_threads": 1,
    "k": 2,
    "shape": [400, 80],
    "r_version": "0.28",
    "rust_version": "0.1.0",
}


def check(doc: dict, fixture_digest: str) -> list[str]:
    """Return the list of drift findings (empty == all pins hold)."""
    findings = []
    if doc.get("fixture_sha256") != fixture_digest:
        findings.append(f"fixture digest {fixture_digest} != sealed "
                        f"{doc.get('fixture_sha256')!r}")
    for field, want in SEALED.items():
        got = doc.get(field)
        if got != want:
            findings.append(f"{field}: got {got!r} want {want!r}")
    # field-order consistency: the ratio must equal the sealed seconds pair
    # to within the bytes the document itself carries.
    r_s, x_s = doc.get("r_seconds"), doc.get("rust_seconds")
    if not (isinstance(r_s, float) and isinstance(x_s, float) and x_s > 0):
        findings.append("seconds fields not admissible")
    else:
        rel = abs((r_s / x_s) - doc.get("ratio_r_over_rust", float("nan"))) / (r_s / x_s)
        if rel > 1e-12:
            findings.append(f"ratio bytes inconsistent with seconds pair (rel {rel:g})")
    return findings


def main() -> int:
    try:
        doc = json.loads(DOC.read_text(encoding="utf-8"))
        fixture_digest = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
    except OSError as exc:
        sys.stderr.write(f"[FATAL] inadmissible inputs: {exc}\n")
        return 2
    findings = check(doc, fixture_digest)
    for line in findings:
        sys.stdout.write(f"DRIFT {line}\n")
    # Firing control: corrupt one pin in memory; the checker MUST speak.
    tampered = dict(doc)
    tampered["ratio_r_over_rust"] = doc["ratio_r_over_rust"] + 1e-6
    control = check(tampered, fixture_digest)
    fired = bool(control)
    sys.stdout.write(f"CONTROL planted-corruption refused={fired} "
                     f"({control[0] if control else 'NOTHING FLAGGED'})\n")
    if not fired:
        return 2
    if findings:
        return 1
    sys.stdout.write(
        f"PINS ok ratio_r_over_rust={doc['ratio_r_over_rust']!r} "
        f"fixture={fixture_digest[:16]}... iters={doc['iterations_fixed']} "
        f"seed={doc['seed']} threads={doc['rust_threads']}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
