# 评审 03：机器学习/统计学专家（独立评审，2026-09-28）

> 评审人设定：矩阵分解/主题模型/变分推断/conformal prediction/成分数据分析方向资深研究者，方法学审稿人，拒稿优先。
> **总裁决：Major revision（若为论文）/ 设计可救（若为工程档案）。** 四个旗舰 MSU 方法的统计声明普遍比档案实际规定的内容强 1–2 个等级——把 §5 表格里每个形容词（"校准过""分布自由""无损""首个"）降级到协议实际支撑的水平，这张表就能活下来。

## P0

### 1.【P0】MSU-LowCount 的 conformal"分布自由覆盖保证"在跨 TMB 场景下数学上不成立
- Split conformal 只要求 calibration 与 test **exchangeable**；panel/ctDNA 样本总突变数 N 跨 1–2 个数量级，残差分布以 ~1/√N 依赖 N——N=50 与 N=500 不 exchangeable，标准 marginal interval 被高 N 主导、在低 N 端系统性 miscalibrated。"distribution-free"指对生成分布 free，**不是对 exchangeability free**；校准集若来自 NB 模拟器，保证只在"模拟=真实"时迁移。nonconformity score 与预测对象（fraction? counts? presence set?）都没定义。
- **修改**：**Mondrian conformal by TMB bin**（分层 per-stratum guarantee）+ N 缩放/studentized score；预测对象与 score 定义写进 §5；声明改写为 "per-TMB-stratum conformal intervals with empirical coverage verified on stratified simulations and retrospective real panel data"；quantile 表按 bin 预计算随包发布 + dispersion misspecification 敏感性曲线。

### 2.【P0】MSU-Fit 覆盖率校准 CI：estimand、interval 类型、边界质量、校准泄漏四件事全部未定义
- (a) fraction vs 绝对计数两个 estimand 的 bootstrap 分布完全不同；(b) 结构性零 → percentile bootstrap 覆盖率按构造退化，小 exposure 强偏态；(c) percentile/basic/BCa 边界行为差异巨大，档案只写 "bootstrap CI"；(d) post-selection：CI 是支撑条件下的，无条件覆盖被选择效应污染（winner's curse），必须校准**整个流程**（LRT 选择+CI+清零）；(e) 清零后输出不再是 CI——如实标注 truncation 或并入点估计重新校准；(f) 合成校准对真实 overdispersion/batch 的迁移无证据。
- **修改**：estimand = **支撑条件下的绝对 exposure**（另报成分版）；BCa 或按 N×Shannon 熵分层的 calibrated-percentile；以流程整体为校准对象，报告 coverage 随 N 与 flatness 曲线；真实数据 sanity 协议（高 TMB 降采样 → CI 是否以名义频率覆盖全量估计）；声明降级为 "empirically coverage-calibrated in simulation under NB-calibrated noise, with sensitivity to dispersion misspecification"。

### 3.【P0】MSU-Corr：log-linear 嵌入存在精确 gauge 不可辨识；m 选择协议缺失；双重正则未论证
- 精确非辨识：任意 c∈R^m 使 (α,L,U)→(α−Lc, L, U+c) 保持 h 不变，再加 (LQ,UQ) 旋转自由度——**嵌入向量本身不可解读**，Gaussian prior 只选代表点；W 的可辨识性依赖"log H 低秩+偏置"强结构假设，误设偏差去向无定理保证（Cornet 证据是合成基准不是 identifiability 定理）；MvNMF 体积正则反而有 Leplat–Gillis 定理谱系——两者"联合"无任何联合理论或 ablation；**m=K 默认使跨 K 的 held-out 比较发生在灵活性不同的模型类之间，与 SUITOR 定 K 直接冲突**；σ²=mean((L,U)²) 与先验惩罚构成自引用反馈，L=U=0 驻点稳定性未知。
- **修改**：(a) 论文只报告 gauge-fixed 量（h、W、重构），禁止嵌入向量直接解读；(b) m 经 held-out likelihood（复用 entry-wise mask）或 W 稳定性选择，K 扫描时固定 m；(c) 体积正则与嵌入作为**消融轴分开报告**；(d) 补 baseline 矩阵：重标定目录上的 plain KL-NMF、纯 MvNMF、精确 Cornet、相关性感知 refit、Wu 2022 生成器下全部对比。

## P1

### 4.【P1】K 选择多证据表没有 decision rule；Wilcoxon 是伪复制检验；矩形 Hungarian 语义未定义
- 三证据冲突时管线无法继续；MuSiCal 式相邻 K Wilcoxon 把 50 个共享同一数据的 replicate 当独立证据——p 值 anti-conservative，只能作诊断；SBS5/40 近重复簇下 cosine silhouette（不满足三角不等式）不可靠；replicate 有效 K 不一致时 unmatched 对计 split 还是 merge 未定义；ARD 17/20 误报的阈值校准未提。
- **修改**：层级决策规则（SUITOR argmin 主规则 → 稳定性 veto → Wilcoxon 降为诊断）；Hungarian unmatched 语义显式定义（split/merge 分开计数，兼容 Islam 阈值扫描）；meta-rule 本身在全网格上评估（meta-rule 也会 overfit benchmark）。

