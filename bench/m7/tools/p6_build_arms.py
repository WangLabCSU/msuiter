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
log).

Usage:
  python3 tools/p6_build_arms.py                     # all six
  python3 tools/p6_build_arms.py --only sigminer_post_v3_rust
  python3 tools/p6_build_arms.py --scratch /tmp/p6build
"""

from __future__ import annotations

import argparse
import json
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

# The build-input files every context carries, in COPY-name order.
FLAT_INPUTS = ("install_sigminer_arm.R", "run_sigminer_arm.R", "m7_entry.py",
               "self_witness_arm.sh", "Dockerfile.sigminer.tree")


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
    pin = ADAPTERS / "arm_pins" / f"{tool}.json"
    if not pin.is_file():
        sys.stderr.write(f"[FATAL] missing committed arm pin {pin} -- "
                         f"run tools/p6_emit_arm_pins.py\n")
        raise SystemExit(2)
    shutil.copy2(pin, ctx / "arm_pin.json")

    _export_tree(SIGMINER_GT, spec["tree_sha"], ctx / "sigminer", log)
    if spec["face"] == "rust":
        _export_tree(MSUITER_SRC, MSUITER_SOURCE_SHA, ctx / "msuiter", log)
    else:
        (ctx / "msuiter").mkdir()   # inert: the FACE-gated layers never read it
    return ctx, log


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
    # SS3 law: the digest is CAPTURED, never transcribed -- and never by this
    # tool's hand into the roster; it prints for the flip and the log keeps it.
    inspect = _run(["docker", "image", "inspect", tag,
                    "--format", "{{json .RepoDigests}}"], log=log)
    digests = json.loads(inspect.strip())
    if not digests:
        sys.stderr.write(f"[FATAL] {tag}: no RepoDigests in inspect output\n")
        raise SystemExit(2)
    block = {"tool": tool, "image_ref": tag, "repo_digest": digests[0],
             "tree_sha": spec["tree_sha"], "face": spec["face"],
             "msuiter_source_sha": MSUITER_SOURCE_SHA if spec["face"] == "rust" else None}
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
