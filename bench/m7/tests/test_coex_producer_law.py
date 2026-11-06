"""Group (QE2) test_coex_producer_law — the flatness law's producer (Phase-D).

DEBT-COEX-PRODUCER closed the diagnosis: the coex inversion-probe record had
no author and the mint gate had no teeth (state C of the Phase-C adjudication
passed on self-reported shape alone). This battery is the RED-first law of
the cure, per the controller ruling of 2026-11-04:

  * tools/coex_inversion_probe is the rig: it measures the N=3 deliberate
    co-tenancy cohort against the serial solo baseline and EMITS the record;
    the verdict and deltas are derived from the leg bytes, never typed;
  * attestation.coex_record_ok grew the self-contained teeth (T1 re-derive,
    T2 class + overlap, T3 binding structure, T4 seal consistency);
    build_attestation grew the contextual ones (T5 image/campaign/clock,
    T6 live replay, ledger double-entry);
  * every refusal unit carries its own seen-to-fire control (dead-metric law);
    every negative drives the same code with the defect removed;
  * the report face revalidates an embedded lv1 coex block (the A-extension),
    while the pre-law face — 375/375 committed witnesses — short-circuits
    unchanged: A10 is that parity law's standing keeper.

Zero containers, zero images: measurement legs run at campaign time on the
controller's side; every unit here drives pure bytes with an injected replay
probe (the gov.pre_flight_assert probe= idiom).
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import tools.attestation as att                       # noqa: E402
from tests import coex_fixtures as fx                 # noqa: E402

# The banked refusal bytes of phase-c/adjudicate_stamp_gate.out (states A and
# B). Byte-truth fixtures: the implementation drifting off these strings is a
# RED here, not a silent paraphrase.
STATE_A_HEAD = ("attestation refused: preflight quiet-gate verdict absent "
                "for cell ")
STATE_A_TAIL = (" — the RB-08(3) GO/REFUSE record must exist in bytes "
                "(attestation cannot be remembered, only read)")
STATE_B = ("attestation refused: coex inversion-probe record absent "
           f"({att.COEX_ENV} unset) — parity bytes may not be reported "
           "without the flatness qualifier")


def _tmp():
    return Path(tempfile.mkdtemp(prefix="coex_law_"))


def _build(tmp, **kw):
    """build_attestation over the staged face with the mint's context."""
    os.environ[att.COEX_ENV] = str(kw.pop("coex_path", tmp / "coex.json"))
    kw.setdefault("preflight_log", fx.preflight_log(tmp))
    kw.setdefault("cell", fx.CELL)
    kw.setdefault("epoch", "law-epoch-1")
    kw.setdefault("image_digest", fx.IMAGE_DIGEST)
    kw.setdefault("campaign", fx.CAMPAIGN)
    kw.setdefault("live_probe", fx.fake_live_probe())
    try:
        return att.build_attestation(**kw)
    finally:
        os.environ.pop(att.COEX_ENV, None)


def _build_refusal(tmp, **kw) -> str:
    try:
        _build(tmp, **kw)
    except att.AttRefusal as exc:
        return str(exc)
    raise AssertionError("the mint teeth did not bite — vacuous control")


def _law_reason(**rig_kw) -> str:
    """The law's single face over a rig attempt. The rig's emit path
    self-checks against the very same teeth (RigError < RuntimeError speaks
    coex_record_ok's bytes verbatim), so a defect dies identically whether
    the rig refuses to mint it or the gate refuses to admit it."""
    try:
        rec = fx.rig_record(**rig_kw)
    except RuntimeError as exc:
        return str(exc)
    return att.coex_record_ok(rec)


# -- (1) the rig's honest face ---------------------------------------------------

