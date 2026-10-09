"""Group (P) test_matrix_governance — driver-side launch governance (RB-07/RB-08).

The Phase-B pass-1 postmortem (phase_b_SHARD-OOM_DEFECT.json) named two
instrumentation gaps this group seals:

  (1) SUBSTRING LABEL CLASSIFICATION. The postmortem itself was once
      compiled through `'__N100' in label`, which silently swept
      N10000/N100000/N1000000 into the N100 class and produced bogus
      inflation arithmetic (controller-owned on record; the same class bit
      the vocabulary audit before it). The seal is an EXACT parser over the
      `tool__arm__N<int>` stamp grammar: n is int-compared, arms are
      full-string compared. Classification-by-substring is illegal here.
  (2) UNIFORMITY BY CONSTRUCTION, ENFORCED. Fan-out=1 is not a wish; the
      driver refuses to launch a cell while ANY measurement-image container
      is live (`docker ps` count assert, outcome logged per cell), samples
      the live process table (`docker top`) during the run, and records the
      max-sibling-proc census per cell OUTSIDE the four-file guard and the
      BYTE_EQUAL set (sidecar census.json under the cell dir — it never
      participates in cache-hit byte comparisons).

Plus the judgment-writer refuse-to-claim law: a judgment over rows that are
not all pass must speak as DEFECT, never as the authoritative fairness
attestation — matrix1 filed its attestation header over 20 failed cells.

All units are pure: the docker-facing probes are injectable, so the suite
is CI-safe (no docker required here, same idiom as group (L))."""

from __future__ import annotations

import copy
import io
import json
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import run_bench                                                    # noqa: E402
import tools.matrix_governance as gov                               # noqa: E402

GRID_N = (100, 1000, 10000)


# -- (1) exact-match stamp parsing ------------------------------------------------

def test_parse_stamp_exact_fields():
    assert gov.parse_stamp("sigminer__main__N100000") == ("sigminer", "main",
                                                          100000)
    assert gov.parse_stamp("sigprofiler__comp_strong_flat__N1000") == (
        "sigprofiler", "comp_strong_flat", 1000)


def test_parse_stamp_rejects_near_miss_labels():
    # The substring-class failure mode, made illegal: every label below is
    # NOT a well-formed `tool__arm__N<int>` stamp and must RAISE, never
    # silently resolve to a shorter arm or n. The unicode-digit case is the
    # int() trap: int("١٠٠") == 100 while the grammar is ASCII.
    for bad in ("sigminer__main__N100_", "sigminer__main__N0100",
                "sigminer__main__100", "sigminer__main__n100",
                "sigminer__main__N", "sigminermain__N100",
                "sigminer__main__N100extra", "sigminer___N100",
                "sigminer__main__N١٠٠", "sigminer__main__N+100",
                "sigminer__main__N 100", "__main__N100",
                "sigminer__main__N100__x", "sigminer__mai__n__N100"):
        try:
            gov.parse_stamp(bad)
        except ValueError:
            continue
        raise AssertionError(f"parse_stamp accepted malformed label {bad!r}")


def test_n100_class_membership_is_exact_not_substring():
    # '__N100' in label matches N10000/N100000/N1000000 -- the very bug
    # that burned the controller's first census. The class selector must
    # partition the whole grid with zero cross-contamination.
    stamps = [f"sigminer__{arm}__N{n}" for arm in ("main", "comp_pole")
              for n in (100, 1000, 10000, 100000, 300000, 1000000)]
    cls = gov.class_by_n(stamps, 100)
    assert cls == ["sigminer__main__N100", "sigminer__comp_pole__N100"], cls
    assert all(gov.parse_stamp(s)[2] == 100 for s in cls)


# -- (2) judgment-writer refuse-to-claim -----------------------------------------

def _row(cell: str, status: str, seconds: float = 10.0, cpu: float = 9.0) -> dict:
    return {"cell": cell, "tool": cell.split("__")[0], "arm": "main",
            "n": 100, "seconds": seconds, "status": status,
            "cpu_seconds": cpu}


