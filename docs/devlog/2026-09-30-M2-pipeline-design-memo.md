# 设计备忘 · M2 统一提取流水线（共识 Hungarian 语义 + SUITOR CV 语义 + K 仲裁规则）

> **状态**：设计备忘（算法语义工作片，先设计后编码）。**未经 PI 裁决前不得派实现**。
> 作者：mutational signature 方法学专家（agent）。日期：2026-09-30。
> 证据基线（本轮网络检索，全部直读源码并逐行核对）：
> - **SigProfilerExtractor** `SigProfilerSuite/SigProfilerExtractor`，pin **master `cc6bf5ef`**（= v1.5.0 release merge，2026-09-29，与 U-M1c-02 备忘同一 pin）。行号均指该 commit。
> - **SUITOR** `binzhulab/SUITOR`，pin **master `9cf4a5f5`**（2022-03-04，仓库末次提交）；论文 Lee et al., PLoS Comput Biol 18(4):e1009309, 2022（DOI `10.1371/journal.pcbi.1009309`，PMC9009674；调研报告 01 §3 已全文核实）。
> - 本地文档：ARCHITECTURE §3.2/§5/§7、ROADMAP M2、IMPLEMENTATION-PLAN U-M2-01…07、research/01 §3/§11、research/07 §1.20/§2(c)(d)、devlog U-M1s-12/14、U-M1c-02、`src/rust/src/replicates.rs`（U-M1s-05 并行模式）、`docs/ffi-surface.md`。
>
> **D11 提醒**：本文所有"逐位/等价"用语按双层术语使用——**语义逐位**（整数/标签/掩码/指派，硬验收 golden）与**数值协议等价**（固定种子+容差）。措辞禁令（D13）：本备忘及其产出的任何文档/代码不得出现"首个/首创/业界第一/无损"类声明；共识与 CV 均为**上游已发表语义的复刻 + 确定性重实现**，我们的 delta 叙事只有一条：确定性（含线程不变性）+ 证据表透明 + Rust 加速使校准统计学买得起（ARCH §5 Delta 叙事）。

---

## 0. 一句话结论（供 PI 快审）

1. **上游共识没有"0.9 阈值"**：SigProfiler v1.5 的共识 = **迭代 Hungarian 重指派 + 平均 silhouette 收敛**，全程无 0.9；0.9 只在 Islam 式评测函数 `evaluation(cutoff=0.9)` 里（subroutines.py:2022）。ARCH §5"共识阈值 0.9"若指共识矩阵切割阈值，那是**旧版叙事**，v1.5 源码不支持。
2. **SUITOR 填补是两阶段**：初始 = **逐通道（行）中位数**（非均值！），ECM 迭代内才换成当前 WH 的条件均值；ARCH §7"条件均值填补"需按此精确化。
3. **K 仲裁三层规则**中，SUITOR 层与稳定性 veto 层的数据来源不同（CV 留出 deviance vs 共识 silhouette），二者天然可分层；Wilcoxon 在上游 SigProfiler 是**参与选择的**（stabVsRError 走 down 时以 ranksums p<0.05 决定终点，subroutines.py:1881-1899），我方把它降为诊断是 **deliberate divergence**，须记录在案。

---

## 1. 共识语义规格（SigProfiler v1.5 精确步骤）

### 1.1 ensemble（多初始化运行）

- 每个 rank k 跑 `nmf_replicates=100` 次拟合（sigpro.py:331 默认；CLI 可调）；`resample=True` 默认（sigpro.py:332）。
- 每个 replicate 的输入构造（`prepare_replicate`，subroutines.py:457-482）：逐样本列多项式 bootstrap（`BootstrapCancerGenomes`，subroutines.py:415-453：列归一化概率 → `seed.multinomial(col_total, col_probs, 1)`）→ `<1e-4` 的格子抬到 1e-4（subroutines.py:472）→ 按 normalization 设置逐样本重标定（subroutines.py:476-481）。
- KL-NMF 拟合（`nnmf_cpu`，subroutines.py:338-372）：`nmf_init="random"`（sigpro.py:337）、min 10000 / max 1e6 迭代、tol 1e-15（sigpro.py:341-344）；随后 W 列归一、H 同因子缩放（pnmf，subroutines.py:544-546）、H 按本 replicate 的样本总数 denormalize（subroutines.py:549）。
- 堆叠：`Wall`（M × k·R）、`Hall`（k·R × N），replicate 逐块横排（decipher_signatures，subroutines.py:710-727）。

