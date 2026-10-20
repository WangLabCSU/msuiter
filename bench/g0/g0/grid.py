"""The G0 grid and experiment-profile configuration (all the numbers are frozen protocol values; do not alter).

The grid's provenance (the frozen adjudication docs/devlog/2026-09-28-G0-pi-adjudication.md "the PI has adjudicated"
clause 3, adopting the realism memo §2):
- the geometric grid N ≈ 30–10⁶ (the realism memo §2: the panel/ctDNA end 30–100 must enter the grid;
  the upper end 10⁶ covers the common WGS arm ceiling, Alexandrov 2020 PMID 32025018);
- the 10²–10⁴ coverage-cliff region densified with ≥6 points (the adjudication's upgrade over the protocol's original 5 points {100…10000}).

PRIMARY_GRID totals 19 points; within the [10², 10⁴] interval 9 points ≥ 6 (the densification meets the bar);
the maximum adjacent ratio in the judgment-relevant region N≥300 is ≈ 1.87×.

The truth composition axis (the frozen adjudication clause 3 + F3, ≥6 groups; the signature set and the shares are
constructed per the realism memo §3 composition list, the shares take realistic anchors, the literature basis see each entry's note):
master (= the F3 frozen 5 signatures, composition list ② "+APOBEC") + clock_only / mmr / pole /
flat_triple / strong_flat, 6 groups in all. master is simultaneously the reference composition of the §2.4 easy/flat
stratification and of the P1 mechanism (i) probe.

The POLE composition is pinned to the high-N tier (POLE_N_SUBSET): the POLE/POLD1 hypermutator >100 mut/Mb
(Campbell 2017 PMID 28810159), the WGS-equivalent N ≥ 3×10⁵ — for that composition the low-N grid points carry
no physical meaning.

The degraded tier (the protocol memo §6/§7-R7, the frozen adjudication expressly kept it): the 3-point tier {100, 1000, 10000}
or reps=100; the degradation must be recorded into the memo (run_grid writes the profile field into the result table).

The repetition count (the protocol §2.3, frozen): 200/tool/signature/grid point; the gray re-judgment = 400.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# ---- the frozen numbers (within the F1–F4 scope; alteration = violating the pre-registration discipline) --------------------

PRIMARY_GRID = (30, 60, 100, 180, 300, 560, 1000, 1800, 3000, 5600, 10000,
                18000, 30000, 56000, 100000, 180000, 300000, 560000, 1000000)
DEGRADED_GRID = (100, 1000, 10000)          # §6 degraded: the 3-point tier
POLE_N_SUBSET = (100000, 300000, 1000000)   # the high-N tier of the pole composition (Campbell 2017)
REPS_PRIMARY = 200                          # the repetition count matching the §2.3 power accounting
REPS_DEGRADED = 100                         # §6 degraded: reps=100 (the −10pp judgment power is still >0.95)
REPS_GRAY = 400                             # §2.4 gray: the borderline cells doubled to 400
JUDGE_N_MIN = 300                           # §2.4 the judgment's N lower bound (the N≥300 cells)

MASTER_TRUTH_COMPOSITION = {                # F3 frozen: the 5-signature fixed composition (= the composition axis "master")
    "SBS1": 0.15,
    "SBS2": 0.15,
    "SBS13": 0.15,
    "SBS5": 0.30,
    "SBS40": 0.25,
}

# ---- the frozen truth composition axis (adjudication §3 "the truth compositions ≥6 groups"; the realism memo §3) ----
# The shares are realistic anchors (each composition's sum is identically 1); the literature basis is annotated entry by entry inline.

COMPOSITIONS = {
    # ② "+APOBEC" = the F3 frozen master composition: the APOBEC whole group SBS2/13 co-truthful (the realism memo §3
    # mandated companion) + clock + the flat near-duplicate pair; the §2.4 easy/flat stratification is defined on this composition.
    "master": dict(MASTER_TRUTH_COMPOSITION),

    # ① clock-only: SBS1 (the 5mC spontaneous deamination, accumulating linearly with division) and SBS5 (clock-like
    # flat) are almost universally present (Alexandrov et al. 2020, Nature 578:94, PMID 32025018);
    # in PCAWG SBS5 is usually the largest clock-like component ⇒ the SBS5 share > SBS1.
    "clock_only": {"SBS1": 0.30, "SBS5": 0.70},

    # ③ the +MMR group: the MMR-deficient/MSI-H tumors are characterized by the correlative group SBS6/15/20/21/26/44 being
    # whole-group co-truthful (the realism memo §3 mandated companion; Alexandrov 2020), SBS44 correlative with SBS6 and
    # carrying the smaller share; the group total ~40% + the clock background (SBS1/SBS5).
    "mmr": {"SBS6": 0.10, "SBS15": 0.08, "SBS20": 0.07, "SBS21": 0.07,
            "SBS26": 0.05, "SBS44": 0.03, "SBS1": 0.20, "SBS5": 0.40},

    # ④ POLE hypermutation: the POLE/POLD1 exonuclease-deficient tumors are dominated by SBS10a plus SBS10b/c/d and
    # SBS28 (Alexandrov 2020; Campbell et al. 2017, Cell 171:1042, PMID 28810159
    # — >100 mut/Mb ⇒ pinned to the high-N tier POLE_N_SUBSET).
    "pole": {"SBS10a": 0.30, "SBS10b": 0.10, "SBS10c": 0.05, "SBS10d": 0.05,
             "SBS28": 0.05, "SBS1": 0.10, "SBS5": 0.35},

    # ⑤ the flat-triple small exposures: SBS1/5/40 same-family flat each <10% (the realism memo §3:
    # "a cell with coexisting small exposures (each <10%) must be set"); the balance is carried by the APOBEC whole group SBS2/13
    # (the burst-type APOBEC tumor + a small flat clock background).
    "flat_triple": {"SBS1": 0.08, "SBS5": 0.08, "SBS40": 0.08,
                    "SBS2": 0.38, "SBS13": 0.38},

    # ⑥ strong signature + flat background: SBS4 (tobacco)/SBS7 (UV) are the classic large-exposure strong signatures
    # (Alexandrov 2020), stacked on the universally present flat clock-like background SBS5/40.
    "strong_flat": {"SBS4": 0.35, "SBS7": 0.35, "SBS5": 0.15, "SBS40": 0.15},
}

EASY_LAYER = ("SBS1", "SBS2", "SBS13")      # §2.4 the stratification (the master composition context)
FLAT_LAYER = ("SBS5", "SBS40")              # §2.4 the flat layer (the near-duplicate pair, the P1 mechanism (i) probe)

# The report stratification of the composition-axis extended signature families (not entering the §2.4 judgment sub-clauses; the coverage-table layer column only).
SIGNATURE_FAMILY = {
    **{k: "easy" for k in EASY_LAYER},
    **{k: "flat" for k in FLAT_LAYER},
    **{k: "mmr" for k in ("SBS6", "SBS15", "SBS20", "SBS21", "SBS26", "SBS44")},
    **{k: "pole" for k in ("SBS10a", "SBS10b", "SBS10c", "SBS10d", "SBS28")},
    **{k: "strong" for k in ("SBS4", "SBS7")},
}

NB_SIZE = 8                                 # the realism memo §4 / P3: the mSigAct default size=8 semantics
CLOCK_PURITY = 0.4                          # the clock-mixing arm: purity≈0.4 equivalent (the adjudication clause 3)
SPARSE_SIGNATURE = "SBS13"                  # §4 the auxiliary sparse arm: the SBS13 share changed to 2%
SPARSE_SHARE = 0.02
SPARSE_N = 1000                             # the sparse arm's single point (expectation SBS13 ≈ 20 counts)
SENS_POINT_N = 1000                         # the sensitivity arms (NB / clock) single-point scope (§2.2)

SUPPORT_A_LOWER = 0.85                      # F1 frozen: the −10pp line supporting A
SUPPORT_A_CI_UPPER_MAX = 0.90               # F1 frozen: the CI upper-bound exclusion line of the clause ①
FLAT_SUPPORT_UPPER = 0.90                   # F1 frozen: the clause ② flat layer all the cells ≤ 0.90
KILL_LOWER = 0.90                           # F1 frozen: the −5pp line of kill→B

TIER1_TOOLS = ("sigfit", "stl")             # F2 frozen: sigfit v2.2.0 + signature.tools.lib v2.5.2


@dataclass(frozen=True)
class ArmSpec:
    """One simulation arm: the name, the generation parameters, the N list and the repetition count.

    judge (P0-2, the frozen addendum clause b): whether this arm enters the §2.4 judgment. The main model arms
    (the main multinomial + the frozen truth composition axis comp_*, the adjudication §3 scenario upgrade) = True;
    the sensitivity arms (nb/clock/sparse) = False — they only refine, they never overturn the judgment, report columns only.

    arms:
      main              the multinomial main arm (the protocol §2.2 main generative model), the master composition, the full grid;
      comp_clock_only   the composition ① (clock-only), the full grid;
      comp_mmr          the composition ③ (the MMR group), the full grid;
      comp_pole         the composition ④ (the POLE hypermutator), the high-N tier POLE_N_SUBSET;
      comp_flat_triple  the composition ⑤ (the flat-triple small exposures), the full grid;
      comp_strong_flat  the composition ⑥ (the strong signature + the flat background), the full grid;
      nb                the NB over-dispersion arm (a must-pick, the adjudication clause 3; size=8, the Gamma-Poisson implementation),
                        the single point N=1000, sensitivity (not entering the judgment);
      clock             the clock-mixing arm (purity=0.4 equivalent), the single point N=1000, sensitivity;
      sparse            the sparse arm (SBS13→2% @ N=1000, the protocol §4), sensitivity.
    """

    name: str
    n_list: tuple
    reps: int
    params: dict = field(default_factory=dict)
    judge: bool = True


def arms_for_profile(profile: str = "primary") -> list:
    """Returns the arm-configuration list of an experiment profile.

    primary: the 6 main model arms (the composition axis) + the 3 sensitivity arms; the full grid 200 reps.
    degraded: the 3-point tier × 100 reps (the protocol §6/§7-R7 degraded tier; the pole composition keeps its
    physically-mandated high-N tier, the sensitivity arms likewise 100 reps).
    smoke: the very small profile for the pipeline self-check (not part of the G0 formal execution, verifying only the harness itself);
    carries one composition arm so as to cover the composition-axis code path.
    """
    if profile == "primary":
        return [
            ArmSpec("main", PRIMARY_GRID, REPS_PRIMARY, {"composition": "master"}),
            ArmSpec("comp_clock_only", PRIMARY_GRID, REPS_PRIMARY,
                    {"composition": "clock_only"}),
            ArmSpec("comp_mmr", PRIMARY_GRID, REPS_PRIMARY, {"composition": "mmr"}),
            ArmSpec("comp_pole", POLE_N_SUBSET, REPS_PRIMARY, {"composition": "pole"}),
            ArmSpec("comp_flat_triple", PRIMARY_GRID, REPS_PRIMARY,
                    {"composition": "flat_triple"}),
            ArmSpec("comp_strong_flat", PRIMARY_GRID, REPS_PRIMARY,
                    {"composition": "strong_flat"}),
            ArmSpec("nb", (SENS_POINT_N,), REPS_PRIMARY, {"nb_size": NB_SIZE},
                    judge=False),
            ArmSpec("clock", (SENS_POINT_N,), REPS_PRIMARY, {"purity": CLOCK_PURITY},
                    judge=False),
            ArmSpec("sparse", (SPARSE_N,), REPS_PRIMARY,
                    {"sparse_signature": SPARSE_SIGNATURE, "sparse_share": SPARSE_SHARE},
                    judge=False),
        ]
    if profile == "degraded":
        return [
            ArmSpec("main", DEGRADED_GRID, REPS_DEGRADED, {"composition": "master"}),
            ArmSpec("comp_clock_only", DEGRADED_GRID, REPS_DEGRADED,
                    {"composition": "clock_only"}),
            ArmSpec("comp_mmr", DEGRADED_GRID, REPS_DEGRADED, {"composition": "mmr"}),
            ArmSpec("comp_pole", POLE_N_SUBSET, REPS_DEGRADED, {"composition": "pole"}),
            ArmSpec("comp_flat_triple", DEGRADED_GRID, REPS_DEGRADED,
                    {"composition": "flat_triple"}),
            ArmSpec("comp_strong_flat", DEGRADED_GRID, REPS_DEGRADED,
                    {"composition": "strong_flat"}),
            ArmSpec("nb", (SENS_POINT_N,), REPS_DEGRADED, {"nb_size": NB_SIZE},
                    judge=False),
            ArmSpec("clock", (SENS_POINT_N,), REPS_DEGRADED, {"purity": CLOCK_PURITY},
                    judge=False),
            ArmSpec("sparse", (SPARSE_N,), REPS_DEGRADED,
                    {"sparse_signature": SPARSE_SIGNATURE, "sparse_share": SPARSE_SHARE},
                    judge=False),
        ]
    if profile == "smoke":
        return [
            ArmSpec("main", (100, 1000), 5, {"composition": "master"}),
            ArmSpec("comp_clock_only", (SENS_POINT_N,), 5, {"composition": "clock_only"}),
            ArmSpec("nb", (SENS_POINT_N,), 5, {"nb_size": NB_SIZE}, judge=False),
        ]
    raise ValueError(f"unknown profile: {profile}")


def all_seed_specs(arms: list) -> list:
    """Expands the arm configurations into the per-(arm, N, rep) SeedSpec list (the row-set of Seeds.txt)."""
    from .seeds import SeedSpec

    specs = []
    for arm in arms:
        for n in arm.n_list:
            for rep in range(arm.reps):
                specs.append(SeedSpec(arm.name, n, rep))
    return specs