def test_rig_emit_satisfies_the_shape_floor():
    """The rig's emit path produces bytes the law admits, and the admitted
    face is complete: dropping any mandatory column speaks a reason."""
    # Arrange
    rec = fx.rig_record()
    # Act / Assert — honest face
    assert att.coex_record_ok(rec) is None, "the rig's own emit must be lawful"
    # Assert — firing controls: the floor still names missing columns
    for column in ("schema", "shape", "legs", "solo_mean_s", "deltas_pct",
                   "verdict", "measured_utc"):
        stripped = {k: v for k, v in rec.items() if k != column}
        reason = att.coex_record_ok(fx.reseal(stripped))
        assert reason is not None, f"dropping {column} sailed through — vacuous"


def test_hand_written_shape_only_record_is_refused():
    """STATE C DIES. The exact bytes that passed the pre-teeth gate (the
    banked adjudication: verdict OK, 'it passed on nothing but self-reported
    shape') must now speak a binding-naming refusal."""
    # Arrange
    rec = fx.handwritten_record()
    # Act
    reason = att.coex_record_ok(rec)
    # Assert — the bite names the missing binding, not a generic shape gripe
    assert reason is not None, "state C passed again — the teeth are decorative"
    assert "bind" in reason.lower() or "record_sha256" in reason, \
        f"the refusal must name the binding gap: {reason!r}"
    # Assert — firing control: the rig face of the same measurement passes
    assert att.coex_record_ok(fx.rig_record()) is None, \
        "the refusal is the binding, not the numbers (control failed)"


def test_verdict_and_deltas_are_rederived_not_trusted():
    """T1: the verdict and the delta face follow from the leg bytes. A
    re-sealed record whose verdict lies, or whose deltas lie, dies. (reseal
    re-digests WITHOUT self-checking — it is the forensic seam that isolates
    these teeth from the seal-consistency teeth; the emit path never allows
    the same tamper past the rig's own mouth.)"""
    # Arrange
    rec = fx.rig_record()
    assert rec["verdict"] == "NOT-FLAT" and max(rec["deltas_pct"]) > 5.0
    # Act / Assert — verdict lie (deltas kept honest, re-sealed past T4)
    reason = att.coex_record_ok(fx.reseal(rec, verdict="FLAT"))
    assert reason is not None and "verdict" in reason, \
        f"a lying verdict must speak with the word: {reason!r}"
    # Act / Assert — delta lie (verdict stays the re-derivable NOT-FLAT)
    lying = list(rec["deltas_pct"])
    lying[0] = lying[0] + 2.0
    reason = att.coex_record_ok(fx.reseal(rec, deltas_pct=lying))
    assert reason is not None and "delta" in reason.lower(), \
        f"typed deltas that do not follow from the legs must die: {reason!r}"
    # Assert — firing control: honest re-seal of the same bytes is admissible
    assert att.coex_record_ok(fx.reseal(rec)) is None


def test_cotenant_windows_must_genuinely_overlap():
    """T2: it is an INVERSION probe — the N=3 cohort legs co-tenant together.
    A cohort whose monotonic windows have no common intersection is a serial
    run wearing a co-tenancy mask, and dies."""
    # Arrange — leg 1 starts after leg 0 finished: no common window
    span = fx.LEG_SPAN_S
    disjoint = [fx.leg(30, fx.COHORT_WALLS[0], stagger_s=0.0),
                 fx.leg(31, fx.COHORT_WALLS[1], stagger_s=2.0 * span),
                 fx.leg(32, fx.COHORT_WALLS[2], stagger_s=span)]
    # Act
    reason = _law_reason(cohort_legs=disjoint)
    # Assert — the bite
    assert reason is not None and "overlap" in reason.lower(), \
        f"non-co-tenant cohort admitted: {reason!r}"
    # Assert — firing control: the staged cohort genuinely overlaps
    assert att.coex_record_ok(fx.rig_record()) is None