**我方 deliberate divergence（须 PI 确认）**：ARCH §5 措辞是"**多初始化** KL-MM ensemble"——即 ensemble 轴 = 初始化种子（`StreamId.replicate`，canonical 布局 v1 已预留），**不做 bootstrap 重采样**（resample=FALSE 语义；bootstrap 变体留作可选开关/后续单元）。理由：bootstrap 与多初始化回答的问题不同（数据扰动 vs 优化器扰动）；确定性叙事下多初始化更干净。U-M1s-05 的 `replicates.rs` 现返回标量 objective，需扩展为返回每 replicate 的 (W, H)——并行单元语义零改动（disjoint streams + index-ordered gather，线程不变性已证）。

### 1.2 共识 = 迭代 Hungarian 重指派（无 0.9，无层次聚类，无 consensus 矩阵）

v1.5 的 `cluster_converge_outerloop`（subroutines.py:1065-1123）：

1. **50 次随机重启**（`parallel_clustering(iterations=50)`，subroutines.py:1075/1014 硬编码）。
2. 每次重启（`cluster_converge_innerloop`，subroutines.py:967-1007）：初始"质心"= 均匀随机矩阵，`Generator(PCG64DXSM(spawned_seq))`（subroutines.py:976-978）；然后循环 `reclustering`：
   a. 对每个 replicate 的 k 条签名 vs 当前质心 k 条，**`cdist(质心ᵀ, replicateᵀ, "cosine")` + `linear_sum_assignment`**（= Hungarian 一对一，subroutines.py:885-889）——每 replicate 恰好向每个簇贡献一条签名（等大小簇，k·R 条总 member）。
   b. 新质心 = 簇内均值（`np.mean(processes3D, axis=2)`，subroutines.py:952）；STE = `scipy.stats.sem(ddof=1)`（subroutines.py:953）。
   c. 收敛判据：平均 silhouette 值与上一轮**完全相等**或额外迭代达 10 次（subroutines.py:992-998）。
3. 50 个重启中取平均 silhouette 最大者（严格 `<` 比较 → 平局取先到者，subroutines.py:1099）。

### 1.3 稳定性统计（k_evidence 的上游对应量）

- `silhouette_samples(所有 replicate 签名, 簇标签, metric="cosine")`（subroutines.py:940, 1042-1062）；**rank=1 时约定全 1.0**（subroutines.py:1050-1051）；每簇稳定性 = 簇内 member silhouette 均值（subroutines.py:945-950）；方案平均稳定性 = 总均值（subroutines.py:942）。因 Hungarian 使每簇恰有 R 个 member，"簇均值之均值"与"总均值"数值相等——CSV 两列来源不同但同值（sigpro.py:1066-1068 注释自认混淆）。
- 逐 rank 导出（`All_solutions_stat.csv` 行，subroutines.py:1600-1612）：`Stability = min(逐簇稳定性)`、`Matrix Frobenius% = ‖V−WH‖F/‖V‖F`、`avgStability = mean(逐簇稳定性)`。

### 1.4 refit 与排序

- 共识质心 W 固定后，**逐样本 NNLS refit exposure**：调 `SigProfilerAssignment::single_sample.fit_signatures_pool`（sigpro.py:53 import；sigpro.py:1024-1046）。注意：门控条件是 `avgSilhouetteCoefficients > -1.0`（恒真），行注释里的"0.85 阈值"是**死注释**（sigpro.py:1024）——不要照抄注释语义。
- 签名按总 exposure 降序重排（sigpro.py:1050-1053）——展示约定，归装配层。