def _judgment_text(rows) -> str:
    args = run_bench.parse_args(["--profile", "smoke", "--adapter", "mock",
                                "--provider", "synthetic",
                                "--competitors", "sigminer",
                                "--outdir", "/tmp/nonexistent-p",
                                "--cachedir", "/tmp/nonexistent-c"])
    specs = {"sigminer": __import__("competitors.registry", fromlist=["x"]
                                    ).lookup("sigminer")}
    tmp = Path("/tmp/m7_governance_judgment")
    tmp.mkdir(exist_ok=True)
    path = run_bench.write_judgment(tmp, args, rows, specs, "ts")
    return path.read_text(encoding="utf-8")


def test_judgment_claims_authority_only_over_all_pass_rows():
    text = _judgment_text([_row("sigminer__main__N100", "ok"),
                           _row("sigminer__comp_mmr__N100", "cached")])
    assert "FAIRNESS ATTESTATION" in text
    assert "DEFECT" not in text


def test_judgment_refuses_claim_over_a_nonpass_row():
    for poison in ("fail: container run failed (exit 137)",
                   "skip: image digest PENDING-VERIFY",
                   "defect-floor: 900.0 > 3x floor"):
        text = _judgment_text([_row("sigminer__main__N100", "ok"),
                               _row("sigminer__main__N1000", poison)])
        assert "DEFECT" in text, poison
        assert "FAIRNESS ATTESTATION" not in text, poison


# -- (3) pre-flight co-tenant refusal (uniformity by construction) ---------------

def test_co_tenant_decision_refuses_any_live_measurement_container():
    assert gov.co_tenant_violation(0) is None
    assert gov.co_tenant_violation(1) == "refuse: 1 measurement container live"
    assert gov.co_tenant_violation(7) == "refuse: 7 measurement containers live"


def test_measurement_process_count_counts_only_measurement_images():
    # Injected `docker ps` table: the shiny/test container is not ours and
    # must never trip the assert; one slice3-r5 row must.
    rows = [{"Image": "rocker/shiny:latest"},
            {"Image": "msuiter-sigminer:slice3-r5"}]
    assert gov.measurement_process_count(rows) == 1
    assert gov.measurement_process_count([]) == 0
    both = rows + [{"Image": "m7-sigprofiler:spa-1.1.5"}]
    assert gov.measurement_process_count(both) == 2


def test_pre_flight_assert_logs_per_cell_outcome(tmp: Path | None = None):
    # The driver logs the assert outcome per cell (controller RB-08(3)):
    # a refused launch must leave an auditable line, not just a raised hand.
    import tempfile
    d = Path(tempfile.mkdtemp(prefix="m7gov"))
    log = d / "preflight_log.jsonl"
    gov.log_preflight(log, cell="sigminer__main__N100", live=0, decision="GO")
    gov.log_preflight(log, cell="sigminer__main__N100", live=1,
                      decision="REFUSE")
    lines = [json.loads(l) for l in log.read_text(encoding="utf-8").splitlines()]
    assert [l["decision"] for l in lines] == ["GO", "REFUSE"]
    assert all(l["cell"] == "sigminer__main__N100" for l in lines)


# -- (3b) driver structure: fan-out=1 is a text law -------------------------------

def test_driver_is_fan_out_free_by_text():
    # RB-08 structural seal: the SHARD-OOM defect was one character — `&`.
    # Any background launch reintroduced into the driver (outside a legal
    # fd redirection like 2>&1) fails this unit before it can fail a pass.
    import re
    src = (Path(__file__).resolve().parents[1] / "tools"
           / "run_m7_bench.sh").read_text(encoding="utf-8")
    code = [ln for ln in src.splitlines() if not ln.lstrip().startswith("#")]
    joined = re.sub(r"[0-9]*>&[0-9]+", "", " ".join(code))
    assert "&" not in joined, "run_m7_bench.sh contains a background launch"


# -- (4) worker census (RB-08(4): observe, never assume) -------------------------

def test_max_sibling_procs_from_top_table():
    # docker top rows: sibling procs share a PPID (the main Rscript).
    table = [{"PID": 1, "PPID": 0}, {"PID": 10, "PPID": 1}] + \
            [{"PID": 100 + i, "PPID": 10} for i in range(10)]
    assert gov.max_sibling_procs(table) == 10


