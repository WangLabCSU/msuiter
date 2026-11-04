"""Group (AL) test_batch_bridge_arm — the batch-bridge parity face pre-registration.

Lane: R1-PARITY Phase-A (design lane card /tmp/r1lane/DESIGN.md). This file is
the TDD RED battery for ONE new, pre-registered m7 arm face that routes the
frozen 4000-fit cell through the certified batch bridge
(`msuiter-kernel fit-kl --cases`, src/rust/engine/src/bin/msuiter-kernel.rs
run_batch + the in-tree R bridge R/kernel-bridge.R / R/kernel-pipeline.R)
instead of one process spawn per fit. Every unit here is either

  * RED-by-absence today — the face, its adapter, its pin, its anchors and
    its witnesses do not exist yet (the house RED idiom: the seam fires, the
    dispatcher prints the traceback, nothing silently passes), or
  * a firing control — the existing gate machinery (register-bridge REFUSE,
    report-side epoch refusal, compose-time digest refusal) is driven with a
    deliberately broken input and MUST bite, proving the battery is not a
    vacuous green (dead-metric law: a test that cannot fail guards nothing).

What the face is (identity law, DESIGN.md §2):
  tool key  sigminer_post_v3_rust_batch
  face      rust_batch                    (argv --backend and arm_pin face,
                                           two sources, one truth)
  lineage   the P0-P3 tip (sigminer_post_v3_rust's tree) + the seam-side
            batch route; the batch tree is a DESCENDANT of the v3 tip, its
            witness is the controller's dated rev-parse attestation, never a
            hand-typed hex (the 2026-10-15 A2 failure mode this file
            inherits the law from).
The frozen six (runners, pins, witnesses, the 147 committed parity rows) are
ZERO-TOUCH: the frozen-runner allowlist units below are the tripwires that
keep it that way.
"""

from __future__ import annotations

import contextlib
import dataclasses
import importlib
import io
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import docker_cmd, p6_arms, registry   # noqa: E402 (RED seams)
from competitors import _p6_common                      # noqa: E402 (RED seam)
import tools.attestation as att                         # noqa: E402
import tools.attestation_sanctions as attestation_sanctions  # noqa: E402
import tools.matrix_governance as gov                   # noqa: E402
from tools import p6_emit_arm_pins                      # noqa: E402
from tests import coex_fixtures as fx                    # noqa: E402

TOOL = "sigminer_post_v3_rust_batch"
FACE = "rust_batch"
BATCH_RUNNER = "run_sigminer_arm_batch.R"
BATCH_SELF_WITNESS = "self_witness_batch_arm.sh"
FROZEN_RUNNER = HERE / "adapters" / "run_sigminer_arm.R"
FROZEN_SELF_WITNESS = HERE / "adapters" / "self_witness_arm.sh"

# The frozen law table, quoted BY VALUE once the controller's dated witness
# lines exist (pre-registration manifest amendment, same ceremony as the (Y)
# group's FROZEN_TREES). Every sentinel below is honest RED: a hand-filled
# fake is impossible because the unit compares the roster against this table,
# and this table only ever moves by a dated witness amendment.
FROZEN_BATCH = {
    "face": FACE,
    "version": "2.3.3",
    "tree_sha": "15b827981dd1a4be28207eb084f78140b70f8f09",
    "ns_sha256": "7d72444f8498635fb3e92b4bc3c29146c2c26b08577567417973832ffc68fea1",
    "lineage_base": "sigminer_post_v3_rust",
    "runner_script": BATCH_RUNNER,
    "self_witness": BATCH_SELF_WITNESS,
}


def _grid_classes():
    """The 21 classes: the frozen degraded grid (read-only g0 import, law
    identical to the (AC) group — this file may only READ the grid)."""
    from g0 import grid
    out = []
    for arm in grid.arms_for_profile("degraded"):
        for n in arm.n_list:
            out.append((arm.name, n))
    return out


# ---------------------------------------------------------------------------
# (Y2) roster / registry identity — the pre-registration itself
# ---------------------------------------------------------------------------

def test_batch_face_key_is_on_the_roster():
    # Arrange / Act
    keys = set(p6_arms.P6_ARM_SPECS)
    # Assert
    assert TOOL in keys, (
        f"{TOOL} is not a pre-registered arm — the seven-key roster is "
        f"{sorted(keys)}")


