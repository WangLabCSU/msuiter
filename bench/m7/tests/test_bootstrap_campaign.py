"""(T) bootstrap-vs-sigminer campaign instrument (U-M7-04 GO-05, charter SCOPE B).

Seals the campaign harness BEFORE the campaign runs (pre-registration law:
docs/devlog/2026-10-10-m7-bootstrap-campaign.md is committed first; every
reported number must trace to a witness this protocol names). The reader-side
verifier (tools/verify_campaign.py) is the independent re-adjudicator: it
verdicts the committed campaign from witness bytes alone — R is not trusted
after the fact, exactly as verify_hardware_pin verdicts a table from its own
CSV columns.

Witness schema (frozen here and by the protocol doc):
  seal.json                       {sha256, campaign_rds, host, hw_profile,
                                   generator, argv}
  witnesses/probe_A{1,2,3}_*.jsonl {kind:"probe", arm, shape{S,R}, wall, cpu,
                                    rep, loadavg}            # no verdict fields
  witnesses/arm_A{1,2,3}.jsonl     {kind:"arm", arm, tier, shape, wall, cpu,
                                    load_before, load_after, floor_projection,
                                    floor_ratio, gate}
  witnesses/anchor_A{1,2}.jsonl    {sample, sig, lo, hi, median} per cell
                                   (25 x 50 cells)
  campaign_timings.csv             9-column pinned timings table
  campaign_launches.jsonl          {kind:"launch", mode:"full"|"pilot", ts}
  result.md                        claims lines, each re-derived by the verifier
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

BOOT = HERE.parent / "bootstrap"                     # bench/bootstrap
SEED = 20260928
HW_PROFILE = ("host-R campaign | Apple Silicon | 10 cores | "
              "hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2")


def _vc():
    from tools import verify_campaign as vc          # RED seams 1-3 (absent)
    return vc


def _tmp() -> Path:
    return Path(tempfile.mkdtemp(prefix="m7boot_"))


def _probe(arm: str, wall: float, rep: int = 1) -> dict:
    return {"kind": "probe", "arm": arm, "shape": {"S": 5, "R": 20},
            "wall": wall, "cpu": wall * 1.02, "rep": rep,
            "loadavg": [2.5, 2.4, 2.3]}


def _arm(arm: str, wall: float, tier: str = "B") -> dict:
    return {"kind": "arm", "arm": arm, "tier": tier,
            "shape": {"K": 1000, "S": 1000, "n_sig": 50, "R": 200},
            "wall": wall, "cpu": wall * 1.05,
            "load_before": [2.6, 2.5, 2.4], "load_after": [2.7, 2.5, 2.4],
            "floor_projection": wall * 1.1, "floor_ratio": 3.0,
            "gate": "pass"}


def _anchors(offset_a2: float = 0.0, cells: int = 25 * 50):
    """Fixture anchor witnesses: identical distributions unless offset_a2 moves
    every msuiter interval beyond sigminer's (an overlap-destroying shift)."""
    a1 = [{"sample": f"S{i // 50:02d}", "sig": f"V{i % 50:02d}",
           "lo": 0.90, "hi": 1.10, "median": 1.0} for i in range(cells)]
    a2 = [{"sample": f"S{i // 50:02d}", "sig": f"V{i % 50:02d}",
           "lo": 0.90 + offset_a2, "hi": 1.10 + offset_a2,
           "median": 1.0 + offset_a2} for i in range(cells)]
    return a1, a2


