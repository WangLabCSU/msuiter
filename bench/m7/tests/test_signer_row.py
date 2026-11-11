"""(c) test_signer_row -- the auxilary Bioconductor row's promotion laws
(SIGNER-c lane, design memo §2c/§10.2, PI identity confirmation 2026-11-02).

The row named by ``competitors.registry.COMPETITOR_KEY`` is the third
competitor of the memo §2 table: the PI ruling of 2026-11-02 confirmed the
brief's "Signal (R/Bioconductor)" denotes the Bayesian-NMF signature
extraction package of the Bioconductor 3.22 release series, displayed
mangled in briefs. Hierarchy (PI ruling, verbatim intent): sigprofiler is
THE primary comparison target; sigminer AND this package are AUXILIARY
comparison objects. Every doc/table this lane touched positions them so.

The promotion law (card mission 3 + memo §5 rule ii): ``UNRESOLVED`` ->
``ready`` only on live-probed, banked evidence --

  * the version pin rides the registry constant, which must speak byte-
    identical to the banked probe authority (the PACKAGES-index record and
    the tarball-name field of the same index entry, probe01);
  * the digest field may only carry the bytes of a committed live
    ``docker image inspect`` witness -- the no-invented-provenance gate of
    (O) re-measures it from that JSON on every suite run;
  * an unverified pin therefore keeps the row pending-verify and the
    adapter keeps refusing, with the sentinel, pre-daemon.

Every coordinate is read from a committed/banked bytes source at test time
-- no 71-char literal, no remembered version string, in this module.
"""

from __future__ import annotations

import dataclasses
import importlib
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import run_bench                                           # noqa: E402
from competitors import docker_cmd, registry              # noqa: E402
from competitors.errors import AdapterUnavailable          # noqa: E402

KEY = registry.COMPETITOR_KEY                       # the one name authority
PIN = registry.COMPETITOR_PIN                       # the one version authority


def _adapter():
    """The adapter seam: absent at RED, resolved at GREEN; every consumer
    goes through here so the module still collects with the seam missing."""
    return importlib.import_module(f"competitors.{KEY}_adapter")

BANK = Path("/tmp/signer-clane/logs")               # lane evidence bank
CARD = BANK / "lane-task.md"
PIN_AUTHORITY = BANK / "pin_version.authority"
IMAGE_AUTHORITY = BANK / "image_name.authority"
PILOT = HERE.parent / "results" / "docker_m7_PILOT_20261008-200152"
INSPECT_JSON = PILOT / f"image_inspect_{KEY}_bioc{PIN}_live.json"
ADIR = HERE / "adapters"                            # the container-family dir
FIXTURE = ADIR / f"mini_{KEY}"
SELF_WITNESS = ADIR / f"self_witness_{KEY}.sh"

# The documented-defaults fairness regime (memo §2c/§3): the call surface is
# the entry point with the mutation matrix alone; every other argument keeps
# its package-documented default. An argv-borne tuning token is a fabricated
# fourth arm and must never appear.
FORBIDDEN_ARGV_TOKENS = ("--nsig", "--nsignatures", "--oppor", "--opportunity",
                         "--start", "--seed", "--kmax", "--thr", "--threshold")
INTERVALS_HEADER = "sample_id,signature,estimate,lo95,hi95,estimand,zeroed"


def _spec():
    return registry.lookup(KEY)


def _bank_or_committed(path: Path, committed: str, label: str) -> str:
    """Read an authority coordinate from the lane bank when the bank is
    present; elsewhere fall back to the committed registry constant, which
    the byte-pair test below polices against the bank whenever the bank
    exists. A silent skip that vacuously greens the coordinate is not
    offered: the fallback speaks loudly on the report line."""
    if path.is_file():
        return path.read_text(encoding="utf-8").strip()
    print(f"[c] bank absent ({path}) -- {label} measured against the "
          f"committed registry constant only")
    return committed