def test_worker_census_records_max_across_samples():
    samples = [[{"PID": 1, "PPID": 0}],
               [{"PID": 1, "PPID": 0}] + [{"PID": 10 + i, "PPID": 1}
                                           for i in range(6)],
               [{"PID": 1, "PPID": 0}] + [{"PID": 10 + i, "PPID": 1}
                                           for i in range(10)]]
    census = gov.worker_census(samples, tool="sigminer",
                               cell="sigminer__main__N100")
    assert census == {"cell": "sigminer__main__N100", "tool": "sigminer",
                      "max_worker_procs": 10, "samples": 3}


# -- (5) the 3x-floor DEFECT-candidate gate (RB-08(7)) ----------------------------

def test_pre_registered_floors_exist_for_the_full_grid():
    from g0 import grid
    for arm in grid.arms_for_profile("degraded"):
        for n in arm.n_list:
            for tool in ("sigminer", "sigprofiler"):
                assert gov.floor_for(tool, arm.name, n) > 0, (tool, arm.name, n)


def test_floor_gate_flags_over_3x_and_passes_under():
    floor = gov.floor_for("sigminer", "main", 100)
    assert gov.floor_gate(_row("sigminer__main__N100", "ok",
                               seconds=2.5 * floor)) is None
    flag = gov.floor_gate(_row("sigminer__main__N100", "ok",
                               seconds=3.5 * floor))
    assert flag is not None and "defect-floor" in flag["status"]


def test_floor_gate_silent_on_nonpass_rows():
    # A dead cell is diagnosed by its own death text; the floor gate must
    # not add noise on top of a real failure.
    assert gov.floor_gate(_row("sigminer__main__N100",
                               "fail: exit 137", seconds=9e5)) is None


def test_floor_gate_scope_hard_errors_on_unknown_arm():
    # Plumbing tools (mock) carry no floor and are exempt; but an unknown
    # ARM of a measured tool must raise — a silently ungated cell is the
    # exact hole that let the sharded pass sail through.
    assert gov.floor_gate(_row("mock__main__N100", "ok",
                               seconds=86400.0)) is None
    try:
        gov.floor_gate(_row("sigminer__comp_mystery__N100", "ok",
                            seconds=10.0))
    except KeyError:
        return
    raise AssertionError("unknown arm of a measured tool passed silently")


# -- (5b) defect ledger + re-adjudication lineage (RB-09(3)(iv)) -------------------

def test_defect_ledger_round_trips_outside_the_cell_guard():
    cache = Path(tempfile.mkdtemp(prefix="m7ledger_"))
    row = _row("sigminer__main__N100",
               "defect-floor: wall/cpu 1004.9s > 3.0x pre-registered floor")
    gov.append_defect_record(cache, row)
    latest = gov.latest_defect_records(cache)
    rec = latest[row["cell"]]
    assert rec["status"].startswith("defect-floor")
    assert rec["epoch"] == gov.floor_table_epoch()
    path = gov.defect_ledger_path(cache)
    # outside the four-file guard and the BYTE_EQUAL set: never under cells/
    assert "cells" not in path.parts and path.parent.name == gov.GOVERNANCE_SUBDIR
    row2 = _row(row["cell"], "defect-floor: later flag")
    gov.append_defect_record(cache, row2)
    assert gov.latest_defect_records(cache)[row["cell"]]["status"] \
        == "defect-floor: later flag"          # append-only log, last wins


def test_missing_ledger_reads_empty_and_silent():
    cache = Path(tempfile.mkdtemp(prefix="m7noledger_"))
    assert gov.latest_defect_records(cache) == {}
    assert gov.re_adjudication(_row("sigminer__main__N100", "ok"), None) is None


def test_floor_table_epoch_is_deterministic_and_flips_on_recalibration():
    e0 = gov.floor_table_epoch()
    assert e0 == gov.floor_table_epoch(), "epoch must be a pure function"
    saved_boot = dict(gov._BOOT)
    try:                                        # test-scoped patch, restored below
        gov._BOOT["sigminer"] = saved_boot["sigminer"] + 1.0
        assert gov.floor_table_epoch() != e0, "re-calibration must flip the epoch"
    finally:
        gov._BOOT.clear()
        gov._BOOT.update(saved_boot)
    assert gov.floor_table_epoch() == e0        # restore verified


