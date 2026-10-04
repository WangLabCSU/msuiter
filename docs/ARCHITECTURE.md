# msuiter 架构设计（ARCHITECTURE）

> 版本：**v2.2（2026-09-28，全库文档对齐版）**。评审证据：[docs/reviews/00-synthesis.md](reviews/00-synthesis.md)（裁决表）与 01–05 原文。调研底稿：docs/research/00–08（快照性质，见各篇头部声明）。完备性检查表：[docs/CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md)。
> 定位：**Rust 计算底层 + R(S7) 用户接口的 mutational signature 生态系统**；领域算法为可插拔组件（便于逐一 benchmark），自研统计推断层为论文 headline；科学准确性（声明与协议对齐）与简便性（S7 统一接口）统一。
> **v2.1 要点**（相对 v2）：统计契约成文（estimand/校准/边界）、conformal 降维到 Mondrian 分层、方法命名收缩为 MSU-Fit/LowCount/Infer 三方法、无状态 FFI、自研 RNG、线程不变性契约、双层验收术语、基准场景升级、refdb 治理、路线图双轨化。

---

## 0. 决策记录（ADR 索引；正式 ADR 逐步迁入 docs/adr/）

| # | 决策 | 选择 | 状态 |
|---|---|---|---|
| D1 | 许可 | Apache-2.0；GPL 来源只从论文公式重实现 | accepted |
| D2 | 包架构 | 单 R 包 + `src/rust/` workspace；engine crate 为未来拆 crates.io 的唯一候选切面；R 侧拆包仅为 CRAN 体积被拒时的应急预案 | accepted |
| D3 | COSMIC 数据 | 捆绑 + 按需更新到 `tools::R_user_dir`；溯源钉死 Alexandrov-lab BSD-2 镜像 | accepted |
| D4 | 分发 | CRAN-ready 设计（cargo vendor），r-universe + GitHub Releases 先行 | accepted |
| D5 | API 风格 | tidy 风格 `ms_*`；通道按标签校验；零魔法字符串 | accepted |
| D6 | 引擎内核 | beta-MM MU（KL 默认=多项 MLE）+ ARD + NNDSVDa/随机双初始化；体积正则与相关性引擎为组件 | accepted（v2.1 修订：删"三噪声模型"宣传，β=1 为默认并声明其统计含义） |
| D7 | 基因组读取 | BSgenome 兼容层 + Rust 快路径（twobit crate over `Cursor<Mmap>` 与自研 reader 两案由 M0 spike 裁决 ADR） | accepted |
| D8 | R 对象系统 | S7 全面实现；地板 R ≥ 4.3；S7 只在 API 边界 | accepted |
| D9 | 方法框架 | 统一框架 + 引擎注册表；外部工具永不进 `ms_*` API（仅 bench 对照） | accepted |
| D10 | 自研命名 | **只命名三个方法：MSU-Fit / MSU-LowCount / MSU-Infer**；其余为框架组件（v2.1 依评审收缩） | accepted（supersedes v2 的 8 方法命名） |
| **D11** | **验收术语** | **语义逐位**（通道算术/协议步骤/平局规则/默认参数：整数与标签 golden，硬验收）≠ **数值协议等价**（浮点内核：固定种子+容差 cosine>1−1e-6）。对 R NMF/MuSiCal 等外部的"bit 级对齐"目标废弃 | accepted（v2.1 新增） |
| **D12** | **FFI 形态** | **无状态**：无句柄注册表、无 `.state`；每次调用一次进出；mmap 进程内即用即释 | accepted（v2.1 新增，supersedes caugi 句柄模式） |
| **D13** | **统计声明纪律** | 每个统计声明必须同时给出 estimand、生成模型、校准协议与失效条件；"首个"类声明限定到可辩护范围 | accepted（v2.1 新增） |
| **D14** | **论文定位** | headline = "Calibrated inference of mutational signature exposures"（Framing A）+ 五模态生态支撑（B）；先导覆盖实验为 kill-criterion 门 | accepted（v2.1 新增） |
| **D15** | **引擎对等原则** | 引擎/方法层对**所有主流与先进算法**提供**接口对等的自有实现**（热核 Rust 原生、统计粘合 R 原生；外部工具仅作 bench 参照——对等 ≠ 包装他人 API，与 D9 一致）；领域用户可用统一接口跑任何主流方法做对比 | accepted（2026-09-28 用户指令） |
| **D16** | **平台定位** | **mutational signatures 领域的 Seurat**：中心对象模型 + 统一工作流文法 + 引擎注册表生态 + 教程文化；自研方法为默认路径，主流算法为可选引擎——一切设计决策以"成为领域默认入口"为标尺 | accepted（2026-09-28 用户指令） |

