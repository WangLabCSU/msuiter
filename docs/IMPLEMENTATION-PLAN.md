# msuiter 实施计划（IMPLEMENTATION-PLAN）—— ROADMAP v3 的可执行分解

> 版本：**v1（2026-09-28）**。上游权威：[ROADMAP.md](ROADMAP.md)（版本轨道与里程碑唯一权威定义）、[ARCHITECTURE.md](ARCHITECTURE.md) §0 D1–D16（宪法）、[CAPABILITY-MATRIX.md](CAPABILITY-MATRIX.md)（完备性权威检查表）。
> 本文档**不引入新范围**：把 ROADMAP 的里程碑翻译为**工作单元（U-\*）**——每个单元有交付物路径、验收标准（引用 D 条款）、依赖与估算。与 ROADMAP/矩阵冲突处以上游为准并走 docs-sync 修正。
> 执行方式：每个工作单元按 [.agents/skills/msuiter-team/SKILL.md](../.agents/skills/msuiter-team/SKILL.md) 的 PI 团队工作流跑一轮；devlog 文件名使用单元 ID（`docs/devlog/YYYY-MM-DD-<U-ID>.md`，随首个单元建目录）。

---

## 1. 执行总则

1. **单元循环**（每单元一轮）：读状态 → PI 分解（≤3 工作片）→ 涉及算法语义/统计声明的单元先出设计备忘（signature 专家 + 计算生物学家并行，落 devlog，PI 裁决后再实现）→ TDD 实现（先测试后实现）→ PI 集成自检（`cargo test` / testthat / 验收标准逐条打勾）→ 独立审核（只喂交付物，PASS/REVISE ≤2 轮）→ devlog + 勾选 ROADMAP + 更新 CAPABILITY-MATRIX 状态列。
2. **验收术语前置标注**（D11）：每单元验收标准标注三类——【逐位】语义逐位 golden（通道算术/协议步骤/平局规则/默认参数，整数与标签，硬验收）｜【等价】数值协议等价（固定种子+容差，一次性平台实验，不进 CI 门）｜【工程】可执行验收（测试全绿/构建产物/文档存在）。
3. **并行规则**：Rust track（engine/catalog crate）与 R track（S7/io/泛型）并行推进；同 track 内按依赖串行；FFI 契约（U-M0-09）冻结前 R track 不做内核调用对接。
4. **范围铁律**：只做当前单元（msuiter-team 硬约束 1）；实施中发现的设计缺陷与"顺手优化"记 devlog 遗留，不扩单元。触及 D1–D16、G 门或 kill criteria 的偏差 → 停下向用户汇报，不自行改宪法。
5. **进度治理**：估算单位为"专注工作日"（单人 + AI agents 的诚实口径，已吸收评审 ~3× 上调结论；单元日数是预算而非承诺）。每周五 PI 巡检重排下周；里程碑验收时复核 kill criteria；**连续两周滑期即触发估算重估**（kill criterion"滑期>100%"的早期预警线）。
6. **状态记录**：单元级进度以 devlog 为准，里程碑级勾选以 ROADMAP checkbox 为准，能力状态以 CAPABILITY-MATRIX 为准——本文件不另设状态列（避免双事实来源）。

## 2. 工作单元依赖图（v0.1 段）

```
U-M0-01 脚手架 ─┬─ U-M0-03 S7 骨架 ── U-M0-04 注册表 ─┐
                ├─ U-M0-05 通道表 ────────────────────┼─→ R track（U-M1s-10/11/12）
                ├─ U-M0-06 自研 RNG ─── U-M1s-04 重采样┤
                └─ U-M0-09 FFI 硬契约 ── U-M1s-09 导出 ┘
U-M0-02 spike（W1 硬截止）─ ADR（2bit 两案 / vendor 体积）─→ U-M1s-08 2bit 快路径
U-M1s Rust track：U-M1s-01 linalg/NNLS → 02 KL-MM → 03 NNDSVDa → 05 线程不变性
U-M1s catalog：  U-M1s-13 夹具基建（依赖 05）→ 06 SBS → 07 DBS+MNV
G0 先导实验（W1–2，作者本人）→ Framing ADR ——独立于代码轨道，不阻塞 M0/M1s
```

