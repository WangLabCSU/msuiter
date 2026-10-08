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
The 2026-10-08 sigminer-image closure dispatch records its own gate
transcripts under §9b-closure below.

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
- `m7-sigminer:cr2.3.1` — BUILD-EXIT=1 on every budgeted build (both
  campaign rebuilds above and the 2026-10-08 closure dispatch below);
  registry entry stays `image_digest=PENDING_VERIFY` and its docker-adapter
  cells are AdapterUnavailable skips, never fabricated successes.

#### 9b-closure. Closure dispatch (2026-10-08): the §9b-item-4 follow-up — three budgeted attempts, verbatim

Mission: provision the curl dev headers and CRAN `Archive/` resolution
"in one pass" per item 4's follow-up line. Budget ledger: 1
recorded-recipe attempt + 2 spares for new distinct classes = 3 builds,
all consumed. Base pull unchanged (mirror-spelled `FROM`, §5; resolved to
the already-recorded `rocker/r-ver:4.3.3@sha256:732d15...`; no 407/502
observed this dispatch).

Attempt 1 (recorded recipe verbatim — `libcurl-dev` + the two Archive
pins) died on a NEW class: the bare package name is virtual on the jammy
base, verbatim:

```
#7 126.3 Package libcurl-dev is a virtual package provided by:
#7 126.3   libcurl4-openssl-dev 7.81.0-1ubuntu1.29
#7 126.3   libcurl4-nss-dev 7.81.0-1ubuntu1.29
#7 126.3   libcurl4-gnutls-dev 7.81.0-1ubuntu1.29
#7 126.3 E: Package 'libcurl-dev' has no installation candidate
exit code: 100                                   (BUILD-EXIT=1)
```

Spare attempt 1 pinned the concrete openssl-backed provider
(`libcurl4-openssl-dev`, matching the distro's runtime libcurl; TLS
backend is irrelevant to the `curl/curl.h` consumer) and the build
advanced into the Rscript step, which died inside the new `ensure.pin`
version probe — the base R's `packageDescription()` returns a
version-less empty listy (not NULL) for a not-installed package:

```
#8 21.66 Error in pd[["Version"]] : subscript out of bounds   (BUILD-EXIT=1)
```

The probe was tryCatch-hardened (both host-R NULL and base-R listy
shapes read as "version absent"). Spare attempt 2 advanced deepest
(~19 min of dependency compilation before the build guard failed it):
both Archive pins surfaced only as `install.packages` **warnings**, so
the error-gated ok-flag read TRUE, the Archive fallback silently never
ran, and the era-pinned Import tree 404/SSL-failed through contrib-only
fetches — verbatim:

```
#8 26.19 2: package ‘rbibutils==2.4.1’ is not available for this version of R
#8 26.34 2: package ‘gridBase==0.4-7’ is not available for this version of R
#8 144.9 trying URL 'https://cran.r-project.org/src/contrib/cli_3.6.6.tar.gz'
#8 150.1 Error in download.file(url, destfile, method, mode = "wb", ...) :
#8 150.1   cannot open URL 'https://cran.r-project.org/src/contrib/cli_3.6.6.tar.gz'
#8 150.1   URL 'https://cran.r-project.org/src/contrib/cli_3.6.6.tar.gz': status was 'SSL connect error'
#8 725.0   cannot open URL 'https://cran.r-project.org/src/contrib/dplyr_1.2.1.tar.gz'
#8 762.6   cannot open URL 'https://cran.r-project.org/src/contrib/globals_0.19.1.tar.gz'
#8 1158.2 ERROR: dependencies ‘cli’, ‘cowplot’, ‘dplyr’, ‘furrr’, ‘future’, ‘ggplot2’, ‘ggpubr’, ‘NMF’, ‘purrr’, ‘tidyr’ are not available for package ‘sigminer’                     (BUILD-EXIT=1)
```

Two root causes, both now recorded: (i) the `==version` spec **warns
instead of raising** when the pin lives only under `Archive/`, so
error-gated success is unsound — `ensure.pin` is now RESULT-gated:
provisioning counts only when `packageDescription` reports the pinned
version actually present in the library, else the build stops loudly;
(ii) the Archive-only class is NOT limited to the two item-4 pins —
remotes pins the whole era-consistent Import tree (cli 3.6.6, dplyr
1.2.1, globals 0.19.1, …), whose tarballs are absent from plain contrib
and whose fetches die with `status was 'SSL connect error'` through this
proxy. The next slice therefore needs an Archive-aware install path for
the ENTIRE tree — candidate direction:
`tools::install.packages("sigminer==2.3.1", contriburl = .../src/contrib,
archiveurl = .../src/contrib/Archive, dependencies = TRUE, type =
"source")` replacing the remotes step, keeping the two explicit
`ensure.pin` calls as belt-and-braces.

Verdict: BUILD-EXIT=1, no image exists (`docker image inspect
m7-sigminer:cr2.3.1` → `No such image`), registry entry stays
PENDING_VERIFY, sigminer cells stay AdapterUnavailable skips — gate text
verbatim: `image 'm7-sigminer:cr2.3.1' digest is 'PENDING-VERIFY' —
provenance not captured from 'docker image inspect' (inventing digests
is prohibited, memo §5 ii)`. No digest was invented this dispatch.

Closure gates (as run on this branch): `cd bench/m7 &&
python3 -m tests.run_all` → `12/12 tests passed.`; `cd bench/g0 &&
python3 -m tests.run_all` → `45/45 tests passed.`;
`python3 tools/ci-selfcheck.py` → `ci-selfcheck: PASS (all CI wiring
assertions hold)` (exit 0).

### 9c. Slice-2 image campaign (2026-10-08, follow-up dispatch): whole-tree Archive-aware closure

Base: origin/main @ `bcc1f31` (verified descendant of the §9b-closure
merge). Mission per §9b-closure's final paragraph: replace the two-
hand-pinned provisioning with an install path that resolves EVERY
transitive dependency of sigminer 2.3.1 through the CRAN contrib+Archive
trees, keep the recorded build-time asserts, one budgeted build attempt
plus at most two spares for NEW distinct defect classes.

