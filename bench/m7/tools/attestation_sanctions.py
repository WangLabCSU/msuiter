"""The sanctioned null-attestation faces (Phase-D Instrument B, controller
ruling 2026-11-04 (2)).

The minter's no-stamp route is DATA-GATED, not flag-gated: the only reasons
that may ride it are the entries below, each citing the controller ruling
that adopted it. Forgetting the flag DEFECTS the mint loudly (the default
is the stamp); reaching the null face requires speaking the mode AND a key
this registry recognises -- an opt-out is a ruling, never a lane option.

The registry pairs with the ledger law (ledger_post_law_ok) and the
witness-face law (dual_face_ok): what the minter writes, the batteries
re-check, from this one source.
"""

from __future__ import annotations

import tools.attestation as att                          # noqa: E402 (one-way)

#: Ledgers created at or after this instant must declare their attestation
#: face (calibrate_p6_floors CALIBRATION.json); earlier committed ledgers
#: predate the ruling and stay exempt -- bytes are not retroactively
#: demanded of the past (the same law that keeps the 375 quotable).
ATTEST_MODE_LAW = "2026-11-04T00:00:00+00:00"

#: The ruled faces. An edit here is an edit to the controller's word;
#: test_null_face_route pins this set byte-exactly as its tripwire.
SANCTIONED_NULL_FACES = {
    "sigminer_post_v3_rust_batch": {
        "ruling": "controller ruling 2026-11-04 (2) -- batch-bridge "
                  "no-stamp route, Phase-D Instrument B",
        "face": "null/pre-law",
        "note": "the batch-bridge comparison face rides the same face as "
                "the 147-row comparison base; the co-tenancy qualifier "
                "arrives with the arm's own campaign, not this lane",
    },
}


def sanction_ok(reason):
    """The ruling behind a null-face reason, or ``None``. The key is
    exact -- no prefix, no fuzz."""
    row = SANCTIONED_NULL_FACES.get(reason if isinstance(reason, str) else "")
    return dict(row) if row is not None else None


def dual_face_ok(doc: dict) -> str | None:
    """Why this witness speaks its attestation face unlawfully, or ``None``.

    One witness, one face: the lv1 block OR a sanctioned null label, never
    both, never an orphan label without the ruling behind it. The key-
    absent face (the committed 375) carries neither marker and is outside
    the law entirely."""
    has_block = "attestation" in doc and doc["attestation"] is not None
    label = doc.get(att.NULL_FACE_KEY)
    if has_block and label is not None:
        return ("witness speaks both faces — the lv1 block and a null "
                "attestation label are mutually exclusive (Phase-D dual-face law)")
    if label is not None:
        if not isinstance(label, dict):
            return "null_attestation_face is not a label object"
        if sanction_ok(str(label.get("reason", ""))) is None:
            return (f"null attestation face without a sanctioned ruling: "
                    f"reason {label.get('reason')!r} is not in "
                    "SANCTIONED_NULL_FACES")
    return None


def ledger_post_law_ok(ledger: dict) -> str | None:
    """Why this CALIBRATION ledger fails the post-ruling declaration law,
    or ``None``. Pre-law ledgers walk untouched; post-law ledgers declare
    live or none-with-reason with the sanction booked."""
    created = str(ledger.get("created_utc", ""))
    if not created or created < ATTEST_MODE_LAW:
        return None
    mode = ledger.get("attestation_mode")
    if mode not in ("live", "none-with-reason"):
        return (f"post-law ledger declares attestation_mode {mode!r} — "
                "the mint face must be declared, not assumed")
    if mode == "none-with-reason":
        san = ledger.get("attestation_sanction")
        key = str((san or {}).get("key", "")) if isinstance(san, dict) else ""
        if sanction_ok(key) is None:
            return (f"none-with-reason ledger books sanction key {key!r} — "
                    "no such ruling in SANCTIONED_NULL_FACES")
    return None
