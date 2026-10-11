#!/usr/bin/env python3
"""Anchor-probe mode laws for the bootstrap-vs-sigminer campaign harness.

GO-05 (charter SCOPE B follow-on, docs/devlog/2026-10-10-m7-bootstrap-campaign.md).
The single authoritative full shot is the RB-10 doctrine: at most one ledger
entry with mode=="full" is lawful, and a red-anchor shot is unrecoverable.
So the anchor gate at full shape (K=1000, S=1000, n_sig=50, S_ANCHOR=25,
R_ANCHOR=200) must be calibrated WITHOUT consuming that shot. This module
pins the --anchor-probe instrument that does exactly that:

  (1) probe rides the FULL shape table (executed capture over the selector;
      the smoke/full tables themselves are pinned against refit),
  (2) the dispatch executes data bytes + census + anchor stage + oracle +
      probe-grade result.md + reader pass, then quits BEFORE the probe
      stage: no probe witnesses, no tier decision, no timed arms, no
      campaign_timings.csv, no ratio -- every claim-producing stage skipped
      (structural slice laws over the dispatch block),
  (3) the ledger entry {"kind":"anchor-probe","grade":"calibration","ts":...}
      carries no mode key, so the reader's shot-count predicate
      (mode=="full") ignores it: the single-full-shot law survives the probe
      (executed on the target interpreter + synthetic-ledger gate checks),
  (4) probe-grade result.md is claim-free (no MEASURED/tier/claimable/ratio
      lines) yet names the anchor oracle verbatim, and the reader-side
      verifier passes it as non-claiming,
  (5) executed refusals: dirty outdir, and pairing --anchor-probe with
      --smoke or a non-full mode,
  (6) the anchor gate constants stay frozen -- a probe never relaxes them.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
CAMPAIGN = REPO / "bench" / "bootstrap" / "run_campaign.R"
VC = str(REPO / "bench" / "m7" / "tools" / "verify_campaign.py")
RSCRIPT = shutil.which("Rscript")
HW_PROFILE = ("host-R campaign | Apple Silicon | 10 cores | "
              "hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2")
SEED = 20260928

# The authoritative shape the probe must ride (frozen; pre-registration law).
FULL_SHAPE = {"K": 1000, "S": 1000, "N_SIG": 50, "S_ANCHOR": 25, "R_ANCHOR": 200}
# The rehearsal shape --smoke keeps, pinned against refit by association.
SMOKE_SHAPE = {"K": 80, "S": 12, "N_SIG": 8, "S_ANCHOR": 4, "R_ANCHOR": 20}
# A gate-passing anchor oracle payload for the fixture-side tests.
ORACLE_JSON = ('{"ok": true, "n_cells": 1250, "overlap_frac": 1.0, '
               '"median_ok_frac": 1.0, "n_failed_overlap": 0}')


def _campaign_src() -> str:
    assert CAMPAIGN.exists(), f"missing instrument {CAMPAIGN}"
    return CAMPAIGN.read_text(encoding="utf-8")


def _r(program: str) -> str:
    """Run one R program on the target interpreter; fail fast, return stdout."""
    assert RSCRIPT, "Rscript absent -- skip-not-skip"
    out = subprocess.run(
        [RSCRIPT, "--vanilla", "-e", program],
        capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, f"R failed (rc={out.returncode}):\n{out.stderr}"
    return out.stdout


def _capture_defs(src: str, names: list[str]) -> str:
    """House capture pattern: re-evaluate the named top-level closures of
    `src` into a fresh environment. The caller splices its body after this
    preamble; bindings placed at the body's top (outdir, shape scalars,
    helper stubs) resolve through the fresh environment's parent chain.
    """
    name_vec = ", ".join(f'"{n}"' for n in names)
    return f'''
src <- "{src}"
env <- new.env(parent = globalenv())
for (e in parse(src)) {{
  if (is.call(e) && length(e) == 3L &&
      as.character(e[[1L]]) %in% c("<-", "<<-", "=") && is.name(e[[2L]]) &&
      as.character(e[[2L]]) %in% c({name_vec})) {{
    e[[3L]] <- eval(e[[3L]], env)
    assign(as.character(e[[2L]]), e[[3L]], env)
  }}
}}
'''


def _vc_cli(*argv: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, VC, *argv],
                          capture_output=True, text=True)


def _anchor_lines(median_fn) -> str:
    """25 samples x 50 sigs of witness lines in the house A1/A2 shape:
    per-cell median with a +-3% bootstrap interval bracketing it."""
    def line(i: int, j: int) -> str:
        m = median_fn(i, j)
        return json.dumps({"sample": i, "sig": j, "lo": m * 0.97,
                           "hi": m * 1.03, "median": round(m, 6)}) + "\n"
    return "".join(line(i, j)
                   for i in range(1, FULL_SHAPE["S_ANCHOR"] + 1)
                   for j in range(1, FULL_SHAPE["N_SIG"] + 1))


def _fixture_campaign(tmp: str, *, anchors: bool = True,
                      ledger: str | None = None) -> Path:
    """A reader-verifier-readable campaign dir WITHOUT any real measurement:
    a sentinel rds, its seal, witnesses within gate tolerance, optional ledger.
    """
    d = Path(tmp)
    d.mkdir(parents=True, exist_ok=True)
    (d / "witnesses").mkdir(exist_ok=True)
    payload = b"anchor-probe-fixture-not-a-real-rds\n"
    (d / "campaign.rds").write_bytes(payload)
    seal = {"sha256": hashlib.sha256(payload).hexdigest(),
            "campaign_rds": "campaign.rds", "host": "fixture",
            "hw_profile": HW_PROFILE, "generator": "gen_campaign.R",
            "argv": ["--seed", str(SEED)]}
    (d / "seal.json").write_text(json.dumps(seal) + "\n", encoding="utf-8")
    if ledger is not None:
        (d / "campaign_launches.jsonl").write_text(ledger, encoding="utf-8")
    if anchors:
        # A2 sits 1% off A1 everywhere: far inside MEDIAN_REL_TOL, overlap full.
        base = lambda i, j: 1.0 + ((i * 50 + j) % 7) * 0.05
        (d / "witnesses" / "anchor_A1.jsonl").write_text(
            _anchor_lines(base), encoding="utf-8")
        (d / "witnesses" / "anchor_A2.jsonl").write_text(
            _anchor_lines(lambda i, j: base(i, j) * 1.01), encoding="utf-8")
    return d


def _harness(argv: list[str]) -> subprocess.CompletedProcess:
    """One executed harness invocation, profile pinned; bounded so that a law
    regression which would ignite a campaign fails loudly instead of running
    for hours."""
    assert RSCRIPT, "Rscript absent -- skip-not-skip"
    cmd = [RSCRIPT, "--vanilla", str(CAMPAIGN), "--", *argv]
    env = dict(os.environ, M7_HW_PROFILE=HW_PROFILE)
    return subprocess.run(cmd, capture_output=True, text=True, env=env,
                          timeout=600)


def _dispatch_block(src: str) -> str:
    """Text of the top-level probe dispatch, from its opener to its close."""
    opener = "if (anchorProbe) {"
    assert opener in src, "anchor-probe dispatch block absent from the harness"
    start = src.index(opener)
    end = src.index("\n}\n", start)
    return src[start:end + 3]


def _write_probe_md(tmp: str) -> None:
    """Execute the harness's own probe-grade result.md writer on the target
    interpreter against a prepared fixture dir, with the shape scalars and
    host helpers bound to fixtures. The oracle JSON rides through verbatim."""
    program = _capture_defs(str(CAMPAIGN), ["write_probe_result"]) + f'''
outdir <- "{tmp}"
K <- 1000L; S <- 1000L; N_SIG <- 50L; S_ANCHOR <- 25L; R_ANCHOR <- 200L
SEED <- {SEED}L
CAMPAIGN_HW_PIN <- "{HW_PROFILE}"
host_name <- function() "fixture-host"
get("write_probe_result", env)(r'({ORACLE_JSON})')
'''
    _r(program)


# ------------------------------------------------------------------ (1) ----

def test_shape_tables_are_pinned_for_both_branches() -> None:
    # Arrange: the harness shape selector is the single top-level `if` node
    # assigning N_SIG; execute it under each branch binding on the target
    # interpreter rather than pattern-matching its text.
    src = str(CAMPAIGN)
    program = f'''
src <- "{src}"
for (branch in c(FALSE, TRUE)) {{
  env <- new.env(parent = globalenv())
  assign("smoke", branch, env)
  for (e in parse(src)) {{
    if (is.call(e) && length(e) >= 3L && identical(as.character(e[[1L]]), "if")) {{
      dd <- paste(deparse(e), collapse = " ")
      if (grepl("N_SIG <-", dd, fixed = TRUE)) eval(e, env)
    }}
  }}
  cat(sprintf("%s|%d|%d|%d|%d|%d\\n", if (branch) "TRUE" else "FALSE",
    get("K", env), get("S", env), get("N_SIG", env),
    get("S_ANCHOR", env), get("R_ANCHOR", env)))
}}
'''
    # Act
    rows = {}
    for l in _r(program).strip().splitlines():
        parts = l.split("|")
        if len(parts) == 6:
            rows[parts[0]] = parts[1:]
    order = ("K", "S", "N_SIG", "S_ANCHOR", "R_ANCHOR")
    # Assert: the authoritative full table verbatim...
    assert rows["FALSE"] == [str(FULL_SHAPE[k]) for k in order], \
        f"full shape table refit: {rows['FALSE']}"
    # ...and the rehearsal table it must never share a scalar with.
    assert rows["TRUE"] == [str(SMOKE_SHAPE[k]) for k in order], \
        f"smoke shape table refit: {rows['TRUE']}"


# ------------------------------------------------------------------ (2) ----

def test_probe_switch_pairing_guard_and_ledger_gating_exist() -> None:
    src = _campaign_src()
    # Arrange/Act/Assert: valueless switch parsed from the house arg idiom...
    assert "--anchor-probe" in src, "--anchor-probe flag not recognised"
    assert "anchorProbe <-" in src, "anchorProbe switch not defined"
    # ...paired to the full table only, refused with --smoke or a pilot mode...
    assert 'if (anchorProbe && (smoke || mode != "full"))' in src, \
        "pairing guard (anchorProbe requires --mode full, no --smoke) missing"
    # ...and the ordinary launch-ledger append (pilot/probe entries) gated off
    # for probe runs, which write their own non-shot entry.
    assert "if (!anchorProbe) {" in src, "launch-gate trio not gated off for probes"
    assert src.index("if (!anchorProbe) {") < src.index('append_ledger(if (smoke)'), \
        "the pilot/probe ledger append must sit behind the !anchorProbe gate"


def test_probe_dispatch_skips_every_claim_producing_stage() -> None:
    src = _campaign_src()
    block = _dispatch_block(src)
    # Assert: the dispatch runs the anchor stage, the oracle, the probe-grade
    # result.md and the reader pass, and quits zero.
    for needle in ("write_anchor(", '"--anchor-check"', "write_probe_result(",
                   "call_oracle_rc(character(0))", "PROBE-COMPLETE",
                   "quit(status = 0L)", "append_probe_ledger()"):
        assert needle in block, f"probe dispatch missing {needle!r}"
    # Assert: no claim-producing stage survives inside the dispatch.
    for banned in ("probe_once", '"--decide"', '"--floor-check"', "arm_A",
                   "campaign_timings", "invariance", "EMITTER", "ratio",
                   '"--launch-gate"', "write_result("):
        assert banned not in block, f"probe dispatch must not run {banned!r}"
    # Assert: the hard ordering law -- the probe quits before the probe stage
    # is ever announced, mirroring the Tier-C early-quit idiom.
    announce = src.index('say("[campaign] probes (')
    assert src.index("PROBE-COMPLETE") < announce, \
        "probe dispatch must quit before the probe stage"


# ------------------------------------------------------------------ (3) ----

def test_probe_ledger_entry_is_not_a_full_shot() -> None:
    # Arrange: execute the harness's own ledger writer against a temp dir,
    # with utc/append_line bound to deterministic fixtures.
    with tempfile.TemporaryDirectory() as tmp:
        program = _capture_defs(str(CAMPAIGN), ["append_probe_ledger"]) + f'''
outdir <- "{tmp}"
utc <- function() "2026-10-11T00:00:00"
append_line <- function(path, line) cat(line, "\\n", file = path, append = TRUE)
get("append_probe_ledger", env)()
cat(readLines(file.path(outdir, "campaign_launches.jsonl"), warn = FALSE), sep = "\\n")
'''
        # Act
        raw = _r(program).strip().splitlines()
        # Assert: exactly one line, well-formed JSON, non-shot by predicate.
        assert len(raw) == 1, f"expected one ledger line, got {raw!r}"
        entry = json.loads(raw[0])
        assert entry.get("kind") == "anchor-probe", entry
        assert entry.get("grade") == "calibration", entry
        assert "mode" not in entry, \
            f"probe entry must carry no mode key: {entry!r}"

        # The reader-side law, pinned on a synthetic ledger: probe-only
        # entries are invisible to the shot counter; a real launch/full
        # entry still trips the gate.
        with tempfile.TemporaryDirectory() as d:
            ledger = Path(d) / "campaign_launches.jsonl"
            ledger.write_text(raw[0] + "\n", encoding="utf-8")
            gate = _vc_cli("--launch-gate", "--mode", "full", "--campaign", str(d))
            assert gate.returncode == 0, gate.stdout + gate.stderr
            ledger.write_text(raw[0] + "\n"
                              + '{"kind":"launch","mode":"full",'
                                '"ts":"2026-10-11T00:00:01"}\n', encoding="utf-8")
            gate = _vc_cli("--launch-gate", "--mode", "full", "--campaign", str(d))
            assert gate.returncode == 3, \
                f"launch/full entry must trip the gate: {gate.stdout!r}"


def test_anchor_check_passes_the_probe_shaped_witnesses() -> None:
    # Guard the fixture itself: 1250 cells, overlap full, rel-deviation 1%.
    with tempfile.TemporaryDirectory() as tmp:
        _fixture_campaign(tmp)
        out = _vc_cli("--anchor-check", "--campaign", tmp)
        assert out.returncode == 0, out.stdout + out.stderr
        res = json.loads(out.stdout)
        assert res["ok"] is True and res["n_cells"] == 1250, res


# ------------------------------------------------------------------ (4) ----

def test_probe_grade_result_md_is_claim_free_and_verbatim() -> None:
    # Arrange: a reader-readable campaign dir with a probe-grade ledger entry.
    probe_ledger = ('"kind":"anchor-probe","grade":"calibration",'
                    '"ts":"2026-10-11T00:00:00"')
    with tempfile.TemporaryDirectory() as tmp:
        d = _fixture_campaign(tmp, ledger="{" + probe_ledger + "}\n")
        # Act: the harness's own writer, executed on the target interpreter.
        _write_probe_md(tmp)
        md = (d / "result.md").read_text(encoding="utf-8")

    # Assert: probe grade, full shape named, oracle verbatim...
    assert "anchor-probe" in md, md
    assert ORACLE_JSON in md, f"oracle JSON not verbatim:\n{md}"
    assert "K=1000" in md and "S=1000" in md and "n_sig=50" in md, md
    assert "S_ANCHOR=25" in md and "R_ANCHOR=200" in md, md
    # ...and zero claim language the reader could mistake for measurement.
    for banned in ("MEASURED", "tier:", "claimable:", "ratio(A1/A2)",
                   "--floor-gate", "verdict: PASS"):
        assert banned not in md, f"probe result.md carries claim language {banned!r}"

    # Reader-side cross-check: the same bytes pass as an unmeasured run.
    with tempfile.TemporaryDirectory() as tmp:
        _fixture_campaign(tmp, ledger="{" + probe_ledger + "}\n")
        _write_probe_md(tmp)
        verdict = _vc_cli("--campaign", tmp)
        assert verdict.returncode == 0, verdict.stdout + verdict.stderr
        report = json.loads(verdict.stdout)
        assert report["ok"] is True, report
        names = {c["check"] for c in report["checks"]}
        assert "launch-ledger" in names, report["checks"]
        assert "anchor-gates-informational" in names, report["checks"]
        assert "ratio-fidelity" not in names, \
            f"no claim path may be checked without timings: {sorted(names)}"
        assert not str(report["claims"].get("verdict", "")).startswith("MEASURED"), \
            report["claims"]


# ------------------------------------------------------------------ (5) ----

def test_probe_refuses_dirty_outdir_and_mispairings_executed() -> None:
    # Arrange: sentinel fixtures so every refused path dies fast even if a
    # law regresses -- the fake rds detonates at readRDS, long before probes.
    cases = [
        ("dirty full-probe", ["--mode", "full", "--anchor-probe"]),
        ("smoke pairing", ["--mode", "pilot", "--smoke", "--anchor-probe"]),
        ("pilot pairing", ["--mode", "pilot", "--anchor-probe"]),
    ]
    for label, argv in cases:
        with tempfile.TemporaryDirectory() as tmp:
            _fixture_campaign(tmp)
            # Act: executed against the real instrument, profile pinned.
            out = _harness([*argv, "--outdir", tmp])
            # Assert: rc=2 harness refusal naming the probe mode -- not a
            # generic usage death, and never an ignition.
            assert out.returncode == 2, \
                f"[{label}] expected rc=2 refusal, got {out.returncode}:\n" \
                f"{out.stdout}\n{out.stderr}"
            assert "--anchor-probe" in out.stdout + out.stderr, \
                f"[{label}] refusal must name --anchor-probe:\n{out.stdout}"


# ------------------------------------------------------------------ (6) ----

def test_anchor_gate_constants_are_frozen() -> None:
    vc = Path(VC).read_text(encoding="utf-8")
    assert ("MIN_OVERLAP, MIN_MEDIAN_OK, MEDIAN_REL_TOL = 0.90, 0.95, 0.15" in vc), \
        "anchor gate constants refitted"
