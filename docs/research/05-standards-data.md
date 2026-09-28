# 调研报告 05：数据标准、许可、基因组读取、可视化、Benchmark 与工程实践
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-27。除标注 UNVERIFIED 外均经实读页面/源码/仓库核实。

---

## 1. COSMIC 参考数据许可与分发

### 许可声明（已核实、引用）

COSMIC signatures 站点声明：签名下载虽不需登录，但**"use of the data is still subject to the COSMIC Terms and Conditions"**，条款在 **https://www.cosmickb.org/terms/**（旧 URL 302 到 cosmickb.org/licensing/）。要点（条款 2025-10-30 修订）：

- COSMIC 归 **Genome Research Limited（Wellcome Sanger 研究所）**所有；学术使用免费但是"非独占、免版税的学术使用权利"。
- **C(g) 条："COSMIC data may never be packaged or distributed further to a customer, such as via a download or on-premise installation"**——无商业许可（QIAGEN）不得打包再分发。
- 4.7 条禁止再分发、转许可、出售 COSMIC 或经公共互联网提供第三方访问（"Publication Enablement" 或商业许可除外）。
- 4.6 条：未经书面同意不得用 COSMIC 数据训练 AI 模型。披露限于带 COSMIC 版本致谢的出版物。

### 领域实际做法（全部经仓库核实）

