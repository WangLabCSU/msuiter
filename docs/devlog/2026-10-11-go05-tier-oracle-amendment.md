# GO-05 tier-oracle amendment — consumed vs report-only fits, the floor-gate
# fallback, and the --tier-probe rehearsal (controller ruling @10:45, RB-09
# doctrine: principle, not outcome)

Date: 2026-10-11. Lane: GO-05 successor (worktree agent-a266f2d2cd8559ec4,
branch go-05-anchor-probe). Oracle: `bench/m7/tools/verify_campaign.py`.
Harness: `bench/bootstrap/run_campaign.R`. Tests: new group **(W)**
`bench/m7/tests/test_tier_probe.py`, registered in `tests/run_all.py`.

## 1. The ruling this implements (recap)

The RB-10 single authoritative shot fired once at 02:43Z and self-halted at
the tier oracle: rc 2, `non-physical cost fit`. Per the single-shot law the
bytes were frozen and the lane halted-and-reported. The controller ruled
@10:45: **halt correct, shot legally unspent** (the ledger never reached the
`append_ledger("full")` site), **instrumentation-class defect confirmed** —
(a) environment co-tenancy is an insufficient co-factor (the identifiability
math is quietness-independent: A2's expected two-shape signal is +0.011 s
against ±0.026 s wall jitter at probe scale, and A2's marginal per-rep cost at
S=5 makes `wall = S(p + rate·R)` unidentifiable for that arm regardless of
weather), (b) instrumentation is primary: the code's own comment says "A1
gates the budget" (`verify_campaign.py`, the decide block), yet the
`--decide` fits comprehension let A2's *report-only* fit veto the decision.
Seven laws bind this amendment; they are cited where each is discharged.

## 2. The frozen halt, verbatim (law: the halt is evidence, keep it legible)

Frozen dir `bench/results/bootstrap_vs_sigminer_20261011T024301Z/` — touched
by nothing since; cited only. Its shot log
(`/tmp/go05lane/shot_20261011T024301Z.log`) tail:

```
[campaign] probes (S=5, R=10/20, warmup + 3 timed; medians adjudicated by the oracle):
..................
[campaign] probes done
[campaign] HALT: tier oracle failed (rc 2): {"ok": false, "error": "non-physical cost fit: p=0.179 rate=-0.0002200000000000002"}
```

Ledger (`campaign_launches.jsonl`), verbatim — the probe-mode entry only;
**zero `mode:full` entries**, so the shot was never consumed:

```
{"kind":"launch","mode":"probe","ts":"2026-10-11T02:43:02"}
```

Census, verbatim (`witnesses/host_census.jsonl`) — one container line, none a
measurement container; the shot ran on a host whose load averages read 3.5–3.9
during residency (the co-factor the ruling weighed and deemed insufficient):

```
{"kind":"census","ts":"2026-10-11T02:43:02","live_measurement":[],"ps":["shiny-server-test rocker/shiny:latest"]}
```

Data seal: `sha256 cc094225d599a6765dbc7958a445609459ded0f32f2481f87c5cb9e8762b3263`
(quoted from `seal.json` bytes; the reader recomputes it from `campaign.rds`).

The three probe witnesses, medians (recomputed from the frozen jsonl bytes;
the two-shape linear solve follows):

```
probe_A1_1.jsonl: R=10: med=0.978 [0.95, 0.978, 1.032],  R=20: med=1.595 [1.59, 1.595, 1.612]
probe_A2_1.jsonl: R=10: med=0.884 [0.869, 0.884, 0.889], R=20: med=0.873 [0.864, 0.873, 0.914]
probe_A3_1.jsonl: R=10: med=0.864 [0.858, 0.864, 0.885], R=20: med=0.870 [0.847, 0.87, 0.91]
```

