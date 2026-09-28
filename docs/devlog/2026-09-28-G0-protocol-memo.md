# G0 先导覆盖实验协议设计备忘（冻结前草案 v0.1，2026-09-28）

> **状态**：草案。作者拿到后按本备忘逐节执行即可；**最终冻结（阈值数字、工具对、开放问题 Q1–Q4）由作者裁决**。冻结后本备忘即预注册式协议，实验开始后不再改动判定规则；只允许追加（如敏感性臂），不允许替换。
> **角色**：mutational signature 方法学专家起草。**不写任何代码**。
> **地位**：G0 = kill-criterion 门（[ROADMAP.md](../ROADMAP.md)「组织行动门」；[ARCHITECTURE.md](../ARCHITECTURE.md) §8 末段、§10 D14）。结果决定论文 headline 走 Framing A（"Calibrated inference of mutational signature exposures"）还是 Framing B（生态），**先于一切论文叙事写作**（reviews/05 §6 表第 7 条、§9.2）。统计声明纪律按 D13 四件套成文。
> **事实核实日期**：2026-09-28（工具版本经 PyPI/GitHub API 实查；算法语义引自 docs/research/02 源码级审计 [V] 与 docs/research/05 §5）。

---

## 1. 可证伪命题（一句话）

**在标准多项模拟下，竞品工具向用户输出的 95% exposure 区间的经验覆盖率显著低于名义 0.95（尤其低 TMB 与平坦签名格点）；反之，若竞品区间基本校准，则 MSU-Fit 的 headline 声明被证伪，接受 Framing B。**

诚实注记（D13）：sigfit 输出的是贝叶斯 HPD **可信**区间，其名义 95% 不是频率保证；本实验测的是"用户视角校准"——工具营销为 95% 的区间在频率意义上包含真值的比率。bootstrap percentile 区间则是频率主义区间，名义覆盖本应是 95%。两类区间分开报告，不混为一谈。

## 2. D13 四件套

### 2.1 Estimand（被覆盖的对象，精确到工具输出的哪种区间）

对每个带区间输出的工具 T、每个网格点 N、每个真值签名 j：

**主 estimand = 工具 T 在其默认部署管线下（含默认清零/过滤规则后的"用户可见"区间）报告的 95% exposure 区间对真值绝对 exposure h_j（counts）的频率覆盖率。**

- sigfit v2.2.0：activities 的 95% HPD 可信区间（Stan HMC 后验；audit [V]，research/02 §1.6）；**默认 CI 清零规则照用**：95% CI 下界 < 0.01 ⇒ 置 0（Medo 2024 证实该规则有益——它是部署行为的一部分）。同时报 raw（未清零）覆盖率一列，用于归因"失准来自后验还是来自清零规则"。
- signature.tools.lib v2.5.2（FitMS 常见层）：bootstrap percentile 95% 区间（默认 nboot=200；audit [V]，research/02 §1.5）；其 exposure 过滤（fixedThreshold 5% / Gini）按默认启用，被过滤为 0 的签名记为区间塌缩到 0。
- 成分版（exposure fraction 覆盖率）为**次要报告**，不作判定（bootstrap 与后验在 fraction vs counts 两个 estimand 上行为不同——reviews/03 P0-2a；主 estimand 必须单一）。
- MuSiCal / SigProfilerAssignment：**无区间输出 = 分类证据，不进覆盖矩阵**（见 §3 Tier 0）。

### 2.2 生成模型（真值怎么来）

