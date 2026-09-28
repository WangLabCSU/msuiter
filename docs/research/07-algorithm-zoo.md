# 调研报告 07：算法动物园完整盘点与自研方法机会清单
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-28。补齐前五份报告的覆盖缺口（20 项逐项核实），并产出分层算法动物园总表（驱动实现范围）与自研整合方法 shortlist。核实手段：Europe PMC/NCBI eutils/OpenAlex、GitHub 源码、规范文档直读。**[unverified]** 已标注。

---

## §1 缺口审计结论（20 项）

1. **musicatk**（Bioconductor 2.6.0, LGPL-3；Chevalier 2021 Cancer Research doi:10.1158/0008-5472/CAN-21-0899）：S4 `musica` 对象 = 变异注解 + 多通道计数表（SBS96/DBS78/ID/TSB/RS 及组合）+ `result_collection`（多算法×多 K）。发现：`algorithm="lda"`（topicmodels LDA，签名=exp(β)、exposure=γ）或 `"nmf"`（+ε 伪计数）。预测：LDA 后验或 decompTumor2Sig。含 UMAP/kmeans/cosine 比对/Shiny。**价值：多目录对象模型 + 主题模型一等公民——设计思想采纳。**
2. **signifinder**（Bioconductor, AGPL-3）：**域外**——基因表达肿瘤签名（RNA/芯片打分），非突变签名。排除。
3. **TBSignatureProfiler**（Bioconductor, MIT）：**域外**——结核转录组签名。排除。
4. **TensorSignatures**（Vöhringer, Nat Commun 12, 2021, doi:10.1038/s41467-021-23551-9；github.com/sagar87/tensorsignatures；PyPI 0.5.1 已停维护，TensorFlow 1.x）：**非负张量分解（NTF）+ 负二项噪声**，计数张量 = 通道 × 样本 × 组织 × 基因组属性箱（复制时序/转录方向/功能元件）；BIC 定 K；签名与"基因组状态响应曲线"联合学习。PCAWG 2,778 + HMF 3,824 应用。**价值：解决 96 向量 NMF 无法表达的"签名随基因组状态变化"——自研重实现目标（见 §3.1）。**
5. **Pollock**：**勘误**——Storrs et al. 的 pollock 是单细胞表达细胞类型分类器（ding-lab, Bioinf Adv 2022），**不存在 mutational signature 版本**（PubMed 零命中）。跳过。
6. **SigFormer**（Zhang, Niu, Zong; bioRxiv 2026-01-21, PMID 41648438, doi:10.64898/2026.01.20.700228, PMC12871590）：集合条件 transformer，参考签名集×样本目录 cross-attention；声称高噪声/过完备目录下胜 MuSiCal；**显式输出"不可归因残差"** 而非强拟合平坦签名。**预印本未同行评议；公开仓库已证实 = github.com/zonglab/SigFormer（MIT，README 自述 "mutational-signature decomposition and analysis toolkit for SBS96 profiles"；无 paper 引用，与 bioRxiv 预印本尚未互链）**。吸收思想：残差通道、噪声鲁棒 refit。
7. **mSigSDK / mSigPortal**：计算层 = SigProfiler 栈包装；无独立出版物索引；**"mSigSDK" 在 GitHub/PyPI/Bioconductor 注册表均零命中（2026-09-28 实证检索），未能证实此包存在**；门户 JSON schema 不可达 [unverified]。
8. **SIGNAL**：signal.mutationalsignatures.com = **Degasperi A et al., "A practical framework and online tool for mutational signatures analyses…", Nature Cancer 1:150–162, 2020, doi:10.1038/s43018-020-0027-5**。MutationalPatterns 捆绑其 2020-07-03 下载：reference / tissue-specific / exposure（**Kucab 2019 Cell 实验诱变签名**）+ artifact 四种形态。**许可（2026-09-28 读源码核实）= `signature.tools.lib` 的 LICENCE 文件为 BSD-3 式条款 + 学术研究专用限制（第 5 条禁用于临床照护；第 6 条限非营利机构且排除受营利实体委托/合作的研究；第 7 条要求修改版自由共享）——非标准 OSI 许可，**与 GPL 一样不可用于直接代码复用**，只可作算法语义参考。** 该仓库 `data/` 捆绑参考集可枚举（RefSigSBS_v2.03、RefSigDBS_v1.01、RefSigv1_Subs/Rearr、COSMIC_v3.2 SBS/DBS GRCh37、Breast560_rearrangement、PCAWG sigs、ConversionMatrix）。**Sanger 站点（reference/tissue-specific/exposure/artifact 四形态）为 JS 渲染，静态抓取不可达 [unverified]。**
9. **Nik-Zainal RefSig/层级**：v1 = Degasperi 2020 Nat Cancer；**v2 = Science 376:eabl9283 (2022)**（12,222 GEL WGS；**新增 40 SBS + 18 DBS**；common/rare；FitMS；层级 T1/T2/T3 common + T0–T4 rare 含 **QC amber/red artifact 签名**）——经 signature.tools.lib README 核实。
10. **USARC/CN40/CNV48/CN176 溯源**：USARC = Steele CD, Cancer Cell 35:441-456.e8, 2019（doi:10.1016/j.ccell.2019.02.002）；**CN40 = Wang S, PLoS Genet 17(5):e1009557, 2021**（sigminer 作者自己的方法）；**CNV48 = Steele Nature 2022**（48 分量 `CNstate:sizeclass` 标签，参考矩阵在 SigProfilerExtractor `data/CNV_signatures.txt`）；**CN176 = Tao Z, Wang S, … Liu X-S, Brief Bioinform 2023, doi:10.1093/bib/bbad053**（TCGA176/PCAWG176）。
11. **Drews 断点特征**：**Drews RM et al., "A pan-cancer compendium of chromosomal instability", Nature 606:976–983, 2022, doi:10.1038/s41586-022-04789-9**（7,880 肿瘤，**17 CN 签名**）；特征族 = segsize/bp10MB/osCN/bpchrarm/copynumber/changepoint（Macintyre 2018 扩展）；`calculateActivityDrews` 用 **`limSolve::lsei`** 拟合 `Drews2022_TCGA_Signatures`。
12. **Koh 2025 新 indel 分类**：**Koh GCC, … Zou X, Nik-Zainal S. "A redefined InDel taxonomy provides insights into mutational signatures." Nat Genet 57:1132–1141, 2025, doi:10.1038/s41588-025-02152-y**。动机：ID83 无法在等基因模型中分离 MMR/聚合酶修复缺陷签名。新分类 = **侧翼上下文 + 信息性基序（更长同聚体）→ 89 亚型 + 476 通道全目录**；100kGP 7 癌型 → **37 indel 签名（27 新）**；**PRRDetect** 修复缺陷分类器。软件：github.com/Nik-Zainal-Group/indelsig.tools.lib（`indel_classifier89`、`gen_catalogue89`、`indel_highspecific` 过滤 [丢弃重复≥10、indel>100bp]；NNLM 拟合）。**新的 indel 标准——原生支持即差异化。**
13. **损伤分离/雨量**：经典 = **Aitken SJ et al., Nature 583:265–270, 2020, doi:10.1038/s41586-020-2435-1**（复制链分相的链偏倚 run 扫描）；后续 Anderson Nature 2024（doi:10.1038/s41586-024-07490-1）、Ginno Nat Genet 2024（doi:10.1038/s41588-024-01712-y）、Spencer Chapman Nature 2025（SBS19 持续损伤）。实现仅最小仓库（J0bbie/LesionSegR、tomsasani/lesion-segregation）。Rainfall/kataegis：≥6 突变 + 平均间突变距离 ≤1000bp（Nik-Zainal 2012 Cell）；经典实现 maftools::rainfallPlot、MutationalPatterns::plot_rainfall。
14. **RTA/topography**：SigProfilerTopography（Otlu, Cell Reports 42:112930, 2023, doi:10.1016/j.celrep.2023.112930）= 染色质/组蛋白/TF/复制/转录对签名活性的地形效应。标准链偏倚检验 = MutationalPatterns `mut_strand/strand_bias_test`。**RTA 无规范独立工具**（仅 Yaacov 2023 临时指标；TensorSignatures 直接建模 RT 依赖）——确认空白。
15. **相似度/比较**：cosine 唯一事实标准（随机非负 96 向量的机会基线 ≈0.75，Islam 2022 计算）；sigminer 仅 cosine（源码核实）；decompTumor2Sig 另有 Euclidean/correlation/SIM(Shiraishi)；JSD/Hellinger 散落。**无原则性度量比较论文**（2022–2026 检索）；"signature ontology"/"MSpoisson" 不存在。空白。
16. **SuperSigs**：Afsari B et al., eLife 10:e61082, 2021（doi:10.7554/eLife.61082）。算法（TomasettiLab/supersigs 源码核实）：经嵌套划分/最小 σ-代数选"生存突变"（`generate_min_sigma_algebra`）+ 年龄校正逻辑回归 + 嵌套 CV 特征选择。Bioconductor **supersigs** v1.21.0。无后继。
17. **暴露回归/关联**：唯一形式化方法 = **Morrill Gavarró L, Couturier DL, Markowetz F. "A Dirichlet-multinomial mixed model for determining differential abundance of mutational signatures." BMC Bioinformatics, 2025, doi:10.1186/s12859-025-06055-x**（成分 DM 混合效应差丰模型）。其余应用文献全是 ad hoc Wilcoxon/Cox。**空白确认：无统一成分回归/生存框架。**
18. **VCF/MAF/BCF 标准**：VCF hts-specs **v4.5 现行**（多样本 FORMAT/AC/GT 倍性/符号 SV alt/左对齐+多等位拆分为编目前置）；BCF v2（BGZF + 索引随机访问）；MAF = TCGA/GDC 规范列（Chromosome/Start_Position/Reference_Allele/Tumor_Seq_Allele2/Tumor_Sample_Barcode/Variant_Classification）。多样本 VCF 拆分为逐样本目录是体细胞/生殖系混淆与倍性 bug 的高发点——typed IO 层是差异化。
19. **目录格式互操作矩阵**（全部源码核实）：SigProfiler txt（SubType/Type 表头 TSV）、COSMIC txt、SIGNAL txt、MutationalPatterns R 矩阵/RDS、**WTSI 长格式**（`MutationType|Trinucleotide|Sample|count`，老集合常见）、signature.tools.lib 目录、sigminer RDS、mSigPortal JSON [unverified]、**ICAMS**（steverozen/ICAMS，规范内存目录 + 链感知 + 归一化语义）、"MSA format/sigverse" 不存在。
20. **Benchmark 指标协议精确定义**（必须逐位复刻）：
   - **Islam 2022 提取协议**（Cell Genomics 2:100179, doi:10.1016/j.xgen.2022.100179）：每个提取签名 **对真值任一签名的最大 cosine ≥ 0.90 记 TP**；FP = 对所有真值 max cosine < 0.90；FN = 未被匹配的真值。Precision=TP/(TP+FP)；敏感度=TP/|truth|；F1。稳健性扫阈值 0.80–0.90。**逐提取签名贪心分类——非一对一 Hungarian**（一对一/一对多仅用于描述与 COSMIC 关系）。
   - **Jiang 2025 拟合协议**（bbaf042）：合成谱 = **负二项通道采样**、色散校准到真实重构精度；**匹配按活性>0（无 cosine）**：TP=真值>0 且估计>0；FP=真值0 估计>0；Specificity=(缺席且未归因)/缺席数；**scaled Manhattan = Σ|â−a|/n 突变**；**Combined Score = (1−scaled Manhattan) + Precision + Recall**；"合理重构"= cosine > 0.969（真实归因中位数）。
   - 加一：Medo 2024 doi:10.1038/s41467-024-53711-6（合成+真实 146 PCAWG >50k SBS）。

