# B2 · SBS 目录生成 bench（M1s 验收门，ARCHITECTURE §8：10⁶ 突变 SBS96 vs SPMG ≥50× 且 <5s 单核）

重跑：`python3 bench/m1s/sbs/gen_fixtures.py && Rscript bench/m1s/sbs/run_bench.R`。
同一合成参考（2×2.5Mb，catalog/tests/genome fixture.rs 放大版，含 N blocks）、
同一 10⁶ SNV：我方 = `ms_tally()` S7 端到端（单线程；次口径 FFI 层 `.ms_tally_rust`）；
SPMG = SigProfilerMatrixGenerator 1.3.6 标准调用（自定义基因组 install + VCF 输入，
一次产出全套 9 种矩阵——工作量大于我方 SBS96 单表，判据偏保守，见注记）。

## 环境

- date: 2026-09-30 08:21:00 CST
- R: R version 4.5.2 (2025-10-31) (aarch64-apple-darwin20)
- python/SPMG: SigProfilerMatrixGenerator 1.3.6 (bench/m1s/.venv)
- host: aarch64-apple-darwin20（Apple Silicon；功耗状态不可控，数字为该钉硬件口径）

## 数字（主臂 = dbsfree：同样本同染色体最小间隔 2、无重复记录，双侧逐条对齐）

- 我方 ms_tally 3 次（s）：3.6360, 3.5840, 3.6000 → **median = 3.6000 s（<5s ✓）**
- 我方 FFI 层 3 次（s）：3.6520, 3.6410, 3.6790 → median = 3.6520 s（S7−FFI 差 ≈ -52.0 ms，噪声级——S7 装配不构成可感开销）
- SPMG 主臂单次墙钟 = 9.7 s（sanity 探针 0.055 s；单次口径——分钟级不复跑）
- **speedup = 2.7×；判据 ≥50× 且我方 <5s：FAIL**
- **正确性锚（主臂逐格）**：ours sum=1000000 = SPMG sum=1000000，逐格差 = 0（✓ 完全一致）

## 次臂 dense（自然相邻密度，(chrom,pos,sample) 去重后对齐）

- 记录数 = 951686；我方判为 DBS 的成员数 = 166104（排除出 SBS96）；我方 median = 2.871 s；SPMG = 45.6 s
- 总量对账：SPMG sum−我方 sum = 166104，与 DBS 成员数相等 = TRUE（且逐格差均 ≥0：SPMG 1.3.6 把 DBS 对成员一并计入 SBS96）

## 语义探针（sanity 100 变异，含 2 对同样本相邻 + 1 对跨样本相邻）

- 双侧路由一致：同样本相邻对均判为 DBS 类（我方 ledger 4 条 `dbs`；SPMG stdout 报 2 DINUCs）；跨样本相邻对双侧均保持 SBS。
- **SBS96 计入策略不一致（P0 发现）**：SPMG 1.3.6 把 DBS 对成员一并计入 SBS96（sanity sum=100 vs 我方 96，差和恰 = 4 个 DBS 成员；最小探针：1 对相邻 + 1 孤立 → SPMG SBS96=3 且不产出 DBS78）。我方按 U-M1s-09 审计语义（dinuc_sub==1 排除出全部 SBS 矩阵）实现。**审计所依据的上游行为与1.3.6 实测不符**——需 PI 复核 docs/research/04 所锚定的上游版本/代码路径，并在 M1c 的 DBS78 单元裁决取舍（本 bench 不改包代码）。

## 口径注记（如实）

- SPMG 侧含 VCF 解析 + 9 种全套矩阵计算与写出；我方仅 SBS96 单表、输入在内存。
  按工作量修正（SPMG 仅 SBS96）speedup 只会更高——本表数字对判据偏保守。
- 速度形态：SPMG 主臂（dbsfree）9.8s vs dense 臂 46s——其耗时被重复记录
  去重/相邻对（DINUC）处理路径主导；干净合成输入上 1.3.6 远低于 ≥50× 预算
  隐含的「分钟级」基线。我方 3.7s 含 R→FFI 的 10⁶ 行字符列传递开销
  （内核纯核口径在 HEAD 不可得，见下）——两侧预算假设均需按本表修正。
- SPMG 会在 <vcf_dir>/input/ 缓存逐染色体转换产物；spmg_run.py 每次运行前
  清除（否则静默消费陈旧记录集——本 bench 排障中的实测发现）。
- SPMG 1.3.6 生成入口以硬编码 CHECKSUMS 白名单校验基因组，自定义基因组无法通过
  （上游限制）；spmg_run.py 在运行时把本地安装产物的 md5 注册进该 dict，
  不修改任何上游文件，矩阵生成代码路径全为原装。
- SPMG 1.3.6 会整条丢弃完全重复记录（与样本无关、按整行比较；dense 臂生成期已按
  (chrom,pos,sample) 去重对齐），以及上节的 DBS 计入策略——两条上游语义差异
  均为本 bench 的发现，已列入遗留清单。
- 「Rust bin 纯核」口径在 HEAD 不可得（tally 装配入口为包私有模块，包代码不可为
  bench 改动）；FFI 层次口径即纯核上界（含 mmap + R 侧校验），已单列。

