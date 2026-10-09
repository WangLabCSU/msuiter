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
import hashlib
import json
import os
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


# -- witnessed-formals lint (RB-04(5)/RB-05(5), the fabricated-API class) --------
#
# The r4 probe death was commandArgs(trailingOnly = TRUE, removeDuplicates =
# FALSE): a named argument that does not exist in the formals the pinned
# image's own R resolves that name to. Declarative closure analysis cannot
# see this class (it is not a package dependency at all). The lint pins it
# offline: a call into an allowlisted name may only carry named arguments
# present in the era-R-harvested witness snapshot (formals_allowlist_slice3-
# r4.json); anything else is flagged. Qualified calls (ns::f) are skipped --
# the witness speaks for search-path resolution, not for an explicit ns.

_LINT_KEYWORDS = frozenset({"if", "for", "while", "function", "in", "next",
                            "break", "repeat", "else"})
_LINT_NAME = "[A-Za-z.][A-Za-z0-9._]*"
_CALL_SCAN = re.compile("(?<![A-Za-z0-9._])(" + _LINT_NAME + ")"
                        + "[ " + _B + "t" + _B + "n]*" + _B + "(")
_SEGMENT_NAMED = re.compile("^[ " + _B + "t" + _B + "n]*(" + _LINT_NAME + ")"
                            + "[ " + _B + "t" + _B + "n]*=" + "(?!=)")
_LOCAL_DEF = re.compile("(?m)^[ " + _B + "t]*(" + _LINT_NAME + ")[ "
                        + _B + "t]*(?:<<?-|=)[ " + _B + "t]*function"
                        + "[ " + _B + "t]*" + _B + "(")
_OPENERS = frozenset("([{")
_CLOSERS = {")": "(", "]": "[", "}": "{"}


def _mask_r_code(text: str) -> str:
    """Same-length mask: string contents -> 'x', comments -> blanks.

    Length/line alignment is preserved so every offset maps 1:1 back onto
    the original text (line numbers, call-token positions). Implemented as a
    character state machine, not regex, so it can not regress on the quoted
    string/comment classes. _NL/_BS are chr-built: bare backslashes in
    literals are this project's known edit-transport hazard."""
    nl, bs, dq, sq = chr(10), _B, chr(34), chr(39)
    out = []
    state = "code"
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if state == "code":
            if ch == "#":
                state = "comment"
                out.append(" ")
            elif ch == dq:
                state = "dq"
                out.append(ch)
            elif ch == sq:
                state = "sq"
                out.append(ch)
            else:
                out.append(ch)
        elif state == "comment":
            if ch == nl:
                state = "code"
                out.append(ch)
            else:
                out.append(" ")
        elif state == "dq":
            if ch == nl:
                out.append(ch)
            elif ch == bs:
                out.append("x")
                if i + 1 < n:
                    out.append(nl if text[i + 1] == nl else "x")
                    i += 1
            elif ch == dq:
                state = "code"
                out.append(ch)
            else:
                out.append("x")
        else:                                        # sq
            if ch == nl:
                out.append(ch)
            elif ch == sq:
                if i + 1 < n and text[i + 1] == sq:
                    out.append("xx")                 # doubled quote-escape
                    i += 1
                else:
                    state = "code"
                    out.append(ch)
            else:
                out.append("x")
        i += 1
    return "".join(out)


def _formals_of(entry: dict) -> list:
    formals = entry.get("formals")
    if formals is None:
        return []
    if isinstance(formals, str):
        return [formals]
    return [str(f) for f in formals]


def _top_level_args(body: str) -> list:
    """Split a call body on commas at paren/bracket/brace depth zero."""
    segs, depth, cur = [], 0, []
    for ch in body:
        if ch in _OPENERS:
            depth += 1
        elif ch in _CLOSERS:
            depth -= 1
        if ch == "," and depth == 0:
            segs.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    segs.append("".join(cur))
    return segs


