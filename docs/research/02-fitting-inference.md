# 调研报告 02：拟合/归因、暴露量统计推断与后处理分析
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-27。方法注记：[V]=克隆源码到 /tmp/fitresearch 或读全文验证；[U]=未完全验证。精读仓库：parklab/MuSiCal、steverozen/mSigAct、Rozen-Lab/mSigTools、AlexandrovLab/SigProfilerAssignment、Nik-Zainal-Group/signature.tools.lib、kgori/sigfit、lrgr/signature-estimation-py、evenrus/mmsig。精读论文：bbaf042（PMC11798676）、MuSiCal（PMC10937379）、Medo 2024（PMC11530434）、sigLASSO（PMC7368050）。

---

## 1. 各工具算法精确形式

### 1.1 MuSiCal — 似然稀疏 NNLS [V]

**术语纠正**：代码与论文中**不存在 "MWPruning"、"MDL penalty"、"catalog denoising"**（grep 0 命中）。实际存在的是：
- **LTH = likelihood threshold ϵ**（论文真实术语），默认 0.001，作用在**每突变**（per-trial）多项对数似然尺度（除以 Σx 归一化，与总计数无关）。
- "MW" = **Mann–Whitney U 检验**：用于 (a) wrappedMVNMF 中选 λ̃；(b) K 选择。
- "去噪" ≈ 匹配后的**平坦签名清理**（`_clean_W_s`）+ 预处理（队列分层、Gini 离群剔除）。

**核心 refit 算法（`nnls_likelihood_bidirectional`，默认）**（`musical/nnls_sparse.py`）：
1. 全目录 NNLS 初始解；支撑集 R⁰ = {j: h_j>0}。
2. **后向步**：对每个 j∈R，在 R∖{j} 上重解 NNLS；计算每突变多项 logL：`L = Σᵢ xᵢ·log(pᵢ)/Σx`（p = W_R h / Σ(W_R h)，clip 1e-16）；Δⱼ = L_current − L_(−j)；移除 Δ 最小者若 Δ < ϵ_backward；否则停。
3. **前向步**：对称地添加 Δ 最大化且 > ϵ_forward 者。
4. 后向/前向交替至双停（max_iter 1000；防死循环）。
5. 最终在幸存支撑上重解 NNLS。保留签名的 connected 签名在最终 NNLS 前重新加入。
- ϵ 网格版：{0} ∪ geomspace(1e-4, 5, 50)（SparseNNLSGrid）。
- **relaxed 变体**：留一重解用除被删者外的**全部**目录（检验对全目录的冗余性）——relaxed 函数在 `nnls_sparse.py:434`（:410/:461 为 LOO 块，行号随上游漂移，仅作导航）。
- 其他方法：thresh_naive/thresh（exposure 占比阈值迭代，默认 0.05）、cosine_bidirectional（ϵ=0.01）。
- **TMB 重标定**（N 选项）：放大到 N 总突变跑稀疏搜索，再回原计数重解。
- **匹配**（`refit.py:match`）：同一 SparseNNLS 机器把每个 de novo 签名分解为目录签名的稀疏非负混合；老式 `match_signature_to_catalog`：cosine ≥ 0.99 收单签名，否则单/双/三签名 NNLS（最小系数 0.1）。
- **平坦签名清理**（`_clean_W_s`，默认 min_sum_0p01=0.15、min_sig_contrib_ratio=0.25）：背景拟合判定 → 重解。
- **connected 签名**（utils.py SIGS_ASSOCIATED）：[SBS2,13]、[SBS17a,17b]、[SBS10a,b,c,d,28]。**注意：无 SBS7a-d**（与 SPA 不同！见 §7）。
- **de novo 侧**：mvNMF = KL 误差 + λ̃·log₁₀det(WᵀW+δI)，δ=1；`wrappedMVNMF` 扫 λ̃ 网格（1e-10→2.0，32 点），选"样本级误差分布不显著差于最小 λ̃"的**最大** λ̃（Mann-Whitney U，alternative='less'，p≤0.05；或 90 分位尾部检验）；K 选择：replicate 过滤（MW+尾部检验）→ cosine 平均连接聚类 → 稳定性（平均 silhouette ≥0.8、最小 ≥0.2、≥20% replicate 幸存）→ 相邻 K 显著性检验 → algorithm1（stable∩显著的最大 K）/algorithm2（stable∩不显著的最小 K）/consistency（gap statistic）。
- **in-silico 校准**：从 (W_s,H_s) 多项式模拟 X，重跑同管道比较 cosine，用于选 LTH。

