"""The G0 simulation generator (the protocol §2.2 generative model + the adjudication clause-3 scenario upgrade).

The truth mixture: p = Σ_k f_k · S_k. The f comes from the frozen truth composition axis grid.COMPOSITIONS
(adjudication §3 "the truth compositions ≥6 groups", the default master = the F3 frozen composition); the S_k =
the 96-channel signature vectors the provider supplies (each summing to 1; the cosmic-file tier = the COSMIC actual values,
the synthetic tier = the functional analogues). The truth's absolute exposure h_k = f_k · N (counts).
Each rep re-draws only the counts X, never the composition (the protocol §2.2: the conditional coverage, avoiding
composition-sampling variance from diluting the judgment power).

The arm algorithms (all documented deterministic algorithms; the same seed must produce the same counts):

  main   X ~ Multinomial(N, p).
         The protocol main generative model: the world the competitors themselves assume; the miscalibration under their ideal settings is the strongest,
         least-confounded evidence. params["composition"] ∈ grid.COMPOSITIONS
         (master / clock_only / mmr / pole / flat_triple / strong_flat).

  nb     X_c ~ Poisson(λ_c),  λ_c ~ Gamma(shape=size, rate=size/μ_c),
         μ_c = N·p_c. The marginal X_c ~ NB(mean=μ_c, size), Var = μ + μ²/size.
         The per-channel independent Gamma-Poisson mixture (i.e. the standard NB construction); the channels are
         independent of one another and the total is no longer pinned to N (the expectation Σμ = N, the actual total carries NB fluctuation —
         this is part of the over-dispersed world, recorded in the output realized_total).
         The size semantics is aligned with the mSigAct default nbinom.size=8 (the P3 addendum columns share this arm).

  clock  p_obs = ρ·p_tumor + (1−ρ)·p_normal, then Multinomial(N, p_obs).
         ρ = purity (the frozen value 0.4). p_normal = the normal-cell clock-type spectrum, restricted
         within the truth set to SBS1 25% / SBS5 75% (the literature consensus that normal-tissue mutations are dominated
         by clock-like SBS1/5; staying inside the 5-signature set guarantees the estimand remains definable).
         At ρ=0.4 the clock-family share goes 45% → 78% (SBS1 21%, SBS5 57%),
         i.e. the "clock share uplift" direction of the realism memo §3.
         **The diagnostic-scope honesty note (P2g)**: the truth h_k = f_k·N emitted by this arm is the
         **un-diluted** tumor composition (the pre-mixing scope). For the post-dilution "tool-observable truth"
         (how the normal-clock share in the decomposition of h_obs_k = N·p_obs enters the
         estimand) there is a definitional choice — which scope the absolute-exposure coverage should take as
         the denominator still awaits adjudication, an **open item**; the arm currently serves only as a sensitivity report column and never enters the judgment,
         so the judgment semantics is unaffected.

  sparse p': the SPARSE signature's share is set to share (the frozen 2%), the remaining signatures are
         re-normalized by their original proportions (×(1−share)/(1−f_sparse)), then Multinomial(N, p').
         At N=1000 the expectation is 20 counts (the protocol §4: specifically testing the boundary/zeroing behaviour).

The output counts is an integer vector of length 96; the order = the tools/channel-reference/
SBS96.txt canonical order (providers.load_sbs96_labels).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .grid import (COMPOSITIONS, SIGNATURE_FAMILY, NB_SIZE, CLOCK_PURITY)
from .providers import ProviderError

DEFAULT_COMPOSITION = "master"

NORMAL_CLOCK_SPECTRUM = {"SBS1": 0.25, "SBS2": 0.0, "SBS13": 0.0,
                         "SBS5": 0.75, "SBS40": 0.0}


@dataclass
class SimCell:
    """The inputs and outputs of one simulation cell."""

    arm: str
    n: int
    rep: int
    seed: int
    counts: np.ndarray            # (96,) int
    truth_p: np.ndarray           # (96,) the generation mixture (after the dilution/sparse transforms)
    truth_h: dict                 # {signature: the truth's absolute exposure (counts, the main estimand)}
    realized_total: int
    params: dict = field(default_factory=dict)


def truth_composition(arm: str, params: dict) -> dict:
    """The truth composition corresponding to the arm (the frozen composition axis + the arm-specific transforms)."""
    name = params.get("composition", DEFAULT_COMPOSITION)
    if name not in COMPOSITIONS:
        raise ProviderError(
            f"unknown composition '{name}' (frozen axis: {sorted(COMPOSITIONS)})")
    comp = dict(COMPOSITIONS[name])
    if arm == "sparse":
        sig = params.get("sparse_signature", "SBS13")
        share = float(params.get("sparse_share", 0.02))
        rest = 1.0 - share
        total_rest = sum(v for k, v in comp.items() if k != sig)
        comp = {k: (share if k == sig else v / total_rest * rest)
                for k, v in comp.items()}
    return comp


def truth_spectrum(provider, arm: str, params: dict):
    """Returns (the p generation mixture, comp). p = Σ_k comp[k]·S_k, S_k = provider.signature(k)."""
    comp = truth_composition(arm, params)
    p = np.zeros(96)
    for name, share in comp.items():
        p += share * provider.signature(name)
    return p, comp


def dilute_for_clock(p: np.ndarray, provider, purity: float) -> np.ndarray:
    """The clock mixing: p_obs = ρ·p_tumor + (1−ρ)·p_normal (a documented deterministic algorithm)."""
    p_normal = np.zeros(96)
    for name, w in NORMAL_CLOCK_SPECTRUM.items():
        p_normal += w * provider.truth[name]
    return purity * p + (1.0 - purity) * p_normal


def sample_cell(provider, arm: str, n: int, rep: int, seed: int,
                params: dict | None = None) -> SimCell:
    """Generates one counts vector per the arm semantics. Deterministic: the same (arm, n, rep, seed) gives the same output."""
    params = dict(params or {})
    rng = np.random.default_rng(seed)
    p_raw, comp = truth_spectrum(provider, arm, params)

    if arm == "clock":
        purity = float(params.get("purity", CLOCK_PURITY))
        p = dilute_for_clock(p_raw, provider, purity)
    else:
        p = p_raw
    p = p / p.sum()

    truth_h = {k: comp[k] * n for k in comp}

    if arm == "nb":
        size = float(params.get("nb_size", NB_SIZE))
        mu = n * p
        # the Gamma-Poisson mixture (the standard NB construction; the documentation is in the module docstring)
        lam = rng.gamma(shape=size, scale=mu / size)
        counts = rng.poisson(lam)
    else:
        counts = rng.multinomial(n, p)

    return SimCell(arm=arm, n=n, rep=rep, seed=seed, counts=counts.astype(np.int64),
                   truth_p=p, truth_h=truth_h,
                   realized_total=int(counts.sum()), params=params)


def layer_of(signature: str) -> str:
    """The report stratification: §2.4 easy/flat (referenced by the judgment sub-clauses; the cross-signature averaging that masks the flat layer is forbidden)
    + the composition-axis extended families mmr/pole/strong (the coverage-table report columns only, never entering the judgment sub-clauses)."""
    fam = SIGNATURE_FAMILY.get(signature)
    if fam is None:
        raise KeyError(signature)
    return fam