### 5.【P1】Benchmark 存在校准泄漏通道与对抗性场景缺口；贪心协议奖励签名分裂
- LTH/λ̃/σ²/conformal quantile/CI 校准/ARD 阈值全部要在合成数据上校准——若与评估同生成器（甚至同种子族），benchmark 就是训练集报告；最难的真实 cell 是**联合对抗**（目录误设+高相关+平坦签名+低 TMB 同时）；Islam 贪心协议下把一个真签名分裂成两个 ≥0.90 近重复，两个都计 TP——**分裂被奖励**。
- **修改**：三层隔离——校准场景、模型选择场景、评估场景（不同生成器：SigProfilerSimulator/SynSig/PCAWG 锚定真实混合）；评估网格加联合对抗 cell 与目录外签名 cell；**主指标 = Hungarian 一对一**，贪心+阈值扫描为鲁棒性附录；分裂行为加显式惩罚或 dedup 统计；发表前冻结协议（pre-registration 式）随包发布。

### 6.【P1】Fisher 信息区间在边界退化，"LRT 选支撑 + 支撑上 Fisher CI"是 post-selection 推断
- Wald/Fisher 在单纯形边界无效（负下界+虚精度），与 LRT 的 χ²₁（边界渐近，正确）不是一回事——档案把两者并列"双模式"造成错觉。
- **修改**：Fisher 区间仅限内点支撑且显式标注条件性；边界一律 LRT + bootstrap；"boundary parameters get tests, not intervals" 写进文档。

### 7.【P1】MSU-Catalog IR "无损投影 SBS96↔1536" 的双向箭头在一个方向上不成立
- 1536→96 是聚合无损；**96→1536 在 catalog 层面不可辨识**（除非回到变异级重算）；ID89 是重新定义的分类法，83→89 映射未必良定义（partition 不互为 refine）。
- **修改**：措辞改为 "lossless coarse-graining (fine→coarse) + variant-level recomputation (coarse→fine requires variants)"；ID83↔89 显式映射表 + 标注不可映射通道；逐对审计双向箭头（SBS192/288 同理受链信息缺失影响）。

### 8.【P1】MSU-Tensor：BIC 对潜因子模型不可靠，张量可辨识性只字未提
- BIC 在 latent factor 模型上已知不一致（参数计数≠有效自由度）；标准替代是 Bai–Ng 型准则或 held-out predictive likelihood；Kruskal 唯一性条件（Σk_ranks ≥ 2R+2）从未讨论；先例 TensorSignatures 已死，同样的模型复杂度陷阱没有结构性理由不重蹈。
- **修改**：收缩范围——K 从 SBS 分析迁移固定，新增模式一次只加一个；K/秩选择改 held-out predictive likelihood + 稳定性，BIC 降为诊断；给出 rank 配置的 Kruskal 条件检查；或诚实定位为 exploratory engine。

## P2

### 9.【P2】KL 管线零通道与 ε 策略未成文
- 真正的雷是 MU 更新中 0/0 防护与 musicatk 式 "+ε 伪计数"（低 TMB 系统性抬高稀疏通道、污染 exposure）。**修改**：明文"目录层零伪计数 + NNDSVDa 正初值 + 数值防护只进除法"，并把"无伪计数"写进与 musicatk 的对比测试。

### 10.【P2】β≠1"三种噪声模型"没有选择协议
- β=1 为默认（=多项 MLE）并如此声明；保留 β 旋钮则给 CV/profile 协议；否则删宣传语。过散由 NB（拟合侧）处理，职责划分写清。

### 11.【P2】MSU-Infer 不处理 structural zeros
- DM 对 sampling zeros 自然，对 structural zeros 需 hurdle/两点分布；Morrill 2025 也没解决——扩展清单显式加 zero-inflation/hurdle；不确定性传播落地为多重插补协议（bootstrap draws 上的 measurement-error 回归）。

### 12.【P2】SUITOR 复刻保真度
- fold 按 index 取模分配（非随机——对基因组聚簇的真实 catalog 这正是原设计）与条件均值填补的 ECM 语义必须逐位复刻，否则 CV 误差与已发表校准不可比；K×10 folds×300 restarts 成本预算进文档 + 与原 R 包 golden 对拍。

## 结论与亮点
- **Major revision / 设计可救**：架构分层、S7 注册表、许可纪律、协议复刻一流；问题集中在"统计声明与统计协议之间的落差"，全部可用"改写声明+补协议+补 baseline"解决，无需推翻架构。
- **三件做得好**：术语与协议的源码级诚实（主动纠 MWPruning/MDL 不存在）；identifiability 意识方向正确（体积正则与 Cornet 两条腿 + 退化 property test）；明确不做清单与边界纪律。
