#!/usr/bin/env python3
"""Convergence-gate audit: executed-surface closure vs image-recipe provisioning.

RB-03 (2026-10-09): the pilot -> slice3-r2 RED -> slice3-r3 jsonlite chain
proved that running one live probe discovers exactly one missing provision at
a time. This tool ends that mode structurally: it parses the EXECUTED SURFACE
of the two scripts the cell protocol actually runs inside the container
(adapters/run_sigminer.R, adapters/m7_entry.py), derives the full package
closure (R: library()/require()/requireNamespace() and the ::/::: namespace
operators; python: import/from), and asserts the closure is provisioned by
the image recipe (Dockerfile apt layers + Rscript install.packages layers
+ the result-gated targets of install_sigminer.R's resolver) before any
build is spent.

Run it before building: a gap here must be folded into the SAME recipe, the
build spent once on the complete closure, never iteratively.

Exit contract: 0 CONVERGED (closure fully provisioned), 1 GAPS (each gap
named with its executed-surface file). Final stdout line is the
machine-readable JSON verdict; human detail on stderr.

Usage:
  python3 tools/audit_executed_surface_deps.py [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # bench/m7
ADAPTERS = HERE / "adapters"

# Every regex below that needs a metacharacter escape is ASSEMBLED from
# chr(92) instead of typed as a backslash literal: backslash runs are the one
# byte class this project's edit-transport has demonstrably mangled before
# (an audit-tool draft picked up doubled backslashes in transit, silently
# turning [^"NEWLINE-CLASS] into a class that excluded the LETTER n). The
# assembly makes the pattern a behavioural object, verifiable at import.
_B = chr(92)                                             # single backslash
_ESC_ANY = _B + _B + "."                                  # regex: backslash + any
_NOT_DQ = "[^" + _B + "n]"                                # regex: not " nor newline
_NOT_SQ = "[^'" + _B + "n]"                               # regex: not ' nor newline
_DQ_BODY = "(?:" + _ESC_ANY + "|" + _NOT_DQ + ")*"
_SQ_BODY = "(?:" + _ESC_ANY + "|" + _NOT_SQ + ")*"
_R_STRINGS = (chr(34) + _DQ_BODY + chr(34) + "|"
              + chr(39) + _SQ_BODY + chr(39))
_R_COMMENT = "(?m)#[^" + _B + "n]*"
_NS_OP = _B + "b([A-Za-z.][A-Za-z0-9._]*):::?"
_QQ = "[" + chr(34) + chr(39) + "]?"                      # optional quote (pkg name)
_INSTALL_PACKAGES = "install" + _B + ".packages" + _B + "(([^)]*)" + _B + ")"
_QUOTED_NAME = "[" + chr(34) + "'" + "]([A-Za-z.][A-Za-z0-9._]*)[" + chr(34) + "'" + "]"
_IMPORT_LINE = ("(?m)^[ " + _B + "t]*(?:import|from)" + _B + "s+"
                + "([A-Za-z_][A-Za-z0-9._]*)")
_WORD_TOK = "[A-Za-z0-9][A-Za-z0-9._+-]*"

R_BASE_PACKAGES = frozenset(
    {"base", "utils", "stats", "methods", "compiler", "parallel",
     "grDevices", "datasets", "tcltk"})

_STDLIB_RAW = sys.stdlib_module_names
# 3.11/3.12 expose stdlib_module_names as a callable; 3.13 exposes it as a
# frozenset attribute. Accept either so the gate cannot fail on version drift.
STDLIB_NAMES = frozenset(_STDLIB_RAW() if callable(_STDLIB_RAW) else _STDLIB_RAW)


# -- executed-surface parsers -----------------------------------------------------

def _strip_r_noise(text: str) -> str:
    """Remove quoted strings, then #-comments: what survives is code."""
    text = re.sub(_R_STRINGS, chr(34) * 2, text)
    text = re.sub(_R_COMMENT, "", text)
    return text


def r_closure(text: str) -> frozenset:
    """R packages the executed code touches (library/require/requireNamespace
    plus the :: and ::: namespace operators)."""
    code = _strip_r_noise(text)
    found = set()
    for fn in ("library", "require", "requireNamespace"):
        for m in re.finditer(fn + _B + "(" + _B + "s*" + _QQ
                             + "([A-Za-z.][A-Za-z0-9._]*)" + _QQ,
                             code):
            found.add(m.group(1))
    for m in re.finditer(_NS_OP, code):
        found.add(m.group(1))
    return frozenset(found)


def python_closure(text: str) -> tuple:
    """Split executed-surface python imports into (stdlib, third-party).

    Third-party imports are, by the ruling's scope, expected to be empty for
    the container surface -- anything here beyond stdlib must be provisioned
    by the recipe's apt layers (same class as python3 itself)."""
    top = set()
    for m in re.finditer(_IMPORT_LINE, text):
        name = m.group(1)
        if not name.startswith("."):
            top.add(name.split(".")[0])
    return frozenset(top & STDLIB_NAMES), frozenset(top - STDLIB_NAMES)