def test_batch_face_identity_is_the_frozen_quintuple_plus_lineage():
    # Arrange
    spec = p6_arms.P6_ARM_SPECS[TOOL]                    # RED KeyError today
    # Act / Assert — every identity field equals the law table, by value
    for field, want in FROZEN_BATCH.items():
        assert spec.get(field) == want, (
            f"{TOOL}: {field}={spec.get(field)!r} is not the pre-registered "
            f"{want!r} — a re-pin needs its own dated manifest amendment")
    for sentinel in FROZEN_BATCH.values():               # no fake may pass
        assert not str(sentinel).startswith("PENDING-ATTEST"), (
            f"{TOOL}: {sentinel!r} is an unbanked sentinel — the witnessed "
            "tree/ns bytes must arrive via the controller's dated witness")


def test_batch_face_lineage_is_the_v3_tip_a_parent_not_a_forgery():
    # Arrange — read the base from the roster itself, never re-typed
    base = p6_arms.P6_ARM_SPECS[FROZEN_BATCH["lineage_base"]]
    spec = p6_arms.P6_ARM_SPECS[TOOL]                    # RED KeyError today
    # Assert: the batch tree is its OWN tree (never launders the twins'
    # bytes), of the same package generation, and rides the documented
    # twin lineage declared as roster data.
    assert spec["tree_sha"] != base["tree_sha"], (
        f"{TOOL} reuses the {FROZEN_BATCH['lineage_base']} tree — the batch "
        "route is a NEW witnessed commit (its parent lineage is the dated "
        "rev-parse attestation, banked at pre-registration)")
    assert spec["version"] == base["version"] == "2.3.3"


def test_child_argv_routes_the_batch_face_to_its_own_runner_fork():
    # Arrange / Act
    argv = _p6_common.child_argv(TOOL, None)             # RED KeyError today
    # Assert: own runner path (never the frozen six's), the face token
    # forwarded verbatim as the LAST pair, frozen required flags present,
    # zero tuning levers.
    assert f"/work/{BATCH_RUNNER}" in argv[1], (
        f"{TOOL} must ride the runner fork /work/{BATCH_RUNNER}, not the "
        "frozen run_sigminer_arm.R")
    assert argv[-2:] == ["--backend", FACE], (
        f"argv tail {argv[-2:]!r} does not speak the two-source truth "
        f"--backend {FACE}")
    for flag in ("--counts", "--catalog", "--params", "--outdir"):
        assert flag in argv, f"argv lost the frozen cell flag {flag}"
    joined = " ".join(argv)
    for token in ("--threshold", "--rank", "--nrun", "--iters", "--seed="):
        assert token not in joined, f"forbidden tuning token {token!r}"


def test_frozen_six_surfaces_never_speak_the_new_face():
    """Anti-laundering tripwire (GREEN today, must STAY green): the frozen
    runner's --backend allowlist and the frozen self-witness's case guard
    remain exactly {R, rust}; the new face reaches the world only through its
    own forked bytes. If a future change widens a frozen allowlist instead of
    forking, this unit reddens the lane."""
    # Arrange
    runner = FROZEN_RUNNER.read_text(encoding="utf-8")
    witness = FROZEN_SELF_WITNESS.read_text(encoding="utf-8")
    # Assert
    assert 'c("R", "rust")' in runner, (
        "frozen run_sigminer_arm.R allowlist moved — the 147 sealed rows are "
        "measured through those exact bytes")
    assert "R|rust)" in witness, "frozen self_witness_arm.sh guard moved"
    for blob in (runner, witness):
        assert TOOL not in blob and FACE not in blob, (
            "the new face leaked into a frozen surface")


def test_arm_pin_mirrors_the_roster():
    # Arrange — the emitter is the single source; hand-edited bytes are the
    # A2 failure mode (test_p6_roster law, extended here for the new face).
    from tools import p6_emit_arm_pins as emitter
    committed = HERE / "adapters" / "arm_pins" / f"{TOOL}.json"
    # Act / Assert
    assert committed.exists(), f"missing committed arm pin {committed}"
    assert committed.read_text(encoding="utf-8") == emitter.pin_text(TOOL), (
        f"{TOOL}: committed arm pin drifts from the roster — regenerate via "
        "tools/p6_emit_arm_pins.py, never hand-edit")