### 1.5 unmatched 的 split/merge 显式语义（兼容 Islam 阈值扫描）

**定义域**：匹配发生在**评测/比对层**（估计签名集 S，|S|=p，对真值或参考集 T，|T|=q），输入是余弦相似度矩阵 C ∈ R^{p×q} 与阈值 τ。与共识层（§1.2，S 与自身 replicate）无关——两处 Hungarian 用同一个 Rust 内核，语义分开写。

- **主协议（一对一，ARCH §8"主指标"）**：矩形 Hungarian 最小化 1−cos。指派对 (s,t) 中 cosine ≥ τ 记 TP。
- **unmatched 估计签名 s（Hungarian 无对手）**，按 C 的行向量分类：
  - **split（过分裂碎片）**：存在真值 t 使得 Hungarian 已把另一估计签名配给 t，且 `cos(s, t) ≥ τ` → s 记为 t 的碎片。逐真值碎片数 = |{s : max_t cos(s,t) 达阈值且 argmax=t}| − 1（t 已配对时）。
  - **merge（欠分裂合并）**：s 的 **top-2 相似度都 ≥ τ** 且分属不同真值（`cos(s,t1) ≥ τ ∧ cos(s,t2) ≥ τ, t1≠t2`）→ s 记为 t1∪t2 的合并。定义取行向量第二大值——**只看行，不改指派**（保持一对一主协议不受污染）。
  - **novel/噪声**：max_t cos(s,t) < τ。
- **unmatched 真值 t（FN）**：未被任何估计签名以 ≥ τ 匹配；若某 unmatched s 的 argmax = t，计数时标注 "FN covered by fragment/merge"（诊断字段，不改 TP/FN）。
- **Islam 兼容（zoo §1.20）**：贪心协议 = 逐估计签名 max cosine ≥ τ 分类（允许多对一），与 Hungarian 主协议共享同一矩阵 C，只换指派算法；**阈值扫描接口** = 匹配函数带 `thresholds: Vec<f64>`（默认 `seq(0.80, 0.90, by=0.01)`），一次矩阵、逐 τ 输出 `{assignment, tp, fp, fn, split_tally, merge_tally}`——M4 `ms_compare()` 三协议参考实现的数据面提前在 M2 定型（仅整数/浮点行级统计，无新统计声明，D13 不触发）。

---

## 2. SUITOR CV 语义规格

### 2.1 fold 划分：按序取模 + 逐列旋转（`get_idx_mat`）

R 参考实现 `source/R/source.R:148-158`；C 默认路径 `source/src/source.c:363-384`（`get_idxMat0`，语义恒等）。设 V 为 NR×NR… 严格地：NR 通道 × NC 样本，Kfold 折，折号 k ∈ {1..Kfold}：

- 对**每列** COL（1-based），留出行 = `seq((COL + k − 1) %% Kfold, NR, by = Kfold)`，起点为 0 时丢掉首项（source.R:152-153）。C 版等价：`val = (i + k − 1) % kfold; if (!val) val += kfold`，然后 val, val+kfold, …（source.c:372-383）。
- 即列 COL 被留出的行满足 **r ≡ (COL + k − 1) (mod Kfold)**（1-based，余 0 映射到 Kfold 的倍数行）。**关键结构：逐列旋转**——第 COL 列的折叠模式相对第 1 列平移 (COL−1) mod Kfold，保证各折在列间均衡。
- 默认 `k.fold = 10`（source.R:42-45；man/suitor.Rd:23）；`kfold.vec` 可只跑部分折（source.R:66-72）。

### 2.2 填补：两阶段（这是最容易做错的一处）

