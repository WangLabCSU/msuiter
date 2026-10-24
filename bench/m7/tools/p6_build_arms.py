#!/usr/bin/env python3
"""Assemble + build the six P6 arm images from pre-registered identity DATA.

Single source of truth: every build identity (tool, tree SHA, version,
NAMESPACE hash, face) is read from competitors.p6_arms -- the same table the
roster test pins to the pre-registration manifest. This tool never invents
identity and never invents digests: after a verified build it prints the
`docker image inspect` RepoDigests verbatim for the roster flip, and the
flip itself is the data edit the registry docstring already promises.

Tree bytes come from the READ-ONLY ground-truth checkout via
`git archive <tree_sha>` (never a clone, never a fetch, never a worktree of
the GT). The object is probed (cat-file -e) before extraction: a shaped
non-object is an immediate loud death -- the 2026-10-15 A2 failure mode.
The msuiter kernel source rides the same discipline from this repo at
MSUITER_SOURCE_SHA (the certified-kernel lineage head, attested in the build
log). The committed constant is the P6 reproducibility witness and never
moves; a re-adjudication build may only OVERLAY it with an explicit
M7_MSUITER_SOURCE_SHA (40-hex validated at the resolver, then subject to the
very same witnessed-object cat-file gate).

Usage:
  python3 tools/p6_build_arms.py                     # all six
  python3 tools/p6_build_arms.py --only sigminer_post_v3_rust
  M7_MSUITER_SOURCE_SHA=<40-hex> python3 tools/p6_build_arms.py --only ...
  python3 tools/p6_build_arms.py --scratch /tmp/p6build
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from competitors import p6_arms                      # noqa: E402

ADAPTERS = HERE / "adapters"
GIT_EXE = "git"
# The ground-truth sigminer checkout (read-only law: this tool only ever runs
# cat-file/archive against it) and the msuiter kernel source pin -- the
# certified-kernel lineage head whose protocol=1 family the rust face rides.
SIGMINER_GT = Path("/Users/wsx/Documents/GitHub/sigminer")
MSUITER_SRC = HERE.parent.parent                      # the msuiter repo root
MSUITER_SOURCE_SHA = "dbef3a77dce3f7b2bb9405895c426dd6342167c6"
FULL_SHA40 = re.compile(r"^[0-9a-f]{40}$")


def resolve_msuiter_source_sha() -> str:
    """The certified-kernel pin THIS build rides. The committed default is
    the P6 reproducibility witness (sealed by value in
    tests/test_p6_source_pin_override.py) and may never be replaced; a
    re-adjudication build rides an EXPLICIT M7_MSUITER_SOURCE_SHA overlay.
    Format-fail is a pre-flight death; a shaped non-object then dies at the
    same witnessed-object cat-file gate the default rides -- the overlay
    adds no trust gap."""
    override = os.environ.get("M7_MSUITER_SOURCE_SHA")
    if override is None:
        return MSUITER_SOURCE_SHA
    if not FULL_SHA40.match(override):
        sys.stderr.write(f"[FATAL] M7_MSUITER_SOURCE_SHA={override!r} is not a "
                         "full lower-case 40-hex commit id -- refused "
                         "pre-flight (A2-class shaped-mistranscription law)\n")
        raise SystemExit(2)
    return override

# The build-input files every context carries, in COPY-name order. The
# mini_cell_p6/ fixture dir is a COPY source too -- the self-witness's cell
# input overlay (death #7: the stage2-proven 96x1 counts.csv is legitimate
# history but nndsvd-rank-refusing at k=2, so the P6 witness rides the
# twenty-sample regeneration sealed by tests/test_p6_mini_fixture.py; the
# byte-frozen mini_cell/ dir stays the single home of the COSMIC catalog and
# params, overlaid under the regeneration) -- omitting either is a
# solve-time "not found", the first bake's recorded death.
FLAT_INPUTS = ("install_sigminer_arm.R", "run_sigminer_arm.R", "m7_entry.py",
               "self_witness_arm.sh", "Dockerfile.sigminer.tree")
TREE_INPUTS = ("mini_cell", "mini_cell_p6")


def _run(argv: list[str], cwd: Path | None = None,
         log: Path | None = None) -> str:
    """Run argv, capture stdout, tee everything to the build log; die loudly."""
    proc = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    if log is not None:
        with log.open("a", encoding="utf-8") as fh:
            fh.write(f"$ {' '.join(argv)}\n")
            fh.write(proc.stdout)
            if proc.stderr:
                fh.write(proc.stderr)
    if proc.returncode != 0:
        sys.stderr.write(f"[FATAL] {' '.join(argv)} exited {proc.returncode}:\n"
                         f"{proc.stderr or proc.stdout}\n")
        raise SystemExit(2)
    return proc.stdout


def _export_tree(repo: Path, sha: str, dest: Path, log: Path) -> None:
    """git-archive one witnessed object out of a read-only repo into dest."""
    rc = subprocess.run([GIT_EXE, "-C", str(repo), "cat-file", "-e",
                         f"{sha}^{{tree}}"], capture_output=True).returncode
    if rc != 0:
        sys.stderr.write(f"[FATAL] {repo}: {sha} is not a witnessed object "
                         f"(A2-class shaped mistranscription or missing fetch)\n")
        raise SystemExit(2)
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    proc = subprocess.run(f"{GIT_EXE} -C {repo} archive {sha} | tar -x -C {dest}",
                          shell=True, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(f"[FATAL] archive {repo}@{sha}: {proc.stderr}\n")
        raise SystemExit(2)
    with log.open("a", encoding="utf-8") as fh:
        fh.write(f"$ git -C {repo} archive {sha} | tar -x -C {dest}\n"
                 f"  extracted OK (DESCRIPTION+NAMESPACE probed below)\n")
    for need in ("DESCRIPTION", "NAMESPACE"):
        if not (dest / need).is_file():
            sys.stderr.write(f"[FATAL] {repo}@{sha}: extracted tree lacks {need}\n")
            raise SystemExit(2)


def assemble(tool: str, scratch: Path) -> tuple[Path, Path]:
    """Materialize the build context for one arm; return (context, log)."""
    spec = p6_arms.P6_ARM_SPECS[tool]
    ctx = scratch / tool
    log = scratch / f"{tool}.build.log"
    if ctx.exists():
        shutil.rmtree(ctx)
    ctx.mkdir(parents=True)
    log.write_text(f"# p6_build_arms context assembly for {tool}\n",
                   encoding="utf-8")

    for name in FLAT_INPUTS:
        src = ADAPTERS / name
        if not src.is_file():
            sys.stderr.write(f"[FATAL] missing build input {src}\n")
            raise SystemExit(2)
        shutil.copy2(src, ctx / name)
    fixtures = {"mini_cell": ("catalog.csv", "params.json"),
                "mini_cell_p6": ("counts.csv",)}
    for name, required in fixtures.items():
        src = ADAPTERS / name
        for fn in required:
            if not (src / fn).is_file():
                sys.stderr.write(f"[FATAL] missing witness fixture "
                                 f"{name}/{fn} under {src}\n")
                raise SystemExit(2)
        shutil.copytree(src, ctx / name)
    pin = ADAPTERS / "arm_pins" / f"{tool}.json"
    if not pin.is_file():
        sys.stderr.write(f"[FATAL] missing committed arm pin {pin} -- "
                         f"run tools/p6_emit_arm_pins.py\n")
        raise SystemExit(2)
    shutil.copy2(pin, ctx / "arm_pin.json")

    _export_tree(SIGMINER_GT, spec["tree_sha"], ctx / "sigminer", log)
    if spec["face"] == "rust":
        _export_tree(MSUITER_SRC, resolve_msuiter_source_sha(),
                     ctx / "msuiter", log)
    else:
        (ctx / "msuiter").mkdir()   # inert: the FACE-gated layers never read it
    return ctx, log


def attested_identity(tool: str, image_digest: str) -> dict:
    """The [ATTESTED] block: pure identity data -- roster columns plus the
    resolved source pin. Only build() reaches it, with the inspect-captured
    digest; nothing hand-typed can join an attestation (SS3 law)."""
    spec = p6_arms.P6_ARM_SPECS[tool]
    return {"tool": tool,
            "image_ref": p6_arms.image_tag(tool, spec.get("revision", 1)),
            "image_digest": image_digest,
            "tree_sha": spec["tree_sha"], "face": spec["face"],
            "msuiter_source_sha": (resolve_msuiter_source_sha()
                                   if spec["face"] == "rust" else None)}


def build(tool: str, scratch: Path) -> dict:
    """Build one arm image; return the inspect-captured identity block."""
    spec = p6_arms.P6_ARM_SPECS[tool]
    ctx, log = assemble(tool, scratch)
    tag = p6_arms.image_tag(tool, spec.get("revision", 1))
    argv = ["docker", "build", "-f", "Dockerfile.sigminer.tree",
            "--build-arg", f"TOOL={tool}",
            "--build-arg", f"TREE_SHA={spec['tree_sha']}",
            "--build-arg", f"EXPECTED_VERSION={spec['version']}",
            "--build-arg", f"NS_SHA256={spec['ns_sha256']}",
            "--build-arg", f"FACE={spec['face']}",
            "-t", tag, "."]
    print(f"[build] {tool} face={spec['face']} tree={spec['tree_sha'][:10]} -> {tag}")
    _run(argv, cwd=ctx, log=log)
    # SS3 law: the digest is CAPTURED, never transcribed. The reference rows
    # were minted from inspect .Id ("sha256:" + 64 hex, the legacy registry's
    # own annotation), and locally BUILT images carry no RepoDigests until
    # pushed -- capture .Id first, keep RepoDigests as the post-push echo.
    inspect = _run(["docker", "image", "inspect", tag,
                    "--format", "{{.Id}}"], log=log)
    digest = inspect.strip()
    if len(digest) != 71 or not digest.startswith("sha256:"):
        sys.stderr.write(f"[FATAL] {tag}: inspect .Id is not sha256+64hex: "
                         f"{digest!r}\n")
        raise SystemExit(2)
    block = attested_identity(tool, digest)
    with log.open("a", encoding="utf-8") as fh:
        fh.write(f"\n[ATTESTED] {json.dumps(block, sort_keys=True)}\n")
    return block


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", action="append", default=None,
                    help="restrict to this arm key (repeatable)")
    ap.add_argument("--scratch", type=Path, default=Path("/tmp/p6build"))
    args = ap.parse_args(argv)
    args.scratch.mkdir(parents=True, exist_ok=True)
    tools = args.only or sorted(p6_arms.P6_ARM_SPECS)
    for t in tools:
        if t not in p6_arms.P6_ARM_SPECS:
            sys.stderr.write(f"[FATAL] unknown arm {t}\n")
            return 2
    blocks = [build(t, args.scratch) for t in tools]
    print("\n--- inspect-captured digests for the roster flip (SS3) ---")
    for b in blocks:
        print(json.dumps(b, sort_keys=True))
    print(f"logs: {args.scratch}/<tool>.build.log")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
