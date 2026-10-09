# U-M7-03 benchmark matrix — Phase-A pilot, projection, and the sigminer interpreter catch (2026-10-09)

Unit: U-M7-03 (full benchmark-matrix execution), branch `u-m7-03-benchmark-matrix`,
base `a6f2e89`. Contract sources: `docs/devlog/2026-10-08-m7-competitor-harness-design.md`
(cell contract §4, timings schema, four-file trust guard, fairness protocol), G0 frozen
protocol grid (`bench/g0`, read-only). This log closes Phase A and records the controller
checkpoint state; the full matrix has NOT been launched.

## 1. Matrix-runner extensions (TDD, commit 5f6d14e)

- `run_bench.py`: `--n-list` N-point filter (per-arm intersection; no-match exits 2 —
  exercised for real by a mis-targeted pole probe, see §4), `--dry-run` machine-readable
  plan printer with zero filesystem side effects (self-tested), `provider_seed` folded
  into `cell_identity` (stale-cache class cure, 2026-10-07 precedent).
- `tools/verify_seed_determinism.py`: resample-verify gate — re-executes one cachedir
  cell through the same frozen pipeline into a scratch cache and byte-compares the three
  attestable outputs (`intervals.csv`, `errors.log`, `manifest.json`; `timing.json`
  excluded by documented jitter-channel design). Exit contract 0 OK / 1 DRIFT /
  2 inadmissible.
- New test group ⑫ `tests/test_matrix_runner.py` (10 units, written RED first): filter
  semantics, pinned dry-run plan shape + plan-vs-execution agreement, seed goldens with
  cross-process re-derivation, resample OK/DRIFT/inadmissible paths.
- Gates at delivery: m7 67/67, g0 45/45, ci-selfcheck exit 0, mock shard-vs-serial
  byte-equality rehearsal green.

## 2. Pilot design and result (measured, not projected)

10 cells (5 (arm,N) selections x 2 competitors), docker adapter, degraded profile,
synthetic provider (seed 0), reps=1, all seven thread caps = 1 injected before the image
token, one shared VM (Docker Desktop, 10 CPUs / 7.748 GiB — `docker info` verbatim).
Cachedir `cache/pilot_r1`; authoritative-shaped outdir
`bench/results/docker_m7_PILOT_20261008-200152/` (this commit).

| cell | wall s | cpu s | status |
|---|---|---|---|
| sigprofiler main N100 | 14.16 | 13.934 | ok |
| sigprofiler main N1000 | 13.31 | 13.073 | ok |
| sigprofiler comp_mmr N100 | 14.37 | 14.141 | ok |
| sigprofiler comp_mmr N1000 | 13.12 | 12.893 | ok |
| sigprofiler nb N1000 | 13.24 | 13.02 | ok |
| sigminer main/comp_mmr/nb (5 cells) | 0.11-0.23 | 0.0 | FAIL exit 127 (see §3) |

Cold-vs-warm (reps=8 probe, `main` @ N1000, isolated caches):
cold-A 16.31 s (cpu 25.693), cold-B 16.35 s (cpu 25.524); warm replay of cold-A's
cache = full four-file-guard cache hits, 0 container invocations.

N-scaling floor probes (pole arm, reps as noted):
N100000 reps1 14.90 s; N100000 reps2 15.25 s (marginal rep ≈ 0.35 s);
N1000000 reps1 14.77 s. Reading: wall-clock is dominated by a ≈13-14 s fixed
container boot + Python import floor per invocation; per-rep work across
N in {1e3,1e5,1e6} runs 0.35-1.0 s and is nearly flat in N at these sizes
(cosmic_fit cost is signature-count-bound, not mutation-count-bound, in this regime).
`cpu_seconds > seconds` in the pole/reps-8 rows means the child tree legitimately uses
>1 core on average despite the BLAS/OMP/Go caps (Python-level worker pools are outside
those env knobs); this is the measured reality under the frozen cap protocol and is
reported identically for every tool — parity, not tuning.

VM headroom: zero `oom` events across the whole pilot+probe window (`docker events`,
channel verified live: 8 `die` events counted); no exit-137/SIGKILL signatures anywhere;
5.3 MB covers the entire 10-cell pilot cache (N1e6 cell ≈ 1 MB).

## 3. The catch: the pinned sigminer image cannot execute its own cell protocol

