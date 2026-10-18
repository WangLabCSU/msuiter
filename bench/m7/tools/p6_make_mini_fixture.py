#!/usr/bin/env python3
"""p6_make_mini_fixture -- deterministic regenerator for the arm-image
witness fixture counts.csv (bake death #7 adjudication).

The #13-era witness fixture carried a single sample: the rust face
legitimately refuses a 96x1 catalog at k=2 ("nndsvd: rank k exceeds
min(m, n)") and the post_p1 tree's .rust_status -- which reads an
always-absent "status" attribute off the system2 RESULT and defaults
to 0 -- reported that rc=2 refusal as a missing meta.csv. The lane law
is that the layer-28 witness must exercise a cell the pipeline can
actually adjudicate, so the fixture grows to twenty aligned samples:

  * row r0 is the #13 attested bytes, verbatim, untouched;
  * rows r1..r19 are seeded draws of N100 = 100 mutation events over
    the 96 channels from a two-profile mixture of committed catalog.csv
    columns (PROFILES below) -- COSMIC profiles already banked in the
    tree, no invented biology;
  * sample j draws from random.Random(SEED_BASE + j) with alpha_j a
    closed-form rotation, so the bytes are reproducible from this file
    alone; tests/test_p6_mini_fixture.py asserts the committed file is
    byte-identical to regeneration.

This is build-witness data only. No number here is a measurement and
none may ever enter the paper's table; campaign cells draw their own
counts through the harness.

Usage:
  python3 tools/p6_make_mini_fixture.py            # print byte-differs status
  python3 tools/p6_make_mini_fixture.py --write    # commit the bytes
  python3 tools/p6_make_mini_fixture.py --check    # rc 2 on drift
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]           # bench/m7
LEGACY = HERE / "adapters" / "mini_cell"             # byte-frozen inputs
MINI = HERE / "adapters" / "mini_cell_p6"            # the regeneration home

SEED_BASE = 1815578668                               # the params.json seed
N_SAMPLES = 20
N_TOTAL = 100                                        # the N100 witness law
PROFILES = ("SBS1", "SBS5")                          # committed COSMIC columns

## The #13 attested r0 row is read from the byte-frozen legacy fixture at
## generation time -- never re-typed here. That file is itself live-rehashed
## by the #13-era rehearsal manifest (group (O) rehashes it on every suite
## run), so the r0 lineage rides the committed hash chain, not a copy.


def _origin_row() -> str:
    """The legacy attested data row, fail-closed: exactly one sample r0."""
    rows = [ln for ln in (LEGACY / "counts.csv").read_text(
        encoding = "utf-8").splitlines() if ln]
    if len(rows) != 2 or not rows[1].startswith("main__N100__r0,"):
        raise SystemExit(f"[FATAL] legacy {LEGACY / 'counts.csv'} is not the "
                         "attested single-sample fixture any more")
    return rows[1]


def _catalog() -> tuple[list[str], dict[str, list[float]]]:
    """Read channel order and the profile columns from committed catalog.csv."""
    lines = (LEGACY / "catalog.csv").read_text(encoding = "utf-8").splitlines()
    head = lines[0].split(",")
    idx = {name: head.index(name) for name in PROFILES}   # fail-closed
    channels: list[str] = []
    cols: dict[str, list[float]] = {name: [] for name in PROFILES}
    for line in lines[1:]:
        fields = line.split(",")
        channels.append(fields[0])
        for name in PROFILES:
            cols[name].append(float(fields[idx[name]]))
    return channels, cols


def _mixture(cols: dict[str, list[float]], alpha: float) -> list[float]:
    left, right = (cols[PROFILES[0]], cols[PROFILES[1]])
    return [alpha * a + (1.0 - alpha) * b for a, b in zip(left, right)]


def _sample(probs: list[float], rng: random.Random) -> list[int]:
    hits = [0] * len(probs)
    for idx in rng.choices(range(len(probs)), weights = probs, k = N_TOTAL):
        hits[idx] += 1
    return hits


def generate_bytes() -> bytes:
    """The full counts.csv bytes, header + r0 attested + r1..r19 derived."""
    channels, cols = _catalog()
    header = "sample_id," + ",".join(channels)
    lines = [header, _origin_row()]
    for j in range(1, N_SAMPLES):
        alpha = ((j * 29) % 21) / 20.0
        probs = _mixture(cols, alpha)
        counts = _sample(probs, random.Random(SEED_BASE + j))
        lines.append(f"main__N100__r{j}," + ",".join(str(c) for c in counts))
    return ("\n".join(lines) + "\n").encode("utf-8")


def main(argv: list[str]) -> int:
    target = MINI / "counts.csv"
    committed = target.read_bytes() if target.is_file() else b""
    fresh = generate_bytes()
    if "--write" in argv:
        (MINI / "counts.csv").write_bytes(fresh)
        print(f"[mini-fixture] wrote {len(fresh)} bytes, "
              f"{N_SAMPLES} samples at N{N_TOTAL}")
        return 0
    if fresh == committed:
        print("[mini-fixture] committed bytes match regeneration")
        return 0
    print("[FATAL] committed counts.csv diverges from the committed rule; "
          "regenerate with --write and commit the delta", file = sys.stderr)
    return 2 if "--check" in argv else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