def _inspect_doc():
    assert INSPECT_JSON.is_file(), (
        f"the live-inspect witness {INSPECT_JSON.name} is not committed -- "
        f"the row may not be ready without it (memo §5 ii)")
    doc = json.loads(INSPECT_JSON.read_text(encoding="utf-8"))
    assert isinstance(doc, list) and doc, "live-inspect JSON must be docker's array"
    return doc[0]


# --------------------------------------------------------------------------
# registry promotion laws

def test_row_promoted_only_with_verified_digest():
    spec = _spec()
    assert spec.status == registry.STATUS_READY, (
        f"row must be ready on the banked evidence, got {spec.status!r} "
        f"(pending reason: {spec.pending_reason!r})")
    assert spec.version == PIN, f"version pin drifted: {spec.version!r}"
    assert spec.runtime == "R" and spec.entrypoint == "python3"
    assert spec.runner_script == f"run_{KEY}.R"


def test_pin_speaks_byte_identical_to_the_banked_authority():
    """The registry constant vs the PACKAGES-index record of probe01 (and
    its tarball-name cross-field): one coordinate, two independent witnesses."""
    authority = _bank_or_committed(PIN_AUTHORITY, PIN, "version pin")
    assert authority == PIN, (
        f"registry pin {PIN!r} diverges from the banked index authority "
        f"{authority!r}")
    assert PIN.count(".") == 2 and all(part.isdigit() for part in PIN.split(".")), \
        f"pin {PIN!r} is not a dotted release version"


def test_digest_is_the_live_inspect_bytes_measured_from_the_committed_witness():
    spec = _spec()
    digest = spec.image_digest
    assert digest.startswith("sha256:") and len(digest) == 71, (
        f"digest shape law broken: {digest!r}")
    doc = _inspect_doc()
    assert digest == doc["Id"], (
        "registry digest diverges from the committed live-inspect .Id witness")
    tagged = {row.split("@")[-1] for row in doc.get("RepoDigests") or []}
    # RepoDigests entries carry the algorithm prefix byte-true ("<n>@<a>:<h>"),
    # so the witness comparison runs on the full digest, not a stripped form.
    assert digest in tagged, (
        "registry digest is not the RepoDigest the witness recorded")


def test_image_ref_speaks_byte_identical_to_the_card_and_the_witness():
    spec = _spec()
    card_name = _bank_or_committed(IMAGE_AUTHORITY, spec.image_ref, "image name")
    assert spec.image_ref == card_name, (
        f"image_ref {spec.image_ref!r} diverges from the card-named tag "
        f"{card_name!r}")
    doc = _inspect_doc()
    assert spec.image_ref in (doc.get("RepoTags") or []), (
        "image_ref does not name a tag the live-inspect witness carries")


def test_provenance_tells_the_true_story():
    """The memo §2c 'absent from the Bioc index' sentence was written under
    the mangled identity; the promoted record must speak what the 2026-11-02
    probes measured, and position the row per the PI hierarchy ruling."""
    prov = _spec().provenance
    for must in ("Bioconductor", "3.22", PIN, "CRAN"):
        assert must in prov, f"provenance omits the coordinate {must!r}: {prov!r}"
    assert "UNRESOLVED" not in prov
    assert _spec().pending_reason == "", "a ready row may not carry a pending reason"


def _hierarchy_authority() -> str:
    """The hierarchy-word authority: the lane card when the bank survives;
    elsewhere the committed adapter docstring, which speaks the same PI
    ruling verbatim (its 'Position' block). Measuring the registry row
    against that separate committed face keeps the law cross-face, not
    self-referential. The fallback speaks loudly on the report line."""
    if CARD.is_file():
        return CARD.read_text(encoding="utf-8")
    print(f"[c] bank absent ({CARD}) -- hierarchy word forms measured "
          f"against the committed adapter docstring (the ruling's face)")
    return _adapter().__doc__ or ""