---

## §2 分层算法动物园总表

状态：**Rust**=引擎原生实现；**R**=R 接口实现；**Adapt**=外部工具基准适配器（仅 benchmark，不入 ms_* API）；**Skip**；★=自研改进候选。

### (a) 目录/表征
| 算法 | 语义 | 来源 | 状态 | 改进 |
|---|---|---|---|---|
| SBS96 | 规范替换通道 | Alexandrov 2013/2020 | Rust | ★ 基石，无损保留 |
| SBS384/1536/6144 | 上下文+链扩展 | PCAWG/SigProfiler | Rust | ★ 高分辨通道欠使用 |
| DBS78 | 双碱基通道 | Alexandrov 2020 | Rust | — |
| ID83 | 规范 indel | Alexandrov 2020 | Rust | 向后兼容 |
| **ID89/476** | 基序+侧翼 indel | Koh 2025；indelsig.tools.lib | Rust | ★ 新标准，早支持=差异化 |
| RS32/RS38/BRCA560 | 重排通道 | Nik-Zainal 2016; Degasperi 2020 | Rust | — |
| CN40/Drews21/CNV48/CN176 | 拷贝数特征空间 | Wang 2021; Macintyre 2018; Steele 2022; Tao 2023 | Rust | ★ 统一 typed 特征 IR |
| TSB/RT/组合通道 | 转录/复制链通道 | musicatk; MP | Rust | ★ 核心一等公民 |
| 张量表示（通道×样本×组织×属性箱） | 基因组状态感知 | TensorSignatures 2021 | Rust | ★ 见 §3.1 |
| musica 多目录对象 | 变异+多目录+结果一体 | musicatk | 设计概念 | ★ 对象模型采纳进 Rust 核心 |
| Shiraishi 特征向量 | 无上下文替代表示 | Shiraishi 2015 | Skip（互操作经外部） | — |

