# GO-05 hardware-pin completeness — the authoritative table must attest its machine (2026-10-10)

Completes the ROADMAP:100 middle clause (钉硬件 bench 全表) and the forward path
EVIDENCE-ADDENDUM §4 pre-registered: *"future authoritative runs attest their
machine from the table alone"*. B1a made the pin columns POSSIBLE (present-but-empty
when `M7_HW_PROFILE` unset — the right contract for probes and plumbing). A table
whose pin columns are EMPTY does not attest anything; the EVIDENCE-ADDENDUM had to
reconstruct the machine from judgment/devlog prose. This stage makes that
reconstruction unnecessary — and makes an unattested authoritative table impossible
to author.

## Why the committed legacy tables are not backfilled (decision, not omission)

The 2026-10-09 authoritative artifacts carry the LEGACY 7-column header: their
`host`/`hw_profile` values were never measured into bytes. Stamping them now would
fabricate provenance — no committed witness records the 10-09 hostname, and the
cache-hit final pass zeroes measured seconds, so a "backfilled" table would
recite pins the bytes cannot support. The honest completion is a FRESH serial
authoritative run under the gates below; the ROADMAP flip waits on that artifact,
not on this code.

## The four seals

1. **`tools/matrix_governance.hardware_pin_verdict(rows, host=, hw_profile=)`** —
   the pure, injected, CI-safe adjudicator. Every row's pins must EQUAL the
   measured environment; empty and divergent cells are named per column, never
   averaged away. A zero-row table is not a complete table (zero rows attests
   zero measurements).
2. **`run_bench.main` authority gate** — the authoritative pass (docker adapter,
   final shard-free pass) **refuses to file** without the operator's
   `M7_HW_PROFILE`: exit 2, fail-fast **before any filesystem effect** (no
   outdir, no cachedir may be born), and the refusal names its own remedy
   channel. This is refuse-to-claim's authoring twin: an unattested authoritative
   table is never born. The dry-run plan printer, mock passes, and shard passes
   keep B1a's present-but-empty optionality law — the gate governs the file that
   makes the machine-attestation claim, not intents or plumbing.
3. **`tools/verify_hardware_pin.py`** — the reader-side verifier: re-runnable
   against a committed table, verdicting it **from its own bytes** (no prose
   trust). Its JSON verdict on stdout is the citable same-window artifact a docs
   citation points at (rc 0 ok / 1 named offenders / 2 unreadable table).
4. **Driver launch assert (`tools/run_m7_bench.sh`)** — a docker ignition without
   `M7_HW_PROFILE` exits 2 before the first shard, so hours of measurement cannot
   die at the final pass. The driver is convenience; seal 2 remains the authority.

The judgment's timings-table line now names the nine-column contract
(`host`/`hw_profile` included), so a reader of the fairness document learns from
it that the table attests its machine.

## TDD evidence (verbatim command output, same window; RED before GREEN)

RED — `python3 /tmp/go05lane/run_one_group.py test_hardware_pin` (implementation
absent; the two survivors are precisely the optionality-law controls, so they
were green by construction and stayed green throughout):

```
FAIL  test_hardware_pin.test_authoritative_docker_pass_refuses_to_file_without_the_operator_pin  (0.4s)
FAIL  test_hardware_pin.test_blank_pin_refuses_like_an_absent_one  (0.1s)
FAIL  test_hardware_pin.test_judgment_speaks_the_nine_column_pinned_contract  (0.7s)
FAIL  test_hardware_pin.test_verdict_names_rows_with_empty_or_divergent_pins  (0.0s)
FAIL  test_hardware_pin.test_verdict_ok_only_when_every_row_pinned_to_the_measured_environment  (0.0s)
FAIL  test_hardware_pin.test_verdict_rejects_an_empty_table  (0.0s)
FAIL  test_hardware_pin.test_verifier_cli_verdicts_a_committed_table_from_its_own_bytes  (0.0s)
PASS  test_hardware_pin.test_dry_run_plan_is_untouched_by_the_authority_gate  (0.0s)
PASS  test_hardware_pin.test_mock_final_pass_stays_green_without_the_pin  (0.7s)
2/9 tests passed.
```

GREEN — same command after the four seals landed:

```
PASS  test_hardware_pin.test_authoritative_docker_pass_refuses_to_file_without_the_operator_pin  (0.0s)
PASS  test_hardware_pin.test_blank_pin_refuses_like_an_absent_one  (0.0s)
PASS  test_hardware_pin.test_dry_run_plan_is_untouched_by_the_authority_gate  (0.0s)
PASS  test_hardware_pin.test_judgment_speaks_the_nine_column_pinned_contract  (0.9s)
PASS  test_hardware_pin.test_mock_final_pass_stays_green_without_the_pin  (0.7s)
PASS  test_hardware_pin.test_verdict_names_rows_with_empty_or_divergent_pins  (0.0s)
PASS  test_hardware_pin.test_verdict_ok_only_when_every_row_pinned_to_the_measured_environment  (0.0s)
PASS  test_hardware_pin.test_verdict_rejects_an_empty_table  (0.0s)
PASS  test_hardware_pin.test_verifier_cli_verdicts_a_committed_table_from_its_own_bytes  (0.0s)
9/9 tests passed.
```