无编号横切件：U-M0-07（CI 矩阵）、U-M0-08（治理文件）、U-M0-10（ADR 目录迁移）无代码依赖，随时并行。

## 3. v0.1 逐周排程（~6 周：M0 工程地基 + M1s 引擎与目录核心）

| 周 | 轨道并行内容 | 说明 |
|---|---|---|
| **W1** | U-M0-01 脚手架｜U-M0-02 spike（**W1 硬截止**）｜U-M0-08 治理文件｜U-M0-10 ADR 迁移｜**G0 开跑** | spike 与脚手架是全计划关键路径；G0 协议冻结并开始实验 |
| **W2** | U-M0-03 S7 骨架｜U-M0-05 通道表｜U-M0-06 RNG｜U-M0-07 CI | **G0 收尾**：报告 + Framing ADR（决定 M7 论文 headline，不阻塞代码） |
| **W3** | U-M0-04 注册表｜U-M0-09 FFI 契约 + `ms_sitrep()`｜**M0 验收评审**；Rust track 预热 U-M1s-01 | FFI 契约冻结 = R track 解锁点；G1 co-maintainer 邀请应已发出 |
| **W4** | U-M1s-01 NNLS｜02 KL-MM｜03 NNDSVDa｜04 重采样｜05 线程不变性｜13 夹具基建｜06 SBS 启动 | engine crate 完备周 |
| **W5** | U-M1s-07 DBS+MNV｜08 2bit 快路径｜09 FFI 导出｜10 `ms_variants()`｜11 `ms_tally()` | 语义正确性重点周（MNV 路由失真 = SBS/DBS 系统性错误，A11） |
| **W6** | U-M1s-12 `ms_extract()` 单方法｜14 KL 一次性对拍｜钉硬件 bench｜**v0.1 发布门** | 缓冲与修整日保留在本周 |

### 3.1 M0 工作单元表（预算 2 周 + W3 收尾验收）

