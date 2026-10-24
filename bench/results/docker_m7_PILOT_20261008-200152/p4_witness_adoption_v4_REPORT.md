# Phase-4 runner-side adoption: sigminer spectra-witness export — PROPOSED battery

Agent: runner-side adoption agent (perf-parity Phase-4)
Date: 2026-10-25 (UTC spans in evidence files)
Branch/worktree: `perf/p4-readjudication` @ `msuiter-wt/p4` — change set **uncommitted**, per mandate
Scratch: `/tmp/p4runner/` (scripts `/tmp/p4runner/tmp/`, logs `/tmp/p4runner/logs/`, VM-visible staging `/Users/wsx/p4runner_stage/`)
Proposal under test: `/tmp/p4scorondiag/proposed/run_sigminer_spectra_witness.patch`

## Verdict

**PROPOSED-PASS as uplifted (v4; controller-leg word-flip of the v3 adoption).** The measured intervals are byte-identical across unpatched,
v1-patched, v3-patched and the slice3-r5 era control (`871eac0f5c5e0412…`) — the export is pure
instrumentation — and the witnessed probe resolves the de-novo predictions (`tp=6 fp=0`,
`mean_match_cosine 0.99138`, Sig1/Sig2 rows carry `denovo-spectra`, no dead_strata).
**The proposal AS WRITTEN (v1) must not be adopted:** attested verbatim `tp=0 fp=6`,
notes `de-novo-unresolved=6`, `dead_strata=[["sigminer__main__N100", 6]]` — its witness loads
(96/96 channels finite) but can never be *matched*, because its channel keys come from
`colnames(catalog)`, which R's `read.csv(check.names=TRUE)` has syntactically mangled
(`A[C>A]A → A.C.A.A`) out of agreement with the on-disk header the scoring contract keys on (§4,
root cause + minimal fix in §2). The adopted change set carries the v3 uplift: channel keys read
from the raw header line via `scan(counts_path, what="", nmax=1L, sep="\n", quiet=TRUE)`. v4 is the
controller-leg re-witness of the adopted bytes: the `(PROPOSED, ` word in the witness-block header
comment is retired in both faces (adoption-commit hygiene, per law-assertion-follows-gate-flip),
diff-verified to exactly that one comment line per face plus the pin-token re-injection in both
Dockerfiles — comment-only on the executable face, and the invariance battery (§3) measured
intervals, witness and errors byte-equal to the v3 outputs, so the flip moved zero payload.

## 1. Mandate compliance

- No push, no commits — change set left uncommitted in the worktree; this manifest is its companion.
- Campaign artifacts untouched: nothing under `bench/results/` modified; no campaign cell re-ignited; the campaign cachedir was never passed to any container or scoring call (all scoring ran on `/tmp/p4runner/probe/*` synthetic dirs).
- Container work synthetic-only: zero-RNG fixture (`make_fixture.py`, evidence `logs/fixture_evidence.json`: three identical samples `main__N100__r0..2`, counts ∝ planted SBS5 truth column × scale 300, row total 293, documented extraction seed 20261025 via `params.json`; the fixture itself carries no RNG stream).
- The frozen G0 truth (profile=degraded, arm=main, N=100, provider synthetic/0) stayed the scoring-side authority; the fixture is a controller battery, not a campaign cell.
- Naming clarification: the M7 protocol's predictions table is `intervals.csv` (seven-col long form `sample_id,signature,estimate,lo95,hi95,estimand,zeroed`, `competitors/intervals.py`). There is no `predictions.csv` in the protocol; the witness is the new optional sidecar `out/spectra.csv`.

## 2. The change set (what the patch does to the tree)

Both committed runners gain the identical block at the identical anchor (after the `labels` fallback line):
`spectra <- obj$Signature` guarded by `is.matrix`, `ncol == length(labels)`, `nrow == ncol(catalog)`,
`identical(rownames(spectra), colnames(catalog))` (all `identical(x, TRUE)` form), then long-form
`out/spectra.csv` written as `sprintf("%.17g")` rows `label,channel,value` under the header
`signature,channel,value`.

Files changed (four), all byte-attested disk→disk (transcription-dropout doctrine: no re-typed byte-critical content; splices executed from the on-disk patch file and measured with `hashlib.sha256`; `sha256sum`/`shasum` never used as authority):

