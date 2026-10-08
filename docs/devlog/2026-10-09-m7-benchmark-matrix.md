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