# -- recipe provisioning surface --------------------------------------------------

def recipe_provisioned(dockerfile_text: str) -> dict:
    """Apt package names and install.packages targets the recipe provides."""
    apt, cran = set(), set()
    for line in dockerfile_text.splitlines():
        if "apt-get install" in line:
            for tok in line.split():
                if (tok not in ("RUN", "&&", "apt-get", "install", "update")
                        and not tok.startswith("-") and not tok.startswith("&&")
                        and re.fullmatch(_WORD_TOK, tok)):
                    apt.add(tok)
    for m in re.finditer(_INSTALL_PACKAGES, dockerfile_text):
        for name in re.findall(_QUOTED_NAME, m.group(1)):
            cran.add(name)
    return {"apt": frozenset(apt), "crane": frozenset(cran)}


def resolver_pins(installer_text: str) -> frozenset:
    """R packages the resolver script result-gates (packageVersion asserts)."""
    return frozenset(re.findall("packageVersion" + _B + "(" + _B + "s*["
                                + chr(34) + "'" + "]([A-Za-z.][A-Za-z0-9._]*)["
                                + chr(34) + "'" + "]", installer_text))


def missing_packages(*, r_packages: set, python_third_party: frozenset,
                     provisioned: dict,
                     resolver_pinned: frozenset | None = None) -> list:
    """Gaps: executed-surface packages the recipe does not provision.

    ``resolver_pinned`` defaults to the live install_sigminer.R result-gate
    targets -- the resolver's own provisioned set is part of the closure."""
    if resolver_pinned is None:
        resolver_pinned = resolver_pins(
            (ADAPTERS / "install_sigminer.R").read_text(encoding="utf-8"))
    allowed_r = set(provisioned["crane"]) | set(resolver_pinned) | set(R_BASE_PACKAGES)
    allowed_py = set(provisioned["apt"])      # python side rides apt (python3 class)
    gaps = [{"package": pkg, "surface": "R"} for pkg in sorted(r_packages - allowed_r)]
    gaps += [{"package": pkg, "surface": "python"}
             for pkg in sorted(python_third_party - allowed_py)]
    return gaps


# -- end-to-end audit -------------------------------------------------------------

def run_audit() -> tuple:
    dockerfile = (ADAPTERS / "Dockerfile.sigminer").read_text(encoding="utf-8")
    runner = (ADAPTERS / "run_sigminer.R").read_text(encoding="utf-8")
    entry = (ADAPTERS / "m7_entry.py").read_text(encoding="utf-8")
    installer = (ADAPTERS / "install_sigminer.R").read_text(encoding="utf-8")

    # Each executed-surface file is parsed under the grammar of the
    # interpreter that actually executes it: run_sigminer.R under R (Rscript),
    # m7_entry.py under python (python3). Cross-scanning a python file for R
    # namespace operators only harvests prose (the module docstring literally
    # spells "docker_cmd.py::ENTRY_SCRIPT" -- a false dependency a comment
    # cannot be), and vice versa. The two closures are still BOTH audited:
    # RB-03 names both /work scripts, just each in its own language.
    r_pkgs = r_closure(runner)
    stdlib, third_party = python_closure(entry)
    provisioned = recipe_provisioned(dockerfile)
    pinned = resolver_pins(installer)
    gaps = missing_packages(r_packages=r_pkgs,
                            python_third_party=third_party,
                            provisioned=provisioned, resolver_pinned=pinned)
    verdict = {
        "r_closure": {"run_sigminer.R": sorted(r_pkgs)},
        "python_closure": {"m7_entry.py": sorted(stdlib | third_party)},
        "python_stdlib": sorted(stdlib),
        "third_party_python": sorted(third_party),
        "provisioned": {"apt": sorted(provisioned["apt"]),
                        "crane": sorted(provisioned["crane"])},
        "resolver_pinned": sorted(pinned),
        "gaps": gaps,
        "verdict": "CONVERGED" if not gaps else "GAPS",
    }
    return (0 if not gaps else 1), verdict


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", default=None, dest="json_path")
    args = ap.parse_args(argv)
    code, verdict = run_audit()
    for gap in verdict["gaps"]:
        print(f"[audit] GAP {gap['surface']} package {gap['package']!r} "
              f"used by the executed surface but not provisioned by the recipe",
              file=sys.stderr)
    print(f"[audit] {verdict['verdict']}: R closure "
          f"{verdict['r_closure']['run_sigminer.R']}, third-party python "
          f"{verdict['third_party_python']}", file=sys.stderr)
    if args.json_path:
        out = Path(args.json_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(verdict, sort_keys=True, indent=1),
                       encoding="utf-8")
    print(json.dumps(verdict, sort_keys=True))                 # final line
    return code


if __name__ == "__main__":
    raise SystemExit(main())