- **主生成模型：多项**。X ~ Multinomial(N, (Wh)/Σ(Wh))，W = COSMIC v3.6 SBS96 GRCh37 目录中的真值列，h = 预注册固定组成（§4）。**理由**：多项是"计数给定目录与 Σh=N"的正确模型（research/02 §3），也是竞品自身假设的模型——**在竞品自己的模型设定下失准是最强、混淆最少的证据**；若在理想设定下都失准，无须再论证真实数据保真。
- **敏感性臂（非裁定用）**：NB 过散单点交叉检验（N=1000，色散取 mSigAct 默认 nbinom.size=8 语义，audit [V] research/02 §1.2），检验多项结论的方向稳健性；结果只作附录，不翻案。
- 真值签名集与组成**预注册固定**（§4），每 rep 只重抽计数 X，不重抽组成——覆盖率是"对固定现实组成的条件覆盖"，避免组成抽样方差稀释判定功效。

### 2.3 校准协议（网格 × 重复 × 种子）

- **TMB 网格**：N ∈ {100, 300, 1000, 3000, 10000}（5 点）。覆盖临床/降采样区间下端；N=100 与 mSigAct 默认丢弃线一致（其丢弃行为本身记录为 Tier 0 证据）；>10⁴ 后多数工具免于假阳性（Medo Fig 1c，doi:10.1038/s41467-024-53711-6），故网格上端止于 10⁴（10⁵–10⁶ 留给 M3b 全网格）。
- **每点重复数**：**200/工具/签名/网格点**。功效核算：p=0.95 时 SE(覆盖率) ≈ 1.5pp；−10pp 失准 ≈ 6σ，−5pp ≈ 3.3σ——两档判定（§2.4）在 n=200 下功效均 >0.99。
- **种子纪律**：master seed = 20260928；逐 (tool, N, replicate) 经确定性派生（计数器流布局，与 ARCH §2 rng.rs 的 SplitMix64 流设计同构）；**全部种子落盘为 Seeds.txt manifest**（research/05 §6 指出的领域缺失实践，本实验先行示范）；任何重跑必须复现同一数据文件。
- 工具参数：**一律默认**（含 sigfit 清零、STL nboot=200 + 过滤、STL 的 RefSig 目录约定）。本实验测的是"领域用户开箱得到什么"，调优即失真。HMC 链数/iter/adapt_delta 记录进 manifest。

### 2.4 失效条件（预注册判定阈值）

对每 cell（tool × N × signature）计算经验覆盖率 ĉ 及其 binomial 95% CI。分签名层汇总：easy 层 = {SBS1, SBS2, SBS13}，flat 层 = {SBS5, SBS40}。

| 判定 | 条件（全部满足） | 行动 |
|---|---|---|
| **支持 Framing A** | ① 任一 Tier-1 工具在任一 cell 上 ĉ ≤ 0.85（名义 −10pp）且该 cell binomial 95% CI 上界 < 0.90（排除孤立噪声）；**或** ② flat 层在 N ≥ 300 全部 cell ĉ ≤ 0.90。 | headline = Framing A；G0 结果写入 M3b 叙事（ARCH §10）。 |
| **Kill / 转 Framing B** | 两 Tier-1 工具在全部 N ≥ 300 cell 上 ĉ ≥ 0.90（−5pp 内）且随 N 无单调恶化。 | 接受 Framing B，**不硬造差异**（reviews/05 §9.2 原文约束）。 |
| **Gray** | 其余情形。 | 仅对 borderline cells 加倍重复至 400 后重判；仍 gray → 作者裁决，**默认走 B**（不对称风险：Framing A 的 Figure 1 需要证据，B 是保底）。 |

补充条款：(a) Tier-0"无区间"证据**不触发任何判定**，只作叙事素材；(b) 敏感性臂（NB、SigProfilerSimulator、目录误设）只细化结论不推翻 §2.4 判定；(c) 竞品在实验期间发布校准 CI = kill criterion 5（ARCH §10），实验启动前复核 release notes（2026-09-28 已核：无）。

## 3. 工具候选与锁定

### Tier 1（覆盖裁定对，2 个竞品工具——均非作者自有工具，裁定可信度优先）

