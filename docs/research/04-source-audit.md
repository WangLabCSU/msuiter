# 调研报告 04：软件源码逐仓深度审计
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-27。所有仓库浅克隆至 /tmp/audit/<NAME>，除标注"not read"外均为源码级阅读。字段：语言/LOC、许可证、核心算法文件（精确路径）、引擎、输入输出、值得采纳的独特思想、性能相关模式、维护状态。

---

## 1. SigProfilerMatrixGenerator（AlexandrovLab）— 最关键仓库

- **语言/LOC**: Python，包总计 ~13,700 LOC；算法集中于重构后的 4,057 行单文件。
- **许可/维护**: BSD-2-Clause；**非常活跃**——最后提交 2026-09-22（重构为 `SigProfilerMatrixGenerator/scripts/MutationMatrixGenerator.py`；旧的 `indel.py`/`dbs.py` 不复存在）。
- **基因组访问（关键工程决策）**：运行时无 pysam、无 2bit。`install_genome()` 下载**预编码的逐染色体原始字节文件**（`{chrom}.txt`，由 `save_chrom_tsb_separate.py` 构建）。每字节是 0–19 枚举，**同时编码碱基与转录链类别**（`SigProfilerMatrixGeneratorFunc.py:173-192`）：0–3=非基因 ACGT（"N" 偏倚），4–7=transcribed，8–11=untranscribed，12–15=bidirectional，16–19=N。运行时上下文获取是 `tsb_ref[chrom_string[start-1]][1]`——一次字典查找同时得到碱基+链。整条染色体以一个 Python bytes 串载入。**预编码注解烘焙——绝妙思想，可平凡移植到 Rust（每字节枚举，零哈希）。**
- **SBS**（`catalogue_generator_single`, `MutationMatrixGenerator.py:350`；上下文获取 `:778-788`；键 `:907-917`）：5 碱基窗口（start-3..start+1, 0-based）= 三核苷酸 ±1 五核苷酸；中间字符 ≠ REF 则跳过该突变；REF∈{A,G} 时 revcompl REF/ALT/序列并翻转偏倚（revbias 交换 T↔U, 1↔2）。键 = `"bias:XY[R>M]ZW"`。索引建于 `SigProfilerMatrixGeneratorFunc.py:1004-1024`：全部嘧啶中心 5-mer × 3 alt × 4 偏倚 {T,U,N,B} = **SBS6144 = 1536×4 TSB**；1536/384/96 由该索引字符串切片分组得出。
- **DBS**（`:484-694`）：双碱基替换 = 距离恰为 1 的相邻 SNV（`dinuc_sub == 1`, `:491`），同样本；MNV（距离 ≤ `mnv=5`）分离到 seqinfo。上下文 = 5'碱基 + `[XY>NZ]` + 3'碱基。方向规范化（`dinuc_tsb_ref = ["CC","CT","TC","TT","AA","AG","GA","GG"]`, `:484`）：若**原始参考二核苷酸**非嘧啶起始，标记偏倚 "Q"（链歧义）**且仍对整个 5-mer 做 revcompl 翻转到规范形**（`:673-694`）。主索引 **DBS2976** = 36 嘧啶起始型 × 16 侧翼 × 4 偏倚 (2304) + 42 Q 型 × 16 (672)；经索引字符串切片折叠为 78/186/1248/150/2400（`matrix_generator_DINUC`, `:3800`）。双向 "B" 计数以整除+余数归较大侧分割到 T 与 U（`:3925-3960`）。
- **INDEL（83 通道，精确算法）**（`catalogue_generator_INDEL_single`, `:1169-2100`）：
  1. 规范化；删除= `len(ref)−len(mut)==len(ref)−1`，插入=对称，否则**complex**（`:1407-1425`）。
  2. 链：取 indel 第一个受影响碱基；G/A 则 revcompl、标 strand −1、翻转偏倚。
  3. **重复检测**（del `:1455-1493`）：从 `start` 按 indel 长度为步长向后游走、向前从 `start+len` 游走，追加匹配的串联单元；**无窗口上限**。
  4. **微同源**（`:1494-1542`，仅 length>1 且非重复时）：`forward_homology = ref[1:-1]`（删除序列去掉末碱基）、`reverse_homology = ref[2:]`；从长到短：比较基因组 [start+len, start+len+i) 与 `forward_homology[:i]`，反向比较 [start−i, start) 与 `reverse_homology[-i:]`。平局 → 前向优先。插入对称于插入点。
  5. **通道键**（`:1659-1736`）：`key1:Del/Ins:key3:key4`；key1=长度封顶 5；key3="R"(重复)/"M"(MH)/1bp 时 "C"(嘧啶) 或 "T"；key4=R 时 `len(sequence)/key1 − 1`（封顶 5）、M 时 `len(sequence) − len(indel)`（封顶 0–5）、1bp 时 `len(sequence)−1`（封顶 5）。⇒ 83 通道（"1:Del:C:0"…"5:Del:M:5"）。`limited_indel` 模式将 MH 插入重映射为 R:0（32 通道简化版）。"complete" 子键存字面序列（G/A 起始则 revcompl）供 5bp 分辨率变体。
  6. **TSB 歧义规则**（`:1846-1857`）：累积重复/MH 序列全为 C/T 或全为 G/A 时事件链不可解析 → 偏倚 "Q" ⇒ **150 通道 ID-TSB** 矩阵。
