# 评审 04：软件开发专家（独立评审，2026-09-28）

> 评审人设定：staff engineer / 开源科学软件维护者。方法：逐条对照文档内数字、验收标准与内部一致性。
> **总裁决：方向正确、调研质量罕见地高，但这是"论文愿望清单"还不是交付计划。有条件通过——先做范围手术与三处契约补丁，再写第一行代码。**

## P0

### 1.【P0】ROADMAP 总工作量被系统性低估约 3 倍，且全篇没有"最小可采纳 v1"的切线
- M0 半周到一周要交付 7 个 S7 类 + 注册表 + 契约测试 + 通道双端生成 + 2bit 夹具 + 三平台 CI——1–2 周起。M1：8 个数值内核 + 五套通道算术 + **ID83 与 ID89 双标准** + twobit 读取器 + 金标准夹具，"2–3 周"是幻想（实际 6–8 周）。M3 的 DM 混合模型复现、M6 的 conformal 是**迷你研究项目**不是待办事项。M8"1 周"完成 vendor + r-universe + nf-core PR + CRAN 提交：CRAN vendored Rust 审稿本身就是数周墙钟迭代。10 个 vignettes 无任何里程碑认领。
- **修改**：双轨制——**v0.1（~6 周）**：SBS96/192/384/1536+DBS78 目录、KL-NMF+NNLS 两个内核、`ms_read_*/ms_tally/ms_extract` 单方法 + 完整 CI + 3 golden fixtures，发布 r-universe；**v0.2（~12 周）**：ID83、`ms_select_k`（稳定性+silhouette；SUITOR 可选）、`ms_fit`（nnls/likelihood/lrt）、bootstrap CI、refdb v1（人类 SBS/DBS/ID）、viz 6 图、extending vignette；**v1.0（~5–6 月）**：MSU-Fit 覆盖率校准、`ms_hrd_report`、pkgdown、NEWS 纪律。**推迟到 v1.x**：ID89、Infer/Tempo/Tensor、MsLda/MsSupervised、CN/SV 拟合、therapy_forensics、RNA 工作流。论文③"择 3–4 深做"变成硬性 Non-goal。

### 2.【P0】"逐位复刻 / bit 级对齐"把两类验收混为一谈，且与自家许可策略自相矛盾
- **(a) 通道语义**（标签/索引/枚举/平局规则）——离散语义，真可逐位 golden 验收，且必须；**(b) 浮点内核**（KL-MU/NNLS/LRT）——bit 级相等取决于运算顺序与 BLAS 行为，本质脆弱。更尖锐的内部矛盾：rust-NMF 的 bit 等价是**移植实现**（因此染上 GPL≥2）；D1 承诺"从论文公式干净重实现"——要 bit 等价就得复刻运算顺序，复刻到什么程度算衍生作品是灰色地带。**验收标准与许可策略正面对撞，档案里没人裁决。**
- **修改**：§7 显式二分：**"语义逐位"**（bit-compatible：通道算术/协议步骤/平局规则/默认参数）= 硬验收，整数与标签 golden vector；**"数值协议等价"**（protocol-equivalent：浮点内核）= 固定种子 + 容差（cosine > 1−1e-6、exposure L1 < tol）。R NMF brunet 对拍 = 固定平台一次性验证实验，不进 CI 门。删掉 ROADMAP 所有无限定语"逐位"，逐条标注类别。

### 3.【P0】确定性声明缺了 thread-count invariance——headline claim 会被并行化无声击穿
- 种子分叉解决随机数流，不解决**浮点归约顺序**；共识聚类/bootstrap 分位数/多初始化择优全涉及浮点累加比较。CI 检查 ≤2 线程 vs 用户 16 线程——确定性主张未经设计。
- **修改**：(a) 引擎契约测试加"seed 固定、RAYON_NUM_THREADS ∈ {1,2,N} 输出 identical"断言；(b) 并行只在互不归约的维度切分，跨 replicate 统计收集后单线程定序计算；(c) provenance 记录线程数但承诺结果与它无关。

## P1

### 4.【P1】refdb 双源（bundle + cache）没有 precedence、向前兼容与完整性模型
- precedence 未定义（默认用 bundle 还是 cache？）；降级场景 schema 兼容；更新源钉在会无版本号重构的 raw HEAD（SPMG 已实证），与同渠道 SHA256 比对是自证不是校验；体积审计是发布关键路径不是后台任务。
- **修改**：(a) 明文 precedence："分析永远 pin 在对象 provenance 记录的版本；默认 bundled 优先，cache 仅显式要求"；(b) 元数据加 `schema_version`，> 包支持则 stop；(c) 更新钉 commit SHA + 构建时烧录 manifest（r-polars lib-sums.tsv 模式），fail-closed；(d) 更新路径测试全部 fixture 化（CRAN 禁检查期联网）；(e) **v1 只捆绑人类 SBS/DBS/ID**，其余走 cache，对齐 5MB 指导线。

### 5.【P1】GRCh38"派生策略"在科学上未定型——relabel 还是推导，档案没想清楚
- 这些通道的**标签本身 build 无关**——若标签无关，"转换"什么？矩阵就是同一组数，那是 relabel 不是 derived；若认为 build 有影响，标签级转换根本造不出合法矩阵。
- **修改**：(a)+(b) 混合：声明"ID/CN/SV/RNA-SBS 通道语义与签名矩阵按 build 无关处理（`build_independent: true`），缺失 build 复用同一矩阵" + 查询时如实提示"该 build 无官方 XX 参考集"。