---

## 1. 系统分层总览

```
┌──────────────────────────────────────────────────────────────────────┐
│ L4 应用工作流 (R/S7)                                                  │
│   ms_hrd_report() · ms_exposure_panel() · ms_lowcount_report()       │
│   ms_atlas_fit()（common/rare 两阶段）· ms_stratify_hypermutants()   │
│   （v1.x 视合作者：ms_rna_report() · therapy forensics）              │
├──────────────────────────────────────────────────────────────────────┤
│ L3 方法层 (R/S7) —— 统一方法框架 + 引擎注册表                          │
│   ms_extract(cat, method)   method = MsEngine 子类（对象一等公民，     │
│                             字符串仅作糖）                            │
│   ms_fit(cat, sigs, method) / ms_fit_bootstrap() / ms_test_presence()│
│   ms_select_k()（默认仲裁规则）· ms_benchmark()（mlr3 式网格）         │
├──────────────────────────────────────────────────────────────────────┤
│ L2 表示与数据层 (R/S7)                                                │
│   S7: MsVariants · MsCatalog · MsSignature · MsFit · MsRefDb         │
│   （对象互引一律**快照摘要**：维度+通道表哈希+refdb 版本——非内嵌完整   │
│    对象，防内存翻倍与 waldo 噪声）                                     │
│   通道注册表（规范序+元数据）· 参考库 · 校准相似度库                   │
├──────────────────────────────────────────────────────────────────────┤
│ L1 计算引擎 (Rust, workspace: engine/catalog/ffi)                     │
│   NMF 系核（KL/EU/HALS/ARD/体积正则/相关性/NTF）· NNLS/QP ·           │
│   多项/负二项似然 + χ²₁ LRT + Fisher(内点) · **自研 PCG64 RNG** ·      │
│   重采样/共识聚类/HMM/GMM · SBS/DBS/**MNV/complex 路由**/ID83 ·        │
│   twobit 快路径 · exactPcf                                            │
└──────────────────────────────────────────────────────────────────────┘
   外部工具（SigProfiler*/MuSiCal/mmsig/…）→ bench/adapters/ 容器化对照，
   永不进入 ms_* API（D9）
```

正交规则：L1 无样本/COSMIC 概念；L2 独占通道语义与参考数据版本；L3 只组合 L2 与 L1；L4 只组装 L3；S7 分发只在 API 边界（热路径全 Rust）。R 侧架构测试强制：`R/<section>/` 只能调用本区 + `classes/` + FFI wrappers + 显式白名单。

## 1.5 平台教义：mutational signatures 的 Seurat（D15/D16）

Seurat 之所以成为单细胞生态的核心，不是因为它发明了最多算法，而是因为它提供了**默认入口**：统一的对象、统一的工作流文法、对全领域方法的整合、以及让人上来就会用的教程文化。msuiter 复制这四件事：

1. **中心对象模型**：MsVariants → MsCatalog → MsSignature/MsFit 构成分析主干，provenance 全链路携带（版本/种子/方法），对象间互引走快照摘要。
2. **统一工作流文法**：`ms_variants() |> ms_tally() |> ms_extract() |> ms_fit() |> ms_compare() |> plot()`——六类变异（SBS/DBS/ID/CN/SV/RNA-SBS）同一文法；换引擎不改管线。
3. **引擎对等（D15）**：主流与先进算法全部以统一接口、自有实现进入注册表（`method = ms_nmf(...) / ms_ard(...) / ms_lda(...) / ...`），用户可以一行换引擎做方法学对比——**这是 benchmark 文化成为日常操作而不是论文附录的关键**。外部工具只作 bench 参照，不进 API。
4. **默认即自研**：默认路径永远是我们的独立方法（提取默认 = 共识-CV 流水线；拟合默认 = MSU-Fit；低计数 = MSU-LowCount；关联 = MSU-Infer）——用户开箱得到的是我们校准过的统计，而不是 2013 年的裸 NNLS。
5. **教程文化与采用**：vignettes、COSMIC 风格图开箱即用、`ms_sitrep()` 诊断、nf-core/CLI 互操作——以"领域 PI 明天把 pipeline 换成 msuiter"为验收标尺。

对 ROADMAP 的含义：引擎对等矩阵（哪种主流算法在哪个版本轨道进入注册表）随每个里程碑更新；benchmark 章节的"逐算法对比"直接由注册表驱动生成。

