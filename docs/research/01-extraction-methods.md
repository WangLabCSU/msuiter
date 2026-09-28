# 调研报告 01：De novo 签名提取方法全景与 NMF 计算引擎
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-27。标注约定：[V]=已读源码/全文验证；[search]=仅摘要级验证；[unverified]=未能确认，需存疑。

---

## 1. Cornet / Sonata —— 最重要的单项发现（用户指定的 biorxiv 论文）

**论文**: Jin H, Geiger B, Glodzik D, Gulhan DC, Park PJ. "Correlation-aware discovery of co-occurring mutational signatures in cancer." bioRxiv 2026.09.14.751548（2026-09-21 挂出，MuSiCal 原班团队）。**DOI `10.64898/2026.09.14.751548`**（bioRxiv 自 2026 起换用 `10.64898` 前缀；旧的 `10.1101/...` 不能解析）。CC-BY-NC，version 1。**[V — Europe PMC 元数据 + 全文（经 jina.ai 镜像绕过 bioRxiv 403）]**

**软件**: `parklab/Sonata`，Python，**MIT 许可**，pip 名 `sonata-tools`，AnnData 原生。含三个模型：`so.models.NMF`（KL-NMF）、`so.models.MvNMF`（最小体积 NMF）、`so.models.Cornet`。集成于 MuSiCal 式 de novo 流水线（bootstrap → fit → filter → cluster → K 选择）。**[V — 源码]**

### 1.1 模型精确形式（源码 `src/sonata/models/cornet.py`, `_utils_cornet.py`）

- 生成模型：`X_vd ~ Poisson((WH)_vd)`，签名为 W 列（列归一化在概率单纯形上），关键创新——**exposure 以对数空间的低秩双线性形式参数化**：

  `h_kd = exp(α_k + β_d + l_k · u_d)`

  其中 `α_k` 签名偏置（K 维）、`β_d` 样本偏置（D 维，吸收测序深度）、`l_k ∈ R^m` 签名嵌入、`u_d ∈ R^m` 样本嵌入，`m ≤ K`（默认 m=K）。
- 嵌入高斯先验 `N(0, σ²I)`，σ² **自适应学习**。
- 目标函数（代码中称 ELBO）：`Σ_vd [x_vd log((WH)_vd) − (WH)_vd]`（Poisson KL）`− Σ_k‖l_k‖²/(2σ²) − Σ_d‖u_d‖²/(2σ²) − (K+D)m·log(2πσ²)`。
- 谱系：**Paisley, Blei & Jordan (2014) correlated NMF**（随机变分推断）→ Cornet 换成确定性 MAP 坐标上升。docstring 明确引用。**[V]**

### 1.2 优化算法（`_update_parameters` 精确更新次序）

每次迭代：
1. 样本偏置（闭式）：`β_d = log Σ_v x_vd − log Σ_k exp(α_k + l_k·u_d)`（log-sum-exp softmax，强制 Σ_k h_kd = 样本总计数）。
2. 重算 exposure `h = exp(α + β + L Uᵀ)`（numba JIT）。
3. **辅助充分统计量**（KL-MU responsibility 技巧，避免物化三维张量）：`aux_kd = Σ_v x_vd·p_vkd`，其中 `p_vkd = w_kv h_kd/(WH)_vd`，即 `aux = Hᵀ ⊙ (W (V ⊘ WH))ᵀ`。
4. 签名偏置（闭式）：`α_k = log Σ_d aux_kd − log Σ_d exp(β_d + l_k·u_d)`。
5. 嵌入：对每个 `l_k`（固定 U）与 `u_d`（固定 L）解**凹子问题** `max_l Σ_d aux_kd(l·u_d) − Σ_d exp(α_k+β_d+l·u_d) − ‖l‖²/(2σ²)`——scipy Newton-CG 解析梯度和 Hessian（Hessian 仅 m×m）；样本嵌入 maxiter=3。
6. 方差（闭式）：`σ² = mean(concat(L,U)²)`（clip ε）。
7. 签名：标准 KL 乘法更新后列归一化。

默认：NNDSVD 初始化，min_iterations=500，max_iterations=10000，tol=1e-7，每 10 迭代检查收敛。**[V]**

### 1.3 论文声明 [V — 全文逐句核实]