def test_re_adjudication_attaches_only_across_epochs():
    row = _row("sigminer__main__N100", "cached")
    now = gov.floor_table_epoch()
    assert gov.re_adjudication(row, {"status": "defect-floor: x",
                                     "epoch": now}) is None   # same law in force
    assert gov.re_adjudication(row, {"status": "fail: exit 137",
                                     "epoch": "a" * 16}) is None   # not a floor flag
    la = gov.re_adjudication(row, {"status": "defect-floor: x", "epoch": "a" * 16})
    assert la is not None and la["prior_epoch"] == "a" * 16
    assert la["epoch"] == now
    assert "REP-1" in la["mechanism"] and "REP-100" in la["mechanism"], \
        "the citation must name the adjudicated root cause"


def test_judgment_emits_re_adjudication_lineage_block():
    row = _row("sigminer__main__N100", "cached")
    row["re_adjudication"] = {
        "prior_status": "defect-floor: wall/cpu 1004.9s > 3.0x pre-registered "
                        "floor 310.0s (tool=sigminer arm=main n=100)",
        "prior_epoch": "a" * 16, "epoch": "b" * 16,
        "mechanism": "RB-09: REP-1 anchors gated REP-100 cells"}
    text = _judgment_text([row, _row("sigminer__main__N1000", "ok")])
    assert "Re-adjudication lineage" in text
    assert "defect-floor: wall/cpu 1004.9s" in text      # prior flag verbatim
    assert "REP-1 anchors gated REP-100 cells" in text   # mechanism cited
    assert "FAIRNESS ATTESTATION" in text                # all-pass: header stands


def test_judgment_omits_lineage_when_no_flips():
    text = _judgment_text([_row("sigminer__main__N100", "ok"),
                           _row("sigminer__main__N1000", "cached")])
    assert "Re-adjudication lineage" not in text


# -- (5a) floor_semantics: anchors must be reps-matched witnesses (RB-09(3)(i)) ----
# RB-09 root cause: every BOOT/WORK constant of the pre-registered table was
# calibrated from a REP-1 witness (the r5 probe's --reps default; the pilot
# Seeds.txt shows one rep row per class) while the frozen protocol runs
# REP-100 cells. floor(sigminer,main,N100)=310 sat BELOW the rep-1 witness
# itself (360.25): no green cell was ever physically possible and the gate
# self-halted the fresh serial matrix. These units make a reps-mismatched
# anchor mechanically impossible, per the controller's TDD order.

def test_floor_anchors_are_reps_matched_to_the_protocol():
    # Every floor class must descend from a witness produced at the frozen
    # protocol reps (RB-09(3)(i)): anchor.reps == protocol cell reps.
    for (tool, arm, n), anchor in gov._FLOOR_ANCHORS.items():
        assert anchor["reps"] == gov.PROTOCOL_REPS, (
            f"floor class {tool}/{arm}/N{n} is anchored by a REP-{anchor['reps']} "
            f"witness while the protocol runs REP-{gov.PROTOCOL_REPS} cells")


def test_floor_dominates_the_measured_witness_for_its_class():
    # The pre-registered floor must not sit below the honest uncontended cost
    # measured for its own class: a floor under its own witness calibrates
    # the gate at a scale no green cell can occupy (the N100 case:
    # 310 < 360.25).
    for (tool, arm, n), anchor in gov._FLOOR_ANCHORS.items():
        floor = gov.floor_for(tool, arm, n)
        measured = gov.anchor_measured(anchor)
        assert floor >= measured, (
            f"floor({tool},{arm},N{n})={floor:.1f}s is below the measured "
            f"rep-matched witness cost {measured:.1f}s for its own class")


def test_anchor_witnesses_are_committed_probe_json_with_full_argv():
    # RB-09(5): every floor/anchor claim carries its witness's FULL argv
    # (including --reps) inside the provenance file, and the recorded cost
    # must equal the witness verbatim — reps mismatch becomes mechanically
    # detectable instead of audit-dependent folklore.
    for (tool, arm, n), anchor in gov._FLOOR_ANCHORS.items():
        path = gov.anchor_witness_path(anchor)
        assert path.exists(), f"anchor witness missing: {path}"
        assert path.suffix == ".json", (
            f"anchor witness for {tool}/{arm}/N{n} is {path.name}, but a "
            f"floor witness must be a probe verdict JSON with an argv echo")
        doc = json.loads(path.read_text(encoding="utf-8"))
        argv = doc.get("argv")
        assert argv and "--reps" in argv, (
            f"anchor witness {path.name} carries no --reps argv echo")
        assert int(argv[argv.index("--reps") + 1]) == anchor["reps"], (
            f"anchor witness {path.name} disagrees with the registry reps")
        assert (doc["sidecar"]["cpu_seconds"]
                == anchor["cpu_seconds"]), "registry cost != witness verbatim"