1. **初始填补 = 逐通道（行）中位数**：对每个通道行 mut，取该行**未留出**格子的 `median` 填入留出格（source.R:568-571（顺序路径）、:466-469（并行路径）、source.c `get_init_x_k`，:867-895；C `get_median`，:842，偶数个取中间两数均值 = R median 约定）。随后全矩阵 `< min.value = 1e-4` 抬到 1e-4（source.R:575-576；source.c 同）。此 `input.k0` 对所有 seed 复用（source.R:577, 584）。
2. **迭代内填补 = E 步条件均值**：首次拟合后 `input.k[idxMat] <- input.k.hat[idxMat]`（source.R:596），此后每轮 ECM 的 KL-MU 在**整张填补矩阵**上做（H、W 乘法更新，source.R:305-308），迭代末把留出格再次替换为当前 WH（source.R:326）——这正是论文"缺失计数以条件均值填补的 ECM 算法"的逐位落点。
3. 收敛监控量 = **训练格**的广义 KL 和（`loglike_new`，source.R:294-297 取 `input[!idxMat]`；:314）；`lik = sqrt(lik/train.adj)`，`train.adj = NR·NC − |idxMat|`（source.R:344, 592）；相对变化 `< em.eps = 1e-5` 或 `max.iter = 2000` 停（source.R:42-45, :318-322）。数值防护：`delta_denom = min(正的 x̂)/2` 作对数地板（source.R:311, 177-187）。

### 2.3 目标量、聚合与选择

- **目标量 = 留出格的 Poisson deviance（广义 KL）总和**，不是逐格似然均值、不是 Frobenius：`err = Σ_留出 [x·(log x − log x̂) − x + x̂]`，x=0 时首项记 0（即退化贡献 x̂）（`loglike`，source.R:160-175；C source.c:386-413 同）。
- **聚合**（`getSummary`，source.R:627-692）：对每个 (rank, fold) **先按训练误差选 seed**（`which.min(vec1)`，source.R:662-665），取该 seed 的**测试误差**；rank 层 `CV.te = Σ_folds 测试误差`（留出格跨折恰并成全矩阵一遍）；报告 `MSErr = sqrt(CV.te / M)`，M = NR·NC（source.R:670-671）。
- **选择 = 测试误差 argmin**（`which.min(CV.te)`，source.R:682-688）；平局取 `which.min` 的首遇（最低 rank）——我方确定性化时显式声明同规则。
- 默认 `n.seeds = 30`（source.R:42-45；man/suitor.Rd:29）。**勘误记录**：调研报告 01 §3 的"300 随机初始化"是论文实验设置，**包默认是 30**——memo 以源码为准，论文口径另注。

### 2.4 与我方 fit_kl 的接口（输入构造）

- 每 (rank, fold, seed) 一次独立拟合：输入 = 折掩码 + 行中位数初填 + 1e-4 地板后的矩阵；内核 = 既有 KL-MU（U-M1s-01），RNG 流 = `StreamId { replicate: seed_idx, rank: k, fold: kfold }`——**canonical 布局 v1 的 fold/rank 轴已预留**（`src/rust/src/replicates.rs` 文档头），语义恰好对位，零布局改动。
- ECM 外环（掩码→拟→替换留出格→重拟…）是一个薄驱动循环：MU 步复用 `engine::nmf` 顺序内核（固定归约序，不并行内层）；并行轴 = (rank × fold × seed) 三重独立单元，走 U-M1s-05 chunked driver + 中断协议（contract 6/7）。**线程不变性由"单元间并行 + 单元内定序"直接继承，无需新证。**
- 偏差声明（数值协议等价层）：上游 MU 无 ε（靠 1e-4 地板与正初始化保除法安全）；我方内核带 ε 防护（D6/零伪计数政策：防护只进除法）——CV 复刻验收按"数值协议等价"（容差），fold 掩码与聚合结构按"语义逐位"。

---

## 3. K 仲裁规则文档化（`ms_select_k()` 契约草案）

**三层裁决，meta-rule 在全网格上评估**（ARCH §5）：

