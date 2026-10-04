# msuiter 路线图（ROADMAP）—— v3（双轨制 + 组织行动门）

> v3（2026-09-28）：依五专家评审裁决（[reviews/00-synthesis.md](reviews/00-synthesis.md)）重构——原 M0–M8 估算被系统性低估 ~3× 且无最小可采纳版本切线；本版改为 **版本双轨制**，并把需要作者本人推进的组织行动项显式化为 G 门。
> 原则不变：每个交付物都是可发布状态；TDD 先行；论文三板块素材与里程碑绑定。
> 可执行分解（工作单元 / 依赖图 / v0.1 逐周排程 / G 门行动 / 启动检查单）：[IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md)。

## 版本轨道总览

| 版本 | 周期（现实估算） | 内容 | 发布 |
|---|---|---|---|
| **v0.1** | ~6 周 | 最小可用核（见 M0+M1s） | r-universe + GitHub Releases |
| **v0.2** | 再 ~12 周 | 完整 SBS/DBS/ID 方法链 | r-universe |
| **v1.0** | 再 ~3–4 月 | MSU-Fit 校准 + HRD 报告 + 发布工程 | CRAN 提交启动 |
| **v1.x** | 滚动 | 见"推迟清单" | 滚动 |

单人 + AI agents 的诚实总量：**到投稿级 benchmark 完备约 12–18 个月**（编辑评审 #3）。

## 组织行动门（G 门——非文档工作，需作者推进）

- **G0（立即，2 周）**：先导覆盖实验——2 个竞品工具 × TMB 网格的名义 vs 实际覆盖率。**kill-criterion 门**：结果决定论文 headline 走 Framing A（校准统计）还是 Framing B（生态）。先于一切论文叙事写作。
- **G1（M1s 前）**：找到 co-maintainer（bus factor + CRAN + 审稿三重需要）。
- **G2（M3b 期间/结束前）**：统计学 co-author（conformal/CoDA 理论）+ 临床/队列合作者（治疗记录 / RNA-only / FFPE panel 三选一）锁定；否则案例注定装饰性，主动接受 GB/NC 上限。
- **G3（每季度）**：竞争格局复核（Cornet/MuSiCal/SPA 动态），重估 kill criteria。

---

## v0.1（~6 周）

### M0 · 工程地基（2 周，原估 0.5–1 周被评审否决）

- [x] rextendr 脚手架 + Cargo workspace（依赖预算收缩版：extendr-api default-features=false、ndarray、rayon、memmap2；**无 rand**）
- [x] **M0 spike（一周内出数）**：真实 cargo vendor + xz 字节数 + rustc 1.71 三平台构建证明 + twobit 两案（crate over Cursor\<Mmap\> vs 自研）byte-swap/大端验证 → ADR（ADR 0001/0002；macOS arm64 已证，Linux/Windows 构建证明由 CI 承接）
- [x] **S7 类骨架（无 .state）**：MsVariants/MsCatalog/MsSignature/MsFit/MsRefDb/MsEngine/MsBenchmark；互引一律快照摘要；saveRDS/load 后全泛型行为测试（平铺前缀命名 classes-*.R，见 ARCH §3.1 实现注记）
- [x] 引擎注册表（含 certified/engine_version/contract_version 字段）+ 契约测试套件
- [x] `data-raw/build_channels.R` 通道注册表单一事实来源 + docs-sync CI（drift 即红）（docs-sync 脚本已绿，CI 接线移交 U-M0-07）
- [x] **自研 RNG 模块**：PCG64 + SplitMix64 流布局 + 跨版本 golden 测试（canonical post-step pcg64；tools/rng-kat.py 独立 KAT）
- [x] `.github/`：3 OS × {release, oldrel, R-4.3(Linux), devel} 矩阵、rcmdcheck --as-cran、cargo test/clippy/deny(ban)/audit、valgrind+ASAN scheduled、dependabot、codecov（U-M0-07 完成；`tools/ci-selfcheck.py` 全部接线断言 PASS）
- [x] 治理文件：CONTRIBUTING（含第三方引擎接入清单）、CoC、issue/PR 模板（含 FFI-surface 变化与 fixture 刷新检查项）、README 骨架、NEWS.md、`_pkgdown.yml`（U-M0-08 完成）
- [x] `ms_sitrep()`；FFI 硬契约落地（column-major/NA/Result 错误/中断/per-call 线程池）（docs/ffi-surface.md 冻结工件 + 漂移守卫已建）

**验收**：check 全绿；S7 校验测试过；RNG golden 过；vendor 体积数字进 ADR。

