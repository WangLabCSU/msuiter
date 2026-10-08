"""⑦ Seed-derived ground-truth reconstruction (single-ground-truth principle).

Ground truth is BY CONSTRUCTION: the cells ran on msuiter-simulated counts
from the frozen G0 simulator, so the true exposures per sample are the
frozen generation parameters — composition share x N — recovered through
``g0.sim.truth_composition`` read-only (bench/g0 is never modified; the same
read-only ``sys.path`` import the harness run path uses).

The reliability anchor for this module: its ``cell_truth`` must equal the
``truth_h`` the frozen simulator itself emits in ``sim.sample_cell`` for
every profile arm — reconstruction may not drift from the generator.
"""

from __future__ import annotations

from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
for _p in (str(HERE), str(HERE.parent / "g0")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from scoring import truth                            # noqa: E402 (RED seam)
from g0 import grid, sim                             # frozen, read-only
from g0.providers import provider_by_name            # frozen, read-only


def test_master_truth_is_share_times_n():
    """The smoke 'main' arm rides the frozen master composition; true
    exposures at N=1000 are share x N (absolute-counts estimand)."""
    got = truth.cell_truth("smoke", "main", 1000)
    assert got == {"SBS1": 150.0, "SBS2": 150.0, "SBS13": 150.0,
                   "SBS5": 300.0, "SBS40": 250.0}, f"truth drift: {got}"
    assert all(v > 0 for v in got.values()), "truth may only carry present sigs"


def test_reconstruction_matches_the_frozen_generator_for_every_profile_arm():
    """cell_truth(profile, arm, n) must equal sim.sample_cell(...).truth_h
    for every (profile, arm, N) the grid exposes — reconstruction-vs-
    generator agreement on the generator's own output is the drift gate."""
    provider = provider_by_name("synthetic", seed=0)
    for profile in ("smoke", "primary", "degraded"):
        for arm in grid.arms_for_profile(profile):
            for n in arm.n_list:
                cell = sim.sample_cell(provider, arm.name, n, 0, 7,
                                        arm.params)
                want = {k: float(v) for k, v in cell.truth_h.items() if v > 0}
                got = truth.cell_truth(profile, arm.name, n)
                assert got.keys() == want.keys(), \
                    f"{profile}/{arm.name}/N{n}: key drift {got.keys() ^ want.keys()}"
                for k in want:
                    assert abs(got[k] - want[k]) < 1e-9, \
                        f"{profile}/{arm.name}/N{n}/{k}: {got[k]} != {want[k]}"


def test_sparse_arm_truth_carries_the_frozen_sparse_share():
    """The sparse arm re-shares SBS13 to the frozen 2% at N=1000 -> 20
    true counts (G0 §4 boundary behaviour; constants read, never copied)."""
    got = truth.cell_truth("primary", "sparse", grid.SPARSE_N)
    assert abs(got["SBS13"] - grid.SPARSE_SHARE * grid.SPARSE_N) < 1e-9


def test_judge_classification_is_read_from_the_frozen_grid():
    """Primary-model arms decide; sensitivity arms (nb/clock/sparse,
    judge=False) stay report-only columns — the same split the G0 judgment
    document draws (adjudication clause b)."""
    assert truth.arm_is_judge("primary", "main") is True
    assert truth.arm_is_judge("primary", "nb") is False
    assert truth.arm_is_judge("primary", "clock") is False
    assert truth.arm_is_judge("primary", "sparse") is False


def test_unknown_arm_fails_fast_listing_known_arms():
    try:
        truth.cell_truth("smoke", "bogusarm", 1000)
    except ValueError as e:
        assert "main" in str(e), f"error must list the known arms: {e}"
    else:
        raise AssertionError("unknown arm must raise, not return empty truth")


def test_signature_layer_uses_the_frozen_family_table():
    """easy/flat layering for the report columns is read from
    grid.SIGNATURE_FAMILY (D3: no invented constants)."""
    assert truth.signature_layer("SBS5") == "flat"
    assert truth.signature_layer("SBS2") == "easy"
    assert truth.signature_layer("SBS99Z") == ""
