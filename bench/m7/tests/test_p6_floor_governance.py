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

import hashlib
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
    """RB-10 re-point: the authority bytes are the post-cap mint dirs. The
    pre-cap p6_* dirs stay committed as frozen provenance but no longer
    feed the gate's law — only p7cap_* bytes may anchor the table."""
    return sorted(RESULTS.glob(gov.POST_CAP_AUTHORITY_PREFIX + "*"))


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
            "no m7_floor_calibration_p7cap_* witness dir committed — anchors may "
            "not exist without their bytes (zero-cached/fabrication law)")
    seen = set()
    for d in dirs:
        for w in (d / "witnesses").glob("*__rep100.json"):
            doc = json.loads(w.read_text(encoding="utf-8"))
            # Stems speak tool__arm__N<n>__rep100 (the calibrator's naming
            # law): the rep token is part of the filename contract, not a
            # parseable-free remainder.
            parts = w.stem.split("__")
            assert len(parts) == 4 and parts[3] == "rep100", f"{w}: stem"
            tool, arm, ntoken = parts[:3]
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
    witnesses and carry the explicit-algorithm recorder + registry sha at mint.
    probes > 0 is the RB-10 (AC) edge: a resume pass that verified bytes without
    declaring its mint's probes speaks probes=0 and must not pass the ledger."""
    dirs = _p6_calibration_dirs()
    if not dirs:
        raise AssertionError(
            "no post-cap authority dir committed — a ledger cannot certify nothing")
    for d in dirs:
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
    """Post-flip law: a live container riding a READY arm's tag counts against
    fan-out=1. Pre-flip the arm has no attested image, so the law binds its
    ready members only (asserted per flip by the same unit)."""
    reg = registry.load()
    ready = [t for t in p6_arms.P6_ARM_SPECS if reg[t].status == "ready"]
    if not ready:
        return
    ref = reg[ready[0]].image_ref
    live = [{"Image": ref}, {"Image": "postgres:16"}]
    assert gov.measurement_process_count(live) == 1, (
        "P6 measurement containers must count against fan-out=1")


# -- RB-10 post-cap authority law --------------------------------------------------
# The table may ride post-cap witnesses only: bytes minted after the fork-axis
# caps went live (main@2e689cd). These units are the RB-09-style TDD red; they
# stay red until the p7cap mint, the register bridge and the ledger
# attestation land, and they keep biting afterwards (counterfactual-tested).

PRECAP_SEALED_EPOCH = "6b3a66bc9d0224eb"      # measured before the flip
POST_CAP_EPOCH_PIN = "f3e894a6933a2ffb"   # measured; set at the ADJ-O3 GREEN commit


def _authority_dirs(*, legacy: bool) -> list[Path]:
    """The two authority halves carved by prefix. The legacy prefix extends
    the campaign one, so the campaign listing must exclude legacy members."""
    prefix = (gov.POST_CAP_LEGACY_PREFIX if legacy
              else gov.POST_CAP_AUTHORITY_PREFIX)
    dirs = sorted(RESULTS.glob(prefix + "*"))
    if not legacy:
        dirs = [d for d in dirs
                if not d.name.startswith(gov.POST_CAP_LEGACY_PREFIX)]
    return dirs


def test_post_cap_authority_dirs_are_committed():
    """Both authority halves must exist as committed dirs: the campaign mint
    (6 tools x 21 classes) and the legacy re-mint (60 classes). RED until
    the RB-10 mints complete."""
    assert _authority_dirs(legacy=False), (
        "no m7_floor_calibration_p7cap_<stamp> campaign authority dir")
    assert _authority_dirs(legacy=True), (
        "no m7_floor_calibration_p7cap_legacy_<stamp> legacy-domain "
        "authority dir")


GEOMETRY_BAND = (1.5, 2.5)        # GATE-1 fan-out band (the probe-gate law)
GEOMETRY_PARITY_TOL = 0.25        # |post/frozen - 1| on the cpu/wall parity


def _compiled_family(tool: str) -> bool:
    """Pinned registry taxonomy, the probe gates' single source (A-prime: no
    new name table): the R family is cap-honoring; any other runtime is a
    compiled competitor whose shape law is frozen-parity geometry."""
    return registry.lookup(tool).runtime != "R"