### M1s · v0.1 引擎与目录（4 周；完整「引擎与目录」拆为 M1s/M1c/M2，M1c/M2 在 v0.2 续）

- [x] engine：KL-MM MU、NNDSVDa（q≥3 + exact Gram-SVD 对照）、Lawson-Hanson NNLS（pivot LDLᵀ + KKT 断言）、多项重采样、**线程不变性 identical() 测试**（U-M1s-01–05；KL 对拍 vs R NMF brunet PASS，‖ΔW‖≈1e-15）
- [x] catalog：SBS96/192/384/1536 + DBS78 + **MNV/complex 路由模块**（skip ledger）+ 2bit 快路径（U-M1s-06/07/08；SPMG 源码逐行对拍 + 审核独立重推）
- [x] 金标准夹具（**语义逐位**）：SPMG SBS/DBS/MNV 对拍、sigminer/MP 玩具交叉验证（SPMG 对拍 = 手推 golden + 上游源码逐行核对 + 双端布局夹具体系；sigminer/MP 玩具交叉验证并入 M1s 验收门 bench）
- [x] `ms_variants/ms_tally/ms_extract`（单方法）+ `print/format`（U-M1s-09/10/11/12；工作流文法三环贯通）
- [x] KL 数值协议等价对拍：vs R NMF brunet（固定平台一次性实验，容差 1e-10）（U-M1s-14 PASS：‖ΔW‖F/‖W‖F ≈ 1e-15，tools/kl-crosscheck 一键复现）

**验收（v0.1 发布）**：目录生成 ≥50× SPMG（钉硬件 bench；CI 只 sanity bound <5s）；NMF ≥100× R NMF；夹具全绿；r-universe 可安装。

---

## v0.2（再 ~12 周）

### M1c · 目录完备 + ID83（3 周）

- [x] ID83（SPMG 语义逐位复刻：重复游走/MH 前向优先/封顶/Q 规则）+ ID83 golden（U-M1c-01；38 golden + 审核 2×P0 修复 + oracle 对拍；设计备忘含 parity=master/v1.3.6 双成立证据）
- [x] GMM 分层器（`ms_stratify_hypermutants` 语义落地）（U-M1c-02；源码证据推翻流行叙事——无 log/mean+2σ 托底/上游全员重标定为我方 deliberate divergence；审核 PASS）

### M2 · 统一提取流水线（5 周）

- [x] `ms_extract()` 默认流水线（ensemble + 共识 + **K 默认仲裁规则**文档化 + refit）；SUITOR 式 CV 为可选开关（v0.2 期）；Wilcoxon 仅诊断（U-M2-03；folds=10/seeds=10/replicates=8 divergence 已记录）
- [x] Hungarian unmatched 的 split/merge 显式语义（兼容 Islam 阈值扫描）（U-M2-01 consensus.rs； Islam 协议复现固化 test-islam-xval.R）
- [x] 引擎注册表接入 MsNmf/MsArd/MsSparse；契约测试全过；`extending.Rmd`（U-M2-04/05/06：ard/sparse/nmf 三引擎 certified 注册；extending.Rmd 在 U-M2 收尾批补齐）
- [x] 端到端合成测试（cosine>0.95）；Islam 2022 协议复现（**语义逐位**：贪心 max-cosine ≥0.90）（test-m2-e2e.R + test-islam-xval.R + bench/xval-m2 sigminer 三方互证 0.99999+）

### M3a · 拟合三法 + bootstrap（4 周）

- [x] `ms_fit()`：nnls / likelihood_bidirectional（MuSiCal 语义，数值协议等价）/ lrt（U-M3a-02/03/04；bootstrap/presence/assign/TSB/rescale/connected 全链交付）
- [x] `ms_fit_bootstrap()`（Rust 并行）+ `ms_test_presence()`（NB χ²₁ LRT + BH）（U-M3a-03；池化零分布 P0 修复后校准矩阵全落窗 n=1..16）

**v0.2 验收（发布）**：Jiang 协议（活性>0 匹配 + Combined Score）对标进入第一梯队合理区间；refdb v1 已交付（U-M3a-06：COSMIC v3.6 BSD-2 镜像 pin ff61b0f 逐字节校验捆绑 + precedence/schema_version/manifest 治理 + build_independent 声明，全离线测试）。

---

## v1.0（再 ~3–4 月）

### M3b · MSU-Fit 校准统计（6 周；**G2 门须在此期间达成**）

