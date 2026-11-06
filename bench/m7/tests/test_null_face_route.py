"""Group (B) test_null_face_route — the sanctioned no-stamp route on the
minter (Phase-D Instrument B, controller ruling 2026-11-04 (2)).

The batch-bridge arm mints its comparison-base witnesses without the
co-tenancy attestation, because the face it rides is the same face as the
147-row comparison base. The ruling converts that from folklore into a
data-gated opt-out:

  * the minter speaks --attestation=live|none-with-reason and
    --null-face-reason; nothing defaults into the null face -- forgetting
    the flag DEFECTS loudly, it never silently un-attests;
  * the reason is a KEY into tools/attestation_sanctions.SANCTIONED_NULL_FACES
    -- controller ruling data, not a lane option: an unsanctioned key is a
    pre-daemon refusal;
  * the null face is EXPLICIT ("attestation": null plus a label block),
    never the pre-law hand-written face; reportability and the printed row
    are identical to the key-absent face (measured, pinned by B3), so the
    opt-out grants no reportability upgrade -- null was already admissible;
  * the stamp internals are byte-frozen: the null route is a separate
    branch at the :232 call site (the A11 keeper in test_coex_producer_law
    pins the frozen face); the ledger records the mode and the sanction.

The runner face arrives stubbed (zero containers): run_bench.main is
replaced by a face that writes the four cell outputs, a valid timing
sidecar and an 'ok' timings row -- the same face the (L) live units
exercise, driven to the probe instead of through the daemon.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import run_bench                                        # noqa: E402
import tools.attestation as att                         # noqa: E402
import tools.attestation_sanctions as sanc              # noqa: E402
import tools.calibrate_p6_floors as cal                 # noqa: E402
from competitors import registry                         # noqa: E402
from tools import probe_sigminer_cell_argv as probe     # noqa: E402
from tests import coex_fixtures as fx                   # noqa: E402

TOOL = "sigminer_post_v3_rust_batch"
ARM = "main"
N = 1000
REPS = 100
CAMPAIGN = "m7_floor_calibration_p7cap_batch_bridge_b_law"
SANCTION_KEY = TOOL                                # the ruling is per face
LIVE_TOOL = "sigminer"        # a READY row with a real digest (the batch
                              # row is PENDING-VERIFY pre-flip by design)


def _cachedir(tmp: Path, tool: str) -> Path:
    """Mirror of the probe's scratch naming (probe_sigminer_cell_argv
    run_probe): the staged preflight/coex faces must sit where the stamp
    will look."""
    h = hashlib.sha256(f"{tool}|{ARM}|{N}|{REPS}".encode()).hexdigest()[:8]
    return tmp / f"probe_{h}" / "probe_cache"


class _StubBench:
    """run_bench.main as a pure-filesystem face: it writes the four cell
    outputs, a valid timing sidecar and an 'ok' timings row under the
    argv's --cachedir. Zero containers, zero daemons."""

    def __init__(self):
        self.calls = []

    def __call__(self, argv):
        self.calls.append(list(argv))
        tok = dict(zip(argv, argv[1:]))
        cachedir = Path(tok["--cachedir"])
        cell = f"{tok['--competitors']}__{tok['--arms']}__N{tok['--n-list']}"
        out = cachedir / "cells" / cell / "out"
        out.mkdir(parents=True, exist_ok=True)
        (out / "intervals.csv").write_text(
            "msuiter_start,msuiter_end,mutation_id,strand,sequence_line\n")
        (out / "errors.log").write_text("")
        (out / "manifest.json").write_text("{}\n")
        (out / "timing.json").write_text(json.dumps(
            {"ru_utime": 50.0, "ru_stime": 10.0, "cpu_seconds": 60.0,
             "exit_status": 0}, sort_keys=True) + "\n")
        oc = cachedir / "out"
        oc.mkdir(parents=True, exist_ok=True)
        (oc / "timings_m7_stub.csv").write_text(
            "cell,a,b,c,d,e,status\n" + f"{cell},1,2,3,4,5,ok\n")
        return 0

    def __enter__(self):
        self._saved = run_bench.main
        run_bench.main = self
        return self

    def __exit__(self, *exc):
        run_bench.main = self._saved


def _tmp():
    return Path(tempfile.mkdtemp(prefix="null_face_"))