Every sigminer cell died at container-start, identical verbatim signature:

    fail: container run failed (exit 127): docker: Error response from daemon: failed to
    create task for container: failed to create shim task: OCI runtime create failed:
    runc create failed: unable to start container process: error during container init:
    exec: "python3": executable file not found in $PATH

Read-only probes of `msuiter-sigminer:slice3-r2` (digest `c2a52c71...1157`, live-verified
byte-match to the registry row): the image is R-only — `python3`, `python`,
`/usr/local/bin/python*`, `/opt/python*` all absent; `Rscript` present
(`/usr/local/bin/Rscript`); `/work/` ships both measurement scripts
(`m7_entry.py` 2515 B — the Python wrapper the registry `entrypoint="python3"` launches —
and `run_sigminer.R` 5951 B); sigminer packageVersion = 2.3.1 as pinned.

Why it survived to the pilot: the entrypoint value was a registry-time assumption; build9's
live-verification exercised Rscript-level smokes only, and `image_gate` validates digest
shape/presence, never entrypoint executability. The cell argv ran against the container for
the first time in this pilot — which is exactly the pilot's anomaly-catching purpose.

Why no zero-touch workaround exists: the four-file trust guard requires the `timing.json`
sidecar only the Python wrapper writes; `run_container_cell` hard-fails on its absence;
entrypoint/mount composition is inside the zero-touch `docker_cmd.py`; a host-side wrapper
around `docker run` would measure the CLI client process, not the container, breaking the
frozen CPU = container-reported-rusage semantics (§4.3). Options presented to the
controller: R1 (recommended) controller-budgeted image rebuild adding python3 to the
existing recipe + live-verification of the real cell argv + digest re-pin; R2 fairness-
protocol amendment with runner-side self-reporting (touches zero-touch modules).
Zero builds performed here; escalation sent 2026-10-09; ruling pending as of this commit
(update this section when it lands).

## 4. Reproducibility evidence (committed next to the matrix records)

`verify_seed_determinism.py` re-ran two real docker cells from their own seed records;
all three attestable files byte-identical (16-hex sha256 prefix pairs):

- `sigprofiler__main__N100` — verdict OK: intervals `a04aa2ab4d967dd1` == , errors
  `e3b0c44298fc1c14` == , manifest `5952419079b65ec6` == .
- `sigprofiler__nb__N1000` — verdict OK: intervals `6920b44edb2e7cdc` == , errors
  `e3b0c44298fc1c14` == , manifest `3ee720bf67723f34` == .

Verdict JSONs committed as `determinism_sigprofiler__{main__N100,nb__N1000}.json`.
The sigminer side carries the same gate obligation once its launch path is ruled.

## 5. Full-matrix projection (paper-grade = frozen degraded profile)

21 (arm,N) cells/competitor x reps=100 folded per invocation = 42 invocations,
4200 samples, once per tool:

| tier | cells/competitor | est. per-invocation | tier total |
|---|---|---|---|
| core N in {100,1e3,1e4} x 5 arms | 15 | ~13.5 + 100 x 0.4-0.6 ≈ 53-74 s | ≈ 13-19 min |
| sensitivity singletons (nb/clock/sparse @1e3) | 3 | ≈ 53-74 s | ≈ 3-4 min |
| pole 1e5 / 3e5 / 1e6 | 3 | ≈ 48-115 s | ≈ 3-6 min |

sigprofiler alone ≈ 20-30 min (conservative ceiling 45); with sigminer once unblocked,
full-matrix wall ≈ 40-60 min single-host (ceiling < 2 h), disk < 0.2 GB, plus the
cache-hit serial recompute pass (minutes, no containers). OOM risk assessed low
(measured child trees peaked ≈ 1.6 cores, 10 vCPU VM, zero events), but the G0
over-subscription lesson (8-way shard fan-out under 8 GB) keeps shard fan-out capped.

## 6. What this does NOT claim

- reps=1 pilot numbers are instrumentation measurements, not paper data; no performance
  or fidelity claim rests on them.
- No sigminer numbers of any kind: its cells measure a launch failure, not the tool.
- Seed-determinism is proven on the two sigprofiler cells above; the sigminer rows are
  BLOCKED pending the interpreter ruling, and will pass the same gate before Phase B.