**Ground-truth probes (containers off the mirror-spelled base, scratch
libs only; nothing installed into a real library).**

* Probe 1 — installer API surface: this base R (4.3.3)
  `install.packages` has NO `archiveurl` parameter, `remotes` is absent,
  `tools::install.packages` is absent, `compareVersion` is string-
  oriented, and the frozen `"pkg==ver"` spec is looked up VERBATIM AS A
  PACKAGE NAME — verbatim: `package 'sigminer==2.3.1' is not available
  for this version of R`. The §9b candidate direction
  (`tools::install.packages(..., archiveurl = ...)`) is therefore dead
  code here; the recorded result-gate semantics (a node counts as
  provisioned only when the library's own DESCRIPTION reports the
  version) become the design itself.
* Probe 2 — fetch/install matrix: `Archive/<pkg>/<pkg>_<ver>.tar.gz`
  (per-package dir) serves, the flat `Archive/<pkg>_<ver>.tar.gz` 404s
  on this CRAN; the contrib PACKAGES `File` column is NA; local-tarball
  `install.packages(tf, repos = NULL, type = "source")` installs and the
  library reports the version.
* Probe 3 — the master Archive index at `Archive/` exists (5,564,905 b,
  28,121 directory tokens) and carries canonical spellings; it proves
  that `maftools` and `Rhtslib` have NO directory on the Archive tree at
  all — neither case, neither layout. The two hand-pins were never going
  to cover the bioc-class Imports.
* Probe 5 — the bioc-class source of record:
  `https://bioconductor.org/packages/3.17/bioc/src/contrib/PACKAGES`
  serves (2,188 rows) and HITS both `maftools` and `Rhtslib`. This is
  the same release the recorded pre-hardening build compiled Rhtslib
  from (defect #2 above — the `-dev` header layer provisions exactly
  this class). Memo §5 governs image pulls; in-build package fetches
  follow the §8 G0 idiom.
* Probe 6 — the walk-failure class: the proxy flakiness (§9b item 1)
  404s LIVE Archive directories on first touch; `Archive/viridisLite/`
  (exact canonical case via the master index) lists 9 versions and its
  tarball fetches after retries.
* Probe 7 — `available.packages` on the bioc contrib dies on the
  rds-first read — verbatim: `URL '.../PACKAGES.rds': status was 'SSL
  connect error'` then `error reading from connection` — the server
  serves no PACKAGES.rds. The installer therefore parses raw
  PACKAGES(.gz) with its own DCF reader instead of trusting
  available.packages.

**Design (`bench/m7/adapters/install_sigminer.R`, COPY'd into the image —
the quoted-`Rscript -e` one-liner and its swallowed-newline hazard class
retired with it).** BFS over the transitive graph from the
`sigminer==2.3.1` root; per node: contrib-db current + the constraint as
fetch candidates (dual-repo PACKAGES db: CRAN first for era fidelity,
bioc 3.17 last), four URL shapes per candidate
(`contrib/P_V.tar.gz` → `Archive/P/P_V.tar.gz` → `Archive/P_V.tar.gz` →
`bioc-contrib/P_V.tar.gz`), name-case candidates
[db-canonical | master-index alias | as-written | lowercase |
capitalized], MAX_TRY retries per URL, `rSatisfies` gate rejecting any
tarball whose DESCRIPTION `Needs R` exceeds the base (live capture this
campaign: `reject Deriv 4.3.5 (Needs-R exceeds base 4.3.3)` — the walk
then accepts the 4.1-line release), the Archive per-package listing walk
with master-index canonical discovery as last resort, then a topological
install pass where EVERY success is result-gated on the library's own
DESCRIPTION (via `install.packages`' return CODE — absence of an
exception is not success, spare-1 lesson). Before anything installs, a
**joint-consistency audit** (CONSIST) recomputes every hard-Imports
constraint across the settled graph and repairs the unjustified side:
per-node resolution soundness is necessary but not sufficient (the
cowplot 1.2.0 / ggplot2 3.3.0 class, ledger below). The two belt-and-braces pins (rbibutils 2.4.1, gridBase
0.4-7) are kept and re-probed through the same path; the recorded tail
asserts (`packageVersion('sigminer')=='2.3.1'` exact + the five
documented exports) are preserved verbatim.

**Pre-flight.** `Rscript install_sigminer.R --dry-run` in the base
container resolved the FULL graph — verbatim: `DRY-RUN graph complete: 92
installable node(s): sigminer cli cowplot data.table dplyr furrr future
ggplot2 ggpubr maftools magrittr nmf purrr rcpp rlang tidyr gtable scales
generics glue lifecycle pillar r6 tibble tidyselect vctrs globals digest
listenv parallelly isoband s7 withr ggrepel ggsci ggsignif gridextra
polynom rstatix rcolorbrewer rhtslib dnacopy zlibbioc registry rngtools
stringr gridbase colorspace foreach doparallel reshape2 biobase
biocmanager cpp11 farver labeling viridislite utf8 pkgconfig broom
corrplot car stringi iterators plyr biocgenerics backports cardata abind
formula pbkrtest quantreg lme4 numderiv doby sparsem matrixmodels rdpack
minqa nloptr reformulas rcppeigen deriv forecast modelr rbibutils
fracdiff lmtest timedate urca zoo rcpparmadillo` — exit 0, no install.

**Build ledger.** Attempt tails verbatim.

* **attempt-1** — `/tmp/m7_sigminer_build4.log`, `BUILD-EXIT=1`,
  installer FATAL at t≈2118 s on the `Biobase` node — verbatim:

  ```
  #9 2118.1 FATAL:node Biobase ( ): candidates [2.60.0] failed and no Archive listing usable — 2.60.0: unresolvable Biobase 2.60.0 (last: ERR:cannot open URL 'https://bioconductor.org/packages/3.17/bioc/src/contrib/biobase_2.60.0.tar.gz'); attempted: https://cran.r-project.org/src/contrib/Biobase_2.60.0.tar.gz -> ERR:cannot open URL '...Biobase_2.60.0.tar.gz' | https://cran.r-project.org/src/contrib/Archive/Biobase/Biobase_2.60.0.tar.gz -> ERR:... | https://cran.r-project.org/src/contrib/Archive/Biobase_2.60.0.tar.gz -> ERR:... | https://bioconductor.org/packages/3.17/bioc/src/contrib/Biobase_2.60.0.tar.gz -> ERR:... | https://cran.r-project.org/src/contrib/biobase_2.60.0.tar.gz -> ERR:... | https://cran.r-project.org/src/contrib/Archive/biobase/biobase_2.60.0.tar.gz -> ERR:... | https://cran.r-project.org/src/contrib/Archive/biobase_2.60.0.tar.gz -> ERR:... | https://bioconductor.org/packages/3.17/bioc/src/contrib/biobase_2.60.0.tar.gz -> ERR:...
  ```

  (The `ERR:...` elisions repeat the identical verbatim tail
  `ERR:cannot open URL '<the shown URL>'` per shape — all eight shapes,
  both spellings, every host.)

