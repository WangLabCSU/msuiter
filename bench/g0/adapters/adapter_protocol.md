# The G0 container adaptation protocol (the JSON/CSV in-out contract)

> Version 2026-09-29 (revised after the W1/D2 API reconciliation, superseding the relevant entries of the 2026-09-28 frozen version).
> The applicable objects: `Dockerfile.sigfit` + `run_sigfit.R`, `Dockerfile.stl` + `run_stl.R`,
> `mock_runner.py` (the pipeline self-check placeholder, not a competitor measurement). The in-container working directory `/work`, the input mounted
> `/work/in` (read-only), the output mounted `/work/out` (writable).
>
> The common discipline of the two runners (the last round's smoke lesson hardened into the contract):
> - `errors.log` **lands first** (the first thing upon entering the outdir), the failure information appended; the run_grid
>   cache-skip guard depends on its existence, the failure path never leaves a half `intervals.csv` (each run
>   first clears the residual outputs, the CSV/manifest written out in one pass only after all succeeds, on failure exit non-zero).
> - **The explicit numeric defense**: any non-numeric column, non-finite value, negative value, duplicate/empty
>   id in the counts/catalog is all rejected (exit non-zero + the reason recorded in errors.log), no silent conversion.
> - Every RUN step of the two images carries the `|| { echo ...; exit 1; }` guard + the post-install `library()`/version
>   assertions (the last round's silently broken STL image must not recur).

## 1. The input (three files, all mounted at `/work/in/`)

### counts.csv (the simulator output)
```csv
sample_id,A[C>A]A,A[C>A]C,...,T[T>G]T
main__N1000__r0,3,1,...,0
```
- The channel columns = 96, **the order must agree item by item with the `tools/channel-reference/SBS96.txt` canonical order** (the simulator and the validator share this anchor).
- The `sample_id` naming: `{arm}__N{n}__r{rep}` (the double-underscore separators; the run_grid decodes it back to the cell accordingly).
- Integer counts; one sample per row (= one replicate).

### catalog.csv (the fitting catalog; user-supplied, never into the repository)
```csv
channel,SBS1,SBS2,...,<sigK>
A[C>A]A,0.010622,...
```
- Rows = the 96 channels (the first column `channel`, the label order as above); the columns = the signatures, each column a sum-to-1 proportion (the runner internally applies a normalization defense).
- The formal G0 (the F3 freeze) = the COSMIC v3.6 SBS96 GRCh37 all the 101 signatures, via the environment variable
  `G0_CATALOG_PATH` pointing at the user's own file, mounted into the container as a read-only volume; the harness
  does not copy, convert or cache the file into git. The `G0_SIGNATURES_PATH` (the 5×96 ground truth)
  is validated and loaded only by the provider, likewise never into the repository.
- The license acceptance is the user's action: before running a real tier beyond docker/mock, the user must confirm
  the license of the held catalog file (the harness states this in the README, no leniency of any kind).

### params.json (the parameters of this call)
```json
{"tool": "sigfit", "seed": 1712345678, "nboot": 200, "notes": "the Tier-1 default parameters, used as-is"}
```
- `seed`: the cell batch anchor = `g0.seeds.derive_seed(tool, arm, N)` (the per-(tool, N, replicate) derivation of the protocol §2.3
  lands through the `sample_seeds` mapping: per sample
  `derive_seed(tool, arm, N, rep)`; the per-sample-driven tools — the STL's
  `randomSeed=` — use the mapping; the sigfit, a single HMC fit over the whole batch, uses the batch anchor).
  All the HMC/bootstrap randomness must be driven by them (the reproducibility discipline).
- `nboot`: read only by the STL (the FitMS `nboot=`), formally frozen 200; the smoke may use 20.
- The sigfit's chains/iter/warmup all take the package defaults (the rstan `chains=4/iter=2000/warmup=1000`),
  written into the result manifest; the three optional keys `params.chains/iter/warmup` serve only the smoke short chains,
  the formal experiment must not set them.

## 2. The output (`/work/out/intervals.csv`, the long table)

```csv
sample_id,signature,estimate,lo95,hi95,estimand,zeroed
main__N1000__r0,SBS1,148.3,101.2,201.9,absolute,0
main__N1000__r0,SBS1,148.3,101.2,201.9,raw,0
```
- Each row = (sample_id × signature × estimand). **The column coverage = all the signatures of the catalog.csv**:
  when the tool result holds only a selected subset (the STL exposures drops the all-zero signature columns), the runner must map back
  to the full catalog columns, an absent signature honestly reported as `estimate=lo95=hi95=0, zeroed=1`.
- The units: the interval endpoints of the absolute estimand are **counts** (the same units as the truth h_j = f_j·N).
  The sigfit's multinomial exposures are proportions ⇒ inside the runner **× the sample's total mutation count to restore**,
  and asserting (i) the per-sample proportion sum ≈ 1; (ii) after restoration the per-sample sum = the total mutation count. The STL's
  exposures are natively counts, no conversion.
- The `estimand` values:
  - `absolute` (the main estimand: the **user-visible** interval) — enters the coverage judgment;
  - `raw` (only the sigfit: the un-zeroed posterior interval). The sigfit v2.2.0 **has no built-in zeroing parameter**
    (no `threshold.lower`) ⇒ the raw and the absolute carry the same numbers, both rows kept to fix the schema
    and to distinguish from future versions.
- `zeroed`: 1 = the signature triggered the tool's/protocol's zeroing or filtering, **the zeroing action itself is done by the
  harness post-processing** (the runner rewrites no numbers, it only honestly stamps the flag):
  - the sigfit: the post-processing rule = the absolute `lo95 < 0.01 ⇒ set to 0` (the protocol default; there is no
    corresponding parameter in the package);
  - the STL: the in-package `fixedThreshold 5%` filter sets an exposure to 0 ⇒ the runner directly reports
    `estimate=lo95=hi95=0, zeroed=1` (this is the tool's deployment behavior, not runner tampering).
  The zeroing/filtering trigger rate is the protocol §5 secondary column.
- The interval provenance:
  - the sigfit: the `retrieve_pars(fit, par="exposures", hpd_prob=0.95)`'s
    `mean/lower_95/upper_95` (the HPD) × the sample total count;
  - the STL: the point estimate = the in-package filtered bootstrap median (`res$exposures`, mapped back to the full catalog after dropping
    the `unassigned` column); the interval = the per-sample self-computed 2.5/97.5 percentiles from
    `res$bootstrap_exposures_samples[[sample]]` (the signature × nboot unfiltered
    bootstrap fits); a filtered signature's interval collapses to [0,0].
- A sample rejected by the tool (the guardline, as 0 mutations): **must not interrupt the whole batch**; for that sample every
  signature gets a row `estimate=lo95=hi95=NaN, zeroed=0`, and the reason written into
  `/work/out/errors.log`. The error rate honestly enters the result table (the protocol: the refusal-to-run rate is the deployment-behavior evidence).

### manifest.json (both runners write it)
- The version provenance: `version_tag` (v2.2.0 / v2.5.2, the full tag — the `packageVersion`'s
  "2.2" is not enough) + `commit` (the sigfit takes the `packageDescription()$RemoteSha`; the STL takes
  the clone SHA the image build stage fixed into `/usr/local/share/g0/build_info.json`).
- The sigfit additionally records: `model`, `hpd_prob`, the actually effective `chains/iter/warmup`,
  the `counts_restoration` rule, the `zero_rule`.
- The STL additionally records: `nboot`, `method`, `nparallel`, `useBootstrap`,
  `maxRareSigsPerSample`, the filter rule, `catalog_mode`, `channel_order`,
  `interval_source`.

## 3. The container call contract (the command form generated by the run_grid)

```bash
docker run --rm \
  -v <cell_dir>/in:/work/in:ro -v <cell_dir>/out:/work/out \
  g0-sigfit Rscript /work/run_sigfit.R \
    --counts /work/in/counts.csv --catalog /work/in/catalog.csv \
    --params /work/in/params.json --outdir /work/out
```
The mock placeholder with the same parameters: `python3 adapters/mock_runner.py --counts ... --catalog ... --params ... --outdir ...`.

## 4. The mock_runner behavior declaration

The mock applies the **same batch of simulated data** with the parameter self-serving method (the multinomial resampling → the EM refit →
the 2.5/97.5 percentiles), what it validates is the harness pipeline (the CSV round-trip / the coverage / the judgment),
**not any competitor behavior**. The `params.coverage_scale` (the default 1.0) is a test hook,
for constructing the calibrated / under-covered situations to drive the judgment's three-way fork.

## 5. The API reconciliation conclusions (the W1/D2 smoke verified them entry by entry per the measurement/the source code and landed them into the runners)

### 5.1 The sigfit v2.2.0 (the kgori/sigfit, measured inside the g0-sigfit:2.2.0 container)
1. The fitting entry is `fit_signatures(counts, signatures, exp_prior=NULL, model=, opportunities=NULL, ...)`;
   **there is no `fit_signatures_counts`**. The `counts` rows = samples × the 96 channel columns;
   the `signatures` takes `t(catalog)` (rows = signatures × the 96 channel columns).
2. The `seed/chains/iter/warmup` pass through the `...` into the `rstan::sampling`; the missing defaults = the package defaults
   4/2000/1000 (recorded in the manifest).
3. The `retrieve_pars(fit, par="exposures", hpd_prob=0.95)` (**`hpd_prob`**, not
   `sig_level/CI/hpd`; **there is no `threshold.lower`**) ⇒ `mean/lower_95/upper_95`,
   samples × signatures, **proportions** (the multinomial), the absolute counts need × the sample's total mutation count.
4. The channel order: the sigfit aligns the counts columns and the signatures columns positionally, both inputs using the repository anchor order
   suffices (the runner asserts the labels agree item by item).

### 5.2 The signature.tools.lib v2.5.2 (the source code checked line by line + container validation)
1. `FitMS(catalogues=, commonSignatures=, rareSignatures=, maxRareSigsPerSample=,
   method=, exposureFilterType=, useBootstrap=, nboot=, nparallel=, randomSeed=)`;
   the old code's actual parameters `signature/counts/parallelisation` do not exist. The `catalogues` takes the
   samples as **columns** and the channels as rows; the `commonSignatures` takes the signatures as columns and the channels as rows.
2. **`useBootstrap=TRUE` must be explicitly opened** (the default FALSE), otherwise the
   `bootstrap_exposures_samples` silently comes NULL and the intervals can come from nowhere. The intervals are self-computed by the runner from the
   per-sample (signature × nboot) matrices as the 2.5/97.5 percentiles.
3. **The channel-order trap**: the STL requires the classical order = the substitution (C>A,C>G,C>T,T>A,T>C,T>G)
   outer × the 5' (A/C/G/T) × the 3' (A/C/G/T) — different from the repository anchor SBS96.txt's lexicographic order.
   The runner re-arranges the counts/catalog rows synchronously into the classical order (the exposures carry no channel dimension, no re-arrangement
   back is needed), and uses the package's `getTypeOfMutationsFromChannels` to assert it is recognized as "subs".
4. The return structure: `res$exposures` = samples (rows) × signatures (columns) **including the `unassigned` column**
   (the runner drops it), and the all-zero signature columns get dropped by the package (the runner maps back to the full catalog columns, an absent signature
   reported as [0,0]/zeroed=1); `res$bootstrap_exposures_samples[[sample]]` = the signature ×
   nboot unfiltered bootstrap fits; the `res$exposures` point estimate = the in-package filtered bootstrap
   median.
5. **The W1 adjudication record (the SBS40/organ-T1)**: the Breast (and any organ) RefSig T1 catalog does
   not contain the ground-truth signatures such as SBS40, the organ path and the F3 frozen catalog are naturally in conflict. **In the formal experiment the STL side
   does not go through the organ T1**: uniformly `commonSignatures=` fed with the frozen v3.6 catalog file
   (`G0_CATALOG_PATH`, author-supplied, mounted as the catalog.csv through the harness),
   `rareSignatures=` set empty + `maxRareSigsPerSample=0` (the FitMS documented caliber: it degrades to
   the full-catalog common fitting, no rare-signature search). The organ= stays for diagnostic use only, not into the formal tier.

## 6. The image build discipline (the two Dockerfiles)

- The version tag locked; the GitHub dependencies (the NNLM, the indelsig.tools.lib, the STL itself) use the
  `git clone --branch <tag>` + `R CMD INSTALL` (the remotes::install_github has the API
  rate-limit risk), the clone's commit SHA fixed into `/usr/local/share/g0/build_info.json`.
- The STL image must install: the system libraries (libcurl4-openssl-dev libssl-dev libxml2-dev
  libicu-dev libpng-dev libz-dev libbz2-dev liblzma-dev libgmp3-dev cmake
  pkg-config) + the CRAN chain (the NMF/factoextra/limSolve/gmp/RCircos/doRNG etc.) +
  the Bioconductor chain (the BiocManager 3.18; the VariantAnnotation/GenomicFeatures/
  SummarizedExperiment etc.) + **the three** BSgenome genomes (the hg38 and the hs37d5 are the STL's
  hard Imports; the hg19 is the indelsig.tools.lib's hard Imports, and the latter is the STL's hard
  Imports — the library() will load all the Imports, one missing and the assertion fails).
- Every RUN step stops on failure (`|| { echo; exit 1; }`), immediately after the installation the
  `requireNamespace`/`library()` assertions; the final acceptance gate =
  `library(signature.tools.lib)` + `packageVersion()=="2.5.2"` + the `FitMS` export.
