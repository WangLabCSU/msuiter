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
  * every repository path referenced by a workflow actually exists
    (sanctioned build-output roots are excepted by EXACT token only, and a
    built-in firing control proves a genuinely dangling path still reddens).

Runs in CI (guards job) and locally:  python3 tools/ci-selfcheck.py
Exit 0 = all checks pass; exit 1 = at least one FAIL printed.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import action_pins

try:
    import yaml
except ImportError:
    # P2e degraded-mode behavior: when PyYAML is unavailable, fail with a
    # clear error naming what to install, rather than surfacing a raw traceback.
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


# The instruments that make the sanitizer legs LOUD (issue #32 D1): without
# any one of them an instrument could be dead while the leg still reports
# green/red by accident. Pinned by name so gutting the harness is a guards
# failure, not a silent weakening.
LOUDNESS_LAW_MARKERS = (
    "probe_rustc",             # rustc must accept -Zsanitizer=<value>
    "census",                  # executed-work census: zero executed work -> red
    "build_canary",            # reviewed canary compiled with/without the sanitizer
    "run_canary",
    "assert_trip_reported",    # live canary violation MUST be reported
    "assert_trip_silent",      # uninstrumented canary MUST stay silent
    "assert_clean_silent",     # clean canary MUST stay silent
)


def loudness_law_markers():
    """Return the loudness-law markers missing from the leg harness."""
    harness = REPO / "tools/deep-checks/run_sanitizer_leg.sh"
    if not harness.is_file():
        return list(LOUDNESS_LAW_MARKERS) + ["tools/deep-checks/run_sanitizer_leg.sh"]
    h = harness.read_text(encoding="utf-8")
    return [m for m in LOUDNESS_LAW_MARKERS if m not in h]


# The valgrind counterpart (issue #32, D4): the weekly arm used to re-run the
# FULL testthat suite under valgrind through R CMD check --use-valgrind --
# measured 5 h 56 m on a single 'Running testthat.R' before the 360-min
# platform ceiling killed the job (2026-10-19 and 2026-10-20 cancelled;
# 2026-10-12 completed at 5 h 40 m 53 s, barely under). The arm's report was
# a weekly coin-flip AND its conclusion was masked by job-level
# continue-on-error. The bounded law: a nominated native-sentry roster runs
# under valgrind with an executed-work census, the ERROR SUMMARY / LEAK
# SUMMARY totals are required evidence (absence = valgrind never ran = red),
# the canaries prove the tool is live both ways, and a hard wall-clock budget
# makes slow-to-death impossible. Pinned by name so gutting any instrument is
# a guards failure, not a silent weakening.
VALGRIND_LOUDNESS_MARKERS = (
    "valgrind_report_census",  # ERROR SUMMARY / LEAK SUMMARY totals are required
    "census",                  # executed-work census: zero executed work -> red
    "build_canary",            # reviewed leaky/clean canaries
    "run_canary",
    "assert_trip_reported",    # valgrind-wrapped trip MUST be reported
    "assert_trip_silent",      # unwrapped trip MUST stay silent (discrimination)
    "assert_clean_silent",     # clean canary under valgrind MUST stay silent
    "valgrind_budget",         # hard wall-clock budget: slow-to-death impossible
)