- 合成基准（1000 数据集；3 个签名、诱导 exposure 相关）：标准 NMF+NNLS 在 pairwise 相关 r ≳ 0.8 后急剧退化（**中位 20–41% 的权重被归到交叉污染**），Cornet 到 r ≈ 0.98 仍正确。逐位数字：NMF **median cosine error 0.032–0.13（0.8 < r ≤ 0.98）**，交叉污染 median 20–41%；Cornet **median cosine error 0.0039–0.033**，交叉污染 2–11%。
- 真实发现：PCAWG 结直肠癌中干净解析 SBS88（colibactin，NMF 会分裂模糊）；GEL 口咽癌 SBS88；BNHL 中无聚类约束下 SBS84/85；SBS93 被证明是复合体；**膀胱癌 SBS4/SBS92 分为 92a/92b，92a 追踪 ERCC2（顺铂）状态**。
- 论文声明的预处理规则：**目录重标定使平均样本 TMB = 通道数 V 的 10–40 倍**（原文 "average tumor mutational burden across samples was between 10 V and 40 V"；SBS96 → ~1000–4000 计数/样本）——设定对数正态 exposure 分布的"温度"，控制稀疏/聚类行为。**[V]**

### 1.4 对 msuiter 的意义

整个 Cornet 模型 ≈ **400 行稠密线性代数**（elementwise exp/log-sum-exp + 一次 O(VMK) matmul + 微型 Newton 解）——是相关性签名问题（Wu 2022 证明其破坏 NMF）最廉价的解。MIT 许可直接参考。MvNMF 与输入重标定规则同样值得采纳。

---

## 2. SignatureAnalyzer（Broad/PCAWG）— ARD 自动定 K（源码级核实）

代码：`sigminer/R/bayesianNMF.R`（Broad Institute BSD-3 版权头，"Copyright (c) 2017, Broad Institute"），算法出处：**Tan & Févotte, IEEE TPAMI 35:1592–1605 (2013)**（beta 散度 NMF 的 ARD）。**[V]**

- 先验：默认变体 `BayesNMF.L1W.L2H` = **W 指数（L1）+ H 半正态（L2）**；另有 `L1KL`（指数/指数）与 `L2KL`。
- 推断：**非 Gibbs、非变分**——确定性 **type-II 最大似然（证据最大化）ARD**。逐分量先验精度 `λ_k = 1/β_k` 闭式更新：
  - L1W/L2H：`β_k ← C / (Σ_i w_ik + ½ Σ_j h_jk² + b0)`，`C = N + M/2 + a0 − 1`
  - L1KL：`λ_k ← (Σ_i w_ik + Σ_j h_jk + b0)/C`，`C = N + M + a0 + 1`，`b0 = sqrt((a0−1)(a0−2)·mean(V)/K0)`
- 因子更新：**带 ARD 惩罚的 KL 乘法更新** `H ← H ⊙ (Wᵀ(V ⊘ WH)) ⊘ (Wᵀ1 + diag(β)H)`；L2 变体用平方根 MU。
- **定 K 机制**：从 `K0`=最大（如 96）开始，ARD 收缩无用分量直到先验精度越过硬阈值（`β.cut = (C/b0)/1.25`；`colSums(W) < 1e-5` 或 `β > β.cut` 判死）。收敛：`max|Δβ/β| < 1e-5` 或 n.iter（默认 **2,000,000 次迭代**！）。默认 a0=10, b0=5。
- 已知缺陷：SUITOR 模拟中 SignatureAnalyzer 在单签名数据上 17/20 次误报（倾向分裂平坦签名）**[search — SUITOR 论文]**；BayesPowerNMF 2026 报告部分癌型高 cosine 误差。

**评估**：ARD 是唯一生产级免 rank 扫描自动定 K，R 里 10⁶ 迭代极慢 → Rust 融合内核可提速数量级。

---

## 3. SUITOR — entry-wise CV 定 K（非最优传输）

Lee D, Wang D, Yang XR, Shi J, Landi MT, Zhu B. "SUITOR: Selecting the number of mutational signatures." PLoS Comput Biol 18(4):e1009309, 2022（NCI DCEG）。代码 `binzhulab/SUITOR`（R/Bioc）。**[V — PMC9009674 全文]**