| file | committed sha256 | adopted (v4) sha256 |
|---|---|---|
| `bench/m7/adapters/run_sigminer.R` | `7f30673847d96cd0e0fbfd1763e89ad12b1e5212c0152db4dd20741a2a750084` | `da2450042fd3e0829de86939157656b651a0978e004eb5e86bf2bab480669659` |
| `bench/m7/adapters/run_sigminer_arm.R` | `337b13ec36fd4ea27d5276df055f7a78604014b5074b3b6b9d5f7f6062c5b482` | `018b8f3f286cef9ae43f73ca983f903a36ef029ad42ca9568eeb22ce19af4208` |
| `bench/m7/adapters/Dockerfile.sigminer` | asserts `7f306738…` | asserts `da2450042fd3e0829de86939157656b651a0978e004eb5e86bf2bab480669659` |
| `bench/m7/adapters/Dockerfile.sigminer.tree` | asserts `337b13ec…` | asserts `018b8f3f286cef9ae43f73ca983f903a36ef029ad42ca9568eeb22ce19af4208` |

v3 (intermediate adoption lineage, superseded by the comment-only v4 flip):
`run_sigminer.R 7c23bd8ff9dce74e23ad65bd7038da79cbc03ec87bc40e5911a55f1f185bcb58`,
`run_sigminer_arm.R 0b0a56be13414f56a8f31798abd96dc1e53d816c749799b388033ba855b657a1`.

Machine-readable, all digests measured disk→disk (`hashlib.sha256`): `logs/pin_diff_v4.json`
(authoritative for the v4 bytes; cross-gated at write time against the controller's own-hands
claims — measured == claimed on all four, asserted), built upon `logs/pin_diff_v3.json`
(lineage ledger; carries the verbatim v1/v2 digests too, cross-checked against `logs/pin_diff.json`
/ `logs/pin_diff_v2.json` — a mis-transcription of the v1/v2 values into the new ledger was caught
and corrected by exactly this cross-check).

### Proposal evolution (the recorded deviation from the patch as written)

| rev | `run_sigminer.R` sha256 (16) | fate |
|---|---|---|
| committed | `7f30673847d96c…` | pre-patch baseline |
| v1 (patch as written) | `4ae373c5779f68…` | built (`p4witness-ctxB-gateless`), deterministic (witness `4fe94995…` r1≡r2), intervals pure — but probe-attested **DECLARED**: `tp=0 fp=6`, `de-novo-unresolved=6` |
| v2 (`read.lines(header)` uplift) | `78d5504bbcf6ae…` | died rc=1 on a missing-function call in the export path — `could not find function "read.lines"` (base-R rename reality, probe-attested: `readLines`/`scan` present, `read.lines` absent); **intervals absent** measured: `runs/fx/ctxBv2_{r1,r2}/out/intervals.csv` do not exist (the export crash preceded the GUARD four-file set; `errors.log` present) — the failed leg is retained on disk as evidence, not laundered |
| v3 (`scan(sep="\n")` uplift) | `7c23bd8ff9dce74e…` | probe-PASS (§4); witness `3cc0a0f9…` deterministic r1≡r2; keys byte-equal the on-disk header (§3) |
| v4 (controller word-flip of v3) — **adopted** | `da2450042fd3e082…` | comment-only `(PROPOSED, ` retirement, diff-verified one line per face + pin-token re-injection both Dockerfiles; re-witnessed on the full scripted path (§3 rows ctxBv4_r1/r2, §4 v4 column, gate replay) — intervals/witness/errors byte-equal to v3, as a comment-only flip must be |

Root cause of the v1 failure (measured, not theorized): `read.csv(check.names=TRUE)` mangles
non-NAME labels, so a witness keyed on `colnames(catalog)` presents `A.C.A.A` where the scoring
strict contract expects the file's own `A[C>A]A` — the witness loads, then every provider-channel
lookup misses and every de-novo call resolves to None → DECLARED. v3 keys the witness rows on the
raw header tokens (the on-disk bytes the contract itself keys on) while the guard keeps the
`identical(rownames(spectra), colnames(catalog))` positional check. v3 was re-run through the
**entire** battery (build, determinism, purity, in-container contract probe, probe cell) — and
v4 was re-run through the same scripted path (build → two fixture reps → invariance gate →
attestation → gate replay). The adopted image is
`msuiter-sigminer:p4witness-ctxBv4-gateless`. In-container verification of the pin layer: the build
echoes and passes the assert
`RUN test "$(sha256sum /work/run_sigminer.R | cut -d' ' -f1)" = "da2450042fd3e082…"` with
`build-exit=0` and no `[FATAL] … bytes diverge` firing (`logs/build_ctxBv4_gateless.log`; the
single [FATAL] string in the log is the instruction echo itself). The tree-side constants equal the
measured on-disk digests (v4 re-pin by the controller's disk-measured token injection; verified
here by `logs/pin_diff_v4.json` cross-gate: file bytes, pin tokens and claims agree four-for-four).

