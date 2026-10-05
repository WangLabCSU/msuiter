# msuiter 0.1.0.9000（开发版）

自 v0.1.0 起的新开发周期。

# msuiter 0.1.0（2026-10-05）

首个发布版：Rust 计算核 + R/S7 接口的最小可用核（ROADMAP v0.1 门 = M0 + M1s；M1c/M2/M3a/M4 校准与相似度层提前并入本树，随版交付）。以下各节为开发期批次记录（升级自 0.0.0.9000 开发线）。


## M0 工程地基

* rextendr 脚手架 + `src/rust/` Cargo workspace（root-package + members 形态）：依赖预算冻结版——`extendr-api`（default-features = false，仅 ndarray feature）、`ndarray`、`rayon`、`memmap2`、`twobit 0.2.2`（ADR 0001）；**无 rand**——随机性为自研 PCG64 + SplitMix64。
* M0 spike（ADR 0001/0002）：真实 cargo vendor 体积落数（vendor.tar.xz ≈ 1.41 MB 基线）、offline 构建证明、rustc 1.71（MSRV）构建证明与钉版纪律（`matrixmultiply = 0.3.9`、`rayon = 1.10.x`、`Cargo.lock` v3）。
* S7 类骨架（无 `.state`）：`MsVariants` / `MsCatalog` / `MsSignature` / `MsFit` / `MsRefDb` / `MsEngine` / `MsBenchmark`，validator 拒绝 NA/坏标签/坏维度；`saveRDS()`/`load()` 往返后泛型行为不变；对象互引用快照摘要。
* 通道注册表单一事实来源：`data-raw/build_channels.R` 生成 R 常量 + Rust 常量 + 构建期断言，与 SigProfiler 上游参考文件（`tools/channel-reference/`，含溯源）锚定；`tools/docs-sync.R` 做 API 面同步检查（drift 即红）。
* 自研 RNG 模块（`engine/rng.rs`）：PCG64（canonical post-step）+ SplitMix64 种子扩展 + 流布局 v1（`LAYOUT_ID` 域分离，per-replicate/rank/fold 计数器流）；跨版本 golden 冻结 + 独立 KAT（`tools/rng-kat.py`）。
* FFI 硬契约落地（`docs/ffi-surface.md` 冻结工件 + 漂移守卫测试）：无状态导出面（6 个 `msffi_*` 诊断探测器）覆盖列主序内存布局、NA/NaN 双层防线、`Result` → R condition 错误映射（class `msuiter_error_*`）、chunk 边界中断、per-call 线程池与线程数不变性。
* 引擎注册表 + 扩展契约：`register_ms_engine()` 九字段（含 `engine_version` / `contract_version` / `certified` 三态信任边界）；`match_ms_engine()` 字符串糖；`fit_engine()` / `required_pkgs()` 泛型；契约测试套件。
* `ms_variants()` / `ms_catalog()` / `ms_signature()` / `ms_fit()` / `ms_refdb()` / `ms_benchmark()` / `ms_engines()` / `ms_sitrep()` 构造与诊断入口；依赖方向守卫（`tools/check-dep-direction.sh`）与 vendor 基线检查（`tools/vendor.sh --check`）。

## M4 · 校准相似度库（U-M4-01）

* **ms_compare() 校准相似度库（R/ms-compare.R + R/classes-compare.R + `ms_compare_null_rust` 核面）**：四度量（cosine/correlation/JSD(sqrt, bits)/Hellinger，share 列归一、零列 NaN）+ 双零分布族（签名零分布 = 均匀 Dirichlet 对，engine 新原语 `dirichlet_uniform`；目录零分布 = 真值在负荷 N 的多项/NB 重构——cosine 的"按通道数×负荷"零校准；type-7 经验分位与 R quantile(type=7) 同序统计量逐位、冻结 MC-SE 容差 0.01 在 R 面强制为 `msuiter_error_calibration`）+ 三匹配协议（Hungarian 一对一主指标 = `match_solutions` 零改动装配；Islam 贪心逐位；Jiang 活性>0 + scaled Manhattan + Combined Score + specificity，冻结 k_est=k_ref 真值字典拟合口径，重构旗引用 bbaf042 的 0.969 线）。解析锚（E⟨x,y⟩=1/m、E‖x‖²=2/(m+1)、delta 均值 (m+1)/(2m)）与 burden 单调性进测试层。`MsComparison` S7 容器 + print/format。设计备忘 docs/devlog/2026-10-04-M4-01-design-memo.md；entropy-matched Dirichlet 零分布记为升级臂。