* **Classification.** All eight URL shapes returned `cannot open URL`,
  including the exact bioc URL that the host dry-run 4 had resolved
  successfully ~30 min earlier. Probe 8 quantified the same endpoints
  (`/tmp/m7_probe8.log`): `FLAKY Biobase_2.60.0.tar.gz ok=7 fail=3`,
  `FLAKY DNAcopy_1.74.1.tar.gz ok=6 fail=4`,
  `FLAKY zlibbioc_1.46.0.tar.gz ok=10 fail=0` — the §9b-item-1 recorded
  intermittent-proxy class: the URLs are good, the transport is not. The
  defect fixed here is the installer's own fragility to that recorded
  class (3 tries per URL, no deferral → an unlucky flake streak kills
  the build): an installer-side FATAL masquerading as an unresolvable
  node.

* **Hardening before spare-1.** `isTransientStatus` separates the
  deterministic 404/403 class (break immediately) from the transient
  class (SSL / timeout / 5xx / empty-reply / bare `cannot open URL`,
  retried with linear backoff); the transient flag propagates onto
  `resolveNode` failure records; the BFS defers transient node failures
  and requeues them (`MAX_DEFER = 2` rounds); Archive pins get their own
  deferral rounds (`PIN_ROUNDS = 3`); PACKAGES metadata fetches are
  retried (≤3 whole refetches). Re-preflight on the host: dry-run 5 —
  `DRY-RUN graph complete: 92 installable node(s)`, exit 0, zero DEFER
  lines required.

* **spare-1** — `/tmp/m7_sigminer_build5.log`, `BUILD-EXIT=1` — the
  resolve phase went fully green (92 nodes, zero DEFER; every
  recorded-class blocker proven passable, bioc layer included — 53
  INSTALL-OK lines followed). The terminal record:

  ```
  #9 3738.8 INSTALL ggplot2        3.3.0 OK
  #9 3739.2 FATAL:install failed for cowplot 1.2.0: OK (library reports (none))
  #9 ERROR: process "/bin/sh -c Rscript /tmp/install_sigminer.R" did not complete successfully: exit code: 1
  ```

* **Classification (spare-1): NEW distinct class — joint hard-dep
  inconsistency.** Host-side root-cause capture (outside the build, per
  decisive-shot discipline): sigminer 2.3.1 imports `cowplot` **bare**
  and `ggplot2 (>= 3.3.0)`, so the BFS settled cowplot at contrib-current
  **1.2.0** (2025) while ggplot2 fell to the era-want candidate **3.3.0**
  (a flaky-proxy artifact of the candidate order, not a policy). cowplot
  1.2.0's own DESCRIPTION demands `Imports: ggplot2 (>= 3.5.2)` —
  per-node resolutions were individually sound but not **jointly** sound.
  `install.packages` (`repos=NULL`) enforces exactly this and reports the
  failure through its **return code**, not an exception — the gate's
  quiet-mode "no exception ⇒ OK" printed the dishonest `: OK` above.
  Distinct from every recorded class (all prior fatals were resolve-phase
  transport/metadata or apt/shell).

* **Repair (three parts, `install_sigminer.R`).** (1) A
  **joint-consistency audit** between BFS and install: constraints are
  collected from every settled node's hard Imports; a violation repairs by
  moving the UNJUSTIFIED side (a pin equal to some requester's explicit
  want is era-sacred; an unconstrained contrib-default floats back
  through the Archive until its imports agree), with the tie resolved by
  raising the dependency to the tightest joint bound — bounded 3 rounds,
  honest die with the verbatim violation otherwise. (2) install status is
  now read from `install.packages`' **return code**, never from absence of
  an exception. (3) A failed install is **replayed without quiet** so the
  R CMD INSTALL error text reaches the build log (the record `quiet=TRUE`
  buried). Verification before the final spare: forced-mutant host dry-run
  (`/tmp/m7_dryrun_force.log`) pinned ggplot2 to the pathological 3.3.0
  and the audit healed it verbatim — `CONSIST ggplot2 3.3.0 breaks
  (ggplot2 >= 3.5.2) from cowplot — dep-justified=TRUE
  demander-justified=TRUE` → `CONSIST raise ggplot2 3.3.0 -> 4.0.2
  (joint bound >= 3.5.2)` → `CONSIST graph jointly consistent (round 2)`
  → graph complete, exit 0; the natural-state dry-run 6 was already
  jointly consistent (zero DEFER, zero CONSIST needed, exit 0); the
  Archive fallback candidate `cowplot_1.1.1` DESCRIPTION was host-verified
  jointly satisfiable (`Imports: ggplot2 (> 2.2.1)` + bare others,
  `NeedsCompilation: no`).

* **spare-2 (FINAL, 2/2)** — `/tmp/m7_sigminer_build6.log`,
  `BUILD-EXIT=1` — the budget's last expedition attempt. The resolve
  phase went fully green under the hardened installer: **111 RESOLVEs,
  zero DEFER, zero CONSIST** (cowplot 1.2.0 paired naturally with
  ggplot2 4.0.3 — the graph arrived jointly consistent, the audit had
  nothing to repair), one Archive walk. The death was the very first
  install node:

  ```
  #9 418.4   install failed cli 3.6.6 (STATUS:NA, library reports 3.6.6) — replaying visibly
  #9 425.1 FATAL:install failed for cli 3.6.6: STATUS:NA (library reports 3.6.6)
  BUILD-EXIT=1
  ```

  The visible replay — the spare-1 repair part (3) doing its job — is
  the self-indictment: R CMD INSTALL ran the *same tarball* end-to-end
  and succeeded while the gate judged it failed:

  ```
  #9 418.7 * installing *source* package ‘cli’ ...
  #9 425.1 * DONE (cli)
  #9 425.1 FATAL:install failed for cli 3.6.6: STATUS:NA (library reports 3.6.6)
  ```