### 1.2 mSigAct — 暴露量似然比检验 [V]

源码：`R/SignaturePresenceTest1.R`、`R/OptimizeExposure.R`、`R/DefaultManyOpts.R`、`R/MAPAssignActivity1.R`、`R/ForwardSearch.R`、`R/LLHSpectrum*.R`。

- **似然**：多项或**负二项**（默认）：`Σᵢ dnbinom(xᵢ; mu=reconᵢ, size=nbinom.size)`；nbinom.size = 8 (SBS96) / 50 (DBS78) / 100 (ID83)。exposure 用 **nloptr**：全局 NLOPT_GN_DIRECT（maxeval 1e4）+ 局部 NLOPT_COBYLA；终值重标到 Σx。
- **签名存在性检验**：全签名拟合 vs 去目标签名拟合；统计量 = 2(ll_with − ll_without)，**p = χ²₁ 上尾**。H0："无目标签名也能合理重构谱"。**无 Monte Carlo**（现行为渐近 χ²）。
- **MAPAssignActivity**（后向组合搜索）：从 NNLS 最优支撑开始（exposure ≥0.5 者）；df=1..max.level(5) 枚举移除子集（≤1000），各移除后重拟合并做 df 自由度 LRT；允许移除条件 p ≥ p.thresh（默认 `0.001/(4·n_sigs)` Bonferroni 式）；必要子集记录、超集跳过。MAP = ll + log P(M)，P(M) 用癌型签名流行率先验。
- **PASA**（Jiang 2024 新算法 = ForwardSearch + presence test）：
  1. 逐签名存在性检验（多项 LRT, χ²₁），p ≥ 0.1 者从候选集剔除（顺序无关）；
  2. **ForwardSearch**：从空集开始，每步对每个候选拟合 候选∪已选 并对全模型做 LRT（df = n_full − n_selected）；**加入 p 最大者**；max p > p.thresh 时停；否则保留全签名拟合。步骤 1 多项、步骤 2 负二项。
- 保卫线：默认丢弃 <100 SBS / <25 DBS-ID 样本。

### 1.3 PASA 基准结果（bbaf042）[V]

- 13 工具、2700 合成样本（9 PCAWG 癌型 × SBS/DBS/ID）。综合分 = (1−缩放曼哈顿距离) + precision + recall。
- **SBS: PASA 2.64 ≈ MuSiCal 2.62（无显著差）> FitMS 2.57 > 其余；DBS: PASA 2.78 > FitMS 2.74 ≫ MuSiCal 2.57（SPA 高精度但召回显著低）；ID: PASA 2.81 > FitMS 2.73 ≫ MuSiCal 2.68**。F1/recall+specificity 视角：MuSiCal SBS 第一、PASA 第二；DBS/ID PASA 第一。排名随癌型剧烈变化；皮肤黑色素瘤最难（常见假阴性是 SBS1/SBS5 而非 SBS7a/b 混淆）。
- 非稀疏 NNLS 系（SignatureEstimation/SigsPack/mutSignatures）：recall 0.943 但 precision < 0.615。均匀比例剪枝（deconstructSigs 式）造成假阴性。
- **关键概念结果**：99/100 合成胃癌谱存在"比真值重建更好的错误归因"（中位 11,189 个 cosine>0.969 的不同归因/谱）；重建相似度指标**无信息量**，必须 precision/recall 评估。
- CPU：MSA 慢 >5 个数量级；PASA >4；MuSiCal ~10× 于 PASA。
- 目录更新建议（SBS40→40a/b/c）：无组织分布先验时**保留父签名 SBS40 参与拟合** [V — 原文引用]。

