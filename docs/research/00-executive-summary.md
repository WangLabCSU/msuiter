# msuiter 调研执行摘要（Executive Summary）
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研时间：2026-09-27。方法：GitHub issue 考古（WangLabCSU/msuiter#1、ShixiangWang/sigminer 全部 open issues）、SigProfiler 全家桶源码精读、5 路并行深度调研（提取方法 / 拟合推断 / 应用场景 / 源码逐仓审计 / 标准数据许可）、PubMed + bioRxiv + 学术数据库广泛检索。
> 本目录所有报告均为一手核实（标注 [V]=读源码/全文验证，[U]=未完全验证），可直接作为论文 Related Work / Methods 素材。

## 1. 项目定位（来自 msuiter#1 与 sigminer#456 v3 roadmap）

- 目标：**性能对齐 SigProfiler、整合领域最优算法的下一代 mutational signature 生态系统**。
- 技术路线：Rust 计算底层 + R 包用户接口（rextendr 桥），模块化、正交、DRY、TDD。
- 论文导向：三大板块 —— ①架构与实现 ②性能与 benchmark ③应用场景案例研究。

## 2. 方法学现状（详见 01/02 报告）

### 提取（de novo extraction）
| 方法 | 核心思想 | 状态 |
|---|---|---|
| SigProfilerExtractor | KL-MU NMF + 100 次多项式重采样/rank + Hungarian 共识聚类 + 稳定性选择 | 行业金标准，慢（2,500 次 NMF，天级） |
| SignatureAnalyzer (PCAWG) | ARD 证据最大化自动定 K（L1W.L2H），KL-MU + 先验收缩 | 无需 rank 扫描但易分裂平坦签名 |
| MuSiCal / Sonata | 似然稀疏 NNLS 拟合 + mvNMF（logdet 体积正则）+ Cornet（相关性感知） | 当前方法学前沿（Park 实验室） |
| SUITOR | entry-wise 10 折 CV 选 K（ECM≈KL-MU） | K 选择校准最佳 |
| mSigHdp | 层次 Dirichlet 过程 | 罕见签名敏感性最佳，慢 |
| signeR / BayesPowerNMF / BASCULE | 贝叶斯（Gibbs / power posterior / SVI） | 后验不确定性，MCMC 慢 |
| 深度学习 | MUSE-XAE / SigNet 等 | **无一成为主流赢家**，暂不投入 |

**关键实证**：rust-NMF 证明"NNDSVD 初始化是魔法而非算法"（NNDSVD+25 次迭代 ≈ 随机初始化+数百次）；KL 乘法更新对计数数据是统计正确的 MLE（多项/Poisson 等价）。

### 拟合（fitting / attribution）
- Medo 2024 Nat Commun（12 工具）：**SigProfilerAssignment 与 MuSiCal 高计数下最佳；剪裁参考目录有害；平坦签名（SBS1/5/40）系统性低估；拟合误差 ∝ 1/√N 且与签名 Shannon 熵相关**。
- Jiang et al. Brief Bioinform 26(1):bbaf042（2025，epub 2024-11；13 工具）：**PASA**（前向搜索 + LRT）DBS/ID 第一，MuSiCal SBS 第一；核心洞见——**重建相似度指标无信息量**（99/100 胃癌样本存在比真值重建更好的错误归因），必须用 precision/recall 评估。
- 似然损失理论：多项似然（KL）是计数数据的正确 MLE；cosine 只能做报告不能做推断；QP 与 NNLS 实质差异仅在 Σe=1 等式约束。
- **三个论文级空白**（我们可占领）：
  1. 暴露量 CI 的覆盖率从未被任何工具验证（Medo 明确提出此 open question）；
  2. 无任何工具对暴露量做成分数据分析（CoDA/log-ratio）的正式统计；
  3. <100 突变的 panel/ctDNA 情形没有有原则的通用拟合工具（SigMA 只覆盖 SBS3/HRD）。

### 后处理
- 每突变分配概率（proportional allocation）无人做条件化与不确定性传播；per-signature TSB/RTT 检验无人原生支持；signature timing（TrackSig/CloneSig）与治疗史解卷积是近零竞争领域。

## 3. 应用全景（详见 03 报告）

11 大类应用 → Top-10 交付工作流：HRD 临床复合报告、atlas refit、暴露归因流行病学、五类变异联合提取（Everall 2026 首个 SV 参考集）、修复缺陷诊断（MSI/POLE/MUTYH via 签名）、治疗史法证、正常组织低计数模式、RNA-seq 签名模块、ctDNA 模式、临床前毒理跨物种。