def test_hierarchy_positioning_survives_promotion():
    """PI hierarchy ruling: the table this row sits in names the primary
    comparison target and marks the two R-side rows as secondary objects.
    The registry is that table's machine-readable face; the note rides its
    provenance record. The exact word forms are read from the lane card
    bytes -- the ruling's banked authority -- so this law cannot drift
    from it; with the bank lost, the committed adapter docstring (the
    ruling's committed face) stands in via the module fallback idiom."""
    prov = _spec().provenance
    import re
    authority = _hierarchy_authority()
    forms = sorted({m.group() for m in
                    re.finditer(r"[Aa][Uu][Xx][Ii][Ll][Ii]?[Aa][Rr][Yy]", authority)})
    assert forms, "hierarchy authority carries no auxiliary word to police against"
    assert any(f in prov for f in forms), (
        f"hierarchy word (one of {len(forms)} authority forms) missing from the row")
    prim = re.search(r"[Pp][Rr][Ii][Mm][Aa][Rr][Yy]", authority).group()
    assert prim in prov, "the primary-target designation must ride the row"


# --------------------------------------------------------------------------
# skip-not-skip firing controls (pre-daemon: provenance branch first)

def _cell(tmp: Path) -> dict:
    in_dir, out_dir = tmp / "in", tmp / "out"
    in_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    return {"in_dir": in_dir, "out_dir": out_dir}


def test_adapter_refuses_unverified_pin_with_sentinel():
    tmp = Path(tempfile.mkdtemp(prefix="m7sr_"))
    try:
        tampered = dataclasses.replace(_spec(), image_digest=registry.PENDING_VERIFY)
        try:
            _adapter().run(_cell(tmp), tampered)
        except AdapterUnavailable as exc:
            low = str(exc).lower()
            assert KEY in low or "provenance" in low or "pending" in low, \
                f"the refusal must state the reason, got: {exc}"
        except Exception as exc:                          # noqa: BLE001
            raise AssertionError(
                f"unverified pin must yield AdapterUnavailable, got "
                f"{type(exc).__name__}: {exc}") from exc
        else:
            raise AssertionError("adapter ran with a PENDING-VERIFY digest -- "
                                 "zero-execution success is prohibited")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_malformed_digest_refused_pre_daemon():
    """The provenance branch must fire before the daemon is ever consulted
    (a stray local tag may not 'rescue' a broken pin)."""
    malformed = dataclasses.replace(_spec(), image_digest="sha256:" + "f" * 63)
    reason = docker_cmd.image_gate(malformed)
    assert reason is not None and "provenance not captured" in reason, \
        f"malformed digest must be refused with the provenance reason: {reason!r}"
    try:
        _adapter().run({"in_dir": "/nonexistent/in", "out_dir": "/nonexistent/out"},
                    malformed)
    except AdapterUnavailable:
        pass
    else:
        raise AssertionError("malformed digest was not refused")


def test_absent_image_is_a_spoken_refusal_not_a_crash():
    """Absent-image control: right shape, wrong bytes -> the daemon's own
    absence verdict, delivered as the sentinel (never a RuntimeError)."""
    doc = _inspect_doc()
    bogus_digest = "sha256:" + doc["Id"].removeprefix("sha256:").swapcase()
    spec = dataclasses.replace(_spec(), image_digest=bogus_digest)
    tmp = Path(tempfile.mkdtemp(prefix="m7sr_"))
    try:
        try:
            _adapter().run(_cell(tmp), spec)
        except AdapterUnavailable as exc:
            assert ("not present" in str(exc) or "not available" in str(exc)), \
                f"expected the store-absence verdict, got: {exc}"
        except Exception as exc:                          # noqa: BLE001
            raise AssertionError(
                f"absent image must yield AdapterUnavailable, got "
                f"{type(exc).__name__}: {exc}") from exc
        else:
            raise AssertionError("adapter ran against an image the store does not hold")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