* **Classification (spare-2): INSTRUMENTATION class — the diagnostic
  layer itself, not the dependency graph.** The spare-1 repair part (2)
  read `install.packages`' *return code* — but the deparse of
  `tools::install.packages` (base R 4.3.3, host-captured) shows the
  success path is `return(invisible())` — **NULL** — and a failed
  `R CMD INSTALL` surfaces only as the warning
  `installation of package %s had non-zero exit status` (the
  `status > 0L` branch); the function has neither an exception path nor
  a status return for the install itself. `as.integer(unlist(NULL))` →
  `integer(0)` → the non-empty check failed → `STATUS:NA` false-reject
  on a library-confirmed-good install. Both generations of the gate
  read channels this R does not have; the warning is the real channel.
  This class was discovered only at the death itself and is absent from
  every recorded class at launch time, so its consumption of the final
  spare is the ledger's honest accounting, not an overrun.

* **Controller budget ruling (governs the build-budget domain; issued
  2026-10-08 upon the spare-2 classification).** Key conditions
  verbatim: *“(1) fix scope is ONLY the STATUS-capture path; first
  establish ground truth with a host probe in the base image: what does
  tools::install.packages (R 4.3.3) actually return for a known-good
  install and a forced-fail install — build the truth table, then map
  it (your quiet-mode trust heuristic returns, but as an explicit
  table-driven verdict with the replay path as witness, never as
  silent trust); (2) resolver, CONSIST audit, Archive logic, pins: ZERO
  changes — any diff outside the status/verdict path voids the
  exception and I will halt the campaign myself; (3) RATCHET: if
  build7 dies by ANY signature that is not the status/verdict path
  itself — network FATAL, unresolvable node, real compile failure,
  audit non-convergence, DEFER — the campaign closes to the §9c
  honest-partial ledger IMMEDIATELY, no further discussion, no further
  exceptions, ever; (4) The ruling itself goes verbatim into §9c as
  controller-approved instrumentation-exception 1-of-1.”*

* **Truth table (condition 1) — captured host-side in the base image
  before the build, against the real `tools::install.packages`:**

  ```
  PROBE expect=OK        m7knowngood  0.0.1 status=OK    library=0.0.1
  PROBE expect=FAIL      m7forcebreak 0.0.1 status=WARN:installation of package ... had non-zero exit status library=NA
  TRUTH-TABLE-DONE
  ```

  success = NULL return, no warning, library reports version → verdict
  `OK`; failure = the `non-zero exit status` warning fires (no
  exception ever) → verdict `WARN:<verbatim>`, and the library gate
  independently reports `(none)`. The shipped gate maps exactly this
  table — warning-capture handler (`grepl` fixed-match,
  `invokeRestart("muffleWarning")`), explicit verdict strings, the
  visible replay retained as witness, the library DESCRIPTION as final
  say. Conformance to condition 2: `install_sigminer.R` (untracked-new
  for this slice) received exactly one edit since build6 terminated —
  the `installTarball` status/verdict block; resolver/CONSIST/Archive/
  pins byte-identical, re-confirmed by buildkit's own cache key
  (`COPY install_sigminer.R CACHED` while the pre-change layers replayed).

* **build7 (controller-authorized instrumentation exception, 1-of-1,
  one-way ratchet per the ruling above).** Launch had host-side
  operational turbulence with zero expedition content, recorded for
  honesty: the background task table mislabeled the wrapper command and
  the first non-interactive launches died `BUILD-EXIT=127` (bare
  `docker` off the non-login PATH — pinned
  `/usr/local/bin/docker` thereafter), leaving two orphaned server-side
  buildkit sessions (buildkit does not cancel on client kill) that the
  single authorized client then rode via shared-cache step dedup. All
  sessions carried byte-identical installer content (COPY cache hit),
  so the artifact remains exactly the authorized recipe; the
  wrapper-owned `BUILD-EXIT` line plus a post-hoc live-container
  re-assert of the §9c tail (version + five exports, run outside the
  build) are the verification witnesses, independent of which session
  solved the step. Pre-authorized risk probe outside the build: base
  image carries the Fortran toolchain (`/usr/bin/gfortran`, `FLIBS =
  -lgfortran -lm`), provisioning the quantreg/car-chain compile class.
  Terminal record (VERBATIM, from the wrapper-owned `/tmp/m7_sigminer_build7.log`,
  CR-cleaned witness `/tmp/m7_build7_clean.txt`):

  ```
  #9 1115.3 INSTALL sigminer       2.3.1 OK
  #9 1115.3 PIN rbibutils      2.4.1 already exact
  #9 1115.3 PIN gridBase       0.4-7 already exact
  #9 1116.4 FATAL:documented sigminer export missing: signature_extract
  #9 ERROR: process "/bin/sh -c Rscript /tmp/install_sigminer.R" did not
        complete successfully: exit code: 1
  BUILD-EXIT=1
  ```

  Terminal state: the whole-tree install completed (`92` distinct
  `INSTALL ... OK` nodes — `96` raw lines including `4` re-emission
  duplicates of car/rstatix/ggpubr/sigminer from the orphan-session
  ride), then the build-time documented-exports guard died `1.1 s`
  after `INSTALL sigminer 2.3.1 OK`, at layer-time `1116.4 s`.
  This death signature is the guard enforcing a documented-exports
  contract, **not** the status/verdict path — the ruling's condition-3
  ratchet therefore fired: campaign closed to the honest-partial
  ledger, zero further builds, no guard edits in-slice (see 9c.2 for
  the controller adjudication verbatim and the forensic fact-check).

## 9c.1 Verdict record — budget exhaustion and the forward-leap ledger