def _profile_fails(tool: str, doc: dict, frozen: dict | None) -> list[str]:
    """ADJ-O3-SERIAL-PRONG-SCOPE-1 (A-prime): R family rides the absolute
    serial prong VERBATIM (the cap-honoring attestation; the pre-cap frozen
    profile never speaks to it); compiled non-R competitors ride the
    frozen-parity geometry attestation of ADJ-O2-SIGPROF-GATE-1/1b INSTEAD --
    mirroring the sanctioned probe-gate split (run_probe_leg._class_gates),
    one law per physics. Silence never passes: every prong speaks a fail."""
    pcpu = (doc.get("sidecar") or {}).get("cpu_seconds")
    pwall = doc.get("wall_seconds")
    try:
        compiled = _compiled_family(tool)
    except Exception as exc:
        return [f"tool {tool!r} absent from the pinned registry taxonomy: {exc}"]
    if not compiled:
        if not (isinstance(pcpu, (int, float)) and pcpu > 0
                and isinstance(pwall, (int, float)) and pwall > 0):
            return [f"zero-time/absent witness: wall={pwall} cpu={pcpu}"]
        dev = abs(pwall - pcpu) / max(pwall, pcpu)
        if dev > gov.POST_CAP_WALL_CPU_TOL:
            return [f"fan-live bytes in a cap-honoring class: wall={pwall} "
                    f"cpu={pcpu} dev={dev:.3f} > {gov.POST_CAP_WALL_CPU_TOL}"]
        return []
    fails: list[str] = []
    digest = (doc.get("provenance") or {}).get("image_digest", "")
    want = registry.lookup(tool).image_digest
    if not want:
        fails.append("no pinned image digest on record to attest")
    elif digest != want:
        fails.append(f"image digest not pinned-invariant: {digest!r} != {want!r}")
    if frozen is None:
        return fails + ["frozen same-class witness absent: parity cannot attest"]
    fcpu = (frozen.get("sidecar") or {}).get("cpu_seconds")
    fwall = frozen.get("wall_seconds")
    if not all(isinstance(x, (int, float)) and x > 0
               for x in (pcpu, pwall, fcpu, fwall)):
        return fails + ["geometry parity inputs not numeric positive"]
    pr = pcpu / pwall
    fr = fcpu / fwall
    band_live = GEOMETRY_BAND[0] <= fr <= GEOMETRY_BAND[1]
    if band_live and not (GEOMETRY_BAND[0] <= pr <= GEOMETRY_BAND[1]):
        fails.append(f"post cpu/wall {pr:.4f} outside fan-out band "
                     f"{GEOMETRY_BAND} (frozen {fr:.4f} in-band)")
    elif abs(pr / fr - 1.0) > GEOMETRY_PARITY_TOL:
        fails.append(f"fan-out parity drift: post {pr:.4f} vs frozen {fr:.4f} "
                     f"beyond tol {GEOMETRY_PARITY_TOL}")
    return fails


def test_post_cap_witnesses_speak_the_serial_chain_profile():
    """(AC) post-cap authority profile law, family-scoped per
    ADJ-O3-SERIAL-PRONG-SCOPE-1 (2026-10-27T22:55Z): R family absolute
    serial prong verbatim; compiled competitors frozen-parity geometry
    instead. A missing frozen byte or an unclassifiable tool refuses."""
    scanned = 0
    frozen_root = RESULTS / "m7_floor_calibration_20261009" / "witnesses"
    for legacy in (False, True):
        for d in _authority_dirs(legacy=legacy):
            for w in sorted((d / "witnesses").glob("*.json")):
                doc = json.loads(w.read_text(encoding="utf-8"))
                assert doc["verdict"] == "OK", f"{w.name}: verdict {doc['verdict']}"
                assert doc["status_tail"] == "ok", f"{w.name}: {doc['status_tail']}"
                fpath = frozen_root / w.name
                frozen = (json.loads(fpath.read_text(encoding="utf-8"))
                         if fpath.is_file() else None)
                fails = _profile_fails(w.stem.split("__")[0], doc, frozen)
                assert not fails, f"{d.name}/{w.name}: {'; '.join(fails)}"
                scanned += 1
    assert scanned > 0, "post-cap authorities scanned zero witnesses"


