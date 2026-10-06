#!/usr/bin/env python3
"""CI selfcheck for msuiter (U-M0-07).

Static, network-free validation of the GitHub Actions wiring against the
contracts it is supposed to implement:

  * every workflow/dependabot file parses with yaml.safe_load;
  * every third-party action is pinned to a major version (@vN);
  * the ARCHITECTURE.md section 9 CI contract items are present
    (3 OS matrix incl. R-4.3 Linux + fail-allowed devel, --as-cran,
    _R_CHECK_LIMIT_CORES_, cargo test/clippy/deny, repo-mode testthat,
    scheduled valgrind + sanitizers, codecov wiring);
  * the ADR 0002 residuals are wired: MSRV 1.71 build proof on
    Linux + Windows (section 4.4/5), and the Cargo.lock pins
    (matrixmultiply 0.3.9, rayon 1.10.x, lock v3) asserted by a CI
    step next to the dependabot ignore rules (belt and braces);
  * every repository path referenced by a workflow actually exists.

Runs in CI (guards job) and locally:  python3 tools/ci-selfcheck.py
Exit 0 = all checks pass; exit 1 = at least one FAIL printed.
"""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    # P2e 降级行为：PyYAML 不可用时给明确报错与安装提示，而不是 traceback。
    sys.stderr.write(
        "ci-selfcheck: cannot run — PyYAML is not installed.\n"
        "  This script validates workflow YAML with yaml.safe_load().\n"
        "  Install it first, e.g.:  python3 -m pip install pyyaml\n"
        "  (inside a venv/conda env, use that environment's pip)\n")
    sys.exit(1)

REPO = Path(__file__).resolve().parent.parent
CI = REPO / ".github/workflows/ci.yml"
SCHED = REPO / ".github/workflows/scheduled.yml"
DEP = REPO / ".github/dependabot.yml"
LOCK = REPO / "src/rust/Cargo.lock"

failures = []


