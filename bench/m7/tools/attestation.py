"""Co-tenancy attestation law (Phase-9 O3): the two proven practices become
harness bytes, not lane folklore.

Phase-5 Q2 established that the only variable between byte-identical cells
measured 376 s and 616 s was the measurement environment, and Phase-6 O2
measured the post-cap residual: at three-way co-tenancy the same capped cell
inflates ~12-13.5 % against the solo mean (wall/cpu pinned at ~1.000 —
shared-VM memory-bandwidth contention). The practices that contain it:
quiet-serial enforcement (RB-08(3), already spoken through the driver) and
the deliberate coex-inversion probe (N=3 class) whose verdict qualifies
which machine a number was taken on. Codified here:

  MINT SIDE  a witness is only ever minted together with (a) the preflight
             quiet-gate record that let its leg launch and (b) a
             well-formed inversion-probe record; no proofs, no mint — the
             leg comes back DEFECT with the reason, never as a silent
             un-attested OK.
  REPORT SIDE  the parity reporter refuses a witness that claims the
             attestation law yet lacks the fields, refuses a REFUSEd quiet
             gate, refuses an epoch-mismatched attestation (the post-cap
             witness law), admits fully-attested bytes, and prints the
             epoch token plus the honest attestation state on every row.
             Witnesses predating the law remain re-derivable — the committed
             record must never be made unquotable — but are labelled
             pre-law on their face.

Immutability: stamp_witness returns a NEW document; it never mutates the
caller's verdict.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ATTEST_LAW = "attestation-lv1"
#: Operator/lane-set path to the current coex-inversion probe record (JSON).
COEX_ENV = "MSUITER_COEX_PROBE"
#: The inversion probe's verdict vocabulary (the 5 % flatness bar decides it;
#: NOT-FLAT is a banked gate outcome, not an error — Phase-6 O2).
FLAT_VERDICTS = ("FLAT", "NOT-FLAT")
COEX_SHAPE_PREFIX = "coex-inversion/"
#: Phase-D teeth (controller ruling 2026-11-04): the rig books every record
#: it mints beside itself; the record's own face cannot be the only proof.
COEX_LEDGER_NAME = "coex_ledger.jsonl"
COEX_MIN_LEGS = 3                      # the deliberate-inversion class
COEX_BAR_PCT = 5.0                     # the sanctioned flatness bar, not tunable
COEX_DELTA_TOL = 0.05                  # pp against the 1-decimal emit face
_SOLO_MEAN_TOL = 1e-6
_HEX64 = re.compile(r"[0-9a-f]{64}")            # bare sha256 hex faces
_SHA256_URI = re.compile(r"sha256:[0-9a-f]{64}")
COEX_SEAL_COL = "record_sha256"           # the rig's self-consistency digest
#: The explicit null face of the sanctioned no-stamp route (Phase-D
#: Instrument B, controller ruling 2026-11-04 (2)): a witness that
#: lawfully declines the attestation SPEAKS that decision — this label,
#: never the pre-law key-absent hand-written face.
NULL_FACE_KEY = "null_attestation_face"


class AttRefusal(RuntimeError):
    """The mint may not happen: one of the two attestation proofs is absent
    or inadmissible. The reason is spoken, never swallowed."""


def _read_json(path: Path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def coex_canonical_bytes(rec: dict) -> str:
    """The sealed byte face: everything but the digest itself, canonically
    ordered, one way to serialise — the rig, the ledger and the gate must
    mean the same bytes when they speak of a record."""
    body = {k: v for k, v in rec.items() if k != COEX_SEAL_COL}
    return json.dumps(body, sort_keys=True, separators=(",", ":"))


def coex_seal_digest(rec: dict) -> str:
    return hashlib.sha256(coex_canonical_bytes(rec).encode("utf-8")).hexdigest()


def coex_seal(rec: dict) -> dict:
    """A NEW record with the self-consistency digest computed over the
    canonical bytes (immutability law)."""
    new = {k: v for k, v in rec.items() if k != COEX_SEAL_COL}
    new[COEX_SEAL_COL] = coex_seal_digest(new)
    return new


def coex_record_ok(rec) -> str | None:
    """Why an inversion-probe record is inadmissible, or ``None``.

    Phase-D teeth tiers (the pre-teeth face admitted state C on self-reported
    shape alone — DEBT-COEX-PRODUCER, controller ruling 2026-11-04):
      T0 the frozen shape floor (unchanged bytes — the banked gate),
      T3 the binding face: rig, campaign, image, cell, host, inspect, seal —
         an unbound record is self-reported folklore and dies naming it,
      T2 the class law: derived N=3-class shape token, positive monotonic
         clock windows with a COMMON intersection (a masked-serial run is
         not a co-tenancy measurement),
      T1 the derived face: solo mean, deltas and verdict are RE-DERIVED
         from the leg bytes; the typed columns only witness agreement.
    The contextual teeth (T5 mint cross-check, T6 live replay, ledger
    double-entry) live in build_attestation — they know the mint, a record
    on its own cannot answer them."""
    if not isinstance(rec, dict):
        return "record is not a JSON object"
    if rec.get("schema") != 1:
        return f"schema is {rec.get('schema')!r}, want 1"
    shape = str(rec.get("shape", ""))
    if not shape.startswith(COEX_SHAPE_PREFIX):
        return (f"shape {shape!r} is not a deliberate inversion probe "
                f"({COEX_SHAPE_PREFIX}N=<n> class)")
    legs = rec.get("legs")
    if not isinstance(legs, list) or not legs:
        return "no legs enumerated"
    for leg in legs:
        if not isinstance(leg, dict):
            return "a leg is not an object"
        for col in ("wall_s", "cpu_s"):
            v = leg.get(col, -1)
            if not isinstance(v, (int, float)) or not v > 0:
                return f"leg {leg.get('probe')!r} column {col} not positive"
    solo = rec.get("solo_mean_s", -1)
    if not isinstance(solo, (int, float)) or not solo > 0:
        return "solo_mean_s missing or non-positive"
    deltas = rec.get("deltas_pct")
    if not isinstance(deltas, list) or len(deltas) != len(legs) \
            or not all(isinstance(d, (int, float)) for d in deltas):
        return "deltas_pct does not pair one-to-one with the legs"
    if rec.get("verdict") not in FLAT_VERDICTS:
        return f"verdict {rec.get('verdict')!r} outside {FLAT_VERDICTS}"
    if not str(rec.get("measured_utc", "")):
        return "record carries no measured_utc stamp"
    # -- T3: the binding face (before the window law: an unbound record dies
    # naming its authorship gap, the state-C diagnosis verbatim) --------------
    bind = rec.get("bind")
    if not isinstance(bind, dict):
        return ("record carries no bind block — an unsigned, unbound record "
                "is self-reported shape, not a rig emission (state C)")
    for col in ("rig", "campaign"):
        if not str(bind.get(col, "")):
            return f"bind.{col} missing — the record names no {col}"
    img = bind.get("image")
    if not isinstance(img, dict) or not str(img.get("ref", "")) \
            or not _SHA256_URI.fullmatch(str(img.get("digest", ""))):
        return "bind.image is not a {ref, digest: sha256:<hex>} pair"
    cell = bind.get("cell")
    if not isinstance(cell, dict) or not str(cell.get("tool", "")) \
            or not str(cell.get("arm", "")) \
            or not isinstance(cell.get("n"), int) \
            or not isinstance(cell.get("reps"), int) \
            or not isinstance(cell.get("cell_argv"), list) \
            or not cell.get("cell_argv"):
        return "bind.cell is not a {tool, arm, n, reps, cell_argv} face"
    host = bind.get("host")
    if not isinstance(host, dict) or any(
            not str(host.get(c, ""))
            for c in ("boot_id", "kernel_release", "cgroup")):
        return "bind.host lacks the boot_id/kernel_release/cgroup identity"
    if not isinstance(bind.get("ledger_entry"), dict) \
            or not str(bind["ledger_entry"].get("produced_utc", "")):
        return "bind.ledger_entry missing — the double-entry pair is absent"
    ids = [str(leg.get("container_id", "")) for leg in legs]
    if any(not _HEX64.fullmatch(i) for i in ids):
        return "a leg names no 64-hex container_id"
    insp = bind.get("inspect")
    if not isinstance(insp, list) or len(insp) != len(legs) \
            or [str(e.get("container_id", "")) for e in insp
                if isinstance(e, dict)] != ids:
        return "bind.inspect does not pair one daemon face per leg"
    if not isinstance(rec.get(COEX_SEAL_COL), str) \
            or not _HEX64.fullmatch(rec[COEX_SEAL_COL]):
        return "record_sha256 absent — the seal that closes the bind is missing"
    if coex_seal_digest(rec) != rec[COEX_SEAL_COL]:
        return ("record_sha256 does not seal the record bytes — the face was "
                "moved after the rig signed it")
    # -- T2: the class law -----------------------------------------------------
    if shape[len(COEX_SHAPE_PREFIX):] != f"N={len(legs)}":
        return (f"shape token {shape!r} does not match the leg count "
                f"{len(legs)} — the class token is derived, not typed")
    if len(legs) < COEX_MIN_LEGS:
        return (f"coex class law: N={len(legs)} is below the "
                f"N={COEX_MIN_LEGS} inversion minimum — too few legs to "
                "co-tenant")
    windows = []
    for leg in legs:
        clk = leg.get("clock")
        bad = (f"leg {leg.get('probe')!r} clock window cannot prove "
               "co-tenancy overlap")
        if not isinstance(clk, dict):
            return bad + ": no clock face"
        for a, b in (("start_mono_ns", "stop_mono_ns"),
                     ("start_real_ns", "stop_real_ns")):
            s, e = clk.get(a), clk.get(b)
            if not isinstance(s, int) or not isinstance(e, int) or not e > s >= 0:
                return bad + f": {a}/{b} is not a positive monotonic span"
        windows.append((clk["start_mono_ns"], clk["stop_mono_ns"]))
    if not min(e for _, e in windows) > max(s for s, _ in windows):
        return ("cohort windows have no common intersection — the legs never "
                "co-tenanted: an inversion probe with no overlap is a serial "
                "run wearing a co-tenancy mask")
    # -- T1: the derived face ---------------------------------------------------
    solo_legs = rec.get("solo_legs")
    if not isinstance(solo_legs, list) or not solo_legs \
            or not all(isinstance(l, dict)
                       and isinstance(l.get("wall_s"), (int, float))
                       and l.get("wall_s") > 0 for l in solo_legs):
        return "no well-formed solo legs — the inflation number has no baseline"
    solo_derived = sum(l["wall_s"] for l in solo_legs) / len(solo_legs)
    if abs(solo_derived - solo) > _SOLO_MEAN_TOL * max(1.0, solo):
        return (f"solo_mean_s {solo!r} does not follow from the solo legs "
                f"(re-derived {solo_derived!r}) — the solo face is measured")
    for i, (leg, d) in enumerate(zip(legs, deltas)):
        want = round(100.0 * (leg["wall_s"] - solo) / solo, 1)
        if abs(want - d) > COEX_DELTA_TOL:
            return (f"delta[{i}] {d!r} does not follow from the leg bytes "
                    f"(re-derived {want!r}) — deltas are computed, not typed")
    bar = rec.get("bar_pct", COEX_BAR_PCT)
    if bar != COEX_BAR_PCT:
        return (f"bar_pct {bar!r} is not the sanctioned {COEX_BAR_PCT} "
                "flatness bar — the gate is not tunable from inside the record")
    want_v = "FLAT" if max(deltas) <= bar else "NOT-FLAT"
    if rec["verdict"] != want_v:
        return (f"verdict {rec['verdict']!r} does not follow from the deltas "
                f"against the {bar} % bar (re-derived {want_v!r})")
    return None


def read_preflight_verdict(preflight_log, cell: str) -> dict | None:
    """The LAST RB-08(3) decision recorded for this exact stamp."""
    try:
        lines = Path(preflight_log).read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    found = None
    for ln in lines:
        try:
            rec = json.loads(ln)
        except ValueError:
            continue
        if isinstance(rec, dict) and rec.get("cell") == cell:
            found = rec
    return found


def _parse_utc(text: str):
    try:
        dt = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def _ledger_ok(record_path: Path, rec: dict) -> None:
    """T4 at the mint: the rig books every record it mints into the ledger
    beside the file; the record's own face may not be the only proof
    (double-entry law, controller ruling 2026-11-04)."""
    led = record_path.parent / COEX_LEDGER_NAME
    try:
        lines = led.read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    entries = []
    for ln in lines:
        try:
            e = json.loads(ln)
        except ValueError:
            continue
        if isinstance(e, dict):
            entries.append(e)
    seal = rec[COEX_SEAL_COL]
    bind = rec["bind"]
    if not entries:
        raise AttRefusal(
            f"coex ledger {COEX_LEDGER_NAME} absent or empty beside "
            f"{record_path.name!r} — the rig books every record it mints; "
            "an un-booked record has nothing to stand on")
    hits = [e for e in entries if e.get(COEX_SEAL_COL) == seal]
    if not hits:
        raise AttRefusal(
            f"coex ledger carries no booking for record_sha256 {seal!r} — "
            "the record beside the ledger was not booked by the rig, or was "
            "moved after it was booked (double-entry law)")
    if not any(e.get("rig") == bind.get("rig") for e in hits):
        raise AttRefusal(
            "coex ledger booking was not authored by the rig the record "
            "binds — the rig is the ledger's sole author")
    want = dict(bind.get("ledger_entry") or {})
    if not all(e.get("produced_utc") == want.get("produced_utc")
               and e.get("rig") == want.get("rig") for e in hits):
        raise AttRefusal(
            "coex ledger booking does not agree with the record's own "
            "ledger_entry binding — one face was moved alone")


def _context_ok(rec: dict, *, image_digest, campaign, now_utc) -> None:
    """T5: the record qualified the machine and campaign it was measured
    for; the mint may not launder it onto another image, into another
    campaign, or under a clock that postdates the stamp."""
    bind = rec["bind"]
    if image_digest is None or str(bind["image"]["digest"]) != str(image_digest):
        raise AttRefusal(
            f"coex record is bound to image {bind['image']['digest']!r}, "
            f"not the image the witness is minted against ({image_digest!r}) "
            "— no cross-image laundering")
    if campaign is None or str(bind["campaign"]) != str(campaign):
        raise AttRefusal(
            f"coex record was measured for campaign {bind['campaign']!r}, "
            f"not {campaign!r} — no cross-campaign replay")
    ts = _parse_utc(str(rec.get("measured_utc", "")))
    if ts is None:
        raise AttRefusal(
            f"measured_utc {rec.get('measured_utc')!r} is unparseable — the "
            "clock face must be a real instant, not a typed sentence")
    now = _parse_utc(now_utc) if now_utc else datetime.now(timezone.utc)
    if ts > now:
        raise AttRefusal(
            f"measured_utc {rec.get('measured_utc')!r} postdates the stamp "
            "— a future clock is a forgery vector, not a forecast")


def docker_inspect_probe(container_ids, image) -> dict:
    """The production T6 replay face: ask the daemon, per leg container,
    whether it ever existed and what it was launched from. A daemon that
    will not answer raises — the caller reads raises as refusal
    (no-silent-skip law); absence is spoken per id, never as a pass."""
    out = {}
    for cid in container_ids:
        cp = subprocess.run(
            ["docker", "inspect", "--format",
             "{{json .State}}\t{{json .Config.Image}}", cid],
            capture_output=True, text=True, timeout=60)
        if cp.returncode != 0:
            out[cid] = {"known": False}
            continue
        state_raw, _, cfg_raw = cp.stdout.partition("\t")
        try:
            state = json.loads(state_raw)
            config_image = json.loads(cfg_raw) if cfg_raw.strip() else ""
        except ValueError:
            out[cid] = {"known": False}
            continue
        out[cid] = {"known": True,
                    "config_image": str(config_image),
                    "started": str(state.get("StartedAt") or ""),
                    "finished": str(state.get("FinishedAt") or "")}
    return out


def _replay_ok(rec: dict, *, live_probe) -> None:
    """T6: the container ids the record names must answer the daemon, in
    agreement with the bound image, and a daemon that will not answer is a
    REFUSAL — never a silent pass."""
    probe = live_probe or docker_inspect_probe
    image = rec["bind"]["image"]
    ids = [leg["container_id"] for leg in rec["legs"]]
    try:
        seen = probe(ids, image)
    except Exception as exc:                        # noqa: BLE001 — any
        # daemon-side failure is a refusal, never a silent pass
        raise AttRefusal(
            f"live coex replay probe unreachable: {exc} — a daemon that will "
            "not answer is a refusal, never a silent pass")
    if not isinstance(seen, dict):
        raise AttRefusal("live coex replay spoke an unreadable face")
    for leg in rec["legs"]:
        cid = leg["container_id"]
        info = seen.get(cid)
        if not isinstance(info, dict) or info.get("known") is not True:
            raise AttRefusal(
                f"live coex replay: container {cid!r} is a phantom — the "
                "daemon does not know the leg the record claims")
        if str(info.get("config_image", "")) != str(image["ref"]):
            raise AttRefusal(
                f"live coex replay: container {cid!r} answers config image "
                f"{info.get('config_image')!r}, not the bound "
                f"{image['ref']!r}")
        for col in ("started", "finished"):
            if not str(info.get(col, "")):
                raise AttRefusal(
                    f"live coex replay: container {cid!r} reports no {col} "
                    "— an empty clock face is absence, not agreement")


def build_attestation(*, preflight_log, cell: str, epoch: str,
                      image_digest=None, campaign=None,
                      live_probe=None, now_utc=None) -> dict:
    """The two proofs as one block, or an AttRefusal with the spoken reason.

    The Phase-D mint context (image_digest, campaign, live_probe) is
    mandatory: the self-contained teeth re-derive the record's own face,
    only the mint can say which image/campaign it is being spent on and ask
    the daemon whether the legs were ever real."""
    pre = read_preflight_verdict(preflight_log, cell)
    if pre is None:
        raise AttRefusal(
            f"preflight quiet-gate verdict absent for cell {cell!r} — the "
            f"RB-08(3) GO/REFUSE record must exist in bytes (attestation "
            f"cannot be remembered, only read)")
    if pre.get("decision") != "GO":
        raise AttRefusal(f"preflight decision is {pre.get('decision')!r} "
                         f"for {cell!r} — a refused launch is not a measurement")
    raw = (os.environ.get(COEX_ENV) or "").strip()
    if not raw:
        raise AttRefusal(
            f"coex inversion-probe record absent ({COEX_ENV} unset) — parity "
            f"bytes may not be reported without the flatness qualifier")
    rec = _read_json(Path(raw))
    if rec is None:
        raise AttRefusal(f"coex-probe record absent or not parseable at {raw!r}")
    reason = coex_record_ok(rec)
    if reason is not None:
        raise AttRefusal(f"coex-probe record inadmissible: {reason}")
    _ledger_ok(Path(raw), rec)
    _context_ok(rec, image_digest=image_digest, campaign=campaign,
                now_utc=now_utc)
    _replay_ok(rec, live_probe=live_probe)
    return {"law": ATTEST_LAW, "preflight": pre, "coex_probe": rec,
            "epoch": epoch}


def stamp_witness(doc: dict, *, preflight_log, cell: str, epoch: str,
                  image_digest=None, campaign=None,
                  live_probe=None, now_utc=None) -> dict:
    """Attach the attestation to a minted witness — or DEFECT the mint with
    the reason. Returns a new document (immutability)."""
    try:
        block = build_attestation(
            preflight_log=preflight_log, cell=cell, epoch=epoch,
            image_digest=image_digest, campaign=campaign,
            live_probe=live_probe, now_utc=now_utc)
    except AttRefusal as exc:
        return {**doc, "verdict": "DEFECT",
                "reason": f"attestation refused: {exc}"}
    return {**doc, "attestation": block}


def label_null_face(doc: dict, *, reason: str, sanctioned: dict) -> dict:
    """The sanctioned null face (Phase-D Instrument B): the explicit,
    labelled DECLINE — never the key-absent accident. The witness carries
    "attestation": null plus this label, so the face is legible from its
    own bytes; reportability and the printed row stay identical to the
    pre-law face (the opt-out upgrades nothing). Returns a new document
    (immutability)."""
    if not isinstance(sanctioned, dict) or not str(sanctioned.get("ruling", "")):
        raise AttRefusal(
            f"null attestation face over reason {reason!r} without a "
            "sanctioned ruling row — the opt-out is controller data, not a "
            "lane option")
    return {**doc, "attestation": None,
            NULL_FACE_KEY: {"law": ATTEST_LAW, "reason": reason,
                           "ruling": str(sanctioned["ruling"]),
                           "face": str(sanctioned.get("face", "null/pre-law"))}}


# -- report side ---------------------------------------------------------------

def reportability(doc: dict, current_epoch: str) -> str | None:
    """Why this witness may not be reported, or ``None``. Pre-law witnesses
    (no attestation block at all) are admissible history — the O0
    re-derivation law forbids making the committed record unquotable."""
    att = doc.get("attestation")
    if att is None:
        return None
    if NULL_FACE_KEY in doc:
        # the sanctioned null label and an lv1 block on one witness is a
        # contradiction, checked here so the road is closed even when the
        # batteries are not the caller (no import of attestation_sanctions:
        # the one-way dependency runs the other direction)
        return ("witness speaks both the lv1 face and the sanctioned null "
                "label — the dual-face law admits one face per witness")
    if not isinstance(att, dict) or att.get("law") != ATTEST_LAW:
        return ("attestation block present but not a well-formed "
                f"{ATTEST_LAW!r} document — fields absent is a refusal, "
                "not a rounding")
    pre, co = att.get("preflight"), att.get("coex_probe")
    if not isinstance(pre, dict) or pre.get("decision") != "GO":
        return "attestation lacks a GO preflight quiet-gate verdict"
    if co is None:
        return "attestation lacks the coex inversion-probe verdict"
    co_reason = coex_record_ok(co)
    if co_reason is not None:
        # The A-extension (Phase-D): an embedded lv1 block is held to the
        # same teeth as the mint face — skipping the minter does not skip
        # the law. Committed pre-law witnesses never reach this line.
        return (f"attestation carries an inadmissible coex probe block: "
                f"{co_reason}")
    if str(att.get("epoch", "")) != str(current_epoch):
        return (f"attestation epoch {att.get('epoch')!r} is not the "
                f"adjudicated epoch {current_epoch!r} — epoch-mismatched "
                f"material is history, not a measurement")
    return None


def row_tokens(doc: dict, current_epoch: str) -> str:
    """The printed row's honesty stamp: the epoch the adjudication rides and
    the witness's own attestation state, spoken on every row."""
    att = doc.get("attestation")
    if isinstance(att, dict) and att.get("law") == ATTEST_LAW:
        pre = att.get("preflight") or {}
        co = att.get("coex_probe") or {}
        state = (f"lv1(preflight={pre.get('decision')!r},"
                 f"coex={co.get('verdict')!r},"
                 f"epoch={att.get('epoch')!r})")
    else:
        state = "pre-law"
    return f"epoch={current_epoch} attestation={state}"