**完备性检查表**：平台的完整功能空间（数据/QC/预处理 → 目录表征 → 识别 → 定量 → 拟合后分析 → **基本可视化** → **应用工作流与可视化挖掘** → 平台层，含"没想到的"清单）以 [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md) 为权威——识别/定量/可视化/挖掘逐能力标注方法、对等引擎、默认路径、可视化交付与里程碑，每里程碑验收时更新。


## 2. Rust workspace（src/rust/）



```
src/rust/
├── Cargo.toml        # 依赖预算（v2.1 收缩）: extendr-api(default-features=false,
│                     #   仅 ndarray feature)、ndarray、rayon、memmap2、twobit(待spike)。
│                     #   ★ 无 rand——随机性自研（见下）。MSRV 目标 1.71（extendr 0.9 官方）。
│                     #   engine/catalog 两 crate: #![forbid(unsafe_code)]；
│                     #   依赖方向 ffi→catalog→engine：deny 全局禁 rand 族，反向/extendr
│                     #   渗入由 tools/check-dep-direction.sh 断言 + manifest 结构强制。
├── engine/           # 纯数值，零 FFI，独立 cargo test
│   ├── nmf.rs        # KL(β=1,默认)/EU MM-MU + HALS + ARD + 体积正则组件
│   ├── correlated.rs # 相关性感知组件（对数空间低秩 exposure；gauge-fixed 输出协议）
│   ├── tensor.rs     # NTF+NB（探索性；held-out likelihood 定秩 + Kruskal 条件检查）
│   ├── rng.rs        # ★ 自研 PCG64 + SplitMix64 种子流布局（per-replicate/rank/fold
│   │                 #   计数器流；布局写进论文 Methods）。multinomial/Dirichlet
│   │                 #   采样在 resample.rs（U-M1s-04），不在此模块
│   ├── nndsvd.rs     # NNDSVDa/ar：随机化 SVD 固定 q≥3 power iterations + oversampling≥16
│   │                 #   + "exact Gram-SVD 对照" property test；KL 分母 max(·,ε)/log(ε+·)
│   ├── nnls.rs       # Lawson-Hanson on Gram：pivot 化 LDLᵀ + ε‖G‖ ridge + KKT 断言
│   ├── likelihood.rs # 多项/负二项 LL + ϵ 步进 + χ²₁ LRT + Fisher（内点支撑 only）
│   ├── resample.rs   # 多项重采样 + NB 校准采样（Jiang 协议）
│   ├── consensus.rs  # 余弦距离 + 矩形 Hungarian（unmatched 显式 split/merge 语义）+ silhouette
│   ├── stats.rs      # 1-D GMM（分层器）、Wilcoxon（诊断）、HMM（损伤分离，v1.x）
│   └── linalg.rs     # pivot 化 Cholesky/LDLᵀ、三角解
├── catalog/          # 通道语义（FFI 无关）
│   ├── sbs.rs        # SBS96/192/384/1536 字节算术
│   ├── mnv.rs        # ★ MNV 2–5bp / >5bp / complex indel / double indel 路由表 +
│   │                 #   拆分-VCF 相邻记录重连（skip ledger 进 provenance）
│   ├── dbs.rs        # DBS78（Q-链规则；仅接受重连后的距离恰 1 doublet）
│   ├── indel83.rs    # ID83（SPMG 语义逐位复刻）
│   ├── pcf.rs        # exactPcf（SV clustered）
│   └── genome.rs     # 2bit 快路径（已裁决：twobit 0.2.2 over Cursor<Mmap>，见
│                     #   docs/adr/0001；自研回退原型 244 行已验证，入库 tools/spike/）
└── (根 crate = FFI 壳 msuiter)   # extendr FFI 壳（无状态，~25 导出；docs/ffi-surface.md 冻结管理）。
                                  # 实现注记：rextendr 硬约定 FFI crate manifest 位于 src/rust/Cargo.toml，
                                  # 故为 root-package + members 形态（U-M0-01 实测定案），上图 msuiter/ 子目录意图并入根 crate。
```