- **CN48**（`CNVMatrixGenerator.py:21-69, 330-381`）：48 特征 = {homdel}×{0-100kb, 100kb-1Mb, >1Mb}(3) + TCN{1,2,3-4,5-8,9+}×{LOH,het}×5 尺寸箱(0-100kb, 100kb-1Mb, 1-10Mb, 10-40Mb, >40Mb)(25+20)。**注意 TCN1 只有 LOH（无 "1:het"）；homdel 仅 3 箱**。LOH 由 8 种输入格式各自的硬编码列名判定（ASCAT/ASCAT_NGS、ABSOLUTE、Battenberg、PURPLE、FACETS、SEQUENZA、PCAWG, `:75-232`）。**每段计数 1（无长度加权）**。长度 = (end−start)/1e6。
- **SV32**（`SVMatrixGenerator.py`）：`processBEDPE`（`:1037-1192`）——svclass 由断点链决定：(+,+)=缺失、(−,−)=串联重复、混合=倒位、异染色体=易位；size=|start1−start2|，5 箱（1-10Kb, 10-100Kb, 100Kb-1Mb, 1Mb-10Mb, >10Mb）；<1kb 的 SV 丢弃（易位除外）。`annotateBedpe`（`:797-930`）：**clustered** = 断点在 "kat region"：每染色体排序断点、算断点间距、对 log 距离跑 `exactPcf`（分段常数拟合，kmin=10 断点/染色体）、标记低于 `thresh_dist` 的区域、传播标记到断点落入区域的任何 SV。`tsv2matrix`（`:1193-1252`）：32 = {del,tds,inv}×5 尺寸×{clustered, non-clustered} + 2 易位通道。
- **引擎**：无。纯 Python 逐字符循环 + 逐字节字典查找 + pandas `.at[]` 增量 + 文件追加。无 BLAS、无 numpy（除矩阵初始化）、无线程。**SigProfiler 栈的最大 CPU 黑洞、最显性的 Rust 移植目标。**
- **I/O**：入 VCF/CSV（+BED、外显子/panel BED 过滤、按染色体拆分）；出 TSV 矩阵（SBS 96…6144、DBS 78…2976、ID 83/150/simple/complete、CNV48、SV32）+ 可选图 + seqinfo/MNV/complex 调试文件。
- **值得采纳的独特思想**：预编码基因组+注解字节串；全三类突变的 "Q" 链歧义通道族；主索引+字符串切片折叠的矩阵层级；严格 REF-vs-基因组校验 + 逐突变跳过日志。
- **RNA 上下文：不存在**（全包 grep——无 RNA 编辑代码；仅 TSB 变体）。"RNA SBS" 需另行实现。

## 2. MutationalPatterns（UMCUGenetics, Bioconductor）

