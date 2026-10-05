# msuiter 功能覆盖矩阵（CAPABILITY-MATRIX）

> 版本：v1（2026-09-28）。**本矩阵是平台完备性的权威检查表**——系统枚举 mutational signature 分析的完整功能空间（数据 → 表征 → 识别 → 定量 → 推断 → 可视化 → 应用工作流 → 挖掘 → 平台层），逐能力标注：主流/先进方法、对等引擎（ms_* API）、默认方法、可视化交付、交付里程碑。每完成一个里程碑更新一次；任何"我们覆盖了 X"的声明以本矩阵为准。
> 状态图例：✅ 已设计（架构就绪）· 🔶 部分（v1 有基础版）· ⏳ 推迟 v1.x · 🔭 探索性 · ❌ 明确不做（Non-goals）
> 里程碑代号（唯一权威定义见 [ROADMAP.md](ROADMAP.md)）：**M0** 工程地基（v0.1）· **M1s** 引擎与目录核心（v0.1）· **M1c** 目录完备+ID83（v0.2）· **M2** 统一提取流水线（v0.2）· **M3a** 拟合三法+bootstrap（v0.2）· **M3b** MSU-Fit 校准统计（v1.0）· **M4** 相似度库+viz（v1.0）· **M6s** HRD 工作流（v1.0）· **M7** benchmark 完备+论文 · **M8** 发布工程。无 M5、无 M6（评审裁决取消，见 reviews/00 A4/A16）。

**如何回答"msuiter 覆盖了什么"**：用户三层需求 → ①识别与定量 = L-C + L-D；②基本可视化 = L-F；③应用场景工作流与可视化挖掘 = L-G；"没想到的" = L-A/L-B/L-E/L-H + 各层标注的 ⚡ 项。

---

## L-A 数据获取、QC 与预处理

| 能力 | 主流/先进方法 | 对等引擎（ms_* API） | 默认 | 可视化 | 里程碑 |
|---|---|---|---|---|---|
| 变异读取：多样本 VCF/BCF、GDC MAF、TSV、Xena | hts-specs v4.5；left-align + 多等位拆分 | `ms_variants()`（读时校验） | ✅ | — | M1s |
| 体细胞可信度：caller/normal 溯源、VAF floor、FILTER 透传 | 领域实践 | MsVariants validator | ✅ | 低 VAF 灵敏度曲线 | M1s |
| CNV 输入：ASCAT/ABSOLUTE/Battenberg/FACETS/PURPLE/SEQUENZA/PCAWG/CNVkit（allele-specific） | SPMG 8-caller 映射 | `ms_segments()` | ✅ | CN profile/circos | M1c(v0.2) |
| SV 输入：BEDPE、SV VCF、caller 输出 | 链→类推导 | `ms_sv()` | ✅ | SV profile | M1c(v0.2) |
| 参考基因组：BSgenome 兼容 + 2bit 快路径；GRCh37/38、T2T、mm9/10/39、rn6/7、自定义 | SPMG 预编码字节串思想 | `genome =` 参数 | ✅ 2bit 推荐 | — | M0/M1s |
| 注解缓存：转录链（GENCODE）、复制时序（Repli-seq 箱）、染色质/元件、mappability、callable BED | MP/TensorSignatures 数据管线 | 注解层（入 MsCatalog provenance） | ✅ | — | M1s–M4 |
| 样本 QC：负荷分布 + 机制级伪迹哨兵（初版交付 U-M4-02b；污染/性别核对 ⏳、Degasperi amber/red 忠实复刻 ⏳v1.x） | 领域实践（ICAMS/SigProfiler QC） | `ms_qc_report()` | ✅ 初版 | QC 仪表页 | M4 |
| 伪迹检测与清除：FFPE/oxoG 机制哨兵 + COSMIC 伪迹签名暴露份额（初版交付 U-M4-02b）、Excerno 式过滤 ⏳、amber/red 分级 ⏳v1.x | Degasperi 2022；Excerno | 伪迹签名拟合 + 过滤器注册表 | 🔶 初版 | 伪迹贡献图 | M4（amber/red 拟合层级 ⏳v1.x） |
| 超突变者分层：GMM cutoff + 排除 de novo + 强制 refit | SigProfiler | `ms_stratify_hypermutants()` | ✅ | 负荷分布 + cutoff 图 | M1c(v0.2) |
| 机会归一化：exome↔genome 转换器 + 自定义机会向量 ✅（U-M4-02c；似然内机会 ⏳v1.x、panel 内置表 ⏳无 [V] 锚） | sigfit 似然内机会；sig_convert | `ms_convert()` + 似然内机会 | 🔶 初版 | 机会分布图 | M4 |
| 深度下采样/公共深度 | SigProfiler | `ms_downsample()` | ✅ | — | M4 |

