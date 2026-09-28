# 调研报告 08：既有调研文档事实核查审计报告
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 审计日期：2026-09-28。对照 Crossref、PubMed E-utilities、GitHub raw/API（当前 HEAD）、crates.io、CRAN、PMC、Europe PMC 与本地 R/rustc 核查 docs/ 全部承载性主张。审计者不可修改文件——本报告即修正依据（对应修正已由主线执行）。

## §1 分歧裁决（可直接引用的规范引用串）

| # | 事项 | 裁决 |
|---|---|---|
| 1 | **Medo DOI** | **`10.1038/s41467-024-53711-6` 正确**；`-53574-6` Crossref 404 不存在。Nat Commun 15:9467 (2024)；PMID 39487150、PMC11530434。原 02 报告引用串已修正。 |
| 2 | **Degasperi 文章号** | **`eabl9283` 正确**；`abl9111` 不存在。Science 376(6591):eabl9283, 2022-04-22；PMID 35949260。 |
| 3 | **Jiang/Wu/Rozen** | 规范引用 = **Brief Bioinform 26(1):bbaf042, 2025**（epub 2024-11-22）；doi:10.1093/bib/bbaf042；**PMID 39910776**、PMC11798676。**PMID 39487150 属 Medo**。建议统一标 2025（epub 2024）。 |
| 4 | **MuSiCal** | 核实：Nat Genet 56:541–552 (2024), doi:10.1038/s41588-024-01659-0（PMC10937379）。 |
| 5 | **PCAWG 2020** | Alexandrov, Nature 578(7793):94–101, doi:**10.1038/s41586-020-1943-3**（PMID 32025018）。**注意 `10.1038/s41586-020-2623-x` 404——若在任何材料出现必须替换**。Li Y, Nature 578:112–121, doi:10.1038/s41586-019-1913-9 核实（PMID 32025012）。 |
| 6 | **Everall** | 已正式发表：Nat Genet 58(3):570–581, 2026 Mar（epub 2026-02-13）, doi:10.1038/s41588-025-02474-x, PMID 41688639。摘要确认 **10,983** 患者、16 癌型、**134 签名、26 个 COSMIC 新增**、SV 参考集。 |
| 7 | **Steele** | 核实：Nature 606(7916):984–991 (2022), doi:10.1038/s41586-022-04738-6；9,873 TCGA、21 CN 签名。 |

## §2 逐主张核查表（摘要）

| 主张 | 结论 | 备注/修正 |
|---|---|---|
| SPMG：`scripts/MutationMatrixGenerator.py` ~4,057 行；indel ~:1169–2100；BSD-2 | **核实** | 精确 4,057 行；`catalogue_generator_INDEL_single` :1169、`forward_homology` :1486–1518、`dinuc_tsb_ref` :484；BSD-2-Clause（Bergstrom/Alexandrov Lab）；2026-09-22 推送 |
| MuSiCal：`nnls_likelihood_bidirectional`、LTH 0.001、SIGS_ASSOCIATED 无 SBS7、无 MWPruning/MDL | **核实** | `nnls_sparse.py:201`（thresh_backward=0.001, per_trial=True）；relaxed 在 :434（:410/:461 为 LOO 块，行号漂移）；`utils.py:72` 三组、无 SBS7；MWPruning/MDL 0 命中 |
| mSigAct：χ²₁ LRT；nbinom.size 8/50/100；GPL-3 | **核实（分支条件）** | 默认分支 `v3.0.3-branch`；**旧 `master` 行为不同（multinom 默认、nbinom.size=5）**——复刻以默认分支为准 |
| Sonata：存在、MIT、cornet.py 模型形式 | **核实** | `compute_exposures = exp(α + β + sig_emb @ sample_emb.T).T` 精确一致 |
| COSMIC v3.6 镜像：文件名模式、RNA-SBS 仅 GRCh37、SV 仅 GRCh38、列数 | **核实 + 修正** | **ID 与 CN 也仅 GRCh37**；小鼠/大鼠仅 SBS+DBS。列数：SBS 102 列（Type+101）、DBS 23、ID 26、CN 27、RNA-SBS 6、SV 13 |
| CN48/SV32 标签 | **核实** | 48/32 全部标签精确一致 |
| SUITOR：PLoS CB 18(4):e1009309 2022；entry-wise CV；ECM≡KL-MU；300 初始化 | **核实** | 原文原句引用确认 |
| sigminer：CRAN "MIT + file LICENSE"；extdata v3.1；`py_path` 硬编码；Broad BSD-3 头 | **核实** | `R/sig_extract.R:38`；extdata 34 文件（**无 SIGNAL 命名文件**） |
| rust-NMF：GPL≥2；76×/~215–280× | **核实** | LICENSE 文件权威；README 16 线程表与我们的数字一致 |
| extendr/savvy/rextendr 版本 | **修正** | **extendr-api 最新 = 0.9.0（2026-04-16 unyanked）**；0.8.2 是 0.8 系末版。savvy 0.11.0 ✓；rextendr 0.5.0 ✓ |
| CRAN 政策引文 | **核实 + 措辞告诫** | 原句确认；**无字面"安装时禁止联网"条款**——实际是"外部资源最小化/https/优雅降级/预编译下载为最后手段需 CRAN 同意"。结论（vendor 一切）不变 |
| twobit crate 0.2.2, MIT, jbethune | **核实** | 2026-03-27 更新 |
| HRDetect 系数 | **核实** | means/sds/weights/intercept −3.364 全部精确 |
| 抽查 5 个 PMID | **核实 5/5** | 35949260/31278357/42351273/41688639/35668106 全对 |
| 本地环境 | **核实** | R 4.5.2；rustc 1.97.1；rextendr 0.5.0；sigminer 2.3.1；MutationalPatterns 未装 |
| （加查）SPA 默认 cosmic_version=3.6、强制背景签名、排除字典 :376–410、probabilities :1694 | **核实** | decomposition.py:257/:272/:376–410（**14 个子群含 Treatment_signatures，此前总结漏记**） |
| （加查）Cornet 预印本 | **核实** | Europe PMC PPR1324264；2026-09-21；doi:10.64898/2026.09.14.751548 |

## §3 其他发现

1. 02 报告 Medo DOI 错误（唯一硬伤）——已修正。
2. 00/04 extendr "最新版" 过时（0.9.0）——已修正。
3. **per-build 参考库可用性过度概括**（05 §1、ARCHITECTURE §4.2、ROADMAP M4 的"五类 × 7 builds"不成立）——已修正 05 并在架构 v2 中调整捆绑计划（缺失 build 自行派生或跨 build 标签转换）。
4. CRAN 网络措辞软化——已修正。
5. Jiang 年份统一为 2025（epub 2024）——已修正 00。
6. mSigAct 分支脚注——已修正 04。
7. 细节：02 排除清单漏 `Treatment_signatures` 子群；00 提及 sigminer extdata 有 SIGNAL 未证实（34 文件无 SIGNAL 命名）。
8. 未复核（低风险标注）：Wu 2022 DOI 形式、BayesPowerNMF/BASCULE DOI、03 报告其余 ~60 PMID（抽查 5/5 通过）、DBS78 组序细节、SPMG "~13,700 LOC" 包总计。

## §4 总体结论

档案在**源码工程层异常准确**（抽样的每条工程主张，包括文件行号、默认值、系数、列数，均与当前上游逐位一致）。作为实现参考前的必需修正共 4 组（§3.1–3.4），均已执行。其余可按原样信任。