def _campaign_dir(tmp: Path, *, ratio: float = 250.0, tier: str = "B",
                  a1=None, a2=None, probes=None, arms=None) -> Path:
    """Materialize a complete witness campaign for verifier exercises."""
    (tmp / "witnesses").mkdir(parents=True, exist_ok=True)
    rds = tmp / "campaign.rds"
    rds.write_bytes(b"RDA2-fixture-bytes")           # sha256 seal pins this
    digest = hashlib.sha256(rds.read_bytes()).hexdigest()
    (tmp / "seal.json").write_text(json.dumps({
        "sha256": digest, "campaign_rds": "campaign.rds",
        "host": "measurement-host", "hw_profile": HW_PROFILE,
        "generator": "gen_campaign.R", "argv": ["--seed", str(SEED)]}))
    probes = probes if probes is not None else {
        "A1": [_probe("A1", 8.0, r) for r in (1, 2, 3)],
        "A2": [_probe("A2", 0.04, r) for r in (1, 2, 3)],
        "A3": [_probe("A3", 0.30, r) for r in (1, 2, 3)]}
    for arm, recs in probes.items():
        (tmp / "witnesses" / f"probe_{arm}_1.jsonl").write_text(
            "\n".join(json.dumps(r) for r in recs) + "\n")
    a1w = a1 if a1 is not None else _anchors()[0]
    a2w = a2 if a2 is not None else _anchors()[1]
    (tmp / "witnesses" / "anchor_A1.jsonl").write_text(
        "\n".join(json.dumps(r) for r in a1w) + "\n")
    (tmp / "witnesses" / "anchor_A2.jsonl").write_text(
        "\n".join(json.dumps(r) for r in a2w) + "\n")
    wall_a1 = 1000.0
    arms = arms if arms is not None else {
        "A1": [_arm("A1", wall_a1, tier)],
        "A2": [_arm("A2", wall_a1 / ratio, tier)],
        "A3": [_arm("A3", wall_a1 / (ratio / 8), tier)]}
    for arm, recs in arms.items():
        (tmp / "witnesses" / f"arm_{arm}.jsonl").write_text(
            "\n".join(json.dumps(r) for r in recs) + "\n")
    (tmp / "campaign_launches.jsonl").write_text(json.dumps(
        {"kind": "launch", "mode": "full", "ts": "2026-10-10T00:00:00Z"}) + "\n")
    from competitors import timings                   # the pinned 9-col schema
    def row(cell, tool, wall):
        return {"cell": cell, "tool": tool, "arm": cell.split("__")[1],
                "n": "1000", "seconds": wall, "status": "ok",
                "cpu_seconds": wall * 1.05, "host": "measurement-host",
                "hw_profile": HW_PROFILE}
    timings.write_timings(tmp / "campaign_timings.csv", [
        row("bootstrap__sigminer_serial__K1000S1000", "sigminer", wall_a1),
        row("bootstrap__msuiter_pool__K1000S1000", "msuiter", wall_a1 / ratio),
        row("bootstrap__msuiter_single__K1000S1000", "msuiter", wall_a1 / (ratio / 8))])
    return tmp


def _result_md(tmp: Path, claim: str, ratio: float, tier: str) -> None:
    (tmp / "result.md").write_text(
        "# bootstrap-vs-sigminer campaign\n\n"
        f"- tier: {tier}\n"
        f"- ratio(A1/A2) = {ratio!r}\n"
        f"- verdict: {claim}\n")


# -- 1. the frozen generator ---------------------------------------------------------
def test_generator_double_run_is_byte_identical():
    """Data-byte identity is the campaign's foundation; the generator must be
    deterministic under the frozen SEED (double-run sha256 equality)."""
    rscript = shutil.which("Rscript")
    assert rscript, "Rscript absent — skip-not-skip: the missing tool is seen"
    gen = BOOT / "gen_campaign.R"
    assert gen.is_file(), f"missing instrument: {gen}"
    tmp = _tmp()
    try:
        digests = []
        for leg in ("a", "b"):
            out = tmp / leg
            subprocess.run(
                [rscript, "--vanilla", str(gen), "--",
                 "--out", str(out), "--k", "60", "--s", "10",
                 "--sig", "8", "--seed", str(SEED)],
                check=True, capture_output=True, text=True)
            rds = out / "campaign.rds"
            assert rds.is_file(), f"generator did not emit {rds}"
            assert (out / "seal.json").is_file(), "generator owes a seal.json"
            digests.append(hashlib.sha256(rds.read_bytes()).hexdigest())
        assert digests[0] == digests[1], \
            f"generator is not deterministic over SEED={SEED}: {digests}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_generator_seal_matches_data_bytes():
    """Seal-side law: the seal's sha256 must equal the shipped campaign.rds bytes."""
    rscript = shutil.which("Rscript")
    assert rscript, "Rscript absent — skip-not-skip"
    tmp = _tmp()
    try:
        subprocess.run([rscript, "--vanilla", str(BOOT / "gen_campaign.R"), "--",
                        "--out", str(tmp), "--k", "40", "--s", "8",
                        "--sig", "6", "--seed", str(SEED)],
                       check=True, capture_output=True, text=True)
        seal = json.loads((tmp / "seal.json").read_text())
        assert seal["sha256"] == hashlib.sha256(
            (tmp / "campaign.rds").read_bytes()).hexdigest()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# -- 2. the tier ladder (pure, decisive) ----------------------------------------------