def test_min_leg_count_is_the_inversion_class():
    """T2 class law: the shape token is derived, N=3 class or die — a
    two-leg 'cohort' and a shape/leg mismatch both speak."""
    # Arrange
    short = [fx.leg(40 + i, w, stagger_s=10.0 * i)
             for i, w in enumerate(fx.COHORT_WALLS[:2])]
    # Act / Assert — two legs: below the class
    reason = _law_reason(cohort_legs=short)
    assert reason is not None and ("n=2" in reason.lower() or "leg" in reason.lower()), \
        f"an N=2 'cohort' was admitted silently: {reason!r}"
    # Act / Assert — shape token lies about the leg count (re-sealed past T4)
    rec = fx.rig_record()
    reason = att.coex_record_ok(fx.reseal(rec, shape="coex-inversion/N=4"))
    assert reason is not None and "shape" in reason, \
        f"shape/legs mismatch admitted: {reason!r}"
    # Assert — firing control
    assert att.coex_record_ok(rec) is None


# -- (2) the mint-side context teeth ---------------------------------------------

def test_double_entry_is_mandatory():
    """T4 at the mint: the record must be booked in the rig ledger beside the
    file the env points at — the rig is that ledger's sole author, so an
    un-booked or re-digested record has nothing to stand on."""
    # Arrange — honest staging for the control first
    tmp = _tmp()
    fx.stage(tmp, book=True)
    assert _build(tmp)["coex_probe"]["verdict"] == "NOT-FLAT"   # control
    # Act — un-booked record
    tmp2 = _tmp()
    fx.stage(tmp2, book=False)
    reason = _build_refusal(tmp2)
    # Assert
    assert "ledger" in reason.lower(), f"un-booked record admitted: {reason!r}"
    # Act — ledger re-digested (record tampered under a stale booking)
    tmp3 = _tmp()
    fx.stage(tmp3, book=True)
    (tmp3 / att.COEX_LEDGER_NAME).write_text(
        json.dumps({"produced_utc": fx.MEASURED_UTC, "rig": "coex-inversion-rig/1",
                    "record_sha256": "0" * 64}) + "\n", encoding="utf-8")
    reason = _build_refusal(tmp3)
    assert "ledger" in reason.lower(), f"ledger disagreement admitted: {reason!r}"


def test_ledger_author_is_the_rig_alone():
    """The rig books the ledger; a hand-written booking without the rig
    identity is not a booking."""
    # Arrange
    tmp = _tmp()
    _, rec = fx.stage(tmp, book=False)
    (tmp / att.COEX_LEDGER_NAME).write_text(
        json.dumps({"produced_utc": fx.MEASURED_UTC,
                    "record_sha256": rec["record_sha256"]}) + "\n",
        encoding="utf-8")
    # Act — the entry carries no rig identity
    reason = _build_refusal(tmp)
    # Assert
    assert "rig" in reason.lower(), \
        f"an unattributed booking stood in for the rig: {reason!r}"
    # Assert — firing control
    tmp2 = _tmp()
    fx.stage(tmp2, book=True)
    assert _build(tmp2)["law"] == att.ATTEST_LAW


def test_record_is_bound_to_the_image_it_measured():
    """T5: which image the record measured is which image the witness is
    stamped for — a record minted for one face's image cannot qualify a
    witness stamped on another's."""
    # Arrange
    tmp = _tmp()
    fx.stage(tmp)
    # Act / Assert — foreign digest at stamp time
    reason = _build_refusal(tmp, image_digest="sha256:" + "0" * 64)
    assert "image" in reason.lower() or "digest" in reason.lower(), \
        f"cross-image laundering admitted: {reason!r}"
    # Assert — firing control: the matching pair passes
    assert _build(tmp)["epoch"] == "law-epoch-1"


def test_record_is_bound_to_the_campaign():
    """T5: the record was measured for THIS campaign; replaying it into
    another campaign's mint is the second laundering vector, and dies."""
    # Arrange
    tmp = _tmp()
    fx.stage(tmp)
    # Act / Assert — foreign campaign at stamp time
    reason = _build_refusal(
        tmp, campaign="m7_floor_calibration_p7cap_other_lane")
    assert "campaign" in reason.lower(), \
        f"cross-campaign replay admitted: {reason!r}"
    # Assert — firing control
    assert _build(tmp)["coex_probe"]["verdict"] == "NOT-FLAT"