- **层 1 — SUITOR argmin**：k* = argmin_k CV.te(k)（§2.3）。**CV 是可选开关（ROADMAP M2）**：`cv=FALSE` 时层 1 缺席，k_evidence 的 CV 列填 NA，仲裁退化为层 2 单独决定——默认值建议 `cv=TRUE`（Rust 预算内；§4），但 v0.2 期允许 FALSE 以控制运行时长（**分叉点 ③，PI 定默认**）。
- **层 2 — 稳定性 veto**：判据量 = 共识层统计（§1.3），阈值沿用上游文档化默认并显式声明来源：`avg_stability(k) ≥ 0.8` 且 `min_cluster_stability(k) ≥ 0.2` 且二者之和 ≥ 1.0（sigpro.py:352-354 的 stability/min_stability/combined_stability；stabVsRError 过滤在 subroutines.py:1802-1813）。veto 触发 = k* 被否 → 在**全网格**里按 CV 误差升序找第一个过 veto 的 k（cv=FALSE 时按 k 升序取第一个过 veto 者）；注意上游选 K 的方向性不同（SigProfiler 从高 k 往下走），我方以 CV argmin 为主锚是 deliberate divergence。
- **层 3 — Wilcoxon 仅诊断**：量 = 逐样本 L2 重构误差%（`L2_Norm_%` 列，SigProfiler 用 scipy `ranksums` 做相邻 k 比较，subroutines.py:1879-1899）；我方输出 p 值与中位数差进证据表，**不参与选择**（上游参与选择——deliberate divergence，理由：其"误差显著恶化才升 k"方向与 CV argmin 语义重复且阈值 0.05/exome 1.0 过粗糙）。R 侧用 `stats::wilcox.test(correct=FALSE, exact=FALSE)` ≈ ranksums；如需逐位对拍再改独立实现。
- **k_evidence 字段 schema**（MsSignature 的 `k_evidence`，ARCH §3.2）：tibble 逐 k 一行：
  `k, cv_test_deviance, cv_test_mse, cv_train_mse, fold_test_deviance<list>, n_seeds_converged, avg_stability, min_cluster_stability, per_signature_stability<list>, wilcoxon_p_vs_prev, wilcoxon_l2_median_delta, passes_veto, is_argmin, selected, veto_reason`。
- **默认 K 不可判定的行为**：全网格被 veto（或网格为空）时——`ms_select_k()` 显式调用 = **报错**（`msuiter_error_kselect`，附完整证据表数据）；默认流水线内 = **取 argmin 并 warning**（文档化降级，对齐上游 fallback 文案 subroutines.py:1818-1820 的精神，但不复刻其"最低 k"选择）。两分支都把证据表完整挂到结果对象（证据表透明 = Delta 叙事的一部分）。

---

## 4. 实现切分建议（对齐 ARCH 分层与 U-M2 工作单元）

**Rust（engine crate + ffi 壳）**：
- `engine/consensus.rs`（U-M2-01）：余弦距离矩阵、**方形 Hungarian**（共识重指派 k×k）+ **矩形 Hungarian**（评测匹配 p×q；或 pad-to-square，定实现时定，golden 双覆盖）、silhouette（cosine 度量）、split/merge 行级分类（纯整数逻辑）。
- `engine` 的 CV 驱动（U-M2-02）：fold 掩码、行中位数初填、ECM 外环（复用 `engine::nmf` MU 步）、留出 deviance、聚合——一个 `suitor_cv(...)` 内核函数。
- 并行：replicates 扩展 `replicates.rs` 返回 (W,H)；CV 三重网格 (rank×fold×seed) 复用 chunked driver；归约全部 index-ordered，线程不变性免费。
- 新 FFI：`ms_consensus_rust`（ensemble W/H + 共识 + 稳定性）与 `ms_cv_rust`（网格 CV 证据）——进 `docs/ffi-surface.md` 评审工件，遵守转置契约（extract.rs 的 t(counts) 恒等式）与中断契约。

**R（编排与证据层）**：
- `R/kselect-select.R`：`ms_select_k()` 三层仲裁、k_evidence 装配、Wilcoxon、错误路径（ARCH §3.1 kselect 位）。
- `R/extract.R` 扩展（U-M2-03）：默认流水线装配 `ms_stratify_hypermutants()`（U-M1c-02 已交付，`policy="exclude_de_novo_then_refit"` 钩子就位）→ ensemble → 共识 → 仲裁 → NNLS refit（`engine/nnls.rs` 已有）→ MsSignature（展示归一 + catalog_summary 快照沿用 U-M1s-12 约定）。
- Islam 协议复现 harness（U-M2-07）：贪心 max-cosine ≥ τ 与阈值扫描在匹配层（§1.5），R 侧组装 golden。