def _matching_paren(masked: str, start: int) -> int:
    """Offset of the ')' closing the '(' at `start`, or -1 (unbalanced)."""
    depth = 0
    for i in range(start, len(masked)):
        ch = masked[i]
        if ch in _OPENERS:
            depth += 1
        elif ch in _CLOSERS:
            depth -= 1
            if depth == 0:
                return i
    return -1


def lint_called_formals(text: str, allowlist: dict, *,
                        label: str = "<text>") -> list:
    """Flags for calls whose named arguments escape the witnessed formals.

    Only names present in the harvest snapshot with state 'ok' are checked;
    primitive/unresolved witnesses are out of scope (the snapshot itself is
    the witness), script-local function definitions are script-owned and
    skipped, qualified calls are left to their explicit namespace."""
    masked = _mask_r_code(text)
    local_defs = frozenset(_LOCAL_DEF.findall(masked))
    entries = allowlist.get("entries", allowlist)
    flags = []
    for m in _CALL_SCAN.finditer(masked):
        name = m.group(1)
        if (name in _LINT_KEYWORDS or name in local_defs
                or ":" in name):
            continue
        entry = entries.get(name)
        if not isinstance(entry, dict) or entry.get("state") != "ok":
            continue
        allowed = _formals_of(entry)
        if "..." in allowed:
            continue
        opened = masked.find("(", m.end() - 1)
        closed = _matching_paren(masked, opened)
        if closed < 0:
            continue
        line_no = masked.count(chr(10), 0, m.start()) + 1
        for seg in _top_level_args(masked[opened + 1:closed]):
            nm = _SEGMENT_NAMED.match(seg)
            if nm and nm.group(1) not in allowed:
                flags.append({"file": label, "line": line_no, "name": name,
                              "arg": nm.group(1), "allowed": sorted(allowed)})
    return flags

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


# -- RB-06 hash-provenance gates (group (O) test_hash_provenance) ---------------
# Explicit-algorithm doctrine, law after the RB-06(1) controller erratum: a
# hash literal is admissible evidence only when it re-measures right now from
# committed bytes with a recorder that NAMES its algorithm, and the recording
# tool self-attests with the 'abc' control vector. The two failure modes that
# produced the addendum -- a SHA-1 tool's output compared against SHA-256
# digests, and a remembered control-vector constant cited as truth without
# measuring it -- each die on a distinct check below.

_CONTROL_INPUT = b"abc"


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hex64_pattern() -> "re.Pattern[str]":
    # The hex character class is ASSEMBLED, never hand-typed: a typed
    # metacharacter class is this project's documented mangling class (an RB-05
    # era draft carried an "0-9a-f" that matched nothing). str.digits is
    # authoritative; the range hyphen is chr(45) so no hyphen literal exists
    # to be doubled in transport.
    digits = bytes(range(ord("0"), ord("9") + 1)).decode("ascii")   # derived, never typed
    cls = "[" + digits + "a" + chr(45) + "f]"
    return re.compile(cls + "{64}")


_HEX64 = _hex64_pattern()

REPO_ROOT = HERE.parents[1]


def _rehearsal_dir(repo_root: Path) -> Path:
    return (repo_root / "bench" / "results"
            / "docker_m7_PILOT_20261008-200152" / "rehearsal_slice3-r4")


def _entry_path(file_field: str, repo_root: Path) -> "Path | None":
    rehearsal = _rehearsal_dir(repo_root)
    for base in (rehearsal, rehearsal.parent, repo_root):
        cand = Path(os.path.normpath(base / file_field))
        if cand.is_file():
            return cand
    return None


def _all_entries(manifest: dict) -> list:
    return (list(manifest.get("entries", []))
            + list(manifest.get("adapters", [])))


def _provenance_data(meta: dict, repo_root: Path) -> "bytes | None":
    src = repo_root / meta["path"]
    if not src.is_file():
        return None
    member = meta.get("member")
    if not member:
        return src.read_bytes()
    import tarfile                                      # lazy: member readers pay
    with tarfile.open(str(src)) as tf:                  # gzip by magic, auto
        handle = tf.extractfile(member)
        return None if handle is None else handle.read()


