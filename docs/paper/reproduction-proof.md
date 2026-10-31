# Reproduction proof — msuiter paper lane (PP-1)

This document is the one-command reproduction face for every sealed number
quoted in `docs/paper/paper-draft.md`. It is a verification artifact, not a
regeneration claim: everything below re-derives quoted values from committed
bytes and committed witnesses, on synthetic data only (G0 master seed
20260928). Regeneration of a campaign from scratch is operator-gated work and
is printed (never executed) by `--full`.

Governing house laws restated where they bind this face:

* Synthetic-only law — no artifact here touches a real-data cohort; the D3
  law keeps COSMIC numerics out of the repo entirely.
* SIM-provisioning trust law — the R-side scenario faces must run against a
  build OF THIS TREE, never an ambient stale install. Hence `MSUITER_REPRO_LIB`.
* Post-cap witness law — timing rows speak the floor-table epoch
  `f3e894a6933a2ffb` (pinned at `bench/m7/tests/test_p6_floor_governance.py:156`);
  pre-cap campaigns are quoted with an explicit epoch-mismatch label.
* Dead-metric law — the yardstick pin verifier and the DOI scanner carry
  planted-corruption controls that must fire for the face to pass; a silent
  green is a fail.

## 0. One command

Provision a library holding a build of the tree (once per tree revision):

```
R CMD INSTALL --library=/tmp/paperlane/rlib /path/to/this/tree
```

Then:

```
MSUITER_REPRO_LIB=/tmp/paperlane/rlib bash docs/paper/reproduce.sh --verify
```

Attested run of this face, this lane, 2026-10-31 (wall 176 s, rc=0):

```
FACE m7-tests                 rc=0  ...  PIN  m7-tests   ok  364/364 tests passed.
FACE o5-parity                rc=0       PIN  o5-parity  ok  lines=147 breaches=147
                                          PIN  o5-parity  ok  epoch=f3e894a6933a2ffb
FACE bootstrap-campaign       rc=0       PIN  ok  "ok": true
                                          PIN  ok  claimed 15.36600758177 vs
                                                  recomputed 15.36600758176629
                                          PIN  sealed-ratio   ok  1.536600758177e+01
                                          PIN  sealed-verdict ok MEASURED-false 15.37x
                                          PIN  sealed-secondary ok 14.2209x
FACE yardstick-pins           rc=0
FACE commit-objects           rc=0
PIN  p1-table                 ok  FAIL — 18 offending class(es)
FACE scen-atlas               rc=0  PIN  ok  OVERALL PASS
FACE scen-hrd                 rc=0  PIN  ok  OVERALL PASS
FACE scen-treatment           rc=0  PIN  ok  OVERALL PASS
PIN  seed-master              ok  seed: 20260928 (G0 master
PIN  seeds-bank               ok  4/4 committed Seeds.txt present
REPRODUCE-VERDICT PASS
```

## 1. What each face proves, and its committed anchor