# Protocol projection (docs/devlog/2026-10-10-m7-bootstrap-campaign.md §2):
#   wall(S, R) = S * (p + rate * R)   — p per-sample point cost, rate per-replicate
# decided against the six-hour cap; tiers are the frozen R ladder {A:1000, B:200}.
def _fit(p: float, rate: float) -> dict:
    return {"p": p, "rate": rate}


def test_tier_a_taken_when_projection_fits_the_six_hour_cap():
    assert _vc().decide_tier(_fit(2.4, 0.019), cap=21600) == "A"   # -> 21400 s


def test_tier_b_taken_when_a_breaches_cap_but_b_fits():
    assert _vc().decide_tier(_fit(2.4, 0.02), cap=21600) == "B"    # A -> 22400 s


def test_tier_c_when_even_b_breaches():
    assert _vc().decide_tier(_fit(2.4, 0.6), cap=21600) == "C"     # B -> 122400 s


def test_tier_boundary_equal_cap_is_tier_a():
    # exactly the cap is 'fits' (<=), decided, never a coin-flip.
    assert _vc().decide_tier(_fit(2.4, (21600 / 1000 - 2.4) / 1000),
                             cap=21600) == "A"


def test_projection_fits_the_linear_cost_model():
    # probe medians at two replicate shapes (same S_probe=5) pin p and rate.
    lo = [_probe("A1", 5 * 2.4 + 0.02 * 5 * 10 + 0.001 * r, rep=r)
          | {"shape": {"S": 5, "R": 10}} for r in (1, 2, 3)]    # R=10 -> med 13.002
    hi = [_probe("A1", 5 * 2.4 + 0.02 * 5 * 20 + 0.001 * r, rep=r)
          | {"shape": {"S": 5, "R": 20}} for r in (1, 2, 3)]   # R=20 -> med 14.002
    fit = _vc().fit_cost_model(lo + hi)
    assert abs(fit["p"] - 2.4) < 1e-3 and abs(fit["rate"] - 0.02) < 1e-4, fit


# -- 3. the anchor gate (before any ratio may be spoken) ------------------------------
def test_anchor_gates_pass_on_concordant_intervals():
    a1, a2 = _anchors()
    verdict = _vc().anchor_gates(a1, a2)
    assert verdict["ok"] is True, verdict
    assert verdict["overlap_frac"] >= 0.90 and verdict["median_ok_frac"] >= 0.95


def test_anchor_gate_refutes_overlap_destroying_shift():
    a1, _ = _anchors()
    _, a2 = _anchors(offset_a2=0.5)                     # intervals disjoint
    verdict = _vc().anchor_gates(a1, a2)
    assert verdict["ok"] is False
    assert verdict["overlap_frac"] < 0.90
    assert verdict["n_failed_overlap"] >= 0.10 * len(a1)


def test_anchor_gate_catches_median_drift_within_overlap():
    a1, a2 = _anchors()
    for r in a2[:24 * 50]:                              # 96% of cells drift
        r["median"] = r["hi"] + 0.10                    # interval untouched (overlap
    verdict = _vc().anchor_gates(a1, a2)                # kept), median 20% off a1
    assert verdict["ok"] is False
    assert verdict["overlap_frac"] >= 0.90 and verdict["median_ok_frac"] < 0.95