**依赖**：U-M2-01（consensus.rs）与 U-M2-02（CV 内核）互相独立可并行；U-M2-03 依赖 01+02；U-M2-04/05（MsArd/MsSparse）独立；U-M2-06 注册表接入依赖 03-05；U-M2-07 依赖 01/03。

---

## 5. golden 设计规格（供 TDD 直译；条数与覆盖点）

**共识层（12 条）**
1. Hungarian 方形 3×3 手推 golden（含平局：等距指派 → scipy `linear_sum_assignment` 语义 = 行序优先最小，断言指派向量而非仅代价）。
2. 矩形 2×3 与 3×2 各一条（min-dim 语义 + 未匹配方索引）。
3. Hungarian vs 暴力全排列对拍（k=1..6 随机 50 例，ARCH §9 既有门）。
4. 余弦距离矩阵 vs `scipy.spatial.distance.cdist(..., "cosine")` 冻结样例（数值协议等价，含零向量 case：上游 `cos_sim` 返回 0 但 cdist 路径产生 nan——**须声明我方取 0 的 divergence**）。
5. 重指派收敛：2 replicates×3 签名玩具，质心均值手推；迭代序列 + 相等停机 + 10 次上限。
6. silhouette vs sklearn 冻结样例（数值协议等价）；rank-1 → 全 1.0 约定；单簇 member 数 <2 的拒绝路径。
7. 50 重启取 max + 平局先到（构造两重启同值 fixture）。
8. 稳定性导出：min/avg 逐簇统计与 Wall/Hall 排列一致性。
9. ensemble 并行：threads ∈ {1,4} identical()（继承 U-M1s-05 断言模式）。
10. split 判定 golden（1 真值 2 碎片、阈值边界 cos=τ 恰好计入：**边界用 ≥ 语义，golden 钉死**）。
11. merge 判定 golden（top-2 ≥ τ 且异真值；top-2 同真值不算）。
12. 阈值扫描：τ ∈ {0.80,…,0.90} 逐档分类向量 golden（Islam 语义逐位复现的落点，U-M2-07 共用）。

**CV 层（7 条）**
13. fold 掩码手推 golden：NR=7, NC=5, Kfold=3 全折逐格断言（含余 0 映射）；NR < Kfold 退化 case；逐列旋转性质断言（列 c 与列 1 的掩码平移关系）。
14. 行中位数初填：奇数/偶数个观测、全列被观测/留出混合；1e-4 地板。
15. 留出 deviance 手推：含 x=0 格（贡献 x̂）与 delta_denom 地板（min 正 x̂/2）。
16. ECM 单步手推：2×2 掩码玩具一步 MU + 一次留出格替换 = 手算代数（数值容差）。
17. 聚合：per-(rank,fold) seed 按 train deviance argmin → 取其 test；Σfolds；MSErr 两公式。
18. rank argmin + 平局取最低 k；NA（不收敛）行的剔除语义。
19. R/Rust 双侧同 fixture：fold 掩码与 deviance 在整数/容差双层各自钉死（D11 双层验收，同 U-M1c-02 模式）。

**仲裁层（4 条）**
20. veto 触发 + 全网格 fallback 顺序 golden；avg/min/combined 三阈值各一负例。
21. cv=FALSE 退化路径证据表 NA 布局。
22. Wilcoxon 诊断字段（p 值容差、方向标记）。
23. 不可判定两分支：显式调用报错（错误 class/payload）、默认路径 warning+argmin。

合计 23 条；全部条目给出输入 fixture 与期望输出表后即可直译为 `#[test]` 与 testthat。

---

## 6. D13/D11 审查标注