The dispatch budget is fully spent: recorded recipe 0/1 (retired
non-viable on established contract facts, §9c pre-flight), attempt-1
(build4) and spares-1/2 (build5/build6) consumed by three **distinct**
defect classes discovered only at each death — transport-flake, joint
hard-dep inconsistency, and the instrumentation/status-capture class —
each root-caused and closed with host-side evidence, never by retry
pounding. Registry stays `PENDING-VERIFY` (no digest was ever invented;
`test_registry.py` was never touched outside its data values because
the image did not yet exist).

**The forward-leap ledger** — what the campaign proved passable, so the
next dispatch spends one build, not six:

1. **Resolve layer: complete.** 111/111 nodes resolve through
   contrib → per-pkg Archive → flat Archive (+listing walk, master-
   index canonicalization) → pinned bioc 3.17 contrib, with zero DEFER
   and a naturally CONSIST-clean graph (build6). The flakiness class is
   absorbed by retry/deferral (probe8: package-URL flakiness is
   intermittent, not permanent; 502-class transient recovery observed
   live in build7 at isoband, DEFER → re-queue → OK).
2. **Install layer: full tree proven end-to-end.** build5 established
   `53` nodes verbatim (the tidyverse/ggplot support spine —
   cli/data.table/Rcpp/rlang/vctrs/purrr/future/furrr/tibble/dplyr/
   ggplot2-family incl. isoband/farver/labeling/viridislite/scales/
   utf8/pillar; the bioc load-bearing layer — DNAcopy/zlibbioc/
   **Rhtslib 2.2.0, the named historical blocker**/maftools 2.16.0/
   BiocManager/cpp11; the NMF support group; rbibutils 2.4.1 under the
   recorded libcurl4-openssl-dev pin). **build7 closed the remainder:
   `92` distinct `INSTALL ... OK` nodes — the complete installable
   tree, the forecast chain (modelr/Deriv/fracdiff/lmtest/timeDate/
   urca/zoo/RcppArmadillo), stringi (ICU), quantreg, ggpubr, and
   sigminer 2.3.1 itself** (`INSTALL sigminer 2.3.1 OK` verbatim at
   `#9 1115.3`). The installation science is DONE; what stopped the
   build is the guard's export contract, adjudicated in 9c.2.
3. **Compile surface: provisioned.** apt layer carries cmake + the
   -dev quartet (zlib/bz2/lzma/curl-openssl); Fortran present
   (`FLIBS=-lgfortran -lm`) for the car→quantreg chain.
4. **The status/verdict gate now matches base-R reality** (truth table
   above): it cannot again print the `: OK` lie (spare-1), and it
   cannot again false-reject a library-confirmed install on a NULL
   return (spare-2).

Five documented-export asserts and the exact-version pin remain the
build's terminal gate, unchanged since dispatch — but the forensic
adjudication below establishes the export list itself is defective for
the pinned artifact, AND the merged adapter shares the same call-site
fiction (controller addendum, 9c.2), so the slice-3 charter EXPANDS
from "guard-contract fix" to the full **adapter API realignment to the
`sig_*` family (call sites + asserts + NMF sequence) under a NEW
controller-authorized budget** — not another build of this recipe.
When that slice's build closes green, the flip
ceremony is fixed: live
`docker image inspect --format '{{.Id}}'` on the tag → registry.py
data-only flip (inspect line in the commit body) → gates 1-4 → smoke
cell proves the adapter clears the image gate.

## 9c.2 Ratchet close-out — controller adjudication and the zero-build fact-check

**Controller adjudication (verbatim, effective at the build7 terminal):**
"RATCHET TRIGGERED — controller adjudication, effective now. Your
build7 verbatim terminal: `FATAL:documented sigminer export missing:
signature_extract` / BUILD-EXIT=1 at layer-time 1116s, after ~96
INSTALL-OK (the FULL installable tree completed — the installation
science is DONE). This death signature is the build-guard enforcing a
documented-exports contract on the installed sigminer 2.3.1 — it is
NOT the status/verdict path; per my ruling's condition-3 this closes
the campaign: ZERO further builds in slice-2, no guard edits in-slice,
no discretion." Close-out lanes per the same dispatch: (a) this
honest-partial ledger; (b) one zero-build host-side fact-check;
(c) registry stays PENDING_VERIFY; (d) gates 1-3 green, push, report —
the follow-up guard-contract correction is a NEW slice, not this one
continuing.

**The fact-check (zero build cost; host-side fetch of the exact
Archive tarball the build log recorded).** Source:
`https://cran.r-project.org/src/contrib/Archive/sigminer/sigminer_2.3.1.tar.gz`,
sha256 `b2836c76a52f7c7add8756afb09dc50ab31d736b4640b803bee57b6caec1953b`,
`4,153,108` bytes, unpacked host-side (never in any build).

* **NAMESPACE verbatim:** `115` `export()` stanzas (slice-3 erratum: this
  line originally read `108` and listed `sig_import` among the real API —
  both wrong; the full-tarball re-count on 2026-10-08 evening gives
  `115` — the controller's independent local grep had already reported
  `115` — and `sig_import` occurs `0` times in the witness; corrected
  against the bytes, ledger-struck not silently rewritten);
  **`0` of the `5` guard names**
  (`set.seed`, `signature_extract`, `fitsignatures`, `signature_import`,
  `signature_renorm`) present; the package's real API is the
  `sig_*`/`bp_*` family (`sig_extract`, `sig_fit`, `sig_fit_bootstrap`,
  `sig_estimate`, `bp_extract_signatures`, …) — the names the slice-3
  realignment drives.
* **Version sweep rules out a lineage drift inside CRAN:** `1.2.5` →
  `0/5`; `0.1.11` (the 2021 paper-era release) → `0/5`, `sig_*` from
  inception; local ground truth `2.3.3` → `0/5`; tree-wide greps for
  all five names across the sources return zero; the local repo's
  `git -S` pickaxe history for the names is empty.
* **bioc excluded:** the pinned Bioconductor 3.17 contrib `PACKAGES`
  index contains no `sigminer` package at all, so no bioc variant
  could have supplied the names.