## M4 · 数据工具首批（U-M4-02 子批）

* **ms_downsample()（R/ms-downsample.R）**：公共深度下采样——语义锚定 M3b sanity harness 同款多项律（`Multinomial(depth, counts_j/total_j)`，base R rmultinom 固定种子按样本列序，逐位可复现）；`depth = "min"` 取活样本最小总量；浅样本原样保留、死样本保持零列；provenance 追加 downsample 记录。有放回近似的诚实声明 + 多元超几何升级臂入设计备忘。
* **COSMIC txt 互操作首批（R/io-catalog.R）**：`ms_export()` / `ms_import(format = "cosmic")`——布局锚 = 捆绑 COSMIC v3.6 上游文件（`Type` 首列 + 规范通道序）；两侧都强制标签 == 注册表规范序（无静默重排/子集）；通道表按行数+标签集唯一推断或显式 pin；目录侧整数控入校验。SigProfiler txt / WTSI 长格式与 signatures 导入面**推迟**（夜间窗口未取得上游 [V] 样例；MsSignature 校验器无法容纳 0 列暴露——均记录于设计备忘 §0/§2）。

## M4 · QC 报告初版 + SigProfiler 互操作（U-M4-02/02b 日间批）

* **SigProfiler txt 解禁实装（[V] 三重上游锚，设计备忘 §4）**：真实样例（SigProfilerAssignment de-novo SBS96 输出，sha256 固定进 tests fixtures）行序==注册表（R identical 实证）；ICAMS 转换器源码核实（MutationType 表头 + 括号标签）；SigProfilerPlotting reference formats 384/96/78 逐位一致。`ms_export/ms_import` format∈{cosmic, sigprofiler}；**signatures 导入面解禁**——MsSignature validator 修订放行 k×0 合法空暴露面（0 列矩阵 colnames 恒 NULL 的 base R 事实显式豁免，标签协议不变）。
* **ms_qc_report() 初版（R/ms-qc-report.R，设计备忘 2026-10-04-M4-02b-qc-memo.md）**：逐样本负荷分布（total/log10/burden_class）+ 机制级伪迹哨兵（gt_share = C>A 通道份额——注册表嘧啶归一化下 oxoG 的 G>T 视图；ct_share = C>T——FFPE 脱胺）+ 给定拟合时的 COSMIC 伪迹签名暴露份额（名册 19 条：SBS27/43/45–60/95，COSMIC SBS 索引页 2026-10-04 实时核实、测试字面钉死；签名名按数值词干匹配）。qc_flag 初版常数（artifact ≥0.05 伪迹份额 或 gt ≥0.30；watch = ct ≥0.40 或 low 负荷）——**我方声明 divergence，Degasperi amber/red 忠实复刻 ⏳v1.x**（逐位阈值未公开，[V] 纪律不声称）。
* **WTSI 长格式维持推迟**：两窗口均未取得上游实样文件（ICAMS 无 WTSI 面、PCAWG WTSI 矩阵在 portal 会话后、本地 Nik-lab 矩阵为 COSMIC 方言）——不可验证即不交付。

* **ms_convert() 机会转换（U-M4-02c，R/ms-convert.R + 设计备忘 2026-10-04-M4-02c-convert-memo.md）**：sigfit convert_signatures 语义（sig/opp_from·opp_to 逐列重归一）——human-genome/human-exome 内置表（COSMIC v2/v3 频数，经 sigminer 源码 [V]，data-raw+inst/extdata 双处固定、标签序为注册表序）+ 自定义机会向量（panel 口）；MsSignature 方法签名转换/暴露原样；genome→genome 恒等、与 sigminer sig_convert 双侧一致 ≤1e-12、往返可逆 1e-8、零列不产 NaN。"似然内机会"（sigfit per-sample 语义）记 ⏳v1.x。