### (b) 预处理/归一化
| 算法 | 语义 | 状态 | 改进 |
|---|---|---|---|
| VCF/BCF 解析、左对齐、多等位拆分 | hts-specs v4.5 | Rust (noodles/hts-rs) | ★ typed、tested、流式 |
| MAF 导入（GDC 列） | 读时校验 | Rust | ★ |
| 机会归一化 | 基因组/外显子/panel | Rust | ★ panel/覆盖度感知——领域弱项 |
| 重复/可映射性/低复杂度过滤 | 不可靠区剔除 | Rust | ★ 统一过滤注册表 |
| 链/RT 注解（GENCODE/Repli-seq） | 逐变异注解缓存 | Rust | ★ 一等公民 |
| 深度下采样 | 跨样本公平 | Rust | — |

### (c) 提取
| 算法 | 语义 | 状态 | 改进 |
|---|---|---|---|
| KL-Poisson NMF MU（Brunet） | 行业核 | Rust | ★ 确定性重实现 |
| NNLS/HALS NMF | 快速交替 | Rust | ★ |
| LDA/主题模型 | 生成式多项 | Rust | ★ Poisson-NMF/LDA 统一 |
| 贝叶斯 HMC/Gibbs NMF | 后验 | Adapt（sigfit/signeR 仅基准对照） | — |
| ARD-NMF | 自动 rank | Rust | ★ |
| **NTF+负二项（基因组状态张量）** | 签名×属性响应 | Rust | ★ §3.1 |
| 监督提取（最小 σ-代数+逻辑回归） | 因子监督 | R（原生）+ Rust 核 | ★ 监督模块 |
| SigProfilerExtractor 全循环 | 参照标准 | Adapt（基准参照）+ Rust 重实现内核并对拍 | — |
| attention 单样本 refit（SigFormer 思想） | 残差通道 | Watch（无代码） | 吸收残差思想 |