* **Internal provenance of the defective list:** the guard mirrors
  `run_sigminer.R` verbatim — its header comment claims "the documented
  API of CRAN sigminer 2.3.1 (signature_extract / fitsignatures /
  signature_import / signature_renorm / set.seed)" (lines 17-18), its
  line 54 runs the same five-name assert loop, and its call sites
  (`signature_extract(signature = list(counts = ...),` line 76;
  `fitsignatures(de_novo_signatures = ...)` line 87) would equally not
  resolve — the same false premise infects both files. That file is
  GREEN-slice authorship, out of this slice's scope.
* **External lineage candidate (UNCONFIRMED lead):** the package's own
  DESCRIPTION quotes "Steele Christopher D., et al. (2022)
  <DOI:10.1038/s41586-022-04738-6>" — the Dunedin SigMiner suite whose
  published API uses the `signature_*` verb names — the most plausible
  source of the confusion. Verbatim external confirmation was NOT
  obtainable with this network's tooling (GitHub repo/raw fetches
  returned `404` for the candidate org paths; the docs host
  `sigminer.dunedin.scot` presents a TLS hostname-mismatch — its
  certificate covers only `dunedin.scot`/`www.dunedin.scot`; the web
  search provider returned unrelated results for every phrasing;
  crossref fuzzy matching missed the paper). Recorded as a lead, not a
  fact.