def test_live_probe_refuses_phantom_containers():
    """T6: the container ids the record names must answer the daemon, and a
    daemon that will not answer is a REFUSAL, never a pass — the
    no-silent-skip law."""
    # Arrange
    tmp = _tmp()
    fx.stage(tmp)
    rec = json.loads((tmp / "coex.json").read_text(encoding="utf-8"))
    phantom = rec["legs"][1]["container_id"]
    # Act / Assert — one unknown container id poisons the record
    reason = _build_refusal(tmp,
                            live_probe=fx.fake_live_probe(unknown=[phantom]))
    assert "phantom" in reason.lower() or phantom in reason, \
        f"an unknown container sailed through: {reason!r}"
    # Act / Assert — the replay must see the SAME image it binds
    reason = _build_refusal(tmp, live_probe=fx.fake_live_probe(
        wrong_image="someone-elses:tag"))
    assert "image" in reason.lower(), \
        f"config-image disagreement admitted: {reason!r}"
    # Act / Assert — no-silent-skip: an unreachable daemon REFUSES
    reason = _build_refusal(tmp, live_probe=fx.fake_live_probe(broken=True))
    assert "daemon" in reason.lower() or "replay" in reason.lower(), \
        f"a dead probe was treated as a pass: {reason!r}"
    # Assert — firing control: the honest replay is admissible
    assert _build(tmp)["law"] == att.ATTEST_LAW


def test_clock_must_be_honest():
    """T5 time law: measured_utc must be parseable and may not postdate the
    stamp — the shape-only floor's 'non-empty' was gameable with a typed
    sentence; the teeth demand an honest clock."""
    # Arrange
    tmp = _tmp()
    # Act / Assert — future-dated record (forged via the forensic reseam,
    # then booked through the rig so only the clock is left to bite)
    bad = fx.reseal(fx.rig_record(), measured_utc="2099-01-01T00:00:00Z")
    (tmp / "coex.json").write_text(json.dumps(bad, sort_keys=True),
                                   encoding="utf-8")
    fx._rig().book_ledger(tmp, bad)
    reason = _build_refusal(tmp)
    assert "measured_utc" in reason or "future" in reason.lower(), \
        f"a future-dated measurement admitted: {reason!r}"
    # Act / Assert — unparseable
    gibberish = fx.reseal(fx.rig_record(), measured_utc="yesterday, I think")
    (tmp / "coex.json").write_text(json.dumps(gibberish, sort_keys=True),
                                   encoding="utf-8")
    fx._rig().book_ledger(tmp, gibberish)
    reason = _build_refusal(tmp)
    assert "measured_utc" in reason, \
        f"an unparseable clock admitted: {reason!r}"
    # Assert — firing control: the honest stamp passes
    fx.stage(tmp, name="honest.json")
    assert _build(tmp, coex_path=tmp / "honest.json")["law"] == att.ATTEST_LAW


def test_solo_face_is_required_and_rederived():
    """The inflation number is cohort-over-solo: no solo legs, or a typed
    solo mean that does not follow from the solo legs, is no measurement."""
    # Act / Assert — empty solo face
    reason = _law_reason(solo_legs=[])
    assert reason is not None and "solo" in reason.lower(), \
        f"a record with no solo legs was admissible: {reason!r}"
    # Act / Assert — solo_mean overwritten toward a lie (re-sealed past T4;
    # the cohort deltas are typed to agree with the fake mean, so only the
    # solo re-derivation can catch it)
    rec = fx.rig_record()
    fake = 1.0
    reason = att.coex_record_ok(fx.reseal(
        rec, solo_mean_s=fake,
        deltas_pct=[round(100.0 * (w - fake) / fake, 1)
                    for w in fx.COHORT_WALLS],
        verdict="NOT-FLAT"))
    assert reason is not None and "solo" in reason.lower(), \
        f"a typed solo mean must be re-derived from the solo legs: {reason!r}"
    # Assert — firing control
    assert att.coex_record_ok(rec) is None