### Digest re-pin enumeration law
`grep -rn` across `bench/m7` for both committed digests hits exactly the two Dockerfile assert
lines above (campaign `results/` deliberately excluded from modification). No other file in the
tracked tree carries either constant.

### Pinned-byte source audit (per [[pinned-byte-source-audit-law]])
A reading test EXISTS for this pin class: group (O) `tests/test_hash_provenance.py`
(`tools/audit_executed_surface_deps.verify_byte_pin_triangle` + `lint_hash_provenance`), which
re-measures committed runner == promoted rehearsal witness == Dockerfile assert constant == manifest
role-claims, plus the RB-06 lint over the recipe family. No new harness is needed. Its live-state
expectation after adoption:
- `test_triangle_is_green_on_measured_live_inputs` → **RED (expected, measured)**: the committed
  runner moves to the adopted `da245004…` while the frozen rehearsal witness
  (`bench/results/docker_m7_PILOT_20261008-200152/rehearsal_slice3-r4/run_sigminer_fixed.R`,
  immutable campaign artifact) stays `7f3067…`. This red is the fleet telling the controller that
  the rehearsal witness + pilot manifest role-claims need a **re-seal against the adopted bytes**.
- `test_lint_is_green_on_the_live_recipe_family` → **RED (measured)**. The lint re-flags the frozen
  `rehearsal_manifest.json` claims verbatim:
  `manifest-entry-rehash: bench/m7/adapters/run_sigminer.R: claimed '7f3067…' is not the measured
  digest`; `manifest-entry-rehash: bench/m7/adapters/Dockerfile.sigminer: claimed 'defd0330…' is
  not the measured digest` (two-level pin: re-pinning the Dockerfile moves *its own* digest, which
  the manifest also claims); plus the downstream `unbacked-literal: rehearsal_manifest.json:
  defd0330…`. The re-seal demand is therefore **two-level** (runner + Dockerfile entries), not the
  single-level §2 first assumed.
- Measured attribution (not assumed): restoring the committed bytes in the same worktree → the
  module re-runs **9/9 green**; re-applying the adopted bytes (hash-attested copy, v3-generation
  `7c23bd…` / `0b0a56be…`) → the same **7/9 red** (four lint + three triangle units, each red on
  the same single root: the frozen campaign manifest/witness now lags the patched tree). All six
  "negative-control" units ride the same root because each seeds from `_live_inputs()` and asserts
  an exact flag list. For v4 no new red was introduced and none laundered: the v4 bytes differ from
  the re-witnessed v3 bytes by one comment line per face (diff-verifiable), so the same seven
  units, same root, stand — the v4 battery (`identity_check_v4.json`) is the invariance attestation
  that a drift would have broken.