def valgrind_loudness_markers():
    """Return the loudness-law markers missing from the valgrind harness."""
    harness = REPO / "tools/deep-checks/run_valgrind_leg.sh"
    if not harness.is_file():
        return list(VALGRIND_LOUDNESS_MARKERS) + ["tools/deep-checks/run_valgrind_leg.sh"]
    h = harness.read_text(encoding="utf-8")
    return [m for m in VALGRIND_LOUDNESS_MARKERS if m not in h]


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
    check("r-lib check action used",
          any(u.startswith("r-lib/actions/check-r-package")
              and action_pins.has_major(u, c, 2)
              for u, c in action_pins.uses_pairs(ci_text)))
    # The action's input is `error-on` (hyphen): an `error_on` key is
    # silently dropped and the action defaults to the warning gate, which
    # contradicts the stated error-level contract (CI audit 2026-10-07).
    check("check action gate uses hyphenated error-on input",
          "'error-on'" in str(rjob) and "error_on" not in str(rjob))
    # The input is a RAW R expression (cf. `args`): the value must ship its
    # own quotes ('"error"'), a bare symbol renders (error) and R aborts
    # with "object 'error' not found" (CI audit 2026-10-07, round 4).
    check("error-on value is a quoted R string literal",
          "'error-on': '\"error\"'" in str(rjob))
    # The 4.3 floor arm installs dependencies: '"hard"' (Suggests skipped),
    # yet R CMD build needs the declared VignetteBuilder -- knitr must be a
    # CRAN-only extra or the build dies in loadVignetteBuilder() (audit
    # 2026-10-07: 902 ms exit 1).
    check("4.3 floor arm ships the vignette builder via extras",
          "any::knitr" in str(rjob))
    # Same hard-arm Suggests skip hits the check tests: the testthat runner
    # hard-fails with "there is no package called 'testthat'" when
    # dependencies: '"hard"' drops it (CI audit 2026-10-07, round 5).
    # testthat + its test-side companions must ride in as CRAN-only extras.
    check("4.3 floor arm ships the testthat runner deps via extras",
          "any::testthat" in str(rjob) and "any::withr" in str(rjob))

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
    pairs = (action_pins.uses_pairs(ci_text)
             + action_pins.uses_pairs(txt(SCHED)))
    bad = [f"{u} #{c}" for u, c in pairs
           if not action_pins.is_acceptably_pinned(u, c)]
    check("all actions pinned (major tag or attested SHA)", not bad, str(bad))
    check("r-lib actions @v2",
          all(action_pins.has_major(u, c, 2) for u, c in pairs
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
    # ---- valgrind leg: the loudness-law extension (issue #32, D1 class) ----
    # Law change (this selfcheck moves WITH the contract it governs): the
    # retired valgrind job ran `rcmdcheck(..., error_on="never",
    # --use-valgrind)` -- it could not fail even when valgrind reported real
    # defects, it raced the 6 h platform ceiling and lost (measured history:
    # one completed/success at 5 h 40 m 53 s, then cancelled at 6 h 00 m 53 s),
    # and its job-level continue-on-error: true masked even the cancellation
    # as a green job. A report-only arm that never demonstrably produced its
    # report is the D1 vacuous-green class exactly. The arm now runs the
    # bounded native-sentry leg: nominated roster, REQUIRED ERROR/LEAK
    # SUMMARY totals, canaries both ways, hard wall-clock budget -- and it is
    # a HARD gate: no continue-on-error on either heavy leg.
    vg = sched["jobs"].get("valgrind", {})
    check("scheduled: valgrind job is a hard gate (no continue-on-error)",
          bool(vg) and vg.get("continue-on-error") is not True)
    check("scheduled: valgrind job carries a timeout-minutes budget",
          isinstance(vg.get("timeout-minutes"), (int, float))
          and 0 < vg.get("timeout-minutes") <= 120,
          f"got {vg.get('timeout-minutes')}")
    vt = job_script(sched, "valgrind")
    check("scheduled: valgrind step invokes the loudness-law leg harness",
          "run_valgrind_leg.sh leg" in vt)
    check("scheduled: the vacuous whole-suite --use-valgrind mode is retired",
          "--use-valgrind" not in vt)
    missing_vg = valgrind_loudness_markers()
    check("valgrind harness exists and enforces the loudness law "
          "(report census, canary trip/silent gates, wall-clock budget)",
          not missing_vg, f"missing {missing_vg}")
    sani = sched["jobs"].get("sanitizer", {})
    sani_matrix = sani.get("strategy", {}).get("matrix", {}) or {}
    sani_set = set(sani_matrix.get("sanitizer", []))
    # Issue #32 D1 law change (this selfcheck moves WITH the contract it
    # governs): the matrix value `undefined` never existed in rustc's
    # -Zsanitizer vocabulary -- the retired leg died at target discovery and
    # produced zero signal while looking red. The executed set is now the
    # rustc-accepted {address, leak}; pinned by EXACT set equality so any
    # silent addition (including a reintroduced `undefined`), removal, or
    # substitution goes red.
    check("scheduled: sanitizer matrix = exact set {address, leak} (rustc-accepted)",
          sani_set == {"address", "leak"}, f"got {sorted(sani_set)}")
    # Wiring moved from the retired RUSTFLAGS inline step to the loudness-law
    # harness. Both halves stay loaded: the workflow must invoke the leg
    # script with the matrix value, and the harness itself must still carry
    # every loudness-law instrument (a deleted canary or deleted census dies
    # the guards arm, so a dead instrument cannot masquerade as green).
    leg = job_script(sched, "sanitizer")
    check("scheduled: sanitizer legs invoke the loudness-law harness per matrix value",
          "run_sanitizer_leg.sh leg" in leg and "${{ matrix.sanitizer }}" in leg)
    missing_markers = loudness_law_markers()
    check("sanitizer harness exists and enforces the loudness law "
          "(rustc probe, executed-work census, canary trip/clean gates)",
          not missing_markers, f"missing {missing_markers}")
    # Issue #32: the sanitizer job's continue-on-error:true is retired with
    # the harness. Pre-#37 archived weekly logs show the pre-harness legs
    # "passing" in 22 s/12 s (whole jobs, checkout included) -- a masked dead
    # arm is exactly what the flag let through. The harness now dies loudly
    # on every vacuous shape, so the mask is gone: green means the harness
    # said LEG GREEN, never "the step never failed".
    check("scheduled: sanitizer job is a hard gate (no continue-on-error)",
          bool(sani) and sani.get("continue-on-error") is not True)
    check("scheduled: sanitizer job carries a timeout-minutes budget",
          isinstance(sani.get("timeout-minutes"), (int, float))
          and 0 < sani.get("timeout-minutes") <= 120,
          f"got {sani.get('timeout-minutes')}")

    # ---- scheduled pkgdown site build (U-M7-04 slice-C, C5) ----------------
    # The per-PR 13-check topology is frozen, so the site render is pinned
    # to the weekly deep check -- and it is a HARD gate: no continue-on-error.
    site = sched["jobs"].get("site", {})
    check("scheduled: pkgdown site job exists", bool(site))
    check("scheduled: site job is a hard gate (no continue-on-error)",
          bool(site) and site.get("continue-on-error") is not True)
    st = job_script(sched, "site")
    check("scheduled: site job renders via pkgdown::build_site",
          "pkgdown::build_site" in st)
    check("scheduled: site job asserts reference index + extending article rendered",
          "reference/index.html" in st and "articles/extending.html" in st)
    check("scheduled: site job uploads the rendered site artifact",
          any("upload-artifact@" in u for u in uses_list(site)))

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
    # Sanctioned build-output allowance (issue #32, controller law change
    # recorded here and in the lane manifest): `docs/dev` is the pkgdown
    # devel-mode OUTPUT ROOT that the site job's existence probe asserts at
    # RUNTIME (development.mode: devel writes docs/dev/, the site root is
    # reserved for release builds). It is a build artifact, never a
    # committed path -- exactly the class the D1 loudness lesson warned
    # about from the other side: a check must not gate on a path the
    # configuration never writes, and this scanner must not demand a path
    # the build only produces. The allowance is EXACT-TOKEN (no prefix, no
    # glob) and stays honest via the firing control below: a genuinely
    # dangling sibling of the sanctioned root must still go red.
    sanctioned_build_outputs = {"docs/dev"}

    def missing(refs):
        return [t for t in sorted(refs)
                if t.rstrip("/") not in sanctioned_build_outputs
                and not (REPO / t.rstrip("/")).exists()]

    refs = set()
    for wtext in (ci_text, txt(SCHED)):
        for m2 in re.finditer(
                r"(?:tools|src/rust|docs|tests)/[A-Za-z0-9_][A-Za-z0-9_./-]*",
                wtext):
            token = m2.group(0).rstrip(".-")
            refs.add(token)
    missing_paths = missing(refs)
    check("every repo path referenced by a workflow exists "
          "(sanctioned build outputs excepted by exact token)",
          not missing_paths, str(missing_paths))
    # Firing control (house law: scanners without a firing positive control
    # are vacuous and refused): the allowance admits ONLY the sanctioned
    # token; its uncommitted sibling and a bogus tools/ path must redden.
    control = missing({"docs/dev", "docs/dev/",
                       "docs/dev/nothing-committed-here-9f3b",
                       "tools/no-such-tool-9f3b.sh"})
    check("path-scanner firing control: narrow allowance, dangling paths still red",
          control == ["docs/dev/nothing-committed-here-9f3b",
                      "tools/no-such-tool-9f3b.sh"],
          f"control leaked {control}")

    print()
    if failures:
        print(f"ci-selfcheck: FAIL ({len(failures)} check(s))")
        return 1
    print("ci-selfcheck: PASS (all CI wiring assertions hold)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