| ID | 单元 | 关键交付物 | 验收（D11 标注） | 依赖 | 估算 |
|---|---|---|---|---|---|
| U-M0-01 | rextendr 脚手架 + Cargo workspace | `DESCRIPTION`/`Makevars.in`/`src/rust/`（workspace：FFI 壳 crate 在根 + `engine/`、`catalog/` 成员，rextendr 约定）/`R/msuiter-package.R`/`zzz.R` | 【工程】依赖=收缩清单（extendr-api default-features=false、ndarray、rayon、memmap2；**无 rand**，D2/ARCH §2）；engine+catalog `#![forbid(unsafe_code)]`；deny ban 方向规则；cargo test 空转绿 + check 绿 | — | 2–3 d |
| U-M0-02 | **M0 spike**（W1 截止） | 真实 cargo vendor + xz 字节数报告；rustc 1.71 × {Linux, macOS, Windows} 构建证明；twobit 两案（crate over `Cursor<Mmap>` vs 自研 reader）byte-swap/大端验证 → 两条 ADR | 【工程】数字落 ADR（D4/D7）；vendor 超预算 → 依赖再收缩决策记录 | 01 | 3 d |
| U-M0-03 | S7 类骨架（无 `.state`） | `R/classes/*.R`：MsVariants/MsCatalog/MsSignature/MsFit/MsRefDb/MsEngine/MsBenchmark 七类 + validator；互引一律快照摘要（维度+通道表哈希+refdb 版本，A5） | 【工程】坏标签/维度/NA 必抛错且错误 class 断言；saveRDS/load 后全泛型行为测试（D8/D12） | 01 | 3 d |
| U-M0-04 | 引擎注册表 + 契约测试 | `register_ms_engine(name, mode, engine_class, fit_fn, packages, tags, engine_version, contract_version, certified)`（A17） | 【工程】字符串糖解析失败时列全部可用引擎名；non-certified 告警逻辑 | 03 | 2 d |
| U-M0-05 | 通道注册表单一事实来源 | `data-raw/build_channels.R` → R data + Rust 常量 + 构建期与 COSMIC 文件断言一致 + docs-sync CI | 【工程】drift 即红（D5） | 01 | 2 d |
| U-M0-06 | 自研 RNG 模块 | `engine/rng.rs`：PCG64 + SplitMix64 种子流布局（per-replicate/rank/fold 计数器流，A6；布局写进论文 Methods） | 【逐位】跨版本 golden：固定 seed → 固定前 N 个 u64 | 01 | 2 d |
| U-M0-07 | CI 体系 | `.github/`：3 OS × {release, oldrel, R-4.3(Linux), devel} 矩阵、rcmdcheck --as-cran、cargo test/clippy/deny(ban)/audit、valgrind+ASAN scheduled、dependabot、codecov（A15）；**接线认领（U-M0-01/02/05/06 交接）**：tools/check-dep-direction.sh、tools/vendor.sh --check、tools/rng-kat.py、tools/docs-sync.R、deny 全量四节、matrixmultiply ≥0.3.10 钉版保护（dependabot 策略）、rustc 1.71 × Linux/Windows 构建证明（ADR 0002 §4.4/§5 残留）、**仓库模式 testthat**（drift 守卫类测试在 R CMD check 语境会 skip——CI 必须在 checkout 上跑 `devtools::test()` 全量，含 test-channels-sync/reference） | 【工程】矩阵全绿 | 01 | 2 d |
| U-M0-08 | 治理文件 | CONTRIBUTING（含第三方引擎接入清单）/CoC/issue 与 PR 模板（含 FFI-surface 变化与 fixture 刷新检查项）/README 骨架/NEWS.md/`_pkgdown.yml` | 【工程】存在且模板可渲染 | — | 1 d |
| U-M0-09 | FFI 硬契约落地 + sitrep | 无状态导出骨架（D12：无句柄/无 `.state`）；column-major"转置探测器"单测；anyNA 拒绝；`Result<_, MsError>` 边界转 condition；`R_CheckUserInterrupt` chunk 轮询；per-call ThreadPool + `msuiter.threads` option（检查期默认 2）；`ms_sitrep()`；`docs/ffi-surface.md` 建立 | 【工程】探测器/错误路径/中断测试过；panic → 整调用报错无部分结果 | 01 | 3 d |
| U-M0-10 | ADR 目录迁移 | `docs/adr/` 建立，D1–D16 迁入（synthesis §4 轻量采纳项） | 【工程】16 条齐且与 ARCH §0 一致 | — | 0.5 d |

**M0 验收门**（ROADMAP 原文）：check 全绿；S7 校验测试过；RNG golden 过；vendor 体积数字进 ADR。

### 3.2 M1s 工作单元表（预算 4 周）

