# 评审 01：计算生物学家（独立评审，2026-09-28）

> 评审人设定：突变特征方向资深计算生物学家，多次主导 Nature/Nature Genetics 级 signature atlas 项目。评审对象：docs/ARCHITECTURE.md、ROADMAP.md、research 00–08。
> **总裁决：有条件信任——按现状不能送审，修复 P0/P1 后可产出扎实的论文。**

## P0（阻塞级）

### 1.【P0】MSU-Fit 的 "coverage-calibrated CI" 未定义 estimand，且 Fisher 信息区间在边界无效
- **攻击位置**：ARCHITECTURE §5 MSU-Fit；ROADMAP M3；02 报告 §2。
- **为什么是科学问题**：(a) Estimand 缺失——exposure 是单纯形成分数据：校准 exposure *fraction* 还是*绝对计数*的覆盖率？混用则覆盖率不可解释。(b) 边界质量——真值大量恰为 0（稀疏支撑）；percentile bootstrap 与 Wald/Fisher 在边界必然欠覆盖；χ²₁ LRT 才是边界问题的正确机器（Self–Liang），但 support-conditional 与 unconditional 是两个不同 estimand。(c) CI 清零规则并入流程后，必须测**复合流程**覆盖率否则数字是假的。(d) 校准的生成模型：领域检验框架（mSigAct）默认 NB size=8——真实目录严重过散，多项下校准的 CI 在真实 NB 数据上必然失效。
- **修改**：写死三层 estimand：①presence = χ²₁ LRT；②magnitude|active = support-conditional bootstrap CI，**同时在多项与 NB（Jiang 色散协议）下校准**，按 N 与签名 Shannon 熵报告经验覆盖曲线；③CI 清零单独测复合覆盖率。Fisher 区间降级为 interior-only 诊断或删除。

### 2.【P0】HRD 工作流超界：HRDetect 2017 系数是 WGS 训练的，"集成不确定性"却无任何集成模型
- **攻击位置**：03 Top-10 #1（"支持 WES/WGS"）；ROADMAP M6。
- **为什么是科学问题**：(a) HRDetect 六特征只有 WGS 级输入才可计算；对 WES/panel 冻结系数是**患者伤害级**风险。(b) LOH/LST/TAI 需要 allele-specific CN——输入契约（caller 白名单）未指定。(c) 档案引用 Nacer 2026 的 7 方法不一致，却用"集成+不确定性"一句话带过——无权重、无校准队列、无预注册。
- **修改**：HRDetect-系数模式 **WGS-only**；allele-specific CN caller 白名单（Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA）；WES 模式必须标 experimental 并独立队列重校准；集成规则预注册；"HRDetect 系数校验测试"改名"参考忠实性测试"（只证明系数抄对，不证明 WES 特征可互换）。

## P1（重大）

### 3.【P1】变异类别覆盖缺口：MNV 分离、complex/double indel 路由、VCF 拆分后 DBS 重构均未定义
- SPMG 明确将距离 2–5bp 的相邻 SNV 分离（MNV），仅距离恰 1 进 DBS78；hts-specs 规范化会把 MNV 拆成连续 SNV——天真计数会系统性膨胀 SBS 通道且 **DBS78 无法从拆分 VCF 重构**；complex indel 路由去向未声明。
- **修改**：目录完备性契约：枚举每类输入事件（SNV/DBS/MNV2-5/MNV>5/complex indel/double indel）的路由去向，skip ledger 进 provenance；拆分 VCF 相邻记录重连算法规范；MNV-相邻 golden fixtures 进 M1。

### 4.【P1】Cornet 10–40× 重标定是模型先验温度旋钮，不是数据卫生标准（且 [search] 级未验证）
- 对纯多项/KL 目标，整体乘常数不改变估计——该规则只在尺度敏感正则（自适应 σ²、体积项）下有意义；还会改变 CV deviance 尺度与绝对 exposure 语义（需 de-rescale，未提）。
- **修改**：降级为 MSU-Corr 内部超参数；M7 网格 sweep scale ∈ {1,10,40,100}，以平坦签名低估为守护指标；明文禁用于 NMF 路径。

### 5.【P1】GMM 超突变者处理被误称"归一化"；Degasperi common/rare 两阶段在架构中无主
- SigProfiler 的 GMM 步骤是**分类并排除出 de novo、事后 refit**——是分层不是归一化；排除的恰是 APOBEC/POLE/MMR 样本，cutoff 直接决定这些签名能否被提取；两阶段策略无 MSU-* 认领、无里程碑、无工作流。
- **修改**：`ms_stratify_hypermutants()`（显式 GMM 阈值 + de novo 排除 + 强制 refit）；common/rare 升格为 atlas 工作流进 M6；基准加 5–10% 超突变者臂（TMB 100×），报告 APOBEC/POLE P/R 对 cutoff 敏感性。