# -- (5b) defect ledger + re-adjudication lineage (RB-09(3)(iv)) -------------------

def test_defect_ledger_round_trips_outside_the_cell_guard():
    cache = Path(tempfile.mkdtemp(prefix="m7ledger_"))
    row = _row("sigminer__main__N100",
               "defect-floor: wall/cpu 1004.9s > 3.0x pre-registered floor")
    gov.append_defect_record(cache, row)
    latest = gov.latest_defect_records(cache)
    rec = latest[row["cell"]]
    assert rec["status"].startswith("defect-floor")
    assert rec["epoch"] == gov.floor_table_epoch()
    path = gov.defect_ledger_path(cache)
    # outside the four-file guard and the BYTE_EQUAL set: never under cells/
    assert "cells" not in path.parts and path.parent.name == gov.GOVERNANCE_SUBDIR
    row2 = _row(row["cell"], "defect-floor: later flag")
    gov.append_defect_record(cache, row2)
    assert gov.latest_defect_records(cache)[row["cell"]]["status"] \
        == "defect-floor: later flag"          # append-only log, last wins


def test_missing_ledger_reads_empty_and_silent():
    cache = Path(tempfile.mkdtemp(prefix="m7noledger_"))
    assert gov.latest_defect_records(cache) == {}
    assert gov.re_adjudication(_row("sigminer__main__N100", "ok"), None) is None


def test_floor_table_epoch_is_deterministic_and_flips_on_recalibration():
    e0 = gov.floor_table_epoch()
    assert e0 == gov.floor_table_epoch(), "epoch must be a pure function"
    saved_boot = dict(gov._BOOT)
    try:                                        # test-scoped patch, restored below
        gov._BOOT["sigminer"] = saved_boot["sigminer"] + 1.0
        assert gov.floor_table_epoch() != e0, "re-calibration must flip the epoch"
    finally:
        gov._BOOT.clear()
        gov._BOOT.update(saved_boot)
    assert gov.floor_table_epoch() == e0        # restore verified


def test_re_adjudication_attaches_only_across_epochs():
    row = _row("sigminer__main__N100", "cached")
    now = gov.floor_table_epoch()
    assert gov.re_adjudication(row, {"status": "defect-floor: x",
                                     "epoch": now}) is None   # same law in force
    assert gov.re_adjudication(row, {"status": "fail: exit 137",
                                     "epoch": "a" * 16}) is None   # not a floor flag
    la = gov.re_adjudication(row, {"status": "defect-floor: x", "epoch": "a" * 16})
    assert la is not None and la["prior_epoch"] == "a" * 16
    assert la["epoch"] == now
    assert "REP-1" in la["mechanism"] and "REP-100" in la["mechanism"], \
        "the citation must name the adjudicated root cause"


def test_judgment_emits_re_adjudication_lineage_block():
    row = _row("sigminer__main__N100", "cached")
    row["re_adjudication"] = {
        "prior_status": "defect-floor: wall/cpu 1004.9s > 3.0x pre-registered "
                        "floor 310.0s (tool=sigminer arm=main n=100)",
        "prior_epoch": "a" * 16, "epoch": "b" * 16,
        "mechanism": "RB-09: REP-1 anchors gated REP-100 cells"}
    text = _judgment_text([row, _row("sigminer__main__N1000", "ok")])
    assert "Re-adjudication lineage" in text
    assert "defect-floor: wall/cpu 1004.9s" in text      # prior flag verbatim
    assert "REP-1 anchors gated REP-100 cells" in text   # mechanism cited
    assert "FAIRNESS ATTESTATION" in text                # all-pass: header stands


def test_judgment_omits_lineage_when_no_flips():
    text = _judgment_text([_row("sigminer__main__N100", "ok"),
                           _row("sigminer__main__N1000", "cached")])
    assert "Re-adjudication lineage" not in text
