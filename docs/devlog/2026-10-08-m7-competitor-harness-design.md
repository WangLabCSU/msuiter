# U-M7-02 competitor benchmark harness — design memo (2026-10-08)

Status: **design accepted / TDD RED batch committed; GREEN implementation is the
next dispatch.** Scope: `bench/m7/` only. The R package surface (`R/`, `src/`,
`tests/`) is untouched; the frozen G0 harness (`bench/g0/`) is reused
read-only and is never modified (G0 drift guards in `tools/ci-selfcheck.py`
stay green — proven below).

Inputs read before deciding (per brief): IMPLEMENTATION-PLAN §M7/§5 (U-M7-02
row, G0 gate), ARCHITECTURE §8 (scenario grid, pinned-hardware bench,
Hungarian P/R/F1 primary metric) and §9 (CI contract), the G0 harness
(`bench/g0/run_grid.py`, `adapters/adapter_protocol.md`, `tools/run_degraded_pi.sh`,
`tests/run_all.py`), the authoritative-run shape
(`bench/results/docker_degraded_pi_20261007-212438/`), and
`docs/devlog/2026-10-08-g0-degraded-closure.md` (thread-cap cure).

## 1. Position of this harness

ARCHITECTURE D9/D15: external tools are bench references and never enter the
`ms_*` API. G0 measured *coverage* of two Tier-1 competitors; M7-02 measures
*assignment quality and cost* of the paper's competitor table on the same
frozen inputs. The single orchestrator idiom (generation → adapter →
parse → table → authoritative pass) and the cell contract
(`in/{counts.csv,params.json}` read-only, `out/{intervals.csv,errors.log,manifest.json,timing.json}`)
are inherited verbatim from G0 — this is a DRY extension, not a parallel invention:

* simulation reuses `bench/g0/g0/` (`sim.py`, `seeds.py`, `grid.py`) by
  `sys.path` insertion, exactly as the G0 test suite does. M7 imports the
  frozen modules; it never edits them and never reads or writes
  `bench/g0/cache/` (its own cache lives under `bench/m7/cache/`).
* seeds reuse the same master seed `20260928`, the same FNV-1a +
  SplitMix64 counter-stream derivation (`g0.seeds.derive_seed`), and the same
  `Seeds.txt` manifest + commit-SHA discipline. M7 tool streams are
  namespaced (`"m7-tool|<competitor>|<arm>|N<n>|r<k>"` labels) so they cannot
  collide with G0's `"g0/v1|tool|…"` streams; benchmark inputs are
  bit-identical to the G0 degraded profile because the data streams
  (`arm, N, rep`) are unchanged.
* cache discipline inherits the G0 lessons: per-cell `.data_hash` over
  counts + arm params + competitor identity/version + caps (the
  2026-10-07 stale-cache root-cause fix), and the re-run guard requires
  `intervals.csv` **and** `errors.log` **and** `manifest.json` **and**
  `timing.json` — stricter than G0's two-file guard because the fairness
  table is not attestable without the manifest/timing sidecars.

## 2. Competitor selection and PINNED provenance

Selection per the PI brief; each entry carries the evidence of how the pin was
established today (2026-10-08) and an explicit `PENDING-VERIFY` where the
registry could not be confirmed. **No digest is ever invented**: digests are
recorded only from `docker image inspect` output of a verified mirror pull.

| # | Competitor | Runtime | Pinned version | Provenance evidence | Container image | Digest | Status |
|---|---|---|---|---|---|---|---|
| a | **sigminer** | R | CRAN **2.3.1** | `packageVersion("sigminer")` → `2.3.1` in the host R library `/Users/wsx/Library/R/arm64/4.5/library/sigminer` (2026-10-08); SBS96 label-aligned cross-validation against this copy already gates the package (`tests/testthat/test-xval-sigminer.R`) | harness-built `m7-sigminer:cr2.3.1` (mirror-pulled `rocker/r-ver` base + CRAN install + build-time `packageVersion()=="2.3.1"` assert, G0 build-guard idiom) | PENDING-VERIFY | ready (after image build) |
| b | **SigProfiler (assignment)** | Python | **v1.1.5** | `gh api repos/SigProfilerSuite/SigProfilerAssignment/releases/latest` → tag `v1.1.5`, published 2026-07-29T09:00:29Z; `repos/AlexandrovLab/SigProfilerAssignment` redirects to the same canonical repo. README advertises PyPI, but this network's PyPI index has **no** distribution ("No matching distribution found", 2026-10-08) → pin provenance is the git tag; container installs `pip install git+<repo>@v1.1.5` | harness-built `m7-sigprofiler:spa-1.1.5` (mirror-pulled Python base) | PENDING-VERIFY | ready (after image build) |
| c | **Signal** | R (Bioconductor) | **UNRESOLVED** | Registry probes on 2026-10-08: not in the CRAN index (`available.packages()` over `cloud.r-project.org`); not in the Bioconductor **3.22** index enumerated via `BiocManager::repositories()` (name search returns only unrelated packages, e.g. `SIGN@0.1.0`, legacy `signal@1.8-1`); `gh api repos/debruijn-lab/Signal` → 404; GitHub search finds no canonical repo. Selection is kept per the PI brief, but the exact package/version/image coordinates must be supplied by the PI before it can run. | — (none pinned) | PENDING-VERIFY | **pending-verify → refuses to run** |

