"""The G0 seed discipline (the protocol §2.3, frozen).

master seed = 20260928; the deterministic per-(arm, N, rep) derivation, all seeds landing on disk in Seeds.txt
manifest (the field-missing practice pointed out by research/05 §6; this experiment demonstrates it first).

The derivation layout (deterministic, reproducible across platforms and across Python versions; the same
shape as the ARCH §2 rng.rs SplitMix64 counter-stream design):

    label   = "g0/v1|" + "|".join(str(p) for p in parts)
    key     = fnv1a64(label)                 # the stream label -> the 64-bit stream key
    seed    = splitmix64_final(MASTER_SEED XOR key)   # the counter + finalizer

- fnv1a64: FNV-1a 64-bit (only the string -> 64-bit compression; no randomization, never the
  Python built-in hash() — it carries a PYTHONHASHSEED randomization over str, forbidden).
- splitmix64_final: the three-round mixing finalizer of SplitMix64 (Steele et al. 2014,
  public domain), the same family as the rng.rs stream derivation.
- The derived 64-bit integer is fed to numpy Generator(PCG64) (np.random.default_rng).

The tool-side randomness (HMC / bootstrap) is derived separately: derive_seed(tool, arm, N, rep),
not overlapping the data seeds (the labels differ).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

MASK64 = (1 << 64) - 1

MASTER_SEED = 20260928  # frozen (the protocol §2.3)
STREAM_VERSION = "g0/v1"

# The tool-boundary seed domain (the 2026-10-07 G0 docker rerun root cause): the container-side R
# `as.integer(params$seed)` overflowed into NA and the whole sigfit/stl cell went FATAL.
# Stan's seed and the STL's randomSeed both land in the int32 domain; the u64 derivation stream
# (the numpy PCG64 data stream) does not pass through this fold.
TOOL_SEED_CAP = 1 << 31


def _splitmix64(x: int) -> int:
    """The SplitMix64 finalizer: one 64-bit counter -> a uniform 64-bit output."""
    x = (x + 0x9E3779B97F4A7C15) & MASK64
    z = x
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
    return z ^ (z >> 31)


def _fnv1a64(s: str) -> int:
    h = 0xCBF29CE484222325
    for byte in s.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001B3) & MASK64
    return h


def derive_seed(*parts: Iterable) -> int:
    """Deterministically derives a 64-bit seed from any tuple of labels.

    Example: derive_seed("main", 1000, 7) is the data seed of (arm=main, N=1000, rep=7);
    the tool side uses tool_seed (the int32 value folded at the tool boundary).
    """
    label = STREAM_VERSION + "|" + "|".join(str(p) for p in parts)
    key = _fnv1a64(label)
    return _splitmix64(MASTER_SEED ^ key)


def tool_seed(*parts: Iterable) -> int:
    """The tool-boundary seed: the deterministic fold of derive_seed, landing in [0, 2^31).

    Everything fed to the container (the seed / sample_seeds of params.json, the per-tool columns of
    Seeds.txt) passes this fold; the full u64 values are kept in the data stream (make_rng) and in
    the manifest's data_seed column. The fold is deterministic: tool_seed = derive_seed % 2^31.
    """
    return derive_seed(*parts) % TOOL_SEED_CAP


def make_rng(*parts) -> "np.random.Generator":
    import numpy as np  # the local import: the pure derivation functions do not depend on numpy

    return np.random.default_rng(derive_seed(*parts))


@dataclass(frozen=True)
class SeedSpec:
    """One simulation cell: arm × N × rep."""

    arm: str
    n: int
    rep: int

    @property
    def data_seed(self) -> int:
        return derive_seed(self.arm, self.n, self.rep)


def write_seeds_manifest(path: Path, specs: Sequence[SeedSpec],
                         tool_names: Sequence[str] = ("sigfit", "stl"),
                         header_note: str = "") -> Path:
    """Lands the Seeds.txt manifest on disk (the protocol §2.3: all the seeds land on disk).

    The format: tab-separated, with the two leading comment lines (starting with #) + the column header.
    Each row: arm, N, rep, data_seed, plus the per-tool seed columns."
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"# G0 Seeds manifest | master_seed={MASTER_SEED} | "
                 f"derivation={STREAM_VERSION}: splitmix64(master ^ fnv1a64(label))\n")
        fh.write("# tool seed columns = same derivation folded mod 2^31 "
                 "(int32 seed domain of Stan/STL; data_seed stays u64)\n")
        if header_note:
            fh.write(f"# note: {header_note}\n")
        cols = ["arm", "N", "rep", "data_seed"] + [f"seed_{t}" for t in tool_names]
        fh.write("\t".join(cols) + "\n")
        for s in specs:
            tool_seeds = [tool_seed(t, s.arm, s.n, s.rep) for t in tool_names]
            fh.write("\t".join(str(v) for v in
                               (s.arm, s.n, s.rep, s.data_seed, *tool_seeds)) + "\n")
    return path