A2 is the death: ten extra replicates moved the wall by **−0.011 s** (the
rep-20 median below rep-10's), so `rate = (0.873−0.884)/(5·10) =
−0.0002200000000000002` and `p = 0.179` — negative rate, the very bytes of the
HALT line above. A1's fit was physically clean throughout (rate ≈ +0.0123;
the replay in §7 shows the exact number). The decision consumes only A1.

## 3. The amendment, law (1): consumed vs report-only fits

`fit_cost_model` is split (the consumed law keeps its verbatim error text —
pinned byte-exactly by the golden regression, W1/W3):

- `fit_cost_model_report(probes)` — the two-shape solve, **reported**: a fit
  failing the physical test returns
  `{"fit_status": "non-identifiable-at-probe-scale", "p", "rate", "shapes"}`
  without raising; structural unusability (no records, S-disagreement, not
  exactly two shapes, identical R) still raises — there is nothing to report.
- `fit_cost_model(probes)` — the **consumed** law, untouched in force: any
  non-`ok` report raises `ValueError("non-physical cost fit: ...")`.

`--decide` now consumes exactly what the decision consumes: A1's fit via the
consumed law (missing witnesses or a non-physical A1 are hard refusals, rc 2
— W3/W4); A2/A3 rides the report path, and a structural failure becomes a
`fit_status` entry with the reason, never a raise. The decision rc and the
A1-governed `tier`/`cap`/`projections`/A1-fit are **invariant to every
report-only state** — pristine, non-identifiable, structurally unusable,
absent — pinned by byte-equality of the consumed subset across the 4×4
product of A2×A3 states (W2).

## 4. The amendment, law (2): the full oracle-call-site audit

Every `call_oracle_rc` site in `run_campaign.R` (line numbers at this
commit), each classified **consumed** (its answer gates control flow or a
gate's number) or **report/ledger** (its answer is recorded):

| site | call | classification | disposition under the amendment |
|---|---|---|---|
| :203 | `--launch-gate --mode pilot` | ledger-consumed | unchanged; additionally gated off for the rehearsal (§6) |
| :393 | `--anchor-check` (anchor-probe dispatch) | anchor-witness-consumed (its rc feeds the probe record, the run stays reportable) | unchanged; gates already amended at @09:45 (`K_CI`/`EPS`, see the anchor-gate note) |
| :396 | reader verifier (anchor-probe) | report | unchanged |
| :411 | `--decide` | **A1 consumed; A2/A3 report-only** — the defect | split per §3; report-only arms can never veto |
| :455 | reader verifier (tier-probe dispatch) | report | new (§6); the rehearsal exits zero so an oracle report stays information |
| :494 | reader verifier (Tier-C quit) | report | unchanged |
| :507 | `--launch-gate --mode full` | ledger-consumed (RB-10) | unchanged; the rehearsal quits before it |
| :520 | `--floor-check` per arm | **consumed** — the arm's own fit feeds the gate's projection | must never stand on a non-physical fit: probe-fit → committed governance floor table → **hard refusal rc 2** (§5) |
| :543 | reader verifier (floor halt-and-report) | report | unchanged |
| :570 | `--anchor-check` (authoritative path) | consumed for the claim | unchanged |
| :606 | reader verifier (final) | report | unchanged |

## 5. The amendment, law (2): the floor gate's provenance ladder

`--floor-check` adjudicates the pre-registered 3× gate and *consumes* its
projection, so its number may come only from a physical fit or the committed
governance table (`matrix_governance.floor_for`, rep-100 witness-anchored):

1. the arm's probe fit via the consumed law → `floor_source: "probe-fit"`;
2. on any unusability, the arm's committed class in
   `CAMPAIGN_FLOOR_CLASSES: dict[str, tuple[str, str, int]]` →
   `floor_source: "governance-floor-table"`, `floor_class` recorded;
3. **no silent pass, no non-physical stand-in**: rc 2 with the named reason
   (pinned by W5 and by the replay in §7).

`CAMPAIGN_FLOOR_CLASSES` is committed **empty**: the campaign arms have no
committed class in `_FLOOR_ANCHORS`, and inventing an A2↔matrix-class
equivalence would be a fabricated governance act, forbidden by the
frozen-domain law (entries are committed only by controller ruling). The
residual exposure is disclosed for controller attention, not papered over:
if a future full shot's A2 probe fit lands non-physical *while the timed arms
run* (the tier decision can no longer halt there — A2 is report-only), the
A2 arm-witness floor gate will rc 2 and the harness's `abort` at the
floor-oracle site will fire — a loud halt-and-report, not a wrong number.
The controller may commit a class (that map, with `floor_class` verbatim in
the error) to turn that residual into a table-gated pass.

## 6. The amendment, laws (3)+(4): the frozen-shape bar and --tier-probe

**Frozen-shape bar attestation** (pinned by W6): the protocol §2 sampling
constants are byte-untouched — `S_PROBE <- 5L; R_PROBE <- c(10L, 20L)` and
`SEED <- 20260928L` verbatim in the harness; there is no `--identifiability`
and no `--rate-floor` anywhere: no R-bump, no identifiability-eps, no
rate-sign carve-out was purchased to buy this fix.

**`--tier-probe`** ((U)-group discipline, all four law-(4) properties):
valueless switch on the house arg idiom; pairs `--mode full` only and never
`--smoke` (pairing `abort`s, executed); requires a fresh/empty outdir
(executed); the rehearsal is ledger-invisible to the shot counter — its sole
entry is `{"kind":"tier-probe","grade":"calibration","ts":...}`, no `mode`
key (the counter counts `e["mode"] == "full"`, so the entry is invisible and
the one-shot law is unweakened: a real `mode:full` line still blocks the gate
rc 3 — W7d). It rides census + sealed generator bytes + probes + decide at
the full frozen shape and quits (`quit(status = 0L)`, never a death) after
the probe-grade `result.md` and a reader pass (`call_oracle_rc(character(0))`)
— before any timed arm, before the `append_ledger("full")` site, carrying no
`--launch-gate`/`arm_A`/`ratio(A1/A2)`/`--floor-check` token in its dispatch
(pinned textually by W7, executed by W7b). Its `result.md` speaks no claim
line the reader could parse as tier/ratio/verdict and carries the decide
oracle's JSON **verbatim, never re-typed** (pinned both ways: W7c generates
it through the harness's own `write_tier_result` on the target interpreter
and re-reads it through `vc._parse_result_md`).

## 7. TDD record and measurements

- **RED** (`/tmp/go05lane/red_witness_w.log`): 3/10 passing pre-amendment,
  with the golden regression reproducing tonight's death verbatim from live
  fixture bytes: `non-physical cost fit: p=0.179 rate=-0.0002200000000000002`.
- **GREEN** (`/tmp/go05lane/green_w.log`): (W) 10/10.
- **Full m7 suite** (`/tmp/go05lane/suite_tier.log`): **207/207** — 197
  pre-existing (the (U)/(V)/(S)/(T) harness-lint groups all re-run against
  the edited harness) plus the new (W) ten.
- **The rehearsal, executed once** — wrapper
  `/tmp/go05lane/run_tier_probe.sh`, outdir
  `/tmp/go05lane/tierprobe_20261011T043151Z`, log
  `/tmp/go05lane/tierprobe_20261011T043151Z.log`, **rc 0**:

  ```
  [campaign] TIER-PROBE (full shape K=1000 S=1000 n_sig=50; decision-path observation only — the RB-10 shot stays unspent)
  [campaign] reader verifier rc=0 {"ok": true, "checks": [seal-sha256 ok, probe-purity ok, launch-ledger ok ("0 full shot(s)")], "claims": {"tier": null, "ratio": null, "verdict": null}}
  [campaign] TIER-PROBE-COMPLETE outdir=... tier=A decision-ok=TRUE
  ```

  `witnesses/tier_decision.json` verbatim (weather this pass gave all three
  arms physically clean fits — note A1's rate 0.0127, the determinism leg):

  ```
  {"tier": "A", "fits": {"A1": {"fit_status": "ok", "p": 0.060999999999999985, "rate": 0.0127, "shapes": [[5, 10], [5, 20]]}, "A2": {"fit_status": "ok", "p": 0.1636, "rate": 8.000000000000007e-05, ...}, "A3": {"fit_status": "ok", "p": 0.16399999999999998, "rate": 6.0000000000000056e-05, ...}}, "cap": 21600, "projections": {"A": 12761.0, "B": 2601.0}}
  ```

  Its ledger is the single `{"kind":"tier-probe","grade":"calibration",...}`
  line; the reader read zero claims and zero full shots.

- **The golden replay** — tonight's own bytes (copied out of the frozen dir,
  which stays untouched) through the amended oracle, `/tmp/go05lane/golden_replay`:

  ```
  $ verify_campaign --campaign /tmp/go05lane/golden_replay --decide   -> rc 0
  {"tier": "A", "fits": {"A1": {"fit_status": "ok", "p": 0.0722, "rate": 0.01234, ...},
   "A2": {"fit_status": "non-identifiable-at-probe-scale", "p": 0.179, "rate": -0.0002200000000000002, ...},
   "A3": {"fit_status": "ok", "p": 0.1716, "rate": 0.00012000000000000011, ...}},
   "cap": 21600, "projections": {"A": 12412.2, "B": 2540.2}}

  $ verify_campaign --campaign /tmp/go05lane/golden_replay --floor-check --arm A2 --observed 0.9 --reps 1000  -> rc 2
  {"ok": false, "error": "A2: probe fit unusable (non-physical cost fit: p=0.179 rate=-0.0002200000000000002); the floor gate refuses to stand on a non-physical fit, and no committed governance floor class covers this arm"}
  ```

  The bytes that killed the shot now report A2 and decide A on A1 — rc 0 —
  while the floor gate keeps its consumed-law refusal loud.

## 8. Disclosures

- **RED-phase live-fire incident**: before the fail-safe pre-flight existed,
  `test_tier_probe_refusals_executed` executed the real harness with
  `--tier-probe` while the switch did not exist yet; unknown flags pass
  unnoticed, so a genuine pilot campaign launched into a temp dir and ran
  until the unit's 600 s subprocess timeout killed it. Verified afterwards:
  zero orphan processes, the temp dir's bytes deleted with its context, the
  RB-10 ledgers untouched, the shot still unspent. The unit now executes only
  once the mode AND both guards exist in the source, else it reports
  `[skip]` — witnessed live once; never again.
- **Wrapper v2 (law (6) co-tenancy) is prepared, not fired**:
  `/tmp/go05lane/run_shot2.sh` samples `docker ps` + `sysctl vm.loadavg` +
  `uptime` + `vm_stat` three times over 30 s into
  `co_tenancy_<TS>.txt`, echoes it verbatim at the head of the launch log,
  and refuses (rc 4) unless all three load1 samples read under the ruled
  1.5 bar. The bar is the controller's; it was not tuned. A standalone
  dry-run at 04:28–04:29Z showed the gate **refusing** on live readings
  (`load1=3.19/3.48/3.59`), i.e. the belt binds. Firing the real shot needs
  its own authorization after the controller witnesses this rehearsal.
- The frozen dir and every byte in it are unmodified; this note cites them
  only. The single-shot ledger across the tree still counts zero `mode:full`
  entries for this lane.

## 9. The §5 residual adjudicated: the UNMEASURABLE floor leg (controller ruling @12:50)

The controller's own witness battery passed this amendment (§8's rehearsal
included), then ruled the §5 residual **shot-blocking** and issued the final
amendment before any shot authorization. The ruling's hazard, verbatim-style:

> THE HAZARD: two same-seed observations of byte-identical sealed data gave
> A2's probe fit **opposite rate signs**. A 3× floor built on such a fit is a
> coin flip; aborting the one lawful shot on it is the decide defect
> transplanted into the timed path.

| observation | sealed bytes | seed | A2 probe-fit rate | A2 probe-fit p |
|---|---|---|---|---|
| frozen shot (`…_20261011T024301Z`, §2) | identical | 20260928 | `-0.0002200000000000002` | `0.179` |
| tier-probe rehearsal (§7) | identical | 20260928 | `+8.000000000000007e-05` | `0.1636` |

The per-rep cost at the frozen probe shape (S=5, R∈{10,20}) sits under wall
jitter, so the two-shape solve is sign-random — the fit is *provably
uninformative*, not merely unlucky. The ruled contract, laws (1)–(5):

1. **Oracle.** `--floor-check` where the arm's probe fit comes back
   `fit_status == NON_IDENTIFIABLE` returns
   `{"ok": true, "floor_gate": "unmeasurable", "arm": …, "reason":
   "probe-fit non-identifiable at probe scale", "fit": <verbatim report
   entry>}` with the **new dedicated rc 3**. rc 2 stays reserved for the
   genuine hard refusals (missing args, missing witnesses, structural); the
   rc 0/4 probe-fit rung — including the `<=` boundary — is byte-untouched.
2. **Instrument.** The floor site accepts `{0, 4}` plus rc 3: the rc-3
   branch records the arm witness via the dedicated top-level writer
   `write_unmeasurable_gate()` — `"gate":
   "UNMEASURED(probe-fit non-identifiable)"` verbatim, the oracle's reason
   as `gate_reason`, and `floor_projection`/`floor_ratio` as literal `null`
   (there is no number; none is invented) — then the campaign **continues**.
   Every other rc still aborts verbatim on the untouched `abort` line;
   rc 3 is inert at all ten other oracle sites (pinned by the accept-set
   occurrence count). The rc-4 breach keeps the verbatim HALT-AND-REPORT
   quit-3 — the one way a floor gate still kills, and it stays loaded.
3. **A1.** The consumed law is untouched; the (W) group still pins it.
4. **MEASURED-true.** The `measured-true-holds` law (ratio ≥ 100 + anchor)
   is byte-untouched — it consumes the gate nowhere. The leg is *disclosed*:
   marker verbatim in the arm witness, a `- floor gate UNMEASURED on: …`
   line in the shot's own result.md, and the leg named in the reader's
   `floor-gates` check detail.
5. **No fabricated equivalence.** `CAMPAIGN_FLOOR_CLASSES` stays committed
   EMPTY; the unmeasurable path supersedes the §5 governance-table fallback
   (which the campaign never exercised and will not need).

**The one interpretation, on the record.** Law (4)'s "MEASURED-true path …
does not consume the floor gate" holds verbatim for the 100×/anchor hold
law, which this amendment did not touch. Read as also freezing the reader's
`floor-gates` replay check at `gate == "pass"` alone, the ruling would be
self-defeating: the ruled scenario (A2 leg unmeasurable → continue → complete
→ MEASURED-true claim) would be rc-1'd by the reader *after* the ledger
append — the gate borrowing its veto after the fact, with the shot consumed.
The internally-consistent reading implements the gate contract: the check
accepts `"pass"` or the **verbatim** pre-registered marker, anything else —
`breach`, `unmeasurable`, a case-flipped forgery — still fails the claim
(pinned, (X6)). If the controller reads law (4) otherwise, the witness
battery gates before any shot burns, so nothing is spent to discover it.

**TDD record.** Group (X) of the m7 suite,
`tests/test_floor_gate_unmeasurable.py`, seven units, RED witnessed first
against the unamended instruments (`/tmp/go05lane/red_x_witness.log`:
2/7, the five law-new units failing with the frozen rc-2 error verbatim),
then 7/7 green; (W) re-greened 10/10 under the amended oracle
(`green_w_x.log`). The W5 bad-fit leg was repinned from rc 2 to the
superseding rc 3 class, keeping its hard-refusal twin (missing bytes) at
rc 2 — the ladder's two classes, separated with the ruling's own wedges.
No push. The tier-probe rehearsal was not re-fired; the frozen dir was not
touched.
