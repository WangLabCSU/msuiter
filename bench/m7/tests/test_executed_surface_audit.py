"""Group (M) test_executed_surface_audit -- convergence-gate contract (RB-03).

The pilot->r3->jsonlite chain proved that single probe runs discover one
missing provision at a time. The convergence gate ends that mode: a static
audit parses the EXECUTED SURFACE of the two /work scripts (run_sigminer.R,
m7_entry.py), derives the full package closure, and asserts it is provisioned
by the image recipe before any build is spent. These offline units pin the
parser/classifier contract; the real-files smoke pins the closure itself --
add a dependency to the runner without provisioning it and this suite goes
red before a daemon is ever consulted.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import tools.audit_executed_surface_deps as audit              # noqa: E402

ADAPTERS = Path(__file__).resolve().parents[1] / "adapters"


# -- R executed-surface closure -------------------------------------------------

def test_r_closure_collects_library_require_and_namespace_operators():
    text = (
        'library(sigminer)\n'
        'suppressWarnings(suppressMessages({ library(jsonlite) }))\n'
        'require(tools)\n'
        'requireNamespace(Matrix)\n'
        'x <- base64enc::encode(y)\n'
        'z <- jsonlite::fromJSON(w)\n'
        'q <- utils::head(z)\n'
        '# library(decoy) lives only in a comment\n'
        's <- "fake3::notCode(string literals)"\n'
    )
    assert audit.r_closure(text) == frozenset(
        {"sigminer", "jsonlite", "tools", "Matrix", "base64enc", "utils"})


def test_r_closure_ignores_commented_and_quoted_librarie():
    text = '# library(fake1)\nc <- "library(fake2)"\nlibrary(stats)\n'
    assert audit.r_closure(text) == frozenset({"stats"})


# -- python executed-surface closure ---------------------------------------------

def test_python_closure_accepts_stdlib_imports():
    text = ("from __future__ import annotations\n"
            "import json\nimport argparse\nimport os\n"
            "import subprocess\nimport sys\nfrom pathlib import Path\n")
    stdlib, third_party = audit.python_closure(text)
    assert stdlib == frozenset({"__future__", "json", "argparse", "os",
                                "subprocess", "sys", "pathlib"})
    assert third_party == frozenset()


def test_python_closure_flags_third_party_imports():
    text = "import json\nimport pandas\nfrom numpy.linalg import norm\n"
    _, third_party = audit.python_closure(text)
    assert third_party == frozenset({"pandas", "numpy"})


# -- recipe provisioning surface --------------------------------------------------

def test_recipe_parsing_collects_apt_and_cran_provisioning():
    dockerfile = (
        "RUN apt-get update \\\n"
        "    && apt-get install -y --no-install-recommends ca-certificates cmake \\\n"
        "    && rm -rf /var/lib/apt/lists/*\n"
        "RUN apt-get install -y --no-install-recommends python3\n"
        "RUN Rscript -e 'install.packages(\"jsonlite\")'\n"
    )
    provisioned = audit.recipe_provisioned(dockerfile)
    assert {"ca-certificates", "cmake", "python3"} <= provisioned["apt"]
    assert "jsonlite" in provisioned["crane"]


def test_resolver_pinned_targets_read_from_the_resolver_script():
    pinned = audit.resolver_pins((ADAPTERS / "install_sigminer.R").read_text(
        encoding="utf-8"))
    assert "sigminer" in pinned


# -- end-to-end audit over the real executed surface ------------------------------

def test_audit_over_real_files_has_zero_gaps_and_pinned_closure():
    code, verdict = audit.run_audit()
    assert code == 0, f"executed-surface gaps: {verdict['gaps']}"
    assert verdict["r_closure"]["run_sigminer.R"] == ["jsonlite", "sigminer"]
    assert verdict["third_party_python"] == []


def test_gap_is_reported_when_runner_loses_its_provisioning():
    # simulate drift: pretend jsonlite vanished from the recipe -- the audit
    # must name it as a gap instead of the build discovering it downstream.
    dockerfile = (ADAPTERS / "Dockerfile.sigminer").read_text(encoding="utf-8")
    stripped = dockerfile.replace('install.packages("jsonlite")',
                                  'install.packages("notjsonlite")')
    assert stripped != dockerfile, "recipe no longer carries the jsonlite layer"
    provisioned = audit.recipe_provisioned(stripped)
    gaps = audit.missing_packages(r_packages={"sigminer", "jsonlite"},
                                  python_third_party=frozenset(),
                                  provisioned=provisioned)
    assert [g["package"] for g in gaps] == ["jsonlite"]


def test_verdict_json_round_trips_machine_readable():
    _, verdict = audit.run_audit()
    assert json.loads(json.dumps(verdict, sort_keys=True)) == verdict


# -- group (N): witnessed-formals lint (RB-04(5)/RB-05(5)) -------------------------
#
# The r4 probe death (commandArgs(unused-argument)) is the fabricated-API
# class: a call whose named argument does not exist in the formals the
# pinned image's own R resolves that name to. The lint consumes the
# committed harvest snapshot (formals_allowlist_slice3-r4.json: per called
# name, the era-R-witnessed formals + resolving environment) and flags any
# call into an allowlisted name carrying a named argument outside that
# witness. Offline, zero container.

PILOT = (Path(__file__).resolve().parents[1].parent / "results"
         / "docker_m7_PILOT_20261008-200152")
REHEARSAL = PILOT / "rehearsal_slice3-r4"
ALLOWLIST_PATH = REHEARSAL / "formals_allowlist_slice3-r4.json"
FIXED_RUNNER = REHEARSAL / "run_sigminer_fixed.R"


def _al(**entries):
    return {"schema": "m7-formals-allowlist-1", "entries": entries}


def _ok(*formals):
    return {"state": "ok", "formals": list(formals)}


def test_lint_flags_named_argument_outside_witnessed_formals():
    al = _al(f=_ok("a", "b"))
    flags = audit.lint_called_formals("y <- f(a = 1, zzz = 2)\n", al)
    assert [f["arg"] for f in flags] == ["zzz"]
    assert flags[0]["name"] == "f"
    assert flags[0]["line"] == 1


def test_lint_accepts_witnessed_named_arguments():
    al = _al(f=_ok("a", "b"))
    assert audit.lint_called_formals("y <- f(a = 1, b = 2)\n", al) == []


def test_lint_dots_witness_admits_any_named_argument():
    al = _al(g=_ok("x", "..."))
    assert audit.lint_called_formals("g(x = 1, whatever = 2)\n", al) == []


def test_lint_ignores_named_arguments_inside_nested_calls():
    al = _al(outer=_ok("a"))
    flags = audit.lint_called_formals("x <- outer(inner(b = 1), z = 2)\n", al)
    assert [f["arg"] for f in flags] == ["z"], "deep arg must not leak outward"


def test_lint_ignores_strings_and_comments():
    al = _al(f=_ok("a"))
    text = ('# f(bad = 1)\n'
            'y <- "f(bad2 = 1)"\n'
            "z <- f(a = 1, q = 'x = 1')\n")
    flags = audit.lint_called_formals(text, al)
    assert [f["arg"] for f in flags] == ["q"]


def test_lint_equality_is_not_read_as_named_argument():
    al = _al(f=_ok("a"))
    assert audit.lint_called_formals("f(a == 1)\n", al) == []


def test_lint_skips_script_local_definitions():
    text = "myFun <- function(q) q\ny <- myFun(qq = 3)\n"
    assert audit.lint_called_formals(text, _al()) == []
    al = _al(myFun=_ok("q"))
    assert audit.lint_called_formals(text, al) == [], "local def is script-owned"


def test_lint_ignores_non_witnessed_entries():
    al = _al(zz={"state": "primitive"}, uu={"state": "unresolved"})
    assert audit.lint_called_formals("zz(a = 1)\nuu(b = 2)\n", al) == []


def test_allowlist_snapshot_carries_the_minimum_witness():
    snapshot = json.loads(ALLOWLIST_PATH.read_text(encoding="utf-8"))
    assert snapshot["schema"] == "m7-formals-allowlist-1"
    entry = snapshot["entries"]["commandArgs"]
    assert entry["state"] == "ok"
    formals = entry["formals"]
    formals = [formals] if isinstance(formals, str) else formals
    assert formals == ["trailingOnly"], \
        "era-R witness: commandArgs carries ONLY trailingOnly"


def test_rehearsed_bytes_lint_clean_against_snapshot():
    text = FIXED_RUNNER.read_text(encoding="utf-8")
    snapshot = json.loads(ALLOWLIST_PATH.read_text(encoding="utf-8"))
    assert audit.lint_called_formals(text, snapshot) == []


def test_defect_injection_lint_fires_against_snapshot():
    text = FIXED_RUNNER.read_text(encoding="utf-8")
    snapshot = json.loads(ALLOWLIST_PATH.read_text(encoding="utf-8"))
    bad = [ln.replace("trailingOnly = TRUE)",
                      "trailingOnly = TRUE, removeDuplicates = FALSE)")
           for ln in text.splitlines(keepends=True)]
    assert sum("removeDuplicates" in ln for ln in bad) == 1
    flags = audit.lint_called_formals("".join(bad), snapshot)
    assert [(f["name"], f["arg"]) for f in flags] == [
        ("commandArgs", "removeDuplicates")]