# -- 4. the reader-side verifier (refuse-to-report laws) ------------------------------
def test_verifier_computes_ratio_from_witnesses_and_accepts_true_claim():
    tmp = _tmp()
    try:
        d = _campaign_dir(tmp, ratio=250.0)
        _result_md(d, "MEASURED-true ≥100x", 250.0, "B")
        rc, out = _vc().main(["--campaign", str(d), "--host", "measurement-host",
                              "--hw-profile", HW_PROFILE])
        assert rc == 0, f"a truthful campaign was refused: {out}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_verifier_refutes_inflated_ratio_claim():
    tmp = _tmp()
    try:
        d = _campaign_dir(tmp, ratio=5.0)               # witnesses say 5x...
        _result_md(d, "MEASURED-true ≥100x", 500.0, "B")   # ...result.md says 500x
        rc, out = _vc().main(["--campaign", str(d), "--host", "measurement-host",
                              "--hw-profile", HW_PROFILE])
        assert rc != 0, f"SCIENCE-FIRST breach accepted: {out}"
        assert "ratio" in out.lower(), f"refusal does not name the breach: {out}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_verifier_refutes_measured_claim_backed_by_failed_anchor():
    tmp = _tmp()
    try:
        a1, _ = _anchors()
        _, a2 = _anchors(offset_a2=0.5)                 # anchor gate fails
        d = _campaign_dir(tmp, ratio=250.0, a1=a1, a2=a2)
        _result_md(d, "MEASURED-true ≥100x", 250.0, "B")
        rc, out = _vc().main(["--campaign", str(d), "--host", "measurement-host",
                              "--hw-profile", HW_PROFILE])
        assert rc != 0, f"a ratio rode over a failed anchor: {out}"
        assert "anchor" in out.lower(), f"refusal does not name the anchor: {out}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_verifier_rejects_probe_witness_carrying_verdict_fields():
    # probes measure; they never adjudicate (RB-09 freshness law family).
    tmp = _tmp()
    try:
        d = _campaign_dir(tmp, ratio=250.0)
        bad = _probe("A1", 8.0, 1) | {"verdict": "pass"}
        (d / "witnesses" / "probe_A1_1.jsonl").write_text(json.dumps(bad) + "\n")
        _result_md(d, "MEASURED-true ≥100x", 250.0, "B")
        rc, out = _vc().main(["--campaign", str(d), "--host", "measurement-host",
                              "--hw-profile", HW_PROFILE])
        assert rc != 0, f"a self-adjudicating probe witness passed: {out}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_campaign_table_must_carry_nine_column_pins():
    # the (S) seal's law lifted into the campaign lane: an unattested campaign
    # table cannot support a MEASURED claim.
    tmp = _tmp()
    try:
        d = _campaign_dir(tmp, ratio=250.0)
        _result_md(d, "MEASURED-true ≥100x", 250.0, "B")
        text = (d / "campaign_timings.csv").read_text()
        (d / "campaign_timings.csv").write_text(
            text.replace(HW_PROFILE, ""))              # strip the pins
        rc, out = _vc().main(["--campaign", str(d), "--host", "measurement-host",
                              "--hw-profile", HW_PROFILE])
        assert rc != 0, f"unpinned campaign table accepted: {out}"
        assert "hw_profile" in out.lower() or "pin" in out.lower(), out
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_second_full_launch_is_refused_by_the_ledger_law():
    tmp = _tmp()
    try:
        d = _campaign_dir(tmp, ratio=250.0)
        ledger = d / "campaign_launches.jsonl"
        ledger.write_text(ledger.read_text() + json.dumps(
            {"kind": "launch", "mode": "full",
             "ts": "2026-10-10T09:00:00Z"}) + "\n")
        assert _vc().launch_gate(ledger, mode="full") is False, \
            "a second full shot into one campaign dir was allowed (RB-10/RB-11(ii))"
        assert _vc().launch_gate(ledger, mode="pilot") is True
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# -- 5. the frozen constants ------------------------------------------------------------
def test_seed_constant_is_frozen_in_the_instruments():
    for f in ("gen_campaign.R", "run_campaign.R"):
        p = BOOT / f
        assert p.is_file(), f"missing instrument: {p}"
        text = p.read_text()
        assert "20260928" in text, f"{f} lost the frozen SEED"
        assert "20260927" not in text and "20260929" not in text, \
            f"{f} carries a drifted G0 master seed"


# -- 6. the R-side append path (RB-04D.2 write-side gap class) ---------------------------
# The launch ledger and probe witnesses must APPEND. writeLines carries no
# append argument: an `append = TRUE` there is an unused-argument hard error
# (witnessed live when the first smoke rehearsal died at the ledger write
# after a clean census pass — the (T) suite at that time never executed the
# R-side append call sites). These units execute the real call path: the
# ledger appender through the real filesystem for both launch modes, plus a
# structural law that no writeLines-with-append misuse can return.

