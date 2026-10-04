# U-M7 前置设计备忘：ms_simulate() 第一版（场景目录模拟器）

日期：2026-10-05 凌晨随批。范围：CAPABILITY-MATRIX L-G "目录模拟器：基因组真实放置、场景生成器、NB 校准采样 | SigProfilerSimulator/SynSig/Jiang | ms_simulate() | M7（内核 M1s）"——**第一版交付变异计数层**（字典+暴露→目录）；基因组真实放置（VCF 级）记 ⏳ M7 全集。

## §1 冻结设计（与 M3b 校准驱动同律，包内零分叉）

```r
ms_simulate(signatures, exposures, arm = c("multinomial", "poisson", "nb"),
            size = 8, seed = 1)
```
- `signatures`：m×k SBS96（或 DBS78）规范序矩阵；`exposures`：k×n 计数或份额（列和>0 即按计数、列和≈1 即按份额自动判定，倍数 = 目标负荷 `burden`）。
- **生成律**（与 calibrate.rs GenerativeArm 逐字对齐）：multinomial = 恰 N 流字多项重采（R 侧 rmultinom，M3b sanity harness 同律——基准/测试共用语义）；poisson/nb = 逐通道 gamma-Poisson 混合（NB(μ_c, κ)）。
- 确定性：单一 seed 顺序按样本列；**与 M3b 校准驱动不同流**（那是 Rust PCG64 面本 R 面用 base RNG——两.face 都为确定性但流无关，文档声明）。
- 返回 MsCatalog（channels/labels/samples 原样；provenance 记 arm/size/seed/burden）。
- DBS78 空间同面（palette 无关；标签表校验同 io）。

## §2 边界（如实）

- 无基因组放置（不计上下文真实分布/外显子靶区）——合成目录 = 通道空间直接采样；VCF 级模拟 ⏳ M7。
- 多项近似的诚实声明与 ms_downsample 同款（有放回近似）。
- NB 臂的 R 侧实现 = rgamma-rpois 混合（与 resample.rs gamma_variate+poisson_variate 同算法族不同实现——测试层统计性质对拍：均值/方差比 = κ+1）。

## §3 验收锚

- 【逐位/数值】：seed 逐位复现；multinomial 列和恰 = burden；NB 臂均值≈μ·N（4SE）且方差/均值≈1+N/κ（NB 理论比）；份额/计数自动判定；
- 【工程】：错误路径全结构化（i/j/c 三段—— viz 教训）；SBS96/DBS78 规范序校验；
- bench/jiang 的合成器与本面语义同源声明（备忘 §1）。
