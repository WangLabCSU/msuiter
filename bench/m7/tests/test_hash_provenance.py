"""Group (O) test_hash_provenance -- explicit-algorithm hash-provenance gates.

RB-06 doctrine, encoded as executable law. Two failure modes produced the
RB-05 addendum confusion on the controller side: a SHA-1 tool's output was
compared against SHA-256 digests (algorithm conflation), and a remembered
control-vector constant was cited as ground truth without measuring it.
The seal is structural, not procedural:

  (1) every hash literal carried by the recipe family (Dockerfile, resolver,
      runner, registry rows, pins, the manifest itself) must be BACKED -- it
      re-measures from committed bytes with an explicitly-named algorithm
      implementation, or is parsed from a committed live-inspect JSON;
  (2) the manifest must carry a control-vector self-check -- the digest of
      the literal input 'abc' produced by the same recording tool -- so a
      tool mislabelling its own algorithm (the SHA-1-as-SHA-256 class) dies
      the lint on first contact;
  (3) the byte-pin triangle (committed runner == promoted witness ==
      Dockerfile assert constant == manifest role-claims) is re-derived from
      measurement on every suite run -- no re-typed constant anywhere in
      this file, and none needed.

Every expected digest below is MEASURED at test time; the tamper units
derive their defects from the measured values (last-hex-char mutations), so
this module could not survive a silent digest change anywhere upstream.
"""

from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import tools.audit_executed_surface_deps as audit               # noqa: E402

M7 = Path(__file__).resolve().parents[1]
REPO = M7.parents[1]
ADAPTERS = M7 / "adapters"
PILOT = M7.parents[1] / "bench" / "results" / "docker_m7_PILOT_20261008-200152"
REHEARSAL = PILOT / "rehearsal_slice3-r4"
MANIFEST_PATH = REHEARSAL / "rehearsal_manifest.json"
RUNNER = ADAPTERS / "run_sigminer.R"
WITNESS = REHEARSAL / "run_sigminer_fixed.R"
DOCKERFILE = ADAPTERS / "Dockerfile.sigminer"
TARBALL = REHEARSAL / "sigminer_2.3.1.tar.gz"


def _sha(data: bytes) -> str:
    """The explicit-algorithm recorder. Every expected value flows through
    here; no digest string is typed anywhere in this module."""
    return hashlib.sha256(data).hexdigest()


def _live_inputs() -> dict:
    """Measure the real tree into the dependency-injected shapes the gates
    consume (so every unit is pure and tamperable in memory)."""
    return {
        "runner_bytes": RUNNER.read_bytes(),
        "witness_bytes": WITNESS.read_bytes(),
        "dockerfile_text": DOCKERFILE.read_text(encoding="utf-8"),
        "manifest": json.loads(MANIFEST_PATH.read_text(encoding="utf-8")),
        "registry_digest": _registry_sigminer_digest(),
        "inspect_id": _r5_inspect_id(),
    }


def _registry_sigminer_digest() -> str:
    sys.path.insert(0, str(M7))
    from competitors import registry                       # noqa: E402
    return registry.load()["sigminer"].image_digest


def _r5_inspect_id() -> str:
    doc = json.loads((REHEARSAL / "image_inspect_slice3-r5_live.json")
                     .read_text(encoding="utf-8"))
    return doc[0]["Id"]


def _flip_last_hex(hexstr: str) -> str:
    """Mutate the final hex digit -- defects derived from measured values,
    never from typed constants."""
    digits = bytes(range(ord("0"), ord("9") + 1)).decode("ascii") + "abcdef"
    idx = max(i for i, ch in enumerate(hexstr) if ch in digits)
    return hexstr[:idx] + format(int(hexstr[idx], 16) ^ 1, "x") + hexstr[idx + 1:]


# -- (1) the byte-pin triangle ------------------------------------------------

def test_triangle_is_green_on_measured_live_inputs():
    assert audit.verify_byte_pin_triangle(**_live_inputs()) == []