Notes on three recording decisions:

* **sigminer 2.3.1 vs the host source tree.** The verbatim ground-truth copy
  at `/Users/wsx/Documents/GitHub/sigminer` reads `Version: 2.3.3` in its
  DESCRIPTION — a host working tree ahead of the registry. The benchmark pins
  the **installed CRAN 2.3.1** copy, because that is the exact artifact the
  existing xval gate cross-validates msuiter's SBS96 catalog against; the
  source tree remains the read-only semantic reference. The version assert in
  the image build (and the registry pin) make any drift loudly fail.
* **Execution symmetry.** All three competitors execute as containers on the
  same Docker VM. The host-library sigminer copy is provenance evidence and
  the xval anchor — not the benchmark executor — because mixing a host-R
  process with VM-resident competitors would make wall/CPU attribution
  incomparable, violating the fair-comparison protocol below.
* **Competitor (c) identity — HYPOTHESIS / UNVERIFIED.** The PI brief names
  competitor (c) "Signal (R/Bioconductor)"; the registry probes above find no
  such package on this network. The PI-controller hypothesis — recorded for
  PI-side verification, **not adopted as fact** — is that the brief denotes
  **signeR**, the Bayesian-NMF mutational-signature R package, which this
  repository's own algorithm zoo already classifies as an Adapt-basis
  baseline: `docs/research/07-algorithm-zoo.md:72` (Bayesian HMC/Gibbs NMF
  posterior; "sigfit/signeR as benchmark comparison only") and `:87`
  (Bayesian marginal-likelihood K selection; "signeR/BayesPowerNMF"). Zero
  provenance is invented under this hypothesis: no version, index or digest
  is claimed; the registry row stays UNRESOLVED/pending-verify and the
  adapter keeps refusing. Full ruling: §10.2.

## 3. Single ground-truth principle

* The only inputs competitors ever see are **msuiter-generated simulated
  counts** from the frozen G0 simulator (`g0.sim` multinomial/NB/clock/sparse
  arms, frozen composition axes, `sample_id = {arm}__N{n}__r{rep}` schema) plus
  the catalog file mounted read-only, exactly as G0 mounts the user's COSMIC
  file (`G0_CATALOG_PATH` idiom; D3 keeps COSMIC data outside the repo — M7
  adds none).
* Competitor invocation is **pure adapters only**: the harness writes
  `counts.csv / catalog.csv / params.json`, mounts `/work/in:ro`, and parses
  `intervals.csv` back. No competitor code path ever reaches msuiter internals.
* **No threshold or parameter invention.** Each competitor runs at its own
  documented defaults (SigProfilerAssignment: `cosmic_fit` defaults, COSMIC
  v3.6 default catalogue reference semantics; sigminer: package defaults). Any
  deviation from defaults requires a memo amendment here with a citation to the
  tool's own documentation; the first slice records **zero** overrides.
* Seeds drive whatever documented seed parameters each tool exposes
  (per-cell batch anchor + per-sample map, G0 §params.json discipline); where a
  tool documents none, the run is marked non-seedable in `manifest.json` —
  never a silent assumption of reproducibility.

## 4. Fair-comparison protocol

1. **Same hardware.** One local Docker Desktop VM for every competitor cell:
   measured today `docker info` → 10 vCPU, ~8.3 GB RAM (the 8 GB class the G0
   closure ran under). No host-side execution (see §2 note).
