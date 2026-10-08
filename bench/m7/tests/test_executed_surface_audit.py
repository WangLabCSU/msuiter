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
