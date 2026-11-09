# B1 · NMF bench(M1s acceptance gate,ARCHITECTURE §8:96×1000, k=10, 100 iter vs R NMF ≥100×)

Rerun:`Rscript bench/m1s/nmf/run_bench.R`. Same V/W0/H0(CSV byte-for-byte exchange), same T=100;
Two-sided protocol: warm up 1 run, + timed 3 runs take the median. Ours = driver pure-kernel (`fit_kl_with_init`, single-threaded);
R = NMF 0.28 brunet(external init W0/H0,stopconv=1e6,maxIter=100 exact control).

## Environment

- date: 2026-11-09 22:50:14 CST
- R: R version 4.5.2 (2025-10-31) (aarch64-apple-darwin20)
- NMF: 0.28
- BLAS: /System/Library/Frameworks/Accelerate.framework/Versions/A/Frameworks/vecLib.framework/Versions/A/libBLAS.dylib | LAPACK: /Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/lib/libRlapack.dylib
- rustc/cargo: rustc 1.92.0 (ded5c06cf 2025-12-08)
- host: aarch64-apple-darwin20(Apple Silicon; power state not controllable, figures are for this pinned hardware)

## Figures

- Input: V 96×1000 integer counts (separable synthetic,seed=20260928);init W0/H0 k/1024 grid (seed=20260929)
- Ours 3 runs (ms):200.408, 202.205, 201.919 → median = 201.919 ms
- R brunet 3 runs (s):0.752, 0.398, 0.476 → median = 4.76e-01 s
- **speedup = 2.4× ; criterion ≥100×:FAIL**
- Informational: per-iteration slope ≈ 2.000 ms/iter(T=1 median 3.884 ms vs T=100 median);fit_kl_with_init each iteration includes one objective-trajectory kl_objective(the 3 rd: WH matmul + 96k ln,U-M1s-14 required by the numeric protocol),R brunet baselinedoes not compute the objective per iteration——a same-granularity fitted comparison would beat this table speedup, but vs 100× still lags by 1  order(s) of magnitude.
- Correctness anchor (informational): T=100 KL final values ours=2.889124888e+03 R=2.887732184e+03 relative diff=4.82e-04(⚠ exceeds 1e-6, needs recheck)