2. **Same thread caps.** Environment caps are injected **before the image
   name**, the exact position that cured the G0 over-subscription OOM storm
   (devlog 2026-10-08 §1, fix 333f06e): the G0 closure list
   `OMP_NUM_THREADS=1, R_LIMIT_THREADS=1, GOMAXPROCS=1, MSUITER_THREADS=1`
   plus the BLAS/Stan caps already present in `run_grid.py::build_docker_cmd`
   (`OMP_NUM_THREADS, OMP_THREAD_LIMIT, STAN_OMP_NUM_THREADS,
   OPENBLAS_NUM_THREADS`). The union is frozen once as
   `docker_cmd.THREAD_CAPS`; a RED-pinned test asserts every adapter's
   composed command carries every cap and that no cap appears after the image
   token (position is semantically load-bearing). Sampling semantics are
   untouched — caps are pure execution-layer ceilings, as in G0.
3. **Wall + CPU time columns.** The timings table keeps G0's six columns
   **verbatim and in order** — `cell,tool,arm,n,seconds,status` — so G0 and
   M7 tables concatenate into one benchmark table, and appends
   `cpu_seconds`. Wall seconds = subprocess measurement around `docker run`;
   CPU seconds = container-reported `ru_utime + ru_stime` (`resource.getrusage
   (RUSAGE_CHILDREN)` around the in-container entrypoint) written to
   `out/timing.json` by the runner, parsed by the adapter. The G0 six-column
   header is committed as a fixture (byte-copied from
   `bench/results/docker_degraded_pi_20261007-212438/timings_sharded_master.csv`)
   and the schema test pins prefix equality against it.
4. **Cache-hit recompute pass.** Same sharded-then-serial orchestration as
   `tools/run_degraded_pi.sh`: arm shards run concurrently over one cachedir,
   every tool invocation is idempotent via the hash+four-file guard, and the
   run ends with a serial full-grid pass that hits the cache and emits the
   authoritative outputs (minutes, not hours).
5. **Authoritative output dir contract.** `bench/results/docker_m7_<UTCts>/`
   contains `Seeds.txt`, `timings_m7_<ts>.csv` (final pass),
   `timings_sharded_master.csv` (rolled shard timings, every measured second
   attributable), `benchmark_m7_<ts>.csv` (per-cell P/R/F1 + exposure-error
   rows, Hungarian primary metric per ARCH §8) and
   `judgment_m7_<profile>_<ts>.md` (this slice: the fairness attestation —
   every cell ran at the pinned version with the frozen caps and seeds; the
   scoring verdict text is the later slice). Same "harness output, adjudication
   gate" framing as the G0 judgment document, including the honest footer about
   which run classes are authoritative.

## 5. NETWORK policy (harness-global, binding on every adapter and Dockerfile)

Container images are pulled **only** through the user's mirror domains. Direct
upstream pulls from this network fail (proxy error 407) and are prohibited —
a 407 is environmental evidence, not a reason to route around the policy.
The translation table (prefix an image with the mirror host instead of the
upstream host) is the authoritative record for this harness:

| Upstream host | Mirror prefix |
|---|---|
| `docker.io` | `9f6c5in3dh5vszgdz0.xuanyuan.run` |
| `ghcr.io` | `9f6c5in3dh5vszgdz0-ghcr.xuanyuan.run` |
| `quay.io` | `9f6c5in3dh5vszgdz0-quay.xuanyuan.run` |
| `registry.gitlab.com` | `9f6c5in3dh5vszgdz0-gitlab.xuanyuan.run` |
| `mcr.microsoft.io` | `9f6c5in3dh5vszgdz0-mcr.xuanyuan.run` |
| `gcr.io` | `9f6c5in3dh5vszgdz0-gcr.xuanyuan.run` |
| `nvcr.io` | `9f6c5in3dh5vszgdz0-nvcr.xuanyuan.run` |

Rules: (i) every `FROM` and every `docker pull` in `bench/m7/` spells the
mirror host explicitly; (ii) after the first verified pull the image is
re-referenced **by digest** and the digest recorded into the registry entry —
any field whose digest was not captured from `docker image inspect` reads
`PENDING-VERIFY` and the adapter treats it as not-ready; (iii) `gh api` /
`git clone` for source provenance follow the established repo practice and are
outside this image-pull policy.

## 6. Adapter registry and module layout (the contract GREEN implements)