def test_triangle_flags_a_tampered_dockerfile_constant():
    live = _live_inputs()
    truth = _sha(live["runner_bytes"])
    tampered = live["dockerfile_text"].replace(truth, _flip_last_hex(truth), 1)
    flags = audit.verify_byte_pin_triangle(**{**live, "dockerfile_text": tampered})
    assert [f["check"] for f in flags] == ["dockerfile-assert-constant"]


def test_triangle_flags_a_diverged_witness_copy():
    live = _live_inputs()
    flags = audit.verify_byte_pin_triangle(
        **{**live, "witness_bytes": live["witness_bytes"] + b"\n"})
    assert {f["check"] for f in flags} >= {"witness-vs-runner", "manifest-entry"}


def test_triangle_flags_registry_inspect_divergence():
    live = _live_inputs()
    flags = audit.verify_byte_pin_triangle(
        **{**live, "registry_digest": _flip_last_hex(live["registry_digest"])})
    assert [f["check"] for f in flags] == ["registry-vs-live-inspect"]


# -- (2) the provenance lint ---------------------------------------------------

def _lint_targets() -> dict[str, str]:
    files = {
        "Dockerfile.sigminer": DOCKERFILE,
        "install_sigminer.R": ADAPTERS / "install_sigminer.R",
        "run_sigminer.R": RUNNER,
        "registry.py": M7 / "competitors" / "registry.py",
        "test_registry.py": M7 / "tests" / "test_registry.py",
        "test_sigminer_api_contract.py": M7 / "tests" / "test_sigminer_api_contract.py",
        "rehearsal_manifest.json": MANIFEST_PATH,
        "self_witness.sh": ADAPTERS / "self_witness.sh",
    }
    return {k: p.read_text(encoding="utf-8") for k, p in files.items()}


def test_lint_is_green_on_the_live_recipe_family():
    live = _live_inputs()
    assert audit.lint_hash_provenance(targets=_lint_targets(),
                                      manifest=live["manifest"],
                                      repo_root=REPO) == []


def test_lint_requires_the_control_vector():
    live = _live_inputs()
    manifest = copy.deepcopy(live["manifest"])
    manifest.pop("control_vector")
    flags = audit.lint_hash_provenance(targets={"x": "no literals here"},
                                       manifest=manifest, repo_root=REPO)
    assert [f["check"] for f in flags] == ["control-vector"]


def test_lint_catches_the_sha1_as_sha256_confusion_class():
    # The exact RB-06(1) failure mode: a tool believing itself SHA-256 while
    # emitting SHA-1. The control vector makes it undetectable-by-omission
    # impossible: the recorded digest must be the TRUE sha256('abc').
    live = _live_inputs()
    manifest = copy.deepcopy(live["manifest"])
    manifest["control_vector"]["sha256"] = hashlib.sha1(b"abc").hexdigest()
    flags = audit.lint_hash_provenance(targets={"x": "clean"},
                                       manifest=manifest, repo_root=REPO)
    assert [f["check"] for f in flags] == ["control-vector"]


def test_lint_flags_an_unbacked_hash_literal():
    live = _live_inputs()
    orphan = _sha(b"synthetic-literal-probe-backed-by-nothing")
    targets = {**_lint_targets(),
               "synthetic.Dockerfile": f'RUN test x = "{orphan}"\n'}
    flags = audit.lint_hash_provenance(targets=targets, manifest=live["manifest"],
                                       repo_root=REPO)
    assert any(orphan in f["detail"] for f in flags), flags


def test_lint_flags_a_tampered_manifest_entry():
    live = _live_inputs()
    manifest = copy.deepcopy(live["manifest"])
    entry = manifest["entries"][0]
    entry["sha256"] = _flip_last_hex(entry["sha256"])
    targets = {k: v for k, v in _lint_targets().items()
               if k != "rehearsal_manifest.json"}
    flags = audit.lint_hash_provenance(targets=targets, manifest=manifest,
                                       repo_root=REPO)
    assert [f["check"] for f in flags] == ["manifest-entry-rehash"]