| 工具 | 区间语义（audit [V]） | 锁定 | 复现方式 |
|---|---|---|---|
| **sigfit** v2.2.0（kgori/sigfit，tag v2.2.0；Gori & Baez-Ortega, bioRxiv 372896, doi:10.1101/372896） | Stan HMC 后验 → 95% HPD；4 似然族 {multinomial, Poisson, negbin, normal}；默认 CI 清零 lower<0.01 ⇒ 0 | tag + commit SHA 记入 manifest | renv.lock + Docker 镜像（digest 落盘）；Stan 编译是主要工期风险（§7 R1） |
| **signature.tools.lib** v2.5.2（Nik-Zainal-Group/signature.tools.lib） | bootstrap percentile 95%（nboot=200 默认）+ 经验 p 值；bleedingFilter / fixedThreshold 5% 过滤默认启用 | tag + commit SHA | renv + Docker |

选型理由：sigfit 是**最强竞品假设**——全场唯一生产级贝叶斯后验区间（research/02 §2 表），若连它都失准，Framing A 无可辩驳；若它校准良好，则是最有力的 kill。STL 是主流实验室（Nik-Zainal）工具、PASA 基准第一梯队（bbaf042, doi:10.1093/bib/bbaf042），bootstrap 是领域最廉价可辩护的区间机制（research/02 §2）。二者分别代表"后验派"与"bootstrap 派"，结论可外推到区间机制层面而非单工具。

**W1 兼容性检查（Day 1 必做）**：STL 仅支持器官 RefSig 目录（audit [V]：不支持 COSMIC 目录）。须验证所用器官（建议 Breast）的 RefSig T1 含全部 5 个真值签名；缺失则换器官或对 STL 报告签名交集子集，并在结果表注明目录差异。

### Tier 0（无区间记录——分类证据层）

| 工具 | 审计语义 [V] | 版本（2026-09-28 实查） |
|---|---|---|
| **MuSiCal** | SparseNNLS 点估计 + LTH in-silico 校准；**无 exposure 区间输出** | GitHub tag v1.0.0（2023-12-04，release notes 仅 bug fix）；PyPI `musical` 0.3.0 滞后——按 GitHub tag 锁定 |
| **SigProfilerAssignment** | `probabilities()` 为比例分配 responsibility，**非贝叶斯后验、非区间** | PyPI 1.1.5 |
| **mSigAct** | χ²₁ LRT **检验**而非区间（边界渐近正确）；本门不用其跑覆盖，仅记录语义 | tag v3.0.3（**分支脚注**：上游以 branch 演进为准，冻结时记录 SHA） |

Tier 0 在两个工具上跑标准 refit（同输入目录），文档化"输出里没有任何可称为区间的对象"——这本身是 Figure 1 素材：**领域最主流的两个工具不输出 exposure 不确定性**（reviews/03 §2 表"解析/Profile likelihood 行：无"；"无 CI 覆盖率验证，Medo 明示 open question"）。

### Tier 2（可选低成本对照）

**sigminer** bootstrap percentile CI（作者自有工具）。纳入有"自己打自己"的诚实加分，也有"作者前史"光学风险（reviews/05 §3）；**不进裁定**，仅作实现 sanity 对照。→ 开放问题 Q3。

## 4. 模拟设计

- **生成器**：直接多项合成（主）——真值精确可控、与工具假设模型一致、无模拟器伪影混淆覆盖解读；**SigProfilerSimulator**（Bergstrom et al., BMC Bioinformatics 2020;21:438）仅在 N=1000 一点跑上下文保持一致性臂（research/05 §5"领域标准零模型"）。符合 ARCH §8"三层场景隔离"中校准场景的用途分工。
- **真值签名集（5 个，预注册固定）**：
  - **SBS1**（时钟，易——Medo 列为"容易"签名，作阳性内参：若连 SBS1 都覆盖失败，实验管线自身有问题）；
  - **SBS2 + SBS13**（APOBEC，常见活跃签名；MuSiCal/SPA 的 connected 组语义差异在拟合侧的照妖镜）;
  - **SBS5 + SBS40**（**平坦签名组**——近重复平坦对，Medo 证明全 N 系统性低估的就是 SBS5/40）。