| ID | 单元 | 关键交付物 | 验收（D11 标注） | 依赖 | 估算 |
|---|---|---|---|---|---|
| U-M1s-01 | linalg + NNLS | `engine/linalg.rs`（pivot 化 Cholesky/LDLᵀ、三角解）+ `engine/nnls.rs`（Lawson-Hanson on Gram：pivot LDLᵀ + ε‖G‖ ridge） | 【工程】KKT 断言 + 病态 Gram 测试（ARCH §9） | 01 | 2 d |
| U-M1s-02 | KL-MM MU 核 | `engine/nmf.rs` β=1 默认（=多项 MLE，D6）；ε 策略（分母 `max(·,ε)`/`log(ε+·)`）成文 | 【等价】vs R NMF brunet 见 U-M1s-14；【工程】KL 单调性 + ε 行为测试 | 01 | 3 d |
| U-M1s-03 | NNDSVDa 初始化 | `engine/nndsvd.rs` 随机化 SVD：q≥3 power iterations + oversampling≥16 | 【工程】exact Gram-SVD 对照 property test | 01 | 2 d |
| U-M1s-04 | 多项重采样 | `engine/resample.rs` + RNG 计数器流接入 | 【逐位】固定 seed 采样序列 golden | 06 | 1–2 d |
| U-M1s-05 | 线程不变性 | per-call ThreadPool 接入引擎；单元间并行/单元内固定归约顺序（A7） | 【工程】同 seed 在 threads∈{1,N} 输出 `identical()`，CI 硬测试 | 02/04 | 2 d |
| U-M1s-06 | SBS 通道家族 | `catalog/sbs.rs` SBS96/192/384/1536 字节算术 | 【逐位】SPMG 对拍 golden（research/04 §1） | 05, 13 | 3 d |
| U-M1s-07 | DBS78 + MNV 路由 | `catalog/dbs.rs`（Q-链规则）+ `catalog/mnv.rs`（2–5bp/>5bp/complex indel/double indel 路由表 + 拆分 VCF 相邻记录重连 + skip ledger 进 provenance，A11） | 【逐位】SPMG DBS/MNV/complex golden；路由失败模式显式 | 06, 13 | 3 d |
| U-M1s-08 | 2bit 快路径 | `catalog/genome.rs`（按 U-M0-02 spike ADR 定案实现） | 【工程】byte-swap/大端验证 + 与 BSgenome 对拍 | 02 | 2 d |
| U-M1s-09 | FFI 导出 | `ms_tally_rust()` / `ms_extract_rust()`；`docs/ffi-surface.md` 冻结（per-release 评审工件） | 【工程】surface diff 进 PR 模板检查项 | 09(M0), 06/07 | 1 d |
| U-M1s-10 | `ms_variants()` | `R/io/variants.R`：VCF/BCF/MAF/TSV 读时校验 → MsVariants；somaticness 信号（caller/normal 溯源、VAF floor、FILTER 透传） | 【工程】validator 坏输入全测试（L-A M1s 行） | 03 | 2 d |
| U-M1s-11 | `ms_tally()` | `R/catalog/tally.R` 泛型分发 + MsCatalog 装配；注解缓存最小集（转录链，支撑 SBS192/384） | 【工程】目录 vs sigminer/MP 玩具交叉验证 | 09(M0), 10 | 2–3 d |
| U-M1s-12 | `ms_extract()` 单方法 | 单方法 KL 提取 + `print/format`（共识-CV 流水线在 M2） | 【工程】端到端冒烟（玩具数据 cosine 合理区间） | 11 | 2 d |
| U-M1s-13 | 金标准夹具基建 | fixture 生成脚本 + golden 文件管理 + 刷新脚本（PR 检查项联动，A15） | 【工程】夹具可复现生成 | 05 | 1 d |
| U-M1s-14 | KL 一次性对拍 | vs R NMF brunet 固定平台实验，`‖ΔW‖/‖W‖<1e-10` | 【等价】报告落 devlog/ADR，**不进 CI 门**（D11/A8） | 02 | 1 d |

**v0.1 发布门**（ROADMAP 原文）：目录生成 ≥50× SPMG（钉硬件 bench；CI 只 sanity bound <5s）；NMF ≥100× R NMF；夹具全绿；r-universe 可安装；CAPABILITY-MATRIX M1s 相关行更新；NEWS + GitHub Release。

## 4. v0.2 / v1.0 中粒度单元（开工前随当时状态细化，依赖图届时更新）

### 4.1 v0.2（再 ~12 周）

**M1c · 目录完备 + ID83（3 周）**

| ID | 单元 | 验收要点 |
|---|---|---|
| U-M1c-01 | ID83（SPMG 语义逐位复刻：重复游走/MH 前向优先/封顶/Q 规则）+ ID83 golden | 【逐位】 |
| U-M1c-02 | GMM 分层器 `ms_stratify_hypermutants()`（分类 + 排除 de novo + 强制 refit，A18） | 【工程】+ 分层场景测试 |
| U-M1c-03 | CN 输入与 CN48 特征空间（`ms_segments()` allele-specific caller 映射；CAPABILITY-MATRIX L-A/L-B M1c 行） | 【逐位】CN48 标签 |
| U-M1c-04 | SV 输入与 SV32（`ms_sv()` BEDPE/SV VCF + `catalog/pcf.rs` exactPcf clustered；矩阵 M1c 行） | 【逐位】SV32 标签 |