def _stage_probe_face(tmp: Path, *, tool: str, coex: bool):
    """The mint-time faces under the probe's cachedir: preflight GO always
    (so the coex face is the variable), the rig record + ledger only for
    the live route."""
    cdir = _cachedir(tmp, tool)
    fx.preflight_log(cdir, cell=f"{tool}__{ARM}__N{N}")
    if coex:
        row = registry.lookup(tool)
        # the record must be bound to the very face the mint will present:
        # the registry row's image bytes and THIS campaign (T5 equalities)
        fx.stage(cdir, book=True, campaign=CAMPAIGN,
                 tool=tool, arm=ARM, n=N, reps=REPS,
                 image={"ref": row.image_ref, "digest": row.image_digest})
        os.environ[att.COEX_ENV] = str(cdir / "coex.json")
    else:
        os.environ.pop(att.COEX_ENV, None)


def _drive_probe(tmp: Path, *, tool: str = TOOL, **kw):
    """One run_probe leg over the stubbed runner face; returns (rc, doc)."""
    _stage_probe_face(tmp, tool=tool, coex=kw.get("stage_coex", False))
    with _StubBench():
        code = probe.run_probe(tool, arm=ARM, n=N, reps=REPS,
                               json_path=str(tmp / "w.json"), work=str(tmp),
                               campaign=kw.get("campaign", CAMPAIGN),
                               live_probe=fx.fake_live_probe(),
                               attestation=kw.get("attestation", "live"),
                               null_face_reason=kw.get("null_face_reason"))
    doc = (json.loads((tmp / "w.json").read_text(encoding="utf-8"))
           if (tmp / "w.json").is_file() else None)
    return code, doc


# ---------------------------------------------------------------------------
# the routing law at the :232 call site
# ---------------------------------------------------------------------------

def test_live_route_still_mints_lv1():
    """The default face is unchanged: preflight GO + rig-emitted coex face
    => the lv1 block rides the witness bytes. (Driven on the READY sigminer
    row: the batch row's digest is PENDING-VERIFY until the arm flips.)"""
    # Arrange
    tmp = _tmp()
    # Act
    code, doc = _drive_probe(tmp, tool=LIVE_TOOL, stage_coex=True)
    # Assert — the honest leg
    assert code == 0, f"the live route must mint, not defect: {doc}"
    assert doc["attestation"]["law"] == att.ATTEST_LAW
    assert doc["attestation"]["coex_probe"]["verdict"] == "NOT-FLAT"
    # Assert — firing control: the same route without the coex face DEFECTs
    code2, doc2 = _drive_probe(_tmp(), tool=LIVE_TOOL, stage_coex=False)
    assert code2 == 1 and doc2["verdict"] == "DEFECT" \
        and "coex inversion-probe record absent" in doc2["reason"], \
        f"the live default lost its teeth: {doc2}"


def test_sanctioned_null_route_mints_the_labelled_null_face():
    """The sanctioned opt-out mints: explicit null, label block, ruling
    named. The witness speaks WHAT it is on its own face."""
    # Arrange
    tmp = _tmp()
    # Act
    code, doc = _drive_probe(tmp, attestation="none-with-reason",
                             null_face_reason=SANCTION_KEY)
    # Assert
    assert code == 0, f"the sanctioned route must mint: {doc}"
    assert "attestation" in doc and doc["attestation"] is None, \
        "the null face is EXPLICIT — not the pre-law key-absent hand-written face"
    label = doc[att.NULL_FACE_KEY]
    assert label["reason"] == SANCTION_KEY and label["ruling"], label
    # Assert — firing control: the key resolves in the ruling registry
    assert sanc.sanction_ok(SANCTION_KEY) is not None, "the sanction vanished"


def test_null_face_is_reportability_identical_to_pre_law():
    """The measured equality that keeps the opt-out honest: null and
    key-absent both sail, both print pre-law; the opt-out upgrades nothing
    (null was already admissible under the parity law)."""
    # Arrange
    _, doc_null = _drive_probe(_tmp(), attestation="none-with-reason",
                               null_face_reason=SANCTION_KEY)
    committed = {"verdict": "OK"}                       # the 375 face
    # Act / Assert — both admissible against any epoch
    assert att.reportability(doc_null, "any-epoch") is None
    assert att.reportability(committed, "any-epoch") is None
    assert att.row_tokens(doc_null, "tok") == att.row_tokens(committed, "tok")
    assert att.row_tokens(committed, "tok") == "epoch=tok attestation=pre-law"
    # Assert — firing control: a law-claiming field-less witness still dies
    assert att.reportability({"attestation": {"law": att.ATTEST_LAW}},
                             "tok") is not None, \
        "the claimant control stopped biting — equality is vacuous"