def check(name, ok, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"{tag}  {name}" + (f" — {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(name)
    return ok


def txt(path):
    return path.read_text(encoding="utf-8")


def load_yaml(path):
    return yaml.safe_load(txt(path))


def uses_list(doc):
    """All `uses:` targets in a workflow doc, as strings."""
    out = []

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "uses" and isinstance(v, str):
                    out.append(v)
                else:
                    walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(doc)
    return out


def run_blocks(doc):
    """All `run:` script bodies in a workflow doc, as strings."""
    out = []

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "run" and isinstance(v, str):
                    out.append(v)
                else:
                    walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(doc)
    return out


def job_script(doc, job):
    """Concatenated run scripts of one job."""
    return "\n".join(run_blocks(doc.get("jobs", {}).get(job, {})))


def main():
    # ---- files exist and parse -------------------------------------------
    for p in (CI, SCHED, DEP, LOCK,
              REPO / "src/rust/deny.toml",
              REPO / "tools/check-dep-direction.sh",
              REPO / "tools/vendor.sh",
              REPO / "tools/rng-kat.py",
              REPO / "tools/docs-sync.R"):
        check(f"file exists: {p.relative_to(REPO)}", p.is_file())

    try:
        ci = load_yaml(CI)
        sched = load_yaml(SCHED)
        dep = load_yaml(DEP)
        check("workflow YAML parses (safe_load)", True)
    except Exception as e:  # noqa: BLE001 - report and stop
        check("workflow YAML parses (safe_load)", False, str(e))
        return 1

    ci_text = txt(CI)

    # ---- ci.yml triggers and global env ----------------------------------
    trig = ci.get(True) or ci.get("on") or {}
    # yaml 1.1 parses the bare key `on` as boolean True
    for t in ("push", "pull_request", "workflow_dispatch"):
        check(f"ci.yml trigger: {t}", t in trig)

    check("ci.yml env _R_CHECK_LIMIT_CORES_ (FFI contract 6)",
          "_R_CHECK_LIMIT_CORES_" in (ci.get("env") or {}))

    # ---- R-CMD-check matrix ----------------------------------------------
    rjob = ci["jobs"]["R-CMD-check"]
    configs = rjob["strategy"]["matrix"]["config"]
    pairs = {(c["os"], str(c["r"])) for c in configs}
    expected = {
        ("macos-latest", "release"), ("windows-latest", "release"),
        ("ubuntu-latest", "release"),
        ("macos-latest", "oldrel-1"), ("windows-latest", "oldrel-1"),
        ("ubuntu-latest", "oldrel-1"),
        ("ubuntu-latest", "4.3"),      # package floor, Linux
        ("ubuntu-latest", "devel"),
    }
    check("R matrix = 3 OS x {release, oldrel-1} + {4.3 Linux, devel}",
          pairs == expected, f"got {sorted(pairs)}")
    check("devel only on Linux", all(c["os"] == "ubuntu-latest"
                                     for c in configs if str(c["r"]) == "devel"))
    check("R-4.3 only on Linux", all(c["os"] == "ubuntu-latest"
                                     for c in configs if str(c["r"]) == "4.3"))
    check("devel job allowed to fail (continue-on-error)",
          "devel" in str(rjob.get("continue-on-error", "")))
    check("fail-fast disabled", rjob["strategy"].get("fail-fast") is False)

    check("rcmdcheck args --as-cran + --no-manual",
          "--as-cran" in str(rjob) and "--no-manual" in str(rjob))
    check("r-lib check action used", "r-lib/actions/check-r-package@v2"
          in uses_list(ci))

    # every job that runs R must also set up SOME rust toolchain before
    # src/rust builds (extendr 0.9 needs R_HOME; the compiler needs a
    # toolchain). The MSRV proof itself lives in the msrv job + the
    # release gate (both assert rustc 1.71.0 explicitly) -- the rust job
    # deliberately tests stable (CI audit 2026-10-06).
    setup_jobs = [j for j, d in ci["jobs"].items()
                  if any("r-lib/actions/setup-r@" in u for u in uses_list(d))]
    for j in setup_jobs:
        script = job_script(ci, j)
        has_toolchain = ("rustup toolchain install 1.71.0" in script
                         or "rustup default stable" in script)
        check(f"job '{j}' sets up a rust toolchain (before src/rust build)",
              has_toolchain)

    # ---- rust job ---------------------------------------------------------
    rs = job_script(ci, "rust")
    check("cargo test --workspace", "cargo test --workspace" in rs)
    check("clippy --workspace -- -D warnings",
          "cargo clippy --workspace -- -D warnings" in rs)
    check("cargo deny check (all four sections)", "cargo deny check" in rs)
    check("cargo-deny installed via taiki-e/install-action",
          any(u.startswith("taiki-e/install-action@") and "cargo-deny" in str(d)
              for d in ci["jobs"]["rust"]["steps"] for u in uses_list(d)))

    # ---- guards job (U-M0-01/02/05/06 handoff) ----------------------------
    g = job_script(ci, "guards")
    for name, needle in [
        ("tools/check-dep-direction.sh", "sh tools/check-dep-direction.sh"),
        ("tools/vendor.sh --check", "sh tools/vendor.sh --check"),
        ("tools/rng-kat.py", "python3 tools/rng-kat.py"),
        ("tools/docs-sync.R", "Rscript tools/docs-sync.R"),
        ("repo-mode testthat (devtools::test)", "devtools::test("),
    ]:
        check(f"guards job runs {name}", needle in g)
    check("guards job asserts Cargo.lock pins (matrixmultiply 0.3.9)",
          'version = "0.3.9"' in g)
    check("guards job asserts lock v3", "version = 3" in g)

    # ---- MSRV proof job (ADR 0002 §4.4/§5 residual) ------------------------
    msrv = ci["jobs"]["msrv"]
    check("msrv matrix = {ubuntu, windows}",
          set(msrv["strategy"]["matrix"]["os"]) == {"ubuntu-latest",
                                                    "windows-latest"})
    m = job_script(ci, "msrv")
    check("msrv runs cargo +1.71.0 build --workspace",
          "cargo +1.71.0 build --workspace" in m)
    check("msrv runs cargo +1.71.0 test --workspace",
          "cargo +1.71.0 test --workspace" in m)

    # ---- coverage (wiring only, no gate) ----------------------------------
    cov_job_text = str(ci["jobs"].get("coverage", {}))
    check("coverage job uses covr", "covr::" in cov_job_text)
    check("codecov upload wired", "codecov/codecov-action@" in cov_job_text)
    codecov_steps = [s for s in ci["jobs"].get("coverage", {}).get("steps", [])
                     if "codecov/codecov-action@" in str(s.get("uses", ""))]
    check("codecov upload not gated (fail_ci_if_error false)",
          any(s.get("with", {}).get("fail_ci_if_error") is False
              for s in codecov_steps))

    # ---- action pinning (major version) -----------------------------------
    bad = [u for w in (ci, sched) for u in uses_list(w)
           if not re.search(r"@v\d+$", u)]
    check("all actions pinned to a major version (@vN)", not bad, str(bad))
    check("r-lib actions @v2",
          all(u.endswith("@v2") for w in (ci, sched) for u in uses_list(w)
              if u.startswith("r-lib/actions/")))

    # ---- scheduled.yml -----------------------------------------------------
    # yaml 1.1 parses the bare key `on` as boolean True
    sch = sched.get(True) or sched.get("on") or {}
    check("scheduled: workflow_dispatch available", "workflow_dispatch" in sch)
    crons = sch.get("schedule", [])
    check("scheduled: weekly cron",
          bool(crons) and re.fullmatch(r"\S+ \S+ \* \* \S+",
                                       crons[0].get("cron", "")) is not None,
          str(crons))
    check("scheduled: valgrind job, allowed to fail",
          "valgrind" in sched["jobs"]
          and sched["jobs"]["valgrind"].get("continue-on-error") is True
          and "valgrind" in job_script(sched, "valgrind"))
    sani = sched["jobs"].get("sanitizer", {})
    sani_m = str(sani.get("strategy", {}).get("matrix", {}))
    check("scheduled: ASAN/UBSAN matrix {address, undefined}",
          "address" in sani_m and "undefined" in sani_m)
    check("scheduled: sanitizer via RUSTFLAGS -Zsanitizer",
          "-Zsanitizer=" in job_script(sched, "sanitizer")
          or "-Zsanitizer=" in str(sani))

    # ---- dependabot --------------------------------------------------------
    ecosystems = {u["package-ecosystem"]: u for u in dep.get("updates", [])}
    check("dependabot: cargo + github-actions ecosystems",
          {"cargo", "github-actions"} <= set(ecosystems))
    check("dependabot: both weekly",
          all(e.get("schedule", {}).get("interval") == "weekly"
              for e in ecosystems.values()))
    check("dependabot: cargo watches /src/rust",
          ecosystems.get("cargo", {}).get("directory") == "/src/rust")
    ignores = {
        i.get("dependency-name"): i.get("versions", [])
        for i in ecosystems.get("cargo", {}).get("ignore", [])
    }
    check("dependabot ignore: matrixmultiply >=0.3.10 (ADR 0002 §4.4)",
          any(v.startswith(">=") and "0.3.10" in v
              for v in ignores.get("matrixmultiply", [])),
          str(ignores))
    check("dependabot ignore: rayon >=1.11 (ADR 0002 §4.4)",
          any("1.11" in v for v in ignores.get("rayon", [])), str(ignores))

    # ---- Cargo.lock pins (same assertion the CI step makes) ----------------
    lock = txt(LOCK)
    check("Cargo.lock stays version 3 (reads under cargo 1.71)",
          re.search(r"^version = 3$", lock, re.M) is not None)
    check("Cargo.lock pins matrixmultiply 0.3.9",
          re.search(r'name = "matrixmultiply"\nversion = "0\.3\.9"', lock)
          is not None)
    check("Cargo.lock pins rayon 1.10.x",
          re.search(r'name = "rayon"\nversion = "1\.10\.\d+"', lock) is not None)

    # ---- referenced paths exist -------------------------------------------
    refs = set()
    for wtext in (ci_text, txt(SCHED)):
        for m2 in re.finditer(
                r"(?:tools|src/rust|docs|tests)/[A-Za-z0-9_][A-Za-z0-9_./-]*",
                wtext):
            token = m2.group(0).rstrip(".-")
            refs.add(token)
    missing = [t for t in sorted(refs) if not (REPO / t).exists()]
    check("every repo path referenced by a workflow exists",
          not missing, str(missing))

    print()
    if failures:
        print(f"ci-selfcheck: FAIL ({len(failures)} check(s))")
        return 1
    print("ci-selfcheck: PASS (all CI wiring assertions hold)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