* **viz 首批 8 图型（U-M4-03，R/viz-*.R + 设计备忘 2026-10-04-M4-03-viz-memo.md）**：plot_catalog_profile / plot_signature_catalog / plot_reference_comparison / plot_reconstruction_panel / plot_exposure_stacked / plot_exposure_heatmap / plot_similarity_heatmap / plot_cosmic_scatter——COSMIC 6 类调色板逐字节取自已核实的 sigProfilerPlotting.py 源码（L2895–2902；research/04 旧笔记色序笔误已修正记录）、规范序强制（复用注册表校验，viz 不静默重排）、ggplot2 4.0 兼容（scale_fill_identity；I() in aes 已移除）、矢量一等（返回 ggplot 对象）；DBS78/ID83 简化单色（palette 冻结 M7）。exposure UMAP 与全集图型 ⏳ 后批。

* **ms_embed() + plot_embedding()（U-M4-03 余项，R/ms-embed.R）**：样本暴露空间嵌入——UMAP（uwot，Suggests）或确定性 kmeans（stats 恒可用）；share 变换默认（单纯形几何）；seed 一等参数（同版本逐位、跨版本诚实声明不保证）；kmeans 组恢复在 3 组人工 fixture 上钉测；plot_embedding 按 cluster 着色。差异挖掘面 ⏳ 后批。

* **bench/jiang 对标（v0.2 验收门证据，4b3c8b4）**：Jiang 2025 拟合协议（bbaf042）——8 条 COSMIC v3.6 参考签名（含 v3.6 拆分名 17a/40a）× 3 活跃/5 decoy × 负荷 {300–10000} × multinomial/NB(κ=8) 双臂 × 30 replicate；参考约束 NNLS refit 双面（真 raw zero_threshold=0 + 管线 1% 清理——审计式发现：默认清理使 raw 口径成空操作）；ms_compare(protocol='jiang') 直读。multinomial 臂过门（CS min 2.72 / 汇总 spec 0.864）；nb8 臂 CS 过（2.41）spec 未过（0.743）——归因与 PI 选项入 result.md。

* **ms_simulate() 第一版（M7 前置，R/ms-simulate.R + 设计备忘 2026-10-05-simulate-memo.md）**：字典+暴露 → 合成目录——multinomial（恰 N，M3b sanity 同律）/poisson/nb（gamma-Poisson，Var=μ+μ²/κ）三臂；份额/计数暴露自动判定；SBS96/DBS78 双空间；seed 逐位。NB 每通道方差律与 Poisson 单位色散进测试（400 replicate 中位数锚）。基因组真实放置（VCF 级）⏳ M7 全集。

* **plot_k_cv_curve() + plot_k_stability()（K 选择证据可视化，L-F ✅ M2/M4 行收口）**：ms_select_k() 的 memo-3 证据表直读——CV 误差曲线（argmin 高亮 + selected 套环 + veto 红蓝着色）与共识稳定性双线（avg/min + 上游 veto 阈值参考线 0.80/0.20）；schema 守卫结构化；真实 ms_select_k 小网格往返渲染。

* **bootstrap CI/stability 图（L-F ✅ M3b/M4 行收口，R/viz-bootstrap.R）**：plot_boot_ci（逐签名误差条 + 合同标题 95% CI/boots）+ plot_boot_stability（稳定性柱 + 0.95 地板线——M3b 复合清零规则的 stability 条款）；plot_boot_distribution 为诚实拒绝面（draws 不落 MsFit——M7 升级臂记录）；点拟合守卫。

* **散点图零分布 p 注记（L-F 收口，R/ms-compare.R + viz）**：plot_cosmic_scatter(null_p = TRUE) 注记经验签名零分布尾概率——uniform-Dirichlet 族 R 孪生采样器（审计已独立对拍 Rust 核同律）+ add-one 规则（永不返 0，5000 draws 默认）；cos=1 钉在下限 1/(n+1)；跨对比 FDR q ⏳ 待多对比表视图。

* **ms_compare 逐对比 p_null/q_bh 矩阵（L-F q 注记全收口）**：每 (est, ref) 对的经验签名零分布尾概率（add-one MC，per-pair seed 偏移）+ 全格 BH 校正（p.adjust 逐位一致钉测）；q≥p 方向、对角加一下限、无关对大 p 全数字断言。散点图注记与表视图共用同一零分布族。

