"""Seed-derived ground truth — the single-ground-truth principle on disk.

The M7 cells run on msuiter-simulated counts from the **frozen G0
simulator**, so the true exposures are known by construction: the frozen
composition axis (``grid.COMPOSITIONS``, with the arm-specific transforms)
times N, on the absolute-counts estimand. Reconstruction therefore goes
through ``g0.sim.truth_composition`` read-only — the very function the
generator composes its mixture from — so truth and counts can never drift
apart, and this slice copies no sampling constant (G0 is frozen; imports
are ``sys.path`` reads, never edits).

The truth is rep-invariant by protocol (each rep re-draws counts, never
the composition, G0 §2.2), which is why it is keyed by ``(profile, arm, N)``.

Honesty note inherited from the generator (``g0/sim.py`` P2g annotation):
on the ``clock`` arm the absolute truth ``h_k = f_k * N`` is the *undiluted
tumour* composition — the observable diluted basis is an open adjudication
item, so clock-arm exposure columns are report-only sensitivity rows and
never verdict input (same stance as the G0 judgment document).
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]              # bench/m7
G0_DIR = HERE.parent / "g0"                             # frozen, read-only
# Insertion order is deliberate: HERE goes in last so bench/m7 ends up AHEAD
# of bench/g0 on sys.path. Both harnesses carry a top-level ``tests`` package
# (and the frozen G0 dir is read-only), so the m7 side must win the name for
# any importer that loads this module first.
for _p in (str(G0_DIR), str(HERE)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from g0 import grid, sim                                # noqa: E402  (read-only)
from g0.providers import provider_by_name              # noqa: E402  (read-only)

# Truth is a pure function of frozen constants; memoise per process.
_ARMS: dict = {}
_PROVIDERS: dict = {}

# Reconstruction shares carry float dust from the composition axes; rounding
# at the 9th decimal sweeps the dust while staying far below the 1e-9
# agreement tolerance with the frozen generator (test_scoring_truth), and the
# CSV renders at 6 decimals anyway — table bytes and in-memory rows can
# never disagree by rounding drift.
_TRUTH_DP = 9


def _arms(profile: str) -> dict:
    arms = _ARMS.get(profile)
    if arms is None:
        arms = {a.name: a for a in grid.arms_for_profile(profile)}
        _ARMS[profile] = arms
    return arms


def _arm(profile: str, name: str):
    arms = _arms(profile)
    if name not in arms:
        raise ValueError(f"unknown arm {name!r} for profile {profile!r} "
                         f"(frozen grid arms: {', '.join(sorted(arms))})")
    return arms[name]


def known_arms(profile: str) -> tuple:
    """The arm names this profile's frozen grid exposes."""
    return tuple(sorted(_arms(profile)))


def cell_truth(profile: str, arm: str, n: int) -> dict:
    """True absolute exposures ``{signature: share x N}`` for one
    ``(profile, arm, N)`` stratum — only present signatures (share > 0)."""
    spec = _arm(profile, arm)
    comp = sim.truth_composition(spec.name, dict(spec.params))
    return {k: round(float(v) * int(n), _TRUTH_DP)
            for k, v in comp.items() if v > 0.0}


def arm_is_judge(profile: str, arm: str) -> bool:
    """Adjudication-membership read straight off the frozen ``ArmSpec``
    (``judge=False`` sensitivity arms are report columns, clause b)."""
    return bool(_arm(profile, arm).judge)


def judge_class(profile: str, arm: str) -> str:
    return "primary" if arm_is_judge(profile, arm) else "sensitivity"


def signature_layer(signature: str) -> str:
    """easy/flat/… report layering from the frozen family table; a
    signature outside it is unlayered ('')."""
    return grid.SIGNATURE_FAMILY.get(signature, "")


def load_provider(name: str, seed: int = 0):
    """The provider whose catalog the cells were generated against — the
    same construction the run path uses (deterministic; memoised)."""
    key = (str(name), int(seed))
    provider = _PROVIDERS.get(key)
    if provider is None:
        provider = provider_by_name(name, seed=key[1])
        _PROVIDERS[key] = provider
    return provider


def truth_vector(provider, signature: str):
    """Unit-normalised truth spectrum of a present signature (split-name
    resolution handled by the provider itself)."""
    return np.asarray(provider.signature(signature), dtype=float)


def catalog_vector(provider, signature: str):
    """Catalog column of a predicted signature, or ``None`` when the tool
    called something the catalog never offered — an uncatalogued call can
    never match and is a false positive by construction."""
    vec = provider.catalog.get(signature)
    return None if vec is None else np.asarray(vec, dtype=float)