- 纯 R（~60 文件）。**MIT**。3.7.1 (devel)；GitHub 镜像 2022-11-22 停更（Bioconductor 经 SVN/git.bioconductor.org 继续）。
- `extract_signatures.R`：`NMF::nmf(mut+0.0001, rank, method="brunet", nrun=200, seed=123456)`（KL MU，多核经 NMF 框架）或 ccfindR 变分贝叶斯。确定性播种默认。
- `fit_to_signatures.R`：**逐样本循环 `pracma::lsqnonneg`**（纯 R Lawson-Hanson NNLS）。
- `fit_to_signatures_strict.R`：**后向选择**——全拟合→丢弃贡献最低者→重拟合→重复；相邻迭代 cosine 相似度降幅 > max_delta (0.004) 时停；另有 **best_subset** 模式（穷举 n−1 组合；建议 ≤10–15 签名）。
- `mut_context.R:37-48`：**`Biostrings::getSeq` 移位 GRanges**（C 级 BSgenome 取数、向量化）——R 中"快速"数上下文的方式；随后字符串拼接通道键、`factor(levels=预计算)` + dplyr 计数。嘌呤起始突变 revcompl 上下文。
- `get_indel_context.R`：**有界**重复计数——取固定 19/20bp 侧翼、字符串替换计重复（`.indel_count_n_repeats`, `:546-566`）、取 max(left,right)；微同源同样窗口封顶。**比 SPMG 简单但封顶于窗口、且不符合 SPMG 精确 R/M key4 语义**（有界近似破坏可比性——反例教训）。
- 保留：通道因子级排序哲学、strict-refit 的 max_delta 概念、cosine 衰减图。替换：lsqnonneg 循环、NMF::nmf、全部 BSgenome 往返。

## 3. deconstructSigs

- R 1.9.0，**GPL≥2**，2020-08 停更（冻结）。
- **不是 NNLS**：贪心坐标下降——从最佳单签名起步（findSeed）；每步对每个候选做**黄金分割搜索**标量 δ（界 [−w_i, 100] ⇒ 强制 w≥0），取 SSE 最低的单坐标更新；相对误差改善 >1e-3 时重复。signatures.limit 封顶非零签名数。预过滤：某通道权重 ≥0.2 而样本占比 <0.01 的签名被剔除。权重 <0.06 清零、余量记 "unknown"。
- **教训**：全场最差求解器设计（R 闭包内逐坐标一维优化）——只配基准基线；其通道预过滤启发式是廉价可取的剪枝思想。

## 4. mmsig

- R 0.0.0.9000，**MIT**，2021-04 停更（研究代码）。
- **混合 EM**（`R/em_signatures.R`）：α 随机起步；E: `probs = (α⊗sig)/rowSums`（按突变频率加权）；M: `α = colSums(probs)/sum`；L1 收敛 <1e-5，max 2000 迭代。然后**后向消元**：逐个移除非强制签名→EM 重拟合→算 cosine 损失；min 损失 < cos_sim_threshold (0.01) 时丢最不伤者。默认 `force_include = c("SBS1","SBS5")`。
- TSB 模块：MutationalPatterns `mut_matrix_stranded` + 链偏倚检验 + mm1 上下文集（C[C>T]A 等）T:S 比检验；bootstrap CI；参考基因组校验。
- 采纳：EM+后向消元（快速逐样本拟合器）、强制包含清单、bootstrap CI。

## 5. signature.tools.lib（Nik-Zainal-Group）

- R ~19,200 LOC，v2.5.2，自定义 BSD-3 式（Degasperi），**活跃**（2026-08）。
- 拟合（`R/SignatureFitLib.R:24-40`）：默认 **KLD NMF 经 `NNLM::nnlm(loss="mkl", method="lee")`**（数学=Brunet KL 经 Rcpp）；备选 NNLS、模拟退火。**bleedingFilter**（`:424-473`）：见 02 报告。**bootstrap 拟合**（nboot=200）→ p 值过滤（boots≈0 比例）→ 中位数过滤 exposure。
- FitMS 层级（`R/signatureFitMultiStepLib.R:68-340`）：器官 T1/T2/T3；4 种多步模式：constrainedFit（lpSolve 约束常见拟合→正残差与罕见签名相关）、partialNMF、errorReduction（加罕见签名需 ≥ min % MAD 降幅）、cossimIncrease；逐深度累积至 maxRareSigsPerSample + 置换去重。
- 每突变分配（`assignMutationsSignatureProbability.R:12-120`）：P(突变来自签名 s) = e_s·sig_s[channel]/Σ_s′ —— plain exposure 加权通道后验；可选 "unassigned" 伪签名 = (catalogue−reconstruction) 正部。
- 提取（`SignatureExtractionLib.R`）：bootstrap 目录（nboots=20）× NMF（NNLM::nnmf 或 NMF::nmf brunet/lee/nsNMF）、跨 rank 聚类解。
- **HRDetect**（`HRDetect.R`, `applyHRDetectDavies2017` L916-975）：6 特征 `del.mh.prop, SNV3, SV3, SV5, hrd, SNV8`；score = sigmoid(−3.364 + Σ w_i·z(log(x_i+1)))；硬编码 means (0.218, 2.096, 1.260, 1.935, 2.195, 4.390)、sds (0.090, 3.555, 1.657, 1.483, 0.750, 3.179)、weights (2.398, 1.611, 1.153, 0.847, 0.667, 0.091)。特征计算含 HRD-LOH 指数（ascatToHRDLOH.R）、MH 缺失比例、SV3/SV5 计数。
- Indels：`vcfToIndelsClassification.R` + `microhomology.R`——Nik-Zainal 式 del.{repeat-mediated, MH-mediated, other}+insertions。**未找到 Koh 2025 分类。**
- 依赖注：NNLM、nnls、lpSolve、gmp、foreach/doParallel。**无 HDP（下游报告亦证实）。**