- **Poisson NMF + entry-wise 无监督 K 折 CV**：按矩阵**单元**留出（每肿瘤内 index 取模分 10 折）→ 训练矩阵带 MCAR 缺失 → 缺失计数以条件均值填补（E 步）的 **ECM 算法**（可证等价 KL-MU，似然单调）。
- 选择：`ERR_r = Σ_folds −log Pr(留出|拟合)`，取 argmin；默认 tol 1e-5、max 2000 迭代、**300 随机初始化**。
- 结果：PCAWG（2,540 肿瘤）留出误差最小；体外诱变基准 91% 敏感性（cosine>0.8）vs 竞品 45–82%；单签名数据零误报。
- **移植注**：entry-wise CV 在 Rust 中就是 mask + 部分和归约，实现简单且是**校准最好的 K 选择方法**。

---

## 4. signeR — 经验贝叶斯 Gibbs NMF

Rosales RA et al., Bioinformatics 33(1):8–16 (2017)。Bioconductor。**[V — rdrr.io 读 signeR.R]**

- Poisson NMF + **Gamma 先验**（签名 P 与 exposure E），Gamma 速率超参的 shape 带**指数超先验**（分层 Gamma–exponential，非 Dirichlet）；超参经验贝叶斯 EM 估计（≤100 轮）。
- 推断：**Gibbs 采样**（C 后端），已知 K：10,000 burn-in + 2,000 后验样本；定 K 跑：1,000+1,000。K 选择：Gibbs 似然 BIC，粗到细网格。
- 后验 → 签名与 exposure 可信区间；2023 后续（Drummond, BMC Bioinformatics）将 exposure 后验传播到临床关联（PMC10664385）。
- 运行时：10⁴ 级 MCMC × 候选 K → 最慢主流工具，不适合大队列。

## 5. BayesPowerNMF — power posterior（NEW 2026）

Xue C, Miller JW, Carter SL. PLoS Comput Biol 2026, DOI 10.1371/journal.pcbi.1014372。代码 `TARPS-group/BayesPowerNMF`（Python, MIT）。**[V — repo+全文]**

- Poisson NMF + 签名行 Dirichlet 先验 + exposure **压缩 Gamma 先验**（Zito & Miller compressive Bayesian NMF）→ 列稀疏收缩自动定 K。
- 关键技巧：**似然取幂 α∈[0,1]**（power posterior）以抗模型误设（污染、过散动、扰动）；α 由模拟校准选定。
- Stan NUTS/HMC，4 链 × 10k warmup + 10k draws；声称误设下 precision/recall 最佳（vs SigProfilerExtractor/SignatureAnalyzer/SigMoS），~30 样本即可恢复真值；95% 可信区间。
- **对 msuiter**：α 幂似然是 KL/Poisson 引擎的一行改动（梯度乘 α），可作为抗噪声"稳健性旋钮"。

## 6. BASCULE — 贝叶斯 NMF + DP 聚类 + GPU SVI（NEW 2025 末）

Buscaroli E et al., Genome Biology 27:15 (2025), DOI 10.1186/s13059-025-03835-9。**[V — PMC 全文]**

- SBS/DBS/ID 联合张量；Poisson 似然；exposure 与 de novo 签名 Dirichlet 先验；**de novo 先验 ω 的构造使已被固定 COSMIC 目录解释的特征获得低先验浓度**——即**残差感知的 de novo 提取**（先拟合目录、de novo 只吸收残差）。
- Pyro 随机变分推断（GPU）；两阶段（先拟合目录再加 de novo）；事后剪枝（与已有 cosine ≥ ~0.9 的 de novo 丢弃）；BIC 定 K；exposure 上 DP 混合自动聚类。
- 速度：GPU 1,000 样本 ~6 min vs SigProfiler/SparseSignatures/FitMS 30–559 min。
- **对 msuiter**："残差感知先验"是 2025 年最佳实用思想（杀死 SBS40/5 反复重分裂问题），可在确定性 MU 内采纳。

## 7. Shiraishi 模型族：pmsignature 与 HiLDA

