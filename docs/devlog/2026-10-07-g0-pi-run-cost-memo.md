# G0 authoritative run — measured cost basis for the PI go/no-go (2026-10-07)

**Purpose.** The frozen protocol (`docs/devlog/2026-09-28-G0-pi-adjudication.md`
§PI-5) allows the formal G0 verdict to originate only from a
`docker` adapter + `cosmic-file` provider execution of the `primary`
(or, per §6/§7-R7, the `degraded`) profile. This memo records what the
harness now actually costs per unit of that work, measured end-to-end on
the 2026-10-07 smoke run, so the PI gate is decided on numbers rather
than on guesses. No protocol constants are changed here.

## 1. Pipeline status: connectivity proven

The 14:01 smoke execution (`results/docker_smoke/`, profile=smoke,
adapter=docker, provider=cosmic-file, F2-frozen sigfit 2.2.0 +
signature.tools STL) closed the last three container-path defects:

| defect | class | guard now in CI |
|---|---|---|
| u64 seeds overflow `as.integer` | tool-boundary seed fold mod 2^31 | `test_seeds` golden pins |
| user catalog never mounted | docker cmd assembly (both mounts) | `test_seeds` mount asserts |
| relative `--cachedir` → named-volume error | `Path.resolve()` at assembly + CLI boundary | `test_seeds.test_docker_cmd_mount_sources_are_absolute` |

Result: 8/8 cells ok, zero FATAL, `intervals.csv` consumed downstream,
fresh `judgment_smoke_20261007-140100.md` (`kill conditions met: False`).
Per its own footer this file remains a harness self-check, not a G0
verdict — that status is unchanged and correct.

## 2. Measured unit rates (this machine, cold containers, N ≤ 1000)

| tool | per rep-run wall time | dominant cost |
|---|---|---|
| sigfit 2.2.0 | ≈ 19–23 s | container start + Stan model init |
| STL (signature.tools) | ≈ 112–122 s | container start + R namespace load |

**High-N calibration (§4, run same day) revises the naive reading.**
At N = 300 000 on fully loaded counts (sum = 300 000, all 96 channels
non-zero, verified estimates up to ~8 × 10^4): sigfit **9 s**, STL
**38 s** per rep-run warm — *faster* than the small-N cold figures.
The smoke per-rep rates are therefore dominated by cold-start tax
(container/daemon/library init amortised over 1 rep), not by per-N
compute: neither tool shows a super-linear N wall in the measured range.
The 1e6 tier is an eight-fold extrapolation of a measured slope and
remains cheap.

## 3. Profile extrapolation (from `g0/grid.py` frozen constants)

| profile | cell-reps/tool | both tools | serial, cold-rate floor | serial, warm-rate floor | ×8 parallel warm |
|---|---|---|---|---|---|
| `primary` (200 reps, full 19-point N grid) | 20 200 | 40 400 | ≈ 791 h | ≈ 263 h | ≈ 33 h |
| `degraded` (§6: 100 reps, 3-point N grid) | 2 100 | 4 200 | ≈ 83 h | ≈ 27.5 h | ≈ 3.5 h |

Warm rates (§2 calibration) are decision-grade for the 3e5 tier and
extrapolated (8×) to 1e6; cold rates bracket the worst case with
per-cell container restarts. The degraded profile is a **same-day
overnight run** under any bracket; primary is a **weekend-scale**
campaign, no longer a multi-week blocker.

## 4. High-N calibration — done

Two-cell execution (sigfit + STL at N = 300 000, `cache/calib/`,
2026-10-07, immediately after the smoke run) replaced the floor-rate extrapolation with measured
warm values; results in §2. The remaining unmeasured tier (1e6) enters
the §3 bounds only through the linear warm slope.

## 5. Decision menu for the PI

1. **Run `degraded` now** (§6 is protocol-predefined precisely for a
   compute-budget-constrained execution; verdict power ≥ 0.95 retained):
   same-day/overnight window under the measured warm rates, produces
   the authoritative Framing A/B input at bounded cost.
2. **Run `primary`** — now a weekend-scale campaign (§3), feasible on
   this machine without the M7 pinned-hardware host; the pinned host
   remains the right venue for the paper's reproducibility exhibit.
3. **Deferred** — not supported by the ROADMAP: the G0 gate blocks
   Framing A vs B, hence the paper's quantitative spine.

Recommendation: option 1 (degraded) immediately; option 2 opportunistically
in parallel on spare cores once the degraded verdict lands.