## 6. mSigAct + mSigTools + mSigPortal（Rozen 实验室）

- **mSigAct**（steverozen/mSigAct, v3.0.3, **GPL-3**, 活跃 2025-09）：存在性检验（负二项 LLH + nlopt GN_DIRECT→COBYLA + χ²₁）；MAPAssignActivity（稀疏逐通道整数分配，抽样式；未深读）；SparseAssignActivity。
- **mSigTools**: Rozen-Lab/mSigTools, GPL-3, 在 CRAN（相似度/关联工具，小）。
- **mSigPortal**: xtmgah/mSigPortal + CBIIT/nci-webtools-dceg-mSigPortal——GPL-3，非常活跃（2026-09-21）。**web 门户 + R 分析层**（Shiny 式模块 + 预计算数据 mSigPortalData），非算法库。仅借鉴 UX。
- 采纳：χ²₁ LRT + NB 似然 = "签名是否真的存在"的金标准检验，1:1 映射到 Rust 似然核；nlopt 全局+局部两段模式。**注意分支**：以上语义核实于默认分支 `v3.0.3-branch`；旧 `master` 分支行为不同（multinom 默认、nbinom.size=5 扁平）——复刻时以默认分支为准。

## 7. SUITOR

- R + C（`source/src/source.c`），**GPL-2**；repo 2022-03 停（Bioc 维护）。
- `suitor()`：**逐单元 k 折 CV × rank**；折模式作用于矩阵单元；每 rank×seed×fold：EM 拟合（`EM_alg` L257，缺失数据似然/矩阵变分框架）→ 留出 deviance；取最小误差 rank；getMV() 事后拟合。默认 k.fold 等（op 表部分读）。
- 采纳：留出单元 deviance 作为原则性 rank 选择器（比 bi-cross-validation 便宜，与共识法互补）。

## 8. signeR

- R + RcppArmadillo，v2.15.2，**GPL-3**，活跃。
- `src/gibbs_2.cpp`（426 行，全读）：分层贝叶斯 Poisson NMF（"BN2F"）。**7 块 Gibbs**：Z（逐突变通道→签名分配）、P（签名）、E（exposure）、Bp/Be（回归超参）、Ap/Ae（Gamma 先验 shape/rate）——带对数后验评估。后验样本汇总进 SignExp 类（均值/中位/sd + exposure 可信度）；超参经验贝叶斯；最优 K 由后验似然 BIC；协变量关联检验；自带 Shiny flow app。
- 采纳：posterior exposure 变异性作为不确定性产品；Z 分配块本质是贝叶斯每突变分配（呼应 STL posterior 思想）。

## 9. SparseSignatures

- R v2.23.0，**Apache-2.0**，Bioc 活跃（danro9685 = Ramazzotti）。
- `R/signatures.discovery.lasso.R`, `nmfLassoCV`：K × λ_α × λ_β 网格；β（签名）由 NMF 初始化、可选背景签名；**交替更新 + 经 nnlasso 包的 α（exposure）、β 的 L1 稀疏化**；模型选择 **bi-cross-validation**：掩 1% 单元、迭代预测/回填、MSE+loglik、50 重复。`signatures.assignment.lasso.R` 为给定签名的稀疏 refit。（已发表的 beta-binomial 变体被现 Bioc 包的 LASSO 版取代。）