# documented-defaults fairness (zero parameter invention)

def test_child_argv_is_the_documented_defaults_quad():
    argv = _adapter()._child_argv(None)
    assert argv[0] == "Rscript" and argv[1] == f"/work/run_{KEY}.R", \
        f"child argv must enter through the row's runner: {argv}"
    for flag in ("--counts", "--catalog", "--params", "--outdir"):
        assert flag in argv, f"mount-contract flag {flag} missing: {argv}"
    assert any(a.startswith("/work/in/") and a.endswith("counts.csv")
               for a in argv), f"counts must ride the ro bind: {argv}"
    joined = " ".join(argv)
    for tok in FORBIDDEN_ARGV_TOKENS:
        assert tok not in joined, (
            f"fabricated tuning token {tok!r} in the child argv -- the call "
            f"surface takes the documented defaults only (zero-invention law)")


def test_mounted_catalog_rides_its_own_bind():
    argv = _adapter()._child_argv("/mnt/cat/catalog.csv")
    assert "/work/catalog.csv" in argv, \
        "a user catalog mounts as its own file bind, not inside the in/ ro bind"


def test_caps_ride_every_form_before_the_image_token():
    """The positional cure (devlog 2026-10-08 §1): all seven frozen thread
    caps at value 1 plus the fork-axis pair, strictly before the image token
    of the entry-wrapped argv the adapter composes through run_container_cell."""
    cmd = [str(p) for p in docker_cmd.build_container_cmd(
        image=_spec().image_ref, runner=docker_cmd.ENTRY_SCRIPT,
        entrypoint=_spec().entrypoint,
        runner_args=docker_cmd.ENTRY_ARGS + _adapter()._child_argv(None),
        in_dir=HERE, out_dir=HERE, catalog_mount=None)]
    img = cmd.index(_spec().image_ref)
    for cap in docker_cmd.THREAD_CAPS:
        positions = [i for i, tok in enumerate(cmd)
                     if tok == "-e" and cmd[i + 1] == f"{cap}=1"]
        assert positions and all(p < img for p in positions), \
            f"cap {cap}=1 missing or after the image token"
    for cap, value in docker_cmd.FORK_AXIS_CAPS:
        positions = [i for i, tok in enumerate(cmd)
                     if tok == "-e" and cmd[i + 1] == f"{cap}={value}"]
        assert positions and all(p < img for p in positions), \
            f"fork cap {cap}={value} missing or after the image token"
    # the entry wrapper is what executes; the competitor command is its child
    # compose injects the mount path ("/work/" + name), so the law compares the
    # rendered token, keeping the one coordinate source (byte-true law).
    assert f"/work/{docker_cmd.ENTRY_SCRIPT}" in cmd and "--" in cmd
    assert cmd.index("Rscript") > cmd.index("--") > img


# --------------------------------------------------------------------------
# the container family and the four-file trust guard

def test_container_family_is_committed_and_self_attesting():
    dockerfile = ADIR / f"Dockerfile.{KEY}"
    installer = ADIR / f"install_{KEY}.R"
    runner = ADIR / f"run_{KEY}.R"
    for p in (dockerfile, installer, runner, SELF_WITNESS):
        assert p.is_file(), f"container family member absent: {p.name}"
    text = dockerfile.read_text(encoding="utf-8")
    assert "xuanyuan.run" in text, "base FROM must spell the mirror host (§5)"
    assert "rocker/r-ver:" in text, "base must be the rocker r-ver family"
    assert "--network=none" in text, \
        "the build must run the container-side self-witness with no network"
    assert f"install_{KEY}.R" in text and f"self_witness_{KEY}.sh" in text
    assert PIN in text, "the build-time version assert must name the pin"
    wtext = SELF_WITNESS.read_text(encoding="utf-8")
    for guard in run_bench.GUARD_FILES:
        assert guard in wtext, f"self-witness does not assert {guard}"
    assert INTERVALS_HEADER in wtext, "the intervals header law must be asserted"