### 6.【P1】API 契约未定型且文档内部已打架；错误信息与生命周期策略完全缺席
- §1 说 `method = "nnls/qp/..."` 字符串，D5/§3.4 说引擎是 S7 对象——v1 头号 API 决策两个章节各说各话；`MsEngine.mode = class_character` 自己就是魔法字符串；`extract_signatures` 在签名提取包里是危险命名（与 hardhat 撞名）；错误信息策略（rlang class、i/j/c 三段式）、lifecycle 政策、FFI 导出冻结流程全部缺失。
- **修改**：(a) 定死：`ms_extract(catalog, method = ms_nmf(...))` 对象一等公民 + `method = "nmf"` 字符串糖（`match_ms_engine()` 报错时列出可用引擎）；(b) 自定义泛型一律 `ms_` 前缀（hardhat 命名只作文档概念对应）；(c) 新增 §3.5 "Error & lifecycle"：错误 class 规范（`msuiter_error_catalog`）、lint 禁裸 `stop()`、lifecycle::deprecate_warn、NEWS 即 changelog、`docs/ffi-surface.md` 作 per-release 评审工件。

### 7.【P1】CI 矩阵有硬缺口：声明的 R ≥ 4.3 地板不在测试矩阵里；FFI 内存安全零覆盖
- oldrel 也覆盖不到 4.3/4.4——地板 = 没测试的声明；extendr FFI + externalptr + memmap2 恰是最需要 valgrind/ASAN-UBSAN 的组合；GHA 共享 runner 噪声会让基准阈值告警每周误报（"≥50×"在 GHA 上不可验证）；有 cargo deny 没有 cargo audit/dependabot；覆盖率无目标值；golden fixture 无刷新工作流承载。
- **修改**：矩阵改 3 OS × {release, oldrel, **R-4.3（至少 Linux）**, devel（允许失败）}；新增 valgrind + sanitizers 两个 scheduled job；基准门降级为 sanity bound（<5s），加速比验收移入 `bench/` 钉硬件流程；dependabot 三件套；codecov 双语言（R ≥85%，Rust 报告不设门）；`data-raw/refresh_fixtures.R` + PR 模板强制 diff 审查项；rhub/win-builder/--as-cran 预提交纪律。

### 8.【P1】第三方引擎的治理与供应链模型未定义："统一质量门"对外部引擎不可强制
- 注册即代码执行——第三方 `.onLoad()` 注入任意 `fit_fn`，`ms_benchmark()` 拿用户数据调它；你们没有机制强制第三方通过契约测试（测试跑在你们 CI，第三方更新你们不知道）；registry 无 contract_version/engine_version/certified 字段；CONTRIBUTING/CoC/模板全缺。
- **修改**：(a) registry schema 加 `engine_version`/`contract_version`/`certified`（certified/self-reported/unknown）；(b) `ms_benchmark()` 对 non-certified 引擎输出 warning + 文档声明信任边界；(c) 月度反向依赖兼容矩阵 job；(d) M0 增补 CONTRIBUTING（含第三方引擎接入清单）、CoC、issue/PR 模板。

## P2

### 9.【P2】ARCHITECTURE 与 ROADMAP 已经漂移（`ms_therapy_forensics` 蒸发）；ADR 形态撑不住演进
- v2 两份文档刚写完已不同步。**修改**：修正矛盾或明确降 Non-goal；D1–D10 抽成 `docs/adr/NNNN-*.md`（status/superseded 字段）；研究文档头部加"archival snapshot"声明；加 docs-sync CI（从 ROADMAP 提取 `ms_*` 与 ARCHITECTURE/R 布局对照，drift 即红）。

### 10.【P2】"单包 + 未来可拆"：Rust 侧边界是真的，R 侧边界是愿望
- Rust 三 crate 编译器强制；R 侧 `R/utils.R` 六个月后成下水道。**修改**：CI 加 cargo workspace 依赖方向断言；R 侧架构测试（`R/<section>/` 只能调本区 + classes/ + FFI wrappers + 白名单）；每 section 三行 README 声明依赖方向；"拆包线"具体化为唯一候选切面（engine crate 发 crates.io；R 拆包仅为 CRAN 体积被拒时的应急预案）。

### 11.【P2】S7 对象模型隐藏成本：重量级嵌入、句柄重连 UX、0.3.x 迁移
- MsSignature 内嵌完整 MsCatalog（千样本队列 = N 份目录副本内存重复）+ waldo 比较噪声；句柄重连 UX 未设计（重跑什么？多久？何时触发？）；S7 0.2→0.3 迁移无监测。
- **修改**：catalog/reference 属性改为**快照摘要**（维度 + channels 注册表哈希 + refdb 版本号），完整对象显式传递；M0 验收加"saveRDS/load 后所有泛型行为有测试"；S7 主分支 nightly job。

### 12.【P2】工程卫生与发布工程缺失：NEWS/semver、README/pkgdown、sitrep、MSU-* ↔ 函数映射、性能锚定
- **修改**：M0 增补 README 骨架 + NEWS.md + `_pkgdown.yml`；`ms_sitrep()` 诊断函数（R 版本/Rust 工具链/rayon 线程/refdb 状态/2bit 缓存）；MSU-* ↔ 导出函数映射表进 pkgdown；M7 增补 CITATION + 性能锚定文档（钉硬件/数据集版本/竞品版本号）；M8 拆成 "M8a 材料周" + "M8b CRAN 迭代（墙钟 4–8 周滚动）"。

## 总体裁决与亮点
- **有条件通过**。三处 P0 都不花钱只花决策纪律：逐位验收与 clean-room 的对撞、并行化与确定性的冲突、无 v1 切线的 15–21 周童话。
- **三件做得好**：fact-check 审计文化（制度化后即护城河）；D9 对照/组件分离（同时回答贴牌质疑与可扩展性，整份档案最成熟的产品决策）；实测数字变工程铁律（staff 级判断力）。
