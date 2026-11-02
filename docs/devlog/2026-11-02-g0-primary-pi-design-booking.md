# G0 PRIMARY (full-authority) authoritative run — design booking (2026-11-02)

**Purpose.** Pre-register the execution design of the single authoritative G0
`primary` run — the experiment that underwrites the paper's quantitative spine
(first coverage-measured intervals claim; ARCHITECTURE.md GATEs that claim
pending exactly this run). This memo books the design BEFORE ignition: cost
basis, shard/cell plan, co-tenancy attestation plan, ledger accounting and
resume semantics. It changes no frozen parameter (D3/D9/F1-F5 untouched);
the runner it books is `bench/g0/tools/run_primary_pi.sh`.

## 1. Authorization and the frozen frame

- The frozen protocol (`2026-09-28-G0-pi-adjudication.md` §PI-5) admits the
  formal verdict only from `primary|degraded × docker × cosmic-file`.
  The degraded authoritative run closed 2026-10-08 (verdict A,
  `bench/results/docker_degraded_pi_20261007-212438/`). The primary run is
  the remaining leg: memo option 2 (`2026-10-07-g0-pi-run-cost-memo.md` §5),
  user-authorized 2026-11-02 at full speed.
- Posture: the memo's spare-core opportunistic posture (§5 recommendation).
  The thread caps the memo's live diagnosis hardened into
  `run_grid.build_docker_cmd` (four `*-e {OMP,OMP_TL,STAN_OMP,OPENBLAS}
  =1` env pins, frozen 2026-10-07, byte-identical in the working tree —
  attested by digest below) are what make the spare-core posture sound; they
  are gates and are not touched here.
- Post-cap epoch law: all cell bytes in this campaign are born after the
  cap-fix epoch (the same commit era that closed the degraded run), so no
  pre-cap cell can leak into the authoritative table; the fresh cachedir
  guarantees the epoch boundary by construction.

## 2. Measured basis (this rig, 2026-11-02)

Rig: `ShixiangWang-WorkSpacedeMacBook-Pro.local`, 10 logical CPUs
(`hw.logicalcpu=10`), host RAM 24 GB, Docker daemon 29.8.2, VM memory
8 319 504 384 B (`docker info MemTotal` ≈ 8.3 GB — the constraining
number). Baseline `vm.loadavg` at booking: {3.52 3.61 4.09} (light).

| measured quantity | value | witness |
|---|---|---|
| g0 self-check | 47/47 green | `python3 -m tests.run_all` this session |
| user F3 files | catalog 117086 B, sig 6158 B, gitignored (`git check-ignore` hit `.gitignore:45`) | sha256 banked §3 |
| degraded shard pass @8-way | 19/42 cells `fail` exit-137 (OOM-class kill), 23 ok | committed `timings_sharded_master.csv` status census (this session) |
| degraded repair pass | 19 cells re-measured ok serially + 23 cached | committed `timings_degraded_20261008-013748.csv` |
| warm per-rep wall (from committed bytes) | sigfit ≤ ~7 s, STL ≤ ~42 s (slowest cell 4168 s @100 reps) | master table §4 of GO-05 era |
| memo floors | serial warm ≈ 263.5 h, serial cold ≈ 791 h for the 40400 rep-runs | memo §2-§3 |

**Fan-out ruling (design, not a gate change): FANOUT=4.** The memo's ×8 column
is an extrapolation; the measured reality of ×8 on this 8.3 GB VM is the
degraded run's 45 % exit-137 kill rate, whose repair leg (serial 10–12 min
per cell) is the very cost the fan-out must avoid. F=4 halves the concurrent
container footprint below the memory cliff while keeping the machine's
spare-core window; ideal wall = 263.5/4 ≈ 66 h.

Projection vs the lane-card figure: the card quotes "~58.82 h projected vs
T2 58.75 headroom" as the memo's numbers — the memo body text carries no
such pair (its numbers are the §2/§3 table above); the card figure is banked
as controller-side provenance and is bracketed: the booked F=4 band (§5)
covers it. MEASURED-then-stated: the authoritative wall-time claim will be
read off the committed timing bytes at closure, not from this projection.

## 3. Inputs and D3 attestation

User-supplied F3 files live OUTSIDE the repo index in the gitignored
`bench/g0/cache/` (main checkout; the feature worktree carries no cache):

| file | bytes | sha256 |
|---|---|---|
| `g0_catalog.csv` | 117086 | `733e38c50b94f7dc59cef15eb042fc4359a818314fb3efb3824a7c54642c3f60` |
| `g0_signatures.csv` | 6158 | `80e911998764667dcb715e7390671e32aa2bbe657a43be398e5e8319305ba29e` |