- Phase B (full matrix) stands by explicit controller instruction only; nothing here
  pre-authorizes it.

## 7. The instrumentation ladder: pilot -> RED -> r3 -> deeper defect -> audit -> r4 (RB-01 re-death, RB-02 GO, RB-03)

RB-01 (python3 provisioning, budget 1/1) was executed to its mandated boundary:
the failing cell-argv probe was committed as the RED witness
(`cell_argv_probe_slice3-r2_RED.json`, commit `1cb49d3`) BEFORE the single
authorized build was spent; the r3 image (python3 layer, digest
`sha256:db86e541...`, Id/Size 1749913171, Created 2026-10-08T20:58:14.870995334Z)
built green but the re-probe DEFECTED one layer deeper:

```
fail: container run failed (exit 1): Error in library(jsonlite) :
      there is no package called 'jsonlite'
```

python3 cleared the interpreter gate; `run_sigminer.R` then died on an R
package the recipe never provisioned. Witness:
`cell_argv_probe_slice3-r3_DEFECT.json` (verbatim sidecar tail; the r3 image
stays local-only -- never flipped, never recorded as final anywhere, exactly
as ruled). Per RB-01 the run STOPPED and reported rather than building again.

RB-02 ruled Phase-B GO on the filed projection (frozen degraded profile,
21 (arm,N) cells/tool x reps=100, master seed 20260928, <2h ceiling) with the
hard ordering "Phase-B launches ONLY after the r3 probe flips GREEN".

RB-03 ruled on the re-death (verbatim extracts):

> r4 BUILD AUTHORIZED (one build; this unit's instrumentation ledger reads
> 2/2 after it): combined scope-frozen delta = {python3 layer AS ALREADY
> BUILT (cache-warm, no change) + ONE appended RUN provisioning jsonlite via
> the recipe's existing CRAN-mirror install.packages idiom + result-gated
> packageVersion assert on jsonlite ...} Zero other changes

> CONVERGENCE GATE (mandatory, before spending the build, committed visible
> on the branch like the RED probe): a static dependency-closure audit test
> that parses the executed surface of BOTH /work scripts ... asserts the
> discovered package closure is a subset of the image-recipe provisioned
> set. It must be GREEN against the r4 recipe candidate pre-build. If the
> closure audit surfaces any gap beyond {python3, jsonlite}, fold its
> provisioning into the SAME r4 recipe before building -- the build is spent
> once on the complete closure, never iteratively.

> If the closure-gate GREEN + build succeeds but the probe STILL finds a gap
> the audit did not predict -> STOP and report: third incident means the
> executed-surface model itself is suspect and escalates to controller-side
> strategy (no further incremental rulings)

> On probe-GREEN: proceed straight through to the Phase-B full matrix per
> RB-02 (no checkpoint)

The gate is implemented as `tools/audit_executed_surface_deps.py` + suite
group (M) (`test_executed_surface_audit.py`, registered in `run_all.py`).
Each executed-surface file is parsed under the grammar of the interpreter
that actually runs it (Rscript: `library/require/requireNamespace` + `::`/`:::`;
python3: import/from classified against the live stdlib table), and the
closure is asserted against the recipe's own provisioning surface (apt layer
tokens, `install.packages` scalar AND vector forms, and the resolver's
result-gated `packageVersion` targets). Escape-class regexes are assembled
from `chr(92)` because this transport has demonstrably mangled backslash runs
in transit -- the pattern is a behavioural object verified at import, not a
byte hope.

Pre-build verdict against the r4 recipe candidate (python3 + jsonlite layers,
both uncommitted-to-image until the single authorized build): **CONVERGED,
zero gaps** -- `executed_surface_audit_r4candidate_CONVERGED.json` here.
R closure `{jsonlite, sigminer}` (sigminer rides the resolver pin, jsonlite
the new CRAN layer with its build9-discipline result gate); executed-surface
python is stdlib-pure; third-party python empty. Had any gap beyond
{python3, jsonlite} appeared, its provisioning would have joined THIS recipe
before the build, per the ruling. The r4 build itself is the unit's second
and final instrumentation-class spend (ledger 2/2).

## RB-04 — the removeDuplicates incident and its root-cause correction (2026-10-09)

The r4 probe (post-python3, post-jsonlite) died with rc=1 at the runner's own
first statement:

```
Error in commandArgs(trailingOnly = TRUE, removeDuplicates = FALSE) :
  unused argument (removeDuplicates = FALSE)
```

Three witnesses, all committed under `rehearsal_slice3-r4/`:

- `minted_called_names` → the runner calls `commandArgs` with a named argument
  no era R has ever had; the era-truth allowlist harvested from the r4 image's
  own R 4.3.3 (`formals_allowlist_slice3-r4.json`) records
  `commandArgs: ["trailingOnly"]` — the second name is fabricated. The lint
  (group (N), `test_executed_surface_audit.py`) fires DEFECT on the branch
  bytes and CLEAN on the fixed bytes: the pair is committed
  (`lint_slice3-r4_{current-bytes_DEFECT,fixed-bytes_CLEAN}.json`).
- `runB_excerpt.log` — the same class-(c) surface plus the class-(d) hazard
  the rehearsal loop exposed: with the network on, R **auto-installs** the
  Suggests-level packages the default extraction path hard-requires
  (synchronicity, lpSolve, matrixStats) mid-measurement — nondeterministic,
  network-dependent, one recorded SSL-death. With the network off, the run
  dies at the first missing namespace. Neither posture is admissible for the
  matrix: the fix is to BAKE the closure and make the measurement path
  self-witness under `--network=none`.
- The controller's own R 4.5.2 probe reproduces the identical unused-argument
  error — the "modern reference-era has it" inference stays a comment, never
  a fact.