def test_registry_row_mints_pre_flip_safe():
    # Arrange
    reg = registry.load()
    row = reg[TOOL]                                      # RED KeyError today
    # Assert
    assert row.runtime == "R", "the R family owns the parity predicate"
    assert row.face == FACE, "the registry face column must echo the roster"
    assert row.image_ref == p6_arms.image_tag(
        TOOL, p6_arms.P6_ARM_SPECS[TOOL].get("revision", 1)), (
        f"{TOOL}: image tag {row.image_ref!r} does not follow the "
        f"{p6_arms.ARM_IMAGE_PREFIX}:p6-<tool>-r<N> law")
    if row.status == "pending-verify":
        reason = docker_cmd.image_gate(row)
        assert reason is not None and ("PENDING-VERIFY" in reason
                                        or "provenance" in reason), (
        "an unattested row must be compose-time refused, skip-not-skip")
    else:
        assert docker_cmd.image_gate(row) is None, (
            "a flipped row must carry an inspect-attested digest")


def test_batch_face_adapter_module_serves_the_shared_contract():
    """RED-by-absence: the thin shim over _p6_common must expose the Z-group
    surface (run + _child_argv) exactly like the six siblings."""
    # Arrange / Act
    try:
        mod = importlib.import_module(f"competitors.{TOOL}_adapter")
    except ModuleNotFoundError as exc:
        raise AssertionError(
            f"RED-by-absence: competitors/{TOOL}_adapter.py is not in tree "
            f"({exc})") from None
    # Assert
    for attr in ("run", "_child_argv"):
        assert callable(getattr(mod, attr, None)), f"{TOOL}_adapter.{attr}"
    assert mod.TOOL == TOOL and mod.FACE == FACE


# ---------------------------------------------------------------------------
# (AC2) floor governance — the new face may not ride ungated
# ---------------------------------------------------------------------------

def test_batch_face_joins_the_measured_tools():
    """RB-09 all-or-nothing per tool: a campaign arm in the roster but not
    in _MEASURED_TOOLS would silently bypass the floor gate."""
    # Arrange / Act
    missing = TOOL not in gov._MEASURED_TOOLS
    # Assert
    assert not missing, (
        f"{TOOL} rides the campaign ungated — 21 REP-100 anchors are "
        "prerequisite (minter --only route, then the register bridge)")


def test_batch_face_anchor_set_is_complete_not_partial():
    # Arrange
    classes = _grid_classes()
    assert len(classes) == 21, "frozen grid shape drifted"
    # Act
    holes = [f"{TOOL}|{arm}|N{n}" for arm, n in classes
             if (TOOL, arm, n) not in gov._FLOOR_ANCHORS]
    # Assert
    assert not holes, (
        f"partial anchor set is worse than none (floor_for KeyErrors "
        f"mid-campaign): {holes[:5]}")


def test_batch_face_anchors_are_sidecar_backed_post_cap_bytes():
    """An anchor figure exists only because a committed witness sidecar
    speaks it: re-read every byte (the register bridge's own verification
    re-enforced from the reader side)."""
    # Arrange
    classes = _grid_classes()
    problems = []
    # Act / Assert
    for arm, n in classes:
        key = (TOOL, arm, n)
        if key not in gov._FLOOR_ANCHORS:
            problems.append(f"{key}: no anchor")
            continue
        anchor = gov._FLOOR_ANCHORS[key]
        caldir = anchor["witness"][0]
        assert caldir.startswith(gov.POST_CAP_AUTHORITY_PREFIX) and not \
            caldir.startswith(gov.POST_CAP_LEGACY_PREFIX), (
            f"{key}: anchors must ride post-cap authority bytes")
        path = gov.anchor_witness_path(anchor)
        if not path.is_file():
            problems.append(f"{key}: witness {path} not on disk")
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        argv = doc.get("argv", [])
        echo = (argv[argv.index("--reps") + 1]
                if "--reps" in argv else None)
        if echo != str(gov.PROTOCOL_REPS) or doc.get("reps") != gov.PROTOCOL_REPS:
            problems.append(f"{key}: reps echo {echo!r}")
        side = doc.get("sidecar", {})
        if side.get("cpu_seconds") != anchor["cpu_seconds"] \
                or doc.get("wall_seconds") != anchor["wall_seconds"]:
            problems.append(f"{key}: table bytes drifted from the sidecar")
    assert not problems, f"anchor backing problems: {problems[:6]}"