def verify_byte_pin_triangle(*, runner_bytes: bytes, witness_bytes: bytes,
                             dockerfile_text: str, manifest: dict,
                             registry_digest: str, inspect_id: str) -> list:
    """The RB-06(4b) triangle: committed runner bytes, promoted rehearsal
    witness, the Dockerfile assert-constant and the manifest's hash/role
    claims -- four measurements that must agree with what an
    explicit-algorithm recorder measures NOW, plus the registry-row pair
    against its committed live inspect. Dependency-injected (bytes/text/dict
    in, flags out) so the suite tampers every leg in memory."""
    flags: list = []
    h_runner = _sha256_hex(runner_bytes)
    if _sha256_hex(witness_bytes) != h_runner:
        flags.append({"check": "witness-vs-runner",
                      "detail": "promoted witness bytes differ from the committed runner"})
    pin_lines = [ln for ln in dockerfile_text.splitlines()
                 if "sha256sum" in ln and "/work/run_sigminer.R" in ln]
    if len(pin_lines) != 1:
        flags.append({"check": "dockerfile-assert-constant",
                      "detail": f"expected exactly one sha256sum pin line, found {len(pin_lines)}"})
    else:
        toks = _HEX64.findall(pin_lines[0])
        if toks != [h_runner]:
            flags.append({"check": "dockerfile-assert-constant",
                          "detail": f"assert constant {toks!r} is not the measured runner digest"})
    legs = (("entries", "run_sigminer_fixed.R", witness_bytes),
            ("adapters", "bench/m7/adapters/run_sigminer.R", runner_bytes))
    for kind, key, over in legs:
        entry = next((e for e in manifest.get(kind, []) if e["file"] == key), None)
        if entry is None or entry.get("sha256") != _sha256_hex(over):
            flags.append({"check": "manifest-entry",
                          "detail": f"{kind}/{key}: claim is not the measured digest"})
    prov = manifest.get("measured_provenance") or {}
    for e in _all_entries(manifest):
        for tok in _HEX64.findall(str(e.get("role", ""))):
            if tok not in prov and not h_runner.startswith(tok):
                flags.append({"check": "role-claim",
                              "detail": f"{e.get('file')}: role cites {tok} ahead of any measurement"})
    if registry_digest != inspect_id:
        flags.append({"check": "registry-vs-live-inspect",
                      "detail": f"registry row {registry_digest!r} differs from live inspect {inspect_id!r}"})
    return flags


def lint_hash_provenance(*, targets: dict, manifest: dict,
                         repo_root: Path) -> list:
    """RB-06(4c): every 64-hex literal the recipe family carries must be
    BACKED -- measured from committed bytes (manifest entries), re-measured
    from its recorded source (measured_provenance), or parsed from a
    committed live-inspect JSON. The manifest must additionally carry a
    verified 'abc' control-vector self-check from the recording tool."""
    flags: list = []
    cv = manifest.get("control_vector")
    control_ok = (isinstance(cv, dict) and cv.get("input") == "abc"
                  and isinstance(cv.get("sha256"), str)
                  and cv["sha256"] == _sha256_hex(_CONTROL_INPUT)
                  and "sha256" in str(cv.get("tool", "")).lower())
    if not control_ok:
        flags.append({"check": "control-vector",
                      "detail": "manifest lacks a verified sha256('abc') control-vector "
                                "self-check from the recording tool (RB-06(1) conflation seal)"})
    backed = {_sha256_hex(_CONTROL_INPUT)}
    for e in _all_entries(manifest):
        p = _entry_path(e["file"], repo_root)
        if p is None:
            flags.append({"check": "manifest-entry-missing", "detail": e["file"]})
            continue
        measured = _sha256_hex(p.read_bytes())
        if measured != e["sha256"]:
            flags.append({"check": "manifest-entry-rehash",
                          "detail": f"{e['file']}: claimed {e['sha256']!r} is not the measured digest"})
        backed.add(measured)
    for h, meta in (manifest.get("measured_provenance") or {}).items():
        data = _provenance_data(meta, repo_root)
        if data is None:
            flags.append({"check": "provenance-source-missing",
                          "detail": f"{h} unmeasurable: {meta.get('path')!r} absent"})
        elif _sha256_hex(data) != h:
            flags.append({"check": "provenance-remeasure",
                          "detail": f"{h} does not re-measure from {meta.get('path')!r}"})
        else:
            backed.add(h)
    rd = _rehearsal_dir(repo_root)
    for j in sorted(rd.glob("image_inspect_*.json")) + sorted(rd.parent.glob("image_inspect_*.json")):
        for d in json.loads(j.read_text(encoding="utf-8")):
            backed.add(str(d.get("Id", "")).removeprefix("sha256:"))
            for row in d.get("RepoDigests") or []:
                backed.add(str(row).split("@")[-1].removeprefix("sha256:"))
    for name, text in targets.items():
        for tok in _HEX64.findall(text):
            if tok not in backed:
                flags.append({"check": "unbacked-literal", "detail": f"{name}: {tok}"})
    return flags