- [x] estimand 三层落地：presence LRT / support-conditional 绝对 exposure CI（BCa）/ 清零复合覆盖率（U-M3b-01/02/03；198-cell 校准网格全落判据窗——池化零分布 P0 修复后；分层 calibrated-percentile 升级臂记录于 M3b 设计备忘；G2 门未达成——co-author 未锁定，GB/NC 上限主动接受）
- [x] 多项 + NB 双生成模型校准；coverage × N × Shannon 曲线；Fisher 内点区间；真实数据降采样 sanity 协议（U-M3b-02/04/05/06：calibrate.rs + ms_calibration_grid/verdict/plot/sanity 全链，终审+确认轮审计闭环 cf0751e）
- [ ] **G0 先导实验结果写入叙事决策**（Framing A vs B）——阻塞于作者 COSMIC v3.6 目录文件（G0_CATALOG_PATH）

### M4 · 相似度校准库 + viz（3 周）

- [x] **校准相似度库（`ms_compare()`，框架组件）**：多度量 + 解析/经验零分布 + Hungarian 主指标/Islam 贪心/Jiang 活性三协议参考实现（金标准测试）（U-M4-01，ca69806+cd67c71；对抗审计 P1 流带碰撞+P2×6 全修——校准锚 +1/(3m)、type-7 ≤2ulp、correlation 守卫；Islam 双口径对标正身 = PI 裁决项记 memo §8；bench/jiang 对标待办）
- [x] 样本 QC 报告 `ms_qc_report()`（负荷分布/伪迹贡献初版——机制哨兵 gt/ct + COSMIC 伪迹名册 19 条份额；amber/red 忠实复刻 ⏳v1.x）+ `ms_downsample()`（U-M4-02/02b，5f832cb+eeea14c 审计闭环）
- [x] 格式互操作 `ms_import/ms_export`（首批：COSMIC txt ✅、SigProfiler txt ✅（[V] 三重锚+真实样例 sha256 固定）、signatures 导入面 ✅（validator 0 列暴露修订）；WTSI 长格式 ⏳ 无上游实样，[V] 纪律推迟）；`ms_convert()` exome↔genome 机会转换 ✅（U-M4-02c，6e30982+eeea14c；似然内机会 ⏳v1.x）
- [ ] viz 首批 8 图型（COSMIC 调色板、规范序、矢量）+ exposure 嵌入（UMAP）初版 + `ms_convert()` 机会转换（exome/panel 机会一等公民）

### M6s · HRD 工作流（3 周；范围安全契约生效）

- [ ] `ms_hrd_report()`：**HRDetect 系数模式 WGS-only**；allele-specific CN caller 白名单（Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA）；WES 模式标 experimental；"参考忠实性测试"（系数逐位）；不确定性报告

### M7 · Benchmark 完备 + 论文（8–10 周）

- [ ] 场景网格全量（ARCH §8 升级版：纯度/caller/联合对抗/目录外/超突变臂/类别计数区间）+ 三层场景隔离 + 协议冻结
- [ ] 竞品容器 harness（仅 bench/）；钉硬件 bench 全表；`ms_benchmark()` 端到端
- [ ] 论文草稿（headline 依 G0 结果定 A/B）+ renv/Docker/seed 一键复现 + bioRxiv 同挂
- [ ] pkgdown 全站 + MSU↔函数映射表 + CITATION + 性能锚定文档

### M8 · 发布工程（M8a 材料周 + M8b CRAN 迭代（墙钟 4–8 周滚动））

- [ ] cargo vendor 终审 + r-universe + GitHub Releases 二进制 + nf-core module PR + CRAN 提交

---

## 推迟到 v1.x（硬性 Non-goal，评审裁决）

- ID89/476（Koh 2025）通道与 PRRDetect —— 映射表先行的前提下延后
- MSU-Infer 扩展（DM hurdle/结构零、生存/纵向）、MSU-LowCount（Mondrian conformal 全量）
- 相关性引擎（预注册可证伪声明达标后按结果去留；五模态仅 SBS+DBS 演示）
- 损伤节奏分析、NTF 张量引擎（exploratory）、MsLda/MsSupervised、CN/SV 拟合
- RNA 工作流（**条件升级**：G2 队列合作为 RNA-only 时提前）、therapy forensics
- Shiny/门户、深度学习、贝叶斯原生后端（不变）

## 依赖关系与 G 门

```
G0(先导实验,立即) ──────────────────┐（结果决定论文 headline）
M0 ─ M1s ─(v0.1)─ M1c ─ M2 ─ M3a ─(v0.2)
                 └─ G1(co-maintainer)
                      M3b(含G2队列门) ─ M4 ─ M6s ─ M7 ─ M8 ─(v1.0)
G3(季度竞争复核) ──────────────────┘
```