| 层 | 验收术语 | 说明 |
|---|---|---|
| fold 掩码 / Hungarian 指派 / split-merge 分类 / 聚合结构 | **语义逐位**（整数/标签 golden） | 用有理数构造输入（正交向量 cosine ∈ {0,1}）钉死整数结构，避免浮点依赖 |
| 余弦矩阵 / silhouette / ECM deviance / 共识质心 | **数值协议等价**（固定种子+容差） | 对 scipy cdist / sklearn silhouette_samples 冻结样例；对拍为一次性平台实验模式（同 U-M1s-14），不进 CI 门 |
| veto 阈值 (0.8/0.2/1.0) | **上游默认值的引用**，非我方校准声明 | 若未来重校准（对生成模型测覆盖率），届时走 D13 四件套再进 §5 契约 |
| Islam 协议复现 | **语义逐位**（协议步骤） | zoo §1.20：贪心 max-cosine ≥ 0.90 + 阈值扫 0.80–0.90 |
| 措辞禁令 | 全文与产出 | 禁"首个/首创/无损/业界最"；正确表述 = "SigProfiler/SUITOR 语义复刻 + 确定性重实现"；"无损"仅可用于有可证伪契约的装配层（U-M1s-11 先例），本设计无此契约则不写 |

---

## 7. 分叉点清单（请 PI 逐条裁决）

1. **共识 0.9 阈值的去向**：任务简报问"consensus 阈值 0.9 的确切用法"——核查结论：v1.5 master 的共识路径**不存在任何 0.9 阈值**（0.9 仅出现在 Islam 式评测函数 `evaluation(cutoff=0.9)`，subroutines.py:2022；sigpro.py:1024 的"0.85"是死注释，实际门控恒真）。ARCH §5 原文本也无 0.9 字样——共识层钉 v1.5 语义（迭代 Hungarian + silhouette），0.9 只保留在 Islam 评测协议里，别处不得再引入。
2. **ensemble 轴是否带 bootstrap**：上游 resample=True 默认；ARCH §5 写"多初始化"。建议：默认多初始化（resample 语义缺席），bootstrap 留可选参数。
3. **CV 默认开关与预算**：SUITOR 默认 10 折 × 30 seeds × 全 rank 网格，ECM 上限 2000 迭代；我方 v0.2 预算建议默认 folds=10、seeds=10（显式 divergence、证据表记录 n_seeds）、`cv=TRUE`，允许 FALSE 退化。
4. **填补语义措辞**：ARCH §7"条件均值填补"须精确化为"行中位数初填 + ECM 迭代内 WH 条件均值"（§2.2）。
5. **Wilcoxon 降级为诊断**：上游参与选择（p<0.05 + 中位数恶化即停），我方 deliberate divergence 需在 NEWS/文档记录（§3）。
6. **零向量余弦**：上游 cos_sim 返回 0、cdist 产 nan 的不一致，我方统一取 0（相似度）→ 距离 1（§5 条目 4）。

（本备忘不实现任何代码；裁决后按 §4 依赖图派 U-M2-01/02 起步。）

---

## PI 裁决（2026-09-30，全部采纳）

1. **0.9 阈值勘误采纳**：v1.5 共识路径无 0.9 阈值（仅 Islam 评测 cutoff=0.9）；sigpro.py:1024 的 "0.85" 为死注释。共识层钉迭代 Hungarian 语义——ARCH §5 相关措辞在实现 PR 时同步勘误。
2. **ensemble 默认仅多初始化**（resample/bootstrap 留可选开关）；**CV 默认 folds=10、seeds=10**（上游 30 seeds 为显式 divergence，写入文档）。
3. **填补语义措辞**照 §2 精确化（行中位数初填 + ECM 内 WH 条件均值）；**Wilcoxon 仅诊断**维持 deliberate divergence；**零向量余弦统一取 0**。
4. **实现切分照 §4 批次 A/B/C**：批次 A = consensus.rs 与 CV 内核并行起步；golden 23 条直译 TDD；线程不变性继承 U-M1s-05 已证模式。
