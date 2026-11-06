#!/usr/bin/env python3
"""Byte-exact comparator for the batch-bridge transport face (R1-PARITY, (AK)).

The batch bridge changes WHO calls the kernel and WHEN -- one process per
(rank, bootstrap) unit through ``msuiter-kernel fit-kl --cases`` instead of one
spawn per fit. It may not change WHAT the cell commits: the two adapter-
protocol outputs a cell delivers (``intervals.csv``, ``spectra.csv``) must be
byte-identical between the batch face and the per-spawn face it replaced. This
is the P10 cross-route bit-identity law (in-tree precedent: the 346+476
expectation cross-route attestation) extended to the arm face, and it is the
gate the parity claim stands on -- a transport that "only" changes scheduling
and silently shifts a printed float is worth nothing as a measurement.

Firing shape (the dead-metric law -- a comparator that cannot fail guards
nothing): both tables must exist on both sides and must hash equal; the bite
names the offending file. Absent file is a bite, not a skip: a face that
delivered one output did not deliver the cell.

Usage:
  python3 tools/batch_bridge_bit_identity.py --batch <dir> --spawn <dir>
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

# The adapter-protocol deliverables, in the order the cell writes them. The
# sidecar JSON is deliberately NOT here: it carries measurement metadata
# (epoch, seeds, timing) that legitimately differs between two runs of the
# same cell, and the battery's (AK) sidecar unit governs it separately.
CELL_OUTPUTS = ("intervals.csv", "spectra.csv")


def _digest(path: Path) -> tuple[str, int]:
    """(sha256 hex, byte length) of one committed table, streamed -- a cell
    table is small, but a comparator that buffers has no business claiming
    byte truth over a file it only partly saw."""
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
            size += len(chunk)
    return h.hexdigest(), size


def compare_cell(batch_dir: Path, spawn_dir: Path) -> None:
    """Die loudly unless both cells committed byte-identical tables.

    Raises FileNotFoundError naming the missing table, or ValueError naming the
    diverging one (with both digests and the first differing offset -- a bare
    'not equal' cannot be adjudicated). Returns None on identity."""
    for name in CELL_OUTPUTS:
        left, right = batch_dir / name, spawn_dir / name
        for side, path in (("batch", left), ("spawn", right)):
            if not path.is_file():
                raise FileNotFoundError(
                    f"{name} is missing on the {side} side ({path}) -- a cell "
                    "that delivered half its outputs delivered no cell")
        hl, sl = _digest(left)
        hr, sr = _digest(right)
        if (hl, sl) != (hr, sr):
            off = next((i for i, (a, b) in enumerate(zip(left.read_bytes(),
                                                         right.read_bytes()))
                        if a != b), min(sl, sr))
            raise ValueError(
                f"{name} is NOT byte-identical across the transport: "
                f"batch {hl}/{sl}B vs spawn {hr}/{sr}B, first divergence at "
                f"offset {off} -- the batch bridge may move the kernel call, "
                "never the committed bytes")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--batch", type=Path, required=True,
                    help="outdir of the cell run through the batch bridge")
    ap.add_argument("--spawn", type=Path, required=True,
                    help="outdir of the same cell run through the per-spawn face")
    args = ap.parse_args(argv)
    try:
        compare_cell(args.batch, args.spawn)
    except (FileNotFoundError, ValueError) as exc:
        sys.stderr.write(f"[FATAL] {exc}\n")
        return 2
    print(f"[bit-identity] {', '.join(CELL_OUTPUTS)} byte-identical across "
          f"the transport: {args.batch.name} == {args.spawn.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