# -- (3) the frozen attested path and the pre-law parity keeper -------------------

def test_attested_path_is_byte_frozen():
    """The attested face's refusal bytes are the banked adjudication's, and
    stay so (byte-true fixtures law); stamping never mutates the caller's
    document."""
    # Arrange
    tmp = _tmp()
    # Act — state A: no preflight record at all
    absent = att.stamp_witness({"verdict": "OK", "cell": fx.CELL},
                               preflight_log=tmp / "absent.jsonl",
                               cell=fx.CELL, epoch="e1")
    # Act — state B: preflight GO, no coex record (the env stays unset)
    os.environ.pop(att.COEX_ENV, None)
    no_coex = att.stamp_witness({"verdict": "OK", "cell": fx.CELL},
                                preflight_log=fx.preflight_log(tmp),
                                cell=fx.CELL, epoch="e1")
    # Assert — the exact banked bytes
    assert absent["verdict"] == "DEFECT" \
        and absent["reason"].startswith(STATE_A_HEAD) \
        and absent["reason"].endswith(STATE_A_TAIL) \
        and repr(fx.CELL) in absent["reason"], \
        f"state A bytes moved: {absent['reason']!r}"
    assert no_coex["verdict"] == "DEFECT" and no_coex["reason"] == STATE_B, \
        f"state B bytes moved: {no_coex['reason']!r}"
    # Assert — immutability of the caller's document
    assert "attestation" not in absent and "attestation" not in no_coex
    doc = {"verdict": "OK", "cell": fx.CELL}
    att.stamp_witness(doc, preflight_log=tmp / "absent.jsonl",
                      cell=fx.CELL, epoch="e1")
    assert doc == {"verdict": "OK", "cell": fx.CELL}, \
        "stamping mutated the caller's document"


def test_pre_law_committed_record_stays_adjudicable():
    """THE PARITY KEEPER: the 375/375 face — no attestation key, any epoch —
    stays REPORTABLE and prints exactly pre-law. If this reddens, every
    parity ratio the program has printed is suspect."""
    # Arrange
    committed = {"verdict": "OK", "cell": fx.CELL, "reps": 100}
    # Act / Assert — admissible against any epoch
    assert att.reportability(committed, "f3e894a6933a2ffb") is None
    assert att.reportability(committed, "any-other-epoch-entirely") is None
    assert att.row_tokens(committed, "tok-1") == "epoch=tok-1 attestation=pre-law"
    # Assert — firing control: a law-CLAIMING field-less witness still dies
    claimant = {"attestation": {"law": att.ATTEST_LAW}}
    assert att.reportability(claimant, "tok-1") is not None, \
        "the claimant control stopped biting — keeper is vacuous"


def test_report_side_revalidates_the_embedded_block():
    """The A-extension: an lv1-claiming witness that carries the hand-written
    (state-C) coex block is refused at the REPORT face too — skipping the
    minter does not skip the law. The sealed rig block sails; the key-absent
    face short-circuits (the 375 are not asked for papers)."""
    # Arrange — a live-epoch, GO-preflight, law-claiming witness
    live = "live-epoch-1"

    def claim(coex):
        return {"attestation": {"law": att.ATTEST_LAW,
                                "preflight": {"decision": "GO"},
                                "coex_probe": coex, "epoch": live}}
    # Act / Assert — the forger's block, live epoch, still inadmissible
    refusal = att.reportability(claim(fx.handwritten_record()), live)
    assert refusal is not None, "a committed state-C block was quotable"
    assert "coex" in refusal.lower(), \
        f"the refusal must name the coex face: {refusal!r}"
    # Assert — firing control 1: the rig-sealed block is admissible
    assert att.reportability(claim(fx.rig_record()), live) is None, \
        "the honest embedded block must sail"
    # Assert — firing control 2: the pre-law face untouched
    assert att.reportability({"verdict": "OK"}, live) is None