def test_unsanctioned_reason_defects_the_mint():
    """A reason outside the ruling registry is not a reason — the daemon
    never runs the opt-out on a lane's say-so."""
    # Arrange
    tmp = _tmp()
    # Act
    code, doc = _drive_probe(tmp, attestation="none-with-reason",
                             null_face_reason="i_wanted_no_stamp")
    # Assert
    assert code == 1 and doc["verdict"] == "DEFECT"
    assert "sanction" in doc["reason"].lower(), \
        f"the refusal must name the sanction law: {doc['reason']!r}"
    # Assert — firing control
    assert sanc.sanction_ok("i_wanted_no_stamp") is None


def test_none_mode_without_a_reason_never_silently_nulls():
    """No-silent-skip at the interface: --attestation=none-with-reason that
    forgot the reason DEFECTS — it may not collapse into the null face."""
    # Act
    code, doc = _drive_probe(_tmp(), attestation="none-with-reason",
                             null_face_reason=None)
    # Assert
    assert code == 1 and doc["verdict"] == "DEFECT"
    assert "reason" in doc["reason"].lower()
    # Assert — the defect is not a null face in disguise
    assert att.NULL_FACE_KEY not in doc, "a silent null minted through the door"


def test_unknown_attestation_mode_defects_loudly():
    """The routing token is a closed set; garbage routes to a spoken
    DEFECT, never to a default."""
    # Act
    code, doc = _drive_probe(_tmp(), attestation="both-please")
    # Assert
    assert code == 1 and doc["verdict"] == "DEFECT"
    assert "both-please" in doc["reason"], \
        f"the defect must name the unknown mode: {doc['reason']!r}"


def test_the_null_route_never_touches_the_stamp_internals():
    """The ruling's byte-freeze half: the null branch is a SEPARATE face at
    the call site — att.stamp_witness is not on the road it travels."""
    # Arrange
    def _tripwire(*a, **kw):
        raise AssertionError("the null route reached the stamp internals")
    saved = att.stamp_witness
    att.stamp_witness = _tripwire
    try:
        # Act — the sanctioned null leg must not raise via the tripwire
        code, doc = _drive_probe(_tmp(), attestation="none-with-reason",
                                 null_face_reason=SANCTION_KEY)
    finally:
        att.stamp_witness = saved
    # Assert
    assert code == 0 and doc["attestation"] is None
    # Assert — firing control: the same tripwire on the LIVE road bites
    att.stamp_witness = _tripwire
    try:
        try:
            _drive_probe(_tmp(), tool=LIVE_TOOL, stage_coex=True)
            fired = False
        except AssertionError:
            fired = True
    finally:
        att.stamp_witness = saved
    assert fired, "the live road never reaches stamp_witness — control vacuous"


# ---------------------------------------------------------------------------
# the minter's pre-daemon validation matrix
# ---------------------------------------------------------------------------

def test_minter_cli_validation_matrix_is_pre_daemon():
    """Four illegal faces, four rc-2 refusals before any mint runs; the
    legal face reaches the mint — the mint itself is tripwired."""
    hits = []

    def _tripwire(*a, **kw):
        hits.append(kw)
        raise AssertionError("mint reached — validation must predate it")
    saved = cal.mint
    cal.mint = _tripwire
    try:
        # Act / Assert — the illegal faces refuse with rc 2
        for argv in (["--dir", "b_x", "--attestation", "none-with-reason"],
                    ["--dir", "b_x", "--attestation", "live",
                     "--null-face-reason", SANCTION_KEY],
                    ["--dir", "b_x", "--attestation", "none-with-reason",
                     "--null-face-reason", "i_wanted_no_stamp"]):
            rc = cal.main(argv)
            assert rc == 2, f"illegal face {argv!r} reached rc={rc} not 2"
        assert not hits, "a mint ran behind a refused face"
        # Act / Assert — the legal live face reaches the mint (tripwire fires)
        try:
            cal.main(["--dir", "b_y", "--attestation", "live"])
            reached = False
        except AssertionError:
            reached = True
        assert reached, "the legal live face never reached the mint"
    finally:
        cal.mint = saved