```
bench/m7/
├── run_bench.py                 orchestrator (mirrors run_grid.py idiom)        [GREEN]
├── tools/run_m7_bench.sh        sharded driver + final cache-hit pass           [GREEN]
├── competitors/
│   ├── __init__.py
│   ├── registry.py              CompetitorSpec dataclass; REGISTRY: {sigminer,
│   │                            sigprofiler, signal}; load()/lookup() (unknown
│   │                            name → error listing available names, the
│   │                            zero-magic-string idiom from the engine table)    [GREEN]
│   ├── docker_cmd.py            THREAD_CAPS frozen tuple; build_container_cmd()
│   │                            (mirror-verified image ref, /work mount contract,
│   │                            caps-before-image invariant)                       [GREEN]
│   ├── timings.py               TIMINGS_COLUMNS (7), G0-prefix writer, rusage
│   │                            sidecar schema                                    [GREEN]
│   ├── errors.py                AdapterUnavailable(reason) skip-not-skip sentinel [GREEN]
│   ├── sigminer_adapter.py      container run, default params, parse            [GREEN]
│   ├── sigprofiler_adapter.py   container run, cosmic_fit defaults, parse        [GREEN]
│   └── signal_adapter.py        raises AdapterUnavailable("pending-verify…")
│                                until §2 coordinates are supplied                 [GREEN]
├── tests/                       RED batch (this commit)
│   ├── run_all.py, test_registry.py, test_adapters.py,
│   │   test_timings_schema.py, test_output_contract.py
│   └── fixtures/                g0_timings_header.csv, g0_intervals_header.csv,
│                                m7_timings_header.csv (7-col expected shape)
└── .gitignore                   cache/ , __pycache__/
```

**skip-not-skip protocol** (as used by the G0 suite): a missing environment is
an explicit, *reported* outcome — never a silent green. An absent image or an
unresolved provenance makes the adapter raise `AdapterUnavailable` with the
reason; the dispatcher prints `SKIP <name> (<reason>)` and tallies skips
separately. Any cell the protocol requires to be adjudicated that came back
SKIP fails the run exit code. The presence of a refusal mechanism is itself
test-asserted (a test may not pass by the exception going missing).

## 7. TDD RED batch (this commit)

Tests live in `bench/m7/tests/` mirroring the G0 idiom (plain `test_*`
functions, `python3 -m tests.run_all`, no pytest dependency). Run:

```bash
cd bench/m7 && python3 -m tests.run_all          # RED now, GREEN after U-M7-02 impl slice
cd bench/g0 && python3 -m tests.run_all          # must stay green (frozen protocol)
python3 tools/ci-selfcheck.py                     # must stay exit 0
```

* `test_registry.py` — registry loads exactly the three competitor names with
  statuses ∈ {ready, pending-verify}; each entry's provenance carries its pin
  (sigminer `2.3.1`, SigProfilerAssignment `v1.1.5`) or an explicit
  PENDING-VERIFY field; `lookup()` on an unknown name errors listing the known
  ones.
* `test_adapters.py` — for every competitor, invoking the adapter while its
  pinned image/namespace is absent raises `AdapterUnavailable` (never a
  generic error, never a zero-execution success); the pending-verify entry
  (Signal) refuses even with Docker present; composed commands place every
  frozen thread cap before the image token.
* `test_timings_schema.py` — adapter timings headers equal the committed G0
  six-column header as an exact ordered prefix and append `cpu_seconds`;
  writer output round-trips the committed fixture row.
* `test_output_contract.py` — a completed cache-hit cachedir fixture drives
  the final pass to emit the authoritative outdir file set with the §4.5 names;
  a cell missing any of the four guard files is re-run, not trusted.

Expected RED cause: `ModuleNotFoundError` for `competitors.*` / `run_bench`
(RED-by-absence; no fake competitor logic is pre-seeded — YAGNI). The failure
transcript is recorded in the RED commit message.

## 8. Scope discipline and non-goals

* Everything lives under `bench/m7/` (plus this memo). `R/`, `src/`, `tests/`
  are untouched; nothing here may be imported by the package.
* G0 constants (`MASTER_SEED`, grid, reps, thresholds) are **not modified**;
  M7 consumes them. The G0 drift guards in `tools/ci-selfcheck.py` stay green
  (proven in the verification record below).