### (d) K 选择
| 算法 | 状态 |
|---|---|
| 重采样稳定性 + cophenetic/dispersion/silhouette-MC（SigProfiler 套件） | Rust ★ 确定性重实现 |
| 重建误差 elbow/plateau | Rust（仅诊断） |
| 张量/NB 模型 BIC | Rust ★ |
| 留出似然（MuSiCal 式） | Rust（已审计语义） |
| SUITOR entry-wise CV | Rust ★ 头牌 |
| 贝叶斯边际似然（signeR/BayesPowerNMF） | Adapt |

### (e) 拟合/归因
| 算法 | 状态 | 改进 |
|---|---|---|
| QP/NNLS 目录拟合 | Rust | ★ 快路径 |
| 多项/Poisson EM 拟合 | Rust | ★ 默认路径 |
| mmsig EM + bootstrap 过滤 refit | R 移植 | — |
| MuSiCal 似然稀疏 NNLS | Rust（已审计） | 基准上击败 |
| SigProfilerAssignment 全套 | Adapt（参照） | — |
| FitMS 分层拟合（T1-T3/T0-T4 + unexplained 检测） | Rust 移植 | ★ 管线复用 |
| LDA 后验 refit | Rust | — |
| 低负荷专家（SigMA 式二项尾聚合） | Adapt | ★ §3.4 |
| 采样似然（sigLASSO） | Adapt | — |
| CN 特征空间约束 LS（Drews/Macintyre） | Rust | ★ 与计数空间 CN 拟合统一 |
| 逐突变后验分配 | Rust | ★ |
| SigFormer 式 attention refit | Watch | §3.4 |

