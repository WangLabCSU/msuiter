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
