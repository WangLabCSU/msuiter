# bench/m1s · M1s 验收门 bench 汇总（U-M1s-13 配套；钉硬件口径，不进 CI）

日期：2026-09-30 · 本机 Apple M5 / macOS 26.6.2 / R 4.5.2 / rustc 1.92 /
SPMG 1.3.6（bench/m1s/.venv）。功耗状态不可控——数字为该钉硬件单次会话口径；
各分项一键复跑命令见 `README.md`，全量数字见 `nmf|sbs|nnls/result.md`。

## 判据结论（ARCHITECTURE §8 预算行 / ROADMAP M1s 验收）

| 预算行 | 判据 | 实测 | 结论 |
|---|---|---|---|
| 目录生成 SBS96（10⁶ 突变） | ≥50× SPMG 且 <5s 单核 | 2.6×（我方 3.73s vs SPMG 9.82s）；<5s ✓ | **speedup FAIL；<5s PASS** |
| 正确性锚（SBS96 逐格，10⁶ dbsfree 主臂） | 逐格一致 | 差 = 0 格（sum 双侧 1,000,000） | **PASS** |
| NMF KL（96×1000, k=10, 100 iter） | ≥100× R NMF | 2.3×（我方 205ms vs brunet 0.47s） | **FAIL** |
| 批量 NNLS（101×10³, k=10） | ≥10× scipy 逐样本 | 1.8×（我方 6.7ms vs scipy 11.2ms） | **FAIL** |

**总评：三条速度预算行在名义点位全部未达（FAIL），正确性锚全部 PASS。**
ROADMAP M1s 验收行「目录生成 ≥50× SPMG；NMF ≥100× R NMF」按本 bench 不成立——
v0.1 发布门前需要 PI 裁决：修内核（NMF/NNLS 的每解分配与 NMF 的逐迭代目标
轨迹）、修预算口径（见下）、或降级验收承诺。

## 关键数字

- **SBS**：我方 `ms_tally()` S7 端到端 3.73s（FFI 层 3.74s，S7 装配 ≈ 噪声级）；
  SPMG 1.3.6 标准调用（VCF 输入 + 9 矩阵全套）9.8s（dbsfree 臂）/ 46s（dense 臂）。
  正确性：10⁶ 主臂 96×2 逐格差 0；sanity（含相邻对）差和恰 = 4 个 DBS 成员；
  dense 臂总量对账 SPMG−ours = 166,104 = 我方 DBS 成员数（精确）。
- **NMF**：我方 `fit_kl_with_init` 204.7ms（2.04ms/iter，含逐迭代 kl_objective
  轨迹 = 第 3 次 WH matmul + 96k ln；R brunet 基线不逐迭代算目标——同粒度
  比较会好于 2.3× 但与 100× 仍差 1 个量级以上）。T=100 KL 终值相对差 4.8e-4
  （信息项；96×20 协议等价已由 U-M1s-14 证明）。
- **NNLS**：我方 6.73ms vs scipy 11.1ms；解逐格一致（max|Δx| = 3.8e-11，
  SSE 相对差 3.7e-16）。小规模 k=10 下两侧同为原生 Lawson-Hanson，python
  循环不构成基线劣势。

## P0 / 发现（遗留清单）

1. **SPMG 1.3.6 把 DBS 对成员一并计入 SBS96**（且不产出 DBS78；最小探针：
   1 对相邻 + 1 孤立 → SPMG SBS96=3）。我方按 U-M1s-09 审计语义（dinuc_sub==1
   排除出全部 SBS 矩阵）实现。**审计依据的上游行为与 1.3.6 实测不符**——
   PI 需复核 docs/research/04 锚定的上游版本/代码路径，M1c DBS78 单元裁决。
2. **SPMG 1.3.6 会整条丢弃完全重复记录**（sample 盲、整行比较；本 bench 夹具
   已按 (chrom,pos,sample) 去重对齐）——我方 tally 对重复记录无去重语义，
   M1c 需明确策略（ledger 已可见 per-record 去重钩子位）。
3. **SPMG 生成入口 CHECKSUMS 白名单**使自定义基因组不可用（上游限制）；
   bench 在运行时注册本地 md5 绕过（零上游文件改动，计算路径原装）。
4. **SPMG 的 `<vcf_dir>/input/` 转换缓存**会在重跑时静默消费陈旧记录集
   （spmg_run.py 已每次清除）。
5. **「Rust bin 纯核」口径在 HEAD 不可得**：tally 装配入口 `mod tally` 为包
   私有，包代码不可为 bench 改动；以 FFI 层口径替代（含 mmap + R 侧校验 +
   10⁶ 行字符列传递）。若需内核纯核数，U-M1c 可考虑 `pub mod tally` + driver。
6. **性能预算的基线假设系统性偏乐观**：R NMF brunet / scipy nnls 均已是原生
   C 内核，「R/Python 基线」不再是数量级劣势；msuiter 的 ≥10×/≥100×/≥50×
   需重校（修内核分配/轨迹开销、或改承诺为绝对延迟口径）。

## 口径

- 协议统一「预热 1 次 + 计时 3 次取中位」（SPMG 为分钟级单次墙钟，如实标注）。
- 我方计时全部走未改动包代码的真实路径；driver 均为独立 workspace、仅 path
  依赖 msuiter-engine（nmf/nnls）；包树零改动。
- bench 不属于 CI（ROADMAP：CI 只放 sanity bound）。