## 10. pmsignature + decompTumor2Sig + HiLDA

- **pmsignature**：R+C++（Rcpp），v0.3.0，GPL-3。Shiraishi 特征向量表示（S4 `possibleFeatures`/`featureVectorList`，稀疏 (feature, sample, count)）；**C++ EM**（`src/EMalgorithm.cpp`：E 步逐模式/样本 aux θ、M 步 F 与 Q、可选背景 F0、`checkBoundary.cpp` 边界检查）。
- **decompTumor2Sig**（Bioconductor v2.14.0）：`Imports: quadprog(>= 1.5-5)` ⇒ exposure 拟合用 **QP**（quadprog::solve.QP），支持 Shiraishi 与 Alexandrov/COSMIC 双向转换。
- **HiLDA**（Bioc v1.27.0, GPL-3）：复用 pmsignature EM 谱系 + **两组层级检验**：exposure 作逐位点潜二元状态、EM + beta-binomial/normal 先验（`hilda_test.R`: pStates1/2, alpha, beta）检测两组全局暴露差。

## 11. CNsignatures + CINSignatureQuantification（markowetzlab）

- **CNsignatures**（脚本包，**MIT**，Macintyre；2023-08 停）——Macintyre/Boomgarden 管线精确定义（`main_functions.R`）：
  1. `extractCopynumberFeatures`（L68）：逐段——**segsize**(bp)、**bp10MB**（10Mb 箱断点数, `helper_functions.R:98-126`）、**osCN**（震荡=拷贝数交替计数）、**bpchrarm**（按着丝粒距离的段计数）、**changepoint**（相邻段边界 |ΔCN|）、**copynumber**(段 CN)。
  2. `fitMixtureModels`（L112）：逐特征 2–10 分量混合、BIC 选——segsize/changepoint/copynumber 用**高斯**，三个计数特征用**Poisson**（flexmix EM）。
  3. `generateSampleByComponentMatrix`（L192）：每段 `flexmix::posterior()` 隶属度按样本求和 ⇒ 样本×分量矩阵（标准 Breast 队列 BIC 选出 ~36 分量 ⇒ "36 分量混合"）。
  4. `generateSignatures`（L39）：`NMF::nmf(method="brunet")`；或 `quantifySignatures`（L27）：投影到预计算的分量×签名参考矩阵。
- **CINSignatureQuantification**（v1.2.0, "ASL" 许可，**非常活跃** 2026-09-08）：双特征管线（`calculateActivityDrews` = Drews 仅断点特征；`calculateActivityMac` = Macintyre 6 特征）。Exposure 推断 = **LCD**（`LinCombDecompSigs.R`）：`limSolve::lsei(A=component_by_signature, B=sample_by_component, G=I, H=0)`——带非负不等式约束的最小二乘，逐样本。+ de novo 提取、临床预测模块（铂响应）。
- 采纳：两种特征定义逐字保留（互操作）；参考分量 LCD 是 CN 签名定量的快路径（Rust 里 trivial 的有界变量 LS）。

## 12. TrackSig

- R + 少量 Py/Perl，**MIT**，2018 停更（休眠；姊妹 TrackSigFreq）。
- `src/change_points.R`：突变按 **CCF** 排序（VAF 经纯度/倍性校正）、沿轨迹分箱；**changepoint = 下三角累积设计矩阵上的 LASSO**（`cv.glmnet(alpha=1, lambda.1se)`）——非零系数=changepoint，得分段常数段；逐段 exposure 经**多项混合 EM**（`mixture_of_multinomials.R`，由总拟合初始化）；bootstrap 稳定性。
- 采纳：CCF 排序 exposure 轨迹概念 + 稀疏分段常数拟合（Rust 里 1-D fused-lasso 平凡且快）。

## 13. SigProfilerPlotting