## L-B 目录表征

| 能力 | 方法/标准 | 对等引擎 | 默认 | 可视化 | 里程碑 |
|---|---|---|---|---|---|
| SBS 通道族：6/24/96/192/288/384/1536/6144 | COSMIC/SigProfiler（语义逐位） | `ms_tally(mode =)` | SBS96/192 | 全系 profile 图 | M1s/M1c |
| DBS 通道族：78/186/312/1248/2976 | SPMG Q-链规则 | 同上 | DBS78 | DBS profile/portrait | M1s(78)/⏳其余 |
| MNV/complex/double-indel 路由 + skip ledger | SPMG | `mnv.rs` + provenance | ✅ | — | M1s |
| ID 通道族：28/83/89/96/150/415/476 | ID83=SPMG 逐位；ID89/476=Koh 2025 | `indel83.rs`→`indel89.rs` | ID83（89⏳v1.x） | ID profile | 83=M1c；89=v1.x |
| CN 特征空间：CN48（Steele）/CN40（Wang）/Macintyre 36 分量/Drews 特征/CN176（Tao） | 各自原文 | `cnv_features.R`（统一 typed IR） | CN48 | CN48 谱/热图 | M1c(v0.2) |
| SV 通道：SV32/RS38/PCAWG16 | exactPcf clustered | `sv_features.rs/R` | SV32 | SV 谱/热图 | M1c(v0.2) |
| RNA-SBS192（非嘧啶归一化，12 ref>alt × 16 侧翼） | COSMIC v3.4+/TRACERx | `ms_tally(mode="rna_sbs")` | — | RNA profile | ⏳v1.x（随 RNA 工作流） |
| 多目录一体对象（musica 式）+ 目录 IR（无损粗粒化 fine→coarse；细粒化需变异级重算） | musicatk 概念 | MsCatalog 族 | ✅ | — | M1s/M1c |
| 目录模拟器：基因组真实放置、场景生成器、NB 校准采样 | SigProfilerSimulator/SynSig/Jiang | `ms_simulate()` | ✅ | 场景示意 | M7（内核 M1s） |
| 格式互操作：COSMIC txt + SigProfiler txt ✅（[V] 双格式，tests fixture 锚）、signatures 导入 ✅；WTSI 长格式 ⏳（无上游实样）、MP 矩阵/sigminer RDS/ICAMS 语义 ⏳ | 互操作矩阵（research 07 §1.19） | `ms_import/ms_export` | 🔶 双格式 | — | M4（余 ⏳） |

## L-C 签名识别（de novo 提取）——对等引擎矩阵

| 引擎（method =） | 主流来源/谱系 | 实现层 | 状态 | 默认 |
|---|---|---|---|---|
| `ms_nmf(engine="kl")` | Brunet KL-MU（SigProfiler/MP 金标准核） | Rust | ✅ M1s | **默认提取流水线的核** |
| `ms_nmf(engine="eu"/"hals")` | Lee-EU；HALS（RcppML 思想） | Rust | ✅ M1s/M2 | 可选 |
| `ms_nmf(engine="nsnmf"/"offset"/"lsnmf")` | R NMF 全家族 | Rust | 🔶（按需） | — |
| `ms_ard()` | SignatureAnalyzer ARD（Tan–Févotte；Broad 公式） | Rust | ✅ M2 | 分诊模式 |
| `ms_sparse()` | 体积正则 mvNMF（Leplat–Gillis）+ L1（SparseSignatures 思想） | Rust | ✅ M2 | 可选 |
| `ms_correlated()` | 相关性感知（Cornet/Paisley 谱系，自研优化） | Rust | ⏳ v1.x | 可选（预注册可证伪声明达标后按结果去留，reviews/00 A4） |
| `ms_tensor()` | NTF+NB 张量（TensorSignatures 现代重实现） | Rust | 🔭 v1.x | — |
| `ms_lda()` | 主题模型（musicatk/topicmodels 谱系） | Rust | ⏳ v1.x | — |
| `ms_hdp()` | mSigHdp（HDP；罕见签名敏感） | Adapt（bench 对照）→⏳自有实现 v1.x | ⏳ | — |
| `ms_bayes()` | signeR Gibbs / sigfit HMC / BayesPowerNMF 幂后验 | Adapt（bench）→⏳ | ⏳ | — |
| `ms_supervised()` | SuperSigs（最小 σ-代数 + 逻辑回归） | R 原生 | ⏳ v1.x | — |
| 深度学习提取器 | 无可信赢家（research 01 §8） | ❌（只吸收残差思想） | ❌ | — |
| **共识-CV 流水线（默认）** | SigProfiler 共识 + SUITOR CV + 多证据 K 仲裁（自研整合） | Rust+R | ✅ M2 | **`ms_extract()` 默认** |