| 工具 | 许可 | 捆绑 COSMIC 签名？ |
|---|---|---|
| SigProfilerAssignment（SigProfilerSuite） | **BSD-2-Clause** | 是——`data/Reference_Signatures/{GRCh37,GRCh38,mm9,mm10,mm39,rn6,rn7}/`，SBS/DBS/ID/CN/**RNA-SBS** txt，COSMIC v1→v3.6（含 exome 变体） |
| SigProfilerPlotting/MatrixGenerator/Extractor/Simulator | BSD-2-Clause | MatrixGenerator 带通道定义/TSB 参考；无签名矩阵 |
| MutationalPatterns | **MIT**（Bioc） | 是——`inst/extdata/signatures/`：snv/dbs COSMIC v3.1、v3.2（GRCh37/38/mm10），经 `inst/scripts/Format_signatures.R` 转成 MP 通道序 |
| deconstructSigs | **无 LICENSE 文件** | 是——signatures.cosmic.rda 等 |
| sigminer | MIT（CRAN） | 是——v3.1 SBS/DBS/ID/TSB + PCAWG176/TCGA CNS/RS + Nik-lab + SIGNAL |
| mSigPortal | GPL-3 | 以服务形式提供（JSON），不捆绑 |
| mmsig/sigfit/signature.tools.lib | 各异（**signature.tools.lib = BSD-3 式 + 学术专用限制（禁临床、限非营利、修改版须共享）；非 OSI 标准，按 GPL 级对待（仅公式参考）**） | 各自捆绑签名参考 |

### 解读与结论

**事实上的普遍实践**是再分发*数值签名矩阵*：它们源自同行评议论文（Alexandrov 2013、PCAWG/Alexandrov 2020），由**生成 COSMIC 官方签名文件的同一实验室（Alexandrov Lab）以 BSD-2-Clause**在 SigProfiler 套件中策划分发。没有任何签名分析包从 cancer.sanger.ac.uk 捆绑；大家都捆绑 SigProfiler 套件副本。COSMIC T&C 文本形式上禁止"打包或分发"COSMIC 数据，对签名矩阵本身沉默；实际法律接触面是 BSD-2 的 SigProfiler 文件。**这是解读，不是法律意见——T&C 与实践的正式差距应向用户标明（标记：法律模糊）。**

**建议：bundle（主）+ 按需下载（辅）**：
- 捆绑 SBS/DBS/ID/CN/SV/RNA-SBS 矩阵，**溯源钉死到 `SigProfilerSuite/SigProfilerAssignment` raw GitHub**（BSD-2 上游，与 COSMIC 内容逐字节一致），逐文件版本元数据（如 `COSMIC_v3.6_SBS_GRCh38.txt`）+ COSMIC 与 PCAWG 论文引用。MIT/Apache 打包 BSD-2 数据没问题。
- 按需下载走同一 GitHub raw 镜像（稳定、活跃：v3.5 2026-01、v3.6 2026-07），**不走** cancer.sanger.ac.uk（登录门、T&C 限制、无稳定 raw URL）。
- mSigPortal JSON 与 USARC xlsx 为次级便利镜像。

## 2. 通道标准与历史

### SBS96 —— 野外存在两种不兼容行序（已核实）

1. **"COSMIC/SigProfiler 序"（侧翼优先）**——COSMIC v3 txt、SigProfilerAssignment、SigProfilerPlotting、sigminer 使用。外循环 = 5'碱基(A,C,G,T)，再 6 替换类，再 3'碱基：`A[C>A]A A[C>A]C ... A[T>G]T C[C>A]A ... T[T>G]T`。
2. **"Nature-2013/deconstructSigs/MutationalPatterns 序"（替换类优先）**——deconstructSigs `signatures.cosmic.rda` 列名与 MP `mut_96_occurrences.R`（tidyr::crossing 以替换类优先）核实：`A[C>A]A ... T[C>A]T A[C>G]A ... T[T>G]T`。

**已知不匹配 bug**：MutationalPatterns GitHub **issue #60 "Order of SNV types in mutation matrix"** 正是这个坑；MP 维护者确认其 COSMIC 参考已预转换为 MP 序。deconstructSigs 喂入 COSMIC 序目录会静默产出错误 exposure。**新工具必须：(a) 内部固定一种规范序；(b) 按标签而非位置校验输入行序；(c) 提供转换器。**

### 规范标签清单（抓自 SigProfilerSuite/SigProfilerAssignment@HEAD，COSMIC v3.6 文件）

**⚠️ per-build 可用性矩阵（2026-09-28 复核修正）**——镜像并非"五类 × 全部 build"：

| build | SBS | DBS | ID | CN | SV | RNA-SBS |
|---|---|---|---|---|---|---|
| GRCh37 | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| GRCh38 | ✓ | ✓ | — | — | ✓ | — |
| mm9/mm10/mm39 | ✓ | ✓ | — | — | — | — |
| rn6/rn7 | ✓ | ✓ | — | — | — | — |

（ID/CN/SV/RNA-SBS 的缺失 build 需自行派生或按标签跨 build 转换——架构已相应调整。）
另外列数核实：SBS 文件 = 96 行 + 表头 102 列（Type + 101 签名）；DBS 23 列（22 签名）；ID 26（25）；CN 27（26）；RNA-SBS 6（5）；SV 13（12）。

- **SBS96**：`A[C>A]A … T[T>G]T`（侧翼优先）。
- **DBS78**：`AC>CA AC>CG … TT>GG`（56 二核苷酸上下文类 × 组内 3 个 ref>alt；组序 AC×9, AT×6, CC×9, CG×6, CT×9, GC×6, TA×6, TC×9, TG×9, TT×9）。
- **ID83**：`1:Del:C:0…5`、`1:Del:T:0-5`、`1:Ins:C:0-5`、`1:Ins:T:0-5`、`2..5:Del:R:0-5`、`2..5:Ins:R:0-5`、微同源 `2:Del:M:1`、`3:Del:M:1-2`、`4:Del:M:1-3`、`5:Del:M:1-5`（共 83）。
- **CN48**（`COSMIC_v3.6_CN_GRCh37.txt` 精确 48 行）：`0:homdel:{0-100kb,100kb-1Mb,>1Mb}`(3)，然后 `1:LOH:`、`2:LOH:`、`3-4:LOH:`、`5-8:LOH:`、`9+:LOH:`、`2:het:`、`3-4:het:`、`5-8:het:`、`9+:het:` 各 × {0-100kb,100kb-1Mb,1Mb-10Mb,10Mb-40Mb,>40Mb}（45 行）。语法 `<totalCN>:<LOH|het>:<segment-size>`。sigminer 有配套 `CN48-Map.txt`。
- **SV32**（`COSMIC_v3.6_SV_GRCh38.txt`）：{clustered, non-clustered} × {del, tds, inv} × {1-10Kb, 10-100Kb, 100Kb-1Mb, 1Mb-10Mb, >10Mb}（30）+ `clustered_trans` + `non-clustered_trans`（2）= 32。
- **RNA-SBS 192**（`COSMIC_v3.6_RNA-SBS_GRCh37.txt`——**仓库只有 GRCh37，无 GRCh38 RNA-SBS 文件**，已核实）：**192 行 = 12 个非恒等 ref>alt 类**（[A>C] [A>G] [A>T] [C>A] [C>G] [C>T] [G>A] [G>C] [G>T] [T>A] [T>C] [T>G]）**× 16 侧翼（5'×3'）**，即 `A[A>C]A` 式。**关键：不是嘧啶归一化的 6 类方案**——16 个 ref>alt 组合减 12 个恒等类。

### TSB / "192" vs "384" 消歧（SPMG 源码核实）

SPMG 定义 `tsb = ["T","U","N","B"]`、`tsb_I = ["T","U","N","B","Q"]`（indel 用 Q）、`bias_sort = {T:0,U:1,N:3,B:2,Q:4}`；`tsb_stat` 对 **24、384、6144** 上下文做链偏倚检验。故：
- **SBS24** = 6 替换类 × 4 链态（T/U/N/B）——纯链偏倚。
- **SBS192**（`save_tsb_192.py`）= 96 × {T,U}——仅转录区链。
- **SBS384** = 96 × 4；**SBS6144** = 1536 × 4；sample portrait 另用 SBS1536 与 DBS312。
- sigminer TSB 模式 = 192 (T/U)；MutationalPatterns `mut_matrix_stranded` = 192；COSMIC 公开 TSB 矩阵按 T/U 192 风格（COSMIC 站点文件细节 UNVERIFIED）。

## 3. 基因组上下文获取性能（Rust 快路径依据）

- **SPMG (Python)**：下载基因组 FASTA → `save_chrom_strings.py` 把**每条染色体转为纯文本单字符串文件**缓存于 `references/chromosomes/chrom_string/<genome>/`；运行时打开 `chrom+".txt"` 做字符串切片。快靠平坦文件缓存，代价是 ~3.2 GB 磁盘缓存 + 安装步骤。
- **MutationalPatterns (R)**：`Biostrings::getSeq(BSgenome, gr)` + 标签构建 + `factor(levels)` 计数。
- **sigminer/deconstructSigs (R)**：多次 `BSgenome::getSeq`。
- R 原生性能面（推理，未基准）：BSgenome 全载（~3 GB 人）后 getSeq 快但载入重；`Rsamtools::FaFile`（htslib faidx）C 速但逐调用开销；**`rtracklayer` 原生支持 2bit**——内存最轻的索引 R 路径；`chartr/substr + match` 对哈希表是最快纯 R 后处理。
- **Rust 快路径（crates 已核实，2026-09）**：
  - **`twobit` 0.2.2**（jbethune/rust-twobit, MIT, 2026-03, ~14.8k 下载）：纯 Rust 零依赖 UCSC 2bit 读取器，索引随机访问 `read_sequence("chr1", 48..74)`、**`open_and_read` 全内存缓存模式**、N-mask 支持。
  - **`noodles` 0.116.0**（活跃，2026-08）+ `noodles-fasta` 0.66.0 + bgzf：生产级索引 FASTA。
  - `bio` 4.0.1（rust-bio）；`rust-htslib` 1.0.1（2026-06, ~667k 下载，BAM/BCF 互操作备选）。
- **零拷贝 2bit 读取器草图**：`memmap2::Mmap` .2bit → 解析头/Pair 索引 → 按染色体分组变体批 → 仅解码所需 4bit 打包字到预分配缓冲 → Rust 内构建 `X[N>M]Y` 标签 → 只回标签索引给 R。WGS 目录每变体最多需 ±1..7 碱基，磁盘索引随机访问已近最优；单 mmap + 排序区间解码避开了 BSgenome 3GB 载入与 Python 字符串缓存 3.2GB 磁盘。**先例核查：未发现任何主流 R/Bioconductor 包经 Rust 读参考基因组（最佳认知）**——r-polars 是最近的工程模板。

## 4. 可视化格局

- **SigProfilerPlotting**（matplotlib, BSD-2, 2026-09 更新）：plotSBS/DBS/ID/CNV/SV（签名谱与逐样本计数、percentage 选项、aggregate）；`sample_portrait.samplePortrait()` 需全网格矩阵；官方 R 包装 SigProfilerPlottingR。**事实风格标准**（堆叠色柱、类分组通道、顶%/底计数双轴、三核苷酸子标签）。
- **sigminer**（ggplot2）：show_sig_profile（mode=SBS/copynumber/DBS/ID/RS; style=default|cosmic——cosmic 式忠实 SigProfiler）、show_sig_exposure、show_catalogue、show_sig_similarity、bootstrap 稳定性图。
- **MutationalPatterns**：~30 个绘图函数——plot_96/192_profile、plot_contribution(_heatmap)、plot_compare_profiles、plot_original_vs_reconstructed、plot_cosine_heatmap、plot_river、plot_rainfall、plot_spectrum、plot_strand_bias、plot_enrichment_depletion、plot_lesion_segregation 等。
- **mSigPortal**（NCI web）：目录/谱图、vs 参考比较、聚类 cosine 视图、exposure 汇总；mSigSDK 支持私有大规模计算。
- 其他：YAPSA、signeR、musicatk、signifinder、TBSignatureProfiler（r-universe 轨道核实）。

### 现代实现的规范图型清单（~18）

1. SBS96 样本目录柱图（计数/%）；2. SBS6/24 迷你目录；3. de novo 签名谱；4. TSB 192 谱；5. DBS78 谱；6. ID83 谱；7. CN48 谱/热图；8. SV32 谱/热图；9. sample portrait 多上下文网格；10. exposure 堆叠柱；11. exposure 热图；12. cosine 相似度热图（样本×签名）；13. 相似度点图（签名 vs COSMIC，q 值注记）；14. 原始 vs 重构对比面板；15. riverplot；16. rainfall 图；17. 链偏倚/TSB 统计图；18. bootstrap 稳定性曲线 + contribution bootstrap。另有富集/区域图（MP 系）。

**ggplot2 原生要求**：矢量输出一等公民（cairo_pdf/svglite；SPP 已产 PDF）、COSMIC 6 类规范调色板 + DBS/ID/CN/SV 调色板、类组分隔与底部注记条（192 的 T/U 链条）、顶%/底计数双轴、小倍数 facet 网格、签名排序控制（字母 vs COSMIC）、**输入顺序校验**（§2）。CRAN 无签名可视化专门包（扫描核实：仅 mutSignatures 与 aws.signature 误命中；"SigVis" 不存在）。

## 5. Benchmark 基础设施

### 公共生成器/数据集（全部核实）

- **SigProfilerSimulator**（SigProfilerSuite, BSD-2）：上下文保持的真实 SBS/DBS/ID 目录模拟；论文 Bergstrom et al., BMC Bioinformatics 2020;21:438。**领域标准零模型生成器。**
- sigminer `simulate_catalogs`——R 原生生成器。
- **Medo 2024**：12 拟合工具 × 合成目录（8 癌型经验签名权重）+ PCAWG 真实数据（146 样本 >50k SBS）。**代码+合成数据：https://github.com/8medom/SigFitTest**（Code availability 核实）。
- **Jiang 2024**：**代码/数据：https://github.com/Rozen-Lab/sig_attribution_paper_code 与 Rozen-Lab/sig_attribution_low_variance**（核实）。
- **Islam 2022**：提取工具基准标准（>20k 肿瘤 + 模拟）。
- **Wu 2022**：相关性签名基准 doi:10.1038/s41598-021-04207-6。
- PCAWG 目录：mSigPortal 公共项目服务（生产应用 CBIIT/nci-webtools-dceg-mSigPortal；本环境无法 pin 直链——引 portal）。

### 现代 benchmark 套件（scIB 式）设计建议

- **场景网格**：TMB（10²–10⁶）× 活跃签名数（1–20+）× 签名相关性（0/中/高——按 Wu 2022）× exposure 稀疏度 × 噪声（Poisson 重采样）× 平台（WGS/WES/panel 经外显子/BED 机会掩码）× 参考误设（真签名缺席——Medo 关键压力源）。
- **指标**：签名检出 precision/recall/F1（带匹配容差）、exposure 误差（L1 + 逐样本 cosine）、重构 cosine、运行时/内存；**缺席签名的误分配质量（exposure bias）**。
- **Top-5 具体采纳**：(1) SigProfilerSimulator（上下文保持零模型）；(2) SigFitTest 合成+PCAWG 目录（Medo）；(3) Rozen-Lab synthetic_data + 基准 harness；(4) Wu 2022 相关性生成器；(5) mSigPortal PCAWG/TCGA 公共目录作真实数据锚。

## 6. 可复现性与工程实践

- **种子**：SigProfilerExtractor 文档化 `seeds` 参数（Seeds.txt 复现）；**SigProfilerAssignment 未见种子参数（搜索核实）**。建议：全链路一等公民种子控制、逐运行持久化（Seeds.txt 式）。
- **容器/分发**：无官方 SigProfiler Docker（Docker Hub 仅社区镜像如 lculibrk/sigprofiler ~1k pulls）；官方分发 PyPI + bioconda（bioconda: sigprofilerassignment 1.1.5、sigprofilerextractor 1.4.1、sigprofilermatrixgenerator 1.3.3——anaconda.org 核实）。
- **工作流生态**：nf-core/modules 含 **`sigprofiler`**（MatrixGenerator+Extractor，带测试）与 **`sparsesignatures`**（R）——核实于 nf-core/modules 树，均用 bioconda 容器。下一代工具应交付 PR-ready 的 nf-core module。
- **CI**：SigProfilerPlotting 有 GHA；sigminer/MP 用 testthat（快照/示例测试）；Bioc 多平台日检。标准实践 = testthat + golden-file fixtures + rcmdcheck + codecov。
- **r-universe**：`shixiangwang.r-universe.dev` 托管 sigminer（17 包）；r-universe 索引 YAPSA/MP/musicatk/signifinder/TBSignatureProfiler——可行的软发布通道。
- **CRAN 对 Rust 包的政策**（cran.r-project.org/web/packages/policies.html 引用）："Packages should be of the minimum necessary size"；"As a general rule, neither data nor documentation should exceed 5MB"；"Source package tarballs should if possible not exceed 10MB"（可申请适度放宽）；检查期多线程代码"绝不超过 2 并发"；示例"每个几秒内"；第三方代码"It is much preferred that third-party source software should be included within the package"（vendor tarball）。**注意措辞精度**：CRAN 并无字面上的"安装时禁止联网"条款，实际约束是"外部资源使用须最小化、必须 https、优雅降级、预编译二进制下载为最后手段且需 CRAN 同意"——结论不变：vendor 一切依赖。CRAN 有专门 **"Using Rust"** 页（cran.r-project.org/web/packages/using_rust.html，核实 200）。**模板：r-polars**——tools/prep-lib.R + lib-sums.tsv 校验和 vendor 全依赖树、安装时静态编译（repo 核实）。
- 另：检查期 2 线程上限 → rayon 需 `RAYON_NUM_THREADS` 感知/在 R 注册的线程数内运行（工程注记）。

## 7. 标准组织/社区

- **未发现 GA4GH 或 ELIXIR 的签名分析标准工作**（Europe PMC "mutational signatures"×ELIXIR/GA4GH 零相关命中；无 "recommendations/consensus/guidelines/handbook" 题名论文）。标记：2026-09 核实缺席。
- 事实标准：COSMIC 策展（Tudor et al. NAR 2024 doi:10.1093/nar/gkad986）、PCAWG 统一处理（Alexandrov Nature 2020）、NCI mSigPortal（Zhang et al. AACR 2021 doi:10.1158/1538-7445.am2021-211）+ mSigSDK（doi:10.48550/arxiv.2308.02995）。
- mSignatureDB（NAR 2018 doi:10.1093/nar/gkx1133）存在；无"签名分析手册"出版物（核实缺席）。最接近报告指南的是基准论文建议（Medo 2024、Jiang 2024）——**新生态可经"报告检查单"（签名目录版本、基因组 build、通道顺序、拟合方法、参考约束策略、种子）填补此空白。**

## 8. 关键文件路径 / 后续 URL

- COSMIC T&C: https://www.cosmickb.org/terms/ ；licensing: https://www.cosmickb.org/licensing/
- 参考签名镜像（BSD-2）: https://github.com/SigProfilerSuite/SigProfilerAssignment/tree/HEAD/SigProfilerAssignment/data/Reference_Signatures/
- 排序转换范例: UMCUGenetics/MutationalPatterns `inst/scripts/Format_signatures.R`；排序 issue：UMCUGenetics/MutationalPatterns#60
- 基准: https://github.com/8medom/SigFitTest ；https://github.com/Rozen-Lab/sig_attribution_paper_code
- Rust: crates.io/crates/twobit（jbethune/rust-twobit）、noodles、bio、rust-htslib
- CRAN Rust 政策: https://cran.r-project.org/web/packages/using_rust.html ；vendor 模板: https://github.com/pola-rs/r-polars（tools/prep-lib.R, lib-sums.tsv）；string2path（CRAN + vendor.tar.xz）

**未验证/含糊项内联标注**：COSMIC T&C 与实践的正式法律差距；mSigPortal 生产 API 稳定性；sigminer CRAN 许可 ID；SigProfilerAssignment 种子支持缺席；MP ID 通道标签方案 vs COSMIC ID83 排序；Rust 读基因组的 R 包先例缺席（最佳认知）。