### 6.【P1】基准缺两个最真实的失败轴——纯度与 caller 依赖；CN/SV 计数区间错配
- 纯度 0–70% 产生混合谱与亚克隆结构；同一 BAM 双 caller 目录不同（档案自己引用 41427300）；CN/SV 的 N 是段/重排数（几十–几百），TMB 10²–10⁶ 不适用。
- **修改**：加 purity ∈ {1.0, 0.7, 0.4, 0.2}；caller 轴（≥2 SNV + ≥2 indel caller）；类别专属计数区间（SV 10–10³、CN 10–10⁴）；平坦签名组内 r=0.8 + 稀有签名共存联合场景；亚克隆 exposure 结构。

### 7.【P1】MSU-Corr 科学 delta 最弱：未排除"MvNMF 提取 + 相关性感知 refit"更简单基线；m=K 过参数化
- 体积正则与嵌入捆绑却无 ablation；h=exp(α+β+l·u) 在 m=K 有旋转/重参数化不可辨识；五模态联合把不同计数尺度强行共享 exposure。
- **修改**：预注册可证伪声明（r∈{0.8,0.9,0.95} 上同时击败 MvNMF+correlated refit 与原版 Cornet）；gauge 固定方式写明；m<K + 选择规则（BIC/CV）；五模态降为 SBS+DBS 双模态演示直至被证明。

### 8.【P1】RNA 工作流对上游依赖不诚实
- COSMIC RNA-SBS 来自特定 calling 管线与过滤链；不同管线变异去拟合这套参考继承的 caller 伪影比 DNA 更重；192 通道需规定用哪条链的上下文；DNA-RNA 一致性需要配对队列与预设度量。
- **修改**：最小输入要求（RNA-Mutect2 或 STAR 2-pass + 文档化过滤；RNA editing 排除；matched normal 标注）；参考面板加 RNA 伪影签名；预设一致性 estimand；案例锁定配对队列；工作流标 research-use。

### 9.【P1】K 选择"多证据全报告"没有仲裁规则——是 dashboard 不是方法
- 失败模式恰是证据互相矛盾（silhouette 对平坦签名平台化、SUITOR 偏简约、Wilcoxon 偏宽松）；"与 SPA 一致率"更弱——一致不等于正确。
- **修改**：默认仲裁规则（如：CV argmin 的 1-SE 内 → 稳定性最大 → presence 最简约）作为 MSU-Extract 的 K 决策，用 Islam 协议对**单一决策规则**打 F1-vs-K，替代一致率。

## P2

### 10.【P2】基因组卫生缺失：染色体白名单、性别机会校正、alt contig、chrM、T2T
- 机会向量必须匹配 callable 领域（男性 chrX、非整倍体片段、alt contig 重复计数）；**"跨 build 派生"概念混乱：ID83/CN48/SV32/RNA-SBS 标签本身 build 无关，签名矩阵 build-agnostic——真正的依赖只在外显子/panel 机会目录**。
- **修改**：contig 策略 + 逐样本机会向量（CN segments + 性别 + callable BED）；§6.2 改写；exome/panel 机会归一参考集为真正缺口。

### 11.【P2】"首个/空白"类声明相对档案自己引用的 2023–2026 文献属于过度声明
- sigfit/signeR/BayesPowerNMF 都产名义区间——"first"须收窄为"**首个对 exposure 区间做经验覆盖率测量**"；SigNet 已做低计数 refit；Morrill 2025 已是 formal 成分框架；**conformal"分布自由"在 N 异质下不成立**，需 grouped/weighted 分层校准。

### 12.【P2】多样本 VCF 与 germline/somatic 歧义：校验契约未接住
- MsVariants validator 未校验 somaticness 信号（FILTER、VAF 下限、matched-normal 来源）；ctDNA 下 CHIP/germline 污染是第一失败模式。
- **修改**：扩展校验（caller+normal provenance 必填、VAF floor、置信分类透传、低 VAF 灵敏度曲线）。

## 总体裁决与亮点
- **有条件信任**；基准论文（板块②）按设计+问题 6 补轴有真实贡献；板块①三个主角声明处于"会被认真评审人一页纸击穿"状态；HRD/RNA 按现状写入论文属临床危险与科学不诚实。
- 附注：M0–M8 ≈ 15–20 周不现实；建议砍 MSU-Tensor/MSU-Tempo 到 watch。
- **三件做得好**：源码级事实核查纪律；统计立场正确且一致（KL=计数 MLE、cosine 降级、χ²₁ 边界、precision/recall 立场）；诚实的竞争与许可定位。