Full suite `python3 -m tests.run_all` (group (S) registered):

```
157/157 tests passed.
```

Launch-assert liveness (RB-11(i) — the instrument executed end-to-end, not
syntax-only): `env -u M7_HW_PROFILE sh tools/run_m7_bench.sh` printed the refusal
and returned `launch-assert-rc=2` with zero shards started.

### Correction — same-day suite re-measurement (the 157/157 above is stale)

The 157/157 line above was recorded BEFORE the launch-assert lines themselves
were added to `tools/run_m7_bench.sh`; it therefore attests a state the tree
never held with the assert present. Two physical facts from the follow-on lane:

1. The first committed form of the launch-assert used `&&` inside the driver,
   which tripped the RB-08 fan-out text seal
   (`test_driver_is_fan_out_free_by_text` went RED — a true positive; the seal
   caught the assert exactly as designed). Fixed in the follow-up commit by the
   nested-`if` form (no `&&` outside an fd-redirect anywhere in the file), with
   the refusal re-proven live: `env -u M7_HW_PROFILE sh tools/run_m7_bench.sh`
   again printed the refusal and exited 2 with zero shards started.
2. The group-(T) bootstrap-campaign group was registered in the same lane, so
   the authoritative lane count for this chain is 174 units, witnessed verbatim:

```
174/174 tests passed.
```

(/tmp/go05lane/m7_suite_after_T2.log — the group tally that covers commits
18d2c41, 5822aab, e105351.) The number spoken in the record from now on is
174/174; the 157/157 line stands above as the historical RED/GREEN witness for
group (S) only, never as the lane's final tally.

## Fresh ignition (the artifact the ROADMAP flip waits on)

Single authoritative shot per RB-10: strict-serial driver, fresh cachedir
(`cache/bench_degraded_docker` proven absent at pre-flight),
`M7_HW_PROFILE="10 vCPU / 8 GB class"`, pre-flight `docker ps` empty and
image RepoDigests byte-exact vs registry rows. Its verbatim evidence — the
42-cell roll-out, the nine-column table, and the reader-verifier rc=0 verdict —
is appended to this file's next section before the checkbox may flip.

### Fresh ignition — verbatim attestation (executed 2026-10-10/11, GO-05 lane)

The single authoritative shot ran to completion (driver `ignition-rc=0`,
witnessed verbatim in the background-task output). Terminal marker, verbatim
from `/tmp/go05lane/ignite1.log`:

```
[adapter] docker: 42/42 cells ok|cached; timings -> timings_m7_degraded_20261011-042331.csv
[scoring] benchmark_m7_20261011-042331.csv: 42 cells scored, 0 skipped -> verdict appended to judgment_m7_degraded_20261011-042331.md
AUTHORITATIVE-RUN-COMPLETE outdir=../results/docker_m7_degraded_20261010-202330
```

Nine-column table (`bench/results/docker_m7_degraded_20261010-202330/`):
header `cell,tool,arm,n,seconds,status,cpu_seconds,host,hw_profile`;
42 data rows; status-column counts witnessed verbatim by substring counts
over the committed bytes: 42 rows carry `,ok,`, zero rows carry `,cached,`
(zero cache hits in the authoritative shard passes — every second was
measured). Table sha256:

```
c116c8e3b7096a0c74c5591906ffc570addfbaeeabb39f24f8ffeac4e678e072  timings_sharded_master.csv
```

Reader pass (verdict spoken from the committed table's own bytes), verbatim:

```
$ python3 bench/m7/tools/verify_hardware_pin.py --table bench/results/docker_m7_degraded_20261010-202330/timings_sharded_master.csv --host "ShixiangWang-WorkSpacedeMacBook-Pro.local" --hw-profile "10 vCPU / 8 GB class"
{"mismatched_host": [], "mismatched_hw_profile": [], "missing_host": [], "missing_hw_profile": [], "ok": true, "rows": 42, "table": "bench/results/docker_m7_degraded_20261010-202330/timings_sharded_master.csv"}
reader-verifier-rc=0
```

Co-tenancy throughout: `docker ps` showed only `shiny-server-test`
(`rocker/shiny:latest`, non-measurement scaffolding per governance scope);
strict-serial fan-out=1 held (RB-08 text-seal unit green in the lane suite,
174/174 — see the correction block above). Instrument liveness witnessed
through the full run by the milestone-only watcher
(`[watch] ... serial shard ... complete` boundary pairs + one
`CELLS=<n>/42` counter line per boundary, final `[watch]
TERMINAL-MARKER-SEEN cycles=10 cells=42/42`).