def test_post_cap_authority_covers_the_full_registry_domain():
    """Every governed class needs post-cap bytes: the 126 campaign stems
    (6 tools x the frozen 21-class grid) in the campaign authority, the 60
    legacy stems (defined by the frozen 20261009 dir: 42 grid + 18 ladder)
    in the legacy authority. A missing stem is an unmeasured class riding
    stale bytes; a stray stem is bytes nobody governed."""
    expected_main = {
        f"{t}__{arm}__N{n}__rep{gov.PROTOCOL_REPS}.json"
        for t in p6_arms.P6_ARM_SPECS for arm, n in _grid_classes()}
    assert len(expected_main) == 126, f"campaign domain drifted: {len(expected_main)}"
    present_main: set[str] = set()
    for d in _authority_dirs(legacy=False):
        present_main |= {w.name for w in (d / "witnesses").glob("*.json")}
    frozen = RESULTS / "m7_floor_calibration_20261009" / "witnesses"
    expected_legacy = {w.name for w in frozen.glob("*.json")}
    assert len(expected_legacy) == 60, f"legacy domain drifted: {len(expected_legacy)}"
    present_legacy: set[str] = set()
    for d in _authority_dirs(legacy=True):
        present_legacy |= {w.name for w in (d / "witnesses").glob("*.json")}
    assert present_main == expected_main, (
        f"campaign authority mismatch: missing="
        f"{sorted(expected_main - present_main)[:4]!r} "
        f"stray={sorted(present_main - expected_main)[:4]!r}")
    assert present_legacy == expected_legacy, (
        f"legacy authority mismatch: missing="
        f"{sorted(expected_legacy - present_legacy)[:4]!r} "
        f"stray={sorted(present_legacy - expected_legacy)[:4]!r}")


def test_post_cap_ledgers_digest_every_committed_witness():
    """CALIBRATION.witness_sha256 is the revalidation map: every committed
    witness byte-for-byte, no more no less. A resume pass that forgot to
    re-hash a kept file, or a byte that drifted under the map, fails here."""
    revalidated = 0
    for legacy in (False, True):
        for d in _authority_dirs(legacy=legacy):
            led = json.loads((d / "CALIBRATION.json").read_text(encoding="utf-8"))
            wmap = led["witness_sha256"]
            committed = {w.name for w in (d / "witnesses").glob("*.json")}
            assert set(wmap) == committed, (
                f"{d.name}: ledger-map drift only-ledger="
                f"{sorted(set(wmap) - committed)[:4]!r} "
                f"only-disk={sorted(committed - set(wmap))[:4]!r}")
            for name, want in wmap.items():
                have = hashlib.sha256(
                    (d / "witnesses" / name).read_bytes()).hexdigest()
                assert have == want, f"{d.name}/{name}: digest drift"
                revalidated += 1
    assert revalidated > 0, "post-cap ledgers revalidated zero digests"


def test_post_cap_epoch_moved_off_the_precap_seal():
    """The table epoch is a content hash over the committed anchors; the
    pre-cap bytes sealed 6b3a66bc9d0224eb. A re-anchor that did not move it
    means the table still rides fan-live witnesses."""
    epoch = gov.floor_table_epoch()
    assert epoch != PRECAP_SEALED_EPOCH, (
        "floor table still sealed over pre-cap bytes — RB-10 re-anchor pending")


def test_post_cap_epoch_sealed_pin():
    """The sealed pin carries the MEASURED epoch of the post-cap table (the
    canonical form floor_table_epoch speaks). The sentinel is the honest RED;
    the GREEN commit records the measured value, and the seal may never pin
    back onto the pre-cap epoch."""
    assert POST_CAP_EPOCH_PIN != PRECAP_SEALED_EPOCH, (
        "post-cap seal may not pin back onto the pre-cap epoch")
    assert gov.floor_table_epoch() == POST_CAP_EPOCH_PIN, (
        f"floor_table_epoch={gov.floor_table_epoch()!r} != sealed pin "
        f"{POST_CAP_EPOCH_PIN!r} (measured value lands here at GREEN)")


def test_minter_attestation_rejects_underspoken_declared():
    """RED-by-absence (the harness idiom): the minter's --probes-declared
    attestation must validate the declared count against the booked ledger
    rows of its own dir. A resume pass declaring more probes than budget.tsv
    speaks is a hand-written ledger in disguise -- it must be refused."""
    from tools import calibrate_p6_floors as minter
    validate = getattr(minter, "_validate_declared_probes", None)
    assert callable(validate), (
        "minter lacks the _validate_declared_probes attestation validator "
        "(RED-by-absence until the GREEN wave adds --probes-declared)")
    import tempfile
    rows = ["probe\tstart\tend\twall\tshape\tscript\tlog\tstatus\n"]
    rows += [f"p{i}\ta\tb\t60\tmint/{'DIR'}/x|y|N1@rep100\ts\tl\tDONE\n"
             for i in range(3)]
    with tempfile.TemporaryDirectory() as td:
        led = Path(td) / "budget.tsv"
        led.write_text("\n".join(rows) + "\n", encoding="utf-8")
        assert validate(led, "DIR", 3) == 3, "honest declaration must pass"
        try:
            validate(led, "DIR", 5)
        except AssertionError:
            pass                                   # the bite: over-declared
        else:
            raise AssertionError("over-declared attestation was accepted")
