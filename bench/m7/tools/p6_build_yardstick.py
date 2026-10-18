#!/usr/bin/env python3
"""Bake the seventh image: the python-capable rust-NMF yardstick bench.

Structural sibling of tools/p6_build_arms.py (same _run capture discipline,
same inspect-.Id digest law, same [ATTESTED]-into-the-log ceremony) minus
the roster coupling: the yardstick is a measurement instrument, not an arm,
so it never touches P6_ARM_SPECS or the roster. Its digest is banked as
delivery evidence beside the six arm attestations -- the yardstick cells
run through run_nmf_yardstick.py, not through the four-file cell contract.

Context is assembled from committed bytes only (adapters/); the wheel
arrives in-image, hash-pinned and index-spelled, per the Dockerfile's
provisioning law (04-nmf-rs-fetch-probe evidence).

Usage:
  python3 tools/p6_build_yardstick.py --scratch /tmp/p6build
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from p6_build_arms import _run                      # noqa: E402  (shared capture idiom)

ADAPTERS = HERE / "adapters"
IMAGE = "msuiter-sigminer:p6-nmf-yardstick-r3"   # r3: fixed-count fairness; r2 measured the 440 refusal boundary
FLAT_INPUTS = ("run_nmf_yardstick.py", "run_nmf_yardstick_leg.R",
               "install_nmf_yardstick.R", "Dockerfile.nmf_yardstick")


def assemble(scratch: Path) -> tuple[Path, Path]:
    ctx = scratch / "nmf_yardstick"
    log = scratch / "nmf_yardstick.build.log"
    if ctx.exists():
        shutil.rmtree(ctx)
    ctx.mkdir(parents=True)
    log.write_text("# p6_build_yardstick context assembly\n", encoding="utf-8")
    for name in FLAT_INPUTS:
        src = ADAPTERS / name
        if not src.is_file():
            sys.stderr.write(f"[FATAL] missing yardstick build input {src}\n")
            raise SystemExit(2)
        shutil.copy2(src, ctx / name)
    fixtures = ADAPTERS / "yardstick_cell"
    if not (fixtures / "matrix.csv").is_file():
        sys.stderr.write(f"[FATAL] missing yardstick fixture {fixtures}\n")
        raise SystemExit(2)
    shutil.copytree(fixtures, ctx / "yardstick_cell")
    return ctx, log


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--scratch", type=Path, default=Path("/tmp/p6build"))
    args = ap.parse_args(argv)
    args.scratch.mkdir(parents=True, exist_ok=True)
    ctx, log = assemble(args.scratch)
    argv = ["docker", "build", "-f", "Dockerfile.nmf_yardstick",
            "-t", IMAGE, "."]
    print(f"[build] nmf_yardstick -> {IMAGE}")
    _run(argv, cwd=ctx, log=log)
    # SS3 law: capture, never transcribe -- same 71-char gate as the arms.
    inspect = _run(["docker", "image", "inspect", IMAGE,
                    "--format", "{{.Id}}"], log=log)
    digest = inspect.strip()
    if len(digest) != 71 or not digest.startswith("sha256:"):
        sys.stderr.write(f"[FATAL] {IMAGE}: inspect .Id is not sha256+64hex: "
                         f"{digest!r}\n")
        raise SystemExit(2)
    # Death #11 law: an instrument image is attested only after the COMMITTED
    # runner has EXECUTED inside it, end to end, over the committed fixture,
    # AT THE COMMITTED DEFAULT COUNT (no --iters override: the witness tests
    # the bytes the campaign will actually run). The gate is self-consistency:
    # each side's own niter attestation must equal the block's stamped
    # iterations_fixed, and no fairness_flag may exist. A text gate over the
    # file and a probe over a draft are not witnesses -- the un-called
    # proc_time line passed every gate until the first real cell run met it.
    wdir = args.scratch / "witness"
    wdir.mkdir(parents=True, exist_ok=True)
    _run(["docker", "run", "--rm", "--network=none",
          "-v", f"{wdir}:/w", IMAGE,
          "python3", "/work/run_nmf_yardstick.py",
          "--out", "/w/witness.json"], cwd=ctx, log=log)
    wit = json.loads((wdir / "witness.json").read_text(encoding="utf-8"))
    fixed = wit.get("iterations_fixed")
    if not isinstance(fixed, int) or fixed < 1:
        sys.stderr.write(f"[FATAL] yardstick witness has no fixed-count stamp: "
                         f"{wit!r}\n")
        raise SystemExit(2)
    if wit.get("rust_niter") != fixed or wit.get("r_niter") != fixed \
            or "fairness_flag" in wit:
        sys.stderr.write(f"[FATAL] yardstick witness bytes unfair "
                         f"(fixed={fixed} rust={wit.get('rust_niter')} "
                         f"r={wit.get('r_niter')}): {wit!r}\n")
        raise SystemExit(2)
    block = {"instrument": "nmf_yardstick", "image_ref": IMAGE,
             "image_digest": digest, "wheel_sha256":
             "9ad81407bbc9335219f31a0b6746264761733494c6b16697e060729fa749dd17",
             "witness": {k: wit[k] for k in
                         ("fixture_sha256", "iterations_fixed",
                          "rust_seconds", "r_seconds",
                          "rust_niter", "r_niter", "r_version", "r_dropped")}}
    with log.open("a", encoding="utf-8") as fh:
        fh.write(f"\n[ATTESTED] {json.dumps(block, sort_keys=True)}\n")
    print(json.dumps(block, sort_keys=True))
    print(f"log: {log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
