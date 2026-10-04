# msuiter 0.0.0.9000

开发版（development version）；对应 docs/ROADMAP.md M0 里程碑「工程地基」。本包尚无 CRAN 发布；版本号遵循 R 开发版惯例（`x.y.z.9000`）。

## M0 工程地基

* rextendr 脚手架 + `src/rust/` Cargo workspace（root-package + members 形态）：依赖预算冻结版——`extendr-api`（default-features = false，仅 ndarray feature）、`ndarray`、`rayon`、`memmap2`、`twobit 0.2.2`（ADR 0001）；**无 rand**——随机性为自研 PCG64 + SplitMix64。
* M0 spike（ADR 0001/0002）：真实 cargo vendor 体积落数（vendor.tar.xz ≈ 1.41 MB 基线）、offline 构建证明、rustc 1.71（MSRV）构建证明与钉版纪律（`matrixmultiply = 0.3.9`、`rayon = 1.10.x`、`Cargo.lock` v3）。
* S7 类骨架（无 `.state`）：`MsVariants` / `MsCatalog` / `MsSignature` / `MsFit` / `MsRefDb` / `MsEngine` / `MsBenchmark`，validator 拒绝 NA/坏标签/坏维度；`saveRDS()`/`load()` 往返后泛型行为不变；对象互引用快照摘要。
* 通道注册表单一事实来源：`data-raw/build_channels.R` 生成 R 常量 + Rust 常量 + 构建期断言，与 SigProfiler 上游参考文件（`tools/channel-reference/`，含溯源）锚定；`tools/docs-sync.R` 做 API 面同步检查（drift 即红）。
* 自研 RNG 模块（`engine/rng.rs`）：PCG64（canonical post-step）+ SplitMix64 种子扩展 + 流布局 v1（`LAYOUT_ID` 域分离，per-replicate/rank/fold 计数器流）；跨版本 golden 冻结 + 独立 KAT（`tools/rng-kat.py`）。
* FFI 硬契约落地（`docs/ffi-surface.md` 冻结工件 + 漂移守卫测试）：无状态导出面（6 个 `msffi_*` 诊断探测器）覆盖列主序内存布局、NA/NaN 双层防线、`Result` → R condition 错误映射（class `msuiter_error_*`）、chunk 边界中断、per-call 线程池与线程数不变性。
* 引擎注册表 + 扩展契约：`register_ms_engine()` 九字段（含 `engine_version` / `contract_version` / `certified` 三态信任边界）；`match_ms_engine()` 字符串糖；`fit_engine()` / `required_pkgs()` 泛型；契约测试套件。
* `ms_variants()` / `ms_catalog()` / `ms_signature()` / `ms_fit()` / `ms_refdb()` / `ms_benchmark()` / `ms_engines()` / `ms_sitrep()` 构造与诊断入口；依赖方向守卫（`tools/check-dep-direction.sh`）与 vendor 基线检查（`tools/vendor.sh --check`）。

## M3b · MSU-Fit 校准统计（收口三件：U-M3b-04/05/06）

* **校准实验面（U-M3b-04，R/calibrate.R）**：`ms_calibration_grid()` 经 `ms_calibration_grid_rust` 核面装配 M3b 蒙特卡洛校准网格——逐 (N × share) cell 的 mean_coverage / se / n_reps / pass_window 与 estimand-③ 复合清零混淆 tally；`ms_calibration_verdict()` 为核侧判据窗 verdict 的纯 R 孪生（含端点窗、1-based failing_cells，测试钉位逐位相等）。R 面契约：n_grid 正整数严格递增、share∈[0,1]、arm 三形合法名、window 两点 [0,1] 有序；全部 msuiter_error_* 错误协议；seed 确定性 + threads∈{1,N} identical 贯通 R 面。
* **曲线判据可视化（U-M3b-05，R/calibrate-plot.R）**：`plot_calibration_curve()` 覆盖率 vs N（log x、按 share 分面、判据窗阴影、逐 cell 二项误差棒、窗外格红叉标记）；ggplot2 为 Suggests 依赖（调用时惰性加载，缺席为结构化 msuiter_error_package）。
* **真实数据 sanity harness（U-M3b-06，R/calibrate-real.R + inst/sanity/README.md）**：`ms_calibration_sanity()` 按设计备忘 §4 协议执行——生产面全量拟合为声明 pseudo-truth → 降采样稀释（Multinomial(N, counts/total)，K ∈ {100, 1000, 10000} 轴）→ S(N) 曲线（share ≥ 0.05 内点）→ 验收 = 与合成主臂曲线差 ±0.05（或 [0.90,1.00] 地板取宽者）且无系统性单调反转。数据获取/治理（PCAWG WGS 主 + TCGA GDC open WXS 副、WES/panel 轴推迟 M4）协议化入 inst/sanity/README.md；harness 不下载不内置真实数据。