## 4. 工程事实（详见 04/05 报告）

- **性能热点**：SigProfilerMatrixGenerator 纯 Python 逐字节循环是全栈最大 CPU 黑洞 → Rust 化收益最大；其"染色体预编码字节串（base+strand 单字节枚举）"设计可直接 mmap 移植。
- **通道语义必须逐位复刻**（bit-compatibility targets）：SPMG 的 ID83 分类（repeat 游走 + microhomology 最长匹配 + 前向优先平局规则 + Q-链歧义）、SBS 6144/1536 主索引、DBS Q-flag 翻转、CN48/SV32 精确定义（48/32 行标签已全文抓取存档）。
- **通道顺序陷阱**：SBS96 两种排序并存（COSMIC flank-major vs Nature2013 substitution-major），必须按标签规范化（MutationalPatterns issue #60 教训）。
- **许可地雷**：rust-NMF(GPL≥2)/RcppML(GPL≥3)/mSigAct(GPL-3)/NNLM(BSD-2 可用)/SPMG(BSD-2 可用)/Sonata(MIT 可用)/sigminer bayesianNMF.R(Broad BSD-3 可移植) → **核心从论文公式干净重实现，避免 GPL 传染**。
- **COSMIC 数据**：官方 T&C 禁止再分发；全领域实践是捆绑 Alexandrov 实验室 BSD-2 镜像（SigProfilerAssignment repo）。方案：bundle（溯源钉死到该镜像）+ 按需更新。
- **CRAN**：禁止安装时联网 → cargo vendor 模板（string2path 已验证可行）；r-polars 只发 GitHub/r-universe。Rust 依赖精简（faer 巨大，可自写 SVD/Cholesky 避免）。
- **Rust 生态**：extendr-api 最新 0.9.0（2026-04-16，0.8.2 为 0.8 系列末版；含 faer/ndarray 集成）、savvy 0.11、twobit crate 0.2.2（纯 Rust 2bit 基因组读取器，随机访问）→ 基因组上下文提取可完全绕开 BSgenome 的 3GB 内存。S7 类系统（RConsortium）：CRAN 0.2.2 稳定、ggplot2 4.0 已采用、104 个 CRAN 包、Bioc2026 主题演讲——R 包层采纳安全（详见报告 06）。

## 5. 竞争格局一句话

SigProfiler=Python 金标准但慢且封闭；R 侧 sigminer/MutationalPatterns 纯 R 慢、COSMIC 版本旧；MuSiCal=Python 前沿方法；**没有人提供 Rust 级性能 + 统计推断完备 + 五类变异统一 + 应用工作流的 R 生态系统** —— 这就是 msuiter 的生态位。

## 6. 文档索引（全库）

**调研报告（本目录，均为快照性质）**
- [01-extraction-methods.md](01-extraction-methods.md) — 提取方法全景与 NMF 引擎动物园（含更新方程）
- [02-fitting-inference.md](02-fitting-inference.md) — 拟合、归因、不确定性、后处理分析
- [03-applications.md](03-applications.md) — 应用文献与场景 → 工作流模块需求映射（含 PMID）
- [04-source-audit.md](04-source-audit.md) — 逐仓源码审计（算法精确到 file:line、许可证）
- [05-standards-data.md](05-standards-data.md) — COSMIC 许可、通道标准、基因组读取、可视化、benchmark、CRAN 政策
- [06-s7-class-system.md](06-s7-class-system.md) — S7 类系统现状、设计模式与方法框架蓝图
- [07-algorithm-zoo.md](07-algorithm-zoo.md) — 分层算法动物园完整盘点 + 自研方法机会清单
- [08-fact-check-audit.md](08-fact-check-audit.md) — 全档案事实核查审计（分歧裁决）

**活文档（唯一生效口径）**
- [../ARCHITECTURE.md](../ARCHITECTURE.md) — 架构 v2.2（决策 D1–D16、分层、科学契约）
- [../ROADMAP.md](../ROADMAP.md) — 双轨路线图 v3（v0.1/v0.2/v1.0 + G0–G3 组织门）
- [../CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) — 功能覆盖矩阵（完备性权威检查表）
- [../reviews/00-synthesis.md](../reviews/00-synthesis.md) — 五专家评审裁决（01–05 为证据原文）