* **ms_exposure_test() 差异挖掘面（L-F 收口，R/ms-embed.R）**：双组逐签名 Wilcoxon 秩和（musicatk 工作流语义）+ 全签名族 BH（与 ms_test_presence 同 p.adjust 口径）；all-tied 签名 NA 面（不伪造 p）；>2 组拒绝（成对拆分是调用方设计决策）；中位数双组对照列。

* **形状条件化零分布升级臂（U-M7-pre，R/ms-compare.R + compare.rs + `ms_compare_shape_null_rust`）**：memo "熵匹配 Dirichlet(α·u)" 的具体化——draws = Multinomial(N,u)/N、统计量 cos(draw,u)，熵语义经形状 u 与噪声尺度 α_total=N 自然进入（无需二分）；散点图 `null_family = "shape_conditional"` 直读；与 catalog 面不同律经方向断言 + χ²/N 缩律（sd 比 ≈ 10 非 1/√N——首稿高斯假设被实测纠正）锚定。

* **ms_cluster_signatures() 签名聚类（L-F 🔶→✅，R/ms-cluster.R）**：阈值图连通分量（cosine ≥ threshold 同簇，确定性 union-find 无 RNG 无重启）；标签按簇降序+首现序稳定；medoid = 簇内平均余弦最高成员；cosine 矩阵随属性返回。与 M2 consensus 原语语义分立（那是 replicate-块结构），设计注记入文件头。阈值默认 0.90（Islam TP 线）。

* **ms_run_benchmark() 网格驱动器第一版（M7 本体开工，R/ms-benchmark-driver.R，D1 阶段 1 + D2 PROVISIONAL）**：ms_benchmark_grid() 场景构造器（校准层 ms_simulate 直驱：TMB/样本数/活跃签名数/生成臂，字典 = 捆绑 COSMIC v3.6 seeded 抽取）；驱动循环 = 场景×certified 引擎（nmf/ard/sparse 默认）全笛卡尔，单 cell tryCatch 隔离（失败仅记 cell_error=1 行——容器 NA 契约保持）；评分 = Hungarian P/R/F1 @0.90 + D2 配对 L1（absolute/compositional，tau 无关指派经 1e-9 阈值导出）+ runtime。seed 逐位确定性（runtime 除外）；命名注记：M0 构造器保留 ms_benchmark()，驱动器 = ms_run_benchmark()（合并为泛型 = M7 polish 决策）。

## M3b · MSU-Fit 校准统计（收口三件：U-M3b-04/05/06）

* **校准实验面（U-M3b-04，R/calibrate.R）**：`ms_calibration_grid()` 经 `ms_calibration_grid_rust` 核面装配 M3b 蒙特卡洛校准网格——逐 (N × share) cell 的 mean_coverage / se / n_reps / pass_window 与 estimand-③ 复合清零混淆 tally；`ms_calibration_verdict()` 为核侧判据窗 verdict 的纯 R 孪生（含端点窗、1-based failing_cells，测试钉位逐位相等）。R 面契约：n_grid 正整数严格递增、share∈[0,1]、arm 三形合法名、window 两点 [0,1] 有序；全部 msuiter_error_* 错误协议；seed 确定性 + threads∈{1,N} identical 贯通 R 面。
* **曲线判据可视化（U-M3b-05，R/calibrate-plot.R）**：`plot_calibration_curve()` 覆盖率 vs N（log x、按 share 分面、判据窗阴影、逐 cell 二项误差棒、窗外格红叉标记）；ggplot2 为 Suggests 依赖（调用时惰性加载，缺席为结构化 msuiter_error_package）。
* **真实数据 sanity harness（U-M3b-06，R/calibrate-real.R + inst/sanity/README.md）**：`ms_calibration_sanity()` 按设计备忘 §4 协议执行——生产面全量拟合为声明 pseudo-truth → 降采样稀释（Multinomial(N, counts/total)，K ∈ {100, 1000, 10000} 轴）→ S(N) 曲线（share ≥ 0.05 内点）→ 验收 = 与合成主臂曲线差 ±0.05（或 [0.90,1.00] 地板取宽者）且无系统性单调反转。数据获取/治理（PCAWG WGS 主 + TCGA GDC open WXS 副、WES/panel 轴推迟 M4）协议化入 inst/sanity/README.md；harness 不下载不内置真实数据。