**FFI 硬契约（v2.1 全部成文）**：
1. **无状态**：`ms_tally_rust(genome_path, variants, …)` 进程内 mmap 即用即释；`ms_extract_rust(counts, params, seeds)` 一次进出。无句柄、无 `.state`、无静默重算。
2. **内存布局**：过界矩阵统一显式 column-major 视图；"方形矩阵转置探测器"单测（非对称 golden 往返）。
3. **NA/NaN**：R validator 强制 `anyNA()` 拒绝；Rust `debug_assert!(!is_nan())` 且不产出 NaN（ε 策略：分母 `max(·,ε)`、`log(ε+·)`，ε 值进文档）；目录层**零伪计数**（与 musicatk 的 +ε 对比测试）。
4. **索引**：i32→usize 显式转换 + bounds check，越界返回 R error 非 panic。
5. **错误**：kernel 返回 `Result<_, MsError>`，仅在 ffi crate 边界转 R condition；禁止 kernel 内调 throwing API（`Rf_error` longjmp 跳过 Rust 析构）；任何 panic → 整调用报错、无部分结果。
6. **并发**：**放弃 rayon 全局池**——每顶层调用内建 per-call ThreadPool（`msuiter.threads` option；`_R_CHECK_LIMIT_CORES_` 下默认 2）；**并行只存在于独立单元之间**（replicate/样本/bootstrap），单元内单线程固定归约顺序——**线程数不变性**：同 seed 在 threads∈{1,N} 输出 `identical()`（CI 硬测试）。
7. **中断**：主线程在 chunk 边界轮询 `R_CheckUserInterrupt`；worker 只查 AtomicBool；中断后无残留（无状态自动成立）。
8. **构建**：Makevars.in 按 string2path 模式（vendor.tar.xz + offline + `CARGO_BUILD_JOBS=2` + cleanup）；DESCRIPTION `SystemRequirements: cargo, rustc (>= 1.71)`；rust-toolchain.toml 不进 tarball；**M0 spike 产出真实 vendor + xz 字节数与 rustc 1.71 构建证明**。

## 3. R 包结构与 S7 类系统

### 3.1 目录布局（模块化、预留拆包线；每 section 一份三行 README 声明允许的依赖方向）

> **实现注记（U-M0-03 实测）**：R 包机制（WRE §1.1.5）只安装 `R/` 顶层 `.R` 文件——上图 `R/<section>/` 子目录不可字面落地。约定改为**平铺前缀命名** `<section>-<topic>.R`（如 `classes-variants.R`、未来的 `io-variants.R`、`catalog-tally.R`），section 归属由文件名前缀表达、加载顺序由 DESCRIPTION `Collate` 控制；各 section 的依赖方向规则由静态架构测试强制（M2 契约测试套件承接，模式同 `tools/check-dep-direction.sh` 与 `tools/docs-sync.R`）。

```
R/
├── msuiter-package.R  zzz.R          # S7::methods_register()；on_load 钩子
├── classes/                           # ★ S7 类定义（单一事实来源）
│   ├── variants.R  catalog.R  signature.R  fit.R  refdb.R
│   ├── engines.R                      # MsEngine 抽象 + 具体引擎 spec 子类
│   ├── benchmark.R  utils.R           # MsBenchmark；union 类型
├── io/                      # 输入层（唯一接触外部格式的地方，读时校验 → MsVariants）
│   ├── variants.R           # VCF/BCF/MAF/TSV/Xena；somaticness 校验
│   ├── segments.R  bedpe.R  genome.R
├── catalog/
│   ├── channels.R           # 通道注册表（规范序标签 + 元数据，构建期与 COSMIC 文件断言一致）
│   ├── tally.R  normalize.R # ms_tally() 泛型分发；GMM 分层/TMB 重标定
│   ├── cnv_features.R  sv_features.R
├── engines/                 # ★ 算法动物园实现位（每引擎一文件，统一 fit_engine 接口）
│   ├── nmf.R  ard.R  sparse.R  correlated.R  tensor.R  lda.R  supervised.R
├── fit/
│   ├── fit.R  bootstrap.R  presence.R  assign.R  coda.R
├── kselect/   select.R                # ms_select_k()：稳定性 + CV + Wilcoxon 多证据与仲裁规则
├── qc/                                # ★ 样本 QC 一等公民层
│   ├── sample.R  artifacts.R          # ms_qc_report()；FFPE/oxoG/amber-red 过滤器注册表
├── refdata/
│   ├── refdb.R  update.R              # 版本化参考库 + precedence/manifest 治理
├── similarity/
│   ├── metrics.R  calibration.R       # 校准相似度库（ms_compare）：零分布 + 三匹配协议
├── analyses/                          # 拟合后分析族
│   ├── tsb.R  rta.R  lesion.R  rainfall.R  timing.R
├── viz/                     # ggplot2 原生（CAPABILITY-MATRIX L-F 的 10 图型族）
│   ├── profile.R  exposure.R  similarity.R  stability.R  strand.R
│   ├── calibration.R  mining.R  palette.R
├── workflows/               # L4（HRD/exposure/lowcount/atlas/report；RNA v1.x 条件）
│   ├── hrd.R  exposure.R  lowcount.R  atlas.R  report.R
│   ├── rna.R  therapy.R               # v1.x
└── extendr-wrappers.R                 # rextendr 生成
```