- **固定组成（预注册）**：SBS1 15%、SBS2 15%、SBS13 15%、SBS5 30%、SBS40 25%（平坦组给大份额，避免可辨识性淹没；log-spaced 变体记 manifest 备用）。真值目录 = COSMIC v3.6 SBS96 GRCh37 全 101 签名（SigProfilerAssignment `data/Reference_Signatures` BSD-2 镜像，research/05 §1 溯源规则）；**拟合目录即全目录**——本实验测区间校准，不测签名选择，须排除参考误设混淆。
- **辅助稀疏臂**：N=1000 上将 SBS13 份额改为 2%（期望 20 counts）——专测边界/清零行为（sigfit 清零规则、STL 过滤）下的区间表现；每 rep 真值 ≥20 counts 保可解释。
- **TMB 网格 × 重复 × 种子**：见 §2.3。
- 总计算量：2 Tier-1 工具 × 5 N × 200 reps = 2000 主 fit + sigfit 每 fit 4 链 HMC + STL 每 fit 200 bootstrap 重拟合。

## 5. 指标与判定规则（汇总）

- **主指标**：per (tool × N × signature) 经验覆盖率 ĉ = P(用户可见 95% 区间包含真值绝对 h_j)，附 binomial 95% CI。
- **次要**：成分版覆盖率；sigfit raw（未清零）覆盖率；STL 过滤触发率；拒绝/报错率（含 N=100 端 guardline 触发）；单 fit 耗时（顺带取得"速度使校准买得起"论证的竞品锚点）。
- **汇总方式**：easy/flat 分层 heatmap（tool × N）；**禁止跨签名平均掩盖 flat 层**（近重复可辨识性现象本身就是被测对象的一部分）。
- **判定**：§2.4 表，冻结后不得改动。

## 6. 两周工作量核算（作者人工时；实验必须两周内出数）

| 天 | 事项 | 人工时 |
|---|---|---|
| D1 | W1 检查（STL RefSig × 5 真值签名）+ 环境搭建：sigfit/rstan Docker 编装（**关键路径**） | 6–10 |
| D2 | STL 安装 + 两工具 vignette smoke test；种子 manifest 脚手架规格确认 | 4–6 |
| D2–3 | 模拟 harness：真值/目录装配、多项生成、Seeds.txt 落盘 | 4–6 |
| D3–5 | 运行 sigfit 网格（墙钟 1–2 天后台，8 核并行）；STL 网格并行跑 | 6–8 |
| D5–6 | Tier 0：MuSiCal / SPA / （mSigAct 语义记录）标准 refit 各跑一遍 + "无区间"文档化 | 3–4 |
| D7–8 | 覆盖率计算、分层 heatmap、失准 cell 逐例检查（清零 vs 后验归因） | 6–8 |
| D9 | 敏感性臂（NB 单点 + SigProfilerSimulator N=1000） | 3–4 |
| D10 | 结果 memo + 判定结论 + 协议冻结归档（devlog + 预注册文本） | 4–6 |
| **合计** | | **40–52 h**（≈ 2 周 × 20–26 h，含缓冲） |

计算量校验：sigfit ~1000 fits × 30–60 s ≈ 8–17 h 单核 → 8 核 ~1–2 天墙钟，与排程相容；若超时降级 = N∈{100,1000,10000} 3 点或 reps=100（−10pp 判定功效仍 >0.95），降级必须记入 memo。

## 7. 风险与降级路径