def test_batch_face_witnesses_speak_the_final_table_epoch():
    """The epoch-collision guard (DESIGN.md §5): a minted-under-E0 witness
    must never be committed after the table moved to E1. The batch face's
    witnesses are admissible ONLY while their attestation epoch equals the
    live floor_table_epoch — this is what forces the fixed-point mint order
    (or the controller's sanctioned re-adjudication device) at GREEN time.

    The dual-face law (Phase-D Instrument B, controller ruling 2026-11-04
    (2)) rides the same sweep: every batch-face witness speaks ONE face —
    the lv1 block, or an explicitly sanctioned null label from
    tools/attestation_sanctions — never both, never an unsanctioned
    orphan."""
    # Arrange
    classes = _grid_classes()
    stale = []
    # Act / Assert
    for arm, n in classes:
        anchor = gov._FLOOR_ANCHORS.get((TOOL, arm, n))
        if anchor is None:
            stale.append(f"{TOOL}|{arm}|N{n}: no anchor")
            continue
        doc = json.loads(gov.anchor_witness_path(anchor).read_text(
            encoding="utf-8"))
        refusal = att.reportability(doc, gov.floor_table_epoch())
        if refusal is not None:
            stale.append(f"{TOOL}|{arm}|N{n}: {refusal}")
            continue
        face = attestation_sanctions.dual_face_ok(doc)
        if face is not None:
            stale.append(f"{TOOL}|{arm}|N{n}: {face}")
    assert not stale, f"epoch-collision victims: {stale[:4]}"


def test_batch_face_reaches_the_parity_instrument_as_eighth_r_face():
    """The parity census is derived (faces x 21); the new face must arrive
    through the same derivation — never by editing the instrument."""
    # Arrange
    r_faces = [t for t in gov._MEASURED_TOOLS
               if t != "sigprofiler" and registry.load()[t].runtime == "R"]
    # Assert
    assert TOOL in r_faces, f"{TOOL} does not reach parity_recompute"
    assert len(r_faces) == 8, f"expected 8 R faces, {len(r_faces)}: {r_faces}"


# ---------------------------------------------------------------------------
# (AA2) bit-identity vs the spawn face — the face is a transport change
# ---------------------------------------------------------------------------

def test_bit_identity_comparator_surface_exists_and_bites():
    """RED-by-absence: tools/batch_bridge_bit_identity must exist and
    compare the adapter-protocol outputs (intervals.csv, spectra.csv) of one
    staged cell run through both faces, BYTE-EXACT, naming the offending
    file. The bridge may change who calls the kernel and when — never the
    committed bytes (the P10 cross-route bit-identity law, 476+346
    expectations, is the in-tree precedent this comparator extends to the
    arm face)."""
    # Arrange / Act
    try:
        mod = importlib.import_module("tools.batch_bridge_bit_identity")
    except ModuleNotFoundError as exc:
        raise AssertionError(
            "RED-by-absence: tools/batch_bridge_bit_identity.py is not in "
            f"tree ({exc})") from None
    compare = getattr(mod, "compare_cell", None)
    assert callable(compare), "comparator lacks compare_cell(batch, spawn)"
    # Assert — firing controls on synthetic bytes (the gate must bite)
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for side in ("batch", "spawn"):
            d = root / side
            d.mkdir()
            (d / "intervals.csv").write_bytes(b"sample_id,signature,x\ns1,S1,1\n")
            (d / "spectra.csv").write_bytes(b"signature,channel,value\nS1,c,1\n")
        assert compare(root / "batch", root / "spawn") is None
        (root / "batch" / "spectra.csv").write_bytes(b"signature,channel,value\nS1,c,2\n")
        try:
            compare(root / "batch", root / "spawn")
        except (AssertionError, ValueError) as exc:
            assert "spectra.csv" in str(exc), (
                f"the bite must name the file: {exc}")
        else:
            raise AssertionError("tampered spectra sailed through — vacuous")
        (root / "spawn" / "intervals.csv").unlink()
        try:
            compare(root / "batch", root / "spawn")
        except (AssertionError, ValueError, OSError) as exc:
            assert "intervals.csv" in str(exc), f"missing-file bite must name it: {exc}"
        else:
            raise AssertionError("missing file sailed through — vacuous")