* `bench/g0/cache/` and all COSMIC/user data: read-only by contract, never
  referenced from any M7 code path (a GREEN-gate grep assertion is specced).
* No metric scoring, no judgment prose beyond the fairness attestation, no
  ms_benchmark() surface — later U-M7-02/03 slices.
* `pip`/CRAN package installs during image *build* follow whatever the G0
  Dockerfiles already established; §5 governs container *image* pulls.

## 9. Verification record (commands actually run for this memo commit)

See the RED commit body for transcripts: ci-selfcheck exit 0; G0 suite
`42/42` green; M7 RED batch fails at the missing-implementation seam.

### 9a. GREEN slice (2026-10-08, same day; no test file or assertion touched)

Suites and gates (transcript tails as run under the worktree):

- `cd bench/m7 && python3 -m tests.run_all` → `12/12 tests passed.` (exit 0).
  Note: the brief's "4/4" refers to the four test modules; the runner's
  terminal line counts the twelve test functions they carry.
- `cd bench/g0 && python3 -m tests.run_all` → `45/45 tests passed.`
- `python3 tools/ci-selfcheck.py` → `ci-selfcheck: PASS (all CI wiring
  assertions hold)` (exit 0).
- Cache non-reference gate: `grep -rn "g0/cache" bench/m7` → no output
  (exit 1, zero matches). The G0 cache tree is never referenced by any M7
  code path.
- Mock smoke rehearsal `sh tools/smoke_rehearsal.sh`:
  `[rehearsal] cells=4 master_rows=4 (measured ok) final_pass_cached=4`,
  four per-cell attribution lines (`wall`/`cpu` per mock cell, `status=ok`),
  `REHEARSAL-VERDICT: shard-vs-serial byte-equal; cache-hit final pass;
  all measured seconds attributable`, `MOCK-REHEARSAL-OK` (exit 0).

### 9b. Image-build campaign (deliverable 3) — mirror pulls and in-build evidence

Base pulls through the §5 mirror (both `PULL-EXIT=0`, registry manifest
digests recorded from the pull transcript):

- `9f6c5in3dh5vszgdz0.xuanyuan.run/library/python:3.11-slim` →
  `Digest: sha256:0dd364ba7e10242f07755449e3a3d0e35f9efd987952737b90def6709ab0c5ce`
- `9f6c5in3dh5vszgdz0.xuanyuan.run/rocker/r-ver:4.3.3` →
  `Digest: sha256:732d15020af326da9e919c07f70ca32bf5d3e409220af32e0a4b6d0a89437309`

Environmental evidence recorded verbatim (probed from inside the build
network; no upstream bypass attempted):

1. Debian `.deb` pool fetches through the intercepting proxy fail
   intermittently with `502 Bad Gateway [IP: 198.18.0.44 80]` (three apt
   attempts, a different package each time — random, not deterministic;
   the mirror index fetch and most archives succeed).
2. The `codeload.github.com/<repo>/archive/…` URL family is dead on this
   network: from inside a build container all three forms, including the
   canonical `/archive/<commit>.tar.gz`, return `HTTP Error 404: Not
   Found`. The working container-side family is the API endpoint:
   `200 application/x-gzip` for
   `https://api.github.com/repos/SigProfilerSuite/SigProfilerAssignment/tarball/refs/tags/v1.1.5`
   (serves `SigProfilerSuite-SigProfilerAssignment-v1.1.5-0-gff61b0f.tar.gz`;
   tag verified via `git ls-remote --tags` → commit
   `ff61b0f56d43c916582b7c505ce72364c883dfbd`). The SigProfiler image
   therefore pins the tag through the API tarball endpoint — same artifact,
   recorded provenance, no git binary and no apt step needed.
3. The r-ver base's default repository stack lets `remotes` resolve some
   hard Imports (e.g. `Rhtslib 2.2.0`) through the legacy Bioconductor
   3.17 archive whose sources fail against this R:
   `bgzf.c:38:10: fatal error: zlib.h: No such file or directory` →
   `ERROR: compilation failed for package 'Rhtslib'`, cascading to
   `dependencies 'ggpubr', 'maftools' are not available for package
   'sigminer'`; and `nloptr` configure requires cmake (`CMAKE NOT FOUND`).
   The SigMiner image therefore pins `options(repos = CRAN-only)` and
   apt-installs `cmake` for the configure step.