| # | 风险 | 降级路径 |
|---|---|---|
| R1 | sigfit/rstan 编装失败、HMC 发散 | renv + 预编译 binary；adapt_delta/链数按默认记录（不收敛率本身是结果）。**Day 3 止损线**：仍不可用 → 换 signeR（Bioconductor，MCMC 后验区间）为 Tier-1 之Bayesian 席位 |
| R2 | W1 失败：STL RefSig 不含真值签名 | 换器官 RefSig；仍缺 → 对 STL 报告交集签名并注明；再不行 → sigminer bootstrap 补位（标记光学风险） |
| R3 | 工具在 N=100 拒跑/静默丢弃（guardline） | 拒跑率如实计入结果（部署行为即证据）；网格下端改 N=200 |
| R4 | 覆盖曲线不 informative（全部校准良好） | **这是 kill 信号，不是失败**。裁决前加一臂目录误设（真值签名从拟合目录剔除）仅作细化；仍校准 → 接受 Framing B，不硬造差异（§2.4） |
| R5 | 近重复签名可辨识性争议（SBS5/40 区间宽是"诚实"还是"失准"） | 主指标只看"是否包含真值"，宽度不进判定；flat 层单列报告，不与 easy 层平均 |
| R6 | 竞品在实验窗口内发布校准 CI | kill criterion 5（ARCH §10）即触发；实验结果仍归档，叙事立即重估 |
| R7 | 计算超时 | §6 降级方案（3 点网格 / reps=100），记入 memo |

## 8. 开放问题（请 PI 裁决，冻结前）

- **Q1 工具对**：Tier-1 裁定对 = sigfit + signature.tools.lib（推荐：后验派 + bootstrap 派，均非作者工具），MuSiCal/SPA 作 Tier-0 分类记录——ROADMAP 字面只说"2 个竞品工具"，此解读请确认。
- **Q2 主 estimand**：绝对 exposure（counts）为主、成分为辅（推荐；与 ARCH §5 MSU-Fit estimand ②"支撑条件下的绝对 exposure"对齐，reviews/03 P0-2a 亦要求二者分立）。
- **Q3 sigminer**：是否纳入为 Tier-2 sanity 对照（推荐纳入但明确不进裁定）。
- **Q4 阈值数字**：−10pp（支持 A）/ −5pp（kill→B）为本人按功效核算与评审 05"基本校准"措辞拟定的预注册值，请作者确认或修改；**冻结后不得回调**。

## 附 A：事实核实记录（2026-09-28）

- PyPI：`musical` 0.3.0；`SigProfilerAssignment` 1.1.5。GitHub tags：kgori/sigfit v2.2.0；Nik-Zainal-Group/signature.tools.lib v2.5.2；parklab/MuSiCal v1.0.0（2023-12-04，release notes 无不确定性功能）；steverozen/mSigAct v3.0.3。
- 算法语义均引自 docs/research/02 源码级审计（[V] 标记）：sigfit §1.6、STL §1.5、MuSiCal §1.1、mSigAct §1.2、SPA §1.4、不确定性格局 §2。
- 文献：Medo, Ng & Medová, Nat Commun 15:9467 (2024), doi:10.1038/s41467-024-53711-6（平坦签名 SBS5/40 全 N 低估；误差 ~1/√N；CI 覆盖率验证 open question）；Jiang, Wu & Rozen, Brief Bioinform 26(1):bbaf042 (2025), doi:10.1093/bib/bbaf042（99/100 谱存在"更优错误归因"；重建指标无信息量）；Jin et al., MuSiCal, Nat Genet 56:541–552 (2024), doi:10.1038/s41588-024-01659-0；Gori & Baez-Ortega, sigfit, bioRxiv 372896, doi:10.1101/372896；Bergstrom et al., SigProfilerSimulator, BMC Bioinformatics 21:438 (2020)。
- 本实验不涉及协议逐位复刻项（Islam/Jiang 协议见 research/07 §1.20 与 §2 状态表，属 M2/M4 范围）；G0 只需目录算术正确 + 多项生成正确，均可由固定种子 golden 夹具验证。
