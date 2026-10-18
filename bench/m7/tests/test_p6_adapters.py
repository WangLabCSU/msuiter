"""Group (Z) test_p6_adapters — per-arm container adapters honour the
measurement contract without touching the frozen 2.3.1 runner.

The legacy Dockerfile byte-pins run_sigminer.R (live tripwire); therefore the
P6 arms ride a NEW sibling runner /work/run_sigminer_arm.R and each arm gets
its thin adapter module competitors/<tool>_adapter.py, which composes the
child argv. Pinned here: argv shape, the --backend passthrough that is the
ONLY behavioural difference between an arm's two faces, the zero-threshold-
override law (the fairness regime's one lever is the thread caps injected by
docker_cmd — an argv-borne tuning token is a forbidden fourth arm), and the
skip-not-skip AdapterUnavailable path.
"""

from __future__ import annotations

import dataclasses
import importlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import docker_cmd, registry        # noqa: E402
from competitors import p6_arms                     # noqa: E402  (RED-by-absence)
from competitors.errors import AdapterUnavailable   # noqa: E402

ARM_RUNNER = "/work/run_sigminer_arm.R"
FORBIDDEN_TOKENS = ("--threshold", "--nsim", "--kmax", "--nfit", "--seed0")


def _adapter(tool: str):
    return importlib.import_module(f"competitors.{tool}_adapter")


def test_every_p6_arm_has_an_adapter_module():
    for tool in p6_arms.P6_ARM_SPECS:
        try:
            mod = _adapter(tool)
        except ModuleNotFoundError as exc:
            raise AssertionError(f"{tool}: adapter module absent ({exc})") from exc
        for attr in ("run", "_child_argv"):
            assert callable(getattr(mod, attr, None)), f"{tool}.{attr} missing"


def test_child_argv_shape_and_backend_passthrough():
    for tool, arm in p6_arms.P6_ARM_SPECS.items():
        argv = _adapter(tool)._child_argv(None)
        argv_mounted = _adapter(tool)._child_argv("/mnt/cat/catalog.csv")
        assert argv[0] == "Rscript", f"{tool}: child argv must start with Rscript"
        assert ARM_RUNNER in argv, (
            f"{tool}: the arm runner must be {ARM_RUNNER} (the 2.3.1 runner is "
            f"byte-frozen; reusing its path would fight the Dockerfile tripwire)")
        assert "--backend" in argv, f"{tool}: missing --backend passthrough"
        want = arm["face"]
        assert argv[argv.index("--backend") + 1] == want, (
            f"{tool}: face {want!r} not forwarded verbatim")
        # mount contract identical to the legacy adapter
        assert "--catalog" in argv, f"{tool}: --catalog seam missing"
        assert any(a.endswith("catalog.csv") and a.startswith("/work/in/")
                   for a in argv), f"{tool}: unmounted catalog must be /work/in/"
        assert any(a == "/work/catalog.csv" for a in argv_mounted), (
            f"{tool}: mounted catalog must be /work/catalog.csv")


def test_child_argv_carries_no_tuning_lever():
    """Zero parameter overrides (the memo SS2a law, restated for the new arms):
    the extraction runs at package documented defaults; the frozen caps are
    docker_cmd's job and arrive as -e tokens before the image, never as argv."""
    for tool in p6_arms.P6_ARM_SPECS:
        argv = _adapter(tool)._child_argv(None)
        joined = " ".join(argv)
        for tok in FORBIDDEN_TOKENS:
            assert tok not in joined, f"{tool}: forbidden tuning token {tok!r} in {argv}"
        for value in argv[argv.index("--backend") + 2:]:
            assert not _looks_float(value), (
                f"{tool}: float-literal argv value {value!r} — parameter "
                f"overrides are banned (zero-override law, memo §2a)")


def _looks_float(token: str) -> bool:
    try:
        float(token)
    except ValueError:
        return False
    return True


def test_pending_or_malformed_image_raises_adapter_unavailable():
    """Skip-not-skip (memo SS6): an unattested image is a spoken refusal with
    a reason, never a zero-execution success and never a generic crash."""
    for tool in p6_arms.P6_ARM_SPECS:
        spec = registry.lookup(tool)
        pending = dataclasses.replace(spec, image_digest=registry.PENDING_VERIFY)
        try:
            _adapter(tool).run({"in_dir": "/tmp/in", "out_dir": "/tmp/out"},
                               pending)
        except AdapterUnavailable as exc:
            assert tool in str(exc), f"{tool}: reason must name the tool: {exc}"
        else:
            raise AssertionError(f"{tool}: PENDING-VERIFY spec was not refused")
        malformed = dataclasses.replace(spec, image_digest="sha256:" + "f" * 10)
        try:
            _adapter(tool).run({"in_dir": "/tmp/in", "out_dir": "/tmp/out"},
                               malformed)
        except AdapterUnavailable:
            pass
        else:
            raise AssertionError(f"{tool}: malformed digest was not refused")