**K 选择全集**（`ms_select_k()`）：cophenetic/dispersion（诊断）、silhouette 共识、SUITOR entry-wise CV、bi-cross-validation、似然剪枝、ARD 自动 K、BIC、gap、Wilcoxon（诊断）、随机基线对照 → 默认仲裁规则（CV argmin → 稳定性 veto → 诊断报告）。✅ M2（部分诊断 ⏳）。
**提取前策略**：超突变分层 ✅、common/rare 两阶段（atlas 工作流）🔶v1.x、去噪 🔶。

## L-D 签名定量（fitting/attribution）——对等引擎矩阵

| 引擎（ms_fit method =） | 主流来源 | 实现层 | 状态 | 默认 |
|---|---|---|---|---|
| `"nnls"` | Lawson-Hanson（deconstructSigs/MP 系基线） | Rust | ✅ M1s | 起步基线 |
| `"qp"` | SignatureEstimation QP（Σe=1） | Rust/quadprog | ✅ v0.2 | 可选 |
| `"likelihood"`（bidirectional） | MuSiCal 语义（ϵ=0.001 逐步） | Rust | ✅ v0.2 | **MSU-Fit 主模式** |
| `"lrt"` | PASA/mSigAct（NB χ²₁ 前向搜索） | Rust | ✅ v0.2 | **MSU-Fit 主模式** |
| `"em"` / 后向消元 | mmsig/MP strict | R | 🔶 v0.2 | 血液肿瘤兼容 |
| `"lasso"` | sigLASSO/StarSignDNA（L1 Poisson MAP） | Rust | ⏳ v1.x | — |
| `"bayes"` | sigfit/signeR 后验 | Adapt→⏳ | ⏳ | — |
| `"sa"` / `"anneal"` | 模拟退火（sigminer SA/STL） | R | ⏳ v1.x | — |
| `"best_subset"` | MP best_subset（小目录穷举） | Rust | ⏳ v1.x | — |
| 暴露稀疏化：bleedingFilter/auto_reduce/清零规则 | STL/sigminer/sigfit | R/Rust | ✅ v0.2 | 可选 |

**目录管理**：COSMIC v3.2–3.6 版本化 ✅、器官 RefSig T1–T4 层级 🔶v1.x、暴露签名面板（Kucab/SIGNAL）🔶v1.x、connected 组（SPA/MuSiCal 清单差异显式化）✅、背景强制（SBS1/5）✅、病因/伪迹子群 ✅、父/子签名策略 ✅。
**不确定性（MSU-Fit）**：bootstrap CI（支撑条件）✅、χ²₁ LRT p/q ✅、Fisher 内点 ✅、conformal（Mondrian by TMB）🔶v1.x、贝叶斯后验 ⏳、**覆盖率校准协议** ✅（M3b）。
**每突变分配**：比例分配 + unassigned 残差伪签名 ✅ v0.2、贝叶斯分配 ⏳。
**相似度/匹配（校准相似度库，`ms_compare()`，框架组件）**：cosine（零校准：签名/目录双零分布面 `ms_compare_null_rust`，type-7 分位 + 冻结 MC-SE 容差）/correlation/JSD/Hellinger ✅（U-M4-01）、Hungarian 一对一（主）+ Islam 贪心 + Jiang 活性三协议 ✅（U-M4-01；Jiang 要求 k_est=k_ref 真值字典拟合口径）、熵匹配 Dirichlet 零分布 ✅（U-M7-pre 形状条件化面 `ms_compare_shape_null_rust`：Multinomial(N,u)/N 重构噪声条件化于参考形状与负荷——alpha_total=N 连续极限，无需熵二分；散点图 null_family = "shape_conditional" 直读）、签名聚类 ✅（ms_cluster_signatures：阈值图连通分量，确定性无 RNG，medoid + 尺寸表；阈值默认 0.90 Islam 线）。
**de novo→目录分解（签名注释）**：MuSiCal match 语义 + 平坦清理 ✅ v0.2。
**特殊模式**：panel/ctDNA 低计数（MSU-LowCount）🔶 v1.0、RNA 模式 ⏳v1.x、单细胞池化 ⏳。