4. That override fixed *which* Rhtslib resolves, but exposed a second,
   independent root cause: the r-ver base ships the zlib runtime without
   the dev headers, so even the CRAN-resolved Rhtslib died again verbatim
   `bgzf.c:38:10: fatal error: zlib.h: No such file or directory`
   (observed 2026-10-08 rebuild 1 — the header provisioning
   `zlib1g-dev libbz2-dev liblzma-dev` was added as a separate cached
   apt layer). Rebuild 2 with that provisioning then failed on the next
   missing header, verbatim
   `hfile_libcurl.c:47:10: fatal error: curl/curl.h: No such file or
   directory`, and additionally on an archive-resolution class the
   CRAN-only override routes around: `cannot open URL
   'https://cran.r-project.org/src/contrib/rbibutils_2.4.1.tar.gz'` and
   `...gridBase_0.4-7.tar.gz` (pinned older Imports live only under
   CRAN's `Archive/` subtree), cascading `Rdpack`/`reformulas`/`NMF`
   unavailability into `sigminer`. The controller-set rebuild budget
   (max 2 attempts per target) is exhausted and a third distinct
   in-build defect class surfaced, so per the standing directive the
   iteration stops here: the SigMiner entry keeps `PENDING-VERIFY` and
   its cells stay AdapterUnavailable skips (image_gate refuses before
   the daemon probe). A follow-up dispatch can provision `libcurl-dev`
   and a repo stack that includes CRAN `Archive/` in one pass.

Final build verdicts (captured from live `docker build` exit codes and
`docker image inspect`; nothing below is invented — an unverified entry
stays PENDING-VERIFY):

- `m7-sigprofiler:spa-1.1.5` — BUILD-EXIT=0 (final bake includes the
  orientation-corrected cell runner). `docker image inspect .Id` →
  `sha256:7dba2f43ad3a3858ed1cfdedd278c9c2f52a665fd4c18ac91a482b74258bfbed`,
  which is the value registry.py pins; each measured cell's manifest.json
  carries the same digest, and the first attributed live run recorded
  `4/4 cells ok|cached` with cache-hit on rerun.
- `m7-sigminer:cr2.3.1` — BUILD-EXIT=1 on both budgeted rebuilds (defect
  classes (3) and (4) verbatim above); registry entry stays
  `image_digest=PENDING_VERIFY` and its docker-adapter cells are
  AdapterUnavailable skips, never fabricated successes.

## 10. Open items for the GREEN dispatch

1. Author the two harness Dockerfiles (`Dockerfile.sigminer`, mirror-pinned)
   and the SigProfilerAssignment image recipe; capture digests via
   `docker image inspect` and update the registry entries (replaces
   PENDING-VERIFY).
2. PI input required for Signal: authoritative package coordinates (this
   network's Bioconductor index does not list it; see §2 probes). Until then
   its adapter must keep raising.

   **HYPOTHESIS / UNVERIFIED — sign-eR ruling (recorded by the GREEN slice,
   2026-10-08; zero invented provenance).** The brief's "Signal (R/
   Bioconductor)" is hypothesised to denote **signeR**, the Bayesian-NMF
   signature-extraction R package: this repository's algorithm zoo lists
   signeR — never "Signal" — in the Adapt column of the extraction and
   K-selection catalogs (`docs/research/07-algorithm-zoo.md:72`, `:87`).
   Under this hypothesis, competitor (c) would be a fourth container cell
   running a signeR release behind the same four-file guard, frozen thread
   caps and documented-defaults fairness contract, with its posterior channel
   measured like the others. The hypothesis is deliberately NOT adopted
   anywhere executable: no version, index or image coordinates are claimed;
   `competitors/registry.py` keeps `signal` at UNRESOLVED/pending-verify
   with a refusal that forward-references this item, and
   `competitors/signal_adapter.py` raises AdapterUnavailable unconditionally.
   Closure requires PI confirmation (or correction); if confirmed, the pin
   must be probed live exactly as the §2 rows a/b were — never inferred from
   this paragraph.
3. Implement `run_bench.py` + `tools/run_m7_bench.sh` (sharded driver), the
   three adapters, timings writer with the rusage sidecar, and the fairness
   attestation document; turn the RED batch green without touching the tests
   (except adding newly required fixtures).
4. Smoke rehearsal of the full orchestration with a mock-style local adapter
   (same as G0's mock idiom) proving shard-vs-serial byte-equality before any
   real competitor matrix is run.
