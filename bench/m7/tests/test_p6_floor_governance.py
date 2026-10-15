"""Group (AC) test_p6_floor_governance — no campaign arm may ride ungated.

The RB-09 gate is all-or-nothing per tool (_MEASURED_TOOLS membership): a tool
with zero anchors silently bypasses the gate; a tool with any anchor must carry
one for EVERY protocol class it runs (floor_for raises KeyError otherwise).
Both halves of that trap are law here (task law 3, manifest SS4): every one of
the six P6 campaign tools must arrive in _MEASURED_TOOLS with a complete,
reps-matched, OK-witnessed 21-class anchor set, minted by the pre-ignition
calibration pass under bench/results/m7_floor_calibration_p6_<stamp>/witnesses/.

Until the calibration pass lands (SS4), these units are the load-bearing RED:
they keep any premature ignition from shipping a suite that silently tolerated
ungated arms. measurement_images() must also cover the new images, or the
RB-08(3) co-tenant census would let a rival measurement container slip past.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import p6_arms, registry           # noqa: E402  (RED seam)
import tools.matrix_governance as gov               # noqa: E402

RESULTS = HERE.parent / "results"


def _p6_calibration_dirs():
    return sorted(RESULTS.glob("m7_floor_calibration_p6_*"))


def _grid_classes():
    """The 21 classes: the frozen degraded grid (read-only import, g0 law)."""
    from g0 import grid
    out = []
    for arm in grid.arms_for_profile("degraded"):
        for n in arm.n_list:
            out.append((arm.name, n))
    return out


def test_all_six_p6_tools_are_measured_tools():
    """An arm absent from _MEASURED_TOOLS rides the campaign ungated — the
    silent-skip class task law 3 forbids. RED until SS4 anchors land."""
    missing = [t for t in p6_arms.P6_ARM_SPECS if t not in gov._MEASURED_TOOLS]
    assert not missing, f"P6 campaign tools without floor anchors: {missing}"


def test_p6_anchor_sets_are_complete_not_partial():
    """A partial anchor set is worse than none: floor_for KeyErrors mid-campaign
    AFTER hours of measurement. Completeness is checked pre-ignition, here."""
    classes = _grid_classes()
    assert len(classes) == 21, f"frozen grid shape drifted: {len(classes)} classes"
    problems = []
    for tool in p6_arms.P6_ARM_SPECS:
        for arm, n in classes:
            if (tool, arm, n) not in gov._FLOOR_ANCHORS:
                problems.append(f"{tool}|{arm}|N{n}")
    assert not problems, f"unanchored P6 classes ({len(problems)}): {problems[:8]}"


def test_p6_witnesses_are_reps_matched_ok_and_verbatim():
    """Same scrutiny test_floor_calibration pins for the legacy table —
    extended over the P6 witness dirs (manifest SS4)."""
    dirs = _p6_calibration_dirs()
    if not dirs:
        raise AssertionError(
            "no m7_floor_calibration_p6_* witness dir committed — anchors may "
            "not exist without their bytes (zero-cached/fabrication law)")
    seen = set()
    for d in dirs:
        for w in (d / "witnesses").glob("*__rep100.json"):
            doc = json.loads(w.read_text(encoding="utf-8"))
            tool, arm, ntoken = w.stem.split("__")
            n = int(ntoken[1:])
            seen.add((tool, arm, n))
            assert doc["verdict"] == "OK", f"{w}: verdict {doc['verdict']}"
            assert doc["status_tail"] == "ok", f"{w}: status_tail {doc['status_tail']}"
            argv = doc["argv"]
            assert argv[argv.index("--reps") + 1] == "100", f"{w}: reps echo"
            assert doc["sidecar"]["exit_status"] == 0, f"{w}: child exit"
            key = (tool, arm, n)
            a = gov._FLOOR_ANCHORS[key]
            assert a["reps"] == gov.PROTOCOL_REPS
            assert doc["sidecar"]["cpu_seconds"] == a["cpu_seconds"], key
            assert gov.anchor_witness_path(a).resolve() == w.resolve(), key
    missing = ({(t, arm, n) for t in p6_arms.P6_ARM_SPECS
                for arm, n in _grid_classes()} - seen)
    assert not missing, f"P6 classes without committed witnesses: {sorted(missing)[:6]}"


def test_calibration_ledger_declares_provenance_fields():
    """CALIBRATION.json (schema m7-floor-calibration-1) must exist beside the
    witnesses and carry the explicit-algorithm recorder + registry sha at mint."""
    for d in _p6_calibration_dirs():
        led = json.loads((d / "CALIBRATION.json").read_text(encoding="utf-8"))
        assert led["schema"] == "m7-floor-calibration-1", d
        assert led["hash_recorder"].startswith("python3 hashlib.sha256"), led
        assert led.get("registry_sha256_at_mint"), "registry sha at mint missing"
        assert isinstance(led.get("probes"), int) and led["probes"] > 0


def test_measurement_images_cover_every_ready_p6_arm():
    """RB-08(3): the co-tenant census counts OURS by image ref; a P6 arm
    image outside measurement_images() is an invisible rival container."""
    reg = registry.load()
    ours = set(gov.measurement_images())
    for tool in p6_arms.P6_ARM_SPECS:
        spec = reg[tool]
        if spec.status == "ready":
            assert spec.image_ref in ours, (
                f"{tool}: ready image {spec.image_ref!r} missing from the census")


def test_census_counts_p6_containers_as_ours():
    reg = registry.load()
    ref = reg[next(iter(p6_arms.P6_ARM_SPECS))].image_ref
    live = [{"Image": ref}, {"Image": "postgres:16"}]
    assert gov.measurement_process_count(live) == 1, (
        "P6 measurement containers must count against fan-out=1")