## L-E 拟合后分析

| 能力 | 方法 | 状态 | 可视化 |
|---|---|---|---|
| 每签名 TSB 检验（无人原生做过，自研） | 泊松/二项 UTS-vs-TS + 不确定性传播 | ✅ v0.2 | 链偏倚图 |
| RTA / 复制时序不对称 | 自研（领域无规范工具） | ⏳ v1.x | RT 剖面 |
| 损伤分离扫描（Aitken 2020）+ rainfall/kataegis | 链分相 run/HMM | ⏳ v1.x | 损伤节奏轨迹图 |
| 签名时序（TrackSig 式 CCF 轨迹） | 变点 + 多项 EM | ⏳ v1.x | 轨迹图 |
| 组间比较：Wilcoxon 基线 + DM 混合模型（MSU-Infer）+ CoDA | Morrill 2025 复现+扩展 | 🔶 v1.0 起 | 森林图/箱线+检验注记 |
| 生存/临床关联（不确定性传播） | 多重插补 + Cox | ⏳ v1.x | KM/森林图 |
| 复合判定：HRD 报告（WGS-only 契约）、PRRDetect、MSI/MMR、组织起源 | HRDetect 系数/Koh 2025 | HRD ✅ v1.0；其余 ⏳ | HRD 报告页 |
| exposure 嵌入（UMAP/kmeans）✅ + 差异挖掘 ✅（ms_exposure_test：双组 Wilcoxon + BH，all-tied NA 面） | musicatk 思想 | ✅ M4 | 嵌入散点/聚类图 |

## L-F 基本可视化（ggplot2 原生；COSMIC 风格规范：规范序强制、官方调色板、类组分隔、双轴、矢量输出）

| 图型族 | 覆盖 | 里程碑 |
|---|---|---|
| 目录/谱图：SBS6/24/96/192/384/1536、DBS78、ID83(89)、CN48、SV32、RNA-SBS192——样本目录 + 签名谱 + 参考谱 | ✅ 首批 8 图 M4，全集 M7 | M4/M7 |
| 原始 vs 重构对比面板（逐通道残差） | ✅ M4 | M4 |
| exposure：堆叠柱 ✅、热图 ✅、riverplot ✅（ggalluvial Suggests，PI 许可 2026-10-05） | ✅ M4 | M4 |
| 相似度：cosine 热图、vs COSMIC 点图（cosine + 零分布经验 p 注记 ✅；ms_compare 逐对比 p_null/q_bh BH 矩阵 ✅——add-one MC + p.adjust，全格保守视图） | ✅ M4 | M4 |
| K 选择证据：CV 误差曲线 + 稳定性双线 + veto 线（U-M4-03 余项，ms_select_k 证据表直读） | ✅ M2/M4 | M4 |
| bootstrap：CI 误差条 + 稳定性柱（U-M4-03 余项）+ 覆盖率曲线（M3b 面）；分布直方图 ⏳M7（draws 不落 MsFit——升级臂） | ✅ M3b/M4 | M4 |
| 链偏倚/TSB 图、rainfall、损伤分离轨迹、RT 剖面 | 🔶（TSB v0.2，其余 v1.x） | 分期 |
| sample portrait 多上下文网格（SBS/DBS/ID 全家桶） | ⏳ v1.x | v1.x |
| CN/SV 专属：谱图+热图+circos 风格 profile | 🔶 v1.0 | v1.0 |
| 组比较/关联图（箱线+检验、森林图、富集点图） | ✅ v1.0 | M4/M6s |