_APPEND_RPROG = """
src <- '@@SRC@@'; outdir <- '@@TMP@@'
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
env <- new.env()
env$outdir <- outdir
env$utc <- function() '2026-10-11T00:00:00'
need <- c('append_line', 'append_ledger')
for (e in parse(src)) {
  op <- ''
  if (is.call(e) && length(e) >= 2L)
    op <- tryCatch(as.character(e[[1L]]), error = function(...) '')
  if (length(op) == 1L && op %in% c('<-', '<<-', '=') && is.symbol(e[[2L]]) &&
      as.character(e[[2L]]) %in% need) eval(e, env)
}
if (!exists('append_ledger', envir = env, inherits = FALSE)) {
  cat('APPEND-LEDGER-NO-FN\\n'); quit(status = 4L)
}
f <- get('append_ledger', envir = env)
r <- tryCatch({ f('pilot'); f('full'); 'OK' },
              error = function(e) paste0('ERR ', conditionMessage(e)))
p <- file.path(outdir, 'campaign_launches.jsonl')
txt <- if (file.exists(p))
  paste(readLines(p, warn = FALSE), collapse = '|') else '<absent>'
if (identical(r, 'OK')) {
  cat('APPEND-LEDGER-OK[', txt, ']\\n', sep = ''); quit(status = 0L)
}
cat('APPEND-LEDGER-', r, '[', txt, ']\\n', sep = ''); quit(status = 3L)
"""


def test_launch_ledger_appender_executes_on_the_real_filesystem_both_modes():
    """append_ledger must run its REAL write path for both the smoke-mode and
    the full-mode launch records (unused-argument defects must not hide
    behind the pre-registration ceremony)."""
    rscript = shutil.which("Rscript")
    assert rscript, "Rscript absent — skip-not-skip: the missing tool is seen"
    src = BOOT / "run_campaign.R"
    assert src.is_file(), f"missing instrument: {src}"
    tmp = _tmp() / "ledger"
    prog = (_APPEND_RPROG.replace("@@SRC@@", str(src).replace("'", ""))
            .replace("@@TMP@@", str(tmp)))
    try:
        r = subprocess.run([rscript, "--vanilla", "-e", prog],
                           capture_output=True, text=True)
        assert r.returncode == 0, \
            f"append_ledger real-fs run failed (the verbatim R error is in " \
            f"stdout; smoke witnessed unused-argument class live):\n" \
            f"stdout={r.stdout!r}\nstderr={r.stderr!r}"
        assert r.stdout.startswith("APPEND-LEDGER-OK["), r.stdout
        assert '"mode":"pilot"' in r.stdout and '"mode":"full"' in r.stdout, \
            f"both-mode launch records missing: {r.stdout!r}"
        assert "2026-10-11T00:00:00" in r.stdout, \
            f"ledger lines must carry the frozen ts through utc(): {r.stdout!r}"
    finally:
        shutil.rmtree(tmp.parent, ignore_errors=True)


def test_harness_carries_no_write_lines_with_append_misuse():
    """Structural law: every appending write in the R harness goes through an
    append-mode connection helper; writeLines must never be handed an
    append= argument (its absence from writeLines is an error, witnessed)."""
    src = BOOT / "run_campaign.R"
    text = src.read_text()
    assert "append = TRUE" not in text and "append=TRUE" not in text, \
        "writeLines has no append argument — a call site carrying it " \
        "hard-errors the moment it executes"
    assert 'file(path, open = "a")' in text, \
        "the harness must own an append-mode connection helper"
    assert "append_line <- function" in text, \
        "the append-mode connection must be a named helper (defined, not " \
        "inlined at one site)"
    assert text.count("append_line(") >= 2, \
        "the helper must serve every append site (ledger + probes): found " \
        f"{text.count('append_line(')} call site(s)"


# -- 7. the call-resolution audit (RB-04D.2 second live witness) ------------------------
# The second smoke rehearsal died one step past the repaired ledger, at
# loadRDS — a function that does not exist (R spells it readRDS). Same gap
# class as the append defect: the (T) suite never executed the harness body,
# so a nonfunction name rode through pre-registration. The fix that must not
# decay into whack-a-mole is static: walk the parse tree of BOTH instruments,
# demand every called name resolve (file-local definition, function
# parameter, the base search path, or msuiter/sigminer namespace members).
# Witnessed live: AUDIT-UNRESOLVED[loadRDS,sys.time] — the sys.time pair
# (lower-case, R spells Sys.time) sat in timed(), which probes call.