### 3.2 S7 类（v2.1 修订）

```r
MsVariants  : table + genome + provenance
              validator: 必需列/坐标合法性 + **anyNA 拒绝 + somaticness 信号**
              （caller 与 matched-normal provenance 必填、VAF floor 选项、
               FILTER 置信分类透传——ctDNA/CHIP 第一失败模式的防御）
MsCatalog   : counts(channels×samples) + channels 注册表快照 + samples + provenance
              validator: 维度一致 + 标签逐一致 + 非负 + anyNA 拒绝
MsSignature : signatures/exposures/stability/k_evidence/engine/seed
              + **catalog_summary**（快照摘要：维度+通道表哈希+build，
                 非完整 MsCatalog——防内存翻倍）
              （v2.1：删除 .state 属性——FFI 无状态化后不存在句柄）
MsFit       : exposures/support/tests + **reference_summary** + engine
MsRefDb     : matrices + metadata(version/class/build/**schema_version**/
              sha256/license/**build_independent**/availability)
MsEngine    : 抽象 spec（name/mode/params/deterministic/packages/label）
MsBenchmark : results(.engine/.scenario/.metric/.estimate) + settings
```

泛型：`ms_tally / ms_extract / ms_fit / ms_select_k / ms_fit_bootstrap / ms_test_presence / ms_benchmark / ms_compare / ms_sitrep / fit_engine / required_pkgs / ms_extract_signatures / ms_extract_exposures / ms_extract_fit_time`——**全部 `ms_` 前缀**（hardhat 命名仅作文档概念对应）；`print/format/summary/plot/knit_print` 复用注册。

`method` 传参定型：`ms_extract(cat, method = ms_nmf(engine = "kl", ...))` S7 对象一等公民；`method = "nmf"` 字符串糖经 `match_ms_engine()` 解析，报错时列出全部可用引擎名。

### 3.3 S7 工程铁律（不变）：分发只在 API 边界；热路径无 `@<-`；批量变更 `set_props(check=FALSE)` + 一次性 validate；RDS 天然安全（无 externalptr 后完全消除重连问题）。

### 3.4 引擎注册表（v2.1 增治理字段）

`register_ms_engine(name, mode, engine_class, fit_fn, packages, tags, engine_version, contract_version, certified)`。`certified ∈ {certified, self-reported, unknown}`；`ms_benchmark()` 对 non-certified 引擎显式 warning（实现注记：告警在引擎解析点 match_ms_engine()/ms_extract()/ms_fit() 每会话每引擎一次，benchmark 过滤读取同一注册表状态）；文档声明信任边界（"注册引擎代码将以你的权限执行"）；maintainer 月度反向依赖兼容矩阵 job。扩展契约：第三方包 `.onLoad()` 注册 + `S7::methods_register()`；`vignettes/extending.Rmd` + 配套 harness。

### 3.5 Error & lifecycle（v2.1 新增）

错误 class 规范 `msuiter_error_<topic>`（rlang abort + cnd payload + i/j/c 三段信息）；lint 禁裸 `stop()`；lifecycle：v1.0 前 `@experimental` 标注、废弃走 `lifecycle::deprecate_warn`、NEWS.md 即 changelog；`docs/ffi-surface.md` 为 per-release 评审工件（diff 进 PR 模板检查项）。

## 4. 统一框架与算法动物园

分层动物园与实现策略见 [research/07-algorithm-zoo.md](research/07-algorithm-zoo.md) §2（状态表：Rust/R/Adapt/Skip）。v2.1 修订：
- **Catalog IR 声明修正**："lossless coarse-graining (fine→coarse) + variant-level recomputation (coarse→fine requires variants)"；ID83↔89 提供显式映射表并标注不可映射通道。
- 相关性引擎、损伤节奏、张量、目录 IR、**校准相似度库（`ms_compare()`）** 为**框架组件**（不再冠 MSU-）；张量降为 exploratory（held-out likelihood 定秩 + Kruskal 条件检查 + 一次只加一个模式）。对应 API 名：`ms_correlated()`（相关性引擎）、`ms_tensor()`（NTF）、`ms_supervised()`（SuperSigs 系）、`ms_hdp()` / `ms_bayes()`（bench 对照位，自有实现推迟 v1.x）、`ms_damage_tempo()`（损伤节奏，v1.x）。提取引擎统一经工厂函数构造 S7 对象：`ms_nmf(engine=)` / `ms_ard()` / `ms_sparse()` / `ms_lda()`；输入侧另有 `ms_segments()`（allele-specific CN 段）与 `ms_sv()`（SV 调用）+ `ms_simulate()`（目录模拟器，benchmark 与测试共用）——**全部经注册表，与 `ms_extract()`/`ms_fit()` 同接口**。