| Face | Command | Sealed claim re-derived | Anchor (bytes on the branch) |
|---|---|---|---|
| m7-tests | `python3 -m tests.run_all` (in `bench/m7`) | governance/unit surface green | `bench/m7/tests/*`, spoken at :156 epoch pin |
| o5-parity | `python3 -m tools.parity_recompute` | O5 census `lines=147 breaches=147`, post-cap epoch | `bench/m7/tools/parity_recompute.py`, witnesses under `bench/results/p6_regen_20261023-044026/` |
| bootstrap-campaign | `python3 -m tools.verify_campaign --campaign ../results/bootstrap_vs_sigminer_20261013T175859Z --host <seal> --hw-profile <seal>` | 15.3660075817662x re-derived from arm witness bytes; MEASURED-false stands; host/hw pins re-checked | `bench/results/bootstrap_vs_sigminer_20261013T175859Z/{result.md,seal.json}` |
| (pins) sealed-ratio/verdict/secondary | byte greps | `1.536600758177e+01`, `MEASURED-false 15.37x`, `14.2209x` | `.../result.md:4,5`; `docs/PERFORMANCE.md:88` |
| yardstick-pins | `python3 tools/verify_yardstick_pins.py` | ratio 1.2323046734094532, iters/seed/threads/k/shape/versions, fixture digest, seconds-pair consistency; planted-corruption control FIRES | `bench/results/p6_regen_20261016-011928/nmf_yardstick_authoritative.json`, `bench/m7/adapters/yardstick_cell/matrix.csv` |
| commit-objects | `git show -s --format=%B` greps | P10 landing ratio 2.3004 and P-1 MEASURED-FALSE (23.7-32.2x) live in commit-message bytes | commits 2296f49, 8213192 |
| p1-table | byte grep | sealed P-1 gate table `FAIL — 18 offending class(es)` | `bench/results/p6_regen_20261016-011928/result.md:6` |
| scen-atlas / scen-hrd / scen-treatment | `Rscript bench/scenarios/run_{atlas,hrd,treatment}.R` | CS-1/CS-2/CS-3 self-adjudicating scenarios OVERALL PASS, rc is the law | `bench/scenarios/*` (PR #56 landing 5530af6) |
| seeds-bank | file presence | 4/4 campaign `Seeds.txt` committed | listed dirs in `reproduce.sh` Face 8 |

The exact sealed-number citations, their citation classes, and their
epoch labels are in the draft's Table 1/Table 2 and Appendix A; this file
only fixes how each is re-verified.

## 2. R-side environment freeze (renv)

`docs/paper/renv.lock` — Posit renv JSON lockfile: R 4.5.2 stamp, CRAN
repository, 111 pinned packages. Provenance (attested, banked in the lane
manifest): closure walk over DESCRIPTION metadata from the seeds
`{S7, rlang, pkgload, testthat, digest, jsonlite, withr, R6, sigminer}` over
the provisioning library: 118 closure entries -> 111 lockfile pins; the 7
dropped entries are recorded by the generator as
`missing=['furrr','ggplot2','graphics','grid','rstatix','sigminer','splines']`
— graphics/grid/splines ride the base distribution, and furrr/ggplot2/
rstatix/sigminer were local installs without a `Repository:` field. For a
clean-room replay those four resolve from CRAN/Bioconductor under the frozen
R 4.5.2 stamp (sigminer 2.3.3 is the ground-truth peer identity, not a
build dependency of msuiter itself).

Readback attestation (generator run, banked): `LOCK-PARSE ok; R=4.5.2;
packages=111` and `READBACK 111 R 4.5.2`.

Deviation, recorded honestly: the classic Ushey-renv API
(`renv::write_renv`/`restore_renv`) is no longer the CRAN `renv` namespace —
CRAN `renv` is Posit's package, whose successor `rrenv` is not reachable
from this box's configured mirrors. The freeze therefore uses the Posit API
(`lockfile_create` / `lockfile_write` / `lockfile_read` / `restore`), which
serves the same purpose: one lockfile, byte-pinned, readback-attested.

Replay: `renv::restore(lockfile = "docs/paper/renv.lock", library = <dir>,
prompt = FALSE)` (printed, not executed, by `--full`).

## 3. Container freeze

Committed Dockerfiles: `bench/m7/adapters/Dockerfile.sigprofiler`,
`Dockerfile.sigminer`, `Dockerfile.nmf_yardstick` (build contexts printed by
`--full`). Image identity is attested by the committed `docker inspect`
records in `bench/results/docker_m7_PILOT_20261008-200152/image_inspect_*.json`
— repo digest pins, not floating tags.

## 4. Seed regime

Master seed 20260928 (G0 synthetic regime) is spoken by the bootstrap
seal (`result.md`, PIN `seed: 20260928 (G0 master`). Per-campaign seed banks:
`Seeds.txt` committed under the bootstrap dir, both `p6_regen` dirs, and the
`docker_m7_degraded` dir; Face 8 refuses if any goes missing.

## 5. What this face deliberately does not claim

* No real-data result anywhere (G0-PRIMARY gated; the draft prints no
  "first coverage-measured" claim outside its gate block).
* No <=2x peer-parity row: the O5 census is quoted AS A CENSUS (147/147
  breach vs the compiled yardstick); the parity headline stays behind
  CAMPAIGN-R exactly as the commit bytes of 2296f49 state it.
* No signeR comparison (PI-C unverified): peer slots (a)/(b) only.
* No campaign regeneration: `--full` prints operator recipes (bootstrap
  one-key shot, container builds, renv restore) and runs none of them.

## 6. Attestation bank

Per-face logs of the attested PASS run and of each tooling pass are banked
in the lane directory (`logs/reproduce-verify-r4.txt` plus the per-face
`/tmp/msuiter-reproduce-*` logs at run time); the DOI census run
(`logs/doi-repin-final3.txt`) and lockfile generation log
(`logs/renv-lock-gen.log`) accompany them. The lane manifest maps every file
to its sha256 and its one-line claim.
