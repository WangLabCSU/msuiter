#!/usr/bin/env python3
"""(AD) test_p6_yardstick -- the rust-NMF yardstick's build-input seals.

The yardstick (manifest :42) is the only route by which the paper's
rust-NMF speed claims become OUR measurements, so its provisioning is
sealed the same way the arm images are: the wheel is hash-pinned against
the banked fetch evidence (04-nmf-rs-fetch-probe-20261015), the upstream
index is spelled (no silent mirror fallback), and every byte the image
executes is pinned to its committed digest. The bake tool is text-sealed
against transcription: its digest can only arrive via inspect .Id echo.
Death #8 (2026-10-16) added the R-face seals: Biobase through the lane-
recorded contrib host, the version-tolerant NMF invocation, and the
asserted network-none brunet witness.
"""

from __future__ import annotations

import hashlib
import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
ADAPTERS = HERE / "adapters"
TOOLS = HERE / "tools"

WHEEL_SHA = ("93608cb2f4ab78c9ece2fcdc2b7feb14536f913db01e8f8cb4f18"
             "6a970c0eed3")


def _load(name: str):
    spec = importlib.util.spec_from_file_location(
        f"tests.{name}", str(HERE / "tests" / f"{name}.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _dockerfile_text() -> str:
    p = ADAPTERS / "Dockerfile.nmf_yardstick"
    if not p.is_file():
        raise AssertionError(f"yardstick image build input missing: {p}")
    return p.read_text(encoding="utf-8")


def test_wheel_is_hash_pinned_against_fetch_evidence():
    t = _dockerfile_text()
    assert f"--require-hashes sha256:{WHEEL_SHA}" in t, \
        "the wheel must be pip --require-hashes pinned to the banked digest"
    assert "pip install" in t and "--no-deps" in t, \
        "wheel provisioning must be single-package (--no-deps), never a resolve sweep"
    assert "--only-binary :all:" in t, \
        "sdist fallthrough would hash-fail the wheel-only policy"
    assert "--index-url https://pypi.org/simple" in t, \
        "the upstream index must be spelled (the configured mirror does not " \
        "sync nmf-rs; a silent mirror fallback is a provisioning lie)"
    assert "nmf-rs==0.1.0" in t, "the yardstick wheel version is frozen"


def test_image_byte_pins_the_executed_surface():
    t = _dockerfile_text()
    for rel in ("run_nmf_yardstick.py", "run_nmf_yardstick_leg.R",
                "yardstick_cell/matrix.csv"):
        sha = hashlib.sha256((ADAPTERS / rel).read_bytes()).hexdigest()
        assert sha in t, f"{rel} not byte-pinned in the yardstick Dockerfile"
        assert f"COPY {rel.split('/')[-1]} " in t or f"COPY {rel} " in t \
            or f"COPY {rel.split('/')[-1]}/ " in t or "yardstick_cell/" in t, \
            f"{rel} has no COPY line in the yardstick Dockerfile"


def test_bake_tool_cannot_transcribe_a_digest():
    p = TOOLS / "p6_build_yardstick.py"
    if not p.is_file():
        raise AssertionError(f"yardstick bake tool missing: {p}")
    t = p.read_text(encoding="utf-8")
    assert '{{.Id}}' in t, \
        "the yardstick digest must be captured from inspect .Id (SS3 law)"
    assert 'raise SystemExit(2)' in t or "SystemExit(2)" in t, \
        "the bake tool must die loudly on a malformed digest"
    # No hard-quotable sha256+64hex literal anywhere in the driver.
    bad = [m.group(0) for m in
           re.finditer(r'sha256:[0-9a-f]{64}', t)
           if "require-hashes" not in t[max(0, m.start() - 80):m.start()]]
    assert not bad, f"yardstick bake tool carries a transcribed digest: {bad}"


def test_r_leg_is_floor_safe_and_speaks_attestation():
    t = (ADAPTERS / "run_nmf_yardstick_leg.R").read_text(encoding="utf-8")
    assert "%||%" not in t, "R-floor platform-premise law: %||% is 4.4+"
    assert "|>" not in t, "R-floor platform-premise law: native pipe is 4.4+"
    assert 'value =' not in t.replace("value=", ""), \
        "renamed-R base quirk: grepl value= must not appear"
    assert "YARDS r_seconds=" in t and "r_niter=" in t and "r_version=" in t, \
        "the R leg must attest seconds, stop-iteration count, and NMF version"
    assert "proc.time" in t, "timing idiom must match the arm runners"


def test_runner_fixture_pin_mirrors_the_committed_bytes():
    t = (ADAPTERS / "run_nmf_yardstick.py").read_text(encoding="utf-8")
    m = re.search(r'FIXTURE_SHA = "([0-9a-f]{64})"', t)
    assert m, "the runner must name its fixture pin as a constant"
    real = hashlib.sha256(
        (ADAPTERS / "yardstick_cell" / "matrix.csv").read_bytes()).hexdigest()
    assert m.group(1) == real, \
        f"runner pin {m.group(1)} drifts from committed bytes {real}"
    assert "committed fixture bytes drifted" in t, \
        "fixture drift must be a hard death, not a silent remeasure"


def test_fairness_is_fixed_iteration_on_both_sides():
    py = (ADAPTERS / "run_nmf_yardstick.py").read_text(encoding="utf-8")
    r = (ADAPTERS / "run_nmf_yardstick_leg.R").read_text(encoding="utf-8")
    assert "stop=\"max_iter\"" in py, \
        "rust leg must run the fixed iteration count, not converge-and-quit"
    assert "eps = 0" in r, \
        "R leg must neutralise the improvement rule (eps=0) for the same reason"
    assert "num_threads=threads" in py and "threads" in py, \
        "rust leg must pin its thread count (co-tenancy law)"
    assert "rust_niter" in py and "r_niter" in py and "fairness_flag" in py, \
        "per-side stop-iteration attestations must be reported, not assumed"


# ---------------------------------------------------------------- death #8
# The CRAN-only NMF layer died: "dependency 'Biobase' is not available".
# Biobase is a Bioconductor-class package the lane resolves through the
# recorded contrib host (same source that served the arm trees, probes
# 3/6); the yardstick now provisions it through a committed, result-gated
# script. These units seal that repair -- the same shape the arm build
# seals its resolver.
_PROV = "install_nmf_yardstick.R"


def test_r_face_provisions_biobase_from_the_recorded_contrib():
    p = ADAPTERS / _PROV
    if not p.is_file():
        raise AssertionError(f"R-face provisioning script missing: {p}")
    t = p.read_text(encoding="utf-8")
    assert "https://bioconductor.org/packages/3.17/bioc/src/contrib" in t, \
        ("Biobase must resolve through the lane-recorded contrib host "
         "(install_sigminer.R BIOC_CONTRIB -- the only bioc source this mirror serves)")
    assert "PACKAGES.gz" in t and "tries" in t, \
        ("the index is fetched by hand (R's repo machinery fetches zero rows "
         "here) and every URL carries per-URL retries (§9b flakiness)")
    assert "install not result-gated" in t, \
        ("a node counts as provisioned only when the library's own "
         "DESCRIPTION reports the version -- the recorded result-gate")
    assert '"BiocGenerics"' in t and '"Biobase"' in t, \
        "the measured contrib closure (BiocGenerics under Biobase) must install deps-first"
    assert '"0.28"' in t and '"2.60.0"' in t, \
        ("the provisioning is version-gated: CRAN-current drift is a build "
         "death, so a re-bake reproduces the attested pair or dies loudly")
    assert "%||%" not in t and "|>" not in t, \
        "R-floor platform-premise law: 4.4-only operators on a 4.3 base"
    d = _dockerfile_text()
    sha = hashlib.sha256(p.read_bytes()).hexdigest()
    assert sha in d and f"COPY {_PROV} " in d, \
        "the provisioning script is executed surface: byte-pinned and COPYed"


def test_r_leg_survives_the_current_nmf_signature():
    t = (ADAPTERS / "run_nmf_yardstick_leg.R").read_text(encoding="utf-8")
    assert "do.call" in t and "formals(NMF::nmf" in t, \
        ("the call must pass through a do.call filtered against the formals -- "
         "NMF 0.28 dropped backup/silent from the brunet bootstrap's accepted set")
    assert "unused argument" in t, \
        "the arg-repair loop must heal exactly what the method refuses, by message"
    assert "r_dropped=" in t, \
        "dropped arguments are attestation data, not silence"


def test_network_none_witness_asserts_the_measured_fit():
    t = _dockerfile_text()
    assert "identical(NMF::niter(r), 5L)" in t, \
        ("the network-none witness must assert the fit actually iterated to "
         "the fixed stop (niter 5), the way the measured probe attests it")
    m = re.search(r'RUN --network=none Rscript -e \'.*?NMF.*?\'', t, re.DOTALL)
    assert m and "backup" not in m.group(0) and "silent" not in m.group(0), \
        "the witness must speak the version-tolerant invocation, not the 2023 shape"


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(vars().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  PASS {name}")
            except Exception as exc:
                fails += 1
                print(f"  FAIL {name}: {exc}")
    raise SystemExit(1 if fails else 0)