`git check-ignore -v` hits `.gitignore:45 /bench/g0/cache/` for both;
`git status --porcelain bench/g0/cache/` is empty; zero real-data bytes are
ever committed (D3). The runner pins both digests as constants and refuses
(rc 2) any divergence — a tampered ground-truth file cannot reach the
mount. Digest pins carry reading tests + a drift attestation duty: if a
pinned file ever legitimately moves (re-derivation via
`tools/g0-derive-inputs.R`), the pin change rides its own commit with the
new reading witnessed.

Harness provenance digests (authoritative tree @ branch base):
`run_grid.py ff60aeb6…`, `adapters/Dockerfile.sigfit be301da1…`,
`adapters/Dockerfile.stl 1c75fe67…`, `run_sigfit.R dd3c9573…`,
`run_stl.R f4993f4c…`; the adapters' command lines are byte-identical to
the degraded-run era (`git diff 0113d05..HEAD -- bench/g0/adapters/` shows
documentation/comment translations only).

## 4. Cell/shard plan

`primary × docker × cosmic-file × {sigfit,stl}`, F2/F3 frozen values:
19-point grid × 200 reps for the five full-grid composition arms,
POLE pinned to its high-N tier, sensitivity trio single-point.
(arm,N) cells/tool = 101; total cells = 202; rep-runs = 40400 per tool
pair — the memo §3 `primary` row.

Shard plan mirrors the closed degraded driver (disjoint arm keys under one
shared cachedir ⇒ concurrent shards are byte-equivalent to serial; judgment
is a pure recomputation over the full cell set in the final serial pass):

| wave order | shard tag | arms |
|---|---|---|
| 1 | main | main |
| 1 | comp_clock_only | comp_clock_only |
| 1 | comp_mmr | comp_mmr |
| 1 | comp_flat_triple | comp_flat_triple |
| 2 | comp_strong_flat | comp_strong_flat |
| 2 | nb | nb |
| 2 | clock_sparse | clock, sparse |
| 2 | comp_pole | comp_pole |

Light-first ordering keeps a defect candidate in a cheap cell halting the
pass before the heavy pole tier spends its hours. F=4 rolling window
(never >4 concurrent containers machine-wide). The final serial pass over
the full grid (all shards complete) emits the authoritative
Seeds/coverage/judgment and doubles as the repair leg: cache-skip requires
`intervals.csv` + `errors.log`, so any cell the shard pass lost to an
exit-137 is re-measured once, serially, at full wall — exactly the closed
degraded closure shape.

## 5. Duration-band watchkeeping law

Judge health by progress, never by minute-intuition (the two premature
cancel-reruns spent learning this; CI-arm-duration truth).

- Completion band: [40 h, 200 h]. Floor = 263.5 h/4 minus generous margin
  (a sub-40 h finish implies cache-fabricated seconds — audit before
  believing). Ceiling = cold-rate floor 791/4 ≈ 198 h rounded up.
- Progress heartbeat (lane side, every 5 min to `/tmp/g0plane/logs/`): UTC
  stamp, `docker ps` measurement-container count, witnessed-cell counter
  (`cells/*/out/intervals.csv` present count over the 202-cell set), shard
  log tail, `vm.loadavg`. A stalled arm is one whose witness count has not
  moved across ≥2 consecutive band-normal cell expectations, corroborated
  by shard-log byte-frozen tails and a live `docker ps` view — only such a
  corroboration, never a wall-clock feeling, licenses a cancel decision,
  and even then the cancel+resume follows the CI-infra-stall precedent
  (cancel, rerun reusing completed arms via the death protocol).