## L-G 应用场景工作流与可视化挖掘

| 工作流 | 场景（research 03 排名） | 状态 | 挖掘/可视化交付 |
|---|---|---|---|
| `ms_atlas_fit()`（common/rare 两阶段 atlas 模式） | 图谱研究标准流程 | 🔶 v1.0 | 队列签名景观热图 + common/rare 桑基图 |
| `ms_hrd_report()` | 临床 HRD 复合（Top-1） | ✅ v1.0 | HRD 报告页（判定+不确定性+文本） |
| `ms_exposure_panel()` | 暴露归因流行病学（Top-3） | ✅ v1.0 | 地理/年龄/暴露关联图 |
| `ms_lowcount_report()` | panel/ctDNA（Top-5/9） | 🔶 v1.0 | 灵敏度界 + conformal 区间图 |
| 队列挖掘：签名×临床/基因组特征关联扫描 + 多重校正 + 可视化（**可视化挖掘层**） | 领域实践形式化（MSU-Infer） | 🔶 v1.0/v1.x | 关联热图/森林图/交互表 |
| `ms_damage_tempo()` | 损伤节奏（近零竞争） | ⏳ v1.x | 轨迹+检验综合图 |
| `ms_rna_report()` | RNA-only 队列（Top-8；G2 条件升级） | ⏳ v1.x | DNA-RNA 一致性图 |
| therapy forensics / cross-species / CHIP | Top-6/10 | ⏳ v1.x | 治疗时间线图 |
| 统一报告引擎（provenance 检查单、多页 HTML/PDF） | 领域无标准（空白） | ✅ v1.0 | 全工作流通用 |

## L-H 平台层

| 能力 | 状态 |
|---|---|
| 中心对象 + 工作流文法（Seurat 教义，D16） | ✅ 架构定稿 |
| 引擎注册表 + 第三方扩展 API + certified 治理 | ✅ 架构定稿，M0/M2 交付 |
| 溯源/报告标准（领域空白） | ✅ 全对象携带 |
| CLI（Rust bin，bench 与流水线用） | ⏳ v1.x |
| nf-core module / Docker / parquet 交换（Python 可消费） | ⏳ M8/v1.x |
| 教程文化：get-started → 全工作流 vignettes + pkgdown | ✅ 分期 M4–M7 |

### L-H API 表面（`ms_*` 名称全集；docs-sync CI 以本表对照 ROADMAP/ARCHITECTURE）

| API（`ms_*`） | 层 | 说明 | 里程碑 |
|---|---|---|---|
| `ms_variants()` `ms_tally()` `ms_extract()` `ms_fit()` `ms_compare()` `plot()` | L2/L3 | 统一工作流文法主干（六类变异同文法；换引擎不改管线） | M1s/M2/M3a/M4 |
| `ms_select_k()` | L3 | K 选择仲裁规则（CV argmin → 稳定性 veto → Wilcoxon 诊断） | M2（部分诊断 ⏳） |
| `ms_fit_bootstrap()` `ms_test_presence()` | L3 | bootstrap CI（支撑条件）与 presence LRT（NB χ²₁ + BH） | M3a |
| `ms_calibration_grid()` `ms_calibration_verdict()` `plot_calibration_curve()` `ms_calibration_sanity()` | L3 | 校准实验面：MC 覆盖率网格（`ms_calibration_grid_rust` 核面上装配）+ 判据窗 verdict + 覆盖率曲线图 + 真实数据降采样 sanity harness（sanity 永不写成 calibration 证据；数据获取/治理协议 inst/sanity/README.md，真实数据不入库） | M3b |
| `register_ms_engine()` `match_ms_engine()` `ms_engines()` | L3 | 引擎注册表扩展入口 + 字符串糖解析（A14，失败列全部可用引擎名）+ 已注册引擎目录；certified 三态治理（A17），non-certified 解析一次性告警 | M0 |
| `ms_engine()` `fit_engine()` `required_pkgs()` `ms_extract_signatures()` `ms_extract_exposures()` `ms_extract_fit_time()` | L3 | 引擎注册表 S7 泛型（`ms_extract_*` 为泛型访问器，仅后两者进 FFI 表面） | M0/M2 |
| `ms_benchmark()` | L3 | mlr3 式基准网格；non-certified 引擎显式 warning | M0 骨架/M7 完备 |
| `ms_sitrep()` | L3 | 环境/依赖/refdb/线程诊断 | M0 |
| `ms_qc_report()` `ms_downsample()` `ms_convert()` `ms_update_refdb()` | L2 | QC 报告、深度下采样、机会转换、参考库更新 | M0 骨架起（`ms_update_refdb()`）/M4 |
| `ms_import()` `ms_export()` `ms_segments()` `ms_sv()` `ms_simulate()` | L2 | 格式互操作、allele-specific CN / SV 输入、目录模拟器（ms_simulate 变异计数层第一版：multinomial/poisson/nb 三臂，VCF 级放置 ⏳M7） | M1c（CN/SV）/M4（互操作）/M7-pre（simulate） |
| `ms_stratify_hypermutants()` | L2 | 超突变者分层（分类+排除 de novo+强制 refit） | M1c |
| `ms_atlas_fit()` `ms_hrd_report()` `ms_exposure_panel()` `ms_lowcount_report()` `ms_rna_report()` `ms_damage_tempo()` | L4 | 应用工作流 | 见 L-G |
| `ms_nmf()` `ms_ard()` `ms_sparse()` `ms_lda()` `ms_correlated()` `ms_tensor()` `ms_supervised()` `ms_hdp()` `ms_bayes()` | L3 | 引擎工厂（S7 对象一等公民，字符串为糖；L-C/L-D 状态列为准） | 见 L-C |
| `ms_tally_rust()` `ms_extract_rust()` | L1 | **FFI 内部**（非用户 API 承诺；`docs/ffi-surface.md` 冻结管理，M0 起） | M0/M1s |