### (f) 不确定性/推断
| 算法 | 状态 | 改进 |
|---|---|---|
| 签名/exposure bootstrap | Rust | ★ |
| 存在性 LRT（mSigAct 式） | Rust | — |
| HMC/Gibbs 后验 | Adapt | — |
| Profile likelihood/Fisher 信息 | Rust | ★（无人实现） |
| **Conformal 预测区间** | 新概念 | ★ §3.4 |

### (g) 拟合后分析
| 算法 | 状态 | 改进 |
|---|---|---|
| TSB 检验 | Rust | ★ per-signature（无人做） |
| RTA 指标 | Rust | ★ §3.6（无规范工具） |
| 损伤分离扫描（链分相 HMM/run） | Rust | ★ §3.6 |
| Rainfall/kataegis | Rust | — |
| exposure UMAP/kmeans + 差异 | Rust | ★ |
| **DM 混合模型差丰（Morrill 2025）** | R 移植 | ★ §3.5 |
| 生存/Cox 于 exposure | Rust/R | ★ §3.5 形式化 |
| 签名时序 vs CN 事件（TrackSig 式） | Adapt | — |
| HRDetect（probit 线性分类器+bootstrap） | Rust | ★ 系数逐位校验测试 |
| **PRRDetect**（ID89 修复缺陷分类） | Rust | ★ |
| 组织起源分类器（Nguyen 2022, doi:10.1038/s41467-022-31666-w） | 候选 | — |
| 系统发育感知 exposure 演化（PhySigs/Palimpsest） | Adapt | — |

### (h) 相似度/比较
| 算法 | 状态 | 改进 |
|---|---|---|
| cosine（机会基线≈0.75） | Rust | ★ 零校准阈值 |
| correlation/Euclidean/JSD/Hellinger | Rust | ★ §3.3 度量研究 |
| 签名层次聚类 | Rust | — |
| 1对1/1对多复合匹配 | Rust | ★ Hungarian + Islam 贪心双协议 |

### (i) QC/伪迹
| 算法 | 状态 | 改进 |
|---|---|---|
| artifact 参考签名（SBS17a/b、FFPE、化疗） | Rust 目录 | — |
| amber/red QC 层级 | Rust | ★ 融入拟合层级 |
| unexplained 残差检测 | Rust | ★ §3.4 |
| 目录合法性/低计数告警 | Rust | — |
| PoN/伪迹区域掩码 | Rust | ★ |