**Adjudication of the three proposed branches:** (i) *package genuinely
lacks `signature_extract`* — **TRUE and complete**: absent from every
CRAN sigminer version ever published, tree-wide, with empty pickaxe
history. (ii) *guard input list defective* — **TRUE by consequence**
for the pinned artifact: the guard (and its `run_sigminer.R` source of
provenance) asserts an API that exists in no sigminer version; the
correct build-time export contract must name the `sig_*` family (or
drop the export assert and keep the exact-version pin), which is the
follow-up slice's charter. (iii) *list sourced from a different
lineage* — **plausible, unconfirmed**: the Dunedin suite (Steele 2022,
cited in the package's own DESCRIPTION) is the best candidate; external
verbatim evidence blocked by the network conditions above.

**Controller addendum to the close-out (verbatim, physically
re-verified by the controller before PR #11).**

* Witnessed confirmation of the ledger: "I independently confirmed with
  my own grep: local ground-truth NAMESPACE = `115` export() lines,
  ALL FIVE guard names = `0` occurrences; real API present
  (`sig_extract`, `sig_fit`, `sig_fit_bootstrap`, `sig_estimate`,
  `bp_extract_signatures`). Your three-branch adjudication stands
  confirmed."
* New finding for the ledger (the file itself stays untouched — out of
  scope this slice): "the same false premise infects the MERGED adapter
  `bench/m7/adapters/run_sigminer.R` — header L17-18 'documented API',
  assert loop L54, AND live call sites L76
  `signature_extract(signature=list(counts=...))` / L87
  `fitsignatures(de_novo_signatures=...)` which could never resolve
  against CRAN sigminer. Record verbatim: the image-build guard was
  not the only carrier; the green-slice adapter itself is
  call-site-fictional, so even a green image+digest would NOT have
  made sigminer cells scientifically executable — the frozen registry
  PENDING-VERIFY gate is what contained this. Consequence: slice-3
  charter EXPANDS from 'guard-contract fix' to 'adapter API realignment
  to the `sig_*` family (call sites + asserts + NMF sequence) under new
  controller-authorized budget'. No code change to `run_sigminer.R` in
  this slice."
* Lineage-lead correction, kept **UNCONFIRMED** (lead, not fact): the
  DESCRIPTION-cited Steele 2022 DOI, as literally recorded in the
  tarball, reads `10.1038/s41586-022-04738-6` — malformed against the
  Nature Methods DOI pattern (`10.1038/s415xx-YYYY-N…`), so even the
  citation string cannot anchor the external witness. `TODO(paper)`:
  pin the correct DOI for the Steele et al 2022 SigMiner paper in
  slice-3.

## 9d. Slice-3 — adapter API realignment to the witnessed `sig_*`/`bp_*` family

Dispatch (controller, post-PR-#11): base `origin/main = 00491db`; charter =
(1) `run_sigminer.R` realignment killing the false premise, (2) build-guard
fix to the real NAMESPACE contract, (3) TDD with zero weakening of the
frozen 48/45, (4) expedition budget 2 max with controller-gated launch,
(5) digest flip ONLY on green build (not yet reached), (6) `TODO(paper)`,
(7) this ledger + gates + push proof.

### 9d.1 Realigned call surface (charter 1)

`run_sigminer.R` now drives the package's documented best-practice
extraction chain — the one its own vignette teaches — at documented
defaults: `bp_extract_signatures(catalog, seed = seed)` (the single
forwarded argument; the package docstring calls `seed` "a random seed to
make reproducible result", so §3's one-lever seed discipline is preserved
and the fictional "package-documented seed entry point" claim is dead —
the witnessed NAMESPACE carries that name 0 times) → `bp_get_sig_obj(e1,
e1$suggested)` (the extraction result's own suggested rank, no threshold
override) → `sig_exposure(obj, type = "absolute")`. Input orientation is
the witnessed sample-by-component catalogue contract (the package's own
`send_info("NOTE: the input should be a sample-by-component matrix.")`).
The `--catalog` mount stays protocol-carried but is NOT consumed by the
de-novo cell — reference matching is the scoring-side `get_sig_similarity`
job (§4), never an extraction lever. Interval honesty follows the
`run_sigprofiler.py` house convention: the chain reports point exposures
and no bounds, so `lo95/hi95` are written as `NaN`, never masquerading as
zero-width (the fictional chain had duplicated the estimate into both
bounds — itself an honesty violation the realignment removes). Pin guard
mirrors the build: exact `2.3.1` + `CORE_API` function presence.

### 9d.2 Build-guard fix (charter 2)

`install_sigminer.R`: the fictional five-name `DOCUMENTED_EXPORTS` gate is
retired (with this ledger as its grave marker). The tail gate now reads
the verbatim `export()` contract **out of the resolver's own downloaded
tarball bytes** — `INSTALLED_TF` stashes each installed node's tarball,
`untar(tf, files = "sigminer/NAMESPACE")` extracts the witness member, a
sha256 tripwire (`NS_SHA256`, value recorded §9c.2) must match before any
trust, then every witnessed export must resolve in the installed
namespace and the `CORE_API` family must resolve *as functions*. No
second copy of the list to drift, no refetch, no build-context change.

Two latent defects caught by the pre-flight, both live on the build base
(zero build dollars spent): base R **4.3.3 has no `digest()`** (that
merge landed in 4.4.0; probe printed "could not find function digest") —
the first hash implementation would have died in the build; and
`system2(stdout=TRUE, stderr=TRUE)` returns an ATOMIC vector under
Rscript (no `$status`), so the hash channel uses the deterministic
file-redirect form returning the integer exit status. Pre-flight verdict
on `r-ver:4.3.3`, witnessed tarball mounted read-only:
`PREFLIGHT-TAIL-OK: 115 witnessed exports, hash verified, core covered`.

### 9d.3 Runner API-form smoke (host-side, real package semantics)

`preflight_runner.R` replicated the shipped chain against the
host-installed sigminer (2.3.3 — FORM check; the cell pins 2.3.1 and the
bytes are exercised by the budgeted build): 3-sample × 96-channel
simulated catalogue from two planted profiles →
`PREFLIGHT-RUNNER-OK: 3 samples x 2 signatures = 6 rows;
labels[Sig1,Sig2]`, suggested rank `2` = the planted truth. The real
chain runs end-to-end with exactly the shipped call shapes.

### 9d.4 TDD evidence (charter 3)

New module `tests/test_sigminer_api_contract.py` (registered in
`run_all.py`, group ⑪), 7 units, contract fixture
`tests/fixtures/sigminer_2.3.1_namespace_exports.txt` = the verbatim
`export()` stanza of the witnessed NAMESPACE (sha256
`2168cf32059f09c2e12cf3f82cb9befc9b15a58883c92fa3473c462671927948`,
`115` lines; full-NAMESPACE-bytes hash `37744aee…6a90df` shared with the
build guard). RED first, verbatim: `54/55 … FAILED:
test_sigminer_api_contract.test_installer_guard_verifies_from_the_fetched_witness`
with the five fiction-pinning units failing against the fictional chain
(earlier RED state: `50/55`, 5 contract failures, old 48 green
throughout). GREEN: `55/55 tests passed.` — old 48 zero-weakened (the
frozen g0 `45/45` untouched: `45/45 tests passed.`), `ci-selfcheck:
PASS (all CI wiring assertions hold)` exit 0. Units pin: fixture↔witness
hash identity, fiction eradicated chain-wide (`run_sigminer.R` /
`install_sigminer.R` / `sigminer_adapter.py`), every `sig_*`/`bp_*`
runner call site witnessed, guard reads the fetched-bytes contract behind
the hash tripwire, guard/runner `CORE_API` cannot drift apart, exact pins
survive, NaN-never-zero-width intervals, seed flows only through the
documented parameter.

### 9d.5 `TODO(paper)` — attempt and honest negative result (charter 6)

The malformed as-recorded citation `10.1038/s41586-022-04738-6` stays
verbatim above (9c.2). Attempted pins this slice: crossref via the search
backend returned only fuzzy-match noise; a remembered candidate DOI
`10.1038/s41592-022-00995-8` died at the resolver with **404** (never
written anywhere as fact); the crossref REST API answers but this network
demonstrably rewrites identifiers at digit level (response bodies carry
impossible DOI/journal-name mutations), so **no verifiable DOI witness is
obtainable from this network** — any pinned value would be invented, which
policy prohibits. `TODO(paper)` REMAINS OPEN with these negative results
recorded; the malformed string's shape suggests it is itself an artifact
of the same rewrite class applied upstream at publication time.

### 9d.6 Budget and gate state at report time

Expedition budget: `0/2` consumed — zero builds spent; controller gates
the launch (dispatch: report TDD evidence + guard/fixture proposal first).
Registry `sigminer` entry: `PENDING-VERIFY` — untouched, per charter 5 the
flip is reserved for the live `docker image inspect .Id` on a green build
(the §9c.1 flip ceremony stands unchanged).

### 9d.7 build8 death — guard-quoting forensics, controller ruling, the preflight-gate discipline

**Death (verbatim, log /tmp/m7_sigminer_build8.log, expedition attempt 1/2).**
Full replay ran clean — hash tripwire passed (no drift die), 96 INSTALL-OK
lines, 92 RESOLVE-via — then the new tail assert stopped the build:

    #9 1284.7 INSTALL sigminer       2.3.1 OK
    #9 1284.7 PIN rbibutils      2.4.1 already exact
    #9 1284.7 PIN gridBase       0.4-7 already exact
    #9 1285.3 FATAL:witnessed sigminer export missing: "%>%"
    #9 ERROR: process "/bin/sh -c Rscript /tmp/install_sigminer.R" did not complete successfully: exit code: 1
    ERROR: failed to build: failed to solve: ... exit code: 1

**Forensics (agent, zero build cost).** The die site is the guard, not the
artifact. The NAMESPACE grammar quotes non-syntactic export names and the
witnessed bytes carry exactly two quoted stanzas — export("%>%") and
export(":=") — so the stanza capture (install_sigminer.R L820) folded the
grammar quotes INTO the lookup name, while exists() resolves BINDING names:
a quote-embedded lookup can never resolve. The FATAL line itself is the
proof — the %s wrap in die() adds no quotes, so the displayed "%>%"
carries the folded-in double-quotes. Host repro /tmp/m7_dl/repro_dequote.R
(exit 0): %in% and <- resolve clean on baseenv (TRUE) while their
quote-embedded forms never do (FALSE); the live host sigminer namespace
answers TRUE only to the clean operator names. Artifact exonerated:
2.3.1 exact, 96 nodes install OK, namespace loads, and ALL 115 witnessed
names resolve under clean lookup.

**Controller ruling (verbatim, 2026-10-08, corroborated by the
controller's own physical re-verification rather than agent attestation):**
"RULING REAFFIRMED ... instrumentation-class CONFIRMED. Controller
evidence: m7 suite re-run in your worktree = 56/56 PASS incl. your new
operator-stanza unit; L831 dequote verified positioned before length-guard
L832/exists-loop L834; witnessed bytes L8-9 = export("%>%")/export(":=")
confirmed; host probe: clean := TRUE/quoted FALSE, clean %>% TRUE/quoted
FALSE; preflight_tail2 re-invoked by me both modes — HOST: 'full-set
exists() misses vs host ns (2.3.1): 0', CORE_API 9/9,
PREFLIGHT-TAIL2-HOST-OK; CONTAINER (rocker/r-ver:4.3.3 via mirror, the
build engine): quote-embedded remaining: 0, PREFLIGHT-TAIL2-CONTAINER-OK
EXIT=0. Preflight gate SATISFIED by controller hand." Per the standing
build-budget policy the one-use instrumentation-class exception is hereby
spent on build9 (the authorized reserve).

**Fix (rides with this ledger).** One normalization statement in the tail
assert between the stanza parse and the resolve loop: each parsed name
loses one pair of surrounding double-quotes or back-ticks before exists()
resolution (verbatim expression in the installer's tail block; plain
syntactic names pass through untouched). The witnessed fixture stays
byte-pinned — dequoting belongs to the consuming guard, never to the
witness.

**Regression unit (TDD).** test_sigminer_api_contract gains
test_guard_resolves_operator_stanzas_dequoted pinning (a) the two quoted
stanzas verbatim inside the fixture, (b) the normalization strictly before
the exists() loop, (c) the algorithm over the fixture bytes: 115 clean
names, zero quote-embedded, operators and CORE_API present. RED 55/56
(exactly the new unit) then GREEN 56/56; g0 frozen 45/45;
tools/ci-selfcheck.py PASS exit 0; protected scope vs origin/main empty.

**Preflight-gate discipline (campaign lesson, ratcheted).** build8's guard
line executed for the FIRST time inside the build — the same blind-spot
class that the slice-2 digest()/system2 pre-flight catches defused, one
budget dollar more expensive. Standing rule: no build dollar without a
host-side preflight that EXECUTES the shipped bytes, not a hand-rewritten
mirror. /tmp/m7_dl/preflight_tail2.R pulls the installer's own parse and
dequote statements out of install_sigminer.R, evaluates them over the
witnessed NAMESPACE bytes, hashes via the shipped coreutils channel, and
in host mode runs the full 115-name exists() resolve loop against the
live installed namespace (misses=0 at 2.3.1, CORE_API 9/9). Both modes
passed pre-launch; the controller re-invoked both hands independently.

**Budget state at build9 launch.** build8 = 1/2 spent (instrumentation-
class, ruled). build9 launches at 2/2 — BUDGET EXHAUSTED AT LAUNCH: any
FATAL/ERROR ⇒ honest-partial close per dispatch (4), registry stays
PENDING-VERIFY, no exceptions ever again. Expected green terminal: replay
→ ASSERT sigminer 2.3.1 exact + 115 witnessed exports present (9 core
functions) → naming/writing-image/exporting-layers → DONE; the digest
flip then follows the §9c.1 ceremony as its own gated step (the controller
holds the data-only registry/test-pin flip commit until the live inspect
bytes land in the report).

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

## 11. Addendum — the scoring slice (benchmark table + scoring verdicts)

Dispatch U-M7-02 follow-on (same PR line, later commit): turn the harness
from fairness attestation into the paper's benchmark-table generator. The
fairness half is untouched in spirit and bytes; scoring is a pure consumer.

**Module layout (bench/m7/scoring/).** `match.py` (Hungarian assignment +
cosine kernel), `metrics.py` (P/R/F1 + exposure-error conventions),
`truth.py` (seed-derived ground truth via read-only `g0.sim.truth_composition`),
`cells.py` (cell discovery + prediction-table loading against the run path's
own `GUARD_FILES`), `run_products.py` (the one score pass; CSV + verdict
emission), `judgment.py` (the appended verdict half). Entry: `run_bench.py`
gains exactly one call site on the final (non-`--shard-tag`) pass;
`run_products.emit()` writes `benchmark_m7_<ts>.csv` into the authoritative
outdir and appends the verdict sections to the judgment document.

**Match-tolerance decision.** `MATCH_MIN_COSINE = 0.85` — the **midpoint** of
the frozen 0.80–0.90 sweep band (ARCHITECTURE §8 / benchmark memo 2026-10-05
§3). The primary table must fix one operating point so the headline number is
never swept post-hoc; the sweep lives on as the robustness appendix. The band
is a protocol fact, not a tuned value, so the midpoint is the least-chosen
choice. TODO(paper): pin the citation for the band with its source ref.
Below-tolerance pairs are *rejected* (gate, not weight) and fall out FP/FN.

**Frozen measurement conventions** (each pinned by tests): per-cell P/R/F1 is
the mean over samples; `arm_rollup`/`n_rollup` pool TP/FP/FN **then** derive
(a low-N tail cannot outvote volume by averaging); exposure errors exist only
on matched bounds — absent bounds read `na`, never a flattering zero; the
call predicate is zero-threshold (tiny leakage on an absent signature is
measured as FP on purpose, §8 semantics); only the `absolute` main estimand
is scored and dropped rows are counted into `notes`; unscorable cells are
*reported* skipped (skip-not-skip on the read side); cell-contract violations
(crossed sample ids, duplicate call rows) raise `CellContractError`.

**Determinism is a hard rule**: no RNG at score time; canonical row order,
fixed 6-decimal rendering, ts is file-name metadata only. The same cachedir
reproduces a byte-identical table (`test_scoring_determinism` is the standing
gate; the dispatch demo saw sha256 equality across independent passes).

**Verification record (commands actually run).** bench/m7 `python3 -m
tests.run_all`: 48/48 (12 pre-existing + 36 new across ⑤–⑩); bench/g0 suite
45/45 unchanged; `tools/ci-selfcheck.py` PASS exit 0; `grep -rn "g0/cache"
bench/m7` empty; double-emission byte-identical demo cmp-exit 0. The mock
smoke pass now ends with `[scoring] benchmark_m7_<ts>.csv: N cells scored, M
skipped -> verdict appended` and exits 0.