def test_ledger_declares_the_attestation_mode():
    """Every ledger the minter writes from the ruling forward declares its
    attestation face; the null face additionally books its sanction — and
    the probe leg received the same face (minter->probe forwarding law)."""
    # Arrange
    tmp = _tmp()
    wdir = tmp / "m7_floor_calibration_p7cap_b_law_ledger"
    calls = []

    def _fake_probe(tool, *, arm, n, reps, json_path=None, work=None, **kw):
        calls.append(kw)
        doc = {"verdict": "OK", "run_rc": 0, "status_tail": "ok",
               "cell": f"{tool}__{arm}__N{n}", "argv": ["--reps", str(reps)],
               "reps": reps, "tool": tool, "arm": arm, "n": n,
               "wall_seconds": 61.0,
               "sidecar": {"exit_status": 0, "cpu_seconds": 60.0,
                           "ru_utime": 50.0, "ru_stime": 10.0}}
        Path(json_path).write_text(json.dumps(doc, sort_keys=True),
                                   encoding="utf-8")
        return 0
    saved = cal.probe.run_probe
    cal.probe.run_probe = _fake_probe
    try:
        # Act — the sanctioned null route over the whole grid for one tool
        rc = cal.mint(wdir, only=[TOOL],
                      attestation_mode="none-with-reason",
                      null_face_reason=SANCTION_KEY)
    finally:
        cal.probe.run_probe = saved
    assert rc == 0, f"mint rc={rc}"
    # Assert — the ledger face
    led = json.loads((wdir / "CALIBRATION.json").read_text(encoding="utf-8"))
    assert led["attestation_mode"] == "none-with-reason", led
    assert led["attestation_sanction"]["key"] == SANCTION_KEY
    assert led["attestation_sanction"]["ruling"]
    assert sanc.ledger_post_law_ok(led) is None, \
        "the written ledger must pass its own law"
    # Assert — the forwarding half: every probe leg saw the mode + campaign
    assert calls and all(c.get("attestation") == "none-with-reason"
                         and c.get("null_face_reason") == SANCTION_KEY
                         and c.get("campaign") == wdir.name for c in calls), \
        f"minter->probe forwarding broke: {calls[:2]}"


def test_the_sanction_registry_is_the_single_dated_ruling():
    """The data-gate: exactly the controller-ruled entry, with its dated
    ruling — an edit here is an edit to the controller's word, and this
    unit is its tripwire."""
    # Assert — exactness, not membership
    assert set(sanc.SANCTIONED_NULL_FACES) == {SANCTION_KEY}, \
        "the sanction registry carries more than the ruled entry"
    row = sanc.SANCTIONED_NULL_FACES[SANCTION_KEY]
    assert "2026-11-04" in row["ruling"], \
        "the sanction must cite its dated controller ruling"
    assert row["face"] == "null/pre-law"
    # Assert — firing control: the gate bites on a foreign key
    assert sanc.sanction_ok(SANCTION_KEY + "_extended") is None


def test_dual_face_law_both_and_orphan_faces_die():
    """A witness speaks one face: the lv1 block OR a sanctioned null label,
    never both, never an unsanctioned orphan. The (AL) epoch-collision
    unit applies this law to every committed batch-face witness."""
    # Arrange
    sanctioned_label = {"reason": SANCTION_KEY}
    # Act / Assert — both faces at once is a contradiction
    both = {"attestation": {"law": att.ATTEST_LAW}, att.NULL_FACE_KEY: sanctioned_label}
    assert sanc.dual_face_ok(both) is not None
    # Act / Assert — an orphan label (no sanction behind it) dies
    orphan = {"attestation": None, att.NULL_FACE_KEY: {"reason": "free-pass"}}
    assert sanc.dual_face_ok(orphan) is not None
    # Assert — firing controls: each single face is lawful
    assert sanc.dual_face_ok({"attestation": None,
                              att.NULL_FACE_KEY: sanctioned_label}) is None
    assert sanc.dual_face_ok({"attestation": {"law": att.ATTEST_LAW},
                              "verdict": "OK"}) is None
    # Assert — and the pre-law face is outside the law entirely (the 375)
    assert sanc.dual_face_ok({"verdict": "OK"}) is None


def test_post_law_ledgers_declare_the_mode_or_die():
    """The (AC) ledger law's own firing controls: post-law ledgers without
    a declared mode, or a null mode without a booked sanction, refuse;
    pre-law committed ledgers are exempt (their bytes predate the ruling)."""
    # Arrange
    post = "2026-11-05T00:00:00+00:00"
    pre = "2026-10-27T00:00:00+00:00"
    # Act / Assert — missing mode post-law dies
    assert sanc.ledger_post_law_ok({"created_utc": post}) is not None
    # Act / Assert — null mode without the sanction booking dies
    assert sanc.ledger_post_law_ok(
        {"created_utc": post, "attestation_mode": "none-with-reason"}) is not None
    # Assert — firing controls: live is lawful, sanctioned-null is lawful,
    # and the pre-law face walks untouched
    assert sanc.ledger_post_law_ok(
        {"created_utc": post, "attestation_mode": "live"}) is None
    assert sanc.ledger_post_law_ok(
        {"created_utc": post, "attestation_mode": "none-with-reason",
         "attestation_sanction": {"key": SANCTION_KEY}}) is None
    assert sanc.ledger_post_law_ok({"created_utc": pre}) is None
