# tools/kl-gate-p1 -- P1 bit-equivalence gate (one-shot fixed-platform experiment)

The msuiter-side kernel-extension face of parity-plan phase P1
(`docs/research/09-sigminer-v3-parity-plan.md` §5 row P1, §7 P1-kickoff
resolution): the certified in-house Apache-2.0 KL-MU kernel
(`src/rust/engine/src/nmf.rs`, `fit_kl`/`fit_kl_on_stream`/
`fit_kl_with_init`) consumed through the stable batch entry
`src/rust/engine/src/bin/msuiter-kernel.rs` (protocol=1) must remain
numerically protocol-equivalent to R `NMF::nmf(method = "brunet")`:

> per case and endpoint `T ∈ {50, 200}`: `‖ΔW‖_F / ‖W_R‖_F < 1e-10`
> (and the `H` twin)

This is the same acceptance gate U-M1s-14 passed once on 2026-09-30
(`tools/kl-crosscheck`, README + result.md). The difference: P1 re-asserts
it against the **stable boundary surface** -- the batch CLI that the
sigminer-side Suggests-gated isolated-process PR will exec -- rather
than the throwaway driver, so what the future consumer will run is what
gets certified.

## Posture: one-shot evidence, mechanically audited record

Per `docs/ARCHITECTURE.md` §7.1 / D11 / A8 this is a fixed-platform
one-shot experiment, NOT a CI-per-run gate. CI enforces the committed
evidence instead: `tests/testthat/test-kernel-gate-evidence.R` refuses a
missing, truncated, or over-budget `result.md` (verdict line required,
every endpoint ratio parsed and re-checked against the 1e-10 criterion,
the fixed seeds required on the face of the record). Zero-fabrication:
every numeric in `result.md` is machine-written by `run_gate.R`; re-running
the script regenerates the record and `data/outputs/` verbatim from the
committed synthetic inputs.

## Scheme A (external initialization), as established by kl-crosscheck

`nmf(V, k, method = "brunet", seed = nmfModel(k, W = W0, H = H0), maxIter = T,
stopconv = 1e6)` -- identical `W0/H0` on both sides, exact iteration count,
brunet's connectivity early-stop disabled. Four mechanism probes gate the
comparison itself (`run_gate.R` refuses to write `result.md` unless all
pass): injection fidelity (`--iters 0` returns the seeded factors
bit-for-bit), rerun determinism (two independent invocations byte-identical),
the prefix property (the T=200 checkpoint at t=50 equals the T=50 run
file-for-file), and batch-mode equality (the `--cases` manifest path
reproduces the single-case invocation byte for byte).

## Inputs (committed, SYNTHETIC -- D3: no COSMIC numerics anywhere)

The three 96x20, k=3 cases of `tools/kl-crosscheck/data/inputs`
(construction seeds V: 20260928/29/30, init seeds 401/402/403, input
quantization to 10-decimal dyadics for exact cross-language double
restoration -- all recorded there). Case summaries (from the
kl-crosscheck record): case1 separable 3-signature synthesis, case2 dense
random integer counts 0..39, case3 sparse spiky signatures with structural
zeros and one very-low-TMB sample. The G2 companion arm additionally runs
`case1` through `--init nndsvda --seed 20261014` (strict positivity +
rerun determinism; the zero-lock invariance proper is pinned in
`src/rust/engine/tests/g2_zero_lock.rs`).

## Run

```bash
cd tools/kl-gate-p1
Rscript run_gate.R        # exit 0 = all endpoints under the criterion
```

Requirements: R >= 4.3 with the `NMF` package (0.28 as in the U-M1s-14
record; CRAN, user-library install suffices), cargo/rustc on PATH. The
comparison pins the **unoptimized (debug) cargo profile on both sides of
every byte-comparison** (CLI goldens in
`tests/testthat/fixtures/kernel-cli/**` were produced by the same debug
build the tests rebuild); profile-cross bit attestation, if ever needed,
is a separate future record.

## Files

- `run_gate.R` -- full pipeline: env record -> build stable entry -> probes
  -> per-case endpoint comparison -> G2 companion arm -> `result.md`
- `result.md` -- the committed evidence (machine-written)
- `data/outputs/` -- committed raw artifacts behind every number in the
  record (CLI outputs per case/endpoint, checkpoints, batch-mode evidence)

Companion tests: `tests/testthat/test-kernel-cli.R` (R-side view of the
binary, byte-pinned goldens) and
`src/rust/engine/tests/kernel_cli_protocol.rs` (protocol pin against the
in-process kernel).