- Python 单模块 10,000+ 行，BSD-2-Clause，非常活跃（2026-09-21）。
- COSMIC 风格图的构成（`sigProfilerPlotting.py`）：纯 matplotlib；逐通道**硬编码颜色组**（C>A 绿、C>T 红、C>G 黑+黄带技巧（堆叠双柱）、T>A 紫、T>C 蓝、T>G 灰；DBS/ID/SV 调色板在函数局部 colors 列表，如 L531、L711）；输入矩阵**重索引到规范 COSMIC 通道顺序**（`order_input_context`, L272-316）后绘制——6 子型分组 + 旋转上下文标签、样本归一 y 轴选项、PdfPages 多样本输出、自带字体；2025-26 新增 `sample_portrait.py`（需 SBS-6/24/96/384/1536 + DBS-78/312 + ID-83/28/96 全网格）。入口：plotSBS L2841, plotID L8475, plotDBS L10457, plotSV L1809, plotCNV L2280。官方 R 包装 SigProfilerPlottingR 存在。
- **教训**：图 = 90% 的"强制规范通道顺序 + 逐类颜色"；引擎永远输出规范顺序 → 绘图变成平凡 R/JS 工作。

## 14. NMF 引擎：NNLM 与 RcppML

- **NNLM**（linxihui/NNLM, v0.4.3, **BSD-2-Clause**, 2024-05 轻维护）：RcppArmadillo。交替更新 + **缺失数据支持**（`src/update_with_missing.cpp`）；方法 scd（KL 损失用二次逼近的序列坐标下降）与 lee（乘法）；损失 mse/mkl；正则接口 alpha/beta 向量 = [L1, L2, offset]（含经 W·W' 项的正交性, `src/nnmf.cpp:224-233`）；mask 支持；NNLS 入口。**signature.tools.lib 的发动机。**
- **RcppML**（zdebruine/RcppML, v1.0.0, **GPL≥3**, 活跃 2026-04）：Eigen/OpenMP 全重建（"FactorNet" 头库 `inst/include/FactorNet/`）：交替**逐列 NNLS**——坐标下降默认 + 批量 Cholesky-解后裁剪（`primitives/cpu/cholesky_clip.hpp`）、融合 NNLS、masked_nnls.hpp；Gram 矩阵 SYRK（`math/blas.hpp` 声称 ~1.7×）；稀疏 dgCMatrix 零拷贝映射、mask_zeros；rank 选择 speckled CV（`nmf/rank_cv.hpp`）；可选 CUDA；流式 .spz。README：大 k 建议 solver="cholesky"。
- **注**：两者均 GPL——许可内核里不得移植代码；*思想*（CD-NNLS + Cholesky-clip 备选 + SYRK Gram）是公共算法知识。
- **rust-NMF 补充**：`rust/src/lib.rs`（2,228 LOC）+ `fcnnls.rs`（535 LOC），栈 = ndarray 0.16 + rayon（无 BLAS、无 extendr——**它是 Python 包**）。基准：pbmc8k rank-10，lee 与 R NMF bit 等价 **76×**（1.65 s, 100 iters）；hals+NNDSVD 10 iters **~218–280×**（~0.45 s）；"NNDSVD init is the magic"。**GPL≥2——只作参考。**

## 15. IMAPR

- Perl+Python+shell（双比对 RNA 体细胞突变发现；detect_variants.pl、filter_variants.pl、stacking_model.py sklearn 集成）。**"Commons Clause" 许可 = 禁商用**。非 R 包，2023-06 停。借鉴点仅：RNA 变异可靠性过滤是 ML 式的。

## 16. Rust–R 集成现状（2026）