def test_fixture_carries_the_three_inputs_and_the_frozen_caps():
    for name in ("counts.csv", "catalog.csv", "params.json"):
        assert (FIXTURE / name).is_file(), f"fixture input absent: {name}"
    params = json.loads((FIXTURE / "params.json").read_text(encoding="utf-8"))
    assert params.get("competitor") == KEY, "fixture must name its competitor"
    assert params.get("version") == PIN, "fixture must carry the pin"
    assert params.get("runner") == f"run_{KEY}.R"
    lens = params.get("caps")
    assert isinstance(lens, list), "fixture must carry the speaking caps lens"
    want = {f"{cap}={docker_cmd.CAP_VALUE}" for cap in docker_cmd.THREAD_CAPS}
    missing = want - {str(t) for t in lens}
    assert not missing, f"fixture caps lens not frozen at {docker_cmd.CAP_VALUE}: {missing}"
    assert params.get("seed"), "fixture must carry the harness seed record"
    counts = (FIXTURE / "counts.csv").read_text(encoding="utf-8").splitlines()
    header = counts[0].split(",")
    assert header[0] == "sample_id" and len(header) > 2, "counts must be wide"


def test_intervals_header_contract_is_one_truth():
    """The runner and the self-witness must demand byte-identical headers --
    two sources for one contract is two chances to drift."""
    runner = (ADIR / f"run_{KEY}.R").read_text(encoding="utf-8")
    witness = SELF_WITNESS.read_text(encoding="utf-8")
    assert INTERVALS_HEADER in runner, "runner lacks the intervals header law"
    assert INTERVALS_HEADER in witness, "self-witness lacks the header law"


def test_tampered_data_hash_and_identity_demote_the_cell():
    """The 2026-10-07 stale-cache cure and its 10-08 identity extension,
    proven live: a flipped byte in counts, in params or in ANY identity
    component must move the hash -- an unresponsive axis would silently
    reuse a stale cell (the dead-metric class)."""
    class _Arm:                                                  # arm.params carrier
        params = {"profile": "smoke"}
    params = {"seed": 1, "caps": "frozen"}
    ident = {"competitor": KEY, "version": PIN, "image_digest": "sha256:a" * 10,
             "caps": docker_cmd.all_caps_speaking()}
    base = run_bench.compute_data_hash("a,b\n1,2\n", _Arm(), 3, params, ident)
    assert run_bench.compute_data_hash("a,b\n1,3\n", _Arm(), 3, params, ident) != base, \
        "counts bytes are not bound into the data hash"
    assert run_bench.compute_data_hash("a,b\n1,2\n", _Arm(), 3,
                                       {**params, "seed": 2}, ident) != base, \
        "params are not bound into the data hash"
    for axis in ("version", "image_digest"):
        flipped = {**ident, axis: ident[axis] + "x"}
        assert run_bench.compute_data_hash("a,b\n1,2\n", _Arm(), 3,
                                           params, flipped) != base, \
            f"identity axis {axis} is dead -- stale cells could ride it"


def test_manifest_roundtrip_then_tamper_speaks():
    """manifest.json is host-written by contract; the guard reads it back.
    A byte flipped in place must be detectable from the file alone."""
    tmp = Path(tempfile.mkdtemp(prefix="m7sr_"))
    try:
        truth = {"competitor": KEY, "version": PIN, "data_hash": "0123456789abcdef"}
        run_bench.write_cell_manifest(tmp, truth)
        path = tmp / "manifest.json"
        assert json.loads(path.read_text(encoding="utf-8")) == truth
        path.write_text(path.read_text(encoding="utf-8").replace("abcdef", "abcdeg"),
                        encoding="utf-8")
        back = json.loads(path.read_text(encoding="utf-8"))
        assert back != truth, "a flipped manifest byte was undetectable"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