- **pmsignature**（Shiraishi 2015 PLoS Genet e1005657；`friend1ws/pmsignature`，R+C++）：签名 = **逐特征独立多项式乘积** `P(m|k) = Π_l F[k,l,feature_l(m)]`（6 替换类、任意长侧翼、链、转录方向）。EM 推断（C++ `EMalgorithm.cpp`），数据稀疏存储（mutation, sample, count）。**[V — 源码]**
- 败因分析：(a) 输出非 96 通道格式、无法与 COSMIC 直接比对；(b) 逐特征独立假设无法表达某些相关侧翼结构；(c) PCAWG/SigProfiler 生态锁定。**[部分 search]**
- **HiLDA**（PLoS Genet 2019, PMC6717498；USCbiostats）：Shiraishi 表示上的 hLDA，定位是**两组 exposure 差异的层级检验**（Gibbs + 置换检验）而非发现。另有 Matsutani 2019 Bioinformatics 35:4543（VB-LDA 自动定 K）。
- **取舍**：保留 Shiraishi 式因子化表示作为内部特征工程选项（免费扩展 strand/flank），交换格式仍以 SBS96/1536 为准。

## 8. 深度学习路线 — 诚实评估

| 方法 | 是什么 | 出处 | 结论 |
|---|---|---|---|
| MUSE-XAE | 自编码器：非线性编码器 + 非负线性解码器 + 最小体积正则，Adam + Poisson NLL | Bioinformatics 40(5):btae320, 2024；`compbiomed-unito/MUSE-XAE` | 同行评议可信；但保真度不明显优于直接跑 MV-NMF，低采纳 |
| SigNet | ANN **refitter**（学 NNLS 的逆，给预测区间，低计数可用） | bioRxiv 2023.12.06.570467；`weghornlab/SigNet` | 低 TMB 拟合/不确定性有用，非提取器，小众 |
| Egendal 2025 | 签名用于患者分层的 NN | DOI 10.54337/aau815838821 | 非方法学贡献 |
| "deep unfolding NMF" (Nasser 2022) | 展开优化网络 | **[unverified — 未找到原始出处]** | 跳过 |

**结论：截至 2026-09，深度学习提取器没有一个成为可信赢家**。前沿转向 (a) 更好适定的线性模型 + 可识别性正则（Cornet/MvNMF）、(b) 贝叶斯不确定性、(c) 模型选择严谨化。"SigDC/MSNet/DeepMS" 不存在（与无关文献撞名）。**DL 不值得占引擎席位；SigNet 式摊销 refit 可作未来特性。**

## 9. 其他提取方法与基准格局

- **Sonata `so.models.MvNMF`**（`parklab/Sonata` 源码读）：`KL(V‖WH) + λ·log det(WᵀW + δI)`（Leplat, Gillis & Ang, IEEE TSP 68:3400–3410, 2020）；MM 乘法更新 + 回溯线搜索 + W 列归一。**相关/过完备签名可识别性的线性世界解药**。[V]
- **SparseSignatures**：L1 惩罚 Poisson NMF + bi-cross-validation（已知）；SUITOR 基准显示对突变检出错误脆弱。
- **SigMoS**（Rosenberg 组；BayesPowerNMF 作为对照引用）：大队列过拟合。[search]
- **mSigHdp**：HDP，罕见签名敏感性最佳、慢（已知）。
- "Sigmoid" 仅在 Islam 2022 出现 [unverified]；Clomial 是克隆基因型解卷积，非签名工具；"MutationalSignatureAnalysis MATLAB / SP-Signatures / AutoSig / 高斯过程提取器"均未找到。
- **基准文献**：Islam 2022 Cell Genomics（提取工具基准标准）；Wu 2022 Sci Rep 12:390（相关性签名失效基准）；**2023–2026 无新的系统性提取基准**（各工具自带 benchmark 除外）——**这是 msuiter 论文的直接机会**。

## 10. 计算引擎动物园（含更新方程）

记号：V ∈ R_+^{M×N}（M 通道 × N 样本），V ≈ WH，W ∈ R_+^{M×K} 签名，H ∈ R_+^{K×N} exposure。

**(a) KL 散度乘法更新**（Lee–Seung 2001；= 多项 PCA / Poisson 似然的 EM，Cemgil 2009）：
```
H ← H ⊙ (Wᵀ(V ⊘ WH)) ⊘ (Wᵀ 1_M)
W ← W ⊙ ((V ⊘ WH)Hᵀ) ⊘ (1_M Hᵀ)
```
成本：3 GEMM + 2 elementwise 除 ≈ 4·MNK flops/迭代。单调非增 KL（Zangwill 全局收敛到驻点）；线性局部收敛；对初始化敏感；支持稀疏 V。使用者：SigProfilerExtractor（PyTorch）、MutationalPatterns（brunet）、rust-NMF brunet、Sonata NMF、Cornet 的 W 步。