**M2 · 统一提取流水线（5 周）**

| ID | 单元 | 验收要点 |
|---|---|---|
| U-M2-01 | `engine/consensus.rs`：余弦距离 + 矩形 Hungarian + unmatched 的 split/merge 显式语义（兼容 Islam 阈值扫描，A10） | 【工程】Hungarian 暴力对拍 |
| U-M2-02 | SUITOR CV 可选开关（fold 按序取模 + 条件均值填补语义【逐位】）+ `ms_select_k()` 默认仲裁规则成文并实现（CV argmin → 稳定性 veto → Wilcoxon 仅诊断，A10） | 仲裁规则文档 = 契约 |
| U-M2-03 | `ms_extract()` 默认共识-CV 流水线装配（分层 → ensemble → 共识 → 仲裁 → NNLS refit；Wilcoxon 仅诊断） | 端到端测试 |
| U-M2-04 | `ms_ard()`（SignatureAnalyzer ARD，Rust） | 【工程】+ 退化测试 |
| U-M2-05 | `ms_sparse()`（体积正则 mvNMF + L1，Rust） | 【工程】 |
| U-M2-06 | 注册表接入 MsNmf/MsArd/MsSparse + 契约测试全过 + `vignettes/extending.Rmd` | 第三方扩展路径可走通 |
| U-M2-07 | 端到端合成测试（cosine>0.95）+ Islam 2022 协议复现（贪心 max-cosine ≥0.90） | 【逐位】协议步骤 |

**M3a · 拟合三法 + bootstrap（4 周）**

| ID | 单元 | 验收要点 |
|---|---|---|
| U-M3a-01 | `engine/likelihood.rs`：多项/NB LL + ϵ 步进 + χ²₁ LRT + Fisher（内点支撑 only） | 【工程】 |
| U-M3a-02 | `ms_fit()` 三法：nnls / likelihood_bidirectional（MuSiCal 语义）【等价：数值轨迹】/ lrt | 双层标注分法验收 |
| U-M3a-03 | `ms_fit_bootstrap()`（Rust 并行）+ `ms_test_presence()`（NB χ²₁ LRT + BH） | 种子确定性 + 跨线程一致 |
| U-M3a-04 | QP / em / 暴露稀疏化清零规则（矩阵 L-D v0.2 行） | 【工程】 |
| U-M3a-05 | 每突变分配 + unassigned 残差伪签名 + TSB 检验 + de novo→目录分解注释（矩阵 L-D/L-E v0.2 行） | 【工程】 |
| U-M3a-06 | refdb v1：人类 SBS/DBS/ID 捆绑 + precedence/schema_version/manifest/build_independent 治理（A13） | fixture 化更新路径，检查期零联网 |

**v0.2 验收门**：Jiang 协议（活性>0 匹配 + Combined Score）对标进入第一梯队合理区间；refdb v1 发布；矩阵更新。

### 4.2 v1.0（再 ~3–4 月）

**M3b · MSU-Fit 校准统计（6 周；G2 门须在此期间达成）**
- U-M3b-01 estimand 三层落地（D13/A1）：presence LRT / support-conditional 绝对 exposure CI（BCa 或分层 calibrated-percentile）/ 清零复合覆盖率。
- U-M3b-02 多项 + NB 双生成模型校准：coverage × N × Shannon 曲线；Fisher 内点区间；真实数据降采样 sanity 协议。
- U-M3b-03 G0 结果写入叙事决策（Framing A/B ADR 定稿）。

