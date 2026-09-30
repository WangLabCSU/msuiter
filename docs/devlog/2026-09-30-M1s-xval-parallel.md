# Devlog · 并行 tally 优化 + sigminer/MP 交叉验证（2026-09-30）

## 并行 tally 优化（U-M1s-05 架构的兑现）
- (chrom, sample) 分区级 per-call 池并行（分区=独立单元，A7 契约）；worker 各持独立 TwoBitGenome 句柄（catalog context 需 &mut seek）；输出/ledger 按索引回写——**语义逐位不变**，threads∈{1,4,16} 双层三组 identical。
- 关键调度修正：replicates 式 threads×4 过订阅会把少分区批串行化（首版 8 线程零加速）→ 整 wave chunk（waves=⌈jobs/workers⌉ clamp 1..16）→ 核时 1.98s(1T)→1.16s(4T)。
- 端到端如实：bench 4 分区场景 3.73→2.95s（1.26×），受串行前置（R marshalling ≈0.7s + 排序 + ledger 渲染）与 debug 构建限制；**更多分区（真实多样本多染色体）扩展更好**；单分区依规约退化顺序。纯核口径 1.7×。
- FFI 签名加 `n_threads`（必要级联，ffi-probes.R + wrappers 同步）；中断轮询边界随分区调整，单分区退化保留原粒度。

## sigminer/MP 玩具交叉验证（M1s 验收门最后一件）：**PASS**
- **四方逐格一致**：msuiter vs sigminer 2.3.1 vs MutationalPatterns 3.20.1 vs 独立 base R 重算——264 条玩具 SNV、3 样本、真实 hg19 三段窗口，96×3=288 格 6 组两两对拍 0 不一致。
- 防假一致三重：标签集合先比再对齐（MP 是 type-major 序，按位置比必错）、96 通道定向全覆盖、第三方重算不同源。
- **我方独有优势实证**：REF-vs-基因组校验（故意放坏记录：msuiter 按 ref_mismatch 跳过，sigminer/MP 均把坏记录计入伪通道）——安全语义差异如实记录不改。
- 固化：test-xval-sigminer.R 进 repo-mode 测试（skip_if_not_installed，CI check job 天然跳过、repo-mode 走 RSPM 二进制）；Suggests += sigminer + BSgenome.Hsapiens.UCSC.hg19（零 Imports）。
- 上游边角记录：sigminer keep_only_matrix 返回转置、极小变异集 Fisher 晦涩报错；MP mut_matrix 须 DNAStringSetList——均入 result.md。

## 状态
- 电池：Rust 12 套件双工具链、testthat **1358 PASS**、check 0/0/1NOTE、docs-sync 绿。
- M1s 验收门余项：**速度预算口径裁决（等作者）** + sigminer 玩具交叉验证（本批完成）→ 全部完成后 M1s 里程碑关闭。