**(b) Frobenius/EU MU**：`H ← H ⊙ (WᵀV) ⊘ (WᵀWH)` — 同成本；Gram 化实现可降至 O(MK²+NK²+MNK)（NNLM `lee_ls`、rust-NMF `lee`）。计数数据下噪声假设错误。

**(c) HALS**（Cichocki 2007–2009；RcppML）：逐分量 `h_k ← max(0, h_k + (g_k − G h_k)/G_kk)`，Gram `G = WᵀW` 增量更新；扫描成本 MNK + (M+N)K²，K≪M,N 时更便宜。Frobenius 下有单调性保证（KL-HALS 无一般保证）。

**(d) ANLS 主动集**（Kim & Park 2007）：每个 NNLS 块精确解；迭代最少、单迭代最贵、实现最复杂。NNLM（linxihui）实现相关的**序列坐标下降 SCD**：KL 版用二次代理逐坐标最小化，可证收敛，支持 L1/L2/缺失掩码。**[V — base_algorithms.cpp]**

**(e) 投影梯度/加速**：Lin 2007 Armijo 线搜索；Nesterov 加速；rust-NMF `dnmf` 比 `lee` 快 26% 因子质量不降。[V — README]

**(f) Beta 散度 MM**（Févotte & Idier 2011；Marmin 2023 Signal Processing，被 Cornet 引用）：
```
H ← H ⊙ [Wᵀ(V ⊘ WH)^{β̃}] ⊘ [Wᵀ(WH)^{β̃}]，β̃ = β−1（1≤β≤2）
```
β=2 Frobenius / β=1 KL / β=0 IS。MM 构造对所有 β 保证单调；Marmin 2023 给出 W、H 同时更新的联合 MM。同 O(MNK) 成本，多一次 pow。**"一个内核、三种噪声模型"——推荐引擎。**

**(g) Poisson NMF via EM/CCCP**：软 EM 潜在计数分配 `c_vkd = x_vd·w_kv h_kd/(WH)_vd` + 闭式 M 步——代数上与 KL-MU 等价（这正是 SUITOR ECM 论证的基础），但打开了随机/mini-batch/镜像下降变体和潜在计数先验（BASCULE/BayesPowerNMF 路线）。Cornet 的 aux 统计量即此潜在计数聚合。

**rust-NMF 实测事实 [V — lib.rs + README]**：bit 等价 R NMF：brunet/lee/offset/nsNMF/snmf-r/snmf-l/hals/ehals/dnmf/lsnmf + NNDSVD；ndarray 0.16 + rayon（无 BLAS）；pbmc8k (3000×1500, rank 8, 16 线程)：lee+NNDSVD@25 iter = 0.19 s、brunet 0.41 s、hals 0.13 s；ARI 最优 = lee+NNDSVD 0.889 vs lee+random 0.568。**核心实证定律："NNDSVD 初始化是魔法，不是算法"**。对 R 加速 ~76×（Lee，bit 等价）至 ~215×（HALS+NNDSVD@25 iter）。**许可 GPL≥2（承自 R NMF 移植）——只作参考，不得复制代码。**

## 11. 初始化与 K 选择最佳实践

- **NNDSVD**（Boutsidis & Gallopoulos 2008）：确定性 SVD 初始化；变体 NNDSVDa（零位填均值）、NNDSVDar（零位填小随机）。Sonata 另有 `flat` + 随机 + separable-NMF (SEMF) 初始化。M≈100–1500、K≤30 时 SVD 微秒级。
- **K 选择可信度排序**：
  1. **Held-out CV（SUITOR）** — 校准最佳、成本高（K×折×重启）但完美并行；
  2. **MuSiCal 剪枝后稳定性/显著性**（见 02 报告）；
  3. **ARD 自动 K**（免扫描但有过分裂记录）；
  4. **共识稳定性：replicate exposure 上的 silhouette**（SigProfiler 默认；cophenetic Brunet 2004 与 dispersion Kim-Park 2007 是其祖先）。**cophenetic 单独使用已不可辩护**（对罕见签名不敏感：Islam 2022；相关签名下不稳定：Wu 2022），仅作辅助诊断；
  5. BIC（signeR/BASCULE，似然框架内合理）；
  6. HDP/收缩自动 K（真非参但慢/敏感）。