---

## ⚡ "你可能没想到的"清单（本矩阵新增覆盖）

1. **QC 是一等公民层**（L-A）：样本 QC 报告、伪迹检出清除、amber/red 分级——领域痛点（research 03 §11.5），非附加功能。
2. **机会归一化与 panel 机会目录**：WES/panel refit 用 WGS 参考会系统性偏置平坦签名——似然内机会 + `ms_convert()`。
3. **MNV/complex 路由与 VCF 拆分后的 DBS 重连**：不修则 SBS/DBS 目录系统性失真（语义正确性，非性能）。
4. **基因组卫生**：contig 白名单、性别机会校正、非整倍体逐样本机会、chrM 路由、T2T。
5. **模拟器作为平台能力**：零模型/场景生成器内置（benchmark 与测试共用），不是外部脚本。
6. **报告引擎与 provenance 检查单**：领域无报告标准——每次分析自带可审计元数据。
7. **校准诊断图**：覆盖率曲线作为一等可视化（MSU-Fit 的诚实性展示）。
8. **队列可视化挖掘**：签名×特征关联扫描 + 多重校正 + 图形化——应用论文的日常操作。
9. **对等引擎矩阵本身**：任何主流方法一行切换（D15），benchmark 文化日常化。
10. **Python/流水线互操作**：parquet 交换 + CLI + nf-core——领域重心在 Python，不锁死 R。

## 与 Seurat 类比的自检（D16）

| Seurat 成功要素 | msuiter 对应 | 矩阵落点 |
|---|---|---|
| 统一对象（Seurat object） | MsVariants/MsCatalog/MsSignature/MsFit | L-H |
| 工作文法（NormalizeData→…→UMAP） | ms_variants→ms_tally→ms_extract→ms_fit→ms_compare→plot | L-H |
| 全方法整合 | 引擎对等矩阵（L-C/L-D） | L-C/L-D |
| 默认可信流水线 | 共识-CV 流水线 + MSU-Fit/LowCount/Infer | §5 默认路径 |
| 教程/生态 | vignettes/pkgdown/nf-core/扩展 API | L-H/L-G |

**矩阵治理**：每个里程碑验收时由 PI 更新本矩阵（状态列 + 新增能力行）；docs-sync CI 校验矩阵中承诺的 ms_* 函数名与 ROADMAP/ARCHITECTURE 一致（枚举载体为 L-H「API 表面」表；ARCH/ROADMAP 出现而未列入该表的用户 API 视为 drift，ms_*_rust FFI 内部名除外，由 docs/ffi-surface.md 单独管理）。