RB-04 was superseded in full by RB-05 below; its two durable rules were
absorbed: REHEARSE-BEFORE-BAKE and BUILD-SELF-WITNESS ("a build that cannot
execute its own measurement path is not allowed to exit").

## RB-05 — forensics accepted, r5 authorized (ledger 1/1)

Controller ruling, verbatim-governing, five clauses executed:

1. **(a) COPY + byte-pin the rehearsed runner.** The committed
   `run_sigminer.R` is now byte-identical to the stage2-proven witness
   (`sha256 7f306738…750084`), and the recipe asserts that hash IN THE IMAGE
   before anything else runs. Erratum on record: the ruling text quoted the
   pin as `fe700abe…`; that string matches no artifact on this host (every
   transport variant probed — as-is/stripped/CRLF/line-44-patched, both byte
   sets; the controller's own session established host display-mangling of
   hashes as precedent). Verify-by-command binds controller instructions too
   — RB-05(2) says so; the pin carries the command-measured hash, the
   commit message (`cc6e048`) records the erratum.

   **RB-06(1) finalization of the erratum (controller FULL RETRACTION of the
   "byte-pin triangle break" framing; how truth was established, not just
   that a constant was corrected).** The pin `7f30673847d96cd0e0fbfd1763e89ad12b1e5212c0152db4dd20741a2a750084`
   IS the true SHA-256 of the committed bytes, established by three
   independent explicit-algorithm recorders agreeing: host
   `openssl dgst -sha256`, in-container `python3 hashlib.sha256`, and the
   in-image `sha256sum` assert. The erratum's `fe700abe…` had two
   controller-side root causes, both now on record: (i) **algorithm
   conflation** — a host `shasum` invocation emits SHA-1 (40 hex) output that
   was read as if SHA-256, which is exactly what a `fe700abec23b…`-shaped
   string is; (ii) **an unmeasured remembered constant** — the "known"
   sha256('abc') control value was cited from memory instead of measured,
   itself the verify-by-command violation it appeared to expose.
   **No oracle defect exists**: the bytes, the pins, and the manifest
   role-claims were true as written throughout; no re-witnessing was or is
   required. The lesson generalizes into tooling (next section), because a
   narrative erratum cannot prevent the class — only measurement-bound
   gates can.
2. **(b) Era-gated bakes.** lpSolve 5.6.20, synchronicity 1.3.10, matrixStats
   1.3.0 — P3M `2024-04-23` snapshot ONLY, literal version gates (build9
   discipline: a null or off-version DESCRIPTION read is a `quit(status=1)`
   build death). No floating installs, no unpinned repos.
3. **(c) Build-time self-witness.** `self_witness.sh` (COPY'd file, never an
   `-e` one-liner — the newline-hazard class is structurally eliminated) runs
   the zero-touch composed cell argv — the exact
   `m7_entry.py … -- Rscript run_sigminer.R …` docker_cmd.py would compose —
   under `RUN --network=none`, over the byte-pinned `mini_cell/` fixture
   triple, asserting rc=0, the seven-column intervals header, ≥1 data row,
   `errors.log`, and a schema-valid sidecar (`cpu_seconds == ru_utime +
   ru_stime`, exit 0). `manifest.json` stays host-side by contract
   (run_bench.py writes it); the container-side four-file guard is
   intervals+errors+timing+schema, and the matrix re-asserts all four plus
   the host file.
4. **(d) Zero-touch elsewhere.** No base-image move, no R pin move, no layer
   reshuffle; the delta layers append after the cache-warm jsonlite layer so
   every recorded-cached layer stays warm.
5. **Pre-bake rehearsal, zero builds spent** (the invariant binding): the
   self-witness layer was rehearsed as a bind-mount over the r4 image,
   network-none, deps staged via `R_LIBS_USER` — `selfwitness_prebake2_excerpt.log`,
   rc=0, **zero auto-install lines**, NMF suggested solution 95.5 verbatim,
   3.902 min. Along the way it exposed that `R_LIB_USER` is Windows-only
   (.Renviron honors `R_LIBS_USER` on Linux) — the very reason stage2's
   "success" had silently self-healed through the network.

### Sixth recorded build defect (closure attempt 1 → 2, same lineage)

Attempt 1 died at the lpSolve/synchronicity layer: the literal-version gate
caught CRAN **5.6.23** answering where the era demanded **5.6.20** — with
both repos configured, `install.packages` resolves each lookup from the
highest version across ALL repos, so the CRAN fallback made the float
deterministic (both verdicts committed: `r5_forensic_{two_repo,p3m_only}.log`,
P3M-only GREEN at 5.6.20/1.3.10). Fold: all three era layers P3M-only. The
gate earned its keep on first contact — exactly "drift is a build death,
never a silent float."

### Ledger and evidence accounting

- Builds spent on the r5 lineage: attempt 1 (gate-caught death, forensically
  rooted, folded) → attempt 2. Precedent: the r3/r4 chains carry verbatim
  "closure attempt N" fold entries in this same Dockerfile.
- Suite at the fold: 98/98 (`python3 -m tests.run_all`, bench/m7).
- Convergence: `executed_surface_audit_r5candidate_CONVERGED.json` —
  executed-surface R closure `{jsonlite, lpSolve, matrixStats, synchronicity}`
  against the recipe, zero gaps.
- Manifest: `rehearsal_manifest.json` (16 entries + 6 adapters) binds every
  witness's sha256, bytes and role, including the unsanitised originals'
  full-file hashes (`stage2.log`, `runB.log`, `selfwitness_prebake2.log`
  on the controller host at `/tmp/m7probe/`).

## RB-05(6) — the r5 bake, the GREEN probe, and the registry ceremony

Single authorized bake lineage (ledger RB-05 1/1): attempt 1 gate-caught the
CRAN-fallback float (sixth recorded defect, folded); attempt 2 completed
GREEN end-to-end:

```
[image] lpSolve  5.6.20 , synchronicity  1.3.10  provisioned
[image] matrixStats  1.3.0  provisioned
[self-witness] mini-cell OK: rc 0, sidecar schema valid, container-side guard satisfied
```

— byte-pin assert PASS, zero auto-install lines in the witness layer, NMF
suggested solution 95.5 verbatim, 3.932 min. Live `docker image inspect`
captured verbatim (`image_inspect_slice3-r5_live.json` in the rehearsal
manifest): Id `sha256:05cb29e0cfe881c3a0c7d1ec7c9058cfbbb9539f5d1c135787027e6002c703e9`,
Size 1936876727, Created 2026-10-09T00:16:11.442885095Z.

The REAL cell-argv probe (zero-touch `docker_cmd` path, registry-driven,
the composed `m7_entry.py -- ... -- Rscript run_sigminer.R ...` argv)
flipped GREEN: `cell_argv_probe_slice3-r5_GREEN.json` — verdict OK,
run_rc 0, sidecar `{ru_utime 341.30887, ru_stime 18.943432, cpu_seconds
360.252302, exit_status 0}` (the cpu identity exact), four-file guard
satisfied, provenance bound to the r5 ref+digest pair.

The registry flip + `test_registry.py` pins are pure-data transcriptions of
that live inspect — the ceremony RB-05(6) ordered: inspect verbatim -> probe
GREEN -> flip, and not one step earlier. Phase-B (RB-02 full matrix)
launches from this head.

## RB-06 — hash provenance as executable law (ratifications and seals)

Controller ratifications recorded verbatim-equivalent: the r5 bake ledger
(1/1) is CONSUMED by the closure lineage above; the sixth recorded build
defect (CRAN-fallback float caught by the literal-version gate) is
classified instrumentation-class whose loud death WAS the result-gate
working as designed; the matrixStats 1.3.0 P3M-only bake fold is ratified.

The doctrine ("hash literals only ever pasted from command output, never
re-authored" — RB-06(6) binds the CONTROLLER as well: a "this hash matches
nothing" claim is a hypothesis requiring same-algorithm reproduction before
it can become an order) is encoded as three structural seals, TDD RED-first
(suite group (O) `tests/test_hash_provenance.py`, zero typed digests — every
expected value measured at test time, every tamper derived from the measured
value by last-hex mutation):

1. **The byte-pin triangle** (`tools/audit_executed_surface_deps.py::
   verify_byte_pin_triangle`): committed runner bytes == promoted witness
   == the Dockerfile in-image assert constant == the manifest's entry and
   role-claims == the registry row reconciled against the committed live
   inspect — re-derived from measurement on every suite run.
2. **The provenance lint** (`lint_hash_provenance`, standalone CLI
   `--hash-provenance`): every 64-hex literal carried by the recipe family
   (Dockerfile, runner, installer, self-witness, registry rows, contract
   tests, the manifest itself) must be BACKED — it re-measures from
   committed bytes, from the committed CRAN Archive tarball member, or is
   transcribed from a committed live-inspect JSON. Witnesses committed:
   `hash_provenance_r5_CLEAN.json` (live family, rc 0) and
   `hash_provenance_TAMPERPROBE_DEFECT.json` (RED: a one-byte-tampered
   copy of the manifest — the probe file, never live state — must and does
   fire `manifest-entry-rehash` + `unbacked-literal`, rc 2).
3. **The control vector** (manifest schema `m7-rehearsal-manifest-2`): the
   minting tool records `sha256('abc')` from its own invocation; the lint
   refuses any manifest whose control vector misses the true digest —
   the RB-06(1)(i) SHA-1-as-SHA-256 class now dies the gate on first
   contact. `measured_provenance` binds every backing source (tarball hash
   `b2836c76…1953b` and NAMESPACE-member hash re-measured against an
   independent upstream re-download — exact match — plus the fixture file).

## Phase-B pass 1 — the shard OOM over-commit (seventh recorded defect,
## matrix-class, tooling-owned)

The first authoritative-pass attempt fanned the eight shards out UNBOUNDED
(`tools/run_m7_bench.sh` line 42 — one background process per shard, no
cap). Measured outcome (not narrative): 8/8 shards completed and filed;
42/42 cells attempted; **20 cells FAILED — 17 sigminer + 3 sigprofiler** —
with the VM's kernel answering ten containers' worth of worker processes on
10 vCPUs / 8319504384 bytes (`docker info` verbatim): sigprofiler cells die
`container run failed (exit 137)` (SIGKILL) right after
`[Parallel(n_jobs=10)] ... LokyBackend with 10 concurrent workers`; sigminer
cells die `Future ... MultisessionFuture interrupted (pid ...)` plus R's own
furrr allocation diagnostics and `Execution halted`, after 39–88 minute
crawled runs against 4–7 minute floors (≈10× contention drag). The frozen
thread-caps were injected and enforced throughout — they cap BLAS/OpenMP
THREADS; they cannot reach joblib/Loky or future::multisession PROCESSES,
which size to the VM. The recorded G0 over-subscription lesson (8-way
fan-out under an 8 GB VM) re-manifested as an omission in the m7 driver.

Classification: instrumentation-class defect of the driver — NOT the r5
image (probe GREEN, self-witness rc 0), NOT the frozen protocol (the 22 ok
cells' seed-pinned outputs stand; zero failed-cell cache entry was accepted
under the four-file guard). Witness committed per the standing
capture-before-retry order: `phase_b_SHARD-OOM_DEFECT.json` (verbatim
per-cell death texts, per-file sha256s, control vector). Cure under
controller ruling: bounded concurrent-container fan-out + cache-hit
re-entry of only the failed cells, then straight through RB-06(5)
(authoritative serial pass, byte-equality attestation, resample gate,
four gates, PR #13).

## RB-08 — cache-reuse denial and the launch-governance seal (eighth law-group)

Controller ruling RB-08, amended on record: the cache is DENIED for reuse —
not on the originally cited inflation arithmetic (that measurement was
compiled through `'__N100' in label`, which swept N10000/N100000/N1000000
into the N100 class; the controller owns the retraction: comparing large-n
cpu_seconds against the N100 probe floor was bogus arithmetic), but on
three merits that need no retracted number:

1. the matrix is INCOMPLETE — 20 of 42 cells failed; no all-pass census
   exists to reuse;
2. uniformity-by-construction is VIOLATED for every surviving cell — all
   eight containers co-tenanted the VM for each cell's entire lifetime;
3. the failed cells crawled 39–88 minutes against 4–7 minute
   pre-registered floors — severe contention is proven by their own clocks.

The FUTURE_MAX_WORKERS probe result (the knob is NOT honored by the r5
image's future plan — live `docker top` counted 10 workers with
`FUTURE_MAX_WORKERS=1` set) is adopted as proof of the doctrine it was
designed by: measure, never assume. The worker pool is therefore
OBSERVED, per cell, via a `docker top` census sidecar
(`cachedir/census/<cell>/census.json`) — OUTSIDE the four-file guard and
the BYTE_EQUAL set, so it can never contaminate cache-hit byte
comparisons. The driver's fan-out, not the tool's pool, is the bounded
quantity: benchmarking sigminer with the pool capped to 1 would measure a
different program.

The seal is suite group (P) `tests/test_matrix_governance.py` (15 units,
TDD RED-first) over `tools/matrix_governance.py`, all pure with injected
docker probes (CI-safe, same idiom as (L)):

- **exact stamp grammar** — `parse_stamp` is the one admissible reader of
  `tool__arm__N<int>`: ASCII digits only (the `int("١٠٠")` trap), no
  leading zeros, full-string arms; `class_by_n` partitions by PARSED int
  equality. Substring classification is now a compile-time impossibility,
  not a discouraged practice;
- **judgment refuse-to-claim** — `write_judgment` over any non-pass row
  speaks as DEFECT and certifies nothing; the FAIRNESS ATTESTATION header
  is admitted only over a complete all-pass matrix (matrix1 filed its
  header over 20 failed cells — never again by construction);
- **pre-flight co-tenant refusal** — before any container launch the
  driver counts live measurement-image containers (`docker ps`, registry-
  derived image set, so a shiny/test co-tenant never trips it) and
  REFUSES to launch while any is live, logging the outcome per cell to
  `preflight_log.jsonl`;
- **worker census** — max-sibling-proc extraction from injected `docker
  top` tables, folded across during-run samples into the census sidecar;
- **3x-floor gate** — pre-registered, pre-committed floor table
  (`floor_for`): BOOT+WORK anchors at the r5 GREEN probe (sigminer
  360.25 cpu_s) and pilot §2 (sigprofiler 13.4 s wall), saturating sqrt
  growth in n (mutation-space saturation: the committed N1e4 survivors
  prove linear scaling would mispredict by an order of magnitude), arm
  multipliers from the §5 pass-count projections; unknown tool = exempt
  (mock is plumbing), unknown arm of a measured tool = hard error — an
  ungated cell is forbidden;
- **driver text law** — `run_m7_bench.sh` is rewritten STRICT SERIAL:
  every shard invocation foreground, and a unit fails the suite if a
  background `&` ever reappears in the driver outside an fd redirection.
  The eighth defect was one character; it is now a test failure.

Execution order per the amendment: commit the governance set → hash-
manifested purge of `cache/bench_degraded_docker` (evicted-entry count in
the DEFECT-witness addendum, deny-on-merits rationale restated, withdrawn
numbers removed) → fresh 42-cell serial ignition under the frozen protocol
(master seed 20260928 verbatim, zero protocol touches), with the first
three cells' measured wall/cpu against their floor classes reported
mid-flight before the tail sinks → straight through RB-06(5).