### (j) 模拟/生成器
| 算法 | 状态 | 改进 |
|---|---|---|
| 基因组真实放置模拟器（SigProfilerSimulator 式） | Rust | ★ |
| 场景生成器（容易/中/难） | Rust | ★ 精确复刻 Islam 2022 场景 |
| NB 通道采样器（色散校准） | Rust | ★ Jiang 协议 |
| SynSig 合成谱+评估 | Adapt（steverozen/SynSig） | ★ |
| CN 基因组模拟 | Adapt（markowetzlab/CINSignatureGenomeSimulation） | — |

---

## §3 自研整合方法 shortlist（自创机会清单——论文方法学核心）

1. **基因组状态张量引擎（"TensorSignatures done right"）**：TS 证明签名响应复制时序/转录/元件状态，但其 TF1 实现已死、无主流集成。自研：Rust NTF + NB 噪声 + GPU + BIC/LOO 定 K + 五模态共享 exposure。新颖性：首个多模态、多属性生成式签名模型。
2. **单一目录 IR、多通道投影**：indel（83 vs 89/476）、CN（40/21/48/176）、SV（32/38）散落互不兼容工具、拟合风格各异。自研：typed 目录中间表示 + 无损投影 + 跨投影一致性先验的联合 exposure。新颖性：跨模态统一 exposure 语义，首次让 CN 签名 benchmark 可比。
3. **校准相似度与匹配库**：cosine 唯一、阈值未校准、匹配协议不一致。自研：多度量 + 解析/经验零分布（按通道数×负荷）+ Hungarian/Islam 贪心/Jiang 活性三协议的精确参考实现。新颖性：领域缺失的"签名比较度量学"论文 + 参考实现。
4. **低负荷 refit：显式残差 + 覆盖保证**：SigFormer（无代码）主张 + SigMA 停滞 + 正常组织/ctDNA 痛点。自研：似然校准 refit + 稀疏先验 + 残差通道 + **conformal 预测区间**（分布自由覆盖保证）。新颖性：归因的分布自由保证——领域首创。
5. **成分暴露回归套件**：仅 Morrill 2025 DM 混合模型形式化了组间检验；无生存/病例对照/纵向框架。自研：DM/logistic-normal 混合模型（固定+随机效应、负荷 offset）+ Cox/AFT 扩展 + 多重校正；先复现 Morrill 再扩展。新颖性：首个统一暴露关联框架（R 侧旗舰）。
6. **损伤节奏分析（damage tempo）**：损伤分离 + TSB + RTA 一等公民化。自研：编目期流式链分相 run/HMM 扫描 + 校准 p 值 + 联合报告（segregation index/TSB/RTA/rainfall）。新颖性：逐样本整合"损伤节奏"剖面；与张量引擎 RT 箱联动。
7. **确定性高性能 NMF 核心**：SigProfiler 循环慢且跨运行非确定；K 选择碎片化。自研：Rust KL-NMF（MU+HALS）+ 确定性种子 + 重采样稳定循环；以精确复现 Islam 2022 F1 曲线认证。新颖性：认证确定性 + 快数量级——工程论文素材与全套可信度锚。
8. **互操作与溯源层**：目录格式碎片化、门户 schema 封闭、签名集版本/许可混乱。自研：已核实格式的无损导入导出 + 我们发布的 JSON schema（填补 mSigPortal 空白）+ 版本化可引用签名集包（病因/队列/许可/DOI）。新颖性：领域的"目录包管理器"。

**域外排除（已核实）**：signifinder、TBSignatureProfiler（表达签名）、pollock（细胞分类）。**不存在/未证实**：mSigSDK 公开版、mSigPortal schema、SigFormer 仓库、SIGNAL 许可与集数、"MSA format"、"sigverse"。