## 5. 方法体系（v2.1 收缩为三命名方法 + 组件）

**默认路径（D16）**：`ms_extract(method = NULL)` 默认 = 共识-CV 提取流水线；`ms_fit(method = NULL)` 默认 = MSU-Fit（nnls 起步 + `ms_test_presence()` 报告）；低计数上下文自动建议 MSU-LowCount；关联分析默认 MSU-Infer。主流算法全部经注册表一行可换（D15 对等原则）——**默认即自研校准统计，换引擎仅为方法学对比服务**。完整功能空间（识别/定量/可视化/工作流/挖掘及全部子能力）见 [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md)——该矩阵是平台完备性的权威检查表，随里程碑更新。


### 命名方法（论文 abstract 层）
| 方法 | 内容 | 精确声明（D13 纪律） |
|---|---|---|
| **MSU-Fit** | 似然稀疏拟合（ϵ 阈值 + χ²₁ LRT 双模式）+ 背景签名策略 + connected 组配置 + bootstrap CI + CI 清零 | 声明："**首个对 exposure 区间做经验覆盖率测量并全网格报告的推断层**"。estimand 三层：①presence = χ² LRT（逐样本 Self–Liang 边界渐近 + cohort 池化时精确 Binomial(½) 混合 χ² 零分布——U-M3a-03 审计修正，n≥2 时 χ²₁ 参照统计无效）；②magnitude = **支撑条件下的绝对 exposure**（另报成分版）；③清零 = 决策规则，单独测复合流程覆盖率。校准：多项与 NB（Jiang 色散）**双生成模型**，coverage 按 N × Shannon 熵成曲线；BCa 或分层 calibrated-percentile；真实数据 sanity = 高 TMB 降采样覆盖检验；Fisher 区间仅内点支撑（"boundary parameters get tests, not intervals"）。退化语义注记：全 replicates 清零次要签名时 CI 退化为样本 total（清零+重标度的诚实退化，非数值噪声） |
| **MSU-LowCount** | panel/ctDNA 低计数 refit：NB 似然 + 稀疏先验 + 显式残差通道 + conformal 区间 | 声明："**per-TMB-stratum conformal intervals（Mondrian by N bin，studentized score）with empirical coverage verified on stratified simulations and retrospective real panel data**"。明示 exchangeability 只在 bin 内成立、模拟保真的敏感性曲线随包发布 |
| **MSU-Infer** | DM/logistic-normal 混合模型差丰（复现 Morrill 2025 → 扩展）+ CoDA 检验 + 生存/纵向 + 不确定性传播（多重插补协议） | 声明："首个覆盖**生存/病例对照/纵向**的统一暴露关联框架（组间差丰的 DM 混合模型已有 Morrill 2025，我们复现并扩展）"；扩展清单显式含 structural zeros / hurdle |

### 框架组件（论文 Methods 层）
- **共识-CV 提取流水线**（`ms_extract` 默认）：GMM **分层**（`ms_stratify_hypermutants`：分类+排除 de novo+强制 refit，非"归一化"）→ 多初始化 KL-MM ensemble → Hungarian 共识（unmatched 显式 split/merge 语义）→ **默认 K 仲裁规则**（SUITOR argmin → 稳定性 veto → Wilcoxon 仅诊断；meta-rule 在全网格上评估）→ NNLS refit。Delta 叙事：确定性（含线程不变性）+ 证据表透明 + Rust 加速"使校准统计学买得起"。
- **相关性引擎**（correlated.rs）：**预注册可证伪声明**——Wu 2022 网格 r∈{0.8,0.9,0.95} 的 exposure L1 上须同时击败 (i) 重标定目录 plain KL-NMF (ii) 纯 MvNMF (iii) 原版 Cornet (iv) 相关性感知 refit，达显著幅度；只报告 gauge-fixed 量（h/W/重构，禁解读嵌入向量）；m<K 经 held-out likelihood 选择、K 扫描时固定 m；体积正则与嵌入为分离 ablation 轴；Cornet 10–40× 重标定 = 引擎内部超参（sweep {1,10,40,100}，平坦签名低估为守护指标，de-rescale 恢复绝对 exposure，禁用于 NMF 路径）；五模态降为 SBS+DBS 演示直至被证明。
- **损伤节奏分析**（v1.x）、**NTF 张量引擎**（exploratory，v1.x）、**目录 IR**（§4 修正语义）、**校准相似度库**（`ms_compare()`，M4：零分布校准 + Hungarian/Islam/Jiang 三匹配协议）。

