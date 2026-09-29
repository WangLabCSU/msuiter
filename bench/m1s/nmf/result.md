# B1 · NMF bench（M1s 验收门，ARCHITECTURE §8：96×1000, k=10, 100 iter vs R NMF ≥100×）

重跑：`Rscript bench/m1s/nmf/run_bench.R`。同 V/W0/H0（CSV 逐字节交换）、同 T=100；
双侧协议：预热 1 次 + 计时 3 次取中位。我方 = driver 纯核（`fit_kl_with_init`，单线程）；
R = NMF 0.28 brunet（外部初始化 W0/H0，stopconv=1e6，maxIter=100 精确控制）。

## 环境

- date: 2026-09-30 06:56:13 CST
- R: R version 4.5.2 (2025-10-31) (aarch64-apple-darwin20)
- NMF: 0.28
- BLAS: /System/Library/Frameworks/Accelerate.framework/Versions/A/Frameworks/vecLib.framework/Versions/A/libBLAS.dylib | LAPACK: /Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/lib/libRlapack.dylib
- rustc/cargo: rustc 1.92.0 (ded5c06cf 2025-12-08)
- host: aarch64-apple-darwin20（Apple Silicon；功耗状态不可控，数字为该钉硬件口径）

## 数字

- 输入：V 96×1000 整数计数（可分合成，seed=20260928）；init W0/H0 k/1024 网格（seed=20260929）
- 我方 3 次（ms）：205.904, 204.722, 206.111 → median = 205.904 ms
- R brunet 3 次（s）：0.666, 0.381, 0.471 → median = 4.71e-01 s
- **speedup = 2.3× ；判据 ≥100×：FAIL**
- 信息项：每迭代斜率 ≈ 2.053 ms/iter（T=1 中位 2.648 ms vs T=100 中位）；fit_kl_with_init 每迭代含目标轨迹的 kl_objective（第 3 次 WH matmul + 96k ln，U-M1s-14 数值协议所需），R brunet 基线不逐迭代算目标——同粒度拟合比较会好于本表 speedup，但与 100× 仍差 1 个量级以上。
- 正确性锚（信息项）：T=100 KL 终值 ours=2.889124888e+03 R=2.887732184e+03 相对差=4.82e-04（⚠ 超 1e-6，需复核）