**M4 · 相似度校准库 + viz（3 周）**
- U-M4-01 `ms_compare()` 校准相似度库：多度量 + 解析/经验零分布 + Hungarian 主指标 / Islam 贪心 / Jiang 活性三协议参考实现【逐位】。
- U-M4-02 `ms_qc_report()` + `ms_downsample()` + `ms_import/ms_export` 首批（SigProfiler txt / COSMIC txt / WTSI 长格式）。
- U-M4-03 viz 首批 8 图型（COSMIC 调色板、规范序、矢量输出）+ exposure UMAP 初版 + `ms_convert()`。

**M6s · HRD 工作流（3 周；范围安全契约生效，A12）**
- U-M6s-01 `ms_hrd_report()`：HRDetect 系数模式 **WGS-only** + allele-specific CN caller 白名单（Battenberg/ASCAT/FACETS/PURPLE/SEQUENZA）+ WES 标 experimental + 参考忠实性测试（系数【逐位】）+ 不确定性报告。

**M7 · Benchmark 完备 + 论文（8–10 周）**
- U-M7-01 场景网格全量（ARCH §8 升级版）+ 校准/选择/评估三层场景隔离 + 协议冻结随包发布。
- U-M7-02 竞品容器 harness（仅 `bench/`）+ 钉硬件 bench 全表 + `ms_benchmark()` 端到端。
- U-M7-03 论文草稿（headline 依 G0 Framing ADR）+ renv/Docker/seed 一键复现 + bioRxiv 同挂。
- U-M7-04 pkgdown 全站 + MSU↔函数映射表 + CITATION + 性能锚定文档。

**M8 · 发布工程**
- U-M8-01（M8a 材料周）：cargo vendor 终审 + r-universe + GitHub Releases 二进制 + nf-core module PR。
- U-M8-02（M8b，墙钟 4–8 周滚动）：CRAN 提交与迭代。

**v1.0 验收门**：CRAN 提交启动；论文三板块素材（架构/性能/应用）齐备（ARCH §10）。

## 5. G 门与 kill criteria 排程（作者本人行动，团队不可代办）

| 门 | 时机 | 行动 | 产出/判定 |
|---|---|---|---|
| **G0** | **立即（W1–W2，与 M0 并行）** | 先导覆盖实验：2 个竞品工具 × TMB 网格的名义 vs 实际覆盖率。工具默认候选 MuSiCal / SigProfilerAssignment，协议冻结时由 signature 专家简报定稿 | G0 报告 + **Framing A/B ADR**；先于一切论文叙事写作（U-M7-03 的前置条件） |
| **G1** | M1s 内（≤W6） | co-maintainer 候选名单与邀请（bus factor + CRAN + 审稿三重需要） | DESCRIPTION co-maintainer 落实；未达成 = kill criterion |
| **G2** | M3b 期间/结束前 | 统计学 co-author（conformal/CoDA 理论）+ 临床/队列合作者（治疗记录 / RNA-only / FFPE panel 三选一）锁定 | 合作约定；否则案例注定装饰性，主动接受 GB/NC 上限 |
| **G3** | 每季度（下次 ~2026-12） | 竞争格局复核（Cornet/MuSiCal/SPA 动态）+ kill criteria 重估 | 复核备忘落 devlog |

**Kill criteria**（ARCH §10，触发任一 → 停当前轨道，向用户汇报 pivot 选项）：先导实验证伪；Cornet 正式发表压制相关性组件；M3b 前无队列合作；竞品发布校准 CI；滑期 >100%；无 co-maintainer。

## 6. 启动检查单（第 1 周即行动）

- [ ] **G0 协议冻结并开跑**（作者 + signature 专家；两周窗口，结果写 Framing ADR）
- [ ] **U-M0-01 脚手架** + **U-M0-02 spike**（spike W1 硬截止——vendor 数字决定后续一切构建决策）
- [ ] U-M0-08 治理文件 + U-M0-10 ADR 目录迁移（无代码依赖，可立即并行）
- [ ] G1 co-maintainer 候选名单启动（作者日历项）
- [ ] 首个工作单元启动时建立 `docs/devlog/`（首个 devlog = U-M0-01）