# ---------------------------------------------------------------------------
# firing controls on the EXISTING gates (anti-vacuous battery, green today)
# ---------------------------------------------------------------------------

def test_control_lying_fragment_refuses_registration():
    """The register bridge is the only sanctioned table author — prove it
    refuses an unbacked witness pointer, and stays byte-sterile doing so."""
    # Arrange
    from tools import register_p6_anchors as reg
    gov_src = HERE / "tools" / "matrix_governance.py"
    before = gov_src.read_bytes()
    with tempfile.TemporaryDirectory() as td:
        caldir = "m7_floor_calibration_p7cap_control"
        (Path(td) / caldir / "witnesses").mkdir(parents=True)
        (Path(td) / caldir / "anchors_fragment.json").write_text(json.dumps({
            f"{TOOL}|main|N1000": {"witness": (caldir, "witnesses",
                                              "ghost__main__N1000__rep100.json"),
                                   "reps": 100, "cpu_seconds": 1.0,
                                   "wall_seconds": 1.0}},
            sort_keys=True), encoding="utf-8")
        # Act
        res = reg.register(gov_source=gov_src, results_dir=Path(td),
                           caldir=caldir)
        # Assert
        assert res["verdict"] == "REFUSE" and res["count"] == 0, res
        assert any("not on disk" in r for r in res["refusals"]), res["refusals"]
        assert gov_src.read_bytes() == before, "REFUSE was not byte-sterile"


def test_control_stale_epoch_attestation_is_not_reportable():
    """The report-side epoch trap bites: a well-formed lv1 attestation
    carrying a stale epoch is history, not a measurement.

    Phase-D reseed (A-extension rider): the embedded coex block is now
    held to the mint teeth at the report face too — the block is the
    rig-sealed face, so the refusal this unit sees is the EPOCH face
    speaking, which is the law this keeper exists to name."""
    # Arrange
    live = gov.floor_table_epoch()
    doc_stale = {"attestation": {
        "law": att.ATTEST_LAW, "preflight": {"decision": "GO"},
        "coex_probe": fx.rig_record(), "epoch": "0" * len(live)}}
    # Act
    refusal = att.reportability(doc_stale, live)
    ok = att.reportability({"attestation": {
        "law": att.ATTEST_LAW, "preflight": {"decision": "GO"},
        "coex_probe": fx.rig_record(), "epoch": live}}, live)
    # Assert
    assert refusal is not None and "epoch" in refusal, "stale stamp passed"
    assert ok is None, "a fresh honest stamp must be reportable"


def test_control_malformed_digest_is_refused_pre_daemon():
    """Compose-time law for the future flip: a 63-hex digest never reaches
    the daemon (registry mints ready only on 71-char sha256+64hex)."""
    # Arrange
    row = registry.lookup("sigminer_post_v3_rust")
    bad = dataclasses.replace(row, image_digest="sha256:" + "0" * 63)
    # Act / Assert
    assert docker_cmd.image_gate(bad) is not None, (
        "malformed digest must be refused before the daemon is asked")


def test_parity_instrument_baseline_still_completes():
    """Today's sealed census (147 rows, exit 0) is the baseline the GREEN
    phase must preserve while it grows to 168 — the recompute is read-only
    over the committed witnesses, so this unit doubles as a no-contamination
    tripwire for this very lane."""
    # Arrange
    from tools import parity_recompute as pr
    buf = io.StringIO()
    # Act
    with contextlib.redirect_stdout(buf):
        rc = pr.main()
    lines = [ln for ln in buf.getvalue().splitlines() if " cpu-basis ratio=" in ln]
    # Assert
    assert rc == 0, f"parity_recompute rc={rc}"
    faces = {ln.split()[0] for ln in lines}
    assert len(lines) == 21 * len(faces), (
        f"census is not faces x 21: {len(lines)} rows, {len(faces)} faces")
    assert len(faces) >= 7, f"R-face census shrunk: {sorted(faces)}"