平台功能全空间（含 QC 层、可视化 10 图型族、应用工作流与可视化挖掘、"没想到的"清单）以 [CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md) 为权威检查表，随里程碑更新。

## 6. 数据与标准（v2.1 修订）

1. **通道注册表**：单一事实来源（data-raw 生成 R CSV + Rust 常量 + 构建期断言）。
2. **参考库治理**：
   - **v1 只捆绑人类 SBS/DBS/ID**（GRCh37/GRCh38 SBS/DBS + GRCh37 ID；对齐 CRAN 5MB 指导线）；CN/SV/RNA-SBS/鼠鼠经 `ms_update_refdb()` 缓存获取。
   - **缺失 build = `build_independent: true` 声明**（ID/CN/SV/RNA-SBS 通道标签与签名矩阵 build 无关——relabel 而非 derived），查询时如实提示"该 build 无官方参考集，最接近的是 YY"。
   - **precedence**：分析永远 pin 在对象 provenance 记录的具体版本；默认 bundled 优先、cache 仅显式要求；`schema_version` 高于包支持即 stop（前向拒绝）。
   - **完整性**：更新钉 commit SHA + 构建时烧录 manifest（lib-sums.tsv 模式）+ fail-closed；更新路径测试全 fixture 化（检查期零联网）。
3. **基因组卫生**：contig 白名单（primary assembly）、性别机会校正、逐样本机会向量选项（CN segments + callable BED 进 MsCatalog）、chrM 显式路由、T2T 兼容（twobit 层天然支持）；**exome/panel 机会归一参考集**为一等公民（WES refit 用 WGS 参考会系统性偏置平坦签名）。
4. **报告检查单**：provenance（目录版本、build、通道序、方法+版本、**种子流布局**、软件版本、线程数[承诺不影响结果]）。

## 7. 算法科学契约（v2.1 重写）

1. **双层验收**（D11）：**语义逐位**（硬验收，整数/标签 golden）：SPMG ID83 与 MNV/complex 路由、DBS Q-flag、CN48/SV32 标签、Koh ID89 映射（v1.x）、SUITOR fold 按序取模与条件均值填补语义、HRDetect 系数、Macintyre/Drews 特征、Islam/Jiang/Medo **指标协议步骤**；**数值协议等价**（固定种子+容差）：KL-MU vs R NMF brunet（固定平台一次性实验，`‖ΔW‖/‖W‖<1e-10`，不进 CI 门）、MuSiCal bidirectional 数值轨迹、共识聚类统计量。
2. **目录完备性契约**：输入事件类路由表（SNV/DBS/MNV2-5/MNV>5/complex indel/double indel → 各自去向），skip ledger 入 provenance；拆分 VCF 相邻记录重连算法规范与失败模式；MNV-相邻与 complex golden fixtures。
3. **统计契约**（D13）：§5 表格的 estimand/生成模型/校准协议即契约；任何新统计声明进 §5 前必须先给出四件套。
4. **零伪计数政策**：目录层无 +ε；数值防护只进除法。
5. GPL 来源只从论文公式重实现（不变）。

## 8. 性能与 benchmark（v2.1 升级）

**场景网格（升级）**：TMB 10²–10⁶ × 签名数 1–20 × 相关性 {0, 0.5, 0.8, 0.95} × **平坦签名组内 r=0.8 + 稀有签名共存（联合）** × purity {1.0, 0.7, 0.4, 0.2} × caller 轴（≥2 SNV + ≥2 indel caller）× 平台 WGS/WES/panel（机会归一）× 参考误设 + **目录外签名 cell** × **超突变臂（5–10% 样本 TMB 100×，APOBEC/POLE P/R 对 cutoff 敏感性）** × 亚克隆 exposure 结构 × **类别专属计数区间（SV 10–10³、CN segments 10–10⁴）**。

**三层场景隔离**：校准场景 / 模型选择场景 / 评估场景使用不同生成器（SigProfilerSimulator / SynSig / PCAWG 锚定真实混合）；协议发表前冻结随包发布。

**指标**：**主指标 = Hungarian 一对一匹配**的 P/R/F1（贪心 max-cosine + 阈值扫 0.80–0.90 为鲁棒性附录；分裂行为显式惩罚/dedup 统计）；exposure L1/cosine（absolute 与 compositional 口径与各引擎 estimand 一致）；缺席签名误分配质量；运行时/内存。Jiang Combined Score 与 Islam 协议逐位复刻（语义层 golden）。