- Post-adoption (v3 bytes, before the controller's r6-authority leg) full suite: **323/330**,
  the 7 reds *exactly* the `test_hash_provenance` set above — no collateral in any other group
  (`logs/suite_post_adoption.log`; baseline pre-change **330/330, exit 0**,
  `logs/baseline_suite.log`).
- **Current-tree re-measure (after the controller leg's slice-authority flip)**: the change set now
  also carries the controller's edits to `tools/audit_executed_surface_deps.py`
  (`REHEARSAL_SLICE = "rehearsal_slice3-r6"`, tests deriving from the single authority) plus
  `tests/test_hash_provenance.py` / `tests/test_executed_surface_audit.py`. Full suite now
  **318/330**, 12 reds in exactly two modules, all one root: the named slice
  `bench/results/docker_m7_PILOT_20261008-200152/rehearsal_slice3-r6/` **does not yet exist**
  (`FileNotFoundError: …/rehearsal_slice3-r6/run_sigminer_fixed.R`) — the r6 **re-seal is the
  controller's pending product**; this battery does not fabricate it. Composition: the whole
  `test_hash_provenance` module (9/9 — the seven measured roots above now sit *behind* the load
  failure, and `lint_flags_an_unbacked_hash_literal` + `triangle_flags_a_diverged_witness_copy`,
  green at the v3 measurement, now fail at the missing-r6 load), plus 3 `test_executed_surface_audit`
  units (`allowlist_snapshot_carries_the_minimum_witness`, `rehearsed_bytes_lint_clean_against_snapshot`,
  `defect_injection_lint_fires_against_snapshot`). Seal requirements the reading tests impose on the
  r6 product (pinned-byte-source-audit-law pairing): the directory must contain `run_sigminer_fixed.R`
  carrying the adopted `da245004…` bytes, `rehearsal_manifest.json` with v4-consistent entries for
  `run_sigminer.R` **and** the re-pinned `Dockerfile.sigminer` (two-level), and
  `formals_allowlist_slice3-r4.json` — the -r4 file-name suffix is what the reading test's own
  constant expects inside the r6 directory; name the artifact accordingly (`logs/suite_current_tree.log`).
- The re-seal is controller-owned (campaign artifact); this battery does not fabricate a replacement
  witness.

## 3. Bake rehearsal — interval byte-identity (instrumentation purity)

Both contexts staged VM-visible under `/Users/wsx/p4runner_stage/` after the `/tmp`-context
blindness incident (COPY-context `/tmp` reads reach the Docker Desktop VM as an EMPTY directory —
silently dangerous; staging dir noted for later cleanup). Build contexts `ctxA` (committed bytes) /
`ctxB` (patched + re-pinned bytes) share every layer up to the runner `COPY`; digests re-verified
after staging.

Image tags (synthetic-only; campaign refs untouched; no registry-row flip, no `p6_flip_roster` run):
`msuiter-sigminer:p4witness-ctxA-gateless`, `msuiter-sigminer:p4witness-ctxB-gateless` (v1),
`msuiter-sigminer:p4witness-ctxBv2-gateless` (crashed variant, kept for the record),
`msuiter-sigminer:p4witness-ctxBv3-gateless` (v3 lineage),
`msuiter-sigminer:p4witness-ctxBv4-gateless` (**adopted**) — all gate-omitted finals, infra account
in §5 — with in-build pin asserts passed (`sha256sum /work/run_sigminer.R` inside each build ==
re-pinned constant; this assert layer caught two stale-context states during the battery and was
never bypassed).

### Rehearsal table (measured `hashlib.sha256` over per-run out dirs; `timing.json` excluded — wall-clock sidecar, not a prediction byte)

Single machine-readable authorities: `logs/identity_check.json` (`all_pass: true`, produced by
`tmp/check_identity.py`) for ctxA/ctxB/ctxBv3/slice3, and `logs/identity_check_v4.json`
(`all_pass: true`; the six v4 rows — both reps × intervals/witness/errors — each measured equal to
the v3-issued expected digests: the invariance STOP-gate never fired) for the adopted v4 rows.
Every hash `hashlib.sha256` over the run out-dirs; `timing.json` excluded by design.

| side | rep | intervals.csv | errors.log | spectra.csv |
|---|---|---|---|---|
| ctxA (committed) | r1 | `871eac0f…` | `01ba4719…` | (absent — committed runner) |
| ctxA | r2 | `871eac0f…` | `01ba4719…` | (absent) |
| ctxB (v1) | r1 | `871eac0f…` | `01ba4719…` | `4fe94995…` |
| ctxB (v1) | r2 | `871eac0f…` | `01ba4719…` | `4fe94995…` |
| ctxBv3 | r1 | `871eac0f…` | `01ba4719…` | `3cc0a0f9…` |
| ctxBv3 | r2 | `871eac0f…` | `01ba4719…` | `3cc0a0f9…` |
| ctxBv4 (**adopted**) | r1 | `871eac0f…` | `01ba4719…` | `3cc0a0f9…` |
| ctxBv4 (**adopted**) | r2 | `871eac0f…` | `01ba4719…` | `3cc0a0f9…` |
| **slice3_r1 — committed-image invariance** | r1 | `871eac0f…` | `01ba4719…` | (era runner, no export) |

Full values: `871eac0f5c5e0412cfb56803bd472958ec99b829c7924653e52f8e3c8a05e72a`,
`01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b`,
`4fe9499576f38bcf6387970f31dbd3ea4d018584a4118623f90277d55d95cdbb`,
`3cc0a0f9d5c57b02a3374180f8f957e895264cd874c6b92b134ccb374fd1280f`.

Determinism (within-side) first, THEN cross-side purity — all **true**, per `identity_check.json`:
- A: ctxA r1 ≡ r2 (intervals + errors); ctxB r1 ≡ r2 (intervals + errors + witness);
  ctxBv3 r1 ≡ r2 (intervals + errors + witness).
- B: intervals and errors.log **byte-identical across every side** — unpatched ≡ v1 ≡ v3 ≡ v4 ≡
  committed-image invariance row; and the v4 witness is byte-equal the v3 witness
  (`3cc0a0f9…`) — the comment-only flip moved zero payload bytes, measured not assumed. The export
  moves ZERO prediction bytes; REJECT/STOP triggers never fired.
- **Committed-image invariance row, named:** `intervals.csv` `871eac0f…` is byte-identical across
  `ctxA_r1/r2`, `ctxB_r1/r2`, `ctxBv3_r1/r2`, `ctxBv4_r1/r2` **AND** `slice3_r1` — the last executed with the frozen
  campaign image `msuiter-sigminer:slice3-r5` (the registry-READY shipped bytes,
  `logs/run_slice3_r1.json` records `image: msuiter-sigminer:slice3-r5`, rc 0) against the same
  zero-RNG fixture. The campaign's own shipped bytes produce the identical intervals on the battery's
  fixture: instrumentation purity proved against the campaign image itself, not merely against a
  same-lineage rebuild. `ctxBv2_*` outputs remain on disk as evidence of the failed leg (intervals
  absent by the crash-above).
- C (round-trip, v3): every witness `channel` token byte-equals the corresponding raw token of
  `in/counts.csv`'s header line (`witness_keys_raw_header: true`), and the witness `(signature,
  value)` pairs match position-for-position the in-container contract probe's independent
  `sprintf("%.17g")` render of `obj$Signature` (`values_match_render: true`). Render keys are
  R's mangled view (`A.C.A.A`) — the very asymmetry that condemned v1; values agree because
  matrix rows and header tokens are positionally locked by the guards.
- Contract facts, in-container probe (`logs/inspect_v3_stdout.log`, `contract_report.txt`):
  `sigminer_version=2.3.1`, `R_version=4.3.3`, `suggested_signum=2`, `labels=Sig1,Sig2`,
  `dim_spectra=96x2`, `guard_ncol_eq_labels=TRUE`, `guard_nrow_eq_ncat=TRUE`,
  `guard_rownames_eq_channels=TRUE`, `count_nonfinite=0`.

## 4. Witnessed probe cell + scoring attestation

Synthetic probe cells assembled ONLY under `/tmp/p4runner/probe/` (never the campaign cachedir);
`manifest.json` written in the `run_bench` dialect with `"synthetic_probe": true`; scoring via the
committed code path (`scoring.cells.load_cell_spectra` strict contract directly + 
`run_products.score_cachedir(profile="degraded", provider synthetic/0)`), de-novo label `Sig1..SigK`.

The strict loader (`scoring.cells.load_cell_spectra`) was executed **directly** on the probe cell's
`out/`, then `run_products.score_cachedir(profile="degraded", provider synthetic/0)` scored the
fresh probe cachedir. Fixture: planted SBS5 truth (`truth_calls` SBS1/2/5/13/40 × 3 samples),
predictions `Sig1, Sig2` de-novo (uncatalogued), 6 pred calls.

| side (image) | witness_present | strict load | cell tp/fp/fn | cell notes | dead_strata | matched cos |
|---|---|---|---|---|---|---|
| ctxA (unpatched) | false | n/a | **0 / 6 / 15** | `de-novo-unresolved=6` | `[["sigminer__main__N100", 6]]` | — (DECLARED) |
| ctxB (v1 as-written) | **true** | accepted (Sig1/2 @96 ch, all finite) | **0 / 6 / 15** | `de-novo-unresolved=6` | `[["sigminer__main__N100", 6]]` | — (DECLARED) |
| ctxBv3 | **true** | accepted (Sig1/2 @96 ch, all finite) | **6 / 0 / 9** | *(clean)* | `[]` | `mean_match_cosine 0.99138` |
| ctxBv4 (**adopted**) | **true** | accepted (Sig1/2 @96 ch, all finite) | **6 / 0 / 9** | *(clean)* | `[]` | `mean_match_cosine 0.99138` (measured equal to v3: same bytes, same outcome) |

v3 signature rows: SBS5 `matched tp=3` (cos 0.99200), SBS40 `matched tp=3` (cos 0.99076) —
planted-known matches resolved **via the witness path**; Sig1 and Sig2 each `matched tp=3` with
notes `denovo-spectra` — the cosine rows are measured through the witness, not declared.
The v1 row is the negative control of the uplift: byte-present, finite, structurally valid
witness that still cannot resolve — the mangled-key proof.
Machine-readable attestations: `logs/attest_attest_unpatched.json`,
`logs/attest_attest_patched.json` (v1), `logs/attest_attest_patched_v3.json`,
`logs/attest_attest_patched_v4.json` (**adopted**; gate asserted: strict-load 96/96 bracket-form
accepted, `tp=6 fp=0`, token absent, `denovo-spectra` on both prediction rows, `dead_strata=[]`,
cosines 0.99200/0.99076/0.99138 all ≥ 0.85); probe cells under
`/tmp/p4runner/probe/{unpatched,patched,patched_v3,patched_v4}/cells/…` only. The committed-side
DECLARED evidence CARRIES unchanged (ctxA staged runner re-verified `7f30673847d96c…`, its cells and
the slice3 attestation re-hashed in place — no rebuild, per the controller leg).
**Witness liveness gate (dead-metric law applied to the witness itself).** The attestation must
show BOTH: (i) the strict `load_cell_spectra` **accepts** the verbatim bracket labels — measured:
2 signatures, 96/96 distinct channel keys accepted, all bracket-form (`A[C>A]A` … `T[T>G]T`); and
(ii) the best-cosine ≥ 0.85 Hungarian match **FIRES** — measured: `tp=6 > 0`, `de-novo-unresolved`
token **gone**, prediction-row notes `denovo-spectra`, matched signature-row means 0.99200 (SBS5) /
0.99076 (SBS40) with cell mean 0.99138 ≫ 0.85, `dead_strata=[]`. A schema-valid witness that left
`de-novo-unresolved` standing would be a DEAD metric ⇒ proposal REJECTED verbatim — and that is
exactly the verdict rendered on v1 (finite, schema-valid, yet the token stands). The same-fixture
DECLARED contrast is measured on both unpatched sides: `ctxA_r1` (no spectra.csv) and the
committed-image `slice3_r1` (frozen `slice3-r5` bytes) each attest `tp=0 fp=6`,
`de-novo-unresolved=6` (two de-novo signatures × three samples; the host dry-run's `=3` is the
one-signature fixture variant — both figures stated at their provenance, no laundering). Machine
ledger: `logs/witness_liveness_gate.json`; new attestation file `logs/attest_attest_slice3_r1.json`.
**Probe attestation verdict: PASS on the adopted (v3) side; FAIL as-written (v1).**

Host-side dry-run of exactly this attestation path (committed fixture writer `tests/scoring_fixtures`,
witness written in the runner's `%.17g` dialect; `logs/dryrun_attest.json`, rc 0):
- **with witness** (`Sig1`, 96/96 channels, all finite): cell `tp=3 fp=0 fn=12`,
  `mean_match_cosine=1.0`; truth row `SBS5 matched tp=3`; prediction row `Sig1 matched
  notes="denovo-spectra"`; `dead_strata=[]`; cell notes carry **no** `de-novo-unresolved` token.
- **without witness** (identical predictions): cell `tp=0 fp=3 fn=15`,
  notes `de-novo-unresolved=3`; `Sig1 false_called notes="uncatalogued"`;
  `dead_strata=[["sigminer__main__N100", 3]]` — the DECLARED contrast, measured not vacuous.
This attests the scoring-side wiring (strict loader + spectrum-space Hungarian) independently of the
container; the container battery then attests the runner actually *produces* such a witness.

## 5. Infra account (verbatim, per [[ci-infra-stall-cancel-rerun]])

Host at battery time: swap total 12288 MB, **free 1407 MB at decision time → 580 MB at battery
start** (external load, not from this battery's footprint; `vm.swapusage`, `vm_stat` sampled).
In-build replay gate
`RUN --network=none sh /tmp/self_witness.sh` died with **exit 137 (SIGKILL)** at ~241–245 s on
ctxA (two attempts: `build_ctxA.attempt1.log`, `build_ctxA.log`) and once on ctxB
(`build_ctxB.log`) — in every case AFTER the replay's extraction completed
(`suggested result 95.5`, `[run_sigminer] 1 samples x 2 signatures -> …/intervals.csv`), i.e. the
kill lands in the step's closing seconds inside the buildkit sandbox, not in the payload:
the identical `docker run --rm --network=none … sh /tmp/self_witness.sh` executed STANDALONE in the
byte-final images returned rc 0 with the gate's own green line
`[self-witness] mini-cell OK: rc 0, sidecar schema valid, container-side guard satisfied`
(`logs/replay_ctxA_manual.log`, `logs/replay_ctxB_manual.log`, `logs/gate_replay_v3.log`,
**and** `logs/gate_replay_v4.log` — every side including the ADOPTED
`p4witness-ctxBv4-gateless`, all attested rc 0 through the same verbatim gate with the gate's own
green line in-file). The gateless finals are
byte-identical to the full recipe minus that one terminal RUN instruction (dropping it adds no layer;
all layers through `COPY self_witness.sh` are the committed chain — digests in build logs:
ctxA committed Dockerfile `defd0330…`, gateless variant `2a0104ac…`;
ctxB committed `40183e3e…`, gateless `16e872bb…`). A host with non-exhausted swap should
reproduce the tagged full images with the in-build gate intact;
commands recorded verbatim:
```
docker build -f /Users/wsx/p4runner_stage/ctxA/Dockerfile.sigminer \
  -t msuiter-sigminer:p4witness-ctxA-r1 /Users/wsx/p4runner_stage/ctxA
docker build -f /Users/wsx/p4runner_stage/ctxB/Dockerfile.sigminer \
  -t msuiter-sigminer:p4witness-ctxB-r1 /Users/wsx/p4runner_stage/ctxB
```
This is an infra condition report, not a semantic waiver: the gate's assertions are attested
executed rc-0 in §3/§4 evidence (the buildkit step is literally `sh /tmp/self_witness.sh`; running
it standalone in the finished image executes the same bytes against the same filesystem).
Scratch-script defect surfaced and fixed by the runtime loop (transcription-dropout doctrine):
`run_cell.py` reached disk with `captureoutput` for the keyword `capture_output`; first battery's
four runs died rc=1 on a `TypeError` before launching containers (`logs/run_ctx*.json` tracebacks
preserved); fixed disk→disk, battery relaunched.

## 6. What is NOT yet true

- Campaign cells remain **unwitnessed**: no campaign `out/` gained a `spectra.csv` (mandate:
  campaign artifacts immutable; witnesses appear only upon re-measurement).
- Full-grid re-measurement is a **future single-ignition decision owned by the controller**; this
  battery licenses the decision, it does not take it.
- The registry row (`competitors/registry.py` sigminer: `msuiter-sigminer:slice3-r5` @
  `sha256:05cb29e0cfe881c3a0c7d1ec7c9058cfbbb9539f5d1c135787027e6002c703e9`, status READY) is
  **not flipped**; the P6 arm roster is not flipped; no `p6_flip_roster.py` run.
- Group (O) `test_hash_provenance` red state: measured **7 of 9** at the v3 adoption (323/330);
  on the current tree (post r6-authority flip) the whole module 9/9 plus 3
  `test_executed_surface_audit` units, **318/330**, all one root — the r6 slice artifacts are not
  yet sealed (§2); the frozen-campaign claim root underneath stays: the frozen campaign rehearsal witness
  (`…/rehearsal_slice3-r4/run_sigminer_fixed.R`) and the sealed `rehearsal_manifest.json`
  role-claims still describe the pre-patch bytes (frozen witness `7f3067…` vs adopted `da245004…`). The sanctioned remedy is a controller re-seal (a
  new rehearsal slice, not an edit of the immutable campaign artifacts) covering the TWO levels the
  lint measures: `run_sigminer.R` and the re-pinned `Dockerfile.sigminer` itself (§2;
  `logs/groupO_post_reapply.txt`, `logs/suite_post_adoption.log`). This battery deliberately does
  not fabricate that witness.
- Arm-family scope: `run_sigminer_arm.R` is patched + re-pinned in the change set, but the six P6
  arm images were not rebuilt in this battery (cold source-tree compile of `install_sigminer_arm.R`
  + P6 context assembly via `tools/p6_build_arms.py`; heavy under the host's memory state). The
  arm-face hunk is the same anchor-verified splice (self-attested `apply_witness_patch.py`), and the
  main-face battery is the adoption gate the registry row rides. Rehearsing the arm face (or
  deferring it to the arm re-measure the controller owns) is a controller call.
- Staging note: `/Users/wsx/p4runner_stage/` (contexts + runs) exists for VM bind visibility;
  disposable after adoption. `/tmp/p4runner/` holds all evidence.
- Mirror law (recorded, unexercised): no image pull was needed (base present locally); the recipe
  header pins `FROM 9f6c5in3dh5vszgdz0.xuanyuan.run/rocker/r-ver:4.3.3`; era-bake layers ride
  `p3m.dev` CRAN snapshots with version asserts (lpSolve 5.6.20 / synchronicity 1.3.10 /
  matrixStats 1.3.0) that re-executed identically on both sides.

## Evidence index

- `logs/pin_diff_v3.json` (authoritative lineage ledger: committed/v1/v2/v3 + Dockerfile pin
  sites), `logs/pin_diff.json` (v1-era), `logs/pin_diff_v2.json` (v2-era), `logs/fixture_evidence.json`,
  `logs/dryrun_attest.json`
- `logs/build_ctxA.attempt1.log`, `logs/build_ctxA.log`, `logs/build_ctxB.log`,
  `logs/build_ctxA_gateless.log`, `logs/build_ctxB_gateless.log`
- `logs/replay_ctxA_manual.log`, `logs/replay_ctxB_manual.log`, `logs/gate_replay_v3.log`,
  `logs/battery.log`, `logs/v3_battery.log`
- `logs/run_ctxA_r{1,2}.log`, `logs/run_ctxB{,v2,v3,v4}_r{1,2}.log`,
  `logs/build_ctxBv4_gateless.log` (pin assert `da245004…`, build-exit=0),
  `logs/identity_check_v4.json` (invariance STOP-gate ledger, all_pass),
  `logs/run_slice3_r1.json` (frozen-image invariance run, rc 0, image recorded in-file),
  `logs/attest_attest_{unpatched,patched,patched_v3,patched_v4,slice3_r1}.json`,
  `logs/witness_liveness_gate.json` (gate ledger, ruling-3, v4 ACCEPT side appended),
  `logs/pin_diff_v4.json` (v4 authoritative digest ledger, controller-claim cross-gated),
  `logs/identity_check.json`,
  `logs/inspect_v3_stdout.log` (in-container contract probe + render), `logs/groupO_post_reapply.txt`
- `logs/baseline_suite.log` (330/330 pre-change), `logs/suite_post_adoption.log` and
  `logs/suite_final_state.log` (323/330 on the final adopted bytes — the 7 reds named verbatim
  in-file), `logs/suite_current_tree.log` (318/330 after the controller's r6-authority leg —
  the 12 reds named verbatim in-file), `logs/groupO_post_reapply.txt` (restore/re-apply
  attribution round-trip)
- Staging digests (measured disk→disk, §2 ledger): **v4 re-stage** — staged
  `ctxB/run_sigminer.R` `da2450042fd3e082…`, `ctxB/run_sigminer_arm.R` `018b8f3f286cef9a…`,
  `ctxB/Dockerfile.sigminer` `b1082c414df17dc1…`, derived `ctxB/Dockerfile.gateless`
  `569fc21504efe443…` (main minus the single gate RUN line); lane ≡ `/tmp/p4runner/ctxB/` ≡
  `/Users/wsx/p4runner_stage/ctxB/` at both hops (assertion-gated), container-asserted in-build; fixture in/ `catalog.csv 35706fdc…`, `counts.csv 672ea545…`,
  `params.json 86372555…` (full values in `logs/fixture_evidence.json`)