- **extendr**: **extendr-api 最新 0.9.0**（crates.io，2026-04-16 unyanked；0.8.2 为 0.8 系列末版），活跃，JOSS 论文；宏框架，可选集成 ndarray/serde/**faer**；rextendr（CRAN 0.5.0）脚手架。矩阵转换在边界**按拷贝**（96×N 级签名矩阵无所谓；基因组级缓冲避免跨界——保持 Rust 侧、只回小结果或预分配输出就地写）。ALTREP 支持存在但官方标注不稳定（issue #945/#743 未关）——v1 不依赖。
- **savvy**: v0.11.0, MIT, 活跃（yutannihilation，前 extendr 维护者）；显式 Sexp 包装、无隐式转换、极简 API；生产用户 r-polars 与 SedonaDB。文档明确：ergonomics 选 extendr、显式性选 savvy。
- **r-polars**（pola-rs/r-polars，活跃 2026-09-23，**不在 CRAN——是设计选择而非被拒**）：`src/rust/` workspace（Cargo.toml + lock + rust-toolchain.toml）；安装时 `configure` 二选一：(a) 编译 Rust 库，(b) **从 GitHub releases 下载预编译静态 `libr_polars.a` + SHA256 校验**（`tools/prep-lib.R`, `tools/lib-sums.tsv`；r-universe 上自动选 b）。**CRAN 政策禁止安装时联网** → CRAN 出局；分发走 GitHub releases + r-universe + Posit binaries。cleanup 从 tarball 剥离 Makevars/工具链文件。
- **CRAN + vendored Rust 已被证明可行**：**string2path**（在 CRAN，2026 更新）以 `src/rust/vendor.tar.xz` 打包全部 crate、安装时经 `Makevars.in` 解包 + `src/cargo_vendor_config.toml`（replace-with vendored-sources）+ cleanup 脚本。⇒ **CRAN 不允许 cargo 联网；必须 cargo vendor 并随包发布 tarball；依赖越小越好。**
- **faer**（sarah-quinones/faer-rs, MIT, 2.5k stars, 活跃）：全功能 Rust linalg；官方基准为图表（无法提取数字），定位为优化 BLAS/Eigen 平级或更好；extendr 有官方 faer 集成。**对本项目真实负载（k≤101 的微型 NMF/NNLS）而言，自写闭式/CD 内核比完整 BLAS 更相关；faer vendor 体积巨大需权衡。**
- Rust 基因组组学 R 先例：roxigraph（cboettig, extendr+Oxigraph, 在 CRAN）、bixverse（GregorLueg）。模板：r-polars、string2path。

## 17. 快速核实（存在性 + 一句话）

- **SigProfilerSingleSample**（SigProfilerSuite）：已知签名集的逐样本归因 + 每突变型概率；依赖 SPMG/plotting；2025-01 停；**repo 无 LICENSE 文件**（复用警示）。
- **SigProfilerSimulation**：**不存在**。
- **SigMA**（parklab）：低统计 SNV 数据的似然拟合（HRD/SBS3）；存在，基本休眠。
- "MSA MATLAB/loci2sig"、"lightsvd"：未找到。
- signature.tools.lib 无 HDP；"HDP-based CN signature tool" 未定位到（cpn-sigs 式名称未命中）——诚实标记：未审计。

## 18. 最终综合表

| 工具 | 算法 | 语言 | 许可 | 引擎 | 对 msuiter 复用价值 |
|---|---|---|---|---|---|
| SigProfilerMatrixGenerator | SBS/DBS/ID/CN48/SV32 目录构建 | Python | BSD-2 | 纯 Python 循环 | **关键**：需逐位复刻的通道语义 |
| MutationalPatterns | KL-NMF、lsqnonneg 拟合、strict refit | R | MIT | NMF/pracma/BSgenome | API 形态 + strict-refit 概念 |
| deconstructSigs | 贪心黄金分割坐标下降 | R | GPL≥2 | 无 | 反面基线；通道预过滤思想 |
| mmsig | 混合 EM + 后向消元 | R | MIT | 纯 R | EM 拟合器 + 强制包含清单 |
| signature.tools.lib | KL 拟合 + bootstrap + bleedingFilter + FitMS + HRDetect | R | BSD 式 | NNLM/nnls/lpSolve | 拟合管线语义、每突变后验 |
| mSigAct | NB 似然 LRT（χ²₁）、MAP 分配 | R | GPL-3 | nlopt | 检验数学可移植 |
| SUITOR | k 折单元 CV rank 选择 | R+C | GPL-2 | 自定义 C | rank 选择方法 |
| signeR | Gibbs BN2F | R+Rcpp | GPL-3 | Armadillo | 后验不确定性概念 |
| SparseSignatures | L1 交替更新 + 单元掩码 CV | R | Apache-2.0 | NMF/nnlasso | CV rank/λ 选择 |
| pmsignature / decompTumor2Sig / HiLDA | Shiraishi EM / QP / LDA 组检验 | R+Rcpp | GPL-3 | 自定义 C++ | 表示 + QP 思想 |
| CNsignatures / CINSignatureQuantification | 6 CN 特征 → GMM/Poisson 混合(BIC) → NMF/LCD | R | MIT / ASL | flexmix/limSolve | 精确 CN 特征定义 |
| trackSig | CCF 轨迹 + LASSO 变点 + 多项 EM | R/Py | MIT | glmnet | 轨迹概念 |
| SigProfilerPlotting | 规范顺序 + 类颜色绘图 | Python | BSD-2 | matplotlib | 绘图规范 |
| NNLM | KL/MSE NNMF (scd/lee) + 正则 + 缺失 | R+Rcpp | BSD-2 | Armadillo | KL-NMF 参考语义 |
| RcppML | 交替 CD/Cholesky-clip NNLS、CV、GPU | R+Rcpp | GPL≥3 | Eigen+OMP+CUDA | 仅性能思想（GPL） |
| rust-NMF | bit 等价 Lee/HALS + NNDSVD、fcnnls | Rust(Py 包) | GPL≥2 | ndarray+rayon | **NNDSVD 结论；基准对标** |

## 19. 必须逐位复刻的算法（bit-compatibility targets）

1. **SPMG INDEL 83 通道分类**——重复游走、MH 最长匹配（前向优先平局）、key1/key3/key4 封顶、1bp C/T 规则、Q-链同聚体规则、`limited_indel` 变体。源：`MutationMatrixGenerator.py:1169-2100`（+1659-1736、1846-1857）。
2. **SPMG SBS 方向 + 6144/1536 层级**——五核苷酸获取、嘌呤翻转、嘧啶中心索引。`MutationMatrixGenerator.py:778-917`；`SigProfilerMatrixGeneratorFunc.py:1004-1024`。
3. **SPMG DBS**——相邻 SNV 检测、dinuc_tsb_ref 规范化（含 Q 标记翻转）、78/186/1248/150/2400/2976 折叠（含 B 分割）。`:484-694`、`:3800-4057`。
4. **SPMG CN48 + SV32**——特征清单、逐 caller LOH、每段计数 1；SV 链→类映射、尺寸箱、kat-region 聚类（exactPcf kmin=10）。`CNVMatrixGenerator.py`、`SVMatrixGenerator.py:797-1252`。
5. **HRDetect Davies-2017 logistic**——上列精确系数。`HRDetect.py:916-975`。
6. **Macintyre/Drews CN 特征 + 36 分量后验求和**——`CNsignatures/helper_functions.R`、`main_functions.R`；CINsig `*Mac.R`/`*Drews.R`。
7. **mSigAct NB LRT**——2ΔlogLH ~ χ²₁ + GN_DIRECT+COBYLA 两段拟合。`SignaturePresenceTest1.R`。
8. **NNLM mkl/lee KL-NMF 更新语义**——复现 signature.tools.lib 兼容拟合（及 R-NMF brunet 的 bit 等价语义）。

## 20. 值得采纳的思想 / 反模式

**采纳**：预编码基因组+注解字节数组（SPMG）；全类 "Q" 歧义链通道；主索引+切片折叠一次计数多发矩阵层级；exposure 稀疏化三件套（STL bleedingFilter、mmsig/MP 后向消元 cosine-delta 停止、小签名库 best_subset）；每突变贝叶斯后验分配 + unassigned 伪签名；bootstrap p 值 + 中位过滤 exposure；NNDSVD 默认初始化 + HALS 少迭代模式；SUITOR 式留出单元 CV 定 rank；LRT 存在性检验（mSigAct）；强制包含清单（mmsig）；CRAN 策略 cargo vendor（string2path 模板）+ 预编译静态库（r-polars 模板）；extendr v0.8.2；基因组缓冲留 Rust 侧、引擎边界统一输出规范顺序（SPP 教训）。

**反模式**：整条染色体的解释器逐字节循环（SPMG 是警示不是范本）；R 循环逐样本 pracma::lsqnonneg（MP）；黄金分割坐标下降（deconstructSigs）；对 30 签名目录无正则过拟合（strict/LCD/EM-消元存在的原因）；逐样本 BSgenome 全基因组对象往返（MP）——Rust 一次遍历应发全部矩阵；窗口封顶的重复/MH 计数静默偏离 SPMG 键（MP indel——有界近似破坏可比性）；CRAN 包安装时联网下载（r-polars 出局原因）；GPL 引擎代码混入许可内核（RcppML/rust-NMF）；引擎输出与绘图通道顺序分叉——在边界一次性规范化。