PROVENANCE_TARGETS = {                     # the recipe family the lint scans
    "Dockerfile.sigminer": "adapters/Dockerfile.sigminer",
    "install_sigminer.R": "adapters/install_sigminer.R",
    "run_sigminer.R": "adapters/run_sigminer.R",
    "self_witness.sh": "adapters/self_witness.sh",
    "registry.py": "competitors/registry.py",
    "test_registry.py": "tests/test_registry.py",
    "test_sigminer_api_contract.py": "tests/test_sigminer_api_contract.py",
}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", default=None, dest="json_path")
    ap.add_argument("--lint", default=None, metavar="R-SCRIPT",
                    help="lint one executed-surface R script's called "
                         "name/named-arg pairs against --allowlist")
    ap.add_argument("--allowlist", default=None, metavar="JSON",
                    help="witnessed-formals harvest snapshot (entries.*)")
    ap.add_argument("--hash-provenance", action="store_true", default=False,
                    dest="hash_provenance",
                    help="RB-06 hash-provenance lint over the recipe family "
                         "(manifest entries, measured_provenance, live "
                         "inspects back every 64-hex literal)")
    ap.add_argument("--manifest", default=None, metavar="JSON",
                    help="rehearsal manifest for --hash-provenance")
    args = ap.parse_args(argv)
    if args.hash_provenance:
        if not args.manifest:
            print("[audit] --hash-provenance requires --manifest", file=sys.stderr)
            return 2
        manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
        targets = {name: (HERE / rel).read_text(encoding="utf-8")
                   for name, rel in PROVENANCE_TARGETS.items()}
        manifest_name = "rehearsal_manifest.json"
        targets[manifest_name] = Path(args.manifest).read_text(encoding="utf-8")
        flags = lint_hash_provenance(targets=targets, manifest=manifest,
                                     repo_root=REPO_ROOT)
        verdict = {"lint": "HASH-PROVENANCE-DEFECT" if flags
                   else "HASH-PROVENANCE-CLEAN", "flags": flags}
        if args.json_path:
            out = Path(args.json_path)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(verdict, sort_keys=True, indent=1) + chr(10),
                           encoding="utf-8")
        for f in flags:
            print(f"[hash-provenance] {f['check']}: {f['detail']}",
                  file=sys.stderr)
        print(json.dumps(verdict, sort_keys=True))
        return 2 if flags else 0
    if args.lint:
        if not args.allowlist:
            print("[audit] --lint requires --allowlist", file=sys.stderr)
            return 2
        allowlist = json.loads(Path(args.allowlist).read_text(encoding="utf-8"))
        text = Path(args.lint).read_text(encoding="utf-8")
        flags = lint_called_formals(text, allowlist, label=str(args.lint))
        verdict = {"lint": "FABRICATED-ARGS" if flags else "CLEAN",
                   "flags": flags}
        for f in flags:
            print(f"[lint] LINE {f['line']} call {f['name']}() carries named "
                  f"argument {f['arg']!r}; witnessed formals: {f['allowed']}",
                  file=sys.stderr)
        print(json.dumps(verdict, sort_keys=True))
        return 2 if flags else 0
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