### 1.4 SigProfilerAssignment 增量事实 [V]

- 新版默认：`cosmic_version=3.6`、`add_background_signatures=True`（**强制 SBS1+SBS5 入目录**——直接回应 Medo 平坦签名低估发现）、`exclude_signature_subgroups`（按病因的排除清单：MMR/POL/HR/BER/chemo/immuno/APOBEC/tobacco/UV/AA/colibactin/**artifact**(SBS27,43,45–60,95)/lymphoid，硬编码于 `decomposition.py:376-410`）。
- `collapse_to_SBS96=True`：1536/288 通道 de novo 签名**仅分解步**折叠到 96。
- `new_signature_thresh_hold=0.8`：de novo refit cosine < 0.8 视为新签名。
- `probabilities(W,H)`（`decompose_subroutines.py:1694`）：P(签名 k 产生通道 i 突变) = W[i,k]H[k,s]/Σ_k W[i,k]H[k,s]——比例分配"responsibility"，**非贝叶斯后验**，忽略通道外的突变上下文。

### 1.5 signature.tools.lib FitMS [V]

- 两层拟合：常见层（器官 RefSig T1/T2/T3；默认 **KLD 目标**，经 `nnlm` 包；可选 NNLS/模拟退火；bleeding filter；bootstrap 默认 nboot=200；exposure 过滤 fixedThreshold 5% 或 Gini 缩放；p 值 = 经验 P(exposure<threshold)）+ **FitMS 多步**：对残差搜罕见签名（T0–T4 绿 QC 层；`multiStepMode="errorReduction"` 需 ≥ minErrorReductionPerc 的 MAD 误差降幅；minCosSimRareSig=0.8；maxRareSigsPerSample=1 默认）。不支持重排/COSMIC 目录（仅 RefSig）。
- **bleedingFilter**（`SignatureFitLib.R:424-473`）：迭代把一个签名的全部 exposure 搬到另一签名上，接受保 cosine 最好且损失 ≤ α 的搬移——事实上的 exposure 稀疏化技巧。
- 每突变分配：`assignSignatureProbabilityToMutations` = exposure 加权通道后验 + 可选"unassigned"伪签名（正残差）。
- `sampleStrandBias`：转录（UTS/TS）与复制（leading/lagging）链偏倚，含/不含三核苷酸上下文。

### 1.6 sigfit [V]

- Stan：family ∈ {multinomial, Poisson, negbin, normal}；exposure simplex + Dirichlet(κ) 先验；**expected_counts = activities × signatures ⊙ opportunities**（机会在似然内部，非目录变换）；HPD 区间。
- `convert_signatures`：sig ← (sig/opp_from)⊙opp_to 再归一。**CI 清零规则**：95% CI 下界 < 0.01 ⇒ 置 0（Medo 证实显著改善）。

### 1.7 sigLASSO [V]

Li, Crawford & Gerstein, Nat Commun 11:3575 (2020)。生成式：L = Multinomial(m|p) × Gaussian(p|Sw, σ²) × Π_k exp(−λc_k w_k)（Laplace 先验 + 逐签名惩罚向量 c 编码先验知识强度）；显式支持 unassigned 突变；不能 DBS/ID（bbaf042 [V]）。

### 1.8 QP 族 [V]

`signature-estimation-py` 与 `mSigTools::optimize_exposure_QP` 同式：M、P 归一到 sum-1；解 min eᵀ(PᵀP)e − (MᵀP)ᵀe s.t. Σe=1, e≥0（quadprog Goldfarb-Idnani）。
**分析**：P 列均 sum-1 时，分数上的 LS ≡ 原计数 NNLS（差常数 1/N²）；**唯一实质差异是 Σe=1 等式约束**——目录无法解释部分谱时两者分歧（NNLS 缩总暴露，QP 必须花完权重 1）。所有实现都用 quadprog；**无 osqp 使用**[V grep]。

## 2. 不确定性量化格局

| 方法 | 工具 | 机制 | 备注 |
|---|---|---|---|
| 多项/参数 bootstrap | sigminer、SigsPack、mmsig、signature.tools.lib(nboot=200)、MSA、StarSignDNA(200 reps) | 重采样突变→重拟合→百分位 CI；STL 转经验 p 值；StarSignDNA 加 t 检验 | 最廉价可辩护；只捕获抽样噪声 |
| 贝叶斯后验 | sigfit（HMC 4 似然）、signeR（MCMC） | exposure 全后验 → HPD/可信区间 | 唯一天然校准的区间；sigfit CI 清零被 Medo 证实有益 |
| 解析（Fisher 信息/Δ 法） | **无** | I = N·Σᵢ(wᵢ)⁻¹∇wᵢ∇wᵢᵀ | **PubMed 无任何命中 [V]——绿地** |
| Profile likelihood | 无 | — | — |
| LRT | mSigAct/PASA（χ²₁ + BH q + AIC 权重） | 检验而非区间 | 唯一生产级检验框架；边界渐近 χ²₁ 正确 |
| 模拟校准阈值 | MSA；MuSiCal in-silico 校准 | 合成副本经验 FPR 校准 | 贵 |

**统计原则**：计数给定目录与 Σh=N 是多项式；exposure 是**成分数据**（单纯形上）→ (i) 区间应尊重单纯形几何（Dirichlet 类、log-ratio）；(ii) "S 是否活跃"是**模型选择/LRT 问题**（参数空间边界——χ²₁ 正是边界渐近）；(iii) bootstrap 应重采样突变（多项）而非通道。**空白 [V：文献缺失]**：无联合 CI；无"LRT 选择 + 支撑上条件 bootstrap CI"的组合；无 CI 覆盖率验证（Medo 明示此 open question）。**绿地机会**：条件支撑的解析/bootstrap CI + 校准 LRT。

## 3. 损失函数理论

生成模型：每突变独立抽取，P(通道 i) = (We)ᵢ/Σ(We)。
- **多项 MLE（KL）**：固定 N 下通道概率的正确 MLE。Poisson（λ=We）对总计数 profile 后与多项等价——差异仅在 (i) 总数是否携带信息（对单纯形上的 W 不携带）(ii) 过散建模（negbin 换稳健性——mSigAct 默认）。
- **原计数 Frobenius/LS**：仅在同方差高斯（不合理）下是 MLE；加权高计数通道；忽略 Var(xᵢ)≈N·wᵢ 异方差。
- **归一化分数 Frobenius（QP）**：与原计数 NNLS 同最小化子（§1.8）。
- **KL vs LS 行为**：KL 按 1/wᵢ 加权（相对误差）→ 罕见高信息通道更重要。**MuSiCal ED Fig 5b/c [V]：1000 SBS3 + 少量 SBS5 时，cosine 在 SBS5≥9% 才能分辨，多项 LL 到 2%（20 SNVs）仍显著；cosine stepwise refit 无需阈值即识别正确活跃集。**
- **cosine**：尺度不变、计数上无统计原则——只用于报告/匹配阈值。
- **L1 惩罚 Poisson**：sigLASSO、StarSignDNA——Laplace 先验下的 MAP；以收缩而非搜索获得稀疏。Medo：小 N 时 sigLASSO 是抑制假阳性最佳之一。
- **经验证据**：无论文证明损失最优性；基准层面三大似然方法（PASA/MuSiCal/sigLASSO）占头部，LS/NNLS 系垫底，两篇基准论文均把似然使用列为差异因子 [V 原文引用]。

## 4. 机会归一化、外显子↔全基因组、panel、低计数

- **机会机制 [V]**：sigfit 似然内机会（支持逐样本）；SPA 发 COSMIC `*_exome` 目录文件（per build）；MuSiCal 无外显子转换（仅 TMB 重标定）；sigminer sig_convert = sigfit 移植。
- **Panel/小计数**：现状薄弱。**SigMA**（Gulhan, Nat Genet 2019;51:912–919 [V 摘要]）是唯一经典 panel 方法：似然测度 + ML 分类器，靶向 panel 几十突变判 HRD/SBS3。bbaf042 丢 <100 SBS；mSigAct 默认丢 <100 SBS / <25 DBS-ID；MuSiCal 用 ≥100 IDs + 癌型阈值；常见门槛 ≥50（SigProfiler 文档）或 ≥200。**Medo 证明无普适阈值有意义**（难度签名特异——Shannon 平坦度；误差 ~1/√N）。"SigProfilerPanel" 未能证实存在 [U]。**第二块绿地：有原则的低计数通用拟合器（negbin/多项 LRT + panel 机会目录 + 校准 LRT）不存在。**
- **TMB 依赖**：Medo Fig 1c [V]：N 下降时误差与假阳性权重陡增；平坦签名（SBS5/40、SBS1）在所有 N 系统性低估；>10,000 突变时多数工具避免假阳性；真实 PCAWG 50k+ 样本上顶级工具仍广泛分歧。

## 5. 拟合后分析

(a) **每突变分配**：SPA probabilities（比例分配，通道级）+ VCF join；signature.tools.lib 等价 + 可选"unassigned"伪签名（正残差）。**无人条件化于基因组特征（复制时序、表达）或传播 exposure 不确定性**——可建差异化。
(b) **拟合后 TSB**：无工具原生算 per-signature TSB——mmsig 是样本级（Poisson per context + MM1/SBS35 池化）[V]；STL sampleStrandBias 样本级 [V]；SPA 的 192/288 目录 + 每突变概率可推导但不输出检验 [V by absence]。设计：每突变分配概率 × 链注释 → per-signature Poisson/binomial UTS-vs-TS 检验 + 不确定性传播。复制时序分析在 SigProfilerTopography（未深读 [U]）。
(c) **克隆时序/动力学**：TrackSig（Rubanova 2020, doi:10.1038/s41467-020-14352-7；CCF 轴 changepoint + 逐段 exposure）；CloneSig（Nat Commun 2021, doi:10.1038/s41467-021-24992-y，联合 ITH）；TRACERx 演化（Nature 2023 doi:10.1038/s41586-023-05783-5）为应用范例。时钟计时（SBS1 vs SBS5 比率 vs 年龄）在应用中出现；"MutationalChronology/mrtSig" 零命中 [V——不存在]。监督式协变量签名：Afsari eLife 2021 SuperSigs（PMID 33491650）；**无人形式化事后 "exposure ~ 协变量" 回归框架**。
(d) **组间比较**：实践随意——sigminer 启发式；Medo 用 Wilcoxon；队列级检验仅 Rozen 实验室 mSigBG（背景突变模型；未深读 [U]）。**任何地方都无 CoDA/log-ratio 处理 [V 检索]——第三块绿地**。
(e) **生存/临床关联**：纯实践无标准（Cox/logistic on exposures）；无人调整成分约束或拟合不确定性。

## 6. 目录、折叠、阈值

- COSMIC 现行 v3.6（配 COSMIC v104, 2026-05）；SPA 已默认 3.6。
- **折叠/连接处理分歧**：SPA 组 [SBS2+13, SBS7a-d, SBS10a+b, SBS17a+b] vs **MuSiCal [SBS2,13]、[SBS17a,17b]、[SBS10a,b,c,d,28]（无 SBS7 组）[V 源码]**——需设计决策（MuSiCal 清单 PMS2/POLE 驱动；SPA 加 UV 子型）。
- SPA 病因排除清单含 artifact（SBS27,43,45–60,95; DBS14）——事实上的"curated catalog" API。
- 相似度阈值：MuSiCal 匹配接受 cosine ≥ 0.99；SPA < 0.8 判新签名；FitMS 罕见候选 ≥ 0.8；**RSS/reconstruction 阈值无社区标准**——bbaf042 证明 cosine>0.969 仍容许数千归因，单报 RSS 无信息。
- 清零惯例（均经 Medo [V]）：sigfit CI 下界<0.01；deconstructSigs <0.06；COSMIC 系 <10 突变；MuSiCal LTH；SPA add/remove 惩罚 + 强制 SBS1/5 背景。

## 7. 对我们套件的需求映射

1. **拟合引擎（Rust）**：(a) NNLS（Lawson-Hanson/FNNLS）+ Σe=1 QP（复用 quadprog 语义）；(b) 多项与 negbin 似然核（向量化 SIMD）；(c) stepwise 后向/前向稀疏求解器，**两种可选拾取模式：每突变 LL 阈值 ϵ（MuSiCal 式）与 χ²-LRT 剪枝（PASA 式）**；(d) 贪心子集移除 MAP + 流行率先验（专家模式）。
2. **推断层（新，差异化）**：每签名的 LRT p/q 值 + 支撑条件下多项 bootstrap CI + 可选 HMC 后验；**在合成真值上做 CI 覆盖率测试（无人做过）**；成分数据输出 + 诚实单纯形几何。
3. **目录**：版本化（v3.2/3.4/3.5/3.6）×（基因组/外显子机会归一）双形态；病因/artifact 子群标签（SPA 式）；父/子签名关系与策略（默认拟合父签名，按需拆分）；connected 组可按目录配置。
4. **机会**：一等公民机会向量（基因组、外显子、任意 panel BED）在似然内使用（sigfit 式）+ 目录转换工具；panel 模式 = SigMA 式低计数分类器 + 校准 LRT（<100 突变）。
5. **后处理**：每突变分配概率（通道级 + 上下文注释）+ 可选 unassigned；由分配导出的 per-signature TSB/RTT 检验；带不确定性的 exposure → 组间检验（Wilcoxon 基线 + 设计中的 log-ratio/CoDA 检验）+ 传播拟合不确定性的回归/生存辅助。

## 8. 关键引用

1. Jin et al. MuSiCal. Nat Genet 56:541–552 (2024) doi:10.1038/s41588-024-01659-0
2. Jiang, Wu & Rozen. PASA benchmark. Brief Bioinform 26(1):bbaf042 (2025) doi:10.1093/bib/bbaf042
3. Medo, Ng & Medová. Nat Commun 15:9467 (2024) doi:10.1038/s41467-024-53711-6 (PMID 39487150；注意：勿用 -53574-6，该 DOI 不存在)
4. Li, Crawford & Gerstein. sigLASSO. Nat Commun 11:3575 (2020) doi:10.1038/s41467-020-17388-x
5. Gulhan et al. SigMA. Nat Genet 51:912–919 (2019) doi:10.1038/s41588-019-0390-2
6. Gori & Baez-Ortega. sigfit. bioRxiv 372896 (2018/2020)
7. Rosenthal deconstructSigs (2019)；Blokzijl MutationalPatterns (2018)；Letouzé YAPSA；Huang SignatureEstimation QP；Senkin MSA BMC Bioinform 22:540 (2021)；Rustad mmsig (2021)；Degasperi Science 2022
8. Rubanova TrackSig (2020)；CloneSig (2021)；TRACERx (2023)；Afsari SuperSigs eLife 10:e61082 (2021)
- 源码：github.com/parklab/MuSiCal、steverozen/mSigAct、Rozen-Lab/mSigTools、AlexandrovLab/SigProfilerAssignment、Nik-Zainal-Group/signature.tools.lib、kgori/sigfit、lrgr/signature-estimation-py、evenrus/mmsig、gersteinlab/siglasso

**明确未验证/不存在**：MuSiCal 的 "MWPruning/MDL penalty/catalog denoising"（不存在）；mSigAct "Monte Carlo p 值"（现行为 χ² LRT）；"SigProfilerPanel"（未找到）；"mrtSig/MutationalChronology"（未找到）；COSMIC 版本-发布对应（可能漂移）；"Wu 2022 损失理论"参考文献（未识别）；SigProfilerTopography/mSigBG 内部（未深读）；osqp 使用（未发现）。