_AUDIT_RPROG = """
walk <- function(e) {
  if (is.name(e)) return(invisible(NULL))
  if (!is.call(e)) {
    if (is.list(e)) for (x in e) walk(x)
    return(invisible(NULL))
  }
  h <- e[[1L]]
  if (is.name(h)) {
    hn <- as.character(h)
    if (hn %in% c('<-', '<<-', '=', '->', '->>')) {
      if (is.name(e[[2L]])) defs[[length(defs) + 1L]] <<- as.character(e[[2L]])
      for (i in seq_len(length(e))[-c(1L, 2L)]) walk(e[[i]])
      return(invisible(NULL))
    }
    if (identical(hn, 'function')) {
      fnm <- names(as.list(e[[2L]]))
      if (!is.null(fnm)) pars <<- c(pars, fnm[nzchar(fnm)])
      walk(e[[3L]])
      return(invisible(NULL))
    }
    if (!hn %in% c('if', 'for', 'while', 'repeat', 'function'))
      calls[[length(calls) + 1L]] <<- hn
  } else if (is.call(h) && length(h) == 3L &&
             is.name(h[[1L]]) && as.character(h[[1L]]) %in% c('::', ':::')) {
    calls[[length(calls) + 1L]] <<- paste0(as.character(h[[2L]]), ':::',
                                           as.character(h[[3L]]))
  }
  for (i in seq_along(e)[-1L]) walk(e[[i]])
  invisible(NULL)
}
defs <- character(0); pars <- character(0); calls <- character(0)
for (s in c('@@RUN@@', '@@GEN@@')) for (e in parse(s)) walk(e)
if (!(requireNamespace('msuiter', quietly = TRUE) &&
      requireNamespace('sigminer', quietly = TRUE))) {
  cat('AUDIT-SKIP-NO-PKGS\\n'); quit(status = 0L)
}
allowed <- c(defs, pars, unlist(lapply(c('msuiter', 'sigminer'),
                                        function(p) ls(asNamespace(p),
                                                       all.names = TRUE))))
unknown <- character(0)
for (cn in unique(calls)) {
  if (cn %in% allowed) next
  if (grepl(':::', cn, fixed = TRUE)) {
    parts <- strsplit(cn, ':::', fixed = TRUE)[[1L]]
    if (exists(parts[2L], envir = getNamespace(parts[1L]),
               inherits = FALSE)) next
  } else if (exists(cn, mode = 'function')) next
  unknown[[length(unknown) + 1L]] <- cn
}
if (length(unknown)) {
  cat('AUDIT-UNRESOLVED[', paste(sort(unknown), collapse = ','), ']\\n',
      sep = '')
  quit(status = 5L)
}
cat('AUDIT-CLEAN calls=', length(unique(calls)), ' defs=',
    length(unique(defs)), '\\n', sep = '')
quit(status = 0L)
"""


def test_instruments_resolve_every_called_function():
    """No nonfunction name may ride through pre-registration again: both
    campaign instruments must parse to calls that all resolve in the host
    runtime (base path + attached package namespaces + file-local defs)."""
    rscript = shutil.which("Rscript")
    assert rscript, "Rscript absent — skip-not-skip: the missing tool is seen"
    run_src = BOOT / "run_campaign.R"
    gen_src = BOOT / "gen_campaign.R"
    assert run_src.is_file() and gen_src.is_file(), "campaign instruments absent"
    prog = (_AUDIT_RPROG
            .replace("@@RUN@@", str(run_src).replace("'", ""))
            .replace("@@GEN@@", str(gen_src).replace("'", "")))
    r = subprocess.run([rscript, "--vanilla", "-e", prog],
                       capture_output=True, text=True)
    assert r.returncode == 0, \
        f"unresolvable call name(s) in the campaign instruments (verbatim R " \
        f"audit line; the class witnessed live at loadRDS, absent from base " \
        f"— R spells it readRDS):\nstdout={r.stdout!r}\nstderr={r.stderr!r}"
    assert r.stdout.startswith("AUDIT-CLEAN"), \
        f"audit did not reach its clean verdict: {r.stdout!r}"