- **建议**：多起点 NNDSVD+随机共识 silhouette（兼容性）**+** SUITOR 式 CV 误差作为头牌统计（差异化）**+** 可选 ARD 模式（快速自动 K 分诊），三者全报告。

## 12. 提取前目录预处理

- **超突变者**：SigProfiler 用 1-D GMM（`GaussianMixture(n_components=2, covariance_type="full")`）在每样本总突变数上定 cutoff，默认 manual_cutoff=**9600**（`subroutines.py:149` `get_normalization_cutoff`），然后按 `matrix_normalization` 重标定：默认 **`"gmm"`**，可选 `"100X"`、`"log2"`、`"none"`，或直接传正整数作为手工 cutoff（`sigpro.py` ~L318；`README.md:93`；`docs/3. Using the Tool - Input.md:64`）。**[V — SigProfilerSuite/SigProfilerExtractor 源码]**（注：仓库已从 AlexandrovLab 迁至 SigProfilerSuite 组织。）固定文献阈值 >10 mut/Mb（hypermutated）、>100（ultra）。
- **common-then-rare 两阶段**（Degasperi 2022 Science 376:eabl9283）：FitMS = **Fit Multi-Step**（PMID 35949260, PMC7613262）。先固定常见签名（器官 RefSig T1–T4；`constrainedFit` 用 limSolve 约束 NNLS），再对残差搜罕见签名；两种策略 `constrainedFit` vs `errorReduction`，论文结论 **errorReduction 胜出**：*"A rare signature is considered present if the reduction in error is at least 15%"*；第二步假设存在 1 或 2 个罕见签名。实现于 `signature.tools.lib`（Zenodo Code S1/S2）。**[V]**
- **机会归一化/外显子↔全基因组**：exposure 保留"活性占比"与"每 Mb 速率"两个概念，sig_convert 类转换保留。
- **2023–2026 新思想**：①Cornet/Sonata 输入重标定（10–40× 通道数）；②MuSiCal 去噪与一致性循环；③BASCULE 残差感知先验；④BayesPowerNMF α 幂似然；⑤SUITOR entry-wise 掩码兼作 QC 评分。

## 13. Rust 引擎候选设计（shortlist）

| # | 设计 | 内核 | K 选择 | 优点 | 缺点 |
|---|---|---|---|---|---|
| E1 | **MM beta 散度核（β=1 默认）+ ARD 模式 + NNDSVDa 初始化** | MU/MM（4MNK）+ ARD 超参更新 | ARD 自动 + 共识 silhouette | 与 SigProfiler/MP 兼容；单调可证；GPL-clean（从 Tan–Févotte/论文公式重实现） | MU 尾部收敛慢（此规模下廉价）；ARD 过分裂平坦签名 |
| E2 | **E1 + SUITOR 式 entry-wise CV 模块** | 同上 + 掩码 KL 评估 | CV 误差头牌 | 校准最佳的 K；强论文差异点；复用 E1（需 mask 支持） | K×折额外成本（完美并行） |
| E3 | **Cornet 移植** | W 的 MU + O(MNK) aux + 微型 Newton | 继承 MuSiCal 式流水线 | 解相关签名问题；MIT 参考；定位下一代 | 对输入重标定敏感；嵌入引入调参面；单点无后验 |
| E4 | **MvNMF 体积正则模式** | MU 类 + K×K logdet + 线搜索 | 同 E1 | 无需嵌入即可获得相关性下可识别性；E1 的开关式正则 | λ/δ 需选择；过正则会扭曲纯签名 |
| E5 | 贝叶斯模式（压缩/收缩先验 MAP 或 SVI） | MU+先验项（ARD 是其 α→MAP 极限）或手写 ADVI | 收缩自动 K + CI | 后验不确定性（无任何 Rust 套件有）；残差感知目录先验 | 复杂度最高；Rust 手写 SVI 是大工程 |

**推荐**：E1+E2 为核心（共享 90% 代码），E3 为旗舰第二模型，E4 作为 E1 的 flag，E5 缓行。引擎面 ≈ 6 个内核 + 1 个 SVD + 1 个 Newton/L-BFGS 工具。

## 14. 引用清单

