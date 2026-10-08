"""② adapter refuse-to-run seam + frozen thread-cap injection (U-M7-02 §2/§4.2).

The skip-not-skip protocol (G0 idiom): a competitor that cannot run must
raise the explicit ``competitors.errors.AdapterUnavailable`` sentinel with a
reason — never a generic crash, never a zero-execution "success", never a
silent pass. The existence of the refusal itself is under test.

Thread caps: every composed docker command must inject the frozen caps as
``-e CAP=1`` **before the image token** — the positional cure for the G0
over-subscription OOM storm (devlog 2026-10-08 §1, fix 333f06e).
"""

from __future__ import annotations

import dataclasses
import importlib
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
import sys
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import docker_cmd, registry                     # noqa: E402 (RED seams)
from competitors.errors import AdapterUnavailable                # noqa: E402 (RED seam)

CAPS_REQUIRED = {"OMP_NUM_THREADS", "R_LIMIT_THREADS",
                 "GOMAXPROCS", "MSUITER_THREADS"}   # devlog 2026-10-08 cure list


def _tmp() -> Path:
    return Path(tempfile.mkdtemp(prefix="m7ad_"))


def _cleanup(tmp: Path):
    shutil.rmtree(tmp, ignore_errors=True)


def _cell(tmp: Path) -> dict:
    """Minimal cell reference per the §1 mount contract."""
    in_dir, out_dir = tmp / "in", tmp / "out"
    in_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    return {"in_dir": in_dir, "out_dir": out_dir}


def test_missing_pinned_image_refuses_with_sentinel():
    """An adapter asked to run on a spec whose image is not in the local
    image store must raise AdapterUnavailable — not fabricate results."""
    reg = registry.load()
    fake = dataclasses.replace(reg["sigminer"],
                               image_ref="m7-absent-for-test:never-built",
                               image_digest="PENDING-VERIFY")
    for competitor in ("sigminer", "sigprofiler"):
        mod = importlib.import_module(f"competitors.{competitor}_adapter")
        tmp = _tmp()
        try:
            try:
                mod.run(_cell(tmp), fake)
            except AdapterUnavailable:
                pass                                   # the required behaviour
            except Exception as e:                     # noqa: BLE001
                raise AssertionError(
                    f"{competitor}: absent image must yield AdapterUnavailable,"
                    f" got {type(e).__name__}: {e}") from e
            else:
                raise AssertionError(
                    f"{competitor}: adapter ran with an absent image — "
                    f"zero-execution success is prohibited (skip-not-skip)")
        finally:
            _cleanup(tmp)


def test_pending_verify_provenance_refuses_even_with_docker_present():
    """Signal: registry probe could not resolve its provenance (§2c). Its
    adapter must refuse unconditionally until the PI supplies coordinates."""
    mod = importlib.import_module("competitors.signal_adapter")
    spec = registry.load()["signal"]
    assert spec.status == "pending-verify"
    tmp = _tmp()
    try:
        try:
            mod.run(_cell(tmp), spec)
        except AdapterUnavailable as e:
            low = str(e).lower()
            assert "pending-verify" in low or "provenance" in low, \
                f"refusal must state the reason, got: {e}"
        except Exception as e:                          # noqa: BLE001
            raise AssertionError(
                f"signal: pending-verify must yield AdapterUnavailable, "
                f"got {type(e).__name__}: {e}") from e
        else:
            raise AssertionError("signal adapter ran despite pending-verify "
                                 "provenance")
    finally:
        _cleanup(tmp)


def test_thread_caps_frozen_and_injected_before_image_token():
    """§4.2: the G0 closure cap list ⊆ frozen THREAD_CAPS, and composed
    commands carry every cap as -e CAP=1 strictly before the image token."""
    caps = set(docker_cmd.THREAD_CAPS)
    missing = CAPS_REQUIRED - caps
    assert not missing, f"THREAD_CAPS lost the OOM-storm cure caps: {missing}"
    tmp = _tmp()
    try:
        cmd = [str(p) for p in docker_cmd.build_container_cmd(
            image="m7-fake:pinned", runner="run_fake.py",
            in_dir=tmp / "in", out_dir=tmp / "out", catalog_mount=None)]
    finally:
        _cleanup(tmp)
    img = cmd.index("m7-fake:pinned")
    for cap in sorted(caps):
        positions = [i for i, tok in enumerate(cmd)
                     if tok == "-e" and i + 1 < len(cmd) and cmd[i + 1] == f"{cap}=1"]
        assert positions, f"cap {cap}=1 not injected via -e: {cmd}"
        assert all(p < img for p in positions), \
            f"cap {cap} injected after image token — positional cure violated"