**性能预算（验收在钉硬件 bench，CI 只放 sanity bound）**：
| 内核 | 基线 | 目标 |
|---|---|---|
| 目录生成 SBS96（10⁶ 突变） | SPMG | ≥50× 且 <5 s 单核 |
| NMF KL（96×1000, k=10, 100 iter） | R NMF / rust-NMF | ≥100× R NMF；rust-NMF 对齐（容差） |
| 批量 NNLS（101×10³） | scipy nnls 逐样本 | ≥10× |
| 全样本拟合 | SPA ~0.21 s/样本 | 对齐或更优 |
| bootstrap（10³×10³） | sigminer 串行 | ≥100× |

**G0 先导覆盖实验（kill-criterion 门，先于一切论文叙事）**：2 个竞品工具 × TMB 网格的名义 vs 实际覆盖率——结果决定 headline 走 Framing A（校准统计）还是 Framing B（生态）。

## 9. TDD 与 CI（v2.1 补全）

- Rust：通道算术 property/golden（含 MNV 路由）；KL 单调性与 ε 行为；NNLS KKT + 病态 Gram（pivot LDLᵀ）；Hungarian 暴力对拍；RNG 跨版本 golden（固定 seed → 固定前 N 个 u64）；**线程不变性 identical() 测试**；相关引擎低相关退化测试。
- R：S7 构造校验（坏标签/维度/NA 必抛错，错误 class 断言）；目录 vs sigminer/MP 玩具交叉验证；提取端到端（cosine>0.95）；拟合 vs quadprog/nnls（容差）；bootstrap 种子确定性 + **跨线程数一致性**；refdb precedence/schema 拒绝/manifest 校验（fixture 化更新路径）；错误路径测试（condition 而非崩溃，会话可继续）。
- CI：3 OS × {release, oldrel, **R-4.3（Linux）**, devel（允许失败）}；rcmdcheck --as-cran + cargo test/clippy/deny（ban 规则）/audit；**valgrind + ASAN/UBSAN scheduled job**；基准门 = sanity bound；codecov（R≥85%，Rust 报告不设门）；docs-sync 检查（ROADMAP `ms_*` ↔ ARCH/R 布局对照，drift 即红）；rhub/win-builder 预提交。

## 10. 论文定位（D14）

- **Headline（Framing A）**："Calibrated inference of mutational signature exposures"——领域 exposure 区间从未被验证校准；MSU-Fit/LowCount/Infer 提供第一套完整推断层；Rust 性能使校准统计学在 cohort 规模分钟级可行（"fast *so that* statistical honesty is affordable"）。Target：Nature Methods（冲刺）/ Nat Commun（现实落点）。
- **支撑（Framing B）**：五模态统一生态 + 语义逐位兼容 + 版本化参考库。Target：Genome Biology 保底。
- **案例升级三路径**（需队列合作，G 门）：治疗记录 concordance / RNA-only 队列 / 低计数 panel 诊断级检出（MUTYH/MSI 模式）。
- **Kill criteria**（触发即 pivot，见 reviews/05 §9）：先导实验证伪、Cornet 正式发表压制、M3b 前无队列合作、竞品发布校准 CI、滑期 >100%、无 co-maintainer。

## 11. 风险登记（v2.1 增补）

| 风险 | 缓解 |
|---|---|
| rand 生态 RNG 跨版本漂移 | 自研 PCG64 + 流布局文档化 + 跨版本 golden（D6/A6） |
| 线程数改变数值结果 | 单元间并行 + 固定归约 + identical() CI 测试（A7） |
| "逐位"验收与 clean-room 对撞 | 双层术语（D11）；R NMF 对拍为一次性平台实验 |
| 统计声明被统计学评审击穿 | D13 四件套前置 + G0 先导实验 + 统计学 co-author（组织行动项） |
| Cornet 正式发表压制相关性组件 | 预注册可证伪声明 + 组件化降级（A4）+ 季度竞争复核（**2026-09-28 事件已发生**：bioRxiv 2026.09.14.751548；复核结论 = 策略维持、kill 未触发，见 devlog G3 复核；威胁面升级：Park 组 + MuSiCal，G0 升为 Framing A 关键路径） |
| vendor 体积超限 | M0 spike 定数 + 依赖收缩（去 rand）+ faer 默认关 |
| CRAN 2 线程/fork | per-call 池 + option 双读 + Makevars -j2 + BiocParallel 兼容文档 |
| refdb 双源漂移 | precedence + schema_version + manifest + fixture 测试（A13） |
| 时间线 fantasy | 双轨 v0.1/v0.2/v1.0 + Non-goals 硬性化（ROADMAP v3） |
| bus factor | co-maintainer 前置到 M1s（组织行动项） |