（关键条目，完整见正文内联引用）
1. Jin et al. Cornet. bioRxiv 2026.09.14.751548, DOI 10.64898/2026.09.14.751548；Sonata: github.com/parklab/Sonata (MIT)
2. Paisley, Blei & Jordan 2014（correlated NMF 谱系）
3. Lee et al. SUITOR. PLoS Comput Biol 18(4):e1009309 (2022). PMC9009674
4. Rosales et al. signeR. Bioinformatics 33(1):8–16 (2017)；Drummond 2023 PMC10664385
5. Xue et al. BayesPowerNMF. PLoS Comput Biol (2026) doi:10.1371/journal.pcbi.1014372
6. Buscaroli et al. BASCULE. Genome Biol 27:15 (2025) doi:10.1186/s13059-025-03835-9
7. Kim et al. SignatureAnalyzer. Nat Genet 2016 doi:10.1038/ng.3557；Tan & Févotte IEEE TPAMI 35:1592–1605 (2013)
8. Shiraishi et al. PLoS Genet 11(12):e1005657 (2015)；Yang et al. HiLDA PMC6717498；Matsutani Bioinformatics 35:4543 (2019)
9. Pancotti et al. MUSE-XAE. Bioinformatics 40(5):btae320 (2024)；Serrano et al. SigNet bioRxiv 2023.12.06.570467
10. Leplat, Gillis & Ang. IEEE TSP 68:3400–3410 (2020)；Boutsidis & Gallopoulos SIAM J Matrix Anal Appl 30:60 (2008)
11. Lee & Seung NIPS 2000 / Nature 401:788 (1999) / Nature 2001（KL）；Févotte & Idier Neural Comput 23:2421 (2011)；Marmin, Goulart & Févotte, Signal Processing 209:109048 (2023) doi:10.1016/j.sigpro.2023.109048
12. Kim & Park 2007/2008；Brunet PNAS 101:4164 (2004)；Cichocki 2007–2009；Cemgil 2009
13. Islam et al. Cell Genomics 2:100131 (2022)；Degasperi et al. Science 376:eabl9283 (2022)；Wu et al. Sci Rep 12:390 (2022)
- 代码：parklab/Sonata (MIT)、binzhulab/SUITOR、TARPS-group/BayesPowerNMF (MIT)、friend1ws/pmsignature、USCbiostats/HiLDA、omicverse/rust-NMF (GPL≥2, 参考)、linxihui/NNLM (BSD-2)、zdebruine/RcppML (GPL≥3, 理念)、weghornlab/SigNet、compbiomed-unito/MUSE-XAE、sigminer R/bayesianNMF.R (Broad BSD-3, 可移植)

## 15. 明确未验证项

- SigMoS 引用细节；Sigmoid 详情（Islam 2022 全文 grep "sigmoid" = 0 命中——该术语不存在）；mmsig2/MATLAB-MSA/SP-Signatures/AutoSig（未找到，很可能不存在）
- **已结案（本轮核查，2026-09-28）**：
  - Cornet 定量基准数字 → **已全文核实**（见 §1.3）；DOI 前缀纠正为 `10.64898`（见 §1）
  - SigProfilerExtractor 超突变参数 → **原 `gmm_cutoff`/`rescale`/`quadratical` 说法被证伪**；真实参数 `matrix_normalization`（默认 `"gmm"`；见 §12）
  - Degasperi 罕见阶段加权 → **已核实**：FitMS `errorReduction` 策略、误差降幅 ≥15% 阈值（见 §12）
  - RcppML 许可 → **GPL (>= 3)**，v1.0.0（已确认）
  - Marmin 2023 DOI → `10.1016/j.sigpro.2023.109048`（Signal Processing **209**, art. 109048, Aug 2023；作者 Marmin, Henrique de Morais Goulart, Févotte）
  - rust-NMF 加速比 → 头版数字应为 **76×（bit 等价，lee）与 ~215×（hals+NNDSVD，25 iter）**；`280×` 是单行宽松配置（10 iter, 0.45 s）外推，不宜作标题
- **许可地雷**：rust-NMF 奇偶校验实现为 GPL≥2；RcppML GPL≥3；Sonata MIT 安全；sigminer bayesianNMF.R 是 Broad BSD-3（带归属可移植）；所有情形下算法本身已发表、可自由重实现