- Legitimacy of a co-tenancy bar refusal: the pre-flight sampler refuses
  (rc 2) when a measurement-class container is live or `load1` > BAR; that
  is an event to report, never an obstacle to route around; the bar is
  constant (`10.0` = the 10 vCPU class — oversubscription above the whole
  machine's capacity means the rig is not spare) and an operator export of
  `G0_PI_LOAD_BAR` is itself a refusal.

## 6. Single-ignition ledger accounting

House ledger = `campaign_launches.jsonl` with the house columns
`{"kind":"launch","mode":…,"ts":…}` (UTC `date -u`); the reader counts
`mode=="full"` rows:

- Authoritative ignition appends exactly one `mode:"full"` row, after the
  pre-flight gates pass, mirroring the bootstrap campaign's
  census-then-append order (a death between census and append leaves no
  half-ignition).
- A fresh ignition against a cache dir already bearing a campaign identity
  (`.primary_pi_outdir` pointer) is refused rc 2: the campaign's identity
  survives its deaths; you do not mint a second one.
- A ledger holding ≥2 `mode:"full"` rows is refused rc 2 (double-full-row
  law, TDD-pinned).
- Resume (the only legal continuation): `G0_REUSE_CACHE=<campaign cachedir>`;
  the outdir is re-read from the pointer (no new stamp — the single
  ignition identity persists), the ledger must show EXACTLY one `full` row
  (absent or doubled ⇒ refusal), and no new row is appended — a resume is
  not an ignition. Optional `G0_SKIP_SHARDS="tag tag…"` for shards whose
  cells are all witnessed; it is a wall-clock optimization only, since the
  final serial pass recomputes the complete grid regardless.
- `G0_PI_REHEARSAL=mock` (with mandatory `G0_PI_REPS`) is the calibration
  face (mock adapter × synthetic provider): its ledger row is
  `mode:"rehearsal"` — invisible to the `full` counter, exactly the
  bootstrap probe-entry discipline — and it can never reach the docker face.

## 7. Hardware-pin attestation (the nine-column class)

The authoritative rollup `timings_sharded_master.csv` speaks the M7 canonical
nine-column contract:

```
cell,tool,arm,n,seconds,status,cpu_seconds,host,hw_profile
```

- `host` = `$(hostname)` at ignition; `hw_profile` = the operator-exported
  canonical pin (for this rig: `"10 vCPU / 8 GB class"`, the M7-verbatim
  machine class). The runner refuses rc 2 a blank pin exactly as an absent
  one (env-shadow sensitivity: the gates are measured live with the real
  pin exported, never with a silent default).
- `cpu_seconds` carries the literal `unmeasured`: the G0 adapter protocol
  reports no container CPU accounting and fabricating one from a local CLI
  wrapper would be a false claim (MEASURED-then-stated; the GO-05
  backfill-fabrication precedent binds). The reader-side verifier
  (`tools/verify_hardware_pin.py`, g0-local twin of the M7 instrument)
  verdicts every row's `host`/`hw_profile` from the table's own bytes
  (rc 0 ok / 1 named offenders / 2 unreadable) AND fails any row whose
  `cpu_seconds` is anything other than `unmeasured` — the table can make no
  CPU claim by construction.

## 8. Witness set (committed surfaces at closure)

Mirror of the closed degraded deliverables, under
`bench/results/docker_primary_pi_<UTCstamp>/`:
`Seeds.txt`, `coverage_primary_*.csv`, `judgment_primary_*.md`,
`timings_primary_*.csv` (final pass), `timings_sharded_master.csv` (9-col),
`campaign_launches.jsonl`, `witnesses/host_census.jsonl` (pre-flight
tenancy readings incl. load triple and `docker ps` snapshot),
`diagnostic_lrt_nb.csv` (P3 report column). `result.md` at the campaign dir
speaks only what the committed bytes prove (status-column census read from
the bytes themselves, reader-verifier JSON verbatim, zero speed/coverage
claims beyond what the tables attest). No real-data numerics beyond the
sanctioned attestation classes.

## Appendix A — pre-ignition verbatim attestation (executed 2026-11-02, G0-P lane)

Images (built fresh from the byte-attested Dockerfiles above, serially per
the 137-lesson; build logs /tmp/g0plane/logs/build_{sigfit,stl}.log):

```
g0-sigfit@sha256:88dca593b2423d760b5dcb543a58bcfdb2306c8ee7a9d6c611a4c4f95cd9847d
g0-stl@sha256:8058116257450032fce980a90039e2a1e908e74262e9ec9448ce857d99d0af82
```

Harness docker-path liveness (smoke profile, real adapter, synthetic
provider — a harness self-check, zero verdict power; verbatim):

```
[adapter] docker: 8/8 cells ok; timings -> cache/smoke_probe/out/timings_smoke_20261103-003143.csv
```

Runner law censuses (verbatim from `/tmp/g0plane/logs/`): RED bank (runner
absent): `47/66 tests passed.` with all 19 lane laws FAIL, prior 47 green.
GREEN bank (instruments + images present): `66/66 tests passed.`

Authoritative-face pre-flight (co-tenancy attestation, verbatim):

```
PREFLIGHT-PASS gates=env,digests,pin,identity,ledger,marker,images,tenancy fanout=4
```

At that reading: `vm.loadavg = { 3.72 3.84 4.10 }` under BAR 10.0;
`docker ps` = `shiny-server-test rocker/shiny:latest` (non-measurement
scaffolding per governance scope); G0 digests matched their pins by live
reading (`shasum` in-gate).

Ignition (the ONE authoritative shot, verbatim):

```
IGNITION-FIRED pid=86033 stamp=20261102-163222 log=/tmp/g0plane/logs/20261102-163222.ignition.log
[ignition] shard main start 2026-11-02T16:32:22Z (fan-out 0/4)
[ignition] shard comp_clock_only start 2026-11-02T16:32:22Z (fan-out 1/4)
[ignition] shard comp_mmr start 2026-11-02T16:32:22Z (fan-out 2/4)
[ignition] shard comp_flat_triple start 2026-11-02T16:32:22Z (fan-out 3/4)
```

Campaign identity: cachedir `bench/g0/cache/primary_pi`, outdir
`bench/results/docker_primary_pi_20261102-163222`, ledger row
`{"kind":"launch","mode":"full","ts":"2026-11-02T16:32:22Z"}` — the single
full row; continuation is G0_REUSE_CACHE resume, never a second ignition.
